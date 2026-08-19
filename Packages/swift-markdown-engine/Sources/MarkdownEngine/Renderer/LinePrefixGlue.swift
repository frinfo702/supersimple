//
//  LinePrefixGlue.swift
//  MarkdownEngine
//
//  TextKit wraps at Unicode break opportunities. A list/quote/indent prefix
//  ends with space or tab, so a following unbreakable run (URL, `aaaa…`) is
//  pushed to the next line and the marker sits alone. Presentation-only:
//  those prefix whitespace characters become U+2060 WORD JOINER (same UTF-16
//  length) kerned to the original advance, which removes the break without
//  changing document storage.
//

import AppKit

enum LinePrefixGlue {
    static let wordJoiner = "\u{2060}"

    /// Returns `true` when `attr` was mutated.
    @discardableResult
    static func apply(to attr: NSMutableAttributedString, tabWidth: CGFloat) -> Bool {
        let prefixLen = prefixLength(in: attr.string)
        guard prefixLen > 0 else { return false }

        let ns = attr.string as NSString
        var didMutate = false
        for i in (0..<prefixLen).reversed() {
            let c = ns.character(at: i)
            guard c == 0x20 || c == 0x09 else { continue }
            glueWhitespace(at: i, in: attr, tabWidth: tabWidth)
            didMutate = true
        }
        return didMutate
    }

    /// Leading indent plus list/blockquote marker, including the trailing
    /// space those markers require. 0 when the paragraph has no such prefix.
    static func prefixLength(in string: String) -> Int {
        let ns = string as NSString
        var end = ns.length
        while end > 0 {
            let last = ns.character(at: end - 1)
            guard last == 0x0A || last == 0x0D else { break }
            end -= 1
        }
        guard end > 0 else { return 0 }

        let lineRange = NSRange(location: 0, length: end)
        let line = ns.substring(with: lineRange)
        let lineNS = line as NSString
        let lineUTF16 = lineNS.length
        let full = NSRange(location: 0, length: lineUTF16)

        var wsLen = 0
        if let m = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: line, range: full) {
            wsLen = m.range.length
        }

        var prefix = wsLen
        let rest = lineNS.substring(from: wsLen)
        let restFull = NSRange(location: 0, length: (rest as NSString).length)

        if let m = MarkdownLists.blockquoteRegex.firstMatch(in: rest, range: restFull) {
            prefix = wsLen + NSMaxRange(m.range)
            let afterQuote = lineNS.substring(from: prefix)
            let afterFull = NSRange(location: 0, length: (afterQuote as NSString).length)
            if let list = MarkdownLists.listRegex.firstMatch(in: afterQuote, range: afterFull) {
                prefix += NSMaxRange(list.range)
            }
        } else if let list = MarkdownLists.listRegex.firstMatch(in: rest, range: restFull) {
            prefix = wsLen + NSMaxRange(list.range)
        }

        return prefix
    }

    private static func glueWhitespace(at index: Int, in attr: NSMutableAttributedString, tabWidth: CGFloat) {
        let ns = attr.string as NSString
        let range = NSRange(location: index, length: 1)
        let original = ns.substring(with: range)
        let attrs = attr.attributes(at: index, effectiveRange: nil)
        let width: CGFloat = original == "\t"
            ? tabWidth
            : max(0, (original as NSString).size(withAttributes: attrs).width)
        attr.replaceCharacters(in: range, with: wordJoiner)
        if original == "\t" || index == 0 {
            // Tabs have no preceding glyph to hang width on.
            attr.addAttribute(.kern, value: width, range: range)
            return
        }
        // WORD JOINER often ignores `.kern`. Hang the original advance on the
        // preceding glyph so a hanging indent still matches the first line.
        let prev = NSRange(location: index - 1, length: 1)
        let prevKern = (attr.attribute(.kern, at: prev.location, effectiveRange: nil) as? CGFloat) ?? 0
        attr.addAttribute(.kern, value: prevKern + width, range: prev)
    }
}
