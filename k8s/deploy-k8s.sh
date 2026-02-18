#!/bin/bash
set -e

# 1. Prepare Environment
ENV_PATH=".env"
if [ -f "$ENV_PATH" ]; then
    echo "--- Loading variables from local $ENV_PATH ---"
    export $(grep -v '^#' "$ENV_PATH" | xargs)
    # Define script-specific overrides
    export GOOGLE_WORKSPACE_SUBJECT=$(gcloud config get-value account)
else
    echo "Error: .env not found" && exit 1
fi

# 2. Configuration
REGION="europe-west1"
JOB_NAME="gas-fakes-job"
REPO_NAME="gas-fakes-repo"
IMAGE_PATH="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$JOB_NAME"
GSA_EMAIL="${GOOGLE_SERVICE_ACCOUNT_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
KSA_NAME="gas-fakes-ksa"
NAMESPACE="default"

# 3. Build Image
echo "--- Building Docker Image ---"
# Ensure the Artifact Registry repository exists
gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for gas-fakes"

gcloud builds submit . --config=cloudbuild.yaml --substitutions=_IMAGE_PATH="$IMAGE_PATH"

# 4. Set up Workload Identity
echo "--- Configuring Workload Identity ---"
# Create IAM binding if it doesn't exist
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${GOOGLE_CLOUD_PROJECT}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --quiet

# 5. Generate Kubernetes Manifest
echo "--- Generating Kubernetes Manifest ---"
# Convert .env to Kubernetes env vars format
# Assuming .env values might already be quoted, we handle both cases.
# We also ensure the block is correctly indented.
K8S_ENV_VARS=$(awk -F'=' '/^[^#]/ { 
    val = substr($0, index($0,"=")+1);
    # Remove surrounding quotes if they exist to avoid double quoting
    gsub(/^"/, "", val); gsub(/"$/, "", val);
    printf "        - name: %s\n          value: \"%s\"\n", $1, val 
}' "$ENV_PATH")

# Add the override explicitly
K8S_ENV_VARS+=$'
'"        - name: GOOGLE_WORKSPACE_SUBJECT"$'
'"          value: "$GOOGLE_WORKSPACE_SUBJECT""

# Use envsubst or similar to replace variables in template
# We'll use a simple sed for the image path since envsubst might not be installed
export K8S_ENV_VARS IMAGE_PATH GOOGLE_SERVICE_ACCOUNT_NAME GOOGLE_CLOUD_PROJECT
# We'll use a python script or just more awk/sed to do a reliable replace if needed
# but let's try a simple sed approach first or just use bash variables in a HEREDOC
cat <<EOF > kubernetes.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $KSA_NAME
  namespace: $NAMESPACE
  annotations:
    iam.gke.io/gcp-service-account: $GSA_EMAIL
---
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
  namespace: $NAMESPACE
spec:
  template:
    spec:
      serviceAccountName: $KSA_NAME
      containers:
      - name: gas-fakes-container
        image: $IMAGE_PATH
        env:
$K8S_ENV_VARS
      restartPolicy: Never
  backoffLimit: 0
EOF

# 6. Deploy to Kubernetes
echo "--- Deploying to Kubernetes Cluster ---"
# Delete existing job if it exists to allow re-running
kubectl delete job "$JOB_NAME" --namespace "$NAMESPACE" 2>/dev/null || true
kubectl apply -f kubernetes.yaml

echo "--- Job $JOB_NAME deployed. You can check status with: ---"
echo "kubectl get jobs -n $NAMESPACE"
echo "kubectl logs -l job-name=$JOB_NAME -n $NAMESPACE"
