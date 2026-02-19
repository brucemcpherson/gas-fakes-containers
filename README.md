# Google Apps Script Containers (Fakes)

This repository demonstrates how to run Google Apps Script (GAS) logic within containers on Google Cloud Platform (GCP) and AWS. It utilizes the [`@mcpher/gas-fakes`](https://www.npmjs.com/package/@mcpher/gas-fakes) library to simulate the Apps Script environment (Drive, Sheets, etc.) in a Node.js runtime.

The project provides deployment paths for **Kubernetes (GKE)**, **Cloud Run Jobs**, and **AWS Lambda**.

---

## Prerequisites

- A Google Cloud Project with the following APIs enabled:
  - Artifact Registry, Cloud Build, Cloud Run, Kubernetes Engine, and Secret Manager.
  - The ability to set up domain-wide delegation in your workspace domain when advised.
- `gcloud` CLI installed and authenticated.
- **`gas-fakes` CLI installed globally**:
  ```bash
  npm install -g @mcpher/gas-fakes
  ```
- **For AWS Path**: 
  - AWS CLI installed and configured (`aws configure`).

## Environment Configuration

Deployment paths rely on a `.env` file located in their respective directories (`k8s/.env`, `cloudrun/.env`, `aws-lambda/.env`). These files are ignored by Git.

The `.env` file and the necessary Google Service Account (GSA) are created and configured using the `gas-fakes` CLI:
1. **Initialize**: Run `gas-fakes init` to set up the project structure and **automatically create the required Google Service Account**. 
2. **Authenticate**: Run `gas-fakes auth` to configure the necessary GCP credentials and project settings.

For more details on setting up the base environment, refer to the documentation in the [gas-fakes](https://github.com/brucemcpherson/gas-fakes) repository.

---

## 1. Kubernetes (GKE) Deployment

The Kubernetes path uses **GKE Autopilot** and **Workload Identity** to securely authenticate the container.

### Cluster Management
```bash
cd k8s
./manage-cluster.sh up   # Create GKE Autopilot cluster
./manage-cluster.sh down # Delete cluster when finished
```

### Deploying the Job
```bash
cd k8s
./deploy-k8s.sh
```

---

## 2. Cloud Run Deployment

The Cloud Run path is ideal for serverless execution of short-lived tasks.

```bash
cd cloudrun
./deploy-cloudrun.sh
```

---

## 3. AWS Lambda Deployment (Cross-Cloud)

This path runs your GAS container on AWS while securely accessing Google Workspace via **Workload Identity Federation (WIF)**—no service account keys required.

### One-time Secret Setup
To allow Google Cloud Build to push images to your AWS registry, you must store your AWS keys in Google Secret Manager:
```bash
cd aws-lambda
./setup-gcp-secrets.sh
```

### Deploying the Function
The `deploy-lambda.sh` script automates the entire cross-cloud handshake:
1. **Builds** the image via Google Cloud Build and **pushes** it directly to AWS ECR (no local Docker required).
2. **Configures WIF** in GCP to trust your AWS account.
3. **Deploys** the Lambda function and configures all environment variables.
4. **Invokes** the function and **tails the logs** to your terminal.

```bash
cd aws-lambda
./deploy-lambda.sh
```

---

## Project Structure

- `k8s/`, `cloudrun/`, `aws-lambda/`: Platform-specific configuration and deployment scripts.
- `containerrun.js`: The entry point for the container. It detects the environment (e.g., Lambda) to handle process lifecycle correctly.
- `example.js`: The core logic using `@mcpher/gas-fakes`. In this example, it identifies duplicate files on Google Drive. 
- `Dockerfile`: Multi-stage build to package the Node.js application.

## How it Works

The `@mcpher/gas-fakes` library provides global objects like `DriveApp` and `SpreadsheetApp` that mimic the GAS environment. It uses the ambient credentials of the environment (GKE Workload Identity, Cloud Run Service Account, or AWS WIF) to interact with live Google APIs.
