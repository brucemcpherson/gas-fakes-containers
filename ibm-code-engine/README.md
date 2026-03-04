# IBM Cloud Code Engine Deployment (Cross-Cloud)

This directory contains scripts for running your GAS containers on **IBM Cloud Code Engine** while still accessing Google Workspace via **Workload Identity Federation**.

## Prerequisites
1.  **IBM Cloud Account**: You will need an IBM Cloud account.
    -   Go to [cloud.ibm.com/registration](https://cloud.ibm.com/registration).
    -   IBM Cloud uses a **Pay-As-You-Go** model for its Free Tier. You will need to provide a credit card for identity verification, but you will not be charged as long as you stay within the "Free" or "Lite" plan quotas.
    -   New accounts typically receive a **$200 credit** for the first 30 days.
2.  **IBM Cloud CLI** installed.
3.  **jq** installed (used for parsing CLI output).
2.  **Container Registry plugin** (`ibmcloud plugin install cr`).
3.  **Code Engine plugin** (`ibmcloud plugin install ce`).
4.  **GCP CLI** installed and configured.
5.  **Secret Manager API** enabled in GCP.

## Installing IBM Cloud CLI (`ibmcloud`)
If you don't have the IBM Cloud CLI installed, follow these steps:

### macOS / Linux
```bash
curl -fsSL https://clis.cloud.ibm.com/install/osx | sh
```
*(For Linux, replace `osx` with `linux64`)*

### Windows (PowerShell)
```powershell
iex (New-Object Net.WebClient).DownloadString('https://clis.cloud.ibm.com/install/powershell')
```

### Post-Installation Setup
Once installed, log in and install the required plugins.

**Recommended Login Method (Passcode)**:
1.  Go to [cloud.ibm.com](https://cloud.ibm.com) and log in.
2.  Click your profile icon in the top right and select **Log in to CLI and API**.
3.  Copy and run the provided command (it looks like `ibmcloud login -a https://cloud.ibm.com -u passcode -p xxxx`).

Once logged in, install the plugins:
```bash
ibmcloud plugin install cr
ibmcloud plugin install ce
```

## Setup IBM for Cloud Build
To allow Google Cloud Build to push to your IBM Container Registry (ICR), you need an IBM API Key.

1.  **Log in to IBM Cloud**:
    ```bash
    ibmcloud login
    ```

2.  **Run the Setup Script**:
    ```bash
    ./setup-ibm-secrets.sh
    ```
    This script will:
    -   Create an IBM Service ID.
    -   Generate an IBM API Key.
    -   Securely store the key in GCP Secret Manager.
    -   Grant Cloud Build permissions to access the key.

    Note - generating a key seems to take a while, so be patient.

## How to use
1. Update the variables in `deploy-ibm.sh` (e.g., `REGION`, `ICR_NAMESPACE`, `CE_PROJECT`).
2. Run `./deploy-ibm.sh`.
3. The script will:
   - Build the container on GCP.
   - Push it to IBM ICR.
   - Configure WIF between GCP and IBM.
   - Create a Code Engine Project and Job.
   - Submit a JobRun and tail the logs.

## The Identity Bridge
Since IBM Code Engine doesn't natively expose an OIDC token to the filesystem, our `containerrun.js` includes an **Identity Bridge**. It uses the `IBM_CLOUD_API_KEY` (passed as a secret) to fetch a fresh IBM IAM token at runtime, which is then used to authenticate with Google via Workload Identity Federation.
