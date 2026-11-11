# Real-device voice check — November 9, 2026

Tested on a USB-connected vivo Y51A (V2031, Android 13) with the GC2145 ESP32-CAM connected to its hotspot at `http://10.67.29.164`. Build 7 is installed. The final English scene description was confirmed **clear and correct** by the user.

## Changes

- Explicit Android communication audio routing: connected Bluetooth/wired communication headset first, otherwise the phone loudspeaker. The previous device route selected the earpiece without earbuds. Device callbacks update routing after connection changes.
- Stable **Stop question** position directly below **Ask a question**, above changing transcripts. A real cancellation stopped PCM playback and returned the interface to ready.
- Local spoken camera/voice disconnection warnings; stale failure callbacks cannot affect a newer live session.
- Debug-only route and playback lifecycle timing, without recording question content in those diagnostic messages.

## Physical tests

Questions were played from the computer speaker into the actual phone microphone. Recognition and playback used the installed app and deployed Gemini Live relay; transcripts were not injected. Hindi test speech was generated using Sarvam. Live replies used Gemini native audio.

| Test | Result | Recording end → first Android PCM write |
|---|---|---:|
| English, Ask a question | Complete speaker playback | 1,568 ms |
| Hey Jarvis → English question, after camera reset | Wake detected; complete speaker playback | 1,288 ms |
| Hindi question | Hindi transcription and reply; complete playback | 1,584 ms |
| Build 7 Stop question | Playback stopped after 31,200 frames; interface recovered | 1,801 ms to first PCM |
| Build 7 final English scene | Full reply; user confirmed clear and correct | 2,202 ms |

These short samples are not percentile estimates or latency guarantees. Timings start at the native recording-end event and exclude the configured 640 ms silence endpointing and physical speaker/Bluetooth latency. The final answer described a pink stuffed animal, ceiling light and patterned wallpaper.

Reading mode captured and completed recognition, returning “No readable text found” for the scene. The reading controls recovered. No printed-text target was provided, so OCR accuracy was not established. Stopping Live returned Android audio mode to `MODE_NORMAL`. The app was returned to Gemini Live afterward.

The camera dropped off Wi-Fi during an earlier test: the hotspot showed zero clients and ping failed. Restarting the hotspot alone did not restore it. The user reset the camera with IO0 disconnected from GND, after which it rejoined and subsequent tests completed. No firmware was flashed; the cause of that physical outage remains undetermined.

## Validation and limits

- Targeted Flutter live/voice tests: 15 passed. Flutter analysis: no issues. Android ARM64 build 7 succeeded; APK signature verified.
- Existing Google phone-auth session restored across updates. New SMS delivery was not tested.
- No Bluetooth earbuds were connected. Speaker output was verified; real earbud microphone/output still needs a connected-headset test.
- No real SOS or guardian alert was sent. Background guardian notifications remain unconfigured, as the app banner states.
- Local disconnection speech is covered by the controller test; no deliberate camera outage was induced after the final build.
- This is a short stationary prototype test, not validation for independent walking or obstacle avoidance.

## APK and evidence

APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk`, package `ai.beyondmarks.blindway`, version code **7**. Debug-signed ARM64 test build.

SHA-256: `87ED23B2504486B7779C2A4A09563BD1773FB8ADD2C7C79F462C6FE8005CB9ED`.

Local acoustic test helpers and timestamped JSON results: `C:\Users\rkmai\AppData\Local\BlindWayAdbTest`. Earlier failed or mistimed cancellation attempts are retained there but are not counted as passes above.
