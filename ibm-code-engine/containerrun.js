import { writeFile } from 'fs/promises';

/**
 * IBM App ID Bridge: 
 * We use IBM App ID (client_credentials) to fetch an OIDC id_token.
 * App ID id_tokens have a proper `aud` claim (= the App ID clientId)
 * which Google Workload Identity Federation requires to validate the token.
 * 
 * The raw IBM IAM Service ID access tokens do NOT have an `aud` claim
 * and therefore cannot be used directly with Google WIF.
 */
const fetchIBMToken = async () => {
  const oauthUrl = process.env.IBM_APP_ID_OAUTH_URL;
  const clientId = process.env.IBM_APP_ID_CLIENT_ID;
  const clientSecret = process.env.IBM_APP_ID_SECRET;

  if (!oauthUrl || !clientId || !clientSecret) {
    console.log('--- Skip IBM App ID Token Fetch (IBM_APP_ID_OAUTH_URL/CLIENT_ID/SECRET missing) ---');
    return;
  }

  console.log('--- Fetching IBM App ID OIDC Token ---');
  try {
    // App ID client_credentials flow with response_type=id_token
    // This issues a JWT id_token with aud=clientId, which Google WIF can validate
    const params = new URLSearchParams();
    params.append('grant_type', 'client_credentials');
    params.append('response_type', 'cloud_iam id_token');

    const tokenUrl = `${oauthUrl}/token`;
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');

    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': `Basic ${credentials}`
      },
      body: params
    });

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Failed to fetch App ID token: ${response.statusText} - ${errText}`);
    }

    const data = await response.json();

    // Use the id_token which has the proper `aud` claim for Google WIF
    const subjectToken = data.id_token || data.access_token;

    if (!subjectToken) {
      throw new Error('IBM App ID did not return any token.');
    }

    await writeFile('/tmp/ibm-token.json', JSON.stringify({
      access_token: subjectToken
    }));

    console.log('--- IBM Token saved to /tmp/ibm-token.json ---');
  } catch (error) {
    console.error('--- Failed to fetch IBM App ID Token ---');
    console.error(error);
  }
};

// Initial setup before logic imports
await fetchIBMToken();

// Now import the logic which depends on the file above
const { mainExample } = await import('./example.js');

const runJob = async () => {
  process.stdout.write('--- Starting IBM Code Engine Job Execution ---\n');
  console.log('--- Starting IBM Code Engine Job Execution ---');

  // set this to maximum amount of files to look at for testing - default is Infinity
  const max = 1000;
  try {
    await mainExample(max);

    console.log('--- Test execution completed successfully ---');
    process.stdout.write('--- Test execution completed successfully ---\n');
    process.exit(0);
  } catch (error) {
    console.error('--- Test execution failed ---');
    console.error(error);
    process.stdout.write('--- Test execution failed ---\n');
    process.exit(1);
  }
};

runJob();
