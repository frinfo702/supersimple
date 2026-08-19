//
//  OrderedListMarkerFormat.swift
//  MarkdownEngine
//
//  Outline-style display labels for nested ordered lists. Source stays
//  Markdown digits (`1.`); the editor overlays 1/a/i cycling by indent:
//  1, 2, … → a, b, … → i, ii, iii, … → 1, 2, …
//

import Foundation

enum OrderedListMarkerFormat {
    /// Display label (no punctuation) for a 1-based item number at `depth`
    /// (0 = top-level). Depth cycles every 3 levels.
    static func label(number: Int, depth: Int) -> String {
        let n = max(1, number)
        switch ((depth % 3) + 3) % 3 {
        case 1: return alphabetic(n)
        case 2: return roman(n)
        default: return String(n)
        }
    }

    static func marker(number: Int, depth: Int, punct: String) -> String {
        label(number: number, depth: depth) + punct
    }

    /// Nested runs restart at 1 so Tab-indenting a continued `2.` shows `a.`,
    /// not `b.`. A top-level run keeps its literal start (`5.` stays 5).
    static func runStart(indent: Int, literal: Int, existing: Int?) -> Int {
        if let existing { return existing }
        return indent == 0 ? max(1, literal) : 1
    }

    /// 1 → a, 26 → z, 27 → aa.
    static func alphabetic(_ number: Int) -> String {
        var n = max(1, number)
        var chars: [Character] = []
        while n > 0 {
            n -= 1
            chars.append(Character(UnicodeScalar(97 + n % 26)!))
            n /= 26
        }
        return String(chars.reversed())
    }

    /// Lowercase roman numerals.
    static func roman(_ number: Int) -> String {
        var n = max(1, min(number, 3999))
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
            (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var result = ""
        for (value, glyph) in table {
            while n >= value {
                result += glyph
                n -= value
            }
        }
        return result
    }
}
