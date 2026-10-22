# Audio Router MVP

The supplied PRODUCT_SPEC.md is the product contract. Implement section 13 first.

## Decisions and order
1. Native menu bar lifecycle, independent capture/processing/UI state, memory-only history.
2. ScreenCaptureKit system audio and AVAudioEngine microphone; 24 kHz mono PCM16 pipeline.
3. Core Audio device discovery and AVAudioEngine output to BlackHole, without changing defaults.
4. Realtime transcription with client-side SoundAnalysis speech classification and item reconciliation; Responses text streaming.
5. Floating NSPanel, Settings/Keychain, configurable Carbon global shortcuts.
6. Unit tests for activation, transcript reconciliation, VAD; build and manual device checks.

Use existing Swift style (four spaces, named types), system frameworks only. Credentials are entered later in Settings, never environment files. No live API calls during development. No automatic listening on launch. Mixed sources and field insertion are phase two. Normal system playback supplies headphone monitoring; do not replay captured audio to normal output.

## Verification
`xcodebuild -project clueless.xcodeproj -scheme clueless -configuration Debug -derivedDataPath /tmp/AudioRouterBuild build CODE_SIGNING_ALLOWED=NO`

`xcodebuild -project clueless.xcodeproj -scheme clueless -destination 'platform=macOS' -derivedDataPath /tmp/AudioRouterBuild test -only-testing:cluelessTests CODE_SIGNING_ALLOWED=NO`

Always: preserve capture ordering, bound queues, cancel stale tasks, show actual state. Never: log keys/audio, persist recordings, change system default devices. Device permissions, real BlackHole routing and paid API behavior need interactive validation.

## API references
- https://developers.openai.com/api/docs/guides/realtime-transcription
- https://developers.openai.com/api/docs/guides/streaming-responses

Realtime uses session.update, PCM16 at 24000 Hz, turn_detection null, client commits. History timestamps are local receipt times, not word timestamps. Queue overflow fails visibly rather than silently losing speech. Network recovery discards unsent audio, never replays old audio, retries at 1/2/4 seconds and then requires manual restart. HTTP/auth/rate-limit/API errors do not retry automatically.

## Updated mode behavior
Live Transcription includes manual conversation chat. AI Assistant is renamed Auto Answer, with migration of its saved preference. Auto Answer processes every nonempty completed speech turn: answer questions when present, otherwise summarize. The model determines whether there are questions; punctuation is not a trigger. Local VAD pauses/release define turns, while 15-second transport commits do not. Transcription finals are assembled in commit order before generation, deduplicated, and queued serially (32 waiting turns maximum, visible overflow error). Graceful stop/release allows pending turns to finish; Stop All or a mode change cancels them. The previous optional automatic-suggestions setting and cooldown are removed.

Speech activity is classified on device with Apple’s built-in SoundAnalysis classifier, using 0.5-second windows and 50% overlap. A speech confidence of at least 0.5, higher than singing confidence, resets the 0.8-second pause timer. RMS remains only an audio-level indicator. The latest classification adds window/inference latency; all captured PCM continues to be sent for transcription. Classifier errors stop capture visibly instead of falling back to amplitude detection. Virtual Microphone bypasses classification.
