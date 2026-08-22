import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Blockquote caret styling")
struct BlockquoteCaretStylingTests {

    @Test("Inactive quote hides its marker and draws a bar")
    func inactiveQuoteUsesRenderedPresentation() {
        let attrs = styledAttributes(caret: -1)

        #expect(attrs.contains { styled in
            styled.range == NSRange(location: 0, length: 10)
                && styled.attributes[.blockquoteLevel] as? Int == 1
        })
        #expect(attrs.contains { styled in
            styled.range == NSRange(location: 0, length: 2)
                && (styled.attributes[.foregroundColor] as? NSColor) == .clear
        })
    }

    @Test("Quote under caret shows raw marker without a bar or quote indent")
    func activeQuoteUsesRawPresentation() {
        let attrs = styledAttributes(caret: 5)

        #expect(!attrs.contains { $0.attributes[.blockquoteLevel] != nil })
        #expect(!attrs.contains { $0.attributes[.paragraphStyle] != nil })
        #expect(attrs.contains { styled in
            styled.range == NSRange(location: 0, length: 2)
                && (styled.attributes[.foregroundColor] as? NSColor) != .clear
        })
    }

    @Test("Only the quote line containing the caret switches to raw presentation")
    func onlyActiveLineUsesRawPresentation() {
        let text = "> first\n> second"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: 3
        )

        let quoteBars = attrs.compactMap { styled -> (NSRange, Int)? in
            guard let level = styled.attributes[.blockquoteLevel] as? Int else { return nil }
            return (styled.range, level)
        }
        #expect(quoteBars.count == 1)
        #expect(quoteBars.first?.0 == NSRange(location: 8, length: 8))
        #expect(quoteBars.first?.1 == 1)
    }

    private func styledAttributes(caret: Int) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: "> research",
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: caret
        )
    }
}
