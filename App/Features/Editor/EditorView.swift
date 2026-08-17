import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SupersimpleCore
import SwiftUI

/// Builds the `NativeTextViewWrapper` for a single note's live-preview editor.
/// Concentrates the engine's pre-1.0 API in one place.
struct EditorView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                editorSurface
                    .layoutPriority(1)

                // A slim vertical gradient accent on the right of the editor. Its width
                // scales with the available width; its height matches the window.
                gradientBand(width: bandWidth(for: geo.size.width))
            }
        }
        .background(Color(nsColor: AppTheme.Color.background))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Editor surface

    private var editorSurface: some View {
        ZStack {
            Color(nsColor: AppTheme.Color.editorSurface)
            if let note = model.currentNote() {
                liveEditor(for: note)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("editor-surface")
    }

    private func liveEditor(for note: Note) -> some View {
        NativeTextViewWrapper(
            text: binding(for: note),
            configuration: EditorConfiguration.build(),
            fontName: "SF Pro",
            fontSize: 16,
            documentId: note.id.uuidString,
            isEditable: true
        )
        .background(Color(nsColor: AppTheme.Color.editorSurface))
    }

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { model.currentNoteID == note.id ? model.currentBody : note.body },
            set: { model.noteBodyEdited($0, for: note.id) }
        )
    }

    // MARK: - Gradient band

    /// Width of the right gradient band, growing with the window but kept slim.
    private func bandWidth(for total: CGFloat) -> CGFloat {
        min(max(total * 0.11, 24), 160)
    }

    /// Full-height, square (unrounded) gradient strip filling its frame on the right
    /// edge. The container has a fixed width so the editor takes the remaining space.
    private func gradientBand(width: CGFloat) -> some View {
        Rectangle()
            .fill(AppTheme.editorGradient)
            .frame(width: width)
            .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("A quiet place\nfor clear thinking.")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .tracking(-1.2)
            Text("Choose a note, or create one with ⌘N.")
                .font(.system(size: 15))
                .foregroundStyle(Color.supersimpleMuted)
            Spacer()
        }
        .padding(52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Concentrates engine configuration (theme + services + typography).
enum EditorConfiguration {
    static func build() -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default

        var theme = MarkdownEditorTheme.default
        theme.bodyText = AppTheme.Color.editorText
        theme.mutedText = AppTheme.Color.mutedText
        theme.disabledText = AppTheme.Color.mutedText.withAlphaComponent(0.65)
        theme.headingMarker = AppTheme.Color.mutedText
        theme.link = AppTheme.Color.accent
        theme.incompleteLink = AppTheme.Color.accent.withAlphaComponent(0.7)
        config.theme = theme

        config.services = MarkdownEditorServices(
            syntaxHighlighter: NativeCodeHighlighter(),
            latex: SwiftMathBridge()
        )
        config.readingWidth = AppTheme.Metric.readingWidth
        config.paragraph.spacingFactor = 0.35
        config.paragraph.lineHeightExtraSpacing = 2
        config.textInsets = TextInsets(horizontal: 42, vertical: 40)
        return config
    }
}
