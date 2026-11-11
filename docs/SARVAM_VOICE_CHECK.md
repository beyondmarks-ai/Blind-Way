# Voice integration verification — 7 November 2026

The Android prototype uses local openWakeWord (“Hey Jarvis”), one native microphone recorder, Sarvam Saaras v4 transcription with `language_code=unknown`, Azure OpenAI image questions, and Sarvam Bulbul v3 streamed MP3 responses with speaker Ritu. Keys remain in Azure Function settings. Picovoice is removed.

## Confirmed

- Official Sarvam MCP server connected using the existing environment key. Its language tool confirmed 11 TTS languages.
- Synthetic Hindi and Tamil speech generated through MCP was transcribed back with the correct detected languages. Recognition measured 594 ms and 560 ms; synthesis of the complete short clips took 1,345 ms and 1,173 ms. These are individual service measurements, not phone response times.
- Backend build and 26 tests passed, including language changes, Indic SOS text normalization, malformed WAV rejection, authorization, and missing-camera behavior.
- Flutter analysis passed; 22 existing tests plus five new question cancellation/language/SOS tests passed, including cancellation during a spoken countdown announcement. The optional live camera test was skipped in the automated suite.
- Android ARM64 debug APK compiled with bundled ONNX models. A local tensor-contract check detected a clear synthetic “Hey Jarvis” sample (peak 0.998) and rejected silence. A second pronunciation was missed (peak 0.453). This is not a wake-word accuracy benchmark.
- A missing-camera live check now returns a fixed Hindi connection message. STT plus first streamed audio measured 1.68 seconds from submitting the test WAV locally. This excludes recording, endpointing, app networking, camera, and phone playback.
- A live synthetic image question correctly described a red circle and blue square in Hindi. Submission to first MP3 bytes took 6.56 seconds (recognition 0.74 seconds; answer ready at 6.00 seconds). This is not a real-phone latency result and is too slow to treat as immediate obstacle avoidance.

## Device checks still required

Install `Blind-Way-Sarvam.apk`, sign in, pair earbuds, connect the camera on the same hotspot, and enable Hands-free questions. Pause after “Hey Jarvis,” then ask a short question. Try Hindi followed by Tamil or English without changing settings. Repeat with TalkBack, screen off, noise and the phone in a pocket. Record missed/false activations and time from the end of a question to the first audible answer. Verify the actual earbud microphone route; Android may use the phone microphone.

Use the Stop question button during processing and verify no late answer plays. Test an SOS countdown and cancel it before sending an alert. No real guardian alert was sent during these checks. Background guardian push remains unconfigured; foreground polling is available. The camera was unreachable during this final voice integration session, so a live camera-to-earbuds demonstration remains unverified.

Recognition supports more languages than speech output. Supported reply languages: English, Hindi, Bengali, Gujarati, Kannada, Malayalam, Marathi, Odia, Punjabi, Tamil and Telugu. Additional recognized languages fall back to English explicitly. Existing high-resolution Read text remains local Latin OCR with device speech; it is separate from cloud voice questions.

Pretrained wake weights are CC BY-NC-SA 4.0; bundled notices apply. This build is a noncommercial assistive prototype with debug signing, not a validated mobility or emergency device.

## Reproduce

- `backend/sarvam_mcp_check.py --smoke` uses the official MCP server through `uvx`; set `SARVAM_UVX`, `SARVAM_API_KEY` and optionally `SARVAM_MCP_BASE_PATH` in the environment.
- `backend/check_wake_models.py path/to/16khz-mono-wake.wav` requires numpy and onnxruntime. A missing WAV argument checks silence/tensor compatibility only.
- After `npm run build`, `node backend/test/manual-voice.mjs question.wav [test-image.jpg]` exercises cloud voice with the configured Azure credentials and Sarvam key. Without an image it verifies the fixed missing-camera response.
- Run `infra/configure-sarvam.ps1` after provisioning/reprovisioning Azure, then publish the backend. Never put Sarvam credentials in Flutter dart-defines.
