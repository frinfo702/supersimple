import AppKit
import SupersimpleCore
import SwiftUI

/// Toolbar chrome: sidebar toggle next to the traffic lights, theme mark on the
/// right. New note and search live in the library.
struct TopBar: ToolbarContent {
    @Bindable var model: AppModel
    var isDark: Bool
    @Environment(ThemeManager.self) private var themeManager

    private var muted: Color { AppTheme.mutedColor(isDark: isDark) }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            sidebarToggle
                .immediateToolbarChrome(isDark: isDark)
        }
        ToolbarItem(placement: .primaryAction) {
            themeButton
                .immediateToolbarChrome(isDark: isDark)
        }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                model.sidebarVisible.toggle()
            }
        } label: {
            SidebarIcon(lineWidth: 1.5)
                .foregroundStyle(muted)
                .frame(width: 18, height: 18)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toggle-sidebar-button")
        .accessibilityLabel("Toggle sidebar")
        .accessibilityHint("Shows or hides the sidebar. Keyboard shortcut: Option-Command-S.")
        .help("Toggle sidebar (⌥⌘S)")
    }

    private var themeButton: some View {
        Button {
            themeManager.cycle()
        } label: {
            Group {
                if isDark {
                    DarkThemeIcon(lineWidth: 1.5)
                } else {
                    LightThemeIcon(lineWidth: 1.5)
                }
            }
            .foregroundStyle(muted)
            .frame(width: 16, height: 16)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("current-theme-icon")
        .accessibilityLabel(isDark ? "Switch to Light" : "Switch to Dark")
        .accessibilityHint("Toggles Light and Dark. Keyboard shortcuts: Shift-Command-L and Shift-Command-D.")
        .help(isDark ? "Switch to Light" : "Switch to Dark")
    }
}

extension View {
    /// Pins toolbar items to the resolved scheme and drops implicit animation so
    /// wells / icons snap with the window instead of interpolating a beat later.
    fileprivate func immediateToolbarChrome(isDark: Bool) -> some View {
        self
            .environment(\.colorScheme, isDark ? .dark : .light)
            .transaction { $0.animation = nil }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var appLaunchTask: Task<Void, Never>?

    private var isDark: Bool { themeManager.isDark(matching: colorScheme) }

    var body: some View {
        Group {
            if model.sidebarVisible {
                HSplitView {
                    SidebarView(model: model)
                        .frame(
                            minWidth: AppTheme.Metric.sidebarMinWidth,
                            idealWidth: model.sidebarWidth,
                            maxWidth: AppTheme.Metric.sidebarMaxWidth
                        )
                        .background(sidebarWidthReader)
                    editorColumn
                }
            } else {
                editorColumn
            }
        }
        .background(Color(nsColor: AppTheme.Color.background))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.supersimpleAccent)
        .background(WindowChrome(title: windowTitle))
        .toolbarBackground(AppTheme.backgroundColor(isDark: isDark), for: .windowToolbar)
        .toolbarColorScheme(isDark ? .dark : .light, for: .windowToolbar)
        .animation(nil, value: themeManager.preference)
        .toolbar {
            TopBar(model: model, isDark: isDark)
        }
        .onAppear {
            if appLaunchTask == nil {
                appLaunchTask = Task { await model.bootstrap() }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { model.notePendingDelete != nil },
                set: { if !$0 { model.notePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let note = model.notePendingDelete {
                    model.deleteNote(note)
                }
                model.notePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                model.notePendingDelete = nil
            }
        } message: {
            Text("The Markdown file will be removed from disk. This cannot be undone.")
        }
    }

    private var editorColumn: some View {
        EditorView(model: model)
            .frame(
                minWidth: AppTheme.Metric.editorMinWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .layoutPriority(1)
    }

    private var windowTitle: String {
        model.currentNote()?.title ?? "supersimple"
    }

    private var sidebarWidthReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: SidebarWidthKey.self, value: geo.size.width)
        }
        .onPreferenceChange(SidebarWidthKey.self) { width in
            guard width > 1, abs(width - model.sidebarWidth) > 1 else { return }
            model.sidebarWidth = width
        }
    }
}

private struct SidebarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AppCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                model.createNote()
            }
            .keyboardShortcut("n")
            Button("Import Notes…") {
                model.presentImportPanel()
            }
            .keyboardShortcut("o")
            Button("Export Note…") {
                model.presentExportPanel()
            }
            .keyboardShortcut("e")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Now") {
                model.saveNowPublic()
            }
            .keyboardShortcut("s")
        }
        CommandGroup(after: .pasteboard) {
            Button("Delete Note") {
                // The editor consumes ⌘⌫ itself (delete current line). Skip when
                // any text input is first responder so a search-field ⌘⌫ cannot
                // delete the open note either.
                if let first = NSApp.keyWindow?.firstResponder, first is NSText {
                    return
                }
                model.requestDelete()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.sidebarVisible.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Search Notes") {
                model.focusSearch()
            }
            .keyboardShortcut("l")
        }
    }
}
