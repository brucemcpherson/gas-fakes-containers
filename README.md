# Google Apps Script Containers (Fakes)

This repository demonstrates how to run Google Apps Script (GAS) logic within containers on Google Cloud Platform (GCP). It utilizes the [`@mcpher/gas-fakes`](https://www.npmjs.com/package/@mcpher/gas-fakes) library to simulate the Apps Script environment (Drive, Sheets, etc.) in a Node.js runtime.

The project provides deployment paths for both **Kubernetes (GKE)** and **Cloud Run Jobs**.

---

## Prerequisites

- A Google Cloud Project with the following APIs enabled:
  - Artifact Registry
  - Cloud Build
  - Cloud Run (for Cloud Run path)
  - Kubernetes Engine (for GKE path)
  - The ability to set up domain wide delegation in your workspace domain when advised
- `gcloud` CLI installed and authenticated.
- **`gas-fakes` CLI installed globally**:
  ```bash
  npm install -g @mcpher/gas-fakes
  ```

## Environment Configuration

Both deployment paths rely on a `.env` file located in their respective directories (`k8s/.env` and `cloudrun/.env`). This file is ignored by Git.

The `.env` file and the necessary Google Service Account (GSA) are created and configured using the `gas-fakes` CLI:
1. **Initialize**: Run `gas-fakes init` to set up the project structure and **automatically create the required Google Service Account**. This will follow the path of creating an auth flow that will use keyless Domain Wide Delegation, which is used for workload identity in GKE and Cloud Run Jobs.
2. **Authenticate**: Run `gas-fakes auth` to configure the necessary GCP credentials and project settings.

For more details on setting up the base environment, refer to the documentation in the [gas-fakes](https://github.com/brucemcpherson/gas-fakes) repository.

After running gas-fakes auth, your `.env` file will contain at least:
```env
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_SERVICE_ACCOUNT_NAME=your-service-account-name
# Any other environment variables required by your script (e.g., API keys, Sheet IDs)
```

---

## 1. Kubernetes (GKE) Deployment

The Kubernetes path uses **GKE Autopilot** for a hands-off experience and **Workload Identity** to securely authenticate the container without managing Service Account keys.

### Cluster Management

A helper script is provided to manage a temporary test cluster:

```bash
cd k8s
# Create a GKE Autopilot cluster (takes ~5-10 mins)
./manage-cluster.sh up

# To delete the cluster when finished
./manage-cluster.sh down

# To set cluster credentials locally
./manage-cluster.sh get-credentials
```

### Deploying the Job

The `deploy-k8s.sh` script automates the entire lifecycle:
1. **Builds** the Docker image using Cloud Build.
2. **Configures Workload Identity** (binds the GSA to a Kubernetes Service Account).
3. **Generates a Manifest** (`kubernetes.yaml`) with environment variables injected from `.env`.
4. **Deploys** a Kubernetes Job to the cluster.

```bash
cd k8s
./deploy-k8s.sh
```

To monitor the job:
```bash
kubectl get jobs
kubectl logs -l job-name=gas-fakes-job
```

---

## 2. Cloud Run Deployment

The Cloud Run path is ideal for serverless execution of short-lived tasks.

### Deploying the Job

The `deploy-cloudrun.sh` script:
1. **Builds** the Docker image.
2. **Generates a YAML environment file** from your `.env`.
3. **Creates/Updates a Cloud Run Job**.
4. **Executes** the job immediately and tails the logs to your terminal.

```bash
cd cloudrun
./deploy-cloudrun.sh
```

---

## Project Structure

- `k8s/` and `cloudrun/`: Configuration and deployment scripts for each platform.
- `containerrun.js`: The entry point for the container which initializes the job.
- `example.js`: The core logic using `@mcpher/gas-fakes`. In this example, it identifies duplicate files on Google Drive by comparing MD5 checksums.
- `Dockerfile`: Multi-stage build to package the Node.js application.

## How it Works

The `@mcpher/gas-fakes` library provides global objects like `DriveApp`, `SpreadsheetApp`, and `ScriptApp` that mimic the GAS environment. When running in a container, it uses the ambient Google Cloud credentials (via Workload Identity or the Cloud Run Service Account) to interact with live Google APIs.
