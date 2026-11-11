# Live camera recovery — Android build 5

The reported message was “Live camera image lost” after starting Gemini Live. The ESP32-CAM at `http://10.67.29.164` responded with `ready: true` and valid 320×240 JPEGs during investigation. The previous app stopped the entire live session on any camera exception or a 1.5-second timeout, including time spent waiting behind another capture. Timing out the Dart future did not cancel the underlying HTTP request.

The update starts a four-second network deadline after the camera queue is acquired and cancels the actual request on timeout. An idle live session retries up to three consecutive capture failures before stopping. A failure during a question stops that question and playback immediately. Questions remain blocked without a fresh frame, and images older than 2.5 seconds from request start (including queue time) are discarded. Preview uses the same freshness-checked live frames and avoids starting extra captures during live setup. Cloud-send failures now have a separate message from camera failures.

Verification: 19 camera/live regression tests passed, including a 1.7-second frame, late-frame rejection, queue timing, actual HTTP cancellation and recovery, brief capture interruption and failure during a question. The updated `captureLive` method fetched and decoded ten real camera frames successfully: 270, 475, 261, 396, 303, 362, 452, 458, 263, 311 ms. These measurements are from the workstation on the hotspot, not the vivo phone. No hardware power fault was established, and this does not prove the phone's local camera route is reliable.

Install `D:\Blind Way\Blind-Way-Camera-Fix.apk` over the existing app, then connect to `http://10.67.29.164` and start Gemini Live. Phone OTP remains configured. The remaining validation is the updated app on the vivo Y51A; if it still fails, the new error reports the camera address and distinguishes a timeout, unreachable camera, invalid image, and cloud send failure.

APK signing certificate matches the existing installed build. SHA-256: `A9373FE40FEB4AA585E12A3F185E709993009ADB1E9C8A0D182C4F4792F58208`. Flutter analysis passed.
