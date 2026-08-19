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
}
