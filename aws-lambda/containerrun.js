import { mainExample } from './example.js';

const runJob = async () => {
  console.log('--- Starting Job Execution ---');
  const max = 1000;
  try {
    await mainExample(max);
    console.log('--- Job Completed Successfully ---');
  } catch (error) {
    console.error('--- Job Failed ---');
    console.error(error);
    throw error;
  }
};

/**
 * The "Official" Custom Runtime Logic for AWS Lambda
 * This prevents Init Timeouts and unwanted retries.
 */
const lambdaRuntimeLoop = async () => {
  const runtimeApi = process.env.AWS_LAMBDA_RUNTIME_API;
  
  while (true) {
    // 1. Tell Lambda we are ready and wait for a trigger
    const result = await fetch(`http://${runtimeApi}/2018-06-01/runtime/invocation/next`);
    const requestId = result.headers.get('lambda-runtime-aws-request-id');
    
    console.log(`--- Processing Lambda Request: ${requestId} ---`);
    
    try {
      // 2. Do the actual work (now in the 'Invoke' phase, not 'Init')
      await runJob();
      
      // 3. Tell Lambda we are finished
      await fetch(`http://${runtimeApi}/2018-06-01/runtime/invocation/${requestId}/response`, {
        method: 'POST',
        body: JSON.stringify({ success: true })
      });
    } catch (error) {
      // Report error to Lambda
      await fetch(`http://${runtimeApi}/2018-06-01/runtime/invocation/${requestId}/error`, {
        method: 'POST',
        body: JSON.stringify({ errorMessage: error.message, errorType: 'JobError' })
      });
    }
  }
};

// Execution logic based on environment
if (process.env.AWS_LAMBDA_RUNTIME_API) {
  console.log('--- Initializing Lambda Runtime ---');
  lambdaRuntimeLoop().catch(err => {
    console.error('Critical Runtime Error:', err);
    process.exit(1);
  });
} else {
  // Standard execution for Cloud Run, K8s, or Local
  runJob()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
}
