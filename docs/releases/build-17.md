# Blind Way — Build 17

Download **Blind-Way-build-17.apk** from this release and install it on an ARM64 Android phone running Android 8 or later. Package: `ai.beyondmarks.blindway`; app version: `1.0.0`; Android version code: `17`.

## Updated features

- ESP32-CAM integration, Gemini Live questions and automatic surroundings descriptions, with buffered replies to reduce interrupted speech.
- In-app Google Maps walking directions. Jarvis reads a destination address, accepts spoken yes/no/next/repeat replies, and asks again before starting guidance.
- Navigation prompts, route summaries, warnings and controls in all 29 offered language variants, plus Automatic mode. Sarvam handles its supported Indian languages; Google cloud speech handles the other variants.
- Phone OTP sign-in recovery, guardian notification integration, local Hey Jarvis wake-word detection and seven-day Azure conversation memory.
- Fixed translated-route URLs and language continuity during short confirmation replies.

## Verification

- Flutter: 71 tests passed; two opt-in hardware tests skipped. Formatting and analyzer checks passed.
- Backend: 47 tests passed. Live relay: 28 tests passed.
- Real Google speech generation checked for all 18 cloud-voice variants. The user confirmed clear Kannada speech on the vivo phone.
- Build 17's final on-phone route retest remains pending because the phone disconnected. The URL fix is covered by regression tests.

This is a debug-signed assistive prototype APK. Walking directions do not establish safe crossings, accessible paths or obstacle clearance; supervised outdoor testing remains necessary. The bundled openWakeWord model notices and licenses are included in the source and APK.

APK SHA-256:

```text
a6994f686bac6954e1eea5ee0ebbfae2023648ef013598d92607a40f760d2e42
```

Private service configuration is excluded from Git. With the documented local configuration in place, the corresponding APK build command is:

```sh
flutter build apk --debug --target-platform android-arm64 --build-number=17 --dart-define-from-file=config/app_config.json
```
