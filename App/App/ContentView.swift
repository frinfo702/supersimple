import AppKit
import SwiftUI

/// Top bar (Apple Notes style): sidebar toggle, search field, and the new-note
/// button live here, so the sidebar stays a clean list and layout never fights
/// over the header.
struct TopBar: View {
    @Bindable var model: AppModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            sidebarToggle

            searchField

            Spacer(minLength: 0)

            newNoteButton
        }
        // Align the controls with the macOS traffic-light buttons (hidden title bar)
        // and leave room on the left so the toggle doesn't overlap them.
        .padding(.leading, 70)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(Color(nsColor: AppTheme.Color.background))
    }

    // MARK: - Sidebar toggle

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                model.sidebarVisible.toggle()
            }
        } label: {
            SidebarIcon(lineWidth: 1.5)
                .foregroundStyle(Color.supersimpleMuted)
                .frame(width: 30, height: 30)
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.supersimpleMuted)
            TextField("Search notes", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
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
                        .font(.system(size: 12))
                        .foregroundStyle(Color.supersimpleMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                .fill(Color(nsColor: AppTheme.Color.sidebarBackground))
        )
    }

    // MARK: - New note

    private var newNoteButton: some View {
        Button {
            model.createNote()
        } label: {
            // The plus glyph is colored directly (no background box).
            PlusIcon(lineWidth: 1.6)
                .foregroundStyle(Color.supersimpleAccent)
                .frame(width: 30, height: 30)
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
    @State private var appLaunchTask: Task<Void, Never>?

    private static let toggleSidebarName = Notification.Name("supersimple.toggleSidebar")

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)

            Rectangle()
                .fill(AppTheme.hairline)
                .frame(height: AppTheme.Metric.hairlineWidth)

            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView(model: model)
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
        }
        .background(Color(nsColor: AppTheme.Color.background))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.supersimpleAccent)
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
