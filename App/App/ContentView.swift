import AppKit
import SupersimpleCore
import SwiftUI

/// Native unified toolbar so glyphs sit on the same row as the traffic lights.
/// Leading glyphs share one item so their spacing stays tight; `.id` forces a
/// fresh slot size when search/plus appear so macOS does not clip them.
struct TopBar: ToolbarContent {
    @Bindable var model: AppModel
    var isDark: Bool
    var palette: PaletteColors
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppUpdater.self) private var updater

    private var muted: Color { palette.muted }

    var body: some ToolbarContent {
        // One item (not a growing stack of items) so macOS sizes the slot for
        // the full glyph row and does not clip search/plus when the library hides.
        GlyphToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                chromeButton(
                    identifier: "toggle-sidebar-button",
                    label: "Toggle sidebar",
                    hint: "Shows or hides the sidebar. Keyboard shortcut: Option-Command-S.",
                    help: "Toggle sidebar (⌥⌘S)",
                    size: 18
                ) {
                    SidebarIcon(lineWidth: 1.5)
                } action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        model.sidebarVisible.toggle()
                    }
                }
                if !model.sidebarVisible {
                    chromeButton(
                        identifier: "sidebar-search-button",
                        label: "Search",
                        hint: "Opens the library and focuses search. Keyboard shortcut: Command-L.",
                        help: "Search notes (⌘L)"
                    ) {
                        SearchIcon(lineWidth: 1.5)
                    } action: {
                        model.focusSearch()
                    }
                    chromeButton(
                        identifier: "new-note-button",
                        label: "New Note",
                        hint: "Creates a new note. Keyboard shortcut: Command-N.",
                        help: "New Note (⌘N)"
                    ) {
                        PlusIcon(lineWidth: 1.5)
                    } action: {
                        model.createNote()
                    }
                }
                chromeButton(
                    identifier: "current-theme-icon",
                    label: isDark ? "Switch to Light" : "Switch to Dark",
                    hint: "Toggles Light and Dark. Keyboard shortcuts: Shift-Command-L and Shift-Command-D.",
                    help: isDark ? "Switch to Light" : "Switch to Dark"
                ) {
                    Group {
                        if isDark {
                            DarkThemeIcon()
                        } else {
                            LightThemeIcon()
                        }
                    }
                } action: {
                    themeManager.cycle()
                }
            }
            .id(model.sidebarVisible)
        }
        if updater.availableUpdateVersion != nil {
            GlyphToolbarItem(placement: .confirmationAction) {
                Button("Update") {
                    model.flushNow()
                    updater.installAndRelaunch()
                }
                .buttonStyle(.plain)
                .foregroundStyle(muted)
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("update-app-button")
                .accessibilityLabel("Update")
                .accessibilityHint("Restarts supersimple to install the downloaded update.")
                .help("Install update and restart")
            }
        }
    }

    private func chromeButton<Icon: View>(
        identifier: String,
        label: String,
        hint: String,
        help: String,
        size: CGFloat = 16,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon()
                .foregroundStyle(muted)
                .frame(width: size, height: size)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .help(help)
    }
}

private struct GlyphToolbarItem<Label: View>: ToolbarContent {
    var placement: ToolbarItemPlacement
    @ViewBuilder var label: () -> Label

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) {
                label()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) {
                label()
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var appLaunchTask: Task<Void, Never>?
    @StateObject private var terminalSession = TerminalSession()

    private var isDark: Bool { themeManager.isDark(matching: colorScheme) }
    private var palette: PaletteColors { themeManager.paletteColors(isDark: isDark) }

    var body: some View {
        VStack(spacing: 0) {
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
            terminalStrip
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .tint(palette.accent)
        .environment(\.palette, palette)
        .toolbar { TopBar(model: model, isDark: isDark, palette: palette) }
        .toolbarBackground(palette.background, for: .windowToolbar)
        .background(WindowChrome(title: windowTitle, background: palette.nsBackground))
        .animation(nil, value: themeManager.preference)
        .animation(nil, value: themeManager.paletteID)
        .onAppear {
            if appLaunchTask == nil {
                appLaunchTask = Task { await model.bootstrap() }
            }
            if model.terminalVisible {
                terminalSession.prepare()
            }
        }
        .onChange(of: model.terminalVisible) { _, visible in
            if visible {
                terminalSession.prepare()
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

    @ViewBuilder
    private var terminalStrip: some View {
        @Bindable var bindableModel = model
        if let context = terminalSession.context {
            TerminalPanel(
                context: context,
                height: $bindableModel.terminalHeight,
                visible: model.terminalVisible,
                focusToken: model.terminalFocusToken,
                palette: palette
            )
            .frame(height: model.terminalVisible ? model.terminalHeight : 0)
            .clipped()
            .opacity(model.terminalVisible ? 1 : 0)
            .allowsHitTesting(model.terminalVisible)
            .accessibilityHidden(!model.terminalVisible)
            .id(ObjectIdentifier(context))
        }
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
    @Bindable var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(updater.isChecking ? "Checking for Updates…" : "Check for Updates…") {
                Task { await checkForUpdatesFromMenu() }
            }
            .disabled(updater.isChecking)
        }
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
            Button("Toggle Terminal") {
                model.toggleTerminal()
            }
            .keyboardShortcut("j")
        }
    }

    @MainActor
    private func checkForUpdatesFromMenu() async {
        switch await updater.checkAndDownloadIfNeeded() {
        case .ready, .alreadyChecking:
            break
        case .upToDate:
            presentUpdateAlert(
                title: "You're up to date",
                message: "supersimple \(updater.currentVersionString) is the latest version."
            )
        case .failed:
            presentUpdateAlert(
                title: "Couldn't check for updates",
                message: "Make sure you're online and try again."
            )
        case .disabled:
            presentUpdateAlert(
                title: "Updates unavailable",
                message: "This copy of supersimple doesn't install GitHub updates (Xcode and test builds)."
            )
        }
    }

    private func presentUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
