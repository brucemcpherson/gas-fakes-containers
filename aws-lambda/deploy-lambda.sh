#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
AWS_REGION="eu-west-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_NAME="gas-fakes-lambda"
REPO_NAME="gas-fakes-repo"
IMAGE_TAG="latest"

# Ensure local .env exists
if [ ! -f ".env" ]; then
    echo "Error: .env not found in current directory."
    exit 1
fi

# GCP CONFIG
GCP_PROJECT_ID=$(gcloud config get-value project)
GCP_REGION="europe-west1"
GCP_REPO_NAME="gas-fakes-repo" 
IMAGE_PATH="$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME/$LAMBDA_NAME"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:${IMAGE_TAG}"

# GCP WIF Config
GCP_POOL_ID="aws-pool"
GCP_PROVIDER_ID="aws-provider"

# Auto-detect GSA from local .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" .env | cut -d'=' -f2 | tr -d '"\r')
GSA_EMAIL="${GSA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')

echo "--- Using GCP Project: $GCP_PROJECT_ID ---"
echo "--- Using GSA: $GSA_EMAIL ---"

# --- 2. GENERATE HIDDEN GCP CREDENTIALS CONFIG ---
echo "--- Generating Temporary Credentials ---"
gcloud iam workload-identity-pools create-cred-config \
    "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/providers/$GCP_PROVIDER_ID" \
    --service-account="$GSA_EMAIL" \
    --output-file=".google-credentials.json" \
    --aws >/dev/null

# --- 3. BUILD & PUSH TO AWS ECR VIA CLOUD BUILD ---
echo "--- Building and Pushing to ECR (via Cloud Build) ---"
gcloud builds submit . \
    --config=cloudbuild-aws.yaml \
    --substitutions=_IMAGE_PATH="$IMAGE_PATH",_AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID",_AWS_REPO_NAME="$REPO_NAME"

# REMOVE temporary hidden file immediately
rm .google-credentials.json

# --- 4. CONFIGURE GOOGLE WORKLOAD IDENTITY FEDERATION ---
echo "--- Configuring GCP Workload Identity Federation ---"
gcloud iam workload-identity-pools describe "$GCP_POOL_ID" --location="global" --quiet >/dev/null 2>&1 || \
    gcloud iam workload-identity-pools create "$GCP_POOL_ID" \
        --location="global" \
        --display-name="AWS Lambda Pool" \
        --quiet >/dev/null

if gcloud iam workload-identity-pools providers describe "$GCP_PROVIDER_ID" --workload-identity-pool="$GCP_POOL_ID" --location="global" --quiet >/dev/null 2>&1; then
    echo "Updating Workload Identity Provider mapping..."
    gcloud iam workload-identity-pools providers update-aws "$GCP_PROVIDER_ID" \
        --workload-identity-pool="$GCP_POOL_ID" \
        --location="global" \
        --attribute-mapping="google.subject=assertion.arn,attribute.aws_account=assertion.account" \
        --quiet >/dev/null
else
    echo "Creating Workload Identity Provider..."
    gcloud iam workload-identity-pools providers create-aws "$GCP_PROVIDER_ID" \
        --workload-identity-pool="$GCP_POOL_ID" \
        --location="global" \
        --account-id="$AWS_ACCOUNT_ID" \
        --attribute-mapping="google.subject=assertion.arn,attribute.aws_account=assertion.account" \
        --quiet >/dev/null
fi

MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/attribute.aws_account/$AWS_ACCOUNT_ID"
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" --role="roles/iam.workloadIdentityUser" --member="$MEMBER" --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" --role="roles/iam.serviceAccountTokenCreator" --member="$MEMBER" --quiet >/dev/null

# --- 5. DEPLOY TO LAMBDA ---
echo "--- Deploying to Lambda ---"
if ! aws iam get-role --role-name "${LAMBDA_NAME}-role" >/dev/null 2>&1; then
    echo "Creating Lambda Role..."
    aws iam create-role --role-name "${LAMBDA_NAME}-role" \
        --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >/dev/null
    sleep 5
fi
aws iam attach-role-policy --role-name "${LAMBDA_NAME}-role" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" >/dev/null

if ! aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
    echo "Creating Lambda Function..."
    aws lambda create-function --function-name "$LAMBDA_NAME" \
        --package-type Image \
        --code ImageUri="$IMAGE_URI" \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_NAME}-role" \
        --region "$AWS_REGION" \
        --timeout 900 \
        --memory-size 2048 >/dev/null
else
    aws lambda wait function-updated --function-name "$LAMBDA_NAME" --region "$AWS_REGION"
    aws lambda update-function-code --function-name "$LAMBDA_NAME" --image-uri "$IMAGE_URI" --region "$AWS_REGION" >/dev/null
fi

# --- 6. CONFIGURE LAMBDA ENVIRONMENT VARIABLES ---
echo "--- Configuring Lambda Environment Variables ---"
aws lambda wait function-updated --function-name "$LAMBDA_NAME" --region "$AWS_REGION"

GOOGLE_WORKSPACE_SUBJECT=$(gcloud config get-value account)
JSON_VARS=$(awk -F'=' '/^[^#]/ {
    key=$1;
    val=substr($0, index($0,"=")+1);
    gsub(/^"/, "", val); gsub(/"$/, "", val);
    gsub(/"/, "\\\"", val);
    printf "\"%s\":\"%s\",", key, val
}' .env)

ENV_JSON="{\"Variables\":{\"GOOGLE_APPLICATION_CREDENTIALS\":\"/usr/src/app/google-credentials.json\",\"GCP_PROJECT_ID\":\"$GCP_PROJECT_ID\",\"GOOGLE_WORKSPACE_SUBJECT\":\"$GOOGLE_WORKSPACE_SUBJECT\",$JSON_VARS}}"
ENV_JSON=$(echo $ENV_JSON | sed 's/,}/}/')

aws lambda update-function-configuration --function-name "$LAMBDA_NAME" \
    --region "$AWS_REGION" \
    --timeout 900 \
    --memory-size 2048 \
    --environment "$ENV_JSON" >/dev/null

aws lambda put-function-event-invoke-config --function-name "$LAMBDA_NAME" --region "$AWS_REGION" --maximum-retry-attempts 0 >/dev/null

# --- 7. INVOKE AND MONITOR ---
echo "--- Waiting for readiness ---"
aws lambda wait function-updated --function-name "$LAMBDA_NAME" --region "$AWS_REGION"

echo "--- Invoking Lambda Function (Asynchronously) ---"
aws lambda invoke --function-name "$LAMBDA_NAME" \
    --region "$AWS_REGION" \
    --invocation-type Event \
    response.json >/dev/null

echo "--- Tailing Logs (Ctrl+C to stop) ---"
aws logs tail "/aws/lambda/$LAMBDA_NAME" --follow --region "$AWS_REGION"
