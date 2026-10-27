import AppKit
import ScreenCaptureKit
import Vision

enum ScreenReadState: String {
    case idle, selecting, capturing, recognizing
}

struct ScreenRegion: Sendable {
    let displayID: UInt32
    let displayName: String
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    // AppKit uses global bottom-left coordinates; ScreenCaptureKit needs display-local top-left points.
    init(displayID: UInt32, displayName: String, globalRect: CGRect, displayFrame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.displayName = displayName
        let rect = globalRect.standardized.intersection(displayFrame).offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        sourceRect = CGRect(x: rect.minX, y: displayFrame.height - rect.maxY, width: rect.width, height: rect.height)
        pixelWidth = Int((rect.width * scale).rounded(.up))
        pixelHeight = Int((rect.height * scale).rounded(.up))
    }
}

@MainActor
protocol ScreenReading {
    func read(onState: @escaping (ScreenReadState) -> Void) async throws -> ScreenContext
    func cancel()
}

@MainActor
final class ScreenReader: ScreenReading {
    private let selector = ScreenRegionSelector()
    private var permissionAlert: NSAlert?

    func read(onState: @escaping (ScreenReadState) -> Void) async throws -> ScreenContext {
        if !CGPreflightScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Allow screen text capture?"
            alert.informativeText = "Select a region to recognize its text locally. Only recognized text is sent to OpenAI when generating responses; screenshots are never uploaded or saved."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            permissionAlert = alert
            NSApp.activate()
            alert.window.level = .modalPanel
            alert.window.hidesOnDeactivate = false
            let response = alert.runModal()
            permissionAlert = nil
            guard response == .alertFirstButtonReturn else { throw CancellationError() }
            try Task.checkCancellation()
            guard CGRequestScreenCaptureAccess() else {
                throw RouterError("Screen capture permission is unavailable. Enable clueless in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. Previous context was kept.")
            }
        }
        try Task.checkCancellation()
        onState(.selecting)
        let region = try await selector.select()
        try Task.checkCancellation()
        onState(.capturing)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }),
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID }),
              region.sourceRect.maxX <= screen.frame.width, region.sourceRect.maxY <= screen.frame.height else {
            throw RouterError("The selected display is no longer available or changed size. Select a new region. Previous context was kept.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = region.sourceRect
        config.width = region.pixelWidth
        config.height = region.pixelHeight
        config.showsCursor = false
        config.capturesAudio = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let capturedAt = Date()
        try Task.checkCancellation()
        onState(.recognizing)
        let work = Task.detached(priority: .userInitiated) { try ScreenTextRecognizer.recognize(image) }
        let text = try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
        try Task.checkCancellation()
        return ScreenContext(text: text, displayID: region.displayID, displayName: region.displayName,
                             sourceRect: region.sourceRect, capturedAt: capturedAt)
    }

    func cancel() {
        if let permissionAlert {
            NSApp.abortModal()
            permissionAlert.window.orderOut(nil)
        }
        selector.cancel()
    }
}

enum ScreenTextRecognizer {
    nonisolated static func recognize(_ image: CGImage) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        let observations = request.results ?? []
        // Group observations into lines before sorting horizontally; a pairwise tolerance
        // comparator alone is not transitive for observations with slightly different heights.
        var lines: [[VNRecognizedTextObservation]] = []
        for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            if let index = lines.firstIndex(where: { line in
                guard let first = line.first else { return false }
                return abs(first.boundingBox.midY - observation.boundingBox.midY) < min(first.boundingBox.height, observation.boundingBox.height) / 2
            }) {
                lines[index].append(observation)
            } else {
                lines.append([observation])
            }
        }
        return lines.map { line in
            line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
