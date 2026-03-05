# Google Apps Script Containers (Fakes)

This repository demonstrates how to run Google Apps Script (GAS) logic within containers across all major cloud providers. It utilizes the [`@mcpher/gas-fakes`](https://www.npmjs.com/package/@mcpher/gas-fakes) library to simulate the Apps Script environment (Drive, Sheets, etc.) in a Node.js runtime.

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

## Environment Configuration

Deployment paths rely on a `.env` file located in their respective directories. These files are ignored by Git.

The `.env` file and the necessary Google Service Account (GSA) are created and configured using the `gas-fakes` CLI:
1. **Initialize**: Run `gas-fakes init` to set up the project structure. 
2. **Authenticate**: Run `gas-fakes auth` to configure the necessary GCP credentials.

## Build Automation & Artifact Stores

A key principle of this project is that **you do not need Docker installed locally**. 

Instead, we use **Google Cloud Build** as a serverless build engine. Each deployment script (`deploy-*.sh`) submits the local source code to GCP, where:
1.  **Cloud Build** packages the code into a container image using the project's `Dockerfile`.
2.  The resulting image is stored in **Google Artifact Registry**.
3.  For Cross-Cloud paths (AWS, Azure, IBM), Cloud Build then securely **pushes** the image directly to the destination registry (e.g., AWS ECR or Azure ACR) using credentials stored in GCP Secret Manager.

This ensures builds are consistent, fast, and secure, regardless of your local machine's operating system or configuration.

---

## Supported Platforms Summary

| Environment | Timeout | Cloud Provider | Key Feature | Identity Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **[Local](./local)** | Unlimited | Local Machine | Best for Dev/Debug and sandboxing AI generated code | User Auth / ADC |
| **[Cloud Run](./cloudrun)** | 60 mins | Google Cloud | Native GCP Identity | Service Account |
| **[GKE](./k8s)** | Unlimited | Google Cloud | Total Control | Workload Identity |
| **[AWS Lambda](./aws-lambda)** | 15 mins | AWS | Event-Driven | Workload Identity Federation (WIF)|
| **[Azure ACA](./azure-aca)** | 24 hours | Microsoft Azure | Long-Running Tasks | WIF + Identity Bridge |
| **[IBM Code Engine](./ibm-code-engine)** | 24 hours | IBM Cloud | Generous Free Tier | WIF + App ID |
| **[Fly.io](./fly)** | Unlimited | Fly.io | Fast MicroVMs | WIF + OIDC Tokens |

---

## 1. Local Node.js Environment
Ideal for development, complex debugging, and one-off administrative tasks.
- **Pros:** Unlimited runtime; full IDE support; access to all NPM packages.
- **Usage:**
  ```bash
  cd local
  npm install
  node example.js
  ```

---

## 2. Google Cloud Run Deployment
The most natural cloud progression for GAS logic within the Google ecosystem.
- **Pros:** Fast setup; 60-minute timeout; native GCP identity.
- **Usage:**
  ```bash
  cd cloudrun
  ./deploy-cloudrun.sh
  ```

---

## 3. Google Kubernetes Engine (GKE)
Total control over the container lifecycle for high-volume pipelines.
- **Pros:** Truly unlimited runtime; GKE Autopilot management.
- **Usage:**
  ```bash
  cd k8s
  ./manage-cluster.sh up
  ./deploy-k8s.sh
  ```

---

## 4. AWS Lambda Deployment (Cross-Cloud)
For teams deeply invested in the Amazon ecosystem or event-driven automation.
- **Pros:** High reliability; extremely cost-effective.
- **Usage:**
  ```bash
  cd aws-lambda
  ./setup-gcp-secrets.sh # One-time
  ./deploy-lambda.sh
  ```

---

## 5. Azure Container Apps (ACA) Jobs
The best solution for serverless tasks that need to run for up to 24 hours.
- **Pros:** 24-hour execution window; serverless scaling.
- **Usage:**
  ```bash
  cd azure-aca
  ./setup-azure-secrets.sh # One-time
  ./deploy-aca.sh
  ```

---

## 6. IBM Cloud Code Engine
Compute-intensive GAS tasks that benefit from generous free tiers.
- **Pros:** 24-hour runtime; extremely high memory/CPU limits.
- **Usage:**
  ```bash
  cd ibm-code-engine
  ./setup-ibm-secrets.sh # One-time
  ./deploy-ibm.sh
  ```

---

## 7. Fly.io Machines
Fast, lightweight Firecracker microVMs that launch in seconds.
- **Pros:** Native OIDC support; globally distributed; unlimited runtime.
- **Usage:**
  ```bash
  cd fly
  ./deploy-fly.sh
  ```

---

## Project Structure

- `[platform]/`: Platform-specific configuration and deployment scripts.
- `containerrun.js`: Entry point that detects environment and handles process lifecycle.
- `example.js`: Core logic using `@mcpher/gas-fakes` (identifies duplicate files on Drive).
- `Dockerfile`: Multi-stage build to package the Node.js application.

## How it Works

The `@mcpher/gas-fakes` library provides global objects like `DriveApp` and `SpreadsheetApp` that mimic the GAS environment. It uses the ambient credentials of the environment (Workload Identity, Service Accounts, or WIF) to interact with live Google APIs securely.
