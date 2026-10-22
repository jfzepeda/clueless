# Audio Router

Native macOS menu bar audio utility built with SwiftUI, AppKit, ScreenCaptureKit and AVAudioEngine. Open `clueless.xcodeproj`, select the `clueless` scheme and Run. The existing project deployment target is macOS 26.5.

## First run

1. Find the waveform icon in the menu bar. The app has no permanent Dock icon or main window.
2. Open **Settings → OpenAI**, enter your key and click **Save to Keychain**. This can be done later. No key is bundled or stored in UserDefaults.
3. Select a mode and source. System Audio requests the macOS capture permission; Microphone requests only microphone access.
4. Start Listening or hold **Control + Option + Space**. The app asks before uploading audio for the first time each launch.
5. Open the floating window for transcripts and responses. Closing it only hides it.

## Modes

- **Virtual Microphone:** install [BlackHole](https://github.com/ExistentialAudio/BlackHole#installation-instructions), choose it in Settings → Audio, and select BlackHole as the microphone in the receiving app. Uses system audio, entirely locally. Keep normal output on headphones; do not enable monitoring of BlackHole in the receiver. System defaults are never changed.
- **AI Dictation:** microphone by default, streaming transcript with Copy. Automatic insertion is a phase-two feature.
- **Live Transcription:** incremental transcript with provisional and confirmed text, local timestamps, copying and TXT export, plus a chat for questions about the captured conversation. Responses are generated only on demand.
- **Auto Answer** (formerly AI Assistant): the same transcript and chat, plus automatic responses after each speech pause (0.8 seconds without detected speech, plus local classification latency) or Push-to-Listen release. The model detects questions by meaning and answers them; when there are no questions, it gives a brief summary of that turn. No suggestion toggle or cooldown is required. Transport chunks alone do not trigger responses; complete turns are queued in order without interrupting a visible response. Stop All, Stop Response and mode changes clear pending automatic requests. The queue holds up to 32 waiting turns and reports an error if full.

## Preloaded response context

Open the floating window’s **Context** tab to paste notes or **Add Files…** before listening. UTF-8 TXT/Markdown and PDFs with selectable text are supported; scanned PDFs require OCR elsewhere. Imports are limited to 10 MB per file and 48,000 total reference characters. Invalid imports leave existing context intact.

Manual chat and Auto Answer include the current reference material with each response. You can ask about context before capturing audio. Remove individual files or use **Clear Context**; **Clear Session History** also clears it. Changes apply to the next response. Context remains in memory until cleared or the app quits. Extracted text is sent to OpenAI only when generating responses; selecting a file does not upload it.

## Controls

All shortcuts use Control + Option. Keys can be reassigned in Settings → Shortcuts; click Apply Shortcuts after editing.

| Action | Default key |
|---|---|
| Push-to-Listen | Space |
| Toggle Listening | L |
| Floating window | P |
| Generate response | R |
| Copy latest response / transcript | C |
| Stop All | . |

Always Listening and temporary activation share one capture coordinator. Stop Listening finalizes pending transcription; Stop All cancels acquisition and active requests. Sleep suspends capture; only previously enabled persistent listening is resumed after wake. Changing an audio engine device configuration stops safely and asks for a manual restart.

## Data and limits

- Audio buffers are in memory only. No raw recording files are created.
- History remains in memory until cleared or the app exits. Export is explicit.
- Keychain stores the API key. HTTP and WebSocket requests use TLS directly to OpenAI.
- PCM16 mono 24 kHz is sent to Realtime. `gpt-live-transcribe` uses local SoundAnalysis speech classification and client commits, not server VAD. The classifier uses overlapping 0.5-second windows; volume alone does not keep a turn open. Singing can still be ambiguous and real-device validation is required.
- Capture buffers are bounded at 100 packets. An overflow stops the session with an error rather than hiding dropped speech.
- Network reconnect uses 1/2/4-second delays and drops audio while disconnected. API errors require manual intervention. Confirmed history is retained; audio is never replayed after reconnect.
- The local session upload limit defaults to 60 minutes. It is **not** a monetary budget or provider billing guarantee. Text-generation cost is not included or estimated.
- Assistant context uses the latest 24,000 transcript characters plus three prior responses. Older history remains available in the UI.
- Models and language hints are configurable and must be available to your OpenAI account. No live API requests were made during implementation.

## Build and tests

```sh
xcodebuild -project clueless.xcodeproj -scheme clueless -configuration Debug -derivedDataPath /tmp/AudioRouterBuild build CODE_SIGNING_ALLOWED=NO
xcodebuild -project clueless.xcodeproj -scheme clueless -destination 'platform=macOS' -derivedDataPath /tmp/AudioRouterBuild test -only-testing:cluelessTests CODE_SIGNING_ALLOWED=NO
```

Verified: Debug build and 17 unit tests (activation, final reconciliation, chronology, provisional context exclusion, VAD, PCM duration, chat mode availability, preference migration and pause-based turn assembly). No Swift compiler warnings. Xcode emits its standard notice about absent AppIntents metadata.

Interactive validation still required:

- Menu controls, Settings and floating panel behavior on actual monitors/Spaces. Automated UI inspection timed out.
- Permission denial/revocation and system audio from Zoom/Teams.
- Real BlackHole playback, headphone/device disconnection and sleep/wake.
- Keychain storage under the final signed app, model access, live STT, response streaming and reconnects with a real key.

## Scope

Implemented MVP foundations and integrations; real-device/API acceptance is not yet certified. Advanced source selection/mixing, automatic field insertion, configurable shortcut modifiers, detected-language UI, monetary budgeting, persistent history, advanced exports and multi-monitor preferences are not implemented. The supplied full product contract is in [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md); implementation decisions are in [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).
