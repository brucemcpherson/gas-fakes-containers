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
| **[Cloud Run + MS Graph](./cloudrun-msgraph)** | 60 mins | Google Cloud | Microsoft Graph Integration | Service Account + JWT Cache |
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

## 3. Google Cloud Run + MS Graph Deployment
Integrating Microsoft Graph (OneDrive/SharePoint) natively within Cloud Run jobs using GCP Secret Manager.
- **Pros:** Access Microsoft resources seamlessly using locally cached tokens; native GCP identity.
- **Usage:**
  ```bash
  cd cloudrun-msgraph
  ./setup-gcp-secrets.sh # One-time
  ./deploy-cloudrun.sh
  ```

---

## 4. Google Kubernetes Engine (GKE)
Total control over the container lifecycle for high-volume pipelines.
- **Pros:** Truly unlimited runtime; GKE Autopilot management.
- **Usage:**
  ```bash
  cd k8s
  ./manage-cluster.sh up
  ./deploy-k8s.sh
  ```

---

## 5. AWS Lambda Deployment (Cross-Cloud)
For teams deeply invested in the Amazon ecosystem or event-driven automation.
- **Pros:** High reliability; extremely cost-effective.
- **Usage:**
  ```bash
  cd aws-lambda
  ./setup-gcp-secrets.sh # One-time
  ./deploy-lambda.sh
  ```

---

## 6. Azure Container Apps (ACA) Jobs
The best solution for serverless tasks that need to run for up to 24 hours.
- **Pros:** 24-hour execution window; serverless scaling.
- **Usage:**
  ```bash
  cd azure-aca
  ./setup-azure-secrets.sh # One-time
  ./deploy-aca.sh
  ```

---

## 7. IBM Cloud Code Engine
Compute-intensive GAS tasks that benefit from generous free tiers.
- **Pros:** 24-hour runtime; extremely high memory/CPU limits.
- **Usage:**
  ```bash
  cd ibm-code-engine
  ./setup-ibm-secrets.sh # One-time
  ./deploy-ibm.sh
  ```

---

## 8. Fly.io Machines
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

## <img src="https://github.com/brucemcpherson/gas-fakes-containers/blob/main/logo.png" alt="gas-fakes logo" width="50" align="top"> Further Reading

## Watch the video

[![Watch the video](introvideo.png)](https://youtu.be/oEjpIrkYpEM)

## Read more docs

- [gas fakes intro video](https://youtu.be/oEjpIrkYpEM)
- [getting started](https://github.com/brucemcpherson/gas-fakes/blob/main/GETTING_STARTED.md) - how to handle authentication for restricted scopes.
- [readme](https://github.com/brucemcpherson/gas-fakes/blob/main/README.md)
- [gas fakes cli](https://github.com/brucemcpherson/gas-fakes/blob/main/gas-fakes-cli.md)
- [ksuite as a back end](https://github.com/brucemcpherson/gas-fakes/blob/main/ksuite_poc.md)
- [msgraph as a back end](https://github.com/brucemcpherson/gas-fakes/blob/main/msgraph.md)
- [gas-fakes in serverless containers](https://docs.google.com/presentation/d/1JlXF9T--DD4ERHopyP3WyAMhjRCxxHblgCP5ynxaJ3k/edit?usp=sharing)
- [apps script - a lingua franca for workspace platforms](https://ramblings.mcpher.com/apps-script-a-lingua-franca/)
- [Apps Script: A ‘Lingua Franca’ for the Multi-Cloud Era](https://ramblings.mcpher.com/apps-script-with-ksuite/)
- [running gas-fakes on google cloud run](https://github.com/brucemcpherson/gas-fakes-containers)
- [running gas-fakes on google kubernetes engine](https://github.com/brucemcpherson/gas-fakes-containers)
- [running gas-fakes on Amazon AWS lambda](https://github.com/brucemcpherson/gas-fakes-containers)
- [running gas-fakes on Azure ACA](https://github.com/brucemcpherson/gas-fakes-containers)
- [Yes – you can run native apps script code on Azure ACA as well!](https://ramblings.mcpher.com/yes-you-can-run-native-apps-script-code-on-azure-aca-as-well/)
- [Yes – you can run native apps script code on AWS Lambda!](https://ramblings.mcpher.com/apps-script-on-aws-lambda/)
- [initial idea and thoughts](https://ramblings.mcpher.com/a-proof-of-concept-implementation-of-apps-script-environment-on-node/)
- [Inside the volatile world of a Google Document](https://ramblings.mcpher.com/inside-the-volatile-world-of-a-google-document/)
- [Apps Script Services on Node – using apps script libraries](https://ramblings.mcpher.com/apps-script-services-on-node-using-apps-script-libraries/)
- [Apps Script environment on Node – more services](https://ramblings.mcpher.com/apps-script-environment-on-node-more-services/)
- [Turning async into synch on Node using workers](https://ramblings.mcpher.com/turning-async-into-synch-on-node-using-workers/)
- [All about Apps Script Enums and how to fake them](https://ramblings.mcpher.com/all-about-apps-script-enums-and-how-to-fake-them/)
- [sandbox](https://github.com/brucemcpherson/gas-fakes/blob/main/sandbox.md)
- [senstive scopes](https://github.com/brucemcpherson/gas-fakes/blob/main/senstive_scopes.md)
- [using apps script libraries with gas-fakes](https://github.com/brucemcpherson/gas-fakes/blob/main/libraries.md)
- [how libhandler works](https://github.com/brucemcpherson/gas-fakes/blob/main/libhandler.md)
- [article:using apps script libraries with gas-fakes](https://ramblings.mcpher.com/how-to-use-apps-script-libraries-directly-from-node/)
- [sensitive scopes with local authentication](https://github.com/brucemcpherson/gas-fakes/blob/main/senstive_scopes.md)
- [sharing cache and properties between gas-fakes and live apps script](https://ramblings.mcpher.com/sharing-cache-and-properties-between-gas-fakes-and-live-apps-script/)
- [gas-fakes-cli now has built in mcp server and gemini extension](https://ramblings.mcpher.com/gas-fakes-cli-now-has-built-in-mcp-server-and-gemini-extension/)
- [gas-fakes CLI: Run apps script code directly from your terminal](https://ramblings.mcpher.com/gas-fakes-cli-run-apps-script-code-directly-from-your-terminal/)
- [How to allow access to sensitive scopes with Application Default Credentials](https://ramblings.mcpher.com/how-to-allow-access-to-sensitive-scopes-with-application-default-credentials/)
- [Supercharge Your Google Apps Script Caching with GasFlexCache](https://ramblings.mcpher.com/supercharge-your-google-apps-script-caching-with-gasflexcache/)
- [Fake-Sandbox for Google Apps Script: Granular controls.](https://ramblings.mcpher.com/fake-sandbox-for-google-apps-script-granular-controls/)
- [A Fake-Sandbox for Google Apps Script: Securely Executing Code Generated by Gemini CLI](https://ramblings.mcpher.com/gas-fakes-sandbox/)
- [Power of Google Apps Script: Building MCP Server Tools for Gemini CLI and Google Antigravity in Google Workspace Automation](https://medium.com/google-cloud/power-of-google-apps-script-building-mcp-server-tools-for-gemini-cli-and-google-antigravity-in-71e754e4b740)
- [A New Era for Google Apps Script: Unlocking the Future of Google Workspace Automation with Natural Language](https://medium.com/google-cloud/a-new-era-for-google-apps-script-unlocking-the-future-of-google-workspace-automation-with-natural-a9cecf87b4c6)
- [Next-Generation Google Apps Script Development: Leveraging Antigravity and Gemini 3.0](https://medium.com/google-cloud/next-generation-google-apps-script-development-leveraging-antigravity-and-gemini-3-0-c4d5affbc1a8)
- [Modern Google Apps Script Workflow Building on the Cloud](https://medium.com/google-cloud/modern-google-apps-script-workflow-building-on-the-cloud-2255dbd32ac3)
- [Bridging the Gap: Seamless Integration for Local Google Apps Script Development](https://medium.com/@tanaike/bridging-the-gap-seamless-integration-for-local-google-apps-script-development-9b9b973aeb02)
- [Next-Level Google Apps Script Development](https://medium.com/google-cloud/next-level-google-apps-script-development-654be5153912)
- [Secure and Streamlined Google Apps Script Development with gas-fakes CLI and Gemini CLI Extension](https://medium.com/google-cloud/secure-and-streamlined-google-apps-script-development-with-gas-fakes-cli-and-gemini-cli-extension-67bbce80e2c8)
- [Secure and Conversational Google Workspace Automation: Integrating Gemini CLI with a gas-fakes MCP Server](https://medium.com/google-cloud/secure-and-conversational-google-workspace-automation-integrating-gemini-cli-with-a-gas-fakes-mcp-0a5341559865)
- [A Fake-Sandbox for Google Apps Script: A Feasibility Study on Securely Executing Code Generated by Gemini CL](https://medium.com/google-cloud/a-fake-sandbox-for-google-apps-script-a-feasibility-study-on-securely-executing-code-generated-by-cc985ce5dae3)

