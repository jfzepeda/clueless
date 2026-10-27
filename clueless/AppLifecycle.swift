import AppKit
import SwiftUI
import Carbon

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var screenReadSuspended = false
    private var restoreAfterScreenRead = false
    private var suspendedWindows: [NSWindow] = []
    private let session: SessionCoordinator
    init(session: SessionCoordinator) {
        self.session = session
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func screensChanged() {
        guard panel?.attachedSheet == nil else { return }
        positionOnScreen(centered: false)
    }
    func show(centered: Bool = false, focus: Bool = true) {
        guard !screenReadSuspended else { return }
        let shouldCenter = centered || panel == nil
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 460), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "clueless"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.minSize = NSSize(width: 330, height: 190)
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: FloatingPanelView(session: session, presentFilePanel: { [weak self] dialog, completion in
                self?.presentFilePanel(dialog, completionHandler: completion)
            }))
            panel.setFrameAutosaveName("AudioRouter.FloatingPanel")
            self.panel = panel
        }
        applySettings()
        positionOnScreen(centered: shouldCenter && panel?.attachedSheet == nil)
        if focus && panel?.attachedSheet == nil { panel?.makeKeyAndOrderFront(nil) }
        panel?.orderFrontRegardless()
        if let sheet = panel?.attachedSheet { bringDialogForward(sheet) }
    }
    func toggle() {
        guard !screenReadSuspended else { return }
        if panel?.attachedSheet != nil { show(centered: false); return }
        if panel?.isVisible == true { panel?.orderOut(nil) } else { show() }
    }
    func presentFilePanel(_ dialog: NSSavePanel, completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        guard !screenReadSuspended, let panel else { return }
        if let sheet = panel.attachedSheet {
            bringDialogForward(sheet)
            return
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        dialog.level = .modalPanel
        dialog.hidesOnDeactivate = false
        dialog.collectionBehavior = panel.collectionBehavior
        dialog.beginSheetModal(for: panel) { result in
            dialog.orderOut(nil)
            completionHandler(result)
            panel.makeKeyAndOrderFront(nil)
        }
        bringDialogForward(dialog)
    }
    private func bringDialogForward(_ dialog: NSWindow) {
        NSApp.activate()
        // AppKit can change a sheet's level while attaching it.
        dialog.level = .modalPanel
        dialog.makeKeyAndOrderFront(nil)
        dialog.orderFrontRegardless()
    }
    func prepareForScreenRead() -> Bool {
        if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet != nil })?.attachedSheet {
            bringDialogForward(sheet)
            return false
        }
        return true
    }
    func suspendForScreenRead() {
        restoreAfterScreenRead = panel?.isVisible == true
        screenReadSuspended = true
        suspendedWindows = NSApp.windows.filter { $0 !== panel && $0.isVisible && $0.styleMask.contains(.titled) }
        suspendedWindows.forEach { $0.orderOut(nil) }
        panel?.orderOut(nil)
    }
    func restoreFromScreenRead() {
        screenReadSuspended = false
        suspendedWindows.forEach { $0.orderFrontRegardless() }
        suspendedWindows.removeAll()
        if restoreAfterScreenRead { show(focus: false) }
        restoreAfterScreenRead = false
    }
    func applySettings() {
        panel?.level = .floating
        panel?.alphaValue = session.settings.opacity
        panel?.collectionBehavior = session.settings.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        if let sheet = panel?.attachedSheet { bringDialogForward(sheet) }
    }
    private func positionOnScreen(centered: Bool) {
        guard let panel else { return }
        let targetScreen = centered ? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) : panel.screen
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = centered ? visible.midX - frame.width / 2 : max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = centered ? visible.midY - frame.height / 2 : max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        panel.setFrame(frame, display: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let sheet = sender.attachedSheet { bringDialogForward(sheet) }
        else { sender.orderOut(nil) }
        return false
    }
}

@MainActor
final class GlobalHotkeyManager {
    static let names = ["Hold", "Toggle", "Panel", "Generate", "Copy", "Stop", "Read Screen"]
    static let keys: [(String, UInt32)] = [("Space", 49), ("L", 37), ("P", 35), ("R", 15), ("C", 8), (".", 47), ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("G", 5), ("H", 4), ("J", 38), ("K", 40)]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var action: (String, Bool) -> Void
    init(action: @escaping (String, Bool) -> Void) {
        self.action = action
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id) - 1
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if GlobalHotkeyManager.names.indices.contains(index) { manager.action(GlobalHotkeyManager.names[index], pressed) }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ keys: [String: UInt32]) throws {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        let assigned = keys.filter { $0.value != UInt32.max }
        guard Set(assigned.values).count == assigned.count else { throw RouterError("Each shortcut must use a different key.") }
        for (index, name) in Self.names.enumerated() {
            guard let key = assigned[name] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x41525452, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
                throw RouterError("Could not register \(name) shortcut (\(status)). Choose a different key.")
            }
            refs.append(ref)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = SessionCoordinator()
    lazy var floating = FloatingPanelController(session: session)
    private var hotkeys: GlobalHotkeyManager?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        session.showPanel = { [weak self] focus in self?.floating.show(focus: focus) }
        session.centerPanel = { [weak self] in self?.floating.show(centered: true) }
        session.prepareForScreenRead = { [weak self] in self?.floating.prepareForScreenRead() ?? true }
        session.togglePanel = { [weak self] in self?.floating.toggle() }
        session.suspendPanelForScreenRead = { [weak self] in self?.floating.suspendForScreenRead() }
        session.restorePanelAfterScreenRead = { [weak self] in self?.floating.restoreFromScreenRead() }
        hotkeys = GlobalHotkeyManager { [weak self] name, pressed in
            guard let self else { return }
            if name == "Hold" { session.hold(pressed); return }
            guard pressed else { return }
            switch name {
            case "Toggle": session.toggleListening()
            case "Panel": floating.toggle()
            case "Generate": session.generate("Suggest a concise response to the latest captured question.")
            case "Copy": session.copy(session.replies.last?.text ?? session.history.confirmedText)
            case "Stop": session.stopAll()
            case "Read Screen": session.readScreen()
            default: break
            }
        }
        applyShortcuts()
    }
    func applyShortcuts() {
        do { try hotkeys?.register(session.settings.shortcuts) }
        catch { session.errorMessage = error.localizedDescription }
    }
    func applicationWillTerminate(_ notification: Notification) { session.stopAll() }
}
