#!/bin/bash
set -e

# --- 0. PREREQUISITES ---
if ! command -v gh &> /dev/null; then
    echo "Error: 'gh' (GitHub CLI) is not installed. Please install it first."
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "Error: You are not logged into GitHub CLI. Run 'gh auth login' first."
    exit 1
fi

# Detect which .env to use
if [ -f ".env" ]; then
    ENV_FILE=".env"
elif [ -f "../.env" ]; then
    ENV_FILE="../.env"
fi

if [ -z "$ENV_FILE" ]; then
    echo "Error: .env file not found. Please run 'npx gas-fakes init' and 'npx gas-fakes auth' first."
    exit 1
fi

# --- 1. CONFIGURATION ---
echo "--- GCP Workload Identity Federation Setup for GitHub Actions ---"

# Try to auto-detect PROJECT_ID from gcloud
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  # Fallback to detected .env
  PROJECT_ID=$(grep "GOOGLE_CLOUD_PROJECT" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"\r')
fi

if [ -z "$PROJECT_ID" ]; then
  echo "Error: No Google Cloud project set. Run 'gcloud config set project [PROJECT_ID]'"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Auto-detect GSA from detected .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"\r')

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

# --- 6. AUTOMATICALLY SET GITHUB SECRETS & VARIABLES ---
echo "--- GitHub CLI detected and authenticated. Setting secrets and variables... ---"

# Core WIF Secrets
gh secret set WIF_PROVIDER_NAME --body "$WIF_PROVIDER_NAME"
gh secret set WIF_SERVICE_ACCOUNT --body "$GSA_EMAIL"
gh variable set GOOGLE_CLOUD_PROJECT --body "$PROJECT_ID"

# Auto-detect workspace subject if possible
WORKSPACE_SUBJECT=$(gcloud config get-value account 2>/dev/null || echo "")
if [ -n "$WORKSPACE_SUBJECT" ]; then
    gh secret set GOOGLE_WORKSPACE_SUBJECT --body "$WORKSPACE_SUBJECT"
fi

# Read .env and set other variables
echo "Reading variables from $ENV_FILE..."
while IFS='=' read -r key val; do
    # Skip comments, empty lines, and already set core vars
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] || \
    [[ "$key" == "GOOGLE_CLOUD_PROJECT" ]] || \
    [[ "$key" == "GOOGLE_SERVICE_ACCOUNT_NAME" ]] || \
    [[ "$key" == "GOOGLE_WORKSPACE_SUBJECT" ]] && continue
    
    # Clean up value
    val=$(echo "$val" | sed 's/^"//;s/"$//')
    
    # Decide if it's a secret or variable (heuristic: if it contains 'KEY', 'TOKEN', or 'SECRET')
    if [[ "$key" =~ (KEY|TOKEN|SECRET) ]]; then
        echo "Setting secret: $key"
        gh secret set "$key" --body "$val"
    else
        echo "Setting variable: $key"
        gh variable set "$key" --body "$val"
    fi
done < "$ENV_FILE"

echo "GitHub configuration complete."

echo -e "\nExample GitHub Action usage:"
echo "--------------------------------------------------"
echo "    - id: 'auth'"
echo "      name: 'Authenticate to Google Cloud'"
echo "      uses: 'google-github-actions/auth@v2'"
echo "      with:"
echo "        workload_identity_provider: '$WIF_PROVIDER_NAME'"
echo "        service_account: '$GSA_EMAIL'"
echo "--------------------------------------------------"
