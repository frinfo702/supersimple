import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Tab indent", .serialized)
@MainActor
struct ListTabIndentTests {

    @Test("Tab on a list item inserts a tab at the start of the line")
    func tabIndentsListItem() {
        let textView = makeTextView("- item", caret: 6)
        let allowed = MarkdownLists.handleInsertion(
            textView: textView,
            affectedCharRange: NSRange(location: 6, length: 0),
            replacementString: "\t"
        )
        #expect(allowed == false)
        #expect(textView.string == "\t- item")
        #expect(textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test("Tab on an already nested list item adds another indent tab")
    func tabIndentsNestedListItem() {
        let textView = makeTextView("\t- item", caret: 7)
        let allowed = MarkdownLists.handleInsertion(
            textView: textView,
            affectedCharRange: NSRange(location: 7, length: 0),
            replacementString: "\t"
        )
        #expect(allowed == false)
        #expect(textView.string == "\t\t- item")
    }

    @Test("Tab on a non-list line is not consumed as list indent")
    func tabOnPlainLineIsNotListIndent() {
        let textView = makeTextView("hello", caret: 0)
        let allowed = MarkdownLists.handleInsertion(
            textView: textView,
            affectedCharRange: NSRange(location: 0, length: 0),
            replacementString: "\t"
        )
        #expect(allowed == true)
        #expect(textView.string == "hello")
    }

    @Test("One tab is one indent level")
    func tabCountsAsOneIndentLevel() {
        #expect(MarkdownLists.indentLevel(from: "") == 0)
        #expect(MarkdownLists.indentLevel(from: "\t") == 1)
        #expect(MarkdownLists.indentLevel(from: "\t\t") == 2)
        #expect(MarkdownLists.indentLevel(from: "  ") == 1)
    }

    @Test("Backspace on an empty nested ordered item outdents instead of eating the marker space")
    func backspaceOutdentsEmptyNestedOrderedItem() {
        let text = "1. parent\n\t2. "
        let textView = makeTextView(text, caret: (text as NSString).length)
        #expect(MarkdownLists.handleBackspace(textView: textView) == true)
        #expect(textView.string == "1. parent\n2. ")
        let markers = MarkdownASTStyler.styleAttributes(
            text: textView.string,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        ).compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers.isEmpty)
    }

    @Test("Tab then Backspace restores a top-level 2. not a.")
    func tabThenBackspaceRestoresDecimalMarker() {
        let text = "1. parent\n2. "
        let textView = makeTextView(text, caret: (text as NSString).length)
        #expect(MarkdownLists.handleInsertion(
            textView: textView,
            affectedCharRange: textView.selectedRange(),
            replacementString: "\t"
        ) == false)
        #expect(textView.string == "1. parent\n\t2. ")
        #expect(MarkdownLists.handleBackspace(textView: textView) == true)
        #expect(textView.string == "1. parent\n2. ")
        let markers = MarkdownASTStyler.styleAttributes(
            text: textView.string,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        ).compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers.isEmpty)
    }

    @Test("Backspace on a double-nested empty item drops one level to a. then b.")
    func backspaceDropsOneNestLevel() {
        let text = "1. parent\n\t2. child\n\t\t3. "
        let textView = makeTextView(text, caret: (text as NSString).length)
        #expect(MarkdownLists.handleBackspace(textView: textView) == true)
        #expect(textView.string == "1. parent\n\t2. child\n\t3. ")
        let markers = MarkdownASTStyler.styleAttributes(
            text: textView.string,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        ).compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers == ["a.", "b."])
    }

    @Test("Backspace inside list item text is not consumed")
    func backspaceInListContentIsNotConsumed() {
        let textView = makeTextView("1. hello", caret: 8)
        #expect(MarkdownLists.handleBackspace(textView: textView) == false)
        #expect(textView.string == "1. hello")
    }

    private func makeTextView(_ string: String, caret: Int) -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = string
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }
}
