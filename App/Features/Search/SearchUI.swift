import SupersimpleCore
import SwiftUI

enum EditorFindNotifications {
    static let query = Notification.Name("supersimple.editor.find.query")
    static let results = Notification.Name("supersimple.editor.find.results")
    static let clear = Notification.Name("supersimple.editor.find.clear")
}

struct SearchHighlightPiece: Equatable {
    let text: String
    let highlighted: Bool
}

enum SearchHighlightParser {
    static func pieces(
        from source: String,
        query: String,
        usesSnippetMarkers: Bool
    ) -> [SearchHighlightPiece] {
        guard usesSnippetMarkers else { return queryPieces(from: source, query: query) }
        var pieces: [SearchHighlightPiece] = []
        var remainder = source[...]
        var foundMarker = false

        while let open = remainder.range(of: SearchResult.highlightStart),
            let close = remainder[open.upperBound...].range(of: SearchResult.highlightEnd)
        {
            pieces.append(SearchHighlightPiece(text: String(remainder[..<open.lowerBound]), highlighted: false))
            pieces.append(
                SearchHighlightPiece(
                    text: String(remainder[open.upperBound..<close.lowerBound]),
                    highlighted: true
                ))
            remainder = remainder[close.upperBound...]
            foundMarker = true
        }
        if foundMarker {
            pieces.append(SearchHighlightPiece(text: String(remainder), highlighted: false))
            return pieces
        }
        return queryPieces(from: source, query: query)
    }

    private static func queryPieces(from source: String, query: String) -> [SearchHighlightPiece] {
        guard !query.isEmpty else { return [SearchHighlightPiece(text: source, highlighted: false)] }
        var pieces: [SearchHighlightPiece] = []
        var remainder = source[...]
        while let match = remainder.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            pieces.append(SearchHighlightPiece(text: String(remainder[..<match.lowerBound]), highlighted: false))
            pieces.append(SearchHighlightPiece(text: String(remainder[match]), highlighted: true))
            remainder = remainder[match.upperBound...]
        }
        pieces.append(SearchHighlightPiece(text: String(remainder), highlighted: false))
        return pieces
    }
}

struct CommandSearchPalette: View {
    @Bindable var model: AppModel
    let palette: PaletteColors

    @FocusState private var searchFocused: Bool
    @State private var selectedIndex = 0

    private var trimmedQuery: String {
        model.commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fullTextQuery: String {
        trimmedQuery.split(whereSeparator: \.isWhitespace)
            .filter { !$0.hasPrefix("#") }
            .joined(separator: " ")
    }

    private var showsRecents: Bool {
        trimmedQuery.isEmpty && model.commandPaletteSelectedTag == nil
    }

    private var resultNotes: [Note] {
        if showsRecents {
            return Array(model.notes.prefix(12))
        }
        var notesByID: [UUID: Note] = [:]
        for note in model.notes { notesByID[note.id] = note }
        return model.commandPaletteResults.compactMap { notesByID[$0.noteID] }
    }

    private var matchingTags: [(tag: Tag, count: Int)] {
        let activeTags = model.commandPaletteActiveTags
        var entries = model.allTags.filter { activeTags.contains($0.tag) }
        var included = Set(entries.map(\.tag))
        let candidate = trimmedQuery.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let fragment = candidate.hasPrefix("#") ? String(candidate.dropFirst()) : candidate
        let suggestions =
            fragment.isEmpty
            ? model.allTags
            : model.allTags.filter { $0.tag.name.localizedCaseInsensitiveContains(fragment) }
        for entry in suggestions where !included.contains(entry.tag) {
            if entries.count >= max(7, activeTags.count) { break }
            entries.append(entry)
            included.insert(entry.tag)
        }
        return entries
    }

    private var selectedNote: Note? {
        guard resultNotes.indices.contains(selectedIndex) else { return resultNotes.first }
        return resultNotes[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            tagStrip
            Divider().overlay(palette.hairline)
            HStack(spacing: 0) {
                resultsPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(palette.hairline)
                previewPane
                    .frame(width: 270)
                    .frame(maxHeight: .infinity)
            }
            footer
        }
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    palette.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.72),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(palette.isDark ? 0.48 : 0.20), radius: 38, y: 18)
        .onAppear { focusSearch() }
        .onChange(of: model.commandPaletteFocusToken) { _, _ in focusSearch() }
        .onChange(of: model.commandPaletteResults) { _, _ in selectedIndex = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-search-palette")
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.muted)
            TextField(
                "",
                text: $model.commandPaletteQuery,
                prompt: Text("Search notes, text, or #tags…").foregroundStyle(palette.muted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium))
            .focused($searchFocused)
            .onChange(of: model.commandPaletteQuery) { _, _ in
                selectedIndex = 0
                model.performCommandPaletteSearch()
            }
            .onSubmit { openSelected() }
            .onExitCommand { model.dismissCommandPalette() }
            .onKeyPress(.downArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .accessibilityIdentifier("command-search-field")

        }
        .padding(.horizontal, 20)
        .frame(height: 66)
    }

    @ViewBuilder
    private var tagStrip: some View {
        if !matchingTags.isEmpty || model.commandPaletteSelectedTag != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Image(systemName: "tag")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.muted)
                    ForEach(matchingTags, id: \.tag) { entry in
                        PaletteTagChip(
                            tag: entry.tag,
                            count: entry.count,
                            selected: model.commandPaletteActiveTags.contains(entry.tag),
                            palette: palette
                        ) {
                            selectedIndex = 0
                            model.selectCommandPaletteTag(entry.tag)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 43)
        }
    }

    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(showsRecents ? "RECENT NOTES" : "SEARCH RESULTS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if resultNotes.isEmpty {
                ContentUnavailableView {
                    Label("No matches", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Try another word or choose a tag above.")
                }
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(resultNotes.enumerated()), id: \.element.id) { index, note in
                                resultRow(note, index: index)
                                    .id(note.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard resultNotes.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(resultNotes[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func resultRow(_ note: Note, index: Int) -> some View {
        let result = model.commandPaletteResults.first { $0.noteID == note.id }
        let snippet =
            result?.snippet.isEmpty == false
            ? result!.snippet
            : NoteStats.preview(from: note.body)
        return Button {
            selectedIndex = index
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(index == selectedIndex ? palette.accent : palette.muted)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 5) {
                    HighlightedSearchText(
                        text: note.title,
                        query: fullTextQuery,
                        palette: palette,
                        fontSize: 13,
                        weight: .semibold
                    )
                    .lineLimit(1)
                    if !snippet.isEmpty {
                        HighlightedSearchText(
                            text: snippet,
                            query: fullTextQuery,
                            palette: palette,
                            fontSize: 11,
                            weight: .regular,
                            usesSnippetMarkers: result?.snippet.isEmpty == false
                        )
                        .foregroundStyle(palette.muted)
                        .lineLimit(2)
                    }
                    if !note.tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(note.tags.sorted().prefix(3)), id: \.self) { tag in
                                Text("#\(tag.name)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(palette.muted)
                            }
                        }
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(index == selectedIndex ? palette.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                model.openFromCommandPalette(note)
            }
        )
        .accessibilityLabel(note.title)
    }

    @ViewBuilder
    private var previewPane: some View {
        if let note = selectedNote {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Spacer()
                    Text(NoteStats.relativeUpdated(note.updatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.muted)
                }
                Text(note.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(3)
                if !note.tags.isEmpty {
                    FlowTagPreview(tags: Array(note.tags.sorted()), palette: palette)
                }
                Divider().overlay(palette.hairline)
                ScrollView {
                    HighlightedSearchText(
                        text: previewText(for: note),
                        query: fullTextQuery,
                        palette: palette,
                        fontSize: 12,
                        weight: .regular,
                        usesSnippetMarkers: hasMarkedSnippet(for: note)
                    )
                    .foregroundStyle(palette.muted)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(palette.editor.opacity(0.20))
        } else {
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label("Move", systemImage: "arrow.up.arrow.down")
            Label("Open", systemImage: "return")
            Spacer()
            Text("esc to close")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 18)
        .frame(height: 36)
        .overlay(alignment: .top) { Divider().overlay(palette.hairline) }
    }

    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.editor.opacity(palette.isDark ? 0.54 : 0.38))
        }
    }

    private func previewText(for note: Note) -> String {
        if let snippet = model.commandPaletteResults.first(where: { $0.noteID == note.id })?.snippet,
            !snippet.isEmpty
        {
            return snippet
        }
        return String(note.body.prefix(900))
    }

    private func hasMarkedSnippet(for note: Note) -> Bool {
        model.commandPaletteResults.first(where: { $0.noteID == note.id })?.snippet.isEmpty == false
    }

    private func moveSelection(by delta: Int) {
        guard !resultNotes.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + resultNotes.count) % resultNotes.count
    }

    private func openSelected() {
        guard let note = selectedNote else { return }
        model.openFromCommandPalette(note)
    }

    private func focusSearch() {
        DispatchQueue.main.async { searchFocused = true }
    }
}

struct NoteFindBar: View {
    @Bindable var model: AppModel
    let palette: PaletteColors
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.muted)
            TextField(
                "",
                text: $model.noteFindQuery,
                prompt: Text("Find in note…").foregroundStyle(palette.muted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($focused)
            .onChange(of: model.noteFindQuery) { _, _ in model.noteFindQueryDidChange() }
            .onSubmit { model.moveNoteFind(by: 1) }
            .onExitCommand { model.dismissNoteFind() }
            .accessibilityIdentifier("note-find-field")

            Text(matchLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.muted)
                .frame(minWidth: 38)

            findButton(systemName: "chevron.up", label: "Previous match") {
                model.moveNoteFind(by: -1)
            }
            findButton(systemName: "chevron.down", label: "Next match") {
                model.moveNoteFind(by: 1)
            }
            findButton(systemName: "xmark", label: "Close find") {
                model.dismissNoteFind()
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 330, height: 42)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.editor.opacity(palette.isDark ? 0.58 : 0.42))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    palette.isDark ? Color.white.opacity(0.13) : Color.white.opacity(0.75),
                    lineWidth: 0.7
                )
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 7)
        .onAppear { focus() }
        .onChange(of: model.noteFindFocusToken) { _, _ in focus() }
        .accessibilityIdentifier("note-find-bar")
    }

    private var matchLabel: String {
        guard model.noteFindMatchCount > 0 else { return "0 / 0" }
        return "\(model.noteFindCurrentIndex + 1) / \(model.noteFindMatchCount)"
    }

    private func findButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.muted)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func focus() {
        DispatchQueue.main.async { focused = true }
    }
}

struct HighlightedSearchText: View {
    let text: String
    let query: String
    let palette: PaletteColors
    let fontSize: CGFloat
    let weight: Font.Weight
    var usesSnippetMarkers = false

    var body: some View {
        Text(attributedText)
            .font(.system(size: fontSize, weight: weight))
    }

    private var attributedText: AttributedString {
        var output = AttributedString()
        let pieces = SearchHighlightParser.pieces(
            from: text,
            query: query,
            usesSnippetMarkers: usesSnippetMarkers
        )
        for piece in pieces {
            var value = AttributedString(piece.text)
            if piece.highlighted {
                value.foregroundColor = palette.text
                value.backgroundColor = palette.searchHighlight
                value.font = .system(size: fontSize, weight: .semibold)
            }
            output.append(value)
        }
        return output
    }
}

private struct PaletteTagChip: View {
    let tag: Tag
    let count: Int
    let selected: Bool
    let palette: PaletteColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("#\(tag.name)")
                Text("\(count)").foregroundStyle(palette.muted)
            }
            .font(.system(size: 10, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                selected ? palette.selection : palette.text.opacity(0.055),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FlowTagPreview: View {
    let tags: [Tag]
    let palette: PaletteColors

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text("#\(tag.name)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(palette.text.opacity(0.05), in: Capsule())
            }
        }
    }
}
