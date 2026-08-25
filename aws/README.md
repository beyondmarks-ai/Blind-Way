# AWS + Google Cloud deployment

The runtime is intentionally split across clouds:

- API Gateway, Lambda, DynamoDB, SQS, Secrets Manager, and CloudWatch run on AWS.
- Lambda uses keyless Google Workload Identity Federation to call Vertex AI Gemini and Firebase Cloud Messaging.
- Sarvam Bulbul v3 stays behind the authenticated AWS API; its key is held in Secrets Manager.
- Firebase Authentication provides phone OTP and API Gateway validates Firebase ID tokens natively.

Run `deploy.ps1` after authenticating both `aws` and `gcloud`. The script builds the Lambda bundle, creates the keyless federation, deploys the stack, and prints `API_BASE_URL` for the Flutter release build.
