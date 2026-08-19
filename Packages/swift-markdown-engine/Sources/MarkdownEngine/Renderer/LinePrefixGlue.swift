//
//  LinePrefixGlue.swift
//  MarkdownEngine
//
//  TextKit wraps at Unicode break opportunities. A list/quote marker ends
//  with a space, so a following unbreakable run (URL, `aaaa…`) is pushed to
//  the next line and the marker sits alone. Presentation-only: that trailing
//  marker space becomes U+2060 WORD JOINER (same UTF-16 length) with the
//  original advance hung on the preceding glyph, which removes the break
//  without changing document storage.
//
//  Leading indent tabs/spaces are left alone. Nested lists and Tab indent
//  use `\t` plus tab stops / `defaultTabInterval`; replacing those with a
//  WORD JOINER collapses the indent because WORD JOINER ignores `.kern`.
//

import AppKit

enum LinePrefixGlue {
    static let wordJoiner = "\u{2060}"

    /// Returns `true` when `attr` was mutated.
    @discardableResult
    static func apply(to attr: NSMutableAttributedString) -> Bool {
        let info = prefix(in: attr.string)
        guard info.length > info.indentLength else { return false }

        let ns = attr.string as NSString
        var didMutate = false
        for i in (info.indentLength..<info.length).reversed() {
            let c = ns.character(at: i)
            // Keep tabs: they are the indent unit and must retain tab-stop width.
            guard c == 0x20 else { continue }
            glueWhitespace(at: i, in: attr)
            didMutate = true
        }
        return didMutate
    }

    /// Leading indent plus list/blockquote marker, including the trailing
    /// space those markers require. 0 when the paragraph has no such prefix.
    static func prefixLength(in string: String) -> Int {
        prefix(in: string).length
    }

    struct Prefix: Equatable {
        /// Full prefix (indent + marker + trailing marker space).
        let length: Int
        /// Leading indent only (`\t` / spaces before the marker).
        let indentLength: Int
    }

    /// 0-length when the line is not a list or blockquote. Plain Tab indent
    /// (`\thello`) must not count — otherwise presentation glue would eat it.
    static func prefix(in string: String) -> Prefix {
        let ns = string as NSString
        var end = ns.length
        while end > 0 {
            let last = ns.character(at: end - 1)
            guard last == 0x0A || last == 0x0D else { break }
            end -= 1
        }
        guard end > 0 else { return Prefix(length: 0, indentLength: 0) }

        let lineRange = NSRange(location: 0, length: end)
        let line = ns.substring(with: lineRange)
        let lineNS = line as NSString
        let lineUTF16 = lineNS.length
        let full = NSRange(location: 0, length: lineUTF16)

        var wsLen = 0
        if let m = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: line, range: full) {
            wsLen = m.range.length
        }

        let rest = lineNS.substring(from: wsLen)
        let restFull = NSRange(location: 0, length: (rest as NSString).length)

        if let m = MarkdownLists.blockquoteRegex.firstMatch(in: rest, range: restFull) {
            var length = wsLen + NSMaxRange(m.range)
            let afterQuote = lineNS.substring(from: length)
            let afterFull = NSRange(location: 0, length: (afterQuote as NSString).length)
            if let list = MarkdownLists.listRegex.firstMatch(in: afterQuote, range: afterFull) {
                length += NSMaxRange(list.range)
            }
            return Prefix(length: length, indentLength: wsLen)
        }
        if let list = MarkdownLists.listRegex.firstMatch(in: rest, range: restFull) {
            return Prefix(length: wsLen + NSMaxRange(list.range), indentLength: wsLen)
        }
        return Prefix(length: 0, indentLength: 0)
    }

    private static func glueWhitespace(at index: Int, in attr: NSMutableAttributedString) {
        let ns = attr.string as NSString
        let range = NSRange(location: index, length: 1)
        let original = ns.substring(with: range)
        let attrs = attr.attributes(at: index, effectiveRange: nil)
        let width = max(0, (original as NSString).size(withAttributes: attrs).width)
        attr.replaceCharacters(in: range, with: wordJoiner)
        guard index > 0 else {
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
