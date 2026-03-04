import { writeFile } from 'fs/promises';

/**
 * Fly.io Bridge:
 * Fly.io injects an internal API at http://_api.internal:4280. We can fetch
 * an OIDC token from /v1/tokens/oidc with the expected audience.
 */
const fetchFlyToken = async () => {
  const audience = process.env.FLY_OIDC_AUD;

  if (!audience) {
    console.log('--- Skip Fly.io Token Fetch (FLY_OIDC_AUD missing) ---');
    return;
  }

  console.log('--- Fetching Fly.io OIDC Token ---');
  try {
    const tokenUrl = `http://_api.internal:4280/v1/tokens/oidc?aud=${encodeURIComponent(audience)}`;
    const response = await fetch(tokenUrl);

    if (!response.ok) {
      const errText = await response.text();
      throw new Error(`Failed to fetch Fly.io token: ${response.statusText} - ${errText}`);
    }

    const token = await response.text();

    if (!token) {
      throw new Error('Fly.io did not return any token.');
    }

    await writeFile('/tmp/fly-token.json', JSON.stringify({
      access_token: token
    }));

    console.log('--- Fly.io Token saved to /tmp/fly-token.json ---');
  } catch (error) {
    console.error('--- Failed to fetch Fly.io Token ---');
    console.error(error);
  }
};

// Initial setup before logic imports
await fetchFlyToken();

// Now import the logic which depends on the file above
const { mainExample } = await import('./example.js');

const runJob = async () => {
  process.stdout.write('--- Starting Fly.io Machine Job Execution ---\n');
  console.log('--- Starting Fly.io Machine Job Execution ---');

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
