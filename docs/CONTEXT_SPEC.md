# Spec: Preloaded response context

## Objective
Let users preload reference material before listening or asking questions. Both manual chat and Auto Answer use the material alongside the existing transcript and previous responses.

Proposed scope: a Context tab in the floating window with a pasted-text editor, an Add Files action, a list of imported filenames with extracted character counts, individual removal, and Clear Context. Text edits and file changes apply to the next response; a response already running retains its original snapshot.

Support UTF-8 TXT and Markdown, and PDFs with extractable text. Use local PDFKit extraction; scanned PDFs without text report an error (no OCR). Reject empty, unreadable, unsupported, or oversized imports with a visible explanation. Limit each file to 10 MB and total reference text to 48,000 characters. Reject excess material rather than silently truncating it. Import work must not block audio capture or the UI.

Context stays in memory until cleared or the app quits, matching session history. Clear Session History also clears context. Show that reference text is sent to OpenAI when generating responses. No separate file upload, persistent storage, or new dependency is required. Allow manual questions with reference context even before any audio has been captured.

## Tech Stack
Existing SwiftUI/AppKit macOS app (deployment target macOS 26.5), Foundation, PDFKit, Swift Testing, and existing OpenAI response client.

## Commands
Build:
```sh
xcodebuild -project clueless.xcodeproj -scheme clueless -configuration Debug -derivedDataPath /tmp/AudioRouterBuild build CODE_SIGNING_ALLOWED=NO
```
Tests:
```sh
xcodebuild -project clueless.xcodeproj -scheme clueless -destination 'platform=macOS' -derivedDataPath /tmp/AudioRouterBuild test -only-testing:cluelessTests CODE_SIGNING_ALLOWED=NO
```
Development: open clueless.xcodeproj and run the clueless scheme. No standalone lint command is currently documented.

## Project Structure
- clueless/Models.swift or a focused Context.swift: context items, validation, extraction, and request formatting.
- clueless/SessionCoordinator.swift: session-owned context and generation snapshot.
- clueless/ContentView.swift: Context tab and import controls.
- clueless/OpenAIClients.swift: distinguish reference material from captured speech in request input.
- cluelessTests/cluelessTests.swift: context and import tests.
- README.md: usage, supported formats, privacy, and limits.

## Code Style
Follow the existing four-space indentation, named Swift types, and small value types. Example:
```swift
struct RouterError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
```

## Testing Strategy
Use Swift Testing for text validation, aggregate limits, file extraction failures, text-based PDF extraction, removal/clearing, and request assembly. Verify reference material reaches the shared manual/automatic generation path without consuming the existing 24,000-character transcript allowance. Label material as reference data, not system instructions, and preserve filenames for attribution. Build and run all existing unit tests. Manually inspect the import picker, text editing, errors, and context-only chat where UI access permits. Do not make paid API requests during development.

## Boundaries
- Always: preserve existing user changes, audio behavior, request ordering, and current history limits; show import errors; release security-scoped file access after import.
- Ask first: persistent context storage, additional formats requiring dependencies, OCR, or remote file storage.
- Never: store API keys in files, upload files upon selection, silently drop reference content, or change unrelated code.

## Success Criteria
1. Users can paste text and import supported files before listening.
2. Both manual and automatic responses include a snapshot of active reference material.
3. Removing or clearing material excludes it from subsequent requests.
4. Unsupported, empty, invalid, or excessive input yields a visible error and preserves existing context.
5. Reference material and transcript are separately labeled; file names remain attached to their text.
6. The build and relevant unit tests pass; any unavailable interactive checks are disclosed.

## Approval and Implementation Plan
Scope approved by the user. Implement the context model and bounded local extraction, connect a session snapshot to the shared response path, add the Context tab, then verify with extraction/limit/request tests and the existing unit suite.
