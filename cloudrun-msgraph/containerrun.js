import { mainExample } from './example.js';
import fs from 'fs';
import path from 'path';

const runJob = () => {
  console.log('--- Starting Cloud Run Job Execution ---');
  
  if (process.env.MSGRAPH_TOKEN_JWT) {
    console.log('--- Writing MS Graph Token Cache ---');
    const tokenPath = path.join(process.cwd(), '.msgraph-token.jwt');
    fs.writeFileSync(tokenPath, process.env.MSGRAPH_TOKEN_JWT);
  }

  // set this to maximum amount of files to look at for testing - default is Infinity
  const max = 1000
  try {
    mainExample(max);

    console.log('--- Test execution completed successfully ---');
    process.exit(0);
  } catch (error) {
    console.error('--- Test execution failed ---');
    console.error(error);
    process.exit(1); 
  }
};

runJob();