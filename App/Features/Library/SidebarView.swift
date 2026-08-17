import SupersimpleCore
import SwiftUI

/// Search, note selection, and tag filtering in a fixed-width library column.
struct SidebarView: View {
    @Bindable var model: AppModel
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            sectionLabel("Notes", count: model.visibleNotes.count)
            noteList

            if !model.allTags.isEmpty {
                Rectangle()
                    .fill(AppTheme.hairline)
                    .frame(height: AppTheme.Metric.hairlineWidth)
                    .padding(.horizontal, 20)
                tagIndex
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: AppTheme.Color.sidebarBackground))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("supersimple")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .italic()
                    .tracking(-0.6)
                Text(model.notes.count == 1 ? "1 note" : "\(model.notes.count) notes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.supersimpleMuted)
            }

            Spacer(minLength: 0)

            Button {
                model.createNote()
            } label: {
                PlusIcon(lineWidth: 1.5)
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                            .fill(Color.supersimpleAccent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("new-note-button")
            .accessibilityLabel("New note")
            .accessibilityHint("Creates a new note. Keyboard shortcut: Command-N.")
            .help("New note (⌘N)")
        }
        .padding(.top, 42)
        .padding(.horizontal, 22)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 9) {
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
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(searchIsFocused ? Color.supersimpleAccent : AppTheme.hairline)
                .frame(height: AppTheme.Metric.hairlineWidth)
        }
        .padding(.top, 24)
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    private func sectionLabel(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .tracking(1.4)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.supersimpleMuted)
        .padding(.horizontal, 22)
        .padding(.bottom, 9)
    }

    // MARK: - Note list

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if model.visibleNotes.isEmpty {
                    Text(model.searchQuery.isEmpty ? "No notes yet" : "No matching notes")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.supersimpleMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                } else {
                    ForEach(model.visibleNotes) { note in
                        NoteRow(note: note, isSelected: model.currentNoteID == note.id) {
                            model.select(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("notes-list")
    }

    // MARK: - Tags

    private var tagIndex: some View {
        VStack(spacing: 8) {
            sectionLabel("Tags", count: model.allTags.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(model.allTags, id: \.tag) { entry in
                        TagRow(tag: entry.tag, count: entry.count, isSelected: model.selectedTag == entry.tag) {
                            model.selectTag(entry.tag)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 14)
        .frame(maxHeight: 190)
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isSelected ? Color.supersimpleAccent : .clear)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.supersimpleMuted)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                    .fill(isSelected ? Color(nsColor: AppTheme.Color.selectionFill) : .clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.title)
        .accessibilityValue(preview)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: String {
        let body = note.body.replacingOccurrences(of: "\n", with: " ")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: #"^\s*#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
    }
}

private struct TagRow: View {
    let tag: Tag
    let count: Int
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.supersimpleAccent : Color.supersimpleMuted)
                Text(tag.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.supersimpleMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                    .fill(isSelected ? Color(nsColor: AppTheme.Color.selectionFill) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag #\(tag.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension AppTheme {
    /// Re-export a hairline `Color` for SwiftUI overlay usage.
    static var hairline: SwiftUI.Color { SwiftUI.Color(nsColor: AppTheme.Color.hairline) }
}
