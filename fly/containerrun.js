import { writeFile } from 'fs/promises';
import http from 'http';

/**
 * Fly.io Bridge:
 * Fly.io exposes its internal Machines API via a Unix socket at `/.fly/api`.
 * We must request an OIDC token from `http://localhost/v1/tokens/oidc`.
 */
const fetchFlyToken = async () => {
  const audience = process.env.FLY_OIDC_AUD;

  if (!audience) {
    console.log('--- Skip Fly.io Token Fetch (FLY_OIDC_AUD missing) ---');
    return;
  }

  console.log('--- Fetching Fly.io OIDC Token ---');
  try {
    const token = await new Promise((resolve, reject) => {
      const payload = JSON.stringify({ aud: audience });
      const req = http.request({
        socketPath: '/.fly/api',
        path: '/v1/tokens/oidc',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload)
        }
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try {
              const parsed = JSON.parse(data);
              // The Fly API returns a JSON field named "oidc_token" or similar, 
              // but often even if the token is literal, we should handle if it is wrapped.
              // We'll extract either a field we're looking for, or fallback to data directly.
              resolve(parsed.oidc_token || parsed.token || data);
            } catch (e) {
              // If it's not JSON, assume raw text
              resolve(data);
            }
          } else {
            reject(new Error(`Failed to fetch Fly.io token: ${res.statusCode} - ${data}`));
          }
        });
      });

      req.on('error', reject);
      req.write(payload);
      req.end();
    });

    if (!token) {
      throw new Error('Fly.io did not return any token.');
    }

    // Google expects a JSON file with an `access_token` key but value must be JUST the token string.
    await writeFile('/tmp/fly-token.json', JSON.stringify({
      access_token: typeof token === 'string' ? token.trim() : String(token).trim()
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
