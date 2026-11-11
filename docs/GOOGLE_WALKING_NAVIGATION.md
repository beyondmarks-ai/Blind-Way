# Google Maps walking navigation

Blind Way now includes an in-app Google map and a walking-route prototype driven by the phone's GPS. This is map guidance, not a validated mobility aid. It cannot determine safe road crossings, live traffic gaps, pavement condition, obstacles, or accessible entrances. An accompanied outdoor test is required before client use.

## User flow

1. Open **Google Maps walking directions** from Assist. Allow precise location and turn on phone location services.
2. Enable **Hey Jarvis** or use **Ask Jarvis**. Say "Hey Jarvis", pause for listening, then "Take me to [place and area]". A destination can also be typed.
3. Jarvis reads **one name and address at a time** and asks "Is this the place you mean?" Say **yes** to accept it, **no** or **next** for the next match, or **repeat** to hear it again. No number or screen selection is required. Numbered choices remain an optional shortcut.
4. The app obtains a walking route from the current position, reads its distance, estimated walking time and warnings, and asks for confirmation. It asks "Shall I start walking guidance?" Say **yes** to start or **no** to cancel. **Start route** and the screen button remain optional shortcuts.
5. Keep using your normal mobility aid. The app speaks the current Google instruction and gives an approximate advance notice before the next instruction. It pauses new directions on inaccurate or missing GPS. It reports "near the destination" rather than claiming it has found the entrance.

With **Hey Jarvis** enabled, the app automatically opens one short reply recording after each confirmation prompt finishes and the listening sound plays. The wake word is not needed for that immediate reply. Silence never accepts a destination or starts guidance. Confirmation expires after 60 seconds; use **repeat directions** to hear the pending prompt again, or search again. Without hands-free mode, use **Ask Jarvis** to reply.

Commands: **repeat directions**, **route status**, **pause navigation**, **resume navigation**, **reroute**, **stop navigation**. Reroute requests a fresh route and asks for confirmation again. A route that appears to have been left is paused after repeated reliable off-route fixes; it never silently redirects the user.

Gemini Live handles navigation intents in the selected language. Common English Sarvam commands use a local server parser; other language/conversational commands use a bounded structured classifier. Google supplies the route text in the selected supported language. Sarvam speaks its supported Indian languages; other route playback uses Google cloud speech, with Android TTS as a fallback. Build 17 localizes navigation prompts, summaries, warnings and navigation-screen controls for every offered language. See [multilingual navigation](MULTILINGUAL_NAVIGATION.md) for voice providers and validation.

Walking navigation can be used without the ESP32-CAM through the navigation screen and Sarvam voice path. Gemini Live camera questions still require a fresh camera image. Camera descriptions remain observations, not map directions. Guidance speech temporarily pauses other assistant speech so the two do not overlap. SOS cancels the walking session and retains the existing emergency flow.

## Implementation and limits

- Places API (New) Text Search finds up to three candidates near a current GPS fix; the user chooses an exact address.
- Routes API `computeRoutes` requests **WALK** only, with explicit field masks for step instructions, geometry, distance, duration and warnings. No driving routes are substituted.
- Destination searches and route requests require a registered vision-assistance account, a location no older than 30 seconds, and reported GPS accuracy of 30 metres or better. Live progress uses a stricter 25-metre accuracy check and rejects stale timestamps and large jumps.
- A location foreground service runs only for a confirmed active route. Pause stops announcements; Stop ends the location subscription. Routes are not automatically resumed after app termination.
- Route progress uses GPS proximity to route geometry. It is approximate and can be confused by parallel roads, complex junctions, GPS drift, or a missed step. It has not been field-validated as a turn-by-turn navigation product. Map distance and arrival estimates do not establish physical safety.
- Coordinates and route geometry are held in app memory and sent to Google when the user requests navigation. No navigation history database was added. Spoken destinations/questions may appear in the existing opted-in seven-day conversation memory. Starting a route does not send a guardian alert.
- No offline routing, public-transit routing, accessibility guarantees, live crossing signals, compass calibration, or background restart recovery is provided.

## Cloud configuration

GCP project: `project-8eeef9d3-080a-4f49-95e`.

Enabled via GCP CLI: `places.googleapis.com`, `routes.googleapis.com`, `maps-android-backend.googleapis.com`.

- `blindway-maps-server-v2`: limited to Places/Routes APIs and the Azure Function's outbound IP addresses. Stored only in Azure app setting `GOOGLE_MAPS_SERVER_KEY`.
- `blindway-maps-android-v2`: limited to Maps SDK for Android, package `ai.beyondmarks.blindway`, and the current debug signing SHA-1 `10:85:A2:2E:17:25:D9:42:BE:A8:15:5F:56:D6:56:21:04:71:D9:F0`. Stored in ignored `android/maps.properties` as `MAPS_API_KEY`. Gradle injects it into Android metadata. A new release signing certificate needs a corresponding restriction update before distribution.

Do not commit either key. Changing Azure hosting/outbound IPs requires updating the server key restrictions. Infrastructure redeployment must preserve/reapply `GOOGLE_MAPS_SERVER_KEY`, as with the existing Sarvam settings. Google Maps uses its own billing and quotas; the API additionally limits route/search requests per signed-in account.

`infra/validate-navigation.ps1` uses an Azure function key without printing it. It calls a fixed public-place check near Cubbon Park, Bengaluru; it does not access a user's current location or start navigation. The deployed check returned three places and a 508-metre walking route with three steps.

## Verification

Android debug APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk`, version code **15**, package `ai.beyondmarks.blindway`. APK SHA-256: `dfc0e6ab84bace5b02a8e4bb7be24d6e86b24f410c8a39b38b95d21fe94caccd`. Source/staging Dart files match. ADB installation succeeded on the vivo V2031 and the package manager confirms version 15. The phone remained locked, preventing interactive validation.

- Backend: 47 tests passed, including walking-only requests, fresh/accurate GPS checks, profile authorization, API failure and destination parsing.
- Flutter: 31 targeted navigation, Live and voice tests passed, including GPS loss/jumps, arrival confirmation, route geometry, off-route fixes, cancellation, confirmation before tracking, pausing without a false GPS warning, and the detected language reaching Maps search. Analyzer clean.
- Live relay: 24 tests passed. Real Vertex tests converted English and Kannada destination requests into the expected search action. Cloud Run revision `blindway-live-00009-7kg`.
- Real Vertex synthetic English audio tests passed for yes/no to an address prompt and yes to the start prompt. Context-free yes/no commands are blocked; cancelling during address speech cannot reopen confirmation. Automatic reply capture and context forwarding also passed an app test.
- Real Places/Routes request passed from deployed Azure using the restricted server key.
- Physical phone map rendering, audio, background GPS and a supervised walking route remain unverified because the connected phone was locked after installation. No simulated phone GPS was substituted for a real route test. The deployed Maps readiness check still returned three candidates and a 508-metre walking route after this backend update.

References: [Routes walking directions and fields](https://developers.google.com/maps/documentation/routes/reference/rest/v2/TopLevel/computeRoutes), [Places Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search), [Google Maps Flutter configuration](https://developers.google.com/maps/flutter-package/config).
