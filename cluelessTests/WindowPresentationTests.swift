import AppKit
import SwiftUI
import Testing
@testable import clueless

@MainActor
@Suite(.serialized)
struct WindowPresentationTests {
    @Test func showingFloatingWindowRecentersItOnThePointerDisplay() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }
        let screen = try #require(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2 + 40, y: screen.visibleFrame.midY - panel.frame.height / 2))

        controller.show(centered: true)

        #expect(abs(panel.frame.midX - screen.visibleFrame.midX) < 1)
        #expect(abs(panel.frame.midY - screen.visibleFrame.midY) < 1)
        #expect(screen.visibleFrame.contains(panel.frame))
    }

    @Test func reopeningPreservesPositionAndReusesThePanel() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }
        let screen = try #require(panel.screen)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2 + 40, y: screen.visibleFrame.midY - panel.frame.height / 2))
        let movedFrame = panel.frame
        controller.toggle()
        #expect(!panel.isVisible)
        controller.toggle()
        #expect(try floatingPanel() === panel)
        #expect(panel.frame == movedFrame)
    }

    @Test func floatingWindowStaysAboveAppsWithLegacyUnpinnedPreference() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "pinned")
        defaults.set(false, forKey: "pinned")
        defer {
            if let previous { defaults.set(previous, forKey: "pinned") }
            else { defaults.removeObject(forKey: "pinned") }
        }
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }

        controller.applySettings()

        #expect(panel.level == .floating)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.level.rawValue < NSWindow.Level.popUpMenu.rawValue)
    }

    @Test func screenReadingRestoresTheMovedWindowWithoutRecentering() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }
        let screen = try #require(panel.screen)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2 + 40, y: screen.visibleFrame.midY - panel.frame.height / 2))
        let movedFrame = panel.frame

        controller.suspendForScreenRead()
        #expect(!panel.isVisible)
        controller.show()
        #expect(!panel.isVisible)
        controller.restoreFromScreenRead()

        #expect(panel.isVisible)
        #expect(panel.frame == movedFrame)
    }

    @Test func automaticShowingPreservesTheUsersPosition() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show(focus: false)
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }
        let screen = try #require(panel.screen)
        #expect(abs(panel.frame.midX - screen.visibleFrame.midX) < 1)
        #expect(abs(panel.frame.midY - screen.visibleFrame.midY) < 1)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2 + 40, y: screen.visibleFrame.midY - panel.frame.height / 2))
        let movedFrame = panel.frame

        controller.show(focus: false)

        #expect(panel.frame == movedFrame)
    }

    @Test func screenReadingHidesAndRestoresOtherVisibleWindows() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.orderFrontRegardless()
        defer { settings.close(); panel.orderOut(nil) }
        #expect(controller.prepareForScreenRead())
        controller.suspendForScreenRead()
        #expect(!settings.isVisible)
        #expect(!panel.isVisible)
        controller.restoreFromScreenRead()
        #expect(settings.isVisible)
        #expect(panel.isVisible)
    }

    @Test func displayChangesRecoverAnOffscreenPanel() throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        defer { panel.orderOut(nil) }
        panel.setFrameOrigin(NSPoint(x: -100_000, y: -100_000))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })
    }

    @Test func screenReadingWaitsForAnOpenDialog() {
        let session = SessionCoordinator()
        session.prepareForScreenRead = { false }
        var suspended = false
        session.suspendPanelForScreenRead = { suspended = true }
        session.readScreen()
        #expect(session.screenReadState == .idle)
        #expect(!suspended)
        #expect(session.screenReadError != nil)
    }

    @Test(arguments: [false, true])
    func fileDialogsStayAboveTheirWindowAndReturnToItOnCancel(importing: Bool) async throws {
        let controller = FloatingPanelController(session: SessionCoordinator())
        controller.show()
        let panel = try floatingPanel()
        let screen = try #require(panel.screen)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2 + 40, y: screen.visibleFrame.midY - panel.frame.height / 2))
        let dialog = importing ? NSOpenPanel() : NSSavePanel()
        var result: NSApplication.ModalResponse?
        defer {
            if dialog.sheetParent != nil { panel.endSheet(dialog, returnCode: .cancel) }
            dialog.orderOut(nil)
            panel.orderOut(nil)
        }

        controller.presentFilePanel(dialog) { result = $0 }

        #expect(panel.attachedSheet === dialog)
        #expect(dialog.sheetParent === panel)
        #expect(dialog.level.rawValue > panel.level.rawValue)
        #expect(!dialog.hidesOnDeactivate)
        #expect(!controller.prepareForScreenRead())
        controller.applySettings()
        await Task.yield()
        #expect(dialog.isVisible)
        #expect(dialog.level.rawValue > panel.level.rawValue)
        let duplicate = NSSavePanel()
        controller.presentFilePanel(duplicate) { _ in Issue.record("Duplicate dialog must not be presented") }
        #expect(panel.attachedSheet === dialog)
        #expect(!duplicate.isVisible)
        #expect(!controller.windowShouldClose(panel))
        #expect(panel.isVisible)
        let attachedFrame = panel.frame
        controller.toggle()
        controller.show()
        #expect(panel.isVisible)
        #expect(panel.frame == attachedFrame)
        panel.endSheet(dialog, returnCode: .cancel)
        for _ in 0..<100 {
            if result != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(result == .cancel)
        #expect(panel.attachedSheet == nil)
        #expect(panel.isVisible)
    }

    private func floatingPanel() throws -> NSPanel {
        try #require(NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<FloatingPanelView> } as? NSPanel)
    }
}
