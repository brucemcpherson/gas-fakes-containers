#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
FLY_APP_NAME="gas-fakes-fly-$(jot -r 1 1000 9999)" # Needs to be globally unique
FLY_REGION="lhr" # London

# Initialize and authenticate if .env doesn't exist
if [ ! -f ".env" ]; then
    echo "--- .env not found. Initializing gas-fakes ---"
    npx gas-fakes init
    npx gas-fakes auth
fi

# Ensure local .env exists now
if [ ! -f ".env" ]; then
    echo "Error: .env not found even after init/auth. Please run 'npx gas-fakes init' and 'npx gas-fakes auth' manually."
    exit 1
fi

if ! command -v fly &> /dev/null; then
    echo "Error: 'fly' CLI is not installed. Please follow the README to install it."
    exit 1
fi

# GCP CONFIG
GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project)
GCP_POOL_ID="fly-pool"
GCP_PROVIDER_ID="fly-provider"

# Auto-detect GSA from local .env
GSA_NAME=$(grep "GOOGLE_SERVICE_ACCOUNT_NAME" .env | cut -d'=' -f2 | tr -d '"\r')
GSA_EMAIL="${GSA_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$GOOGLE_CLOUD_PROJECT" --format='value(projectNumber)')

echo "--- Using GCP Project: $GOOGLE_CLOUD_PROJECT ---"
echo "--- Using GSA: $GSA_EMAIL ---"

# --- 2. GENERATE WIF CREDENTIALS CONFIG ---
echo "--- Generating Temporary Credentials Config ---"
gcloud iam workload-identity-pools create-cred-config \
    "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/providers/$GCP_PROVIDER_ID" \
    --service-account="$GSA_EMAIL" \
    --output-file=".google-credentials.json" \
    --credential-source-file="/tmp/fly-token.json" \
    --credential-source-type="json" \
    --credential-source-field-name="access_token"

# --- 3. CONFIGURE GOOGLE WORKLOAD IDENTITY FEDERATION ---
echo "--- Configuring GCP Workload Identity Federation ---"
gcloud iam workload-identity-pools describe "$GCP_POOL_ID" --location="global" --quiet >/dev/null 2>&1 || \
    gcloud iam workload-identity-pools create "$GCP_POOL_ID" \
        --location="global" \
        --display-name="Fly.io Machines Pool" \
        --quiet >/dev/null

# Fly OIDC issuer
ISSUER_URI="https://fly.io/oidc"
# The expected audience is the full provider URL
AUDIENCE="https://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/providers/$GCP_PROVIDER_ID"

echo "Applying configuration to Workload Identity Provider (Fly.io)..."
gcloud iam workload-identity-pools providers undelete "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" --quiet >/dev/null 2>&1 || true

gcloud iam workload-identity-pools providers create-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.app=assertion.app" \
    --quiet >/dev/null 2>&1 || true

gcloud iam workload-identity-pools providers update-oidc "$GCP_PROVIDER_ID" \
    --workload-identity-pool="$GCP_POOL_ID" \
    --location="global" \
    --issuer-uri="$ISSUER_URI" \
    --allowed-audiences="$AUDIENCE" \
    --attribute-mapping="google.subject=assertion.sub,attribute.app=assertion.app" \
    --quiet >/dev/null

# Allow the pool to impersonate the GSA
MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$GCP_POOL_ID/*"
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$MEMBER" --quiet >/dev/null

# --- 4. DEPLOY TO FLY.IO ---
echo "--- Setting up Fly.io App ---"

# Create a deterministic app name or use one if it exists
# We'll see if we can find an existing gas-fakes app, else make a new one
EXISTING_APP=$(fly apps list -j | jq -r '.[].Name' | grep '^gas-fakes-fly' | head -n 1 || echo "")
if [ -n "$EXISTING_APP" ]; then
    FLY_APP_NAME="$EXISTING_APP"
    echo "Found existing Fly app: $FLY_APP_NAME"
else
    echo "Creating new Fly app: $FLY_APP_NAME"
    fly apps create "$FLY_APP_NAME" --org personal
fi

# Prepare environment variables arrays
ENV_VARS=()
ENV_VARS+=("GOOGLE_APPLICATION_CREDENTIALS=/usr/src/app/google-credentials.json")
ENV_VARS+=("GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT")
ENV_VARS+=("GOOGLE_WORKSPACE_SUBJECT=$(gcloud config get-value account)")
ENV_VARS+=("FLY_OIDC_AUD=$AUDIENCE")

while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.* ]] || [[ -z "$key" ]] || [[ "$key" == "GOOGLE_CLOUD_PROJECT" ]] && continue
    val=$(echo "$val" | sed 's/^"//;s/"$//')
    ENV_VARS+=("${key}=${val}")
done < .env

# Set secrets on the app (only needed for sensitive stuff, but we'll set everything as secrets for simplicity)
echo "--- Setting App Secrets ---"
fly secrets set "${ENV_VARS[@]}" -a "$FLY_APP_NAME" >/dev/null 2>&1 || true

# Clean up previous machines with 'Destroyed' or 'replaced' state
echo "--- Cleaning up previous machines ---"
for machine in $(fly machines list -a "$FLY_APP_NAME" -j | jq -r '.[] | select(.state=="destroyed" or .state=="replaced") | .id' 2>/dev/null || echo ""); do
    [ -n "$machine" ] && fly machines destroy "$machine" -a "$FLY_APP_NAME" --force >/dev/null 2>&1 || true
done

echo "--- Building and Running Machine (Tail logs automatically) ---"
# We run detached, without --rm so we can capture logs until it definitely stops.
# Fly CLI streams out a bunch of lines. We capture them to extract the Machine ID.
OUTPUT=$(fly machine run . -a "$FLY_APP_NAME" -r "$FLY_REGION" \
    --name "gas-fakes-job-$(jot -r 1 100 999 2>/dev/null || echo $RANDOM)" \
    --detach)

echo "$OUTPUT"
MACHINE_ID=$(echo "$OUTPUT" | grep -i "Machine ID" | awk '{print $NF}')

if [ -z "$MACHINE_ID" ]; then
    echo "Error: Could not determine Machine ID from output."
    exit 1
fi

echo "--- Tailing Logs (Ctrl+C to stop) ---"

# Start tailing logs in background
fly logs -a "$FLY_APP_NAME" --machine "$MACHINE_ID" &
LOG_PID=$!

# Wait for machine to finish (stop or destroy)
while true; do
    STATE=$(fly machine status "$MACHINE_ID" -a "$FLY_APP_NAME" -j 2>/dev/null | jq -r '.state' || echo "unknown")
    if [ "$STATE" = "stopped" ] || [ "$STATE" = "destroyed" ] || [ "$STATE" = "replaced" ]; then
        echo "--- Machine finished with state: $STATE ---"
        break
    fi
    sleep 5
done

# Stop the log tailer
kill $LOG_PID 2>/dev/null || true

# Destroy the machine now that it's done
echo "--- Cleaning up container instance ---"
fly machine destroy "$MACHINE_ID" -a "$FLY_APP_NAME" --force >/dev/null 2>&1 || true

# Clean up local creds
rm -f .google-credentials.json
echo "--- Fly.io Execution Complete ---"
