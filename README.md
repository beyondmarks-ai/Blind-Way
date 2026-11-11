# Blind Way

Accessible Android camera assistance and emergency coordination using an ESP32-CAM, Google phone authentication, Vertex AI, and Azure data services.

Blind Way is an assistive aid. It does not replace a cane, guide dog, trained mobility support, or emergency services. Camera images and AI descriptions can be delayed or wrong.

## Google Maps walking directions

Build 17 localizes navigation speech and controls for all 29 offered language variants, plus Automatic mode. Confirmations, route summaries, warnings and provider instructions follow the selected language. See [multilingual behavior and testing](docs/MULTILINGUAL_NAVIGATION.md).

Build 15 adds **Google Maps walking directions** in Assist. Say **Hey Jarvis**, pause, then **Take me to [place and area]**. Jarvis reads one address and asks whether it is correct. Say **yes**, **no**, **next**, or **repeat**. After the route summary, say **yes** to start. With Hey Jarvis enabled, it listens automatically after each confirmation prompt, so the immediate replies need no wake word or screen selection. The app uses current phone GPS and Google walking instructions, with spoken advance notices, repeat/pause/resume controls, and an explicit reroute option. Google Maps APIs are configured through GCP with separate restricted Android and server keys.

Cloud routing and voice-command checks passed. Phone playback and supervised outdoor navigation still require testing; GPS/map directions cannot establish safe crossings or accessible paths. See [setup, commands and verification](docs/GOOGLE_WALKING_NAVIGATION.md).

## Gemini Live trial

The latest Android build adds **Start Gemini Live** after connecting the ESP32-CAM. It keeps a Vertex AI Gemini 3.8 Live session open, sends fresh JPEG camera frames about once per second, and uses Gemini's native multilingual voice. Say **Hey Jarvis**, pause, then ask. Question audio streams in 80 ms microphone chunks after activation. Replies arrive as 24 kHz PCM; the phone buffers each complete short reply before playback to prevent network gaps from breaking words. **Stop question** cancels playback; **Stop Gemini Live** stops camera streaming and microphone listening. Sarvam remains the separate fallback when live mode is off.

Enable **Automatic surroundings** within Gemini Live to hear descriptions without asking. The phone compares decoded thumbnail pixels against the last announced view, requests a short update after a substantial visual change, and waits at least two seconds after playback before another automatic update. A still scene stays quiet; this is visual-change detection, not reliable tracking of every moving object. **Stop question** also pauses automatic updates. Spoken questions remain available between updates.

**Azure conversation memory** stores completed, playback-acknowledged questions and descriptions for seven days in a separate Cosmos DB container partitioned by authenticated user. Reconnecting loads the latest 12 exchanges. Images and raw audio are not stored in this memory. Historical descriptions can be wrong and never substitute for a fresh camera view. If memory is unavailable, live assistance continues with an explicit memory-status message.

Build 10 increases the model output allowance, resets deadlines while audio arrives, and plays complete replies from a static Android audio buffer. This trades some start latency for uninterrupted speech. A transient camera capture failure no longer cuts off an already-speaking observation. New descriptions still require fresh frames; a persistent outage stops assistance after the current observation finishes and announces the disconnection.

Google credentials stay on an authenticated Cloud Run relay. It validates a Google Firebase phone ID token and asks the Azure API to verify that the caller is a registered vision-assistance user. The phone contains a relay URL, not a Vertex API credential. Live mode pauses the earlier periodic navigation loop and disables high-resolution reading while active. Preview reuses the ongoing camera frames.

Direct Vertex tests with fresh ESP32-CAM frames measured **1.04 s (Hindi)** and **1.20 s (Tamil)** from the end of streamed speech to the first audio bytes on one persistent connection; initial model setup took **2.21 s**. These measurements exclude phone microphone endpointing (configured at 640 ms of silence), relay overhead, Android playback and Bluetooth latency. They are not a promised phone response time. The model recognized the round light but misidentified its ceiling as a wall; walking guidance remains unvalidated.

See [Gemini Live setup and verification](docs/GEMINI_LIVE_CHECK.md) for deployment, testing and limitations.

Real vivo Y51A tests on November 9 measured **1.29–2.20 seconds from recording end to the first Android PCM write** for completed English/Hindi replies. These include the relay and playback startup, but exclude microphone endpointing and physical audio latency. The latest scene reply was confirmed clear and correct by the user. Build 7 explicitly selects the phone speaker when no headset is connected, keeps **Stop question** in a stable position, and speaks a local warning if live assistance disconnects. See [ADB voice test results](docs/ADB_VOICE_CHECK_2026_11_09.md).

## Camera connection

Connect the phone and camera to the same Wi-Fi or phone hotspot. In **Connect camera**, enter the root address (currently `http://10.67.29.164`) and leave the token blank for the current GC2145 firmware. The address can change when the hotspot restarts.

| Action | Request | Resolution |
|---|---|---|
| Preview / navigation | GET /capture | 320 × 240 |
| Read text | POST /read | 1600 × 1200 |
| Connection check | GET /status | JSON readiness and capabilities |

Preview requests run sequentially and pause during reading. Navigation resumes after a reading capture. The verified firmware provides approximately 2 frames/second preview and an 11–12 second reading capture; it does not provide smooth high-resolution video.

**Read text** uses bundled Android ML Kit Latin-script OCR and Android speech. Reading photos and recognized text stay on the phone. Hold the camera still in good light. Real printed-text accuracy still needs phone testing. Hindi and Tamil OCR are not included; language selection controls guidance speech.

The current GC2145 firmware is in the sibling `../navigation_reader/` project. BLE provisioning and mDNS apply only to the older OV2640 firmware in `CameraWebServer/`; do not flash it onto this GC2145 setup.

## Voice languages

Settings > Voice response language offers all documented Gemini Live languages, five additional Sarvam languages, and Automatic. Your explicit choice is saved and overrides previous conversation language. All listed languages work in Gemini Live, including Gujarati, Kannada, Malayalam, Odia and Punjabi; Sarvam remains available for its supported languages. This controls AI replies, not translation of every app label.

## Cloud services

- **Google Firebase Authentication / Identity Platform:** Indian mobile-number SMS OTP, automatic Android verification where available, native session refresh.
- **Azure Functions and Cloud Run:** verify Google token signature, issuer, project audience, expiry, phone provider and verified phone claim.
- **Azure OpenAI:** transient navigation-image analysis, using a configured vision deployment.
- **Sarvam:** automatic question transcription (Saaras v4) and streamed voice replies (Bulbul v3), with Android TTS fallback.
- **Cosmos DB:** profiles, immutable account roles, trusted links, and alerts.
- **Private Blob Storage:** emergency photos, deleted on cancellation/resolution and covered by a one-day lifecycle rule.

Google phone authentication replaces Entra. Guardian notifications use Firebase Cloud Messaging directly from Azure Functions, with keyless GCP Workload Identity Federation. Linked guardians receive high-priority notifications; five-second foreground polling recovers missed alerts. See [language and notification setup](docs/LANGUAGES_AND_GUARDIAN_PUSH.md) for configuration and verification limits.

The account API supports IPv4 and IPv6, including Jio connections without an IPv4 route. If connectivity fails after Google verifies the OTP, **Retry sign-in** keeps that verified login and retries the account request without another SMS. See [login recovery verification](docs/LOGIN_RECOVERY_2026_11_10.md).

Old Entra profiles and links are not automatically matched to phone accounts. Sign in with your phone number and link trusted people again. Existing cloud data is retained.

## Setup

Requirements: Flutter, Android SDK (API 26+), compatible JDK, Node.js 22, and Azure CLI.

1. Enable Firebase Authentication / Identity Platform phone sign-in and billing on your Google project. Allow the required SMS regions (currently India only).
2. Register Android package `ai.beyondmarks.blindway`, add the signing certificate SHA-1 and SHA-256, and download its real `android/app/google-services.json`. See [phone OTP verification](docs/PHONE_OTP_CHECK.md).
3. Deploy:

```powershell
./infra/deploy.ps1 -OpenAiResourceGroup YOUR_AI_GROUP -OpenAiAccount YOUR_AI_ACCOUNT -OpenAiDeployment YOUR_VISION_DEPLOYMENT
# Set SARVAM_API_KEY in your environment first. Run again after infrastructure redeployment.
./infra/configure-sarvam.ps1 -FunctionApp YOUR_FUNCTION_APP
./infra/deploy-backend.ps1
```

The Function's managed identity receives access only to the selected OpenAI resource. Speech keys stay in server settings. Debug authentication is disabled in Azure. Web PubSub remains optional. Guardian push uses the FCM workload identity provider and service account passed to the deployment script.

4. Copy `config/app_config.example.json` to `config/app_config.json`; fill the deployed API and Gemini Live URLs. Set `FIREBASE_PROJECT_ID` on both servers. No service-account secret belongs in the APK.
5. Configure keyless FCM using the provider described in docs/LANGUAGES_AND_GUARDIAN_PUSH.md, then run infra/validate-push.ps1. Set GUARDIAN_PUSH_CONFIGURED=true in the private app config only after validation succeeds.
6. Build:

```powershell
flutter pub get
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/app_config.json
```

This makes an ARM64 debug APK suitable for the vivo Y51A. Production distribution requires your release signing key; the existing release configuration currently uses debug signing.

## App workflow

Choose **I need vision assistance** or **I am a trusted contact**, enter your name and mobile number, and complete SMS OTP verification. Account role is permanent after registration.

Connect the camera, open **Camera preview**, or choose **Read text**. Navigation sends low-resolution frames to Azure; reading stays local.

The emergency button requires a two-second hold and cancellation countdown. Voice SOS has its own cancellation countdown. Reading cannot start during SOS; late reading results are suppressed when an emergency begins. Location, the last scene cue, and an optional camera photo are available only to linked guardians.

Enable **Hands-free questions**, say **Hey Jarvis**, pause, then ask a short question. Bundled openWakeWord runs locally through ONNX Runtime; no Picovoice account or key is used. **Ask a question** provides a touch alternative. Automatic language detection runs separately for each question. Sarvam supports spoken replies in English, Hindi, Bengali, Gujarati, Kannada, Malayalam, Marathi, Odia, Punjabi, Tamil and Telugu. Recognition supports additional languages; unsupported response languages explicitly fall back to English. Code-switching follows the predominant detected language and is not guaranteed word by word.

In hands-free mode, say **Hey Jarvis**, pause, then **Help** for SOS. Recognition needs internet; the emergency button remains available. With hands-free mode off, Android's existing short-command SOS listener operates during assistance. Wake detection pauses during app speech. Force-stop, reboot, permissions, or battery restrictions can interrupt listening.

Question audio (up to 12 seconds) is sent through the authenticated Azure API to Sarvam after activation; a fresh navigation frame goes to Azure OpenAI for the answer. Missing frames produce a fixed connection message, never a generated scene. Responses are short and speech streams as MP3. Camera capture has a 1.5-second deadline in this flow; high-resolution local reading is separate. This is not guaranteed real-time navigation.

The bundled pretrained wake weights are **CC BY-NC-SA 4.0**, intended here for a noncommercial prototype. See the bundled [model notice](android/app/src/main/assets/openwakeword/NOTICE.md). Detection must be tested with real accents, microphones and noise. A clear synthetic sample passed; another pronunciation was missed. “Hey Blind Way” would require a separately trained model.

See [Client App Guide](docs/CLIENT_APP_GUIDE.md) for the screen-by-screen workflow.

## Verification

```powershell
flutter analyze
flutter test
cd backend
npm ci
npm run build
npm test
```

Optional live camera test:

```powershell
flutter test test/camera_device_test.dart --dart-define=CAMERA_DEVICE_URL=http://10.67.29.164
```

It verifies JPEG decoding, both resolutions, and return to navigation. Tests cover camera serialization, reading cancellation and SOS, native OCR calls, auth refresh/logout races, token validation, account roles, raw JPEG upload, and emergency snapshot authorization.

Real-phone checks remain necessary for browser return, TalkBack, large text, OCR, audio routing, and guardian delivery.

Sarvam MCP setup and live verification are recorded in [voice verification](docs/SARVAM_VOICE_CHECK.md). MCP is used for development checks; the app calls Sarvam through Azure directly to avoid an extra runtime hop and keep its API key off the phone.

## Repository layout

| Directory | Purpose |
|---|---|
| `lib/`, `android/` | Flutter app, native OCR, Google phone OTP |
| `backend/`, `infra/` | Active Azure API and provisioning |
| `test/`, `backend/test/` | App and API tests |
| `CameraWebServer/` | Older OV2640 firmware |
| `aws_backend/`, `aws/`, `google-cloud/` | Previous AWS/Google implementation |

Keep credentials, private configuration, camera Wi-Fi secrets, signing keys, and user photos out of Git. Follow [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

References: [OpenAI image inputs](https://developers.openai.com/api/docs/guides/images-vision), [GPT-4.1 mini capabilities](https://developers.openai.com/api/docs/models/gpt-4.1-mini), [Firebase phone authentication](https://firebase.google.com/docs/auth/flutter/phone-auth).

<!-- beyond-marks-credit:start -->
---
### Built by Beyond Marks AI Academy

Developed by **Rakesh Kumar** at [Beyond Marks AI Academy](https://beyondmarks.ai).
<!-- beyond-marks-credit:end -->
