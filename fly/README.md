# Gas Fakes on Fly.io Machines

This directory contains the scripts to deploy the `gas-fakes` testing container to **Fly.io**.

Fly.io provides fast, lightweight Firecracker microVMs ("Machines"). It natively supports **OpenID Connect (OIDC)** tokens which can be fetched directly from within the Machine and securely exchanged with Google Workload Identity Federation (WIF).

## 1. Prerequisites & Signup

1.  **Fly Account**: Sign up at [fly.io](https://fly.io/). Note that Fly requires you to add a credit card to your account (Dashboard -> Billing) to launch Machines, even if you stay within the free tier.
2.  **Fly CLI (`fly`)**: Install the Fly Command Line Interface.
    *   **Mac**: `brew install flyctl` or `curl -L https://fly.io/install.sh | sh`
    *   Initialize it: run `fly auth login` to authenticate in your browser.
3.  **jq**: Ensure `jq` is installed as the deploy script uses it.
4.  **Google Cloud CLI (`gcloud`)**: Must be configured and logged in to your GCP project.

## 2. Configuration & Initialization

If you do not have a `.env` file in the `fly/` directory, the deploy script will automatically run **`npx gas-fakes init`** and **`npx gas-fakes auth`** for you. This will interactively guide you through:
- Creating a GCP Service Account.
- Enabling required Google APIs.
- Setting up your `.env` file with `GOOGLE_CLOUD_PROJECT`, `GOOGLE_SERVICE_ACCOUNT_NAME`, and other required variables (like Upstash keys).

Alternatively, you can manually copy an existing `.env` file into the `fly/` directory. Ensure it has:
1.  **`GOOGLE_CLOUD_PROJECT`**: Your GCP Project ID.
2.  **`GOOGLE_SERVICE_ACCOUNT_NAME`**: The name of the GCP Service Account (e.g., `gas-fakes-sa`).
3.  **Upstash** (optional): `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`. Upstash is an optional dropin replacement gas-fakes can use instead of Apps Script Cache and Properties service.

## 3. Deployment

Simply run the deploy script. It will automatically create a Fly app (if none exists), configure Google WIF to trust `https://fly.io/oidc`, securely push your `.env` variables as Fly secrets, and then build and execute the container.

```bash
cd fly
chmod +x deploy-fly.sh
./deploy-fly.sh
```

## How It Works

1.  **WIF Setup**: `deploy-fly.sh` automatically configures a Google WIF provider with `ISSUER_URI=https://fly.io/oidc`.
2.  **Audience mapping**: The script constructs the exact expected audience URL for the WIF provider and saves it to the Fly app as the `FLY_OIDC_AUD` secret.
3.  **Ad-Hoc Machines**: The script runs `fly machine run . --rm --detach=false`. This invokes Fly's builder to package the container and run it on a temporary microVM in London (`lhr`). The `--rm` flag ensures the VM is destroyed once the script completes.
4.  **Token Fetching**: Inside the container, `containerrun.js` calls Fly's internal API (`http://_api.internal:4280/v1/tokens/oidc`) requesting an OIDC token with the exact `aud` claim matching the Google WIF provider.
5.  **Secure Execution**: The standard Google Auth library seamlessly exchanges this `id_token` for temporary GCP credentials. The test suite runs securely and logs stream directly to your terminal.
