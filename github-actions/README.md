# GitHub Actions Authentication (WIF)

This directory contains setup scripts for authenticating **GitHub Actions** to **Google Cloud** using **Workload Identity Federation (WIF)**. This allows your CI/CD pipelines to securely access Google APIs (like Drive, Sheets, or Cloud Build) without using long-lived JSON service account keys.

## The Strategy
1. **Keyless**: No `.json` service account keys are stored in GitHub Secrets.
2. **Short-lived Tokens**: GitHub Actions uses an OIDC token to "trade" for a temporary Google Cloud access token.
3. **Identity-Based**: Permissions are granted specifically to your GitHub repository and branch/actor.

## Setup Instructions

### 1. Initialize your environment
Before running the setup, ensure your local environment is configured by running these commands in this directory:
```bash
npx gas-fakes init
npx gas-fakes auth
```
This will create and populate the local `.env` file required for synchronization.

### 2. Run the Setup Script
From this directory, run:
```bash
./setup-wif.sh
```
This script is highly automated and will:
-   Detect your GCP Project and GitHub Repository.
-   Create a Workload Identity Pool (`github-pool`) and OIDC Provider (`github-provider`).
-   Grant your GitHub repository permission to impersonate your Google Service Account.
-   **Automated Secrets Sync**: The script uses the `gh` CLI to automatically push all configuration from your local `.env` file to your GitHub Repository Secrets and Variables.

### 3. Use in a Workflow
A sample workflow is provided in `.github/workflows/gas-fakes.yml`. The core authentication step looks like this:

```yaml
    steps:
      - uses: actions/checkout@v4

      - id: 'auth'
        name: 'Authenticate to Google Cloud'
        uses: 'google-github-actions/auth@v2'
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER_NAME }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}
          # cloud-platform scope is required for DWD (signJwt)
          access_token_scopes: 'https://www.googleapis.com/auth/cloud-platform'

      - name: 'Run gas-fakes'
        run: |
          cd github-actions
          npm install
          node ./containerrun.js
        env:
          GOOGLE_CLOUD_PROJECT: ${{ vars.GOOGLE_CLOUD_PROJECT }}
          GOOGLE_WORKSPACE_SUBJECT: ${{ secrets.GOOGLE_WORKSPACE_SUBJECT }}
          # ... other env vars from secrets/vars
```

## Benefits
- **Security**: No static keys to leak or rotate.
- **Automation**: One-click synchronization of your local development environment to your CI/CD pipeline.
- **Auditability**: Every authentication event is logged in GCP Cloud Audit Logs.
- **Granular Control**: You can restrict access to specific branches, environments, or even specific GitHub actors.
