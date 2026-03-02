import { writeFile } from 'fs/promises';

const fetchAzureToken = async () => {
  const endpoint = process.env.IDENTITY_ENDPOINT;
  const header = process.env.IDENTITY_HEADER;
  const clientId = process.env.AZURE_CLIENT_ID;
  
  if (!endpoint || !header) {
    console.log('--- Skip Azure Token Fetch (Not in ACA or Identity not assigned) ---');
    return;
  }

  console.log('--- Fetching Azure Managed Identity Token ---');
  try {
    // We request a token for the Google STS audience
    const audience = 'api://AzureADTokenExchange';
    const url = `${endpoint}?api-version=2019-08-01&resource=${audience}&client_id=${clientId}`;
    
    const response = await fetch(url, {
      headers: { 'X-IDENTITY-HEADER': header }
    });
    
    if (!response.ok) {
      throw new Error(`Failed to fetch Azure token: ${response.statusText}`);
    }
    
    const data = await response.text();
    await writeFile('/tmp/azure-token.json', data);
    console.log('--- Azure Token saved to /tmp/azure-token.json ---');
  } catch (error) {
    console.error('--- Failed to fetch Azure Token ---');
    console.error(error);
  }
};

// Initial setup before logic imports
await fetchAzureToken();

// Now import the logic which depends on the file above
const { mainExample } = await import('./example.js');

const runJob = async () => {
  process.stdout.write('--- Starting Azure Container App Job Execution ---\n');
  console.log('--- Starting Azure Container App Job Execution ---');
  
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