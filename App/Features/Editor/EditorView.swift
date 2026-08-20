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
    }

    private func liveEditor(for note: Note) -> some View {
        NativeTextViewWrapper(
            text: binding(for: note),
            configuration: EditorConfiguration.build(
                imageStore: model.imageStore,
                faviconService: model.faviconService,
                palette: palette
            ),
            fontName: themeManager.editorFont.postScriptName,
            fontSize: themeManager.editorFontSize,
            styleRevision: themeManager.styleRevision,
            documentId: note.id.uuidString,
            isEditable: true,
            onPasteImage: model.pasteImageHandler
        )
        .background(palette.editor)
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

/// Concentrates engine configuration (theme + services + typography).
enum EditorConfiguration {
    static func build(
        imageStore: ImageStore,
        faviconService: FaviconService,
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
        config.theme = theme

        config.services = MarkdownEditorServices(
            images: imageStore,
            syntaxHighlighter: NativeCodeHighlighter(),
            latex: SwiftMathBridge(),
            favicons: faviconService
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
