import AppKit
import Testing
@testable import MarkdownEngine

@Suite("LinePrefixGlue")
struct LinePrefixGlueTests {

    @Test("Plain Tab indent is not a glue prefix")
    func plainTabIndentIsNotAPrefix() {
        #expect(LinePrefixGlue.prefixLength(in: "\thello") == 0)
        #expect(LinePrefixGlue.prefixLength(in: "\t\tindented paragraph") == 0)
        #expect(LinePrefixGlue.prefixLength(in: "hello") == 0)
    }

    @Test("List marker includes the trailing space, not leading tabs")
    func listMarkerPrefixSkipsIndentTabs() {
        let top = LinePrefixGlue.prefix(in: "- item")
        #expect(top.indentLength == 0)
        #expect(top.length == 2) // "- "

        let nested = LinePrefixGlue.prefix(in: "\t- item")
        #expect(nested.indentLength == 1)
        #expect(nested.length == 3) // "\t- "
    }

    @Test("Blockquote marker includes the trailing space")
    func blockquotePrefix() {
        let info = LinePrefixGlue.prefix(in: "> quote")
        #expect(info.indentLength == 0)
        #expect(info.length == 2) // "> "
    }

    @Test("apply keeps leading indent tabs so Tab indent retains width")
    func applyKeepsLeadingIndentTabs() {
        let attr = NSMutableAttributedString(string: "\t- item")
        let mutated = LinePrefixGlue.apply(to: attr)
        #expect(mutated)
        #expect((attr.string as NSString).character(at: 0) == 0x09)
        #expect(attr.string.dropFirst() == "-\u{2060}item")
    }

    @Test("apply does not rewrite a tab-indented paragraph")
    func applyLeavesPlainTabIndentAlone() {
        let attr = NSMutableAttributedString(string: "\thello")
        #expect(LinePrefixGlue.apply(to: attr) == false)
        #expect(attr.string == "\thello")
    }

    @Test("apply glues the space after a list marker")
    func applyGluesListMarkerSpace() {
        let attr = NSMutableAttributedString(string: "- https://example.com/very/long")
        #expect(LinePrefixGlue.apply(to: attr))
        #expect(attr.string.hasPrefix("-\u{2060}"))
        #expect(attr.string.utf16.count == "- https://example.com/very/long".utf16.count)
    }

    @Test("apply glues the space after a blockquote marker")
    func applyGluesBlockquoteSpace() {
        let attr = NSMutableAttributedString(string: "> https://example.com")
        #expect(LinePrefixGlue.apply(to: attr))
        #expect(attr.string.hasPrefix(">\u{2060}"))
    }

    @Test("apply does not glue an empty list item's trailing space")
    func applyLeavesEmptyOrderedItemSpace() {
        let attr = NSMutableAttributedString(string: "1. ")
        #expect(LinePrefixGlue.apply(to: attr) == false)
        #expect(attr.string == "1. ")
    }

    @Test("apply does not glue an empty bullet item's trailing space")
    func applyLeavesEmptyBulletItemSpace() {
        let attr = NSMutableAttributedString(string: "- ")
        #expect(LinePrefixGlue.apply(to: attr) == false)
        #expect(attr.string == "- ")
    }

    @Test("apply still glues when ordered-item content follows")
    func applyGluesOrderedItemWithContent() {
        let attr = NSMutableAttributedString(string: "1. hello")
        #expect(LinePrefixGlue.apply(to: attr))
        #expect(attr.string.hasPrefix("1.\u{2060}"))
    }
}
