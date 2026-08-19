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

    private func makeTextView(_ string: String, caret: Int) -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = string
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return textView
    }
}
