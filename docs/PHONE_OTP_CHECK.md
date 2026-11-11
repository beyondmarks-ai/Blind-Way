# Google phone OTP — 7 November 2026

Entra sign-in has been replaced by Google Firebase Authentication (Identity Platform) SMS OTP. The Android screen collects a role, name and Indian mobile number, sends a code, supports automatic Android verification and manual six-digit entry, and permits resend after 60 seconds. Cancellation invalidates late verification callbacks. Firebase's native SDK handles token persistence and refresh; UID/name/role metadata uses Flutter Secure Storage. Android backup is disabled. Old Entra credentials are removed on restoration/sign-out.

## Deployed configuration

- Google project: `project-8eeef9d3-080a-4f49-95e`, number `896452575262`.
- Firebase Android app: `1:896452575262:android:b98dce17cc34ba75272e0f`.
- Package: `ai.beyondmarks.blindway`.
- Phone provider enabled; SMS region allowlist: India (`IN`). Billing is enabled.
- Real app configuration is in ignored `android/app/google-services.json`. No Vertex credential, service-account private key or SMS bypass is included in the APK.
- Debug signing SHA-1: `10:85:A2:2E:17:25:D9:42:BE:A8:15:5F:56:D6:56:21:04:71:D9:F0`.
- Debug signing SHA-256: `5B:8B:8D:4B:22:22:15:9E:8E:7B:A6:47:61:F2:A7:5E:A9:40:5E:6F:FB:AD:26:74:39:17:ED:EB:28:44:60:D0`.
- Both fingerprints are registered in Firebase. Release or Play signing requires registering those certificates too.
- Azure API `blindway-api-win-d7ofaubf` and Cloud Run `blindway-live` now use `FIREBASE_PROJECT_ID`; their Entra settings were removed. Cloud Run revision: `blindway-live-00003-l9n`.

Both servers verify RS256 signatures using Google's fixed Secure Token JWKS endpoint, the project's issuer/audience, expiry, issue/authentication times, Firebase UID, phone provider and E.164 phone claim. Password, anonymous, custom-provider and old Entra tokens are not accepted. Existing profile-role and guardian authorization checks remain in place. Debug authentication remains disabled on deployed services.

## Install and check

Install `../Blind-Way-Phone-OTP.apk` from the workspace root (version code 4, ARM64 debug build). Select a role, enter a name and +91 mobile number, tap **Send OTP**, enter the received SMS code and tap **Verify and sign in**. A sideloaded APK may briefly open Google's reCAPTCHA verification page. Keep Google Play services enabled and internet available. Test automatic SMS verification, manual entry, a wrong code, resend, restarting the app, and sign-out on the actual phone.

Old Entra accounts are not automatically matched to a phone identity. Sign in again and re-establish guardian links. Existing records and the old tenant have not been deleted. Roles remain permanent after profile registration.

## Verification and limits

- Flutter analysis passed; 39 Flutter tests passed, including OTP failures, cancellation, duplicate automatic/manual completion, session restoration, refresh failure and sign-in UI interaction. One optional hardware test was skipped.
- 32 API tests and 17 live-server tests passed, including token forgery, expiry and identity/provider rejection.
- Both deployed health checks returned HTTP 200; the live relay reported `vertexReady: true`.
- Both deployed services rejected `debug-token` with HTTP 401.
- APK signature verified and matches both registered fingerprints; package/version are `ai.beyondmarks.blindway` / `4`. The merged manifest includes Google's reCAPTCHA activity, disables backup, and contains no AppAuth activity. APK size: 188,623,691 bytes; SHA-256: `C57E68ADA0FB91CF1E5DBAAD7878C0D692DB29E347003DF21C6430BB1952FD52`.
- Google phone-provider settings and registered Android signing fingerprints were verified via authenticated Google APIs.
- **Real SMS delivery, Google app verification and signed-in camera interaction on the vivo Y51A are not yet verified.** No OTP was sent to a real user number during this change.
- Gemini Live, camera capture and Sarvam fallback remain available after sign-in. This auth change does not establish new latency measurements.
- Firebase setup alone does not configure Azure guardian push delivery. The app retains its foreground-polling warning until `GUARDIAN_PUSH_CONFIGURED=true` is explicitly supplied after backend FCM setup and delivery testing.

## Rebuild/deploy

Use Google's Firebase console or authenticated Firebase Management APIs to register the Android app and download its real configuration. This machine's Firebase CLI account differs from its authorized gcloud account; provisioning used `gcloud auth print-access-token` with the `x-goog-user-project` header rather than granting the unrelated account access. The downloaded configuration and admin snapshots are ignored by Git.

Set `FIREBASE_PROJECT_ID` in Azure app settings, publish with `infra/deploy-backend.ps1`, and deploy the live relay with `infra/deploy-live.ps1`. New infrastructure uses `infra/deploy.ps1 -FirebaseProjectId YOUR_PROJECT ...`. Legacy `configure-identity.ps1` / `identity.bicep` are historical Entra provisioning and are not part of current setup.

Build with `flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/app_config.json --build-number=4` after supplying the real Google services file. Do not disable Google app verification or embed fictional phone-number bypasses in a distributed build.

Reference: [Flutter phone authentication](https://firebase.google.com/docs/auth/flutter/phone-auth), [Android app verification and fingerprints](https://firebase.google.com/docs/auth/android/phone-auth).
