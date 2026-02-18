import { mainExample } from './example.js';

const runJob = () => {
  console.log('--- Starting Kubernetes Execution ---');
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