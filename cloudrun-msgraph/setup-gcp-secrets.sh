#!/bin/bash
set -e

echo "--- Google Cloud Secret Manager Setup for MS Graph Token ---"

# Check if .msgraph-token.jwt exists in the current directory
TOKEN_FILE=".msgraph-token.jwt"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: MS Graph token file not found at $TOKEN_FILE"
    echo "Please run 'gas-fakes auth' (or 'node ../gas-fakes/gas-fakes.js auth') in this directory to generate it."
    exit 1
fi

TOKEN_VALUE=$(cat "$TOKEN_FILE")

PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_ID" ]; then
  echo "Error: No Google Cloud project set. Run 'gcloud config set project [PROJECT_ID]'"
  exit 1
fi

echo "Setting up MSGRAPH_TOKEN_JWT secret in project: $PROJECT_ID ($PROJECT_NUMBER)"

if gcloud secrets describe MSGRAPH_TOKEN_JWT >/dev/null 2>&1; then
    echo "Secret MSGRAPH_TOKEN_JWT already exists. Updating..."
    printf "%s" "$TOKEN_VALUE" | gcloud secrets versions add MSGRAPH_TOKEN_JWT --data-file=-
else
    echo "Creating secret MSGRAPH_TOKEN_JWT..."
    printf "%s" "$TOKEN_VALUE" | gcloud secrets create MSGRAPH_TOKEN_JWT --replication-policy="automatic" --data-file=-
fi

# --- GRANT PERMISSIONS ---
echo "Granting Secret Accessor role to Compute Engine default service account..."
gcloud secrets add-iam-policy-binding MSGRAPH_TOKEN_JWT \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

# Also grant to custom service account if specified in .env
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    SA_NAME=$(grep -E '^GOOGLE_SERVICE_ACCOUNT_NAME=' "$ENV_FILE" | head -n 1 | cut -d '=' -f2 | tr -d '"\r')
    if [ -n "$SA_NAME" ]; then
        echo "Granting Secret Accessor role to custom service account: ${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        gcloud secrets add-iam-policy-binding MSGRAPH_TOKEN_JWT \
            --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="roles/secretmanager.secretAccessor" \
            --quiet
    fi
fi

echo "--- Setup Complete! ---"
echo "Your MS Graph token cache has been securely uploaded to GCP Secret Manager."
