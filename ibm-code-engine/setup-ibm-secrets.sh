#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
echo "--- IBM Cloud & GCP Secret Manager Setup for Code Engine ---"

# Check for gcloud and ibmcloud
if ! command -v ibmcloud &> /dev/null; then
    echo "Error: ibmcloud CLI not found. Please install it first."
    exit 1
fi

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

echo "--- Using GCP Project: $PROJECT_ID ($PROJECT_NUMBER) ---"

# --- 2. TARGET RESOURCE GROUP ---
echo "--- Targeting Default Resource Group ---"
ibmcloud target -g Default || {
    echo "Error: Could not target 'Default' resource group. Please set one manually using 'ibmcloud target -g [GROUP]'"
    exit 1
}

# --- 2. CREATE IBM SERVICE ID & API KEY ---
SERVICE_ID_NAME="gas-fakes-service-id"
API_KEY_NAME="gas-fakes-ibm-key"

echo "--- Ensuring IBM Service ID exists: $SERVICE_ID_NAME ---"
# Create Service ID if it doesn't exist, and capture the info
# Note: ibmcloud service-id-create returns an object, ibmcloud service-id returns an array or object
SERVICE_ID_INFO=$(ibmcloud iam service-id-create "$SERVICE_ID_NAME" --description "Auth for gas-fakes cross-cloud" --output json || ibmcloud iam service-id "$SERVICE_ID_NAME" --output json)
SERVICE_ID_ID=$(echo "$SERVICE_ID_INFO" | jq -r 'if type=="array" then .[0].id else .id end')

if [ -z "$SERVICE_ID_ID" ] || [ "$SERVICE_ID_ID" == "null" ]; then
    echo "Error: Could not retrieve Service ID 'id'."
    exit 1
fi

echo "--- Granting Container Registry Permissions to Service ID ---"
# Grant Manager role for all registry resources
ibmcloud iam service-policy-create "$SERVICE_ID_ID" --roles Manager --service-name container-registry || true
# Grant Administrator role for IAM (required for some registry ops)
ibmcloud iam service-policy-create "$SERVICE_ID_ID" --roles Administrator --service-name iam-identity || true

echo "--- Generating IBM API Key for Service ID: $SERVICE_ID_ID ---"
# Generate a new API key using the unique ServiceId-xxx string
ibmcloud iam service-api-key-create "$API_KEY_NAME" "$SERVICE_ID_ID" --description "Key for GCP Cloud Build" --file .ibm-key.json --output json > /dev/null
IBM_API_KEY=$(jq -r .apikey .ibm-key.json)
rm .ibm-key.json

if [ -z "$IBM_API_KEY" ] || [ "$IBM_API_KEY" == "null" ]; then
    echo "Error: Failed to create/retrieve IBM API Key."
    exit 1
fi

# --- 3. CREATE GCP SECRETS ---
create_secret() {
  local NAME=$1
  local VALUE=$2
  
  if gcloud secrets describe "$NAME" >/dev/null 2>&1; then
    echo "Secret $NAME already exists. Updating with new version..."
    printf "%s" "$VALUE" | gcloud secrets versions add "$NAME" --data-file=-
  else
    echo "Creating secret $NAME..."
    printf "%s" "$VALUE" | gcloud secrets create "$NAME" --replication-policy="automatic" --data-file=-
  fi
}

create_secret "IBM_CLOUD_API_KEY" "$IBM_API_KEY"

# --- 4. GRANT PERMISSIONS ---
echo "--- Granting Secret Accessor role to Cloud Build Service Account ---"

gcloud secrets add-iam-policy-binding IBM_CLOUD_API_KEY \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding IBM_CLOUD_API_KEY \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

echo "--- Setup Complete! ---"
echo "IBM Cloud API Key is now stored in GCP Secret Manager."
echo "Your Cloud Build can now securely push images to IBM Container Registry."
