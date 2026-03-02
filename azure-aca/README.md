# Azure Container Apps Job Deployment (Cross-Cloud)

This directory contains experimental scripts for running your GAS containers on **Azure Container Apps (ACA) Jobs** while still accessing Google Workspace via **Workload Identity Federation**.

## Prerequisites
1.  **Azure CLI** installed and configured.
2.  **GCP CLI** installed and configured (`gcloud config set project ...`).
3.  **Secret Manager API** enabled in GCP.
4.  **Service Principal** in Azure with `AcrPush` permissions.
5.  **GCP Secret Manager Secrets**:
    -   `AZURE_CLIENT_ID`
    -   `AZURE_CLIENT_SECRET`

## Installing Azure CLI (`az`)
If you don't have the Azure CLI installed, follow these steps:

### macOS
```bash
brew update && brew install azure-cli
```

### Windows (PowerShell)
```powershell
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi
```

### Linux (Ubuntu/Debian)
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Post-Installation Setup
Once installed, log in and enable the `containerapp` extension:
```bash
az login
az config set extension.use_dynamic_install=yes_without_prompt
```

## Setup Azure for Cloud Build
To allow Google Cloud Build to push to your Azure Container Registry (ACR), you need a Service Principal.

1.  **Run the Setup Script**:
    ```bash
    ./setup-azure-secrets.sh
    ```
    This script will:
    -   Automatically retrieve your Azure Subscription ID.
    -   Create an Azure Service Principal with `AcrPush` permissions.
    -   Securely store the credentials in GCP Secret Manager.
    -   Grant Cloud Build permissions to access these secrets.

## The Strategy
1. **No Keys**: We do not use Google `.json` service account keys.
2. **Workload Identity Federation (WIF)**: We use Google Cloud WIF to allow Azure's Managed Identity to impersonate a Google Service Account.
3. **Token Exchange**: When the container runs on Azure, the Google SDK detects the Azure environment, fetches the Azure Managed Identity token, and "trades" it for a temporary Google access token.

## How to use
1. Update the variables in `deploy-aca.sh` (e.g., `LOCATION`, `RESOURCE_GROUP`, `ACR_NAME`).
2. Run `./deploy-aca.sh`.
3. The script will automatically:
   - Build the container on GCP.
   - Push it to Azure ACR.
   - Configure WIF between GCP and Azure.
   - Deploy and start an Azure Container App Job.
   - Tail the logs from the execution.

## Note on Execution
Azure Container App Jobs are designed for long-running tasks. Unlike AWS Lambda, they can run for up to 24 hours.

Azure's first-time setup for the Managed Environment is notably slower than Cloud Run or Lambda, as it provisions an entire Kubernetes cluster (K8s) in the background. Once the environment is ready, future job runs will be significantly faster.
