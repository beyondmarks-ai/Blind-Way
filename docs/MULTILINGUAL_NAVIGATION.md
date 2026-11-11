# Multilingual walking navigation — build 17

Navigation prompts now follow all 29 language variants in the app selector. Automatic mode uses the language detected from a destination request and keeps it through the short confirmation exchange. Selecting a language explicitly takes priority over detection.

The app bundles 53 navigation strings per locale, including destination questions, route summaries, cancellation, GPS loss, off-route messages and the arrival limitation. Addresses, distances and times are inserted after translation. The navigation screen's controls also use the selected language. These translations do not require a network round trip at each GPS update.

Google Maps supplies the walking route. While preparing a non-English route, the authenticated relay translates the provider's instructions and warnings into the requested language. Translation failure prevents that route from starting; it does not silently substitute English instructions. Odia requests use English Google Maps results before this translation step. Changing language during guidance pauses tracking, obtains the route in the new language, and asks the user to confirm again.

Sarvam remains the voice provider for its supported Indian languages. The other 18 selectable variants use Google Cloud Text-to-Speech, including Arabic through its `ar-XA` voice. Android TTS remains a fallback when cloud speech is unavailable; an appropriate installed voice is needed for that fallback. Each queued speech item retains its own locale. Google MP3 responses are buffered in memory before playback.

The relay receives authenticated POST requests at `/speech` and `/navigation/translate`. Both require a valid Firebase phone token and a registered vision-assistance profile, with bounded input and per-user rate limits. No new API key is placed in the APK. The Cloud Run service identity calls Google APIs. Cloud Translation and Text-to-Speech APIs were enabled in the existing Blind Way project; the service identity has the Cloud Translation User role. No new guardian messages or SOS alerts are sent by this feature.

For short replies, Gemini receives the pending question type and its spoken language. For example, Japanese “hai” is interpreted in Japanese rather than as an English greeting. “Yes/no” navigation actions remain valid only while a confirmation is pending. In Automatic mode, a short confirmation does not change the established navigation language.

Verification completed during implementation:

- All 29 catalogs contain the complete source set and preserve every placeholder. Selected Hindi, Kannada, Tamil, French, Arabic and Japanese prompts were inspected; ambiguous “start walking” wording was changed to starting spoken directions.
- 35 targeted Flutter tests passed, including route language changes, confirmation listening and GPS behavior; analyzer passed.
- 28 relay tests passed, including authentication gating, locale mapping and rejecting incomplete translations. Backend routing tests passed with 47 tests.
- Google generated actual MP3 audio for all 18 cloud-voice variants using localized product text.
- Real Vertex synthetic-audio checks recognized French and Japanese confirmations; the Japanese case was verified after adding prompt-language context.

Translations were generated with Google Cloud Translation using `infra/generate-navigation-translations.py`. They have not all been reviewed by native speakers. Physical playback, microphone recognition, pronunciation and supervised outdoor use still require device testing. This change does not establish safe crossings, obstacle avoidance or accessible paths. Non-Sarvam spoken questions still use Gemini Live and its existing camera connection requirement. Other app screens, such as sign-in and guardian management, are outside this navigation-localization change.

APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk`, version 17. SHA-256: `a6994f686bac6954e1eea5ee0ebbfae2023648ef013598d92607a40f760d2e42`. The initial build 16 was installed and tested on the vivo V2031; the final build 17 awaits installation because the phone disconnected. Cloud Run revision: `blindway-live-00011-n5t`.

The vivo phone displayed the Kannada destination prompt and the user confirmed its spoken Kannada was clear. A subsequent device test found an empty-query URL suffix causing route-translation requests to return 404; the client URI builder and relay path parsing were corrected and regression-tested. Final route playback verification is pending because the phone disconnected.
