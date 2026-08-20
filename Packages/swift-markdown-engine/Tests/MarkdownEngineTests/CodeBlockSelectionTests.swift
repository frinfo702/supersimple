import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("Code block overlay selection", .serialized)
@MainActor
struct CodeBlockSelectionTests {

    @Test("NSRange.isWithin rejects out-of-bounds ranges that would trap substring")
    func rangeBoundsCheck() {
        #expect(NSRange(location: 0, length: 0).isWithin(0))
        #expect(NSRange(location: 0, length: 5).isWithin(5))
        #expect(NSRange(location: 5, length: 0).isWithin(5))
        #expect(!NSRange(location: 0, length: 6).isWithin(5))
        #expect(!NSRange(location: 4, length: 20).isWithin(0))
        #expect(!NSRange(location: NSNotFound, length: 0).isWithin(10))
    }

    @Test("Stale code-block cache against a shorter document does not crash")
    func staleCacheOnNewNoteDoesNotCrash() {
        var text = "# New"
        var wiki = false
        let coordinator = makeCoordinator(text: Binding(get: { text }, set: { text = $0 }), wiki: Binding(get: { wiki }, set: { wiki = $0 }))
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = text
        if let tlm = textView.textLayoutManager {
            coordinator.layoutBridge = LayoutBridge(tlm)
        }

        coordinator.cachedCodeBlockTokens = [(0, MarkdownToken(
            kind: .codeBlock,
            range: NSRange(location: 0, length: 80),
            contentRange: NSRange(location: 10, length: 50),
            markerRanges: []
        ))]

        var received: [CodeBlockSelection]?
        coordinator.onCodeBlockSelectionChange = { received = $0 }
        coordinator.updateCodeBlockSelection(textView: textView)
        #expect(received?.isEmpty == true)
    }

    @Test("Rebuild onto an empty note drops the previous note's code-block cache")
    func rebuildEmptyNoteDropsStaleCodeBlockCache() {
        let fenced = """
        ```swift
        print("hi")
        ```
        """
        var text = fenced
        var wiki = false
        let coordinator = makeCoordinator(text: Binding(get: { text }, set: { text = $0 }), wiki: Binding(get: { wiki }, set: { wiki = $0 }))
        let textView = NSTextView(usingTextLayoutManager: true)

        coordinator.rebuildTextStorageAndStyle(textView, from: fenced)
        #expect(!coordinator.cachedCodeBlockTokens.isEmpty)

        text = ""
        coordinator.rebuildTextStorageAndStyle(textView, from: "")
        #expect(coordinator.cachedCodeBlockTokens.isEmpty)
        #expect(textView.string.isEmpty)
    }
}

@MainActor
private func makeCoordinator(text: Binding<String>, wiki: Binding<Bool>) -> NativeTextViewCoordinator {
    NativeTextViewCoordinator(
        text: text,
        fontName: "Helvetica",
        fontSize: 16,
        isWikiLinkActive: wiki,
        onLinkClick: nil,
        onInlineSelectionChange: nil
    )
}
