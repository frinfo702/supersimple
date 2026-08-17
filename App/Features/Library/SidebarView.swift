import SupersimpleCore
import SwiftUI

/// Left-hand sidebar: a search field at the top, the (optionally tag-filtered)
/// note list below, and a compact tag index at the bottom.
struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
                .overlay(AppTheme.hairline)
            noteList
            Divider().overlay(AppTheme.hairline)
            tagIndex
        }
        .frame(minWidth: 220, idealWidth: AppTheme.Metric.sidebarWidth, maxHeight: .infinity)
        .background(Color(nsColor: AppTheme.Color.sidebarBackground))
        .animation(.easeOut(duration: 0.15), value: model.sidebarVisible)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: model.searchQuery) { old, new in
                    model.performSearch()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Note list

    private var noteList: some View {
        List(selection: selection) {
            ForEach(model.visibleNotes) { note in
                NoteRow(note: note)
                    .tag(note.id)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { model.currentNoteID },
            set: { newValue in
                if let id = newValue, let note = model.notes.first(where: { $0.id == id }) {
                    model.select(note)
                }
            }
        )
    }

    // MARK: - Tags

    private var tagIndex: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.allTags, id: \.tag) { entry in
                    TagRow(tag: entry.tag, count: entry.count, isSelected: model.selectedTag == entry.tag) {
                        model.selectTag(entry.tag)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 220)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var preview: String {
        let body = note.body.replacingOccurrences(of: "\n", with: " ")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading markdown heading markers for the preview.
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
            HStack(spacing: 6) {
                Text("#\(tag.name)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Metric.cornerRadius, style: .continuous)
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
