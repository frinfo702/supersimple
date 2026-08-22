import AppKit
import Testing

@testable import MarkdownEngine

@Suite("Markdown layout fragment rendering", .serialized)
@MainActor
struct MarkdownTextLayoutFragmentTests {
    @Test("Render plan follows attributed-text edits")
    func renderPlanInvalidation() throws {
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        guard let layoutManager = textView.textLayoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else {
            throw LayoutFragmentTestError.missingTextKitStack
        }

        textContainer.widthTracksTextView = false
        textContainer.size = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        layoutManager.delegate = layoutDelegate
        (layoutManager.textContentManager as? NSTextContentStorage)?.delegate = layoutDelegate

        textStorage.setAttributedString(NSAttributedString(
            string: "Highlighted text\n",
            attributes: [.font: NSFont.systemFont(ofSize: 16)]
        ))
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let initialFragment = try firstFragment(in: layoutManager)
        #expect(initialFragment.blockBackgroundFills(at: .zero).isEmpty)

        textStorage.addAttribute(
            .markdownBlockBackground,
            value: NSColor.systemYellow,
            range: NSRange(location: 0, length: 11)
        )
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let styledFragment = try firstFragment(in: layoutManager)
        #expect(!styledFragment.blockBackgroundFills(at: .zero).isEmpty)

        textStorage.removeAttribute(
            .markdownBlockBackground,
            range: NSRange(location: 0, length: textStorage.length)
        )
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        let clearedFragment = try firstFragment(in: layoutManager)
        #expect(clearedFragment.blockBackgroundFills(at: .zero).isEmpty)

        // Keep the weak TextKit delegates alive through all three layout passes.
        withExtendedLifetime(layoutDelegate) {}
    }

    private func firstFragment(in layoutManager: NSTextLayoutManager) throws -> MarkdownTextLayoutFragment {
        var result: MarkdownTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            result = fragment as? MarkdownTextLayoutFragment
            return false
        }
        guard let result else { throw LayoutFragmentTestError.missingFragment }
        return result
    }
}

private enum LayoutFragmentTestError: Error {
    case missingTextKitStack
    case missingFragment
}
