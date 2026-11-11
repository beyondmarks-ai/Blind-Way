> Authentication update: Entra has been replaced by Google phone OTP. See [current phone authentication setup](PHONE_OTP_CHECK.md). Entra references below describe the earlier build.

# Azure and device check — 2026-11-07

APK: `D:\Blind Way\Blind-Way-Azure.apk` (ARM64 debug build, 135,601,145 bytes).

SHA-256: `42A91B88B7FD017046CC3D4DB6050446C1049D23160BF1447963DAD5A5CF99FF`.

API: `https://blindway-api-win-d7ofaubf.azurewebsites.net/api`.

Camera: `http://10.67.29.164` on the vivo Y51A hotspot. The address can change.

## Verified

- Real camera: ready status, decoded 320 × 240 navigation image, 1600 × 1200 reading image, and return to navigation; approximately 11 seconds for the test sequence.
- Flutter analysis: no issues. App tests: 22 passed; live-camera test passed separately.
- Backend: TypeScript build and 19 tests passed, including JWT rejection rules, immutable roles, raw JPEG upload, SOS context, and snapshot authorization/deletion.
- Native Android OCR and AppAuth compiled into the APK. Embedded Azure API, client ID, camera address, and ARM64 library verified.
- Entra External ID customer tenant, Android/API registrations, delegated consent, and public email/password sign-up flow created. Authorization page returned HTTP 200 without a tenant error.
- Azure Functions deployment completed; all 17 functions indexed. Health returned HTTP 200. Missing credentials and a debug token both returned HTTP 401.
- Azure Speech returned HTTP 200 and 16,416 audio bytes for a test sentence.
- The backend vision service processed a real camera image using the configured Azure OpenAI deployment and Azure CLI credentials. It reported low visibility. This proves connectivity, not navigation accuracy.

## Remaining phone validation

The user chose to install the APK manually. Browser return after email sign-up, API calls with a real mobile access token, TalkBack, OCR on printed text, audio routing, and guardian workflows have not been tested on the vivo phone.

FCM background notifications and the Picovoice always-on wake-word key are not configured. The app shows a background-notification warning and uses its existing foreground alternatives. Existing Firebase users and trusted links are not migrated automatically.

The original D: build ran out of space. The delivered APK was built from a source copy at `C:\Users\rkmai\AppData\Local\BlindWayBuild20261107`. Partial generated caches remain in the original build directory and `Z:\codex-builds\blind-way-20261107`; the transfer was stopped. No source files were deleted.
