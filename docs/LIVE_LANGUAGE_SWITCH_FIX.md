# Gemini Live language switching — build 13

The connected phone showed `Kannada uses Sarvam voice. Use Start assistance or Ask a question.` in build 12. A client restriction prevented Kannada, Gujarati, Malayalam, Odia and Punjabi from starting Gemini Live. Changing languages also stopped the entire camera/microphone session and depended on Android TTS configuration before restarting.

Build 13 removes the restriction. All entries in the language selector are accepted by the Live relay. A validated `language` message refreshes the Vertex model within the existing authenticated WebSocket, preserving the camera, microphone, automatic narration setting and completed conversation memory. The client waits for a ready acknowledgement matching the requested language, then sends a fresh frame and resumes. Switching during speech deliberately discards the unfinished reply and its late audio. Rapid choices are serialized. Stopping assistance during a pending switch cannot restart it. Missing Android voice packs no longer block Gemini audio.

Validation on 10 November 2026:

- 21 Flutter Live/voice tests passed, including every selector entry, switching during speech, successive changes, cancellation and native TTS failure.
- 22 Live relay tests passed, including locale validation for both updates and changes.
- Flutter analyzer passed.
- Real Vertex Gemini 3.8 Live calls generated response text and PCM audio in Gujarati, Kannada, Malayalam, Odia and Punjabi. This is representative generation testing, not a guarantee of pronunciation or accuracy in every situation.
- Cloud Run revision `blindway-live-00007-dcl` deployed.
- APK build 13 installed successfully over build 12 through ADB, preserving app data.
- After the user unlocked the phone, Gemini started with Kannada selected. Camera capture then failed because the ESP32-CAM at `10.67.29.164` did not answer from the phone's hotspot; ADB ping confirmed packet loss. A real camera-and-playback language-switch test still requires the camera to reconnect. No camera image was substituted.

APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk`.
SHA-256: `2c202debd18901cab94408206538c8add31fefbbbfee5f23bb51fba8e84c61df`.
