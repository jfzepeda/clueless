# Spec: Screen region text — v1

## Objective and user flow

In Live Transcription and Auto Answer, **Read Screen Region…** in the menu or Context tab lets the user drag a rectangle on a monitor. Releasing captures its current visible contents and recognizes text locally. Escape cancels; a click without an area leaves the selector open. A selection is clamped to the monitor where the drag starts. The screen is not frozen while selecting.

The default configurable shortcut is Control + Option + S. Existing assignments are preserved: if S is occupied, Read Screen starts unassigned. Unassigned shortcuts are not registered.

The floating panel is hidden during the operation and restored only if previously visible. ScreenCaptureKit excludes the application's windows and the cursor. The capture uses display-local top-left points and the selected monitor's pixel scale, including monitors positioned above or left of the primary display.

The **Screen Text** section shows recognized text, display name, capture time, character count, Copy, Remove, and a new capture action. Text is editable. Recognition automatically replaces the previous screen context; no review confirmation is required. A successful capture does not generate a response. The UI explains that subsequent responses, including Auto Answer, use this text automatically. A capture is a point-in-time reference, not a live view.

## Architecture and context

Use existing native frameworks, sandbox and deployment target. `ScreenRegionSelector` owns temporary AppKit selection panels; `ScreenReader` independently orchestrates screen permission, region capture and Vision recognition. `SessionCoordinator` owns the asynchronous operation and its state (`idle`, `selecting`, `capturing`, `recognizing`). Views only invoke coordinator actions. No audio buffers or transcription connections are reused for image capture.

Capture uses SCScreenshotManager, SCContentFilter and SCStreamConfiguration.sourceRect. Vision uses VNRecognizeTextRequest with accurate recognition, automatic language detection and language correction disabled. Recognition runs outside MainActor; best candidates are grouped into lines and ordered top to bottom, then left to right. Exact table, column, formula and code indentation reconstruction is not guaranteed.

`ResponseContext` owns one optional screen element containing text, display identifier/name, selected source rectangle and capture time. Notes, imported files and screen text share the existing 48,000-character limit. Replacement subtracts the previous screen element first. Oversized, empty or invalid results fail atomically without truncating or overwriting prior material. Valid edits affect subsequent requests; empty edits remove the element.

Manual chat and Auto Answer use the existing shared generation path, including screen-only questions without audio. Requests label screen material as quoted reference data, not instructions, heard speech or a current live screen view. Each response retains the context snapshot taken when generation starts. Waiting automatic responses use the context available when they start. Existing transcript/history budgets remain unchanged.

## Lifecycle and privacy

Only one logical screen-reading operation is active. Operation identifiers prevent cancelled or superseded work from applying late results or changing the current state. Screen errors do not stop audio or text generation. Cancellation, permission denial, unavailable displays, OCR failure, empty output and limit errors keep existing context and explain the result.

- Remove cancels pending work and removes only screen context.
- Clear Context and Clear Session History cancel pending work and clear screen text along with other context.
- Stop All, mode changes, sleep and quit cancel screen work. Stop All and mode changes retain committed context. No screen capture resumes on wake.
- Quit discards session data. Removing context does not retract sent requests or erase previous replies that quote it.

Screen recording permission is requested only on explicit screen-reading use. No Accessibility or keyboard-monitoring permission, API key or active listening is needed for OCR. Images exist only in memory and are released after processing; neither images nor recognized text are automatically saved or logged. Only reference text is sent to OpenAI during response generation. No images are uploaded, and no automatic capture retries occur.

Out of scope: TTS, continuous monitoring, window selection, cloud vision, OCR of imported PDFs and offscreen content.

## Verification

Swift Testing covers atomic replacement and limits, screen-only requests, source labels, immutable request snapshots, coordinate conversion on offset/Retina displays, shortcut migration, local Spanish/English OCR, independent errors, and cancellation with late results. Coordinator tests inject a pending reader and never request screen permission or call OpenAI.

```sh
xcodebuild -project clueless.xcodeproj -scheme clueless -configuration Debug -derivedDataPath /tmp/AudioRouterBuild build CODE_SIGNING_ALLOWED=NO
xcodebuild -project clueless.xcodeproj -scheme clueless -destination 'platform=macOS' -derivedDataPath /tmp/AudioRouterBuild test -only-testing:cluelessTests CODE_SIGNING_ALLOWED=NO
```

No standalone lint command is configured. Interactive acceptance remains necessary for native permissions, drag/Escape behavior, panel restoration and exclusion, multiple physical monitors/Spaces, monitor removal, simultaneous real audio capture, and actual response generation with the user's key. No paid requests are made during development.

Implementation verification: Debug build and all 37 unit test cases passed. Native UI inspection was attempted but the computer-use service timed out before returning app state; interactive acceptance remains unverified.

## References

- [ScreenCaptureKit source rectangle](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect)
- [Screen content filters](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
