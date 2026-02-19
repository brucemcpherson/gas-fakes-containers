import { mainExample } from './example.js';

const runJob = async () => {
  console.log('--- Starting Job Execution ---');
  // set this to maximum amount of files to look at for testing - default is Infinity
  const max = 1000
  try {
    await mainExample(max);
    console.log('--- Test execution completed successfully ---');
  } catch (error) {
    console.error('--- Test execution failed ---');
    console.error(error);
    throw error;
  }
};

// This is the "Official" Lambda entry point
export const handler = async (event) => {
  await runJob();
  return { statusCode: 200, body: "Done" };
};

// If running in Cloud Run, K8s, or Local (not Lambda)
// we execute immediately
if (!process.env.AWS_LAMBDA_FUNCTION_NAME) {
  runJob().then(() => process.exit(0)).catch(() => process.exit(1));
}
