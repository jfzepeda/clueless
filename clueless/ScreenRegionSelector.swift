import AppKit

@MainActor
final class ScreenRegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<ScreenRegion, any Error>?
    private var displayObserver: NSObjectProtocol?
    private var selectionID = UUID()

    func select() async throws -> ScreenRegion {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let id = UUID()
            selectionID = id
            for screen in NSScreen.screens {
                guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
                let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setFrame(screen.frame, display: false)
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .statusBar
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.onCancel = { [weak self] in self?.cancel() }
                view.onSelect = { [weak self] rect in
                    let region = ScreenRegion(displayID: displayID, displayName: screen.localizedName,
                                              globalRect: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
                                              displayFrame: screen.frame, scale: screen.backingScaleFactor)
                    self?.finish(.success(region))
                }
                panel.contentView = view
                panels.append(panel)
                panel.orderFrontRegardless()
                panel.makeFirstResponder(view)
            }
            guard !panels.isEmpty else {
                finish(.failure(RouterError("No display is available for screen reading.")))
                return
            }
            let point = NSEvent.mouseLocation
            (panels.first { $0.frame.contains(point) } ?? panels.first)?.makeKey()
            displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard self?.selectionID == id else { return }
                    self?.finish(.failure(RouterError("Display configuration changed. Select a new region. Previous context was kept.")))
                }
            }
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<ScreenRegion, any Error>) {
        guard let pending = continuation else { return }
        continuation = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        pending.resume(with: result)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionSelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = clampedPoint(event)
        selection = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { updateSelection(event) }
    override func mouseUp(with event: NSEvent) {
        updateSelection(event)
        start = nil
        guard selection.width >= 1, selection.height >= 1 else { return }
        onSelect?(selection)
    }
    private func clampedPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: max(bounds.minX, min(point.x, bounds.maxX)), y: max(bounds.minY, min(point.y, bounds.maxY)))
    }
    private func updateSelection(_ event: NSEvent) {
        guard let start else { return }
        let point = clampedPoint(event)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(selection)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        shade.fill()
        if !selection.isEmpty {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        let text = "Drag to select text · Release to read · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let frame = CGRect(x: max(8, (bounds.width - size.width) / 2), y: bounds.height - 70, width: size.width + 24, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: frame.minX + 12, y: frame.minY + 8), withAttributes: attributes)
    }
}
