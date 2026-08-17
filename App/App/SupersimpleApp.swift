import SwiftUI

@main
struct SupersimpleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(themeManager)
                .preferredColorScheme(themeManager.preference.colorScheme)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands()
            ThemeCommands(themeManager: themeManager)
        }
        .defaultSize(width: 1100, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort flush; AppModel.shutdown() is also a safety net.
        NotificationCenter.default.post(name: Notification.Name("supersimple.saveNow"), object: nil)
    }
}
