# GitHub Actions Authentication (WIF)

This directory contains setup scripts for authenticating **GitHub Actions** to **Google Cloud** using **Workload Identity Federation (WIF)**. This allows your CI/CD pipelines to securely access Google APIs (like Drive, Sheets, or Cloud Build) without using long-lived JSON service account keys.

## The Strategy
1. **Keyless**: No `.json` service account keys are stored in GitHub Secrets.
2. **Short-lived Tokens**: GitHub Actions uses an OIDC token to "trade" for a temporary Google Cloud access token.
3. **Identity-Based**: Permissions are granted specifically to your GitHub repository and branch/actor.

## Setup Instructions

### 1. Run the Setup Script
From this directory, run:
```bash
./setup-wif.sh
```
This script will:
-   Detect your GCP Project and GitHub Repository.
-   Create a Workload Identity Pool (`github-pool`).
-   Create an OIDC Provider (`github-provider`).
-   Grant your GitHub repository permission to impersonate your Google Service Account.

### 2. Configure GitHub Secrets
The script will output several values. Add these to your GitHub Repository **Settings > Secrets and variables > Actions**:

-   `WIF_PROVIDER_NAME`: The full resource name of the provider.
-   `WIF_SERVICE_ACCOUNT`: The email of the Google Service Account.
-   `GOOGLE_CLOUD_PROJECT`: Your GCP Project ID.

### 3. Use in a Workflow
Add the following step to your `.github/workflows/your-workflow.yml`:

```yaml
jobs:
  run-gas-fakes:
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write' # Required for WIF

    steps:
      - uses: actions/checkout@v4

      - id: 'auth'
        name: 'Authenticate to Google Cloud'
        uses: 'google-github-actions/auth@v2'
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER_NAME }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: 'Run gas-fakes'
        run: |
          npm install
          npx gas-fakes run ./example.js
```

## Benefits
- **Security**: No static keys to leak or rotate.
- **Auditability**: Every authentication event is logged in GCP Cloud Audit Logs.
- **Granular Control**: You can restrict access to specific branches, environments, or even specific GitHub actors.
