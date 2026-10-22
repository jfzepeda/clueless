import AppKit
import SwiftUI
import Carbon

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let session: SessionCoordinator
    init(session: SessionCoordinator) { self.session = session }
    func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 460), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "clueless"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.minSize = NSSize(width: 330, height: 190)
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: FloatingPanelView(session: session))
            panel.center()
            panel.setFrameAutosaveName("AudioRouter.FloatingPanel")
            self.panel = panel
        }
        applySettings()
        clampToScreen()
        panel?.orderFrontRegardless()
    }
    func toggle() { if panel?.isVisible == true { panel?.orderOut(nil) } else { show() } }
    func applySettings() {
        panel?.level = session.settings.pinned ? .floating : .normal
        panel?.alphaValue = session.settings.opacity
        panel?.collectionBehavior = session.settings.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
    }
    private func clampToScreen() {
        guard let panel, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        panel.setFrame(frame, display: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
}

@MainActor
final class GlobalHotkeyManager {
    static let names = ["Hold", "Toggle", "Panel", "Generate", "Copy", "Stop"]
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
        guard Set(keys.values).count == keys.count else { throw RouterError("Each shortcut must use a different key.") }
        for (index, name) in Self.names.enumerated() {
            guard let key = keys[name] else { continue }
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
        session.showPanel = { [weak self] in self?.floating.show() }
        session.togglePanel = { [weak self] in self?.floating.toggle() }
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
