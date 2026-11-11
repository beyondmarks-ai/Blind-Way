# Automatic surroundings and seven-day memory

## Behavior

Enable **Automatic surroundings** after starting Gemini Live. A first observation is spoken without a question. The phone then compares 24 × 18 decoded RGB thumbnails against the last announced view. A change of more than 28 intensity levels in over 18% of pixels triggers another observation, when idle and at least two seconds after the last reply. The model is asked for one complete sentence of at most 12 words, or equivalent brevity in other languages.

This detects image changes, not every moving object. Camera shake and exposure changes can also trigger it; small movements can be missed. The model receives current images, not an old queued image. Speech does not overlap. Switching automatic mode off lets the current reply finish; **Stop question** cancels it and pauses automatic mode. Voice questions work during quiet intervals.

## Speech interruptions

Real vivo Y51A testing identified gaps in incoming streamed audio. Android AudioFlinger reported repeated underruns on the app's 24 kHz output. The user described “pauses, then continues.” Increasing output limits and avoiding camera-triggered cancellation alone did not fix that.

The final player collects each bounded short PCM reply and plays it from a static AudioTrack buffer after model completion. Network jitter therefore affects start delay rather than interrupting words. Cancellation still invalidates queued work immediately. Completion waits for playback-head progress, with an error if playback stalls. The user confirmed the buffered test was smooth.

A measured memory reply started 7,479 ms after native recording ended. Its 144,001 samples contain 6.000 seconds of speech; Android playback completed in 6.131 seconds. This is evidence of continuous local playback, not a guarantee of low start latency. The configured 640 ms microphone silence endpointing is excluded. Automatic updates use shorter answers to reduce that delay.

Camera retries no longer cancel an already-started observation on one missed frame. Persistent loss prevents new observations and announces disconnection after the current reply. Historical observations do not establish present walking safety.

## Azure memory

Provisioned using Azure CLI in the existing Blind Way Cosmos DB account:

- Database: `blindway`
- Container: `conversation-memory`
- Partition: `/partitionKey`, always derived from the authenticated user
- TTL: **604800 seconds (7 days)**

Authenticated vision-assistance users can read/write only their own memory through `/v1/live/memory`. Guardian accounts are rejected. Each stored entry contains an ID, timestamp, question and answer; no camera image or raw audio. Retrieval filters expiry explicitly and loads the latest 12 entries in chronological order. Cosmos TTL removes expired entries.

The Cloud Run relay accumulates transcripts in memory, then persists only after the phone acknowledges completed playback. Cancelled or incomplete answers are omitted. Persistence is outside the playback path. Reconnection loads historical exchanges as quoted context, with instructions that current images and the latest spoken question's language take priority. Memory can be inaccurate or incomplete; it does not provide perfect recall.

The live phone restored saved conversations after reconnecting and after an APK update. An English history question received the previous Hindi description; the model prompt was tightened to translate recalled details into the new question's language. Language behavior remains model-dependent.

## Checks

- 17 targeted Flutter live, voice and image-change tests passed.
- 34 Azure backend tests passed, including account isolation, guardian rejection, seven-day expiry and bounded retrieval.
- 20 relay tests passed, including playback acknowledgment, cancellation and malformed automatic requests.
- Flutter analysis reported no issues.
- The user confirmed automatic descriptions matched the changing view, including a hand making a peace sign, and subsequently confirmed buffered speech was smooth.
- Final build 10 automatic test recorded two completed replies: 116,160 samples (4.840 s) played in 4.968 s; 74,641 samples (3.110 s) played in 3.245 s. Later UI showed a changed observation of a hand with bracelets/threads, and Azure memory reached the 12-exchange loaded-context limit. These checks do not measure motion-to-speech latency, because camera movement was not timestamped.
- Final build 10 Stop question test cancelled static playback 234 ms after playback started, returned to ready, and did not complete or acknowledge that answer. The English question received English answer text following the prompt adjustment. Its fully buffered start delay was 8,299 ms after recording ended; the model took time to deliver the complete reply. This confirms smoothness is improved at the cost of start latency, not instant responses.

No real SOS was sent. Bluetooth earbuds and independent mobility safety were not tested. Background guardian push remains unconfigured.

## Installed artifact

Final Android build: **version code 10**, installed on vivo Y51A through ADB.

APK: `D:\Blind Way\Blind-Way-Camera-Fix.apk` (ARM64 debug build; signature verified).

SHA-256: `80A2A7616209D15DB380A44FE024F7B2991FECEDF36D0FDD38E14E4BE1E75D42`.

Cloud Run revision: `blindway-live-00005-jgr`. Azure Functions package includes the authenticated memory endpoint; both deployed health checks passed. Local test evidence is in `C:\Users\rkmai\AppData\Local\BlindWayAdbTest`.
