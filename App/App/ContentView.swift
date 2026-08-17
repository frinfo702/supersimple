import SupersimpleCore
import SwiftUI

/// Toolbar chrome: sidebar toggle + search on the left (next to the traffic lights),
/// appearance / bottom-bar / export / new-note on the right.
struct TopBar: ToolbarContent {
    @Bindable var model: AppModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchIsFocused: Bool

    private var isDark: Bool { themeManager.isDark(matching: colorScheme) }
    private var muted: Color { AppTheme.mutedColor(isDark: isDark) }
    private var well: Color { AppTheme.sidebarBackgroundColor(isDark: isDark) }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 10) {
                sidebarToggle
                searchField
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            themePicker
            bottomBarToggle
            exportButton
            newNoteButton
        }
    }

    // MARK: - Sidebar toggle

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

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            SearchIcon(lineWidth: 1.4)
                .foregroundStyle(muted)
                .frame(width: 13, height: 13)
            TextField("Search notes", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchIsFocused)
                .accessibilityIdentifier("search-field")
                .accessibilityLabel("Search notes")
                .onChange(of: model.searchQuery) { _, _ in
                    model.performSearch()
                }

            if !model.searchQuery.isEmpty {
                Button {
                    model.closeSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                .fill(well)
        )
    }

    // MARK: - Appearance

    private var themePicker: some View {
        HStack(spacing: 0) {
            themeOption(
                icon: LightThemeIcon(lineWidth: 1.4),
                selected: !isDark,
                identifier: "theme-light-button",
                label: "Light appearance"
            ) {
                themeManager.preference = .light
            }
            themeOption(
                icon: DarkThemeIcon(lineWidth: 1.4),
                selected: isDark,
                identifier: "theme-dark-button",
                label: "Dark appearance"
            ) {
                themeManager.preference = .dark
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(well)
        )
        .accessibilityElement(children: .contain)
        .help("Appearance: \(isDark ? "Dark" : "Light")")
    }

    private func themeOption<Icon: View>(
        icon: Icon,
        selected: Bool,
        identifier: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .foregroundStyle(selected ? Color.supersimpleAccent : muted)
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.supersimpleAccent.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Bottom bar

    private var bottomBarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                model.bottomBarVisible.toggle()
            }
        } label: {
            BottomBarIcon(lineWidth: 1.5)
                .foregroundStyle(
                    model.bottomBarVisible ? Color.supersimpleAccent : muted
                )
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toggle-bottom-bar-button")
        .accessibilityLabel("Toggle bottom bar")
        .accessibilityHint("Shows or hides the word count and tags strip.")
        .help("Toggle bottom bar")
    }

    // MARK: - Export

    private var exportButton: some View {
        Button {
            model.presentExportPanel()
        } label: {
            DownloadIcon(lineWidth: 1.5)
                .foregroundStyle(muted)
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.currentNote() == nil)
        .accessibilityIdentifier("export-note-button")
        .accessibilityLabel("Export note")
        .accessibilityHint("Saves the current note as a Markdown file. Keyboard shortcut: Command-E.")
        .help("Export note (⌘E)")
    }

    // MARK: - New note

    private var newNoteButton: some View {
        Button {
            model.createNote()
        } label: {
            PlusIcon(lineWidth: 1.6)
                .foregroundStyle(Color.supersimpleAccent)
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-note-button")
        .accessibilityLabel("New note")
        .accessibilityHint("Creates a new note. Keyboard shortcut: Command-N.")
        .help("New note (⌘N)")
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var appLaunchTask: Task<Void, Never>?
    @State private var notePendingDelete: Note?

    private var isDark: Bool { themeManager.isDark(matching: colorScheme) }

    private static let toggleSidebarName = Notification.Name("supersimple.toggleSidebar")
    private static let toggleBottomBarName = Notification.Name("supersimple.toggleBottomBar")
    private static let exportNoteName = Notification.Name("supersimple.exportNote")
    private static let importNoteName = Notification.Name("supersimple.importNote")
    private static let deleteNoteName = Notification.Name("supersimple.deleteNote")
    private static let cycleThemeName = Notification.Name("supersimple.cycleTheme")

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView(model: model, notePendingDelete: $notePendingDelete)
                    .frame(width: AppTheme.Metric.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Rectangle()
                    .fill(AppTheme.hairline)
                    .frame(width: AppTheme.Metric.hairlineWidth)
            }

            EditorView(model: model)
                .frame(
                    minWidth: AppTheme.Metric.editorMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .layoutPriority(1)
        }
        .background(Color(nsColor: AppTheme.Color.background))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.supersimpleAccent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.bottomBarVisible {
                BottomBarView(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(WindowChrome())
        .toolbarBackground(AppTheme.backgroundColor(isDark: isDark), for: .windowToolbar)
        .toolbarColorScheme(isDark ? .dark : .light, for: .windowToolbar)
        .animation(nil, value: themeManager.preference)
        .toolbar {
            TopBar(model: model)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: Self.toggleBottomBarName)) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                model.bottomBarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.exportNoteName)) { _ in
            model.presentExportPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.importNoteName)) { _ in
            model.presentImportPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.deleteNoteName)) { _ in
            notePendingDelete = model.currentNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.cycleThemeName)) { _ in
            themeManager.cycle()
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { notePendingDelete != nil },
                set: { if !$0 { notePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let note = notePendingDelete {
                    model.deleteNote(note)
                }
                notePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                notePendingDelete = nil
            }
        } message: {
            Text("The Markdown file will be removed from disk. This cannot be undone.")
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
            Button("Import Notes…") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.importNote"), object: nil)
            }
            .keyboardShortcut("o")
            Button("Export Note…") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.exportNote"), object: nil)
            }
            .keyboardShortcut("e")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Now") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.saveNow"), object: nil)
            }
            .keyboardShortcut("s")
        }
        CommandGroup(after: .pasteboard) {
            Button("Delete Note") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.deleteNote"), object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.toggleSidebar"), object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Toggle Bottom Bar") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.toggleBottomBar"), object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Cycle Appearance") {
                NotificationCenter.default.post(name: Notification.Name("supersimple.cycleTheme"), object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}
