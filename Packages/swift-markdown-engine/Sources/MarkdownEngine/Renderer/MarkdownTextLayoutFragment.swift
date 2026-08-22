//
//  MarkdownTextLayoutFragment.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 12.04.26.
//
//  TextKit 2 replacement for CodeBlockLayoutManager.
//  Draws code-block backgrounds, LaTeX images, and task checkboxes
//  via NSTextLayoutFragment instead of NSLayoutManager glyph overrides.

import AppKit

// MARK: - Custom attribute keys for rendering overlays

extension NSAttributedString.Key {
    static let latexImage = NSAttributedString.Key("LatexRenderedImage")
    static let latexBounds = NSAttributedString.Key("LatexImageBounds")
    static let latexIsBlock = NSAttributedString.Key("LatexIsBlock")
    static let latexBlockOffsetY = NSAttributedString.Key("LatexBlockOffsetY")
    static let thematicBreak = NSAttributedString.Key("ThematicBreak")
    /// Int nesting level (1-based) of a blockquote line; the fragment
    /// paints that many vertical bars in the left gutter.
    static let blockquoteLevel = NSAttributedString.Key("BlockquoteLevel")
    /// Marks a bullet-list marker char (`-`/`*`/`+`) whose glyph is hidden so
    /// the fragment can paint a `•` in its place. Set to `true`.
    static let bulletMarker = NSAttributedString.Key("BulletListMarker")
    static let orderedMarker = NSAttributedString.Key("OrderedListMarker")
    /// CGFloat — natural image width; presence flags block as overlay-rendered.
    static let scrollableBlockNaturalWidth = NSAttributedString.Key("ScrollableBlockNaturalWidth")
    /// Int — hash of source text; key for overlay reconcile + offset persistence.
    static let scrollableBlockSourceID = NSAttributedString.Key("ScrollableBlockSourceID")
    /// CGFloat — total reserved height (image + scroller strip) for overlay sizing.
    static let scrollableBlockTotalHeight = NSAttributedString.Key("ScrollableBlockTotalHeight")
    /// NSValue(range:) — full multi-line range of a rendered table, used to scope width-change restyles.
    static let scrollableBlockFullRange = NSAttributedString.Key("ScrollableBlockFullRange")
}

public extension NSAttributedString.Key {
    /// NSColor — a background painted across the whole LINE BOX (the line
    /// fragment's typographic bounds) instead of the glyph box AppKit's
    /// `.backgroundColor` covers. Use it for marker-style fills: a span that
    /// wraps over several lines then reads as one solid block, at any font
    /// size and with any `paragraph.lineHeightExtraSpacing`, where
    /// `.backgroundColor` leaves a gap between every pair of lines.
    ///
    /// Painted by `MarkdownTextLayoutFragment`, so it renders in the editor
    /// only — table cells rasterize their own text and fall back to
    /// `.backgroundColor` (see `MarkdownStyler+Tables`).
    static let markdownBlockBackground = NSAttributedString.Key("MarkdownBlockBackground")

    /// NSColor — fenced code-block fill, painted full-width by
    /// `MarkdownTextLayoutFragment`. Distinct from `.backgroundColor` so
    /// AppKit doesn't composite a second glyph-box fill on top (a
    /// translucent code background then looks darker on the text line and
    /// on the short ``` fence glyphs than on the rest of the block).
    static let markdownCodeBlockBackground = NSAttributedString.Key("MarkdownCodeBlockBackground")
}

/// Vertical placement for painted overlays (`•`, `a.`) on a TextKit line box.
/// Extra `minimumLineHeight` leading sits above the glyphs, so the em-box is
/// pinned to the typographic bottom — matching the caret crop.
enum OverlayGlyphGeometry {
    /// Notion-like filled disc diameter, relative to body point size
    /// (~6.8pt at 17pt). The `•` glyph is closer to a period in most fonts.
    static let bulletDiameterEm: CGFloat = 0.4

    static func textTopY(lineMaxY: CGFloat, font: NSFont) -> CGFloat {
        lineMaxY + font.descender - font.ascender
    }

    static func bulletDiameter(for font: NSFont) -> CGFloat {
        max(5, font.pointSize * bulletDiameterEm)
    }

    /// Filled disc centered in the marker slot and on the font's x-height,
    /// matching Notion's bullet alignment.
    static func bulletRect(
        slotX: CGFloat,
        dashWidth: CGFloat,
        lineMaxY: CGFloat,
        font: NSFont
    ) -> CGRect {
        let d = bulletDiameter(for: font)
        let topY = textTopY(lineMaxY: lineMaxY, font: font)
        let xHeightCenterY = topY + font.ascender - font.xHeight * 0.5
        return CGRect(
            x: slotX + max(0, (dashWidth - d) * 0.5),
            y: xHeightCenterY - d * 0.5,
            width: d,
            height: d
        )
    }
}

/// Attributes that require custom work beyond TextKit's normal glyph drawing.
/// A fragment builds this mask once per valid layout, then dispatches only the
/// overlay painters that are present in that fragment.
private struct FragmentRenderFeatures: OptionSet {
    let rawValue: UInt16

    static let codeBlockBackground = Self(rawValue: 1 << 0)
    static let blockBackground = Self(rawValue: 1 << 1)
    static let latexImage = Self(rawValue: 1 << 2)
    static let taskCheckbox = Self(rawValue: 1 << 3)
    static let bulletMarker = Self(rawValue: 1 << 4)
    static let orderedMarker = Self(rawValue: 1 << 5)
    static let thematicBreak = Self(rawValue: 1 << 6)
    static let blockquote = Self(rawValue: 1 << 7)

    static let surfaceExtending: Self = [
        .codeBlockBackground, .thematicBreak, .blockquote, .taskCheckbox, .bulletMarker
    ]
}

private struct FragmentAttributeRun<Value> {
    let range: NSRange
    let value: Value
}

private struct FragmentLatexRun {
    let range: NSRange
    let image: NSImage
    let explicitImageBounds: CGRect?
    let isBlock: Bool
    let blockOffsetY: CGFloat?
    let isScrollableOverlay: Bool
}

private struct FragmentRenderPlan {
    let textStorage: NSTextStorage
    let range: NSRange
    let features: FragmentRenderFeatures
    let codeBlockBackground: NSColor?
    let blockBackgrounds: [FragmentAttributeRun<NSColor>]
    let latexImages: [FragmentLatexRun]
    let taskCheckboxes: [FragmentAttributeRun<Bool>]
    let bulletMarkers: [NSRange]
    let orderedMarkers: [FragmentAttributeRun<String>]
    let thematicBreaks: [NSRange]
    let blockquotes: [FragmentAttributeRun<Int>]

    init(textStorage: NSTextStorage, range: NSRange) {
        self.textStorage = textStorage
        self.range = range

        // Code backgrounds intentionally apply only when the fragment's first
        // character carries the attribute.
        let collectedCodeBlockBackground = textStorage.attribute(
            .markdownCodeBlockBackground,
            at: range.location,
            effectiveRange: nil
        ) as? NSColor
        codeBlockBackground = collectedCodeBlockBackground

        var collectedBlockBackgrounds: [FragmentAttributeRun<NSColor>] = []
        textStorage.enumerateAttribute(.markdownBlockBackground, in: range, options: []) { value, runRange, _ in
            guard let color = value as? NSColor else { return }
            collectedBlockBackgrounds.append(.init(range: runRange, value: color))
        }
        blockBackgrounds = collectedBlockBackgrounds

        var collectedLatexImages: [FragmentLatexRun] = []
        textStorage.enumerateAttribute(.latexImage, in: range, options: []) { value, runRange, _ in
            guard let image = value as? NSImage else { return }
            let location = runRange.location
            let bounds = (textStorage.attribute(.latexBounds, at: location, effectiveRange: nil) as? NSValue)?
                .rectValue
            collectedLatexImages.append(.init(
                range: runRange,
                image: image,
                explicitImageBounds: bounds,
                isBlock: textStorage.attribute(.latexIsBlock, at: location, effectiveRange: nil) as? Bool ?? false,
                blockOffsetY: textStorage.attribute(.latexBlockOffsetY, at: location, effectiveRange: nil) as? CGFloat,
                isScrollableOverlay: textStorage.attribute(
                    .scrollableBlockNaturalWidth,
                    at: location,
                    effectiveRange: nil
                ) != nil
            ))
        }
        latexImages = collectedLatexImages

        var collectedTaskCheckboxes: [FragmentAttributeRun<Bool>] = []
        textStorage.enumerateAttribute(.taskCheckbox, in: range, options: []) { value, runRange, _ in
            guard let isChecked = value as? Bool else { return }
            collectedTaskCheckboxes.append(.init(range: runRange, value: isChecked))
        }
        taskCheckboxes = collectedTaskCheckboxes

        var collectedBulletMarkers: [NSRange] = []
        textStorage.enumerateAttribute(.bulletMarker, in: range, options: []) { value, runRange, _ in
            guard value as? Bool == true else { return }
            collectedBulletMarkers.append(runRange)
        }
        bulletMarkers = collectedBulletMarkers

        var collectedOrderedMarkers: [FragmentAttributeRun<String>] = []
        textStorage.enumerateAttribute(.orderedMarker, in: range, options: []) { value, runRange, _ in
            guard let marker = value as? String else { return }
            collectedOrderedMarkers.append(.init(range: runRange, value: marker))
        }
        orderedMarkers = collectedOrderedMarkers

        var collectedThematicBreaks: [NSRange] = []
        textStorage.enumerateAttribute(.thematicBreak, in: range, options: []) { value, runRange, _ in
            guard value as? Bool == true else { return }
            collectedThematicBreaks.append(runRange)
        }
        thematicBreaks = collectedThematicBreaks

        var collectedBlockquotes: [FragmentAttributeRun<Int>] = []
        textStorage.enumerateAttribute(.blockquoteLevel, in: range, options: []) { value, runRange, _ in
            guard let level = value as? Int else { return }
            collectedBlockquotes.append(.init(range: runRange, value: level))
        }
        blockquotes = collectedBlockquotes

        var collectedFeatures: FragmentRenderFeatures = []
        if collectedCodeBlockBackground != nil { collectedFeatures.insert(.codeBlockBackground) }
        if !collectedBlockBackgrounds.isEmpty { collectedFeatures.insert(.blockBackground) }
        if !collectedLatexImages.isEmpty { collectedFeatures.insert(.latexImage) }
        if !collectedTaskCheckboxes.isEmpty { collectedFeatures.insert(.taskCheckbox) }
        if !collectedBulletMarkers.isEmpty { collectedFeatures.insert(.bulletMarker) }
        if !collectedOrderedMarkers.isEmpty { collectedFeatures.insert(.orderedMarker) }
        if !collectedThematicBreaks.isEmpty { collectedFeatures.insert(.thematicBreak) }
        if !collectedBlockquotes.isEmpty { collectedFeatures.insert(.blockquote) }
        features = collectedFeatures
    }
}

final class MarkdownTextLayoutFragment: NSTextLayoutFragment {

    /// Horizontal space (points) each blockquote nesting level occupies —
    /// shared so the styler's text indent and the painted bars line up.
    static let blockquoteIndentPerLevel: CGFloat = 18
    static let blockquoteBarWidth: CGFloat = 3

    /// Strip below an overlay block for the legacy-small scroller (~11pt) + buffer.
    static let scrollableBlockScrollerStrip: CGFloat = 14

    // MARK: - FB15131180

    /// Maps to TextKit-2's private `extraLineFragmentAttributes` selector so we can pin the trailing extra-line metrics to body font; otherwise a trailing heading paragraph inflates `usageBoundsForTextContainer` by ~30pt when the caret enters it. Pattern from STTextView.
    @objc(extraLineFragmentAttributes)
    dynamic var stExtraLineFragmentAttributes: NSDictionary?

    /// Valid for the lifetime of this fragment's current TextKit layout.
    /// `invalidateLayout()` is the authoritative invalidation point for text
    /// and rendering-attribute edits, so scrolling can reuse the render plan
    /// without risking stale overlay dispatch after an edit or restyle.
    private var cachedRenderPlan: FragmentRenderPlan?

    override func invalidateLayout() {
        cachedRenderPlan = nil
        super.invalidateLayout()
    }

    // MARK: - Rendering surface

    /// Extend rendering bounds for code-block backgrounds (full container width)
    /// and block images drawn below text via paragraphSpacing.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        guard let plan = makeRenderPlan() else { return bounds }
        // Task checkboxes too: the box draws left of the first glyph (marker
        // slot), outside the default text surface — TextKit would clip it.
        if !plan.features.intersection(.surfaceExtending).isEmpty {
            let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
            // Extend left to container edge
            bounds.origin.x = -layoutFragmentFrame.origin.x
            bounds.size.width = containerWidth
        }
        // Extend bounds to cover block images that render below the text line
        // (visibleSource mode uses paragraphSpacing to create space for the image).
        if plan.features.contains(.latexImage) {
            for rect in blockImageRects(at: .zero, plan: plan) {
                bounds = bounds.union(rect)
            }
        }
        // Line-box fills are taller than the glyphs they sit behind.
        if plan.features.contains(.blockBackground) {
            for fill in blockBackgroundFills(at: .zero, plan: plan) {
                bounds = bounds.union(fill.rect)
            }
        }
        return bounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let plan = makeRenderPlan() else {
            super.draw(at: point, in: context)
            return
        }

        // 1. Code-block backgrounds (behind text)
        if plan.features.contains(.codeBlockBackground) {
            drawCodeBlockBackground(at: point, in: context, plan: plan)
        }

        // 1b. Line-box fills (`==highlight==` and friends), behind text
        if plan.features.contains(.blockBackground) {
            drawBlockBackgrounds(at: point, in: context, plan: plan)
        }

        // 2. LaTeX images (behind text — hidden markers are invisible anyway)
        if plan.features.contains(.latexImage) {
            drawLatexImages(at: point, in: context, plan: plan)
        }

        // 3. Normal text
        super.draw(at: point, in: context)

        // 4. Task checkboxes (on top of hidden [ ]/[x] markers)
        if plan.features.contains(.taskCheckbox) {
            drawTaskCheckboxes(at: point, in: context, plan: plan)
        }

        // 4b. Bullet glyphs (on top of hidden -/*/+ markers)
        if plan.features.contains(.bulletMarker) {
            drawBulletMarkers(at: point, in: context, plan: plan)
        }
        if plan.features.contains(.orderedMarker) {
            drawOrderedMarkers(at: point, in: context, plan: plan)
        }

        // 5. Thematic breaks (full-width line, painted last so it doesn't
        //    fight with anything that already drew at the line's center)
        if plan.features.contains(.thematicBreak) {
            drawThematicBreaks(at: point, in: context, plan: plan)
        }

        // 6. Blockquote bars (left gutter, behind nothing — text is indented)
        if plan.features.contains(.blockquote) {
            drawBlockquoteBars(at: point, in: context, plan: plan)
        }
    }

    // MARK: - Helpers

    /// NSRange in the document for this fragment's content.
    private var fragmentNSRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private var textStorage: NSTextStorage? {
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
    }

    private func makeRenderPlan() -> FragmentRenderPlan? {
        guard let textStorage, let range = fragmentNSRange, range.length > 0 else { return nil }
        if let cachedRenderPlan,
           cachedRenderPlan.textStorage === textStorage,
           NSEqualRanges(cachedRenderPlan.range, range) {
            return cachedRenderPlan
        }
        let plan = FragmentRenderPlan(textStorage: textStorage, range: range)
        cachedRenderPlan = plan
        return plan
    }

    /// Returns the drawing position for a character at `docIndex` (document-level NSRange location).
    /// `point` is the draw origin passed to `draw(at:in:)`.
    private func drawPosition(
        forDocumentCharAt docIndex: Int,
        point: CGPoint,
        fragmentRange: NSRange
    ) -> (x: CGFloat, baselineY: CGFloat, lineHeight: CGFloat)? {
        let localIndex = docIndex - fragmentRange.location
        guard localIndex >= 0 else { return nil }

        // NSTextLineFragment.typographicBounds.origin.y is already relative to the
        // parent layout fragment, so we use it directly — accumulating per-line
        // heights would double-count the inter-line offset on wrapped lines.
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let charPos = lineFragment.locationForCharacter(at: localIndex)
                let tb = lineFragment.typographicBounds
                return (
                    x: point.x + tb.origin.x + charPos.x,
                    baselineY: point.y + tb.origin.y + charPos.y,
                    lineHeight: tb.height
                )
            }
        }
        return nil
    }

    /// Typographic bounds of the line fragment containing `localIndex`
    /// (index relative to the fragment, not the document).
    private func lineBounds(forLocalIndex localIndex: Int, point: CGPoint) -> CGRect? {
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let tb = lineFragment.typographicBounds
                return CGRect(x: point.x + lineFragment.glyphOrigin.x + tb.origin.x,
                              y: point.y + tb.origin.y,
                              width: tb.width,
                              height: tb.height)
            }
        }
        return nil
    }

    // MARK: - Code Block Background

    private func drawCodeBlockBackground(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        // Only fenced code-block fragments get the full-width fill (first char must carry the marker).
        guard let color = plan.codeBlockBackground else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
           let lastLF = textLineFragments.last,
           lastLF.characterRange.length == 0 {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y
        let rawMaxY = point.y + effectiveHeight
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale

        // Draw full-width background, clipping out any active selection rects
        // so the system's blue selection highlight remains visible inside code blocks.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let bgRect = CGRect(
            x: point.x - layoutFragmentFrame.origin.x,
            y: snappedY,
            width: containerWidth,
            height: snappedMaxY - snappedY
        )

        let selectionRects = selectionRectsInDrawCoordinates(drawPoint: point, snappedY: snappedY, snappedMaxY: snappedMaxY)
        color.setFill()
        if selectionRects.isEmpty {
            NSBezierPath(rect: bgRect).fill()
        } else {
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.appendRect(bgRect)
            for r in selectionRects {
                path.appendRect(r.intersection(bgRect))
            }
            path.fill()
        }
    }

    /// Returns active text-selection rectangles intersecting this fragment, in
    /// the same draw-relative coordinate system used by `drawCodeBlockBackground`.
    private func selectionRectsInDrawCoordinates(drawPoint: CGPoint, snappedY: CGFloat, snappedMaxY: CGFloat) -> [CGRect] {
        guard let tlm = textLayoutManager else { return [] }
        var rects: [CGRect] = []

        let dx = drawPoint.x - layoutFragmentFrame.origin.x
        let myRange = self.rangeInElement

        for selection in tlm.textSelections {
            for textRange in selection.textRanges {
                let interStart = textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd = textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                      let intersection = NSTextRange(location: interStart, end: interEnd) else { continue }

                tlm.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    // Expand vertically to match the bgRect's snapped span so the
                    // even-odd cut-out is geometrically congruent with the fill.
                    let drawRect = CGRect(
                        x: segFrame.origin.x + dx,
                        y: snappedY,
                        width: segFrame.width,
                        height: snappedMaxY - snappedY
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return rects
    }

    // MARK: - Line-Box Backgrounds

    /// Fill rects for every `.markdownBlockBackground` run in this fragment,
    /// one per line the run touches, relative to `point`.
    ///
    /// Each rect spans the line fragment's full typographic bounds — the same
    /// box the blockquote bars use, which is why a run of them reads as one
    /// continuous shape. AppKit's own `.backgroundColor` fill is the glyph box
    /// instead (ascent + descent), so it falls short of the line height by the
    /// leading plus `paragraph.lineHeightExtraSpacing` and a wrapped highlight
    /// comes out as stacked bands.
    func blockBackgroundFills(at point: CGPoint) -> [(rect: CGRect, color: NSColor)] {
        guard let plan = makeRenderPlan(), plan.features.contains(.blockBackground) else { return [] }
        return blockBackgroundFills(at: point, plan: plan)
    }

    private func blockBackgroundFills(
        at point: CGPoint,
        plan: FragmentRenderPlan
    ) -> [(rect: CGRect, color: NSColor)] {
        let range = plan.range
        var fills: [(rect: CGRect, color: NSColor)] = []
        for background in plan.blockBackgrounds {
            let attrRange = background.range
            let local = NSRange(location: attrRange.location - range.location, length: attrRange.length)
            for lineFragment in textLineFragments {
                let lineRange = lineFragment.characterRange
                let hit = NSIntersectionRange(lineRange, local)
                guard hit.length > 0 else { continue }
                let tb = lineFragment.typographicBounds
                let startX = lineFragment.locationForCharacter(at: hit.location).x
                // A run reaching the line's end fills to the line's own width:
                // the index one past the line belongs to the next fragment, and
                // asking this one for it is undefined.
                let reachesEnd = hit.location + hit.length >= lineRange.location + lineRange.length
                let endX = reachesEnd
                    ? tb.width
                    : lineFragment.locationForCharacter(at: hit.location + hit.length).x
                guard endX > startX else { continue }
                fills.append((
                    rect: CGRect(x: point.x + tb.origin.x + startX,
                                 y: point.y + tb.origin.y,
                                 width: endX - startX,
                                 height: tb.height),
                    color: background.value
                ))
            }
        }
        return fills
    }

    private func drawBlockBackgrounds(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let fills = blockBackgroundFills(at: point, plan: plan)
        guard !fills.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        for fill in fills {
            fill.color.setFill()
            NSBezierPath(rect: fill.rect).fill()
        }
    }

    // MARK: - LaTeX / Block Image Helpers

    /// Compute the draw rect for a block image at `attrRange` using `point` as
    /// the draw origin.  Shared by `drawLatexImages` and `blockImageRects` so
    /// bounds and rendering stay in sync.
    private func blockImageDrawRect(
        attrRange: NSRange,
        imageBounds: CGRect,
        blockOffsetY: CGFloat?,
        point: CGPoint,
        fragmentRange: NSRange
    ) -> CGRect? {
        guard let pos = drawPosition(
            forDocumentCharAt: attrRange.location,
            point: point,
            fragmentRange: fragmentRange
        ) else { return nil }
        let localStart = attrRange.location - fragmentRange.location
        let localLast = max(localStart, localStart + attrRange.length - 1)
        let firstLb = lineBounds(forLocalIndex: localStart, point: point)
        // For a wrapped source span (e.g. a long `![alt](url)` that wraps in
        // a narrow window), anchor to the LAST line's maxY so the image
        // doesn't paint over subsequent wrapped lines of its own source.
        let lastLb = lineBounds(forLocalIndex: localLast, point: point) ?? firstLb
        let lineHeight = firstLb?.height ?? pos.lineHeight
        let firstLineMinY = firstLb?.origin.y ?? (pos.baselineY - lineHeight)
        let lastLineMaxY = (lastLb?.origin.y ?? firstLineMinY) + (lastLb?.height ?? lineHeight)

        let yPosition: CGFloat
        if let blockOffsetY {
            // Backward-compatible interpretation: `blockOffsetY` is the gap
            // from the FIRST line's top to the image's top (= baseLineHeight
            // + imageGap on a single-line source). Re-anchor to the last
            // line by subtracting one line height, leaving the same single-
            // line geometry intact while pushing the image down by one
            // extra line per wrap.
            yPosition = lastLineMaxY + blockOffsetY - lineHeight
        } else {
            yPosition = firstLineMinY + (lineHeight - imageBounds.height) / 2
        }
        return CGRect(x: pos.x, y: yPosition,
                       width: imageBounds.width, height: imageBounds.height)
    }

    /// Returns the rects of all block images in this fragment, relative to
    /// `point`.  Used by `renderingSurfaceBounds` (with `.zero`) to extend
    /// the surface so images drawn in paragraphSpacing aren't clipped.
    private func blockImageRects(at point: CGPoint, plan: FragmentRenderPlan) -> [CGRect] {
        let range = plan.range
        var rects: [CGRect] = []
        for latex in plan.latexImages {
            guard latex.isBlock else { continue }
            // Skip overlay blocks; surface bounds must stay within container.
            guard !latex.isScrollableOverlay else { continue }
            if let rect = blockImageDrawRect(
                attrRange: latex.range,
                imageBounds: latex.explicitImageBounds ?? .zero,
                blockOffsetY: latex.blockOffsetY,
                point: point,
                fragmentRange: range
            ) {
                rects.append(rect)
            }
        }
        return rects
    }

    // MARK: - LaTeX Images

    private func drawLatexImages(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let range = plan.range

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        for latex in plan.latexImages {
            // Skip overlay-rendered blocks; WideTableOverlay owns the visual.
            guard !latex.isScrollableOverlay else { continue }

            guard let pos = drawPosition(
                forDocumentCharAt: latex.range.location,
                point: point,
                fragmentRange: range
            ) else { continue }

            let drawRect: CGRect
            let imageBounds = latex.explicitImageBounds ?? CGRect(origin: .zero, size: latex.image.size)
            if latex.isBlock {
                guard let rect = blockImageDrawRect(
                    attrRange: latex.range,
                    imageBounds: imageBounds,
                    blockOffsetY: latex.blockOffsetY,
                    point: point,
                    fragmentRange: range
                ) else { continue }
                drawRect = rect
            } else {
                let descent = imageBounds.origin.y
                drawRect = CGRect(x: pos.x + imageBounds.origin.x,
                                  y: pos.baselineY + descent - imageBounds.height,
                                  width: imageBounds.width, height: imageBounds.height)
            }
            latex.image.draw(in: drawRect)
        }
    }

    // MARK: - Thematic Breaks (---, ***, ___)

    /// Draw a 1pt horizontal rule across the full container width for any
    /// line fragment whose backing text carries the `.thematicBreak`
    /// attribute. This decouples HR rendering from the source-text length,
    /// so a 3-char `---` looks the same as a 80-char auto-expanded line.
    private func drawThematicBreaks(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let strokeColor = theme.strikethroughColor.withAlphaComponent(0.4)
        strokeColor.setFill()

        // Walk each line fragment in this layout fragment and paint a
        // band on those whose first character carries the marker. (HR
        // tokens are always single-line, but the loop is robust if a
        // future caller ever stacks several rules in one paragraph.)
        let fragLocation = plan.range.location
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            let docStart = fragLocation + lr.location
            let isHR = plan.thematicBreaks.contains { NSLocationInRange(docStart, $0) }
            let tb = lineFragment.typographicBounds
            if isHR {
                // tb.origin.y is already relative to this layout fragment.
                let centerY = point.y + tb.origin.y + tb.height / 2
                let bandRect = CGRect(
                    x: point.x - layoutFragmentFrame.origin.x,
                    y: centerY - 0.5,
                    width: containerWidth,
                    height: 1
                )
                NSBezierPath(rect: bandRect).fill()
            }
        }
    }

    // MARK: - Blockquote Bars

    /// Paint `level` vertical bars in the left gutter of every line that
    /// carries `.blockquoteLevel`. Each line paints its own segment, so a
    /// run of quote lines reads as one continuous bar.
    private func drawBlockquoteBars(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default
        let indentPerLevel = Self.blockquoteIndentPerLevel
        let barWidth = Self.blockquoteBarWidth

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        theme.mutedText.withAlphaComponent(0.5).setFill()

        let fragLocation = plan.range.location
        let leftEdge = point.x - layoutFragmentFrame.origin.x
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            let docStart = fragLocation + lr.location
            let tb = lineFragment.typographicBounds
            if let level = plan.blockquotes.first(where: { NSLocationInRange(docStart, $0.range) })?.value {
                // tb.origin.y is already relative to this layout fragment.
                let barY = point.y + tb.origin.y
                for i in 0..<level {
                    let barX = leftEdge + CGFloat(i) * indentPerLevel + indentPerLevel * 0.25
                    NSBezierPath(rect: CGRect(
                        x: barX, y: barY, width: barWidth, height: tb.height
                    )).fill()
                }
            }
        }
    }

    // MARK: - Bullet Markers

    /// Paint a Notion-sized filled disc over every hidden bullet marker
    /// (`.bulletMarker`). Centered in the original marker char's advance so it
    /// still sits where `-`/`*`/`+` was. Selection paints the raw source char.
    private func drawBulletMarkers(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let ts = plan.textStorage
        let range = plan.range
        let selectionRanges: [NSRange] = {
            guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
            return tv.selectedRanges.map { $0.rangeValue }.filter { $0.length > 0 }
        }()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default
        let storageString = ts.string as NSString
        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        func alignToPixel(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        }

        for attrRange in plan.bulletMarkers {
            guard let pos = drawPosition(
                forDocumentCharAt: attrRange.location,
                point: point,
                fragmentRange: range
            ) else { continue }

            let bodyFont = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.baseFont
                ?? (textLayoutManager?.textContainer?.textView?.font
                    ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
            let runFont = ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont
            let collapsed = (runFont?.pointSize ?? bodyFont.pointSize) < 1
            // A `.bulletMarker` range means the styler painted the raw char
            // `.clear`, so something must ALWAYS be drawn over the slot. Outside
            // a selection that's the rendered disc; while the marker sits inside
            // a selection the raw source char (`-`/`*`/`+`) is painted instead,
            // so selecting a list line reveals its raw syntax. (The styler's own
            // reveal is caret-based and doesn't fire for selections — an earlier
            // selection-skip here drew nothing over the cleared char, which left
            // an empty slot wherever the selection anchor wasn't in the marker.)
            let isSelected = selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 })
            let raw = storageString.substring(with: attrRange)
            let dashWidth = (raw as NSString).size(withAttributes: [.font: bodyFont]).width
            let spaceWidth = (" " as NSString).size(withAttributes: [.font: bodyFont]).width
            // Collapsed `- ` sits at the content edge; paint the bullet in the
            // indent slot to its left (same geometry as the hanging indent).
            let slotX = collapsed ? pos.x - dashWidth - spaceWidth : pos.x
            let localIndex = attrRange.location - range.location
            let lineMaxY: CGFloat
            if let bounds = lineBounds(forLocalIndex: localIndex, point: point) {
                lineMaxY = bounds.maxY
            } else {
                lineMaxY = pos.baselineY - bodyFont.descender
            }

            if isSelected {
                let glyph = raw as NSString
                let glyphAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: theme.bodyText]
                let glyphWidth = glyph.size(withAttributes: glyphAttrs).width
                let xOffset = max(0, (dashWidth - glyphWidth) / 2)
                let topY = OverlayGlyphGeometry.textTopY(lineMaxY: lineMaxY, font: bodyFont)
                glyph.draw(at: CGPoint(x: slotX + xOffset, y: topY), withAttributes: glyphAttrs)
            } else {
                var rect = OverlayGlyphGeometry.bulletRect(
                    slotX: slotX,
                    dashWidth: dashWidth,
                    lineMaxY: lineMaxY,
                    font: bodyFont
                )
                rect.origin.x = alignToPixel(rect.origin.x)
                rect.origin.y = alignToPixel(rect.origin.y)
                theme.bodyText.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }

    // MARK: - Ordered List Markers

    /// Paint the whole display marker "N." (`.orderedMarker` value) over the
    /// hidden source marker (digits + dot, cleared by the styler as one unit and
    /// kerned to the display width so any digit count aligns and content/wrapped
    /// lines hang at that width). Draws the raw source marker instead while the
    /// line is selected, so selection reveals the literal digits.
    private func drawOrderedMarkers(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let ts = plan.textStorage
        let range = plan.range
        let selectionRanges: [NSRange] = {
            guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
            return tv.selectedRanges.map { $0.rangeValue }.filter { $0.length > 0 }
        }()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let theme = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.theme ?? .default
        let storageString = ts.string as NSString

        for marker in plan.orderedMarkers {
            let attrRange = marker.range
            guard let pos = drawPosition(
                forDocumentCharAt: attrRange.location,
                point: point,
                fragmentRange: range
            ) else { continue }
            let font = (ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont)
                ?? (textLayoutManager?.textContainer?.textView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
            let isSelected = selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 })
            let raw = storageString.substring(with: attrRange)
            let glyph = (isSelected ? raw : marker.value) as NSString
            let glyphAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.bodyText]
            let localIndex = attrRange.location - range.location
            let topY: CGFloat
            if let bounds = lineBounds(forLocalIndex: localIndex, point: point) {
                topY = OverlayGlyphGeometry.textTopY(lineMaxY: bounds.maxY, font: font)
            } else {
                topY = pos.baselineY - font.ascender
            }
            glyph.draw(at: CGPoint(x: pos.x, y: topY), withAttributes: glyphAttrs)
        }
    }

    // MARK: - Task List Checkboxes

    private func drawTaskCheckboxes(
        at point: CGPoint,
        in context: CGContext,
        plan: FragmentRenderPlan
    ) {
        let range = plan.range

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        for checkbox in plan.taskCheckboxes {
            let attrRange = checkbox.range
            // A `.taskCheckbox` range means the styler cleared the raw `- [ ]`
            // (and collapsed the box's advance), so the box must ALWAYS be
            // drawn — including while the range sits inside a selection. An
            // earlier selection-skip here left an empty marker-width gap (the
            // bullet-marker blank-slot bug's twin). Unlike bullets, the raw
            // source can't be painted here instead: the hidden `[ ]` advance
            // is collapsed, so raw glyphs would overlap the content — raw
            // reveal stays caret-based (taskRevealed in the styler).
            let isChecked = checkbox.value
            guard let pos = drawPosition(
                forDocumentCharAt: attrRange.location,
                point: point,
                fragmentRange: range
            ) else { continue }

            // Box collapsed to 0.1pt, so pos.x sits at the content edge; the
            // square is right-aligned to it (shared with the click hit-test).
            // Use baseFont, NOT NSTextView.font — its getter returns the first
            // char's font (0.1pt in a heading-first doc → 1px boxes).
            let font = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.baseFont
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let ascent = max(0, font.ascender)
            let descent = max(0, -font.descender)
            let size = TaskCheckboxGeometry.size(for: font)
            let boxX = TaskCheckboxGeometry.boxX(contentX: pos.x, size: size)
            let centerY = pos.baselineY + (descent - ascent) / 2
            let boxY = centerY - size / 2

            let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2.0
            func alignToPixel(_ value: CGFloat) -> CGFloat {
                (value * scale).rounded(.toNearestOrAwayFromZero) / scale
            }
            let boxRect = CGRect(x: alignToPixel(boxX), y: alignToPixel(boxY), width: size, height: size)
            guard !boxRect.isEmpty, !boxRect.isNull else { continue }

            let iconInset = max(0.0, size * 0.01)
            let iconRect = boxRect.insetBy(dx: iconInset, dy: iconInset)
            let configuration = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.configuration
                ?? .default
            let style = configuration.taskCheckbox
            let symbolName = isChecked ? style.checkedSymbolName : style.uncheckedSymbolName
            let fallbackName = isChecked
                ? TaskCheckboxStyle.default.checkedSymbolName
                : TaskCheckboxStyle.default.uncheckedSymbolName
            if let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil) {
                let sizeConfig = NSImage.SymbolConfiguration(pointSize: iconRect.height, weight: .regular)
                let tint = isChecked ? configuration.theme.bodyText : configuration.theme.mutedText
                let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: tint)
                let symbolConfig = sizeConfig.applying(colorConfig)
                let symbol = baseSymbol.withSymbolConfiguration(symbolConfig) ?? baseSymbol
                symbol.draw(in: iconRect)
            }
        }
    }
}

// MARK: - Layout Manager Delegate

final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate, NSTextContentStorageDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        PerfTrace.accumulate("fragProv") {
            makeFragment(textLayoutManager: textLayoutManager, textElement: textElement)
        }
    }

    private func makeFragment(
        textLayoutManager: NSTextLayoutManager,
        textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        // Seed body font + paragraphStyle so the trailing fragment doesn't inherit heading metrics (FB15131180).
        if let textView = textLayoutManager.textContainer?.textView as? NativeTextView {
            let baseFont = textView.baseFont
            let para = NSMutableParagraphStyle()
            let lineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: textView.layoutBridge)
            para.minimumLineHeight = ceil(lineHeight) + textView.configuration.paragraph.lineHeightExtraSpacing
            para.paragraphSpacing = ceil(lineHeight * textView.configuration.paragraph.spacingFactor)
            para.paragraphSpacingBefore = 0
            fragment.stExtraLineFragmentAttributes = NSDictionary(dictionary: [
                NSAttributedString.Key.font: baseFont,
                NSAttributedString.Key.foregroundColor: textView.configuration.theme.bodyText,
                NSAttributedString.Key.paragraphStyle: para
            ])
        }
        return fragment
    }

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let ts = textContentStorage.textStorage,
              range.location >= 0, NSMaxRange(range) <= ts.length else { return nil }
        let snippet = ts.attributedSubstring(from: range)
        guard LinePrefixGlue.prefixLength(in: snippet.string) > 0 else { return nil }
        let mutable = NSMutableAttributedString(attributedString: snippet)
        guard LinePrefixGlue.apply(to: mutable) else { return nil }
        return NSTextParagraph(attributedString: mutable)
    }
}
