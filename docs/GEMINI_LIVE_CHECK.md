> Authentication update: Entra has been replaced by Google phone OTP. See [current phone authentication setup](PHONE_OTP_CHECK.md). Entra references below describe the earlier build.

# Vertex Gemini Live trial — 7 November 2026

## Deployed configuration

- Google Cloud project: `project-8eeef9d3-080a-4f49-95e`.
- Cloud Run: `blindway-live`, `us-central1`.
- Relay: `https://blindway-live-896452575262.us-central1.run.app`.
- WebSocket: same host, `wss`, path `/live`.
- Vertex model: `gemini-3.8-live`, Google prebuilt voice `Aoede`, native 24 kHz mono PCM output.
- Service identity: `blindway-live@project-8eeef9d3-080a-4f49-95e.iam.gserviceaccount.com`, with Vertex AI User permission. No service-account JSON private key or Google API key is in the APK.
- Existing Azure Entra sign-in is preserved. The relay verifies RS256 JWT issuer, audience, tenant, mobile client, expiry and delegated scope, then calls Azure `GET /v1/live/access` to check the user's registered role. The new route is deployed and indexed.
- Cloud Run permits requests at the platform layer so it can accept Entra authentication, then enforces authorization in the WebSocket upgrade handler. Anonymous and `debug-token` upgrades both returned HTTP 401.
- Maximum two instances, 20 WebSocket clients per instance, and two connections per user per instance. Minimum instances is zero; initial cold starts can add setup time. Vertex usage and active relay time incur Google Cloud charges while enabled.

## App behaviour

Install `Blind-Way-Gemini-Live.apk` (ARM64 Android debug build, version code 3). Sign in, connect the ESP32-CAM on the same hotspot, pair earbuds, and tap **Start Gemini Live**. Allow microphone and, on supported Android versions, nearby-device/Bluetooth permission.

Camera frames stream approximately once a second while live mode is enabled. Microphone audio is processed locally for “Hey Jarvis” until a question starts. After activation, the question streams in 80 ms PCM chunks. Eight quiet chunks (640 ms) end the question; recordings are capped at 12 seconds. Ask a question also works as a touch control. Build 5 cancels camera HTTP requests after four seconds, retries brief idle capture failures, and discards frames older than 2.5 seconds from request start. The relay also refuses a new question without a frame received within 2.5 seconds. See [camera recovery verification](CAMERA_LIVE_RECOVERY.md).

Incoming audio goes directly to ordered Android AudioTrack playback; it does not wait for the complete answer or call Sarvam TTS. Native playback uses a 200 ms buffer where supported. The model switches response language from the user's speech; Hindi and Tamil were tested. Wake detection pauses while a response plays to avoid activation from the app's own voice.

Stop question invalidates the turn, clears native playback and replaces the upstream session so delayed chunks cannot play in the next question. SOS stops live mode and uses the existing cancellable emergency countdown. An idle expiring connection reconnects with a fresh access token; a connection lost during a question stops the question and asks the user to restart. The relay closes sessions after nine minutes or token expiry to stay within service limits.

The earlier periodic Azure navigation loop is paused during live mode. High-resolution reading is disabled until live mode stops, because it takes around ten seconds and blocks navigation capture. The preview uses current streaming frames instead of requesting competing captures.

## Measurements

| Test | Initial model setup | End of test speech to first PCM bytes |
|---|---:|---:|
| Gemini 3.8 Live, stored real bag image | 2.28 s | 1.24 s |
| Gemini 2.5 Flash Native Audio, same image/question | 2.19 s | 1.39 s |
| Gemini 3.8, one session with ongoing frame input, Hindi | 2.31 s once | 1.10 s |
| Same session, Tamil | already connected | 0.98 s |
| Gemini 3.8, 13 freshly captured ESP32 frames, Hindi | 2.21 s once | 1.04 s |
| Same fresh-camera session, Tamil | already connected | 1.20 s |

The microphone questions in these cloud tests were prerecorded 16 kHz WAVs streamed at real-time pace. The measurements used the computer's Google CLI credentials directly against Vertex. They exclude native microphone endpointing, relay transit, actual Android playback and Bluetooth routing. They do not establish a percentile latency, real-phone smoothness or accuracy benchmark.

On the bag image, Gemini 3.8 identified a white bag obstructing the camera and requested a camera adjustment rather than a walking action. On the current camera feed, both language answers identified a round light but incorrectly referred to the ceiling as a wall. The system prompt forbids movement directions and invented distances, but a prompt cannot guarantee visual correctness. This remains an assistive trial, not validated obstacle avoidance.

Evidence, camera frames, JSON timings and PCM/WAV replies are saved locally under `D:\Blind Way\gemini-live-test\`; personal camera images are not added to Git.

## Verification completed

- 13 live-relay authorization/protocol tests: valid token acceptance, invalid token rejection, media bounds and message restrictions.
- 27 Azure API tests, including the new registered-user/role gate.
- Existing 27 Flutter tests and six live-controller tests: streaming before turn completion, cancellation, stale audio suppression, connection loss, idle reconnect, SOS preemption and camera failure. The optional physical camera Flutter test remains opt-in.
- Flutter analysis passed; Android Kotlin/native PCM playback code compiled; final APK built.
- Cloud Run readiness confirmed the managed service account could establish a Vertex Live session. The deployed relay rejected missing and invalid credentials. Azure live-access rejected unauthenticated requests.

Still required: install the APK on the vivo Y51A and test authenticated app-to-relay access, the actual earbud microphone/output route, TalkBack, background/screen-off behaviour, accents, missed/false wake activations, noise, cancellation during audio, sustained sessions and real end-of-question-to-audible-response latency. No real SOS notification was sent during this work.

## Reproduce deployment and tests

Prerequisites: enabled Vertex AI, Cloud Run, Cloud Build and Artifact Registry APIs; a billing-enabled project; the dedicated service account above; existing Entra public configuration in ignored `config/azure-identity.json`. Deploy the Azure API first so `/v1/live/access` is available.

Run `infra/deploy-live.ps1` with Google CLI access. It runs relay tests, deploys the service, and updates `GEMINI_LIVE_URL` in ignored `config/app_config.json`. Build Flutter with that dart-define file. `config/live-env.json` contains public identifiers and endpoints, never Google credentials.

In `live_backend`, run `npm test`. `probe.mjs` checks available models, `benchmark.mjs` compares model responses, and `session-test.mjs` tests a persistent connection. Live scripts require `GOOGLE_CLOUD_PROJECT` and a short-lived `VERTEX_TEST_TOKEN` captured from `gcloud auth print-access-token` in the process environment; never print or commit that token. Set `CAMERA_TEST_URL` to capture fresh camera frames during the session test.

References: [Vertex Live API](https://cloud.google.com/vertex-ai/generative-ai/docs/live-api), [Gemini 3.8 Live availability](https://cloud.google.com/vertex-ai/generative-ai/docs/models/gemini/3-8-live), [session lifecycle](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/live-api/start-manage-session).
