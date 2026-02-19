#!/bin/bash
set -e

# --- 1. GET USER INPUT ---
echo "--- Google Cloud Secret Manager Setup for AWS ---"
read -p "Enter your AWS_ACCESS_KEY_ID: " AWS_ID
read -p "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET
echo -e "\n"

# --- 2. GET PROJECT INFO ---
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

if [ -z "$PROJECT_ID" ]; then
  echo "Error: No Google Cloud project set. Run 'gcloud config set project [PROJECT_ID]'"
  exit 1
fi

echo "Setting up secrets in project: $PROJECT_ID ($PROJECT_NUMBER)"

# --- 3. CREATE SECRETS ---
create_secret() {
  local NAME=$1
  local VALUE=$2
  
  # Check if secret exists
  if gcloud secrets describe "$NAME" >/dev/null 2>&1; then
    echo "Secret $NAME already exists. Updating with new version..."
    # Use printf to avoid any trailing newlines or interpretation of -n
    printf "%s" "$VALUE" | gcloud secrets versions add "$NAME" --data-file=-
  else
    echo "Creating secret $NAME..."
    printf "%s" "$VALUE" | gcloud secrets create "$NAME" --replication-policy="automatic" --data-file=-
  fi
}

create_secret "AWS_ACCESS_KEY_ID" "$AWS_ID"
create_secret "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET"

# --- 4. GRANT PERMISSIONS ---
echo "Granting Secret Accessor role to Cloud Build Service Account..."

gcloud secrets add-iam-policy-binding AWS_ACCESS_KEY_ID \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding AWS_SECRET_ACCESS_KEY \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

# Also grant to the compute service account just in case
gcloud secrets add-iam-policy-binding AWS_ACCESS_KEY_ID \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding AWS_SECRET_ACCESS_KEY \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

echo "--- Setup Complete! ---"
echo "Your Cloud Build script can now securely access your AWS credentials."
