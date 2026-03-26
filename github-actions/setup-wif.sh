#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
echo "--- GCP Workload Identity Federation Setup for GitHub Actions ---"

# Try to auto-detect PROJECT_ID from gcloud
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  # Fallback to .env in root
  PROJECT_ID=$(grep "GOOGLE_CLOUD_PROJECT" ../.env | cut -d'=' -f2 | tr -d '"\r')
fi

if [ -z "$PROJECT_ID" ]; then
  echo "Error: No Google Cloud project set. Run 'gcloud config set project [PROJECT_ID]'"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Auto-detect GSA from local .env or root .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" .env 2>/dev/null | cut -d'=' -f2 | tr -d '"\r')
if [ -z "$GSA_NAME" ]; then
    GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" ../.env 2>/dev/null | cut -d'=' -f2 | tr -d '"\r')
fi

if [ -z "$GSA_NAME" ]; then
    read -p "Enter the Google Service Account name (e.g. gas-fakes-sa): " GSA_NAME
fi

GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Auto-detect GitHub Repo from git
REPO_NAME=$(git remote -v | grep origin | head -n 1 | awk '{print $2}' | sed 's/.*github.com[:\/]//;s/\.git$//')

if [ -z "$REPO_NAME" ]; then
    read -p "Enter the GitHub Repository (OWNER/REPO, e.g. brucemcpherson/gas-fakes-containers): " REPO_NAME
fi

POOL_ID="github-pool"
PROVIDER_ID="github-provider"

echo "--- Using GCP Project: $PROJECT_ID ($PROJECT_NUMBER) ---"
echo "--- Using GSA: $GSA_EMAIL ---"
echo "--- Using GitHub Repo: $REPO_NAME ---"

# --- 2. CREATE WORKLOAD IDENTITY POOL ---
echo "--- Ensuring Workload Identity Pool exists: $POOL_ID ---"
gcloud iam workload-identity-pools describe "$POOL_ID" --location="global" --quiet >/dev/null 2>&1 || \
    gcloud iam workload-identity-pools create "$POOL_ID" \
        --location="global" \
        --display-name="GitHub Actions Pool" \
        --quiet

# --- 3. CREATE WORKLOAD IDENTITY PROVIDER ---
echo "--- Ensuring Workload Identity Provider exists: $PROVIDER_ID ---"
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --location="global" --quiet >/dev/null 2>&1; then
    
    echo "Creating Workload Identity Provider..."
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
        --workload-identity-pool="$POOL_ID" \
        --location="global" \
        --display-name="GitHub Provider" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
        --attribute-condition="assertion.repository == '$REPO_NAME'" \
        --quiet
else
    echo "Provider $PROVIDER_ID already exists. Updating configuration..."
    gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_ID" \
        --workload-identity-pool="$POOL_ID" \
        --location="global" \
        --display-name="GitHub Provider" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
        --attribute-condition="assertion.repository == '$REPO_NAME'" \
        --quiet
fi

# --- 4. ALLOW REPO TO IMPERSONATE SERVICE ACCOUNT ---
echo "--- Granting impersonation permissions to GitHub Repo ---"
MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/attribute.repository/$REPO_NAME"

gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER" \
    --quiet

# --- 5. OUTPUT CONFIGURATION FOR GITHUB ---
WIF_PROVIDER_NAME="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID"

echo -e "\n--- Setup Complete! ---"

# --- 6. AUTOMATICALLY SET GITHUB SECRETS (Optional) ---
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo "--- GitHub CLI detected and authenticated. Setting secrets automatically... ---"
    gh secret set WIF_PROVIDER_NAME --body "$WIF_PROVIDER_NAME"
    gh secret set WIF_SERVICE_ACCOUNT --body "$GSA_EMAIL"
    gh secret set GOOGLE_CLOUD_PROJECT --body "$PROJECT_ID"
    echo "Secrets WIF_PROVIDER_NAME, WIF_SERVICE_ACCOUNT, and GOOGLE_CLOUD_PROJECT have been set."
else
    echo "Add these values to your GitHub Repository Secrets/Variables manually (or install 'gh' and login):"
    echo "WIF_PROVIDER_NAME: $WIF_PROVIDER_NAME"
    echo "WIF_SERVICE_ACCOUNT: $GSA_EMAIL"
    echo "GOOGLE_CLOUD_PROJECT: $PROJECT_ID"
fi

echo -e "\nExample GitHub Action usage:"
echo "--------------------------------------------------"
echo "    - id: 'auth'"
echo "      name: 'Authenticate to Google Cloud'"
echo "      uses: 'google-github-actions/auth@v2'"
echo "      with:"
echo "        workload_identity_provider: '$WIF_PROVIDER_NAME'"
echo "        service_account: '$GSA_EMAIL'"
echo "--------------------------------------------------"
