import AppKit
import SwiftUI
import Testing

@testable import MarkdownEngine

@Suite("Wiki-link interaction")
struct WikiLinkInteractionTests {
    @Test("Editable wiki links require Command-click to navigate")
    func editableWikiLinkNavigationModifiers() {
        #expect(
            !NativeTextViewCoordinator.shouldNavigateWikiLink(
                isEditable: true,
                modifierFlags: []
            )
        )
        #expect(
            NativeTextViewCoordinator.shouldNavigateWikiLink(
                isEditable: true,
                modifierFlags: [.command]
            )
        )
        #expect(
            NativeTextViewCoordinator.shouldNavigateWikiLink(
                isEditable: true,
                modifierFlags: [.command, .shift]
            )
        )
    }

    @Test("Read-only wiki links navigate without modifiers")
    func readOnlyWikiLinkNavigation() {
        #expect(
            NativeTextViewCoordinator.shouldNavigateWikiLink(
                isEditable: false,
                modifierFlags: []
            )
        )
    }

    @MainActor
    @Test("Explicit Command-click activation opens the wiki target")
    func commandClickActivation() async {
        var text = "[[Target]]"
        var wikiActive = false
        var openedTarget: String?
        let coordinator = NativeTextViewCoordinator(
            text: Binding(get: { text }, set: { text = $0 }),
            fontName: "Helvetica",
            fontSize: 16,
            isWikiLinkActive: Binding(get: { wikiActive }, set: { wikiActive = $0 }),
            onLinkClick: { openedTarget = $0 },
            onInlineSelectionChange: nil
        )
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.string = text
        textView.isEditable = true
        textView.textStorage?.addAttribute(
            .wikiLinkID,
            value: "note-id",
            range: NSRange(location: 2, length: 6)
        )

        #expect(
            coordinator.handleLinkClick(
                textView,
                link: "note-id",
                at: 3,
                modifierFlags: [.command]
            )
        )
        await Task.yield()
        #expect(openedTarget == "note-id")
    }
}
