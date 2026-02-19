# AWS Lambda Deployment (Cross-Cloud)

This directory contains experimental scripts for running your GAS containers on **AWS Lambda** while still accessing Google Workspace via **Workload Identity Federation**.

## Prerequisites
1. **AWS CLI** installed and configured (`aws configure`).
2. **Docker** running locally.
3. **IAM Permissions**: You need permissions to create ECR repositories, Lambda functions, and IAM Roles.

## The Strategy
1. **No Keys**: We do not use Google `.json` service account keys.
2. **WIF**: We use Google Cloud Workload Identity Federation. 
3. **Token Exchange**: When the container runs on AWS, the Google SDK detects the AWS environment, grabs the AWS identity token, and "trades" it for a temporary Google access token.

## How to use
1. Update the variables in `deploy-lambda.sh`.
2. Run `./deploy-lambda.sh`.
3. In the AWS Console, add your `.env` variables to the Lambda function's configuration.
4. Set `GOOGLE_APPLICATION_CREDENTIALS` to `/var/task/google-credentials.json` (this file is generated and baked into the image or mounted).

## Note on Timeouts
AWS Lambda has a hard maximum timeout of **15 minutes**. If your job takes longer, use GKE or Cloud Run instead.
