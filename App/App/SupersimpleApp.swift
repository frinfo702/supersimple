import SwiftUI

@main
struct SupersimpleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        // A single window app: avoids per-window command fan-out and the
        // ⌘N/New-Window conflict, and keeps one editor state in focus.
        Window("supersimple", id: "main") {
            ContentView()
                .environment(model)
                .environment(themeManager)
                .preferredColorScheme(themeManager.preference.colorScheme)
                .frame(minWidth: 900, minHeight: 560)
                .task { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands()
            ThemeCommands(themeManager: themeManager)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Weak reference set by the app so termination can flush edits even when no
    /// window/view is alive anymore.
    weak var model: AppModel?

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown()
        return .terminateNow
    }
}
