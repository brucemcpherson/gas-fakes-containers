#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
LOCATION="westeurope"
RESOURCE_GROUP="gas-fakes-rg"
ACR_NAME="gasfakesregistry"
ACA_ENV_NAME="gas-fakes-env"
ACA_NAME="gas-fakes-app"
MANAGED_IDENTITY_NAME="gas-fakes-identity"
REPO_NAME="gas-fakes-repo"

# Ensure local .env exists
if [ ! -f ".env" ]; then
    echo "Error: .env not found in current directory."
    exit 1
fi

# GCP CONFIG
GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project)
GCP_REGION="europe-west1"
GCP_REPO_NAME="gas-fakes-repo" 
IMAGE_PATH="$GCP_REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$GCP_REPO_NAME/$ACA_NAME"

# GCP WIF Config
GCP_POOL_ID="azure-pool"
GCP_PROVIDER_ID="azure-provider"

# Auto-detect GSA from local .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" .env | cut -d'=' -f2 | tr -d '"
')
GSA_EMAIL="${GSA_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$GOOGLE_CLOUD_PROJECT" --format='value(projectNumber)')

AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "--- Using GCP Project: $GOOGLE_CLOUD_PROJECT ---"
echo "--- Using GSA: $GSA_EMAIL ---"
echo "--- Using Azure Tenant: $AZURE_TENANT_ID ---"

# --- 2. GENERATE HIDDEN GCP CREDENTIALS CONFIG ---
echo "--- Generating Temporary Credentials ---"
gcloud iam workload-identity-pools create-cred-config \
    "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/providers/$GCP_PROVIDER_ID" \
    --service-account="$GSA_EMAIL" \
    --output-file=".google-credentials.json" \
    --credential-source-file="/tmp/azure-token.json" \
    --credential-source-type="json" \
    --credential-source-field-name="access_token"

if [ ! -f ".google-credentials.json" ]; then
    echo "Error: Failed to generate .google-credentials.json"
    exit 1
fi

# --- 3. ENSURE AZURE PROVIDERS ARE REGISTERED ---
echo "--- Ensuring Azure Resource Providers are registered ---"
PROVIDERS=("Microsoft.ContainerRegistry" "Microsoft.App" "Microsoft.OperationalInsights" "Microsoft.ManagedIdentity")

for PROVIDER in "${PROVIDERS[@]}"; do
    STATUS=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
    if [ "$STATUS" != "Registered" ]; then
        echo "Registering $PROVIDER (currently $STATUS)..."
        az provider register --namespace "$PROVIDER"
        # We'll wait for each one if it was not already registered
        echo "Waiting for $PROVIDER to complete registration..."
        while [ "$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv)" != "Registered" ]; do
            sleep 5
            echo -n "."
        done
        echo " Registered."
    else
        echo "Provider $PROVIDER is already registered."
    fi
done

# --- 4. PRE-CREATE AZURE RESOURCES (REQUIRED FOR PUSH) ---
echo "--- Ensuring Azure Resource Group and ACR exist ---"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null

if ! az acr show --name "$ACR_NAME" >/dev/null 2>&1; then
    echo "Creating ACR: $ACR_NAME..."
    az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --sku Basic --admin-enabled true >/dev/null
else
    echo "ACR $ACR_NAME already exists."
fi

# --- 5. BUILD & PUSH TO AZURE ACR VIA CLOUD BUILD ---
echo "--- Building and Pushing to ACR (via Cloud Build) ---"
gcloud builds submit . \
    --config=cloudbuild-azure.yaml \
    --substitutions=_IMAGE_PATH="$IMAGE_PATH",_ACR_NAME="$ACR_NAME",_REPO_NAME="$REPO_NAME"

# REMOVE temporary hidden file immediately
rm .google-credentials.json

# --- 5. CONFIGURE GOOGLE WORKLOAD IDENTITY FEDERATION ---
echo "--- Configuring GCP Workload Identity Federation ---"
gcloud iam workload-identity-pools describe "$GCP_POOL_ID" --location="global" --quiet >/dev/null 2>&1 || \
    gcloud iam workload-identity-pools create "$GCP_POOL_ID" \
        --location="global" \
        --display-name="Azure ACA Pool" \
        --quiet >/dev/null

ISSUER_URI="https://login.microsoftonline.com/$AZURE_TENANT_ID/v2.0"
# This UUID was observed in the 'aud' claim of the Azure token in logs
AUDIENCE="fb60f99c-7a34-4190-8149-302f77469936"

echo "Applying configuration to Workload Identity Provider..."
# Best effort undelete
gcloud iam workload-identity-pools providers undelete "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" --quiet >/dev/null 2>&1 || true

# Best effort create (will fail if exists, which is fine)
gcloud iam workload-identity-pools providers create-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.az_app=assertion.azp" \
    --quiet >/dev/null 2>&1 || true

# Final forced update to ensure settings are correct
gcloud iam workload-identity-pools providers update-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.az_app=assertion.azp" \
    --quiet >/dev/null

# --- 6. DEPLOY TO AZURE CONTAINER APPS JOB ---
echo "--- Deploying to Azure ---"

# Create Managed Identity if it doesn't exist
if ! az identity show --name "$MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "Creating Managed Identity..."
    az identity create --name "$MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null
fi
IDENTITY_ID=$(az identity show --name "$MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
IDENTITY_CLIENT_ID=$(az identity show --name "$MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)

# Allow GCP WIF to be used by this Identity
MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/attribute.az_app/$IDENTITY_CLIENT_ID"
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" --role="roles/iam.workloadIdentityUser" --member="$MEMBER" --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" --role="roles/iam.serviceAccountTokenCreator" --member="$MEMBER" --quiet >/dev/null

# Allow the Managed Identity to pull from the ACR
ACR_ID=$(az acr show --name "$ACR_NAME" --query id -o tsv)
az role assignment create --assignee "$IDENTITY_CLIENT_ID" --role "AcrPull" --scope "$ACR_ID" >/dev/null 2>&1 || true

# Ensure ACA Environment exists
if ! az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "Creating ACA Environment..."
    az containerapp env create --name "$ACA_ENV_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

# Prepare Environment Variables
GOOGLE_WORKSPACE_SUBJECT=$(gcloud config get-value account)
ENV_VARS_ARRAY=("GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT" "GOOGLE_WORKSPACE_SUBJECT=$GOOGLE_WORKSPACE_SUBJECT" "GOOGLE_APPLICATION_CREDENTIALS=/usr/src/app/google-credentials.json" "AZURE_CLIENT_ID=$IDENTITY_CLIENT_ID" "GCP_PROJECT_NUMBER=$PROJECT_NUMBER" "GCP_POOL_ID=$GCP_POOL_ID" "GCP_PROVIDER_ID=$GCP_PROVIDER_ID")

# ACA provides these for Managed Identities
if [ -n "$IDENTITY_ENDPOINT" ]; then
    ENV_VARS_ARRAY+=("IDENTITY_ENDPOINT=$IDENTITY_ENDPOINT")
fi
if [ -n "$IDENTITY_HEADER" ]; then
    ENV_VARS_ARRAY+=("IDENTITY_HEADER=$IDENTITY_HEADER")
fi

while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] || [[ "$key" == "GOOGLE_CLOUD_PROJECT" ]] && continue
    # Clean up value
    val=$(echo $val | sed 's/^"//;s/"$//')
    ENV_VARS_ARRAY+=("$key=$val")
done < .env

# Deploy ACA Job
IMAGE_URI="$ACR_NAME.azurecr.io/$REPO_NAME:latest"

if az containerapp job show --name "$ACA_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "Deleting existing Azure Container App Job to ensure clean state..."
    az containerapp job delete --name "$ACA_NAME" --resource-group "$RESOURCE_GROUP" --yes >/dev/null
fi

echo "Creating Azure Container App Job..."
az containerapp job create \
    --name "$ACA_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENV_NAME" \
    --image "$IMAGE_URI" \
    --trigger-type Manual \
    --parallelism 1 \
    --replica-completion-count 1 \
    --mi-user-assigned "$IDENTITY_ID" \
    --registry-server "$ACR_NAME.azurecr.io" \
    --registry-identity "$IDENTITY_ID" \
    --replica-timeout 86400 \
    --replica-retry-limit 0 \
    --cpu "1.0" --memory "2.0Gi" \
    --env-vars "${ENV_VARS_ARRAY[@]}" >/dev/null

# --- 6. EXECUTE AND MONITOR ---
echo "--- Starting Execution ---"
EXEC_NAME=$(az containerapp job start --name "$ACA_NAME" --resource-group "$RESOURCE_GROUP" --query name -o tsv)

if [ -z "$EXEC_NAME" ]; then
    echo "Error: Failed to start execution."
    exit 1
fi
echo "--- Execution Started: $EXEC_NAME ---"

echo "--- Tailing Logs (Automatic close on completion) ---"
# Loop to keep tailing as long as the job is running
while true; do
    # 1. Attempt to tail logs
    az containerapp job logs show \
        --name "$ACA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --execution "$EXEC_NAME" \
        --container "$ACA_NAME" \
        --follow || true

    # 2. Check if the job is still running
    STATUS=$(az containerapp job execution show \
        --name "$ACA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --job-execution-name "$EXEC_NAME" \
        --query properties.status -o tsv 2>/dev/null || echo "Unknown")

    if [ "$STATUS" == "Succeeded" ] || [ "$STATUS" == "Failed" ]; then
        echo "--- Job finished with status: $STATUS ---"
        break
    fi

    # 3. If it stopped tailing but job is still running, wait a bit and retry
    echo "--- Connection closed, but job still $STATUS. Reconnecting... ---"
    sleep 5
done
