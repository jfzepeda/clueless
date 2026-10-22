import SwiftUI

@main
struct cluelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("clueless", systemImage: delegate.session.symbol) {
            MenuBarView(session: delegate.session)
        }
        .menuBarExtraStyle(.window)
        Settings {
            RouterSettingsView(session: delegate.session, applyShortcuts: delegate.applyShortcuts, applyPanel: delegate.floating.applySettings)
        }
    }
}
