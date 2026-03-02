#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
echo "--- Azure & GCP Secret Manager Setup for ACA ---"

# Get Subscription ID directly from Azure CLI
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Error: Could not retrieve Azure Subscription ID. Are you logged in with 'az login'?"
    exit 1
fi

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_ID" ]; then
  echo "Error: No Google Cloud project set. Run 'gcloud config set project [PROJECT_ID]'"
  exit 1
fi

echo "--- Using Azure Subscription: $AZURE_SUBSCRIPTION_ID ---"
echo "--- Using GCP Project: $PROJECT_ID ($PROJECT_NUMBER) ---"

# --- 2. CREATE AZURE SERVICE PRINCIPAL ---
SP_NAME="gas-fakes-sp"
echo "--- Ensuring Azure Service Principal exists: $SP_NAME ---"

# az ad sp create-for-rbac is essentially idempotent if you use the same name.
# It will either create a new one or reset credentials for the existing one.
# Note: This requires 'jq' to be installed locally.
SP_JSON=$(az ad sp create-for-rbac --name "$SP_NAME" --role "AcrPush" --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID" --output json 2>/dev/null)

if [ -z "$SP_JSON" ]; then
    echo "Error: Failed to create or update Service Principal. Check permissions."
    exit 1
fi

AZURE_CLIENT_ID=$(echo $SP_JSON | jq -r .appId)
AZURE_CLIENT_SECRET=$(echo $SP_JSON | jq -r .password)

if [ -z "$AZURE_CLIENT_ID" ] || [ "$AZURE_CLIENT_ID" == "null" ]; then
    echo "Error: Failed to parse Service Principal details. Ensure 'jq' is installed."
    exit 1
fi

echo "--- Service Principal Configured: $AZURE_CLIENT_ID ---"

# --- 3. CREATE GCP SECRETS ---
create_secret() {
  local NAME=$1
  local VALUE=$2
  
  if gcloud secrets describe "$NAME" >/dev/null 2>&1; then
    echo "Secret $NAME already exists. Updating with new version..."
    printf "%s" "$VALUE" | gcloud secrets versions add "$NAME" --data-file=-
  else
    echo "Creating secret $NAME..."
    # Initial creation with value
    printf "%s" "$VALUE" | gcloud secrets create "$NAME" --replication-policy="automatic" --data-file=-
  fi
}

create_secret "AZURE_CLIENT_ID" "$AZURE_CLIENT_ID"
create_secret "AZURE_CLIENT_SECRET" "$AZURE_CLIENT_SECRET"

# --- 4. GRANT PERMISSIONS ---
echo "--- Granting Secret Accessor role to Service Accounts ---"

# The standard Cloud Build Service Account
gcloud secrets add-iam-policy-binding AZURE_CLIENT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding AZURE_CLIENT_SECRET \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

# Also grant to the default compute service account as some Cloud Build configs use it
gcloud secrets add-iam-policy-binding AZURE_CLIENT_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding AZURE_CLIENT_SECRET \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

echo "--- Setup Complete! ---"
echo "Azure Service Principal credentials are now stored in GCP Secret Manager."
echo "Your Cloud Build can now securely push images to Azure Container Registry."
