# Apps Script Beyond the Browser: Choosing Your Runtime Environment

In my previous explorations of this architecture—covering [AWS Lambda](https://github.com/brucemcpherson/gas-fakes), [Google Cloud Run](https://github.com/brucemcpherson/gas-fakes), and [Kubernetes](https://github.com/brucemcpherson/gas-fakes)—I demonstrated how to liberate native Apps Script from its original browser-based sandbox. 

By leveraging **Keyless DWD [^1]**, **Workload Identity Federation [^2]**, and the `gas-fakes` runtime, we can now execute Google-native logic across nearly any serverless platform. Today, I’m adding **Azure Container Apps (ACA)** to the list of supported environments, offering a massive execution window for high-intensity tasks.

### The Runtime Spectrum
Using the `@mcpher/gas-fakes` library, you can run the exact same Apps Script code across a variety of environments. Here is how they contrast with the standard IDE.



#### 1. Apps Script IDE (The Default)
The built-in browser-based editor is where most scripts begin.
* **Best for:** Simple triggers, UI-bound scripts (Sidebars/Dialogs), and quick automation.
* **Pros:** Zero setup; built-in triggers; easy sharing.
* **Cons:** 6-minute hard timeout; no access to the **NPM [^3]** ecosystem; limited version control.

#### 2. Local Environment (The Workbench)
Running Apps Script locally via **Node.js [^4]** and `gas-fakes` is the bridge between simple scripting and professional software engineering.
* **Best for:** Development, complex debugging, and one-off administrative tasks.
* **Pros:** Unlimited runtime; use VS Code; full Git integration; access to NPM packages.
* **Cons:** Not "always-on"; requires a local machine or manual trigger.

#### 3. Google Cloud Run (The Serverless Sweet Spot)
The most natural cloud progression for Apps Script logic.
* **Best for:** Production tasks that take up to 60 minutes.
* **Pros:** Fast setup; native **GCP [^5]** identity (no complex WIF setup); scales to zero when idle.
* **Cons:** 60-minute limit; cold starts can occasionally impact time-sensitive triggers.

#### 4. Google Kubernetes Engine / GKE (The Powerhouse)
Total control over the container lifecycle.
* **Best for:** High-volume pipelines or long-running background workers.
* **Pros:** Truly unlimited runtime; robust networking and storage options.
* **Cons:** High management overhead; complex manifest configuration.

#### 5. AWS Lambda (The Event-Driven Specialist)
For teams deeply invested in the Amazon ecosystem.
* **Best for:** Automation triggered by AWS events (e.g., file arriving in S3).
* **Pros:** High reliability; extremely cost-effective for short, frequent tasks.
* **Cons:** 15-minute hard timeout; requires **WIF [^2]** setup to communicate with Google.

#### 6. Azure Container Apps Jobs (The Marathon Runner)
Azure’s solution for serverless tasks that need to run for extended periods.
* **Best for:** Massive data migrations or Drive-wide security scans.
* **Pros:** **24-hour execution window**; serverless scaling.
* **Cons:** Requires a custom **Identity Bridge** (provided in this project) to bypass Azure's metadata service limitations when interacting with the Google SDK.

---

### Comparison Matrix

| Environment | Timeout | Setup | NPM Support | Auth Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **Apps Script IDE** | 6 mins | None | No | Native |
| **Local Node.js** | Unlimited | Easy | Yes | Keyless DWD / ADC [^6] |
| **Cloud Run** | 60 mins | Medium | Yes | Keyless DWD |
| **GKE** | Unlimited | High | Yes | Keyless DWD / WIF |
| **AWS Lambda** | 15 mins | Medium | Yes | WIF |
| **Azure ACA** | 24 hours | High | Yes | WIF + Identity Bridge |

---

### Summary: Which to Choose?

* **Need to process a few rows?** Stay in the Apps Script IDE.
* **Developing or debugging complex logic?** Run it **Locally**.
* **A task takes 10–15 minutes?** Use **Cloud Run** or **AWS Lambda**.
* **A task takes 10 hours?** Use **Azure Container Apps** or **GKE**.

All serverless options require different strategies for integrating authentication with Google Domain Wide Delegation. Azure is currently the most complex to configure, but I have automated the entire path—from environment setup and cloud build to final execution. 

The implementation for all these paths, including the necessary cross-cloud security handshakes, is available in the **gas-fakes-containers** repository.

**Links**
* [GitHub: gas-fakes](https://github.com/brucemcpherson/gas-fakes)
* [GitHub: gas-fakes-containers](https://github.com/brucemcpherson/gas-fakes-containers)

---

### Terminology Reference
[^1]: **DWD (Domain-Wide Delegation):** A feature that allows a service account to impersonate users to access data across a Google Workspace domain.
[^2]: **WIF (Workload Identity Federation):** A keyless authentication method that allows non-Google workloads (AWS, Azure, etc.) to securely access Google Cloud resources.
[^3]: **NPM (Node Package Manager):** The standard package manager for Node.js, allowing the use of millions of external libraries.
[^4]: **Node.js:** A JavaScript runtime that allows code to be executed outside of a web browser.
[^5]: **GCP (Google Cloud Platform):** The suite of cloud computing services provided by Google.
[^6]: **ADC (Application Default Credentials):** A strategy used by Google authentication libraries to automatically find credentials based on the environment context.