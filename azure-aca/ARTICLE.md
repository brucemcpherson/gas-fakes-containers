# Apps Script Beyond the Browser: Choosing Your Runtime Environment

Google Apps Script (GAS) is the quintessential "low-code" platform, but its growth path often leads developers out of the browser and into the cloud. The primary driver is almost always the **execution timeout**—the 6-minute wall that standard Apps Script cannot climb.

Using the [`@mcpher/gas-fakes`](https://www.npmjs.com/package/@mcpher/gas-fakes) library, you can run native Apps Script code across a spectrum of environments. Here is how they contrast, from the standard IDE to the deep cloud.

## 1. Apps Script IDE (The Default)
The built-in browser-based editor is where most scripts begin.
*   **Best for:** Simple triggers, UI-bound scripts (Sidebars/Dialogs), and quick automation.
*   **Pros:** Zero setup; built-in triggers; easy sharing.
*   **Cons:** **6-minute hard timeout**; no access to the vast Node.js (NPM) ecosystem; limited version control.

## 2. Local Environment (The Workbench)
Running Apps Script locally via Node.js and `gas-fakes` is the bridge between simple scripting and professional software engineering.
*   **Best for:** Development, complex debugging, and one-off administrative tasks.
*   **Pros:** Unlimited runtime; use your favorite IDE (VS Code); full Git integration; access to NPM packages.
*   **Cons:** Not "always-on"; requires local machine to be running or a manual trigger.

## 3. Google Cloud Run (The Serverless Sweet Spot)
The most natural cloud progression for GAS logic.
*   **Best for:** Production tasks that take up to 60 minutes.
*   **Pros:** Fast setup; native GCP identity (no complex WIF setup); scales to zero when not in use.
*   **Cons:** 60-minute limit for services; cold starts can occasionally impact time-sensitive triggers.

## 4. Google Kubernetes Engine / GKE (The Powerhouse)
Total control over the container lifecycle.
*   **Best for:** High-volume pipelines or long-running background workers.
*   **Pros:** Truly unlimited runtime; robust networking and storage options.
*   **Cons:** High management overhead; complex manifest configuration.

## 5. AWS Lambda (The Event-Driven Specialist)
For teams deeply invested in the Amazon ecosystem.
*   **Best for:** Automation triggered by AWS events (e.g., file arriving in S3).
*   **Pros:** High reliability; extremely cost-effective for short, frequent tasks.
*   **Cons:** **15-minute hard timeout**; requires Workload Identity Federation (WIF) setup to talk to Google.

## 6. Azure Container Apps Jobs (The Marathon Runner)
Azure’s solution for serverless tasks that need to run for a very long time.
*   **Best for:** Massive data migrations or drive-wide scans.
*   **Pros:** **24-hour execution window**; serverless scaling.
*   **Cons:** Requires a custom **Identity Bridge** (provided in this project) to bypass Azure's metadata service limitations with the Google SDK.

---

## Comparison Matrix

| Environment | Timeout | Setup | NPM Support | Auth Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **Apps Script IDE** | 6 mins | None | No | Native |
| **Local Node.js** | Unlimited | Easy | Yes | Local User/ADC |
| **Cloud Run** | 60 mins | Medium | Yes | Service Account |
| **GKE** | Unlimited | High | Yes | Workload Identity |
| **AWS Lambda** | 15 mins | Medium | Yes | WIF |
| **Azure ACA** | **24 hours** | Medium | Yes | WIF + Bridge |

---

## Summary: Which to Choose?
- **Need to process a few rows?** Stay in the **Apps Script IDE**.
- **Developing or debugging complex logic?** Run it **Locally**.
- **A task takes 10 minutes?** Use **Cloud Run** or **AWS Lambda**.
- **A task takes 10 hours?** Use **Azure Container Apps** or **GKE**.

The implementation for all these paths—including the necessary cross-cloud security handshakes—is available in the [gas-fakes-containers repository](https://github.com/brucemcpherson/gas-fakes-containers).
