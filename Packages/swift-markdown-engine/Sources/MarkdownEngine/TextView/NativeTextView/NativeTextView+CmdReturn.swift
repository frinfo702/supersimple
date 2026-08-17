//
//  NativeTextView+CmdReturn.swift
//  MarkdownEngine
//
//  ⌘↵ ("link & open") for the inline [[…]] preview. AppKit does NOT route ⌘+Return
//  through doCommandBy(insertNewline:), so we intercept it as a key equivalent — which
//  fires first for ⌘-combos — and forward `.confirmAndOpen` to the embedder.
//
//  ⌘⌫ (Delete) is also a key equivalent: the host's "Delete Note" menu item would
//  otherwise swallow it while the editor is first responder. Consume it here and
//  delete the current line(s) instead. Only when this view is first responder —
//  performKeyEquivalent walks the whole view tree, so a sidebar-focused ⌘⌫ must
//  still reach the menu.
//

import AppKit

extension NativeTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isEditable,
           window?.firstResponder === self,
           flags == .command,
           event.keyCode == 51 {            // Delete / Backspace
            deleteCurrentLines()
            return true
        }
        if flags == .command,
           event.keyCode == 36 || event.keyCode == 76,            // Return / keypad Enter
           let coord = delegate as? NativeTextViewCoordinator,
           coord.isWikiLinkActive || coord.isImageEmbedActive,
           let handler = coord.onInlinePreviewKey,
           handler(.confirmAndOpen) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Removes every paragraph that intersects the selection, including the
    /// trailing newline, so the following line moves up. Empty last line of
    /// the document is a no-op.
    func deleteCurrentLines() {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lineRange = ns.paragraphRange(for: selectedRange())
        guard lineRange.length > 0 else { return }
        guard shouldChangeText(in: lineRange, replacementString: "") else { return }
        breakUndoCoalescing()
        storage.replaceCharacters(in: lineRange, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: lineRange.location, length: 0))
    }
}
