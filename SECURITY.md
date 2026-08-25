# Security policy

Blind Way handles location, emergency images, authentication tokens, and push-notification identifiers. Do not open a public issue containing a vulnerability, credential, personal data, or production endpoint.

## Reporting

Use GitHub's private vulnerability reporting feature for this repository. Include the affected component, reproduction steps, potential impact, and a safe proof of concept. If private reporting has not been enabled by the repository owner, contact the owner privately before disclosing details.

## Supported version

Security fixes target the latest `main` branch until formal releases and a version-support policy are published.

## Deployment responsibilities

Operators must restrict Firebase client API keys, rotate exposed credentials, keep cloud audit logs enabled, review server-locked role mappings, and test Firebase Authentication, FCM, S3, DynamoDB, and API authorization before any field deployment.
