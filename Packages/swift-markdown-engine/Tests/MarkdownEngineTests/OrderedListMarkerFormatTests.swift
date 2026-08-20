import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Ordered list outline markers")
struct OrderedListMarkerFormatTests {

    @Test("Depth cycles decimal, alphabetic, roman")
    func depthCycles() {
        #expect(OrderedListMarkerFormat.label(number: 1, depth: 0) == "1")
        #expect(OrderedListMarkerFormat.label(number: 2, depth: 0) == "2")
        #expect(OrderedListMarkerFormat.label(number: 1, depth: 1) == "a")
        #expect(OrderedListMarkerFormat.label(number: 2, depth: 1) == "b")
        #expect(OrderedListMarkerFormat.label(number: 1, depth: 2) == "i")
        #expect(OrderedListMarkerFormat.label(number: 2, depth: 2) == "ii")
        #expect(OrderedListMarkerFormat.label(number: 3, depth: 2) == "iii")
        #expect(OrderedListMarkerFormat.label(number: 1, depth: 3) == "1")
        #expect(OrderedListMarkerFormat.label(number: 1, depth: 4) == "a")
    }

    @Test("Keeps source punctuation")
    func keepsPunctuation() {
        #expect(OrderedListMarkerFormat.marker(number: 1, depth: 1, punct: ".") == "a.")
        #expect(OrderedListMarkerFormat.marker(number: 2, depth: 2, punct: ")") == "ii)")
    }

    @Test("Alphabetic wraps past z")
    func alphabeticWraps() {
        #expect(OrderedListMarkerFormat.alphabetic(26) == "z")
        #expect(OrderedListMarkerFormat.alphabetic(27) == "aa")
    }

    @Test("Roman covers subtractive pairs")
    func romanSubtractive() {
        #expect(OrderedListMarkerFormat.roman(4) == "iv")
        #expect(OrderedListMarkerFormat.roman(9) == "ix")
        #expect(OrderedListMarkerFormat.roman(14) == "xiv")
    }

    @Test("Nested ordered items overlay a. then i.")
    func nestedItemsGetOutlineOverlay() {
        let text = "1. one\n\t1. two\n\t\t1. three"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        )
        let markers = attrs.compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers == ["a.", "i."])
    }

    @Test("Nested first item restarts at a. even when source is 2.")
    func nestedFirstItemRestartsAtA() {
        let text = "1. parent\n\t2. child"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        )
        let markers = attrs.compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers == ["a."])
    }

    @Test("Nested siblings after a continued 2. number as a. then b.")
    func nestedSiblingsRestartThenCount() {
        let text = "1. parent\n\t2. first\n\t3. second"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        )
        let markers = attrs.compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers == ["a.", "b."])
    }

    @Test("runStart restarts nested lists at 1")
    func runStartNestedRestarts() {
        #expect(OrderedListMarkerFormat.runStart(indent: 0, literal: 5, existing: nil) == 5)
        #expect(OrderedListMarkerFormat.runStart(indent: 1, literal: 2, existing: nil) == 1)
        #expect(OrderedListMarkerFormat.runStart(indent: 1, literal: 2, existing: 3) == 3)
    }

    @Test("Outdent from i. to one tab shows a. then b., not i.")
    func outdentFromRomanShowsAlphabetic() {
        let text = "1. parent\n\t2. child\n\t3. deep"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        )
        let markers = attrs.compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers == ["a.", "b."])
    }

    @Test("Top-level 1. matching its display number is not overlaid")
    func matchingTopLevelHasNoOverlay() {
        let text = "1. one\n2. two"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1
        )
        let markers = attrs.compactMap { $0.attributes[.orderedMarker] as? String }
        #expect(markers.isEmpty)
    }
}

@Suite("Overlay glyph geometry")
struct OverlayGlyphGeometryTests {

    @Test("Pins the em-box to the line's typographic bottom")
    func pinsEmBoxToLineBottom() {
        let font = NSFont.systemFont(ofSize: 16)
        let lineMaxY: CGFloat = 40
        let topY = OverlayGlyphGeometry.textTopY(lineMaxY: lineMaxY, font: font)
        let emHeight = font.ascender - font.descender
        #expect(abs((lineMaxY - topY) - emHeight) < 0.001)
        #expect(topY < lineMaxY)
    }

    @Test("Bullet disc is Notion-sized relative to body type")
    func bulletDiscIsNotionSized() {
        let font = NSFont.systemFont(ofSize: 17)
        let diameter = OverlayGlyphGeometry.bulletDiameter(for: font)
        #expect(abs(diameter - font.pointSize * OverlayGlyphGeometry.bulletDiameterEm) < 0.001)
        #expect(diameter >= 5)
    }

    @Test("Bullet disc sits in the marker slot, centered on x-height")
    func bulletDiscCenteredOnXHeight() {
        let font = NSFont.systemFont(ofSize: 16)
        let lineMaxY: CGFloat = 40
        let dashWidth: CGFloat = 8
        let rect = OverlayGlyphGeometry.bulletRect(
            slotX: 10,
            dashWidth: dashWidth,
            lineMaxY: lineMaxY,
            font: font
        )
        let topY = OverlayGlyphGeometry.textTopY(lineMaxY: lineMaxY, font: font)
        let xHeightCenter = topY + font.ascender - font.xHeight * 0.5
        #expect(abs(rect.midY - xHeightCenter) < 0.001)
        #expect(rect.minX >= 10)
        #expect(rect.maxX <= 10 + dashWidth)
    }
}

@Suite("Caret trailing whitespace")
struct CaretGeometryTests {

    @Test("Empty ordered item counts the marker space")
    func emptyOrderedItemCountsMarkerSpace() {
        let text = NSAttributedString(string: "1. ", attributes: [
            .font: NSFont.systemFont(ofSize: 16)
        ])
        #expect(CaretGeometry.trailingWhitespaceUTF16Count(in: text.string as NSString, caret: 3) == 1)
        let extra = CaretGeometry.trailingWhitespaceAdvance(in: text, caret: 3)
        let space = (" " as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16)]).width
        #expect(abs(extra - space) < 0.01)
    }

    @Test("Caret inside content is not treated as trailing whitespace")
    func contentEndIsNotTrailingWhitespace() {
        let text = NSAttributedString(string: "1. hello")
        #expect(CaretGeometry.trailingWhitespaceUTF16Count(in: text.string as NSString, caret: 8) == 0)
        #expect(CaretGeometry.trailingWhitespaceAdvance(in: text, caret: 8) == 0)
        #expect(CaretGeometry.trailingWhitespaceUTF16Count(in: text.string as NSString, caret: 3) == 0)
    }

    @Test("Collapsed marker space does not invent a visible gap")
    func collapsedMarkerSpaceHasNoAdvance() {
        let font = NSFont.systemFont(ofSize: 0.1)
        let text = NSMutableAttributedString(string: "- ")
        text.addAttributes([.font: font, .kern: -font.pointSize], range: NSRange(location: 0, length: 2))
        let extra = CaretGeometry.trailingWhitespaceAdvance(in: text, caret: 2)
        #expect(extra < 0.5)
    }
}
