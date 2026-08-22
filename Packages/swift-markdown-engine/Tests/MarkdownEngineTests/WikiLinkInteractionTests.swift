import AppKit
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
}
