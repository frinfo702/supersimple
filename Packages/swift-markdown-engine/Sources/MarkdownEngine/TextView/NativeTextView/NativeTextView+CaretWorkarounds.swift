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
            x: r.origin.x, y: r.origin.y,
            width: indicator.frame.width, height: r.height
        ))
    }

    /// TextKit 2 sizes `NSTextInsertionIndicator` to the line fragment, which includes
    /// `minimumLineHeight` extra leading. That extra sits *above* the em-box, so a
    /// top-aligned crop leaves the caret floating over the glyphs. Pin the em-box
    /// to the line's typographic bottom.
    ///
    /// X is taken from TextKit, not AppKit. This text view is a centered subview of
    /// the document view (reading column); AppKit lays the indicator out as if we
    /// were the document view, so a leftover or origin-shifted X lands outside the
    /// column — empty notes and first layout after launch are the usual triggers.
    func snapInsertionIndicatorToGlyph(_ indicator: NSView) {
        let font = fontAtCaret() ?? baseFont
        let glyphHeight = ceil(max(0, font.ascender - font.descender))
        guard glyphHeight > 1 else { return }
        let current = indicator.frame
        let line = caretLineBoundsInView()
        let layout = layoutCaretSegmentRectInView()
        let boxHeight = min(glyphHeight, line?.height ?? layout?.height ?? current.height)
        guard boxHeight > 1 else { return }
        let y: CGFloat
        if let line, line.height > 1 {
            y = line.maxY - boxHeight
        } else if let layout, layout.height > 1 {
            y = layout.maxY - boxHeight
        } else {
            y = current.origin.y + max(0, current.height - boxHeight)
        }
        let x = caretXInView(line: line, layout: layout)
        applyCaretFrame(indicator, rect: CGRect(
            x: x, y: y,
            width: current.width, height: boxHeight
        ))
    }

    /// Column-local X: TextKit segment, else the line's leading edge, else the
    /// text-container origin (empty docs before fragments exist).
    private func caretXInView(line: CGRect?, layout: CGRect?) -> CGFloat {
        let proposed: CGFloat
        if let layout {
            proposed = layout.origin.x
        } else if let line {
            proposed = line.origin.x
        } else {
            proposed = textContainerOrigin.x
        }
        let minX = textContainerOrigin.x
        let columnWidth = textContainer?.size.width ?? bounds.width
        let maxX = minX + max(columnWidth, 0)
        return min(max(proposed, minX), maxX)
    }

    private func fontAtCaret() -> NSFont? {
        guard let ts = textStorage else { return nil }
        if ts.length == 0 { return baseFont }
        let idx = min(selectedRange().location, ts.length - 1)
        let font = ts.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
        // Hidden list-marker runs use a ~0.1pt font; snapping to that em-box
        // would skip the X correction for an empty `- ` / `1. ` item.
        if let font, font.pointSize >= 1 { return font }
        return baseFont
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

        if ns.length == 0 {
            if let layout = layoutCaretSegmentRectInView(), layout.height > 1 {
                return layout
            }
            let lineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: layoutBridge)
                + configuration.paragraph.lineHeightExtraSpacing
            return CGRect(
                x: origin.x,
                y: origin.y,
                width: 1,
                height: max(lineHeight, 1)
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
        let length = textStorage?.length ?? 0
        let sel = selectedRange().location
        let queryLoc: NSTextLocation?
        if length == 0 || sel >= length {
            _ = tlm.enumerateTextLayoutFragments(
                from: tlm.documentRange.endLocation,
                options: [.ensuresLayout, .ensuresExtraLineFragment]
            ) { _ in false }
            queryLoc = tlm.documentRange.endLocation
        } else {
            queryLoc = tcs.location(tcs.documentRange.location, offsetBy: sel)
        }
        guard let queryLoc else { return nil }
        var layoutRect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: queryLoc), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
            if f.width >= 0, f.height > 0 { layoutRect = f }
            return false
        }
        let rect = layoutRect?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return adjustedCaretRectForTrailingWhitespace(rect)
    }

    /// TextKit 2 parks the EOL caret on the last non-space glyph, so typing
    /// `1. ` (empty ordered item) shows the caret on the `.` until content
    /// exists. Advance it by the marker space when that happened.
    private func adjustedCaretRectForTrailingWhitespace(_ rect: CGRect?) -> CGRect? {
        guard var rect, let ts = textStorage else { return rect }
        let caret = selectedRange().location
        let extra = CaretGeometry.trailingWhitespaceAdvance(in: ts, caret: caret)
        guard extra > 0.5 else { return rect }
        let spaceCount = CaretGeometry.trailingWhitespaceUTF16Count(in: ts.string as NSString, caret: caret)
        guard spaceCount > 0 else { return rect }
        if let spaceX = caretXForDocumentIndex(caret - spaceCount) {
            let measured = spaceX + extra
            if measured > rect.origin.x + 0.5 {
                rect.origin.x = measured
            }
        } else {
            rect.origin.x += extra
        }
        return rect
    }

    private func caretXForDocumentIndex(_ index: Int) -> CGFloat? {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let ts = textStorage, ts.length > 0 else { return nil }
        let probe = min(max(0, index), ts.length - 1)
        guard let docLoc = tcs.location(tcs.documentRange.location, offsetBy: probe) else { return nil }
        var x: CGFloat?
        tlm.enumerateTextLayoutFragments(from: docLoc, options: [.ensuresLayout]) { fragment in
            let fragStart = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
            guard fragStart != NSNotFound else { return false }
            let local = probe - fragStart
            let line = fragment.textLineFragments.first { line in
                let lr = line.characterRange
                return local >= lr.location && local < lr.location + lr.length
            } ?? fragment.textLineFragments.last
            guard let line else { return false }
            let charPos = line.locationForCharacter(at: local)
            let tb = line.typographicBounds
            x = textContainerOrigin.x + fragment.layoutFragmentFrame.origin.x + tb.origin.x + charPos.x
            return false
        }
        return x
    }

    private func applyCaretFrame(_ indicator: NSView, rect: CGRect) {
        guard abs(indicator.frame.height - rect.height) >= 0.5
            || abs(indicator.frame.origin.y - rect.origin.y) >= 0.5
            || abs(indicator.frame.origin.x - rect.origin.x) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame = rect
        isApplyingCaretShift = false
    }

    /// Reading-column centering moves this view inside the document view; AppKit
    /// does not re-lay the insertion indicator, so snap it back into the column.
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let originChanged = abs(newOrigin.x - frame.origin.x) > 0.5
            || abs(newOrigin.y - frame.origin.y) > 0.5
        super.setFrameOrigin(newOrigin)
        if originChanged {
            applyBlockImageCaretPolicy()
        }
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

/// Caret-X helpers for trailing marker whitespace that TextKit 2 drops at EOL.
enum CaretGeometry {
    static func trailingWhitespaceUTF16Count(in ns: NSString, caret: Int) -> Int {
        let loc = min(max(0, caret), ns.length)
        guard loc > 0 else { return 0 }
        let line = ns.lineRange(for: NSRange(location: loc - 1, length: 0))
        var lineEnd = NSMaxRange(line)
        while lineEnd > line.location {
            let c = ns.character(at: lineEnd - 1)
            if c == 0x0A || c == 0x0D { lineEnd -= 1 } else { break }
        }
        guard loc == lineEnd else { return 0 }
        var i = loc
        var count = 0
        while i > line.location {
            let ch = ns.character(at: i - 1)
            guard ch == 0x20 || ch == 0x09 else { break }
            count += 1
            i -= 1
        }
        return count
    }

    static func trailingWhitespaceAdvance(in text: NSAttributedString, caret: Int) -> CGFloat {
        let ns = text.string as NSString
        let count = trailingWhitespaceUTF16Count(in: ns, caret: caret)
        guard count > 0 else { return 0 }
        let start = caret - count
        var width: CGFloat = 0
        for i in 0..<count {
            let idx = start + i
            let attrs = text.attributes(at: idx, effectiveRange: nil)
            let s = ns.substring(with: NSRange(location: idx, length: 1))
            width += (s as NSString).size(withAttributes: attrs).width
            if let kern = attrs[.kern] as? CGFloat {
                width += kern
            }
        }
        return max(0, width)
    }
}
