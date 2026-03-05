# Beyond the 6-Minute Wall: Running Google Apps Script Anywhere with Containers

Google Apps Script (GAS) is a developer's dream for quick automation within the Google Workspace ecosystem. It’s serverless, zero-config, and deeply integrated. However, as projects grow in complexity—processing thousands of Drive files, performing massive data migrations, or integrating complex NPM packages—developers inevitably hit the "6-minute wall."

When your logic outgrows the Apps Script IDE, the solution isn't to rewrite your code; it's to move it into a container.

Using the [`@mcpher/gas-fakes`](https://www.npmjs.com/package/@mcpher/gas-fakes) library, you can take your existing Apps Script logic and run it on almost any cloud platform, from Google Cloud and AWS to Azure, IBM, and Fly.io.

---

## The Core Challenge: Identity, Not Just Code

The hardest part of moving Apps Script into a container isn't simulating `DriveApp` or `SpreadsheetApp`; it's **Identity**. In the GAS IDE, your identity is "magic." You click "Authorize," and it just works. In a container—especially one running on another cloud—that magic disappears.

To solve this, we use a combination of **Domain-Wide Delegation (DWD)** and **Workload Identity Federation (WIF)** to achieve secure, keyless authentication.

### 1. The Foundation: Domain-Wide Delegation (DWD)
Before looking at clouds, we must understand how a "Robot" (a Service Account) gets permission to touch your data. 

In a Google Workspace environment, **Domain-Wide Delegation** is the "superpower" granted to a Google Service Account (GSA). A Workspace Admin explicitly trusts a specific Service Account to **impersonate** any user in the domain.

**Apps Script Native Permissions:**
All permissions (OAuth Scopes) are defined exactly where they would be in a standard script: the **`appsscript.json` manifest file**. When you initialize a project, the CLI reads these scopes. An administrator then adds these scopes to the Workspace Admin Console. Because the scopes are driven by the manifest, your container has exactly the same permissions as your script would—no more, no less.

### 2. Local Development: Keyless DWD & ADC
Running `gas-fakes` locally on your workbench provides two main paths for identity, both managed simply via the CLI command `gas-fakes auth`:

*   **Keyless DWD (The Default):** Performs the DWD handshake without needing a JSON key file. It's the most secure way to develop locally while acting as a Workspace user.
*   **ADC (The Fallback):** For developers without Workspace Admin privileges, `gas-fakes` supports **Application Default Credentials (ADC)** to use your personal Google identity for local testing.

### 3. Native Workload Identity (Cloud Run & GKE)
When running *inside* Google Cloud, Google handles identity natively. You attach the GSA to the service, and the container automatically fetches tokens from a local metadata server. No keys are ever handled by the developer.

### 4. Cross-Cloud: Workload Identity Federation (WIF)
How does an AWS Lambda function or an Azure Job prove its identity to Google? WIF replaces dangerous, long-lived JSON keys with a "Short-lived Token Exchange" handshake:

1.  **Generate Local Identity:** The container (on AWS, Azure, etc.) fetches its own "Identity Token" from its local cloud provider.
2.  **The Google Exchange:** The container sends this token to the **Google Security Token Service (STS)**.
3.  **Validation:** Google validates the token with the external provider.
4.  **Impersonation:** If valid, Google issues a temporary access token for the Google Service Account (GSA).

---

## The Architecture of Harmonization: How it All Fits Together

To run GAS logic in a container, we use a three-layer architecture. This system ensures that your core business logic remains "pure" while the underlying infrastructure handles the complexities of identity, networking, and platform-specific lifecycles.

### 1. The Core Logic (`example.js`)
This is where your actual Apps Script code lives. It looks and feels exactly like a standard script, using `DriveApp`, `SpreadsheetApp`, and all the normal Apps Script services so far implemented in gas-fakes. It is platform-agnostic; it only knows the Apps Script API. 

The example provided is a long running eample that checks your Drive for duplicate content and writes a summary to a google sheet. You can either use this (by substituting the id of one of your spreadsheets to summarize into) or replace with your own Apps Script code. The example also uses a live Apps Script library to show that even that is supported.

### 2. The Harmonizer (`@mcpher/gas-fakes`)
This is the invisible "magic" layer. It provides global objects that mimic the Apps Script environment. When your code calls `DriveApp.getFiles()`, the harmonizer intercepts this and uses the standard Google Node.js SDK to talk to the live Google APIs using whatever token is available in the environment.

### 3. The Entry Point (`containerrun.js`)
This is the "Platform Manager." It is the first thing that runs, and its implementation varies by platform:
*   **The Identity Bridge (Azure, IBM, Fly):** Fetches a local identity token and saves it to a temporary file before starting the script.
*   **The Runtime Manager (AWS Lambda):** Implements the Lambda Runtime API loop to handle invocations and prevent timeouts.
*   **The Simple Runner (Cloud Run & Local):** Immediately executes the logic using native or provided credentials.

### Component Interaction

| Step | Component | Action |
| :--- | :--- | :--- |
| **1. Start** | `containerrun.js` | Fetches platform-specific tokens or connects to Runtime API. |
| **2. Initialize** | `@mcpher/gas-fakes` | Globally defines `DriveApp`, `SpreadsheetApp`, etc. |
| **3. Execute** | `example.js` | Runs your business logic using the fake globals. |
| **4. Authenticate** | Harmonizer | Uses the token prepared in Step 1 to call real Google APIs. |
| **5. Finish** | `containerrun.js` | Reports success/failure and exits. |

---

## The Rosetta Stone of Runtimes

Each path in this repository includes a `deploy-*.sh` script that automates the entire lifecycle: building, identity setup, and execution.

| Need | Recommended Platform | Timeout | Identity Strategy |
| :--- | :--- | :--- | :--- |
| **Dev & Debugging** | **[Local](./local)** | Unlimited | Keyless DWD / ADC |
| **Standard Automation** | **[Cloud Run](./cloudrun)** | 60 mins | Native Service Account |
| **AWS Integration** | **[AWS Lambda](./aws-lambda)** | 15 mins | WIF |
| **Massive Data Jobs** | **[Azure ACA](./azure-aca)** | 24 hours | WIF + Identity Bridge |
| **High Resource/Free Tier** | **[IBM Code Engine](./ibm-code-engine)** | 24 hours | WIF + App ID |
| **Global Speed** | **[Fly.io](./fly)** | Unlimited | WIF + OIDC Tokens |

---

## Summary: Why this Matters

By containerizing your Apps Script logic and using Workload Identity Federation, you achieve **Keyless Authentication**. There are no secrets to rotate, no keys to steal, and the identity is tied directly to the running compute instance. 

Whether you are processing a few rows locally or running a 10-hour data migration on Azure, your business logic remains exactly the same. You finally gain the full power of the Node.js ecosystem and the reliability of enterprise cloud providers, all while breaking through the 6-minute wall.

***

*Explore the full source code and deployment guides at the [Google Apps Script Containers](https://github.com/brucemcpherson/gas-fakes-containers) repository.*
