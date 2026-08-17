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
        Group {
            if let note = model.currentNote() {
                liveEditor(for: note)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: AppTheme.Color.background))
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
        .background(Color(nsColor: AppTheme.Color.background))
    }

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { model.currentNoteID == note.id ? model.currentBody : note.body },
            set: { model.noteBodyEdited($0) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No note selected")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Concentrates engine configuration (theme + services + typography).
enum EditorConfiguration {
    static func build() -> MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default

        var theme = MarkdownEditorTheme.default
        theme.bodyText = .labelColor
        theme.mutedText = .secondaryLabelColor
        theme.link = NSColor.systemBlue
        theme.incompleteLink = NSColor.systemBlue.withAlphaComponent(0.7)
        config.theme = theme

        config.services = MarkdownEditorServices(
            syntaxHighlighter: NativeCodeHighlighter(),
            latex: SwiftMathBridge()
        )
        config.readingWidth = AppTheme.Metric.readingWidth
        config.paragraph.spacingFactor = 0.35
        config.paragraph.lineHeightExtraSpacing = 2
        config.textInsets = TextInsets(horizontal: 28, vertical: 28)
        return config
    }
}
