import SwiftUI

@main
struct SupersimpleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var themeManager = ThemeManager()
    @State private var updater = AppUpdater()

    var body: some Scene {
        // A single window app: avoids per-window command fan-out and the
        // ⌘N/New-Window conflict, and keeps one editor state in focus.
        Window("supersimple", id: "main") {
            ContentView()
                .environment(model)
                .environment(themeManager)
                .environment(updater)
                .preferredColorScheme(themeManager.preference.colorScheme)
                .animation(nil, value: themeManager.preference)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    appDelegate.model = model
                }
                .task {
                    appDelegate.model = model
                    await model.bootstrap()
                }
                .task {
                    await updater.checkAndDownloadIfNeeded()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(6 * 60 * 60))
                        await updater.checkAndDownloadIfNeeded()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(model: model)
            ThemeCommands(themeManager: themeManager)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Weak reference set by the app so termination can flush edits even when no
    /// window/view is alive anymore.
    weak var model: AppModel?

    func applicationWillResignActive(_ notification: Notification) {
        model?.flushNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown()
        return .terminateNow
    }
}
