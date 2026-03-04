#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
REGION="eu-gb"
RESOURCE_GROUP="Default"
ICR_NAMESPACE="gas-fakes-ns"
ICR_DOMAIN="uk.icr.io"
CE_PROJECT="gas-fakes-project"
CE_JOB_NAME="gas-fakes-job"
REPO_NAME="gas-fakes-repo"

# Ensure local .env exists
if [ ! -f ".env" ]; then
    echo "Error: .env not found in current directory."
    exit 1
fi

# GCP CONFIG
GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project)
GCP_REGION="europe-west1"
IMAGE_PATH="$GCP_REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$CE_JOB_NAME"

# GCP WIF Config
GCP_POOL_ID="ibm-pool"
GCP_PROVIDER_ID="ibm-provider"

# Auto-detect GSA from local .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" .env | cut -d'=' -f2 | tr -d '"
')
GSA_EMAIL="${GSA_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$GOOGLE_CLOUD_PROJECT" --format='value(projectNumber)')

echo "--- Using GCP Project: $GOOGLE_CLOUD_PROJECT ---"
echo "--- Using GSA: $GSA_EMAIL ---"

# --- 2. TARGET RESOURCE GROUP ---
echo "--- Targeting Default Resource Group ---"
ibmcloud target -g "$RESOURCE_GROUP" || {
    echo "Error: Could not target '$RESOURCE_GROUP' resource group."
    exit 1
}

# --- CLEANUP PREVIOUS ATTEMPTS ---
echo "--- Cleaning up previous deployment resources (if any) ---"
ibmcloud ce job delete --name "$CE_JOB_NAME" --hard --force >/dev/null 2>&1 || true
# We keep the project and registry secret as they are stable
# but we'll recreate the App ID key to be sure
ibmcloud resource service-key-delete "gas-fakes-key" --force >/dev/null 2>&1 || true

# --- 2. GENERATE HIDDEN GCP CREDENTIALS CONFIG ---
echo "--- Generating Temporary Credentials ---"
gcloud iam workload-identity-pools create-cred-config \
    "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/providers/$GCP_PROVIDER_ID" \
    --service-account="$GSA_EMAIL" \
    --output-file=".google-credentials.json" \
    --credential-source-file="/tmp/ibm-token.json" \
    --credential-source-type="json" \
    --credential-source-field-name="access_token"

# --- 3. PRE-CREATE IBM RESOURCES ---
echo "--- Ensuring IBM Container Registry Namespace exists ---"
ibmcloud cr namespace-add "$ICR_NAMESPACE" || true

echo "--- Cleaning up old images and job runs ---"
# Delete all images in the repository to make room for the new build
ibmcloud cr image-rm "$ICR_DOMAIN/$ICR_NAMESPACE/$REPO_NAME" >/dev/null 2>&1 || true
# Also clean up untagged images (dangling)
ibmcloud cr image-prune --force >/dev/null 2>&1 || true
# Delete all previous job runs to clear run history/logs
ibmcloud ce project select --name "$CE_PROJECT" 2>/dev/null || true
for run in $(ibmcloud ce jobrun list --job "$CE_JOB_NAME" --output json 2>/dev/null | jq -r '.[]? | objects | .name? // empty'); do
    ibmcloud ce jobrun delete --name "$run" --force 2>/dev/null || true
done

echo "--- Ensuring IBM App ID instance exists for OIDC ---"
APP_ID_NAME="gas-fakes-appid"
if ! ibmcloud resource service-instance "$APP_ID_NAME" --output json >/dev/null 2>&1; then
    echo "Creating App ID instance..."
    ibmcloud resource service-instance-create "$APP_ID_NAME" "appid" "graduated-tier" "$REGION" -g "$RESOURCE_GROUP"
fi

APP_ID_JSON=$(ibmcloud resource service-instance "$APP_ID_NAME" --output json)
TENANT_ID=$(echo "$APP_ID_JSON" | jq -r 'if type=="array" then .[0].guid else .guid end')

# Create a service key if not exists to get credentials
if ! ibmcloud resource service-key "gas-fakes-key" --output json >/dev/null 2>&1; then
    ibmcloud resource service-key-create "gas-fakes-key" "Writer" --instance-name "$APP_ID_NAME" >/dev/null
fi
KEY_INFO=$(ibmcloud resource service-key "gas-fakes-key" --output json)
APP_ID_CLIENT_ID=$(echo "$KEY_INFO" | jq -r 'if type=="array" then .[0].credentials.clientId else .credentials.clientId end')
APP_ID_SECRET=$(echo "$KEY_INFO" | jq -r 'if type=="array" then .[0].credentials.secret else .credentials.secret end')
APP_ID_OAUTH_URL=$(echo "$KEY_INFO" | jq -r 'if type=="array" then .[0].credentials.oauthServerUrl else .credentials.oauthServerUrl end')

# --- 4. BUILD & PUSH TO IBM ICR VIA CLOUD BUILD ---
echo "--- Building and Pushing to ICR (via Cloud Build) ---"
gcloud builds submit . \
    --config=cloudbuild-ibm.yaml \
    --substitutions=_IMAGE_PATH="$IMAGE_PATH",_ICR_DOMAIN="$ICR_DOMAIN",_ICR_NAMESPACE="$ICR_NAMESPACE",_REPO_NAME="$REPO_NAME"

rm .google-credentials.json

# --- 5. CONFIGURE GOOGLE WORKLOAD IDENTITY FEDERATION ---
echo "--- Configuring GCP Workload Identity Federation ---"
gcloud iam workload-identity-pools describe "$GCP_POOL_ID" --location="global" --quiet >/dev/null 2>&1 || \
    gcloud iam workload-identity-pools create "$GCP_POOL_ID" \
        --location="global" \
        --display-name="IBM Cloud Pool" \
        --quiet >/dev/null

# App ID OIDC issuer and audience
# App ID issues id_tokens with aud=clientId, solving the IBM IAM `aud` problem
ISSUER_URI="$APP_ID_OAUTH_URL"
# The audience of App ID tokens is the client ID itself
AUDIENCE="$APP_ID_CLIENT_ID"

echo "Applying configuration to Workload Identity Provider (App ID)..."
gcloud iam workload-identity-pools providers undelete "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" --quiet >/dev/null 2>&1 || true

gcloud iam workload-identity-pools providers create-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.sub=assertion.sub" \
    --quiet >/dev/null 2>&1 || true

gcloud iam workload-identity-pools providers update-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.sub=assertion.sub" \
    --quiet >/dev/null

MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/*"
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER" --quiet >/dev/null

# --- 6. DEPLOY TO IBM CODE ENGINE ---
echo "--- Deploying to IBM Code Engine ---"

# Target project
ibmcloud ce project create --name "$CE_PROJECT" || ibmcloud ce project select --name "$CE_PROJECT"

# Create Registry Secret so Code Engine can pull the image
IBM_API_KEY=$(gcloud secrets versions access latest --secret="IBM_CLOUD_API_KEY")
ibmcloud ce registry create --name icr-secret --server "$ICR_DOMAIN" --username iamapikey --password "$IBM_API_KEY" >/dev/null 2>&1 || true

# Prepare Environment Variables
GOOGLE_WORKSPACE_SUBJECT=$(gcloud config get-value account)
# Initialize ENV_ARGS array with standard variables and App ID credentials
ENV_ARGS=("--env" "GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" "--env" "GOOGLE_CLOUD_PROJECT_NUMBER=$PROJECT_NUMBER" "--env" "GOOGLE_WORKSPACE_SUBJECT=$GOOGLE_WORKSPACE_SUBJECT" "--env" "GOOGLE_APPLICATION_CREDENTIALS=/usr/src/app/google-credentials.json" "--env" "IBM_CLOUD_API_KEY=$IBM_API_KEY" "--env" "IBM_APP_ID_CLIENT_ID=$APP_ID_CLIENT_ID" "--env" "IBM_APP_ID_SECRET=$APP_ID_SECRET" "--env" "IBM_APP_ID_OAUTH_URL=$APP_ID_OAUTH_URL")

# Load other variables from .env
while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] || [[ "$key" == "GOOGLE_CLOUD_PROJECT" ]] && continue
    val=$(echo $val | sed 's/^"//;s/"$//')
    ENV_ARGS+=("--env" "$key=$val")
done < .env

# Create or Update Job
IMAGE_URI="$ICR_DOMAIN/$ICR_NAMESPACE/$REPO_NAME:latest"

if ibmcloud ce job get --name "$CE_JOB_NAME" >/dev/null 2>&1; then
    echo "Updating existing Job..."
    ibmcloud ce job update --name "$CE_JOB_NAME" --image "$IMAGE_URI" "${ENV_ARGS[@]}"
else
    echo "Creating new Job..."
    ibmcloud ce job create --name "$CE_JOB_NAME" --image "$IMAGE_URI" "${ENV_ARGS[@]}" --registry-secret icr-secret
fi

# --- 7. EXECUTE AND MONITOR ---
echo "--- Starting Execution ---"
JOB_RUN_NAME=$(ibmcloud ce jobrun submit --job "$CE_JOB_NAME" --output json | jq -r .metadata.name)

echo "--- JobRun Started: $JOB_RUN_NAME ---"
echo "--- Tailing Logs ---"
ibmcloud ce jobrun logs --name "$JOB_RUN_NAME" --follow
