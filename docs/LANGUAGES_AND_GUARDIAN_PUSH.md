# Voice languages and guardian notifications

Updated 10 November 2026.

## Choose the voice language

Open **Settings > Voice response language**. The app saves the choice locally across restarts and sign-out. An explicit choice controls AI answers and automatic scene updates, including answers recalling conversations in a different language. **Automatic** follows spoken questions; with no spoken question, Live starts in English. Language changes refresh the model inside the active connection, preserve the camera and microphone, and resume automatic descriptions. A language change deliberately cancels any unfinished reply; its late audio is discarded.

The list includes English (India and US), Hindi, Bengali, Marathi, Tamil, Telugu, Arabic, Dutch, French, German, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Romanian, Russian, Spanish, Thai, Turkish, Ukrainian and Vietnamese through Gemini Live. Gujarati, Kannada, Malayalam, Odia and Punjabi are also enabled in Gemini Live after real model checks generated a response and PCM audio in each language. Sarvam remains an alternative through **Start assistance / Ask a question** for its supported languages. Quality can vary; these checks do not establish equal accuracy or pronunciation across languages.

This changes AI voice responses, not all interface labels or system announcements. Local reading currently supports Latin-script OCR; additional scripts are not bundled. Android speech for international text reading depends on installed voice packs.

## Set up a guardian

1. Install Blind Way on the guardian's Android phone and sign in as **I am a trusted contact**.
2. Allow Android notifications. Keep internet available and allow the app to run without restrictive battery settings.
3. On the assistance user's phone, open **Trusted people > Create secure invite**.
4. Redeem that code in **Trusted people** on the guardian's phone before it expires (10 minutes).
5. On the guardian's phone, tap **Settings > Test notification for my account**. This explicitly labelled test targets that account's devices only. It does not create an SOS or notify another account.

A real SOS is saved, then queued for high-priority Firebase Cloud Messaging delivery to currently linked guardians. The notification opens Blind Way; the existing emergency screen shows available GPS location, scene context and snapshot. Coordinates are retrieved with authenticated access rather than exposed in the push payload. Five-second foreground polling recovers missed alerts. No real guardian alert was sent during configuration.

Push is not guaranteed: Android permissions, force-stop, battery restrictions, network access and expired device tokens can prevent delivery. SMS escalation is separate and is not enabled by configuring FCM. At least one linked guardian with a registered notification token is required.

## Keyless cloud configuration

Firebase/GCP project: `project-8eeef9d3-080a-4f49-95e` (896452575262).

The Azure Functions managed identity exchanges its Azure token with Google STS, then impersonates `blindway-notifications@project-8eeef9d3-080a-4f49-95e.iam.gserviceaccount.com`. The service account has `roles/firebasecloudmessaging.admin`. No service-account private key is generated or placed in the APK.

Workload identity provider:
`projects/896452575262/locations/global/workloadIdentityPools/blindway-azure/providers/azure-function`.

The provider maps `google.subject=assertion.oid` and restricts tokens to Azure tenant `16b09027-c852-4980-9d01-bd9ffc9b1276` and function identity `9cf435e8-a57a-4d2f-9918-b500aac4a3fa`. Its allowed audience is exactly `https://management.azure.com` (no trailing slash), matching the actual managed identity token. Only that principal has `roles/iam.workloadIdentityUser` on the notification service account. Enabled APIs: FCM, STS and IAM Credentials.

Azure app settings are `FIREBASE_PROJECT_ID`, `FCM_WIF_PROVIDER`, and `FCM_SERVICE_ACCOUNT`. `infra/deploy.ps1` passes these nonsecret settings to Bicep. Recreating the Azure managed identity requires updating the provider restriction and service-account binding. Legacy Notification Hubs are not used by this delivery path.

Run `infra/validate-push.ps1` with an authorized Azure CLI login. It calls a function-key-protected endpoint, which sends `validate_only=true` to FCM. Successful validation proves the deployed identity exchange and Firebase send permission without delivering a notification. The script does not print the function key.

`guardian-push` retries failed deliveries up to five times, with a 10-second retry visibility delay and up to two-second idle polling. Failed messages then remain in `guardian-push-poison` for operator investigation. Workers recheck guardian links and alert state before delivery. Retrying an SOS with the same idempotency key repairs an unsuccessful queue submission. A device token is transferred when the installation changes account; sign-out invalidates the installation token when online.

## Verification

- Flutter: 53 tests passed, two pre-existing tests skipped (including hardware-dependent coverage).
- Backend: 41 tests passed; covers scoped token exchange, token caching, validation without delivery, token ownership, self-test isolation, retired-token handling, cancelled-alert suppression and SOS scheduling retry.
- Live relay: 22 tests passed; every offered Live language code passes protocol validation.
- Real Vertex checks with synthetic Hindi memory returned English, Tamil and French correctly, with PCM audio generated for each. This is representative testing, not acoustic validation of every language.
- Firebase CLI 15.35.0 listed the Android app and downloaded SDK configuration, which matched the local `google-services.json`. Its ADC invocation requires `GOOGLE_CLOUD_QUOTA_PROJECT` set to this project and a task-specific `XDG_CONFIG_HOME` when the normal Firebase CLI login belongs to another account.
- Cloud Run revision: `blindway-live-00006-6jb`.
- Deployed Azure-to-GCP-to-FCM validation passed: `configured=true`, `validated=true`, `delivered=false`. No real notification was sent by this check. `GUARDIAN_PUSH_CONFIGURED=true` is enabled in the APK build configuration.
- ADB did not show a connected phone during this update. Installation, guardian background delivery and listening tests on the physical phone remain to be checked.
- APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk`, version code 12, built successfully. SHA-256: `74175ef1d4c49bf4b666aa343ff2f447740a9596b91b40a465c3221c457344f7`. Build source/configuration matched the repository. Final FCM validation passed again after deployment.

References: [Gemini Live languages](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/live-api/configure-language-voice), [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api), [Workload identity federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds).
