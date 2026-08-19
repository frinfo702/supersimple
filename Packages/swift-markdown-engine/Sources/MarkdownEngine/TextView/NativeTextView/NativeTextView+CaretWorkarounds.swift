//
//  NativeTextView+CaretWorkarounds.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Caret-indicator workarounds: block-image hide/resize + trailing-`\n` Y-snap (FB22524198).
//

import AppKit

extension NativeTextView {
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fixPhantomTrailingCaret()
            self.applyBlockImageCaretPolicy()
        }
        applyBlockImageCaretPolicy()
    }

    func applyBlockImageCaretPolicy() {
        let indicators = subviews.filter { type(of: $0) == NSTextInsertionIndicator.self }
        guard !indicators.isEmpty else { return }

        var hide = false
        var resize = false
        if let ts = textStorage {
            let sel = selectedRange()
            if sel.length != 0 || sel.location > ts.length {
                hide = true
            } else if sel.location < ts.length {
                let paraRange = (ts.string as NSString).paragraphRange(
                    for: NSRange(location: sel.location, length: 0)
                )
                ts.enumerateAttribute(.latexIsBlock, in: paraRange, options: []) { value, range, stop in
                    guard value as? Bool == true else { return }
                    if ts.attribute(.latexBlockOffsetY, at: range.location, effectiveRange: nil) != nil {
                        resize = true
                    } else {
                        hide = true
                        stop.pointee = true
                    }
                }
            }
        }

        for sub in indicators {
            if hide {
                if sub.isHidden != true { sub.isHidden = true }
                continue
            }
            if resize {
                resizeIndicatorToLayoutCaret(sub)
            } else {
                snapInsertionIndicatorToGlyph(sub)
            }
            if sub.isHidden != false { sub.isHidden = false }
        }
    }

    /// After collapsed→visible, the indicator frame stays at image height; snap it to the layout manager's actual caret rect.
    func resizeIndicatorToLayoutCaret(_ indicator: NSView) {
        guard let r = layoutCaretSegmentRectInView(), r.height > 0,
              indicator.frame.height > r.height + 1 else { return }
        applyCaretFrame(indicator, rect: CGRect(
            x: indicator.frame.origin.x, y: r.origin.y,
            width: indicator.frame.width, height: r.height
        ))
    }

    /// TextKit 2 sizes `NSTextInsertionIndicator` to the line fragment, which includes
    /// `minimumLineHeight` extra leading. That extra sits *above* the em-box, so a
    /// top-aligned crop leaves the caret floating over the glyphs. Pin the em-box
    /// to the line's typographic bottom; keep AppKit's X.
    func snapInsertionIndicatorToGlyph(_ indicator: NSView) {
        let font = fontAtCaret() ?? baseFont
        let glyphHeight = ceil(max(0, font.ascender - font.descender))
        guard glyphHeight > 1 else { return }
        let current = indicator.frame
        let line = caretLineBoundsInView()
        let boxHeight = min(glyphHeight, line?.height ?? current.height)
        guard boxHeight > 1 else { return }
        let y: CGFloat
        if let line, line.height > 1 {
            y = line.maxY - boxHeight
        } else {
            y = current.origin.y + max(0, current.height - boxHeight)
        }
        applyCaretFrame(indicator, rect: CGRect(
            x: current.origin.x, y: y,
            width: current.width, height: boxHeight
        ))
    }

    private func fontAtCaret() -> NSFont? {
        guard let ts = textStorage else { return nil }
        if ts.length == 0 { return baseFont }
        let idx = min(selectedRange().location, ts.length - 1)
        return ts.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
    }

    /// Typographic bounds of the caret's line, in text-view coordinates.
    private func caretLineBoundsInView() -> CGRect? {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let ts = textStorage else { return nil }
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let ns = ts.string as NSString
        let origin = textContainerOrigin

        func viewRect(fragment: NSTextLayoutFragment, line: NSTextLineFragment) -> CGRect {
            let tb = line.typographicBounds
            return CGRect(
                x: origin.x + fragment.layoutFragmentFrame.origin.x + tb.origin.x,
                y: origin.y + fragment.layoutFragmentFrame.origin.y + tb.origin.y,
                width: max(tb.width, 1),
                height: tb.height
            )
        }

        // Trailing extra line after a final `\n` is not a real text line fragment.
        if ns.length > 0, sel.location == ns.length, ns.character(at: ns.length - 1) == 0x0A,
           let trailingLoc = tcs.location(tcs.documentRange.location, offsetBy: ns.length - 1) {
            var extra: CGRect?
            tlm.enumerateTextLayoutFragments(from: trailingLoc, options: [.ensuresLayout]) { fragment in
                let lastTextLine = fragment.textLineFragments.last { $0.characterRange.length > 0 }
                    ?? fragment.textLineFragments.last
                guard let line = lastTextLine else { return false }
                let lineMaxY = fragment.layoutFragmentFrame.origin.y + line.typographicBounds.maxY
                let style = ts.attribute(.paragraphStyle, at: ns.length - 1, effectiveRange: nil) as? NSParagraphStyle
                extra = CGRect(
                    x: origin.x,
                    y: lineMaxY + (style?.paragraphSpacing ?? 0) + origin.y,
                    width: 1,
                    height: max(style?.minimumLineHeight ?? 0, line.typographicBounds.height)
                )
                return false
            }
            return extra
        }

        guard ns.length > 0 else { return nil }
        let query = min(sel.location, ns.length - 1)
        guard let docLoc = tcs.location(tcs.documentRange.location, offsetBy: query) else { return nil }
        var result: CGRect?
        tlm.enumerateTextLayoutFragments(from: docLoc, options: [.ensuresLayout]) { fragment in
            let fragStart = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            guard fragStart != NSNotFound else { return false }
            let local = query - fragStart
            let line = fragment.textLineFragments.first { line in
                let lr = line.characterRange
                return local >= lr.location && local < lr.location + lr.length
            } ?? fragment.textLineFragments.last
            guard let line else { return false }
            result = viewRect(fragment: fragment, line: line)
            return false
        }
        return result
    }

    /// Caret segment in **text view** coordinates (`enumerateTextSegments` is
    /// text-container-relative; add `textContainerOrigin` for the inset).
    private func layoutCaretSegmentRectInView() -> CGRect? {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage else { return nil }
        let offset = min(selectedRange().location, max(0, (textStorage?.length ?? 1) - 1))
        guard let docLoc = tcs.location(tcs.documentRange.location, offsetBy: offset) else { return nil }
        var layoutRect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: docLoc), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
            layoutRect = f
            return false
        }
        return layoutRect?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private func applyCaretFrame(_ indicator: NSView, rect: CGRect) {
        guard abs(indicator.frame.height - rect.height) >= 0.5
            || abs(indicator.frame.origin.y - rect.origin.y) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame = rect
        isApplyingCaretShift = false
    }

    /// FB22524198: AppKit drops the trailing-`\n` caret onto the previous line's top — snap it to `lastLineMaxY + paragraphSpacing` instead. (Companion to FB15131180; this one fixes Y, the other fixes height.)
    func fixPhantomTrailingCaret() {
        if let indicator = subviews.first(where: { type(of: $0) == NSTextInsertionIndicator.self }),
           observedCaretIndicator !== indicator {
            caretIndicatorObservation?.invalidate()
            observedCaretIndicator = indicator
            caretIndicatorObservation = indicator.observe(\.frame, options: [.new]) { [weak self] _, _ in
                guard let self, !self.isApplyingCaretShift else { return }
                self.fixPhantomTrailingCaret()
                self.applyBlockImageCaretPolicy()
            }
        }
        guard let ts = textStorage, let indicator = observedCaretIndicator,
              let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage else { return }
        let sel = selectedRange()
        let ns = ts.string as NSString
        guard sel.length == 0, sel.location == ns.length, ns.length > 0,
              ns.character(at: ns.length - 1) == 0x0A,
              let trailingLoc = tcs.location(tcs.documentRange.location, offsetBy: ns.length - 1) else {
            return
        }
        var desiredY: CGFloat?
        tlm.enumerateTextLayoutFragments(from: trailingLoc, options: [.ensuresLayout]) { fragment in
            // Use the LAST text line (length > 0) so multi-line wrapped paragraphs aren't pulled to the first line.
            let lastTextLine = fragment.textLineFragments.last { $0.characterRange.length > 0 }
                ?? fragment.textLineFragments.last
            guard let line = lastTextLine else { return false }
            let lineMaxY = fragment.layoutFragmentFrame.origin.y + line.typographicBounds.maxY
            let style = ts.attribute(.paragraphStyle, at: ns.length - 1, effectiveRange: nil) as? NSParagraphStyle
            // Layout-fragment Y is textContainer-relative; the indicator frame is textView-relative — add the textContainerInset offset so the snap stays correct when an embedder configures non-zero text insets.
            desiredY = lineMaxY + (style?.paragraphSpacing ?? 0) + self.textContainerInset.height
            return false
        }
        guard let desiredY, abs(indicator.frame.origin.y - desiredY) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame.origin.y = desiredY
        isApplyingCaretShift = false
    }
}
