import SupersimpleCore
import SwiftUI

/// Library column: Cursor-style action list, then recency-grouped notes.
/// Filter state lives on `AppModel` and is independent of the open note.
struct SidebarView: View {
    @Bindable var model: AppModel
    @FocusState private var searchIsFocused: Bool

    private var showsSearchField: Bool {
        searchIsFocused || model.isSearching
    }

    var body: some View {
        VStack(spacing: 0) {
            actionList
            if showsSearchField {
                searchField
            }
            if !model.allTags.isEmpty {
                tagChips
            }
            noteList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: AppTheme.Color.sidebarBackground))
        .onChange(of: model.searchFocusToken) { _, _ in
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsSearchField)
    }

    // MARK: - Actions

    private var actionList: some View {
        VStack(spacing: 2) {
            SidebarActionRow(
                title: "New Note",
                isPrimary: true,
                accessibilityIdentifier: "new-note-button",
                accessibilityHint: "Creates a new note. Keyboard shortcut: Command-N."
            ) {
                PlusIcon(lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            } action: {
                model.createNote()
            }

            SidebarActionRow(
                title: "Search",
                isSelected: showsSearchField,
                accessibilityIdentifier: "sidebar-search-button",
                accessibilityHint: "Focuses the note search field. Keyboard shortcut: Command-L."
            ) {
                SearchIcon(lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            } action: {
                model.focusSearch()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-actions")
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            SearchIcon(lineWidth: 1.4)
                .foregroundStyle(Color.supersimpleMuted)
                .frame(width: 13, height: 13)
            TextField(
                "",
                text: $model.searchQuery,
                prompt: Text("Search or #tag").foregroundStyle(Color.supersimpleMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($searchIsFocused)
            .accessibilityIdentifier("search-field")
            .accessibilityLabel("Search notes")
            .onChange(of: model.searchQuery) { _, _ in
                model.performSearch()
            }
            .onSubmit {
                if let first = model.visibleNotes.first {
                    model.open(first)
                    model.focusEditor()
                }
            }
            .onExitCommand {
                if model.isSearching {
                    model.closeSearch()
                } else {
                    searchIsFocused = false
                    model.focusEditor()
                }
            }

            if model.isSearching {
                Button {
                    model.closeSearch()
                    searchIsFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
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
                .fill(Color(nsColor: AppTheme.Color.editorSurface).opacity(0.7))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Tags

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.allTags, id: \.tag) { entry in
                    TagChip(
                        tag: entry.tag,
                        count: entry.count,
                        isSelected: model.selectedTag == entry.tag
                    ) {
                        model.selectTag(entry.tag)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 28)
        .padding(.bottom, 6)
    }

    // MARK: - Note list

    private var noteList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if model.visibleNotes.isEmpty {
                    Text(model.hasActiveFilter ? "No matches" : "No notes")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.supersimpleMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else if model.isSearching {
                    ForEach(model.visibleNotes) { note in
                        noteRow(note)
                    }
                } else {
                    ForEach(model.groupedVisibleNotes, id: \.group) { section in
                        sectionLabel(section.group.title)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(section.notes) { note in
                            noteRow(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: AppTheme.Color.sidebarBackground))
        .accessibilityIdentifier("notes-list")
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.return) {
            model.focusEditor()
            return .handled
        }
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            model.open(note)
        } label: {
            NoteRow(note: note, isSelected: model.currentNoteID == note.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Export…") {
                model.open(note)
                model.presentExportPanel()
            }
            Divider()
            Button("Delete…", role: .destructive) {
                model.requestDelete(note)
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let notes = model.visibleNotes
        guard !notes.isEmpty else { return }
        let current = notes.firstIndex(where: { $0.id == model.currentNoteID }) ?? 0
        let next: Int
        switch direction {
        case .up: next = max(0, current - 1)
        case .down: next = min(notes.count - 1, current + 1)
        default: return
        }
        model.open(notes[next])
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.supersimpleMuted)
    }
}

// MARK: - Action rows

/// Icon + label row. Primary is a filled rounded rect; others stay chrome-less until hover.
private struct SidebarActionRow<Icon: View>: View {
    let title: String
    var isPrimary: Bool = false
    var isSelected: Bool = false
    var accessibilityIdentifier: String
    var accessibilityHint: String
    @ViewBuilder var icon: () -> Icon
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            SidebarActionLabel(
                title: title,
                isPrimary: isPrimary,
                isSelected: isSelected,
                hovering: hovering,
                icon: icon
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .help(title)
    }
}

private struct SidebarActionLabel<Icon: View>: View {
    let title: String
    var isPrimary: Bool
    var isSelected: Bool
    var hovering: Bool
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        HStack(spacing: 10) {
            icon()
                .foregroundStyle(Color.primary.opacity(0.82))
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.88))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
        )
    }

    private var rowFill: Color {
        if isPrimary { return Color(nsColor: AppTheme.Color.editorSurface) }
        if isSelected { return Color(nsColor: AppTheme.Color.selectionFill) }
        if hovering { return Color(nsColor: AppTheme.Color.hoverFill) }
        return .clear
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(NoteStats.relativeUpdated(note.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.supersimpleMuted)
                    .lineLimit(1)
            }
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.supersimpleMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityLabel(note.title)
        .accessibilityValue(preview)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowFill: Color {
        if isSelected { return Color(nsColor: AppTheme.Color.selectionFill) }
        if hovering { return Color(nsColor: AppTheme.Color.hoverFill) }
        return .clear
    }

    private var preview: String { NoteStats.preview(from: note.body) }
}

private struct TagChip: View {
    let tag: Tag
    let count: Int
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("#\(tag.name)")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.supersimpleMuted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(nsColor: AppTheme.Color.selectionFill)
                            : Color(nsColor: AppTheme.Color.editorSurface).opacity(0.45)
                    )
            )
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag #\(tag.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
