import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SupersimpleCore
import SwiftUI

/// Builds the `NativeTextViewWrapper` for a single note's live-preview editor.
/// Concentrates the engine's pre-1.0 API in one place.
struct EditorView: View {
    @Bindable var model: AppModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isWikiLinkActive = false
    @State private var pendingInlineReplacement: InlineReplacementRequest?
    @State private var activeWikiSelection: WikiLinkSelection?
    @State private var wikiPickerRect: CGRect = .zero
    @State private var wikiPickerIndex = 0
    @State private var backlinksExpanded = false
    @State private var hoveredBacklinkID: UUID?

    private var palette: PaletteColors {
        themeManager.paletteColors(isDark: themeManager.isDark(matching: colorScheme))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            palette.editor
            if let note = model.currentNote() {
                liveEditor(for: note)
            }
            wordCountOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.editor)
        .background(EditorFocusBeacon(token: model.editorFocusToken))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-surface")
        .overlay(alignment: .topTrailing) {
            if model.noteFindPresented {
                NoteFindBar(model: model, palette: palette)
                    .padding(.top, 14)
                    .padding(.trailing, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay {
            GeometryReader { proxy in
                if activeWikiSelection != nil {
                    let pickerWidth: CGFloat = 280
                    let pickerX = min(
                        max(20, wikiPickerRect.minX),
                        max(20, proxy.size.width - pickerWidth - 16)
                    )
                    let pickerY =
                        wikiPickerRect.maxY < proxy.size.height * 0.62
                        ? max(20, wikiPickerRect.maxY + 6)
                        : max(20, wikiPickerRect.minY - 285)
                    WikiLinkPicker(
                        notes: wikiSuggestions,
                        query: wikiQuery,
                        selectedIndex: wikiPickerIndex,
                        canCreate: canCreateWikiTarget,
                        palette: palette,
                        onSelect: { index in commitWikiSelection(at: index, openAfter: false) }
                    )
                    .frame(width: pickerWidth)
                    .offset(x: pickerX, y: pickerY)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            backlinkControl
                .padding(.leading, 16)
                .padding(.bottom, 10)
        }
        .animation(.easeOut(duration: 0.13), value: model.noteFindPresented)
        .onReceive(NotificationCenter.default.publisher(for: EditorFindNotifications.results)) {
            notification in
            guard let count = notification.userInfo?["count"] as? Int else { return }
            model.noteFindResultsDidChange(count: count)
        }
        .onChange(of: model.currentNoteID) { _, _ in
            if model.noteFindPresented {
                DispatchQueue.main.async { model.refreshNoteFind() }
            }
        }
        .onChange(of: model.currentBody) { _, _ in
            model.scheduleNoteFindRefresh()
        }
    }

    private func liveEditor(for note: Note) -> some View {
        NativeTextViewWrapper(
            text: binding(for: note),
            isWikiLinkActive: $isWikiLinkActive,
            pendingInlineReplacement: $pendingInlineReplacement,
            configuration: EditorConfiguration.build(
                imageStore: model.imageStore,
                faviconService: model.faviconService,
                notes: model.notes,
                palette: palette
            ),
            fontName: themeManager.editorFont.postScriptName,
            fontSize: themeManager.editorFontSize,
            styleRevision: themeManager.styleRevision,
            documentId: note.id.uuidString,
            isEditable: true,
            onPasteImage: model.pasteImageHandler,
            onLinkClick: { model.openLinkedNote(identifier: $0) },
            onCaretRectChange: { wikiPickerRect = $0 },
            onInlineSelectionChange: { state in
                guard let state else {
                    activeWikiSelection = nil
                    wikiPickerIndex = 0
                    return
                }
                switch state.kind {
                case .wikiLink:
                    activeWikiSelection = state.selection
                    wikiPickerIndex = 0
                case .imageEmbed:
                    activeWikiSelection = nil
                }
            },
            onInlinePreviewKey: handleWikiPreviewKey
        )
        .background(palette.editor)
    }

    private var wikiQuery: String {
        guard let placeholder = activeWikiSelection?.placeholder else { return "" }
        var value = placeholder
        if value.hasPrefix("[[") { value.removeFirst(2) }
        if value.hasSuffix("]]") { value.removeLast(2) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var wikiSuggestions: [Note] {
        let query = wikiQuery
        return model.notes
            .filter { note in
                note.id != model.currentNoteID
                    && (query.isEmpty || note.title.localizedCaseInsensitiveContains(query))
            }
            .sorted { lhs, rhs in
                let lhsPrefix =
                    lhs.title.range(
                        of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                let rhsPrefix =
                    rhs.title.range(
                        of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(7)
            .map { $0 }
    }

    private var canCreateWikiTarget: Bool {
        let query = wikiQuery
        guard !query.isEmpty, !query.contains("|"), !query.contains("]") else { return false }
        return !model.notes.contains {
            $0.title.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private var wikiPickerCount: Int {
        wikiSuggestions.count + (canCreateWikiTarget ? 1 : 0)
    }

    private func handleWikiPreviewKey(_ key: InlinePreviewKey) -> Bool {
        guard activeWikiSelection != nil else { return false }
        switch key {
        case .moveUp:
            guard wikiPickerCount > 0 else { return true }
            wikiPickerIndex = (wikiPickerIndex - 1 + wikiPickerCount) % wikiPickerCount
        case .moveDown:
            guard wikiPickerCount > 0 else { return true }
            wikiPickerIndex = (wikiPickerIndex + 1) % wikiPickerCount
        case .confirm:
            commitWikiSelection(at: wikiPickerIndex, openAfter: false)
        case .confirmAndOpen:
            commitWikiSelection(at: wikiPickerIndex, openAfter: true)
        case .cancel:
            activeWikiSelection = nil
            isWikiLinkActive = false
        }
        return true
    }

    private func commitWikiSelection(at index: Int, openAfter: Bool) {
        guard let selection = activeWikiSelection,
            let documentID = model.currentNoteID?.uuidString
        else { return }
        let target: Note?
        if wikiSuggestions.indices.contains(index) {
            target = wikiSuggestions[index]
        } else if canCreateWikiTarget, index == wikiSuggestions.count {
            target = model.createLinkedNote(named: wikiQuery)
        } else {
            target = nil
        }
        guard let target else { return }
        pendingInlineReplacement = InlineReplacementRequest(
            documentId: documentID,
            selection: selection,
            storageFragment: "[[\(target.title)|\(target.id.uuidString)]]",
            isImageEmbedMode: false
        )
        activeWikiSelection = nil
        isWikiLinkActive = false
        if openAfter {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                model.open(target)
            }
        }
    }

    @ViewBuilder
    private var backlinkControl: some View {
        if let note = model.currentNote() {
            let backlinks = model.backlinks(to: note)
            if !backlinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if backlinksExpanded {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(backlinks) { backlink in
                                Button {
                                    model.open(backlink)
                                    backlinksExpanded = false
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(backlink.title)
                                            .lineLimit(1)
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(
                                            cornerRadius: AppTheme.Metric.controlRadius,
                                            style: .continuous
                                        )
                                        .fill(hoveredBacklinkID == backlink.id ? palette.hover : .clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredBacklinkID = hovering ? backlink.id : nil
                                }
                            }
                        }
                        .frame(width: 250)
                        .padding(6)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
                    }
                    Button {
                        backlinksExpanded.toggle()
                    } label: {
                        Label("Linked from \(backlinks.count)", systemImage: "link")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Show notes that link here")
                }
            }
        }
    }

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { model.currentNoteID == note.id ? model.currentBody : note.body },
            set: { model.noteBodyEdited($0, for: note.id) }
        )
    }

    private var wordCountOverlay: some View {
        Text(wordLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.muted)
            .padding(.trailing, 16)
            .padding(.bottom, 10)
            .allowsHitTesting(false)
            .accessibilityIdentifier("word-count")
            .accessibilityLabel(wordLabel)
    }

    private var wordLabel: String {
        guard model.currentNote() != nil else { return "" }
        let count = model.currentWordCount
        return count == 1 ? "1 word" : "\(count) words"
    }
}

private struct WikiLinkPicker: View {
    let notes: [Note]
    let query: String
    let selectedIndex: Int
    let canCreate: Bool
    let palette: PaletteColors
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if notes.isEmpty, !canCreate {
                Text("No matching notes")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
            } else {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    pickerRow(
                        title: note.title,
                        icon: "doc.text",
                        selected: index == selectedIndex
                    ) {
                        onSelect(index)
                    }
                }
                if canCreate {
                    pickerRow(
                        title: "Create “\(query)”",
                        icon: "plus",
                        selected: selectedIndex == notes.count
                    ) {
                        onSelect(notes.count)
                    }
                }
            }
        }
        .padding(6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: AppTheme.Metric.hairlineWidth)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .accessibilityIdentifier("wiki-link-picker")
    }

    private func pickerRow(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? palette.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Concentrates engine configuration (theme + services + typography).
enum EditorConfiguration {
    static func build(
        imageStore: ImageStore,
        faviconService: FaviconService,
        notes: [Note],
        palette: PaletteColors
    ) -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default

        var theme = MarkdownEditorTheme.default
        theme.bodyText = palette.nsText
        theme.mutedText = palette.nsMuted
        theme.disabledText = palette.nsMuted.withAlphaComponent(0.65)
        theme.headingMarker = palette.nsMuted
        theme.link = palette.nsAccent
        theme.incompleteLink = palette.nsAccent.withAlphaComponent(0.7)
        theme.findMatchHighlight = palette.nsSearchHighlight
        theme.findCurrentMatchHighlight = palette.nsSearchCurrentHighlight
        config.theme = theme

        config.services = MarkdownEditorServices(
            wikiLinks: NoteWikiLinkResolver(notes: notes),
            images: imageStore,
            syntaxHighlighter: NativeCodeHighlighter(),
            latex: SwiftMathBridge(),
            favicons: faviconService,
            bus: MarkdownEditorBus(
                findClearHighlights: EditorFindNotifications.clear,
                findQuery: EditorFindNotifications.query,
                findResults: EditorFindNotifications.results
            )
        )
        config.readingWidth = AppTheme.Metric.readingWidth
        var headings = config.headings
        headings.fontMultipliers = [1.5, 1.28, 1.12, 1.0, 1.0, 1.0]
        config.headings = headings
        var paragraph = config.paragraph
        paragraph.spacingFactor = 0.28
        paragraph.lineHeightExtraSpacing = 4
        config.paragraph = paragraph
        config.textInsets = TextInsets(horizontal: 48, vertical: 36)
        return config
    }
}

/// Finds the editor `NSTextView` and makes it first responder when the token bumps.
private struct EditorFocusBeacon: NSViewRepresentable {
    var token: UInt

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard token > 0, context.coordinator.lastToken != token else { return }
        context.coordinator.lastToken = token
        DispatchQueue.main.async {
            guard let window = nsView.window, let textView = Self.firstTextView(in: window.contentView) else {
                return
            }
            window.makeFirstResponder(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastToken: UInt = 0
    }

    private static func firstTextView(in root: NSView?) -> NSTextView? {
        guard let root else { return nil }
        if let textView = root as? NSTextView { return textView }
        for child in root.subviews {
            if let found = firstTextView(in: child) { return found }
        }
        return nil
    }
}
