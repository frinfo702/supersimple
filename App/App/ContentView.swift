import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var appLaunchTask: Task<Void, Never>?

    private static let toggleSidebarName = Notification.Name("supersimple.toggleSidebar")

    var body: some View {
        HSplitView {
            if model.sidebarVisible {
                SidebarView(model: model)
                    .frame(minWidth: 220, idealWidth: AppTheme.Metric.sidebarWidth)
            }
            EditorView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: AppTheme.Color.background))
        .onAppear {
            if appLaunchTask == nil {
                appLaunchTask = Task { await model.bootstrap() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("supersimple.newNote"))) { _ in
            model.createNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("supersimple.saveNow"))) { _ in
            model.saveNowPublic()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.toggleSidebarName)) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                model.sidebarVisible.toggle()
            }
        }
    }
}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.newNote"), object: nil)
            }
            .keyboardShortcut("n")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Now") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.saveNow"), object: nil)
            }
            .keyboardShortcut("s")
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.toggleSidebar"), object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}
