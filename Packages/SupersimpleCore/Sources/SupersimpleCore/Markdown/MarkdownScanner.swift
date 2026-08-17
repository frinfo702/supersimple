import Foundation

public struct MathSegment: Equatable, Sendable {
    /// `true` for display math `$$...$$`, `false` for inline math `$...$`.
    public let isInline: Bool
    public let source: String
    public let content: String
    public let range: Range<String.Index>
    /// Byte offset of the segment start within the source string (UTF-16).
    public let utf16Offset: Int
}

public struct CodeFence: Equatable, Sendable {
    public let language: String?
    /// Range of the fence line (opening), used to skip math scanning inside code.
    public let range: Range<String.Index>
}

/// Lightweight single-pass markdown scanning, free of any rendering framework.
///
/// Used by the editor for LaTeX cache invalidation and code-block metadata. Everything
/// here is pure so it is trivially unit-testable.
public enum MarkdownScanner {

    /// Collects LaTeX segments (block `$$...$$` and inline `$...$`).
    /// Segments inside a fenced code block are ignored.
    public static func mathSegments(in text: String) -> [MathSegment] {
        let fenceRanges = codeFenceRanges(in: text)

        func inFence(_ index: String.Index) -> Bool {
            fenceRanges.contains { index >= $0.lowerBound && index < $0.upperBound }
        }

        var result: [MathSegment] = []
        var index = text.startIndex

        while let dollar = findDollar(from: index, in: text, excluding: inFence) {
            let nextIndex = text.index(dollar, offsetBy: 1, limitedBy: text.endIndex)
            let doubleOpen = nextIndex.map { text[$0] == "$" } ?? false

            if doubleOpen {
                guard let contentStart = text.index(dollar, offsetBy: 2, limitedBy: text.endIndex) else {
                    break
                }
                if let close = findSequence("$$", from: contentStart, in: text) {
                    let segmentEnd = text.index(close, offsetBy: 2)
                    let whole = String(text[dollar..<segmentEnd])
                    result.append(
                        MathSegment(
                            isInline: false,
                            source: whole,
                            content: String(text[contentStart..<close]),
                            range: dollar..<segmentEnd,
                            utf16Offset: text.utf16.distance(from: text.startIndex, to: dollar)
                        )
                    )
                    index = segmentEnd
                } else {
                    break
                }
            } else {
                guard let contentStart = text.index(dollar, offsetBy: 1, limitedBy: text.endIndex),
                    contentStart < text.endIndex
                else { break }
                if let close = findClosingDollar(from: contentStart, in: text) {
                    let segmentEnd = text.index(after: close)
                    result.append(
                        MathSegment(
                            isInline: true,
                            source: String(text[dollar..<segmentEnd]),
                            content: String(text[contentStart..<close]),
                            range: dollar..<segmentEnd,
                            utf16Offset: text.utf16.distance(from: text.startIndex, to: dollar)
                        )
                    )
                    index = segmentEnd
                } else {
                    break
                }
            }
        }
        return result
    }

    /// Returns the ranges (as spans) inside which math should be skipped because they hold code.
    public static func codeFenceRanges(in text: String) -> [Range<String.Index>] {
        codeFences(in: text).map(\.range)
    }

    /// Collects fenced code blocks together with their language info.
    public static func codeFences(in text: String) -> [CodeFence] {
        var result: [CodeFence] = []
        let lines = text.linesWithRanges
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let backticks = line.text.prefix(while: { $0 == "`" }).count
            if backticks >= 3 {
                let languageEnd = line.text.index(line.text.startIndex, offsetBy: backticks)
                let language = String(line.text[languageEnd...]).trimmingCharacters(in: .whitespaces)
                let fenceStart = line.range.lowerBound

                var j = i + 1
                var closeLineIndex: Int?
                while j < lines.count {
                    if lines[j].text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        closeLineIndex = j
                        break
                    }
                    j += 1
                }

                let closeLineEnd =
                    closeLineIndex.map { lines[$0].range.upperBound } ?? lines[lines.count - 1].range.upperBound
                result.append(
                    CodeFence(
                        language: language.isEmpty ? nil : language,
                        range: fenceStart..<closeLineEnd
                    )
                )

                if let close = closeLineIndex {
                    i = close + 1
                    continue
                }
            }
            i += 1
        }
        return result
    }

    // MARK: - Internals

    private static func findDollar(
        from index: String.Index,
        in text: String,
        excluding inFence: (String.Index) -> Bool
    ) -> String.Index? {
        var cursor = index
        while cursor < text.endIndex {
            if text[cursor] == "$", !inFence(cursor) {
                return cursor
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func findClosingDollar(from index: String.Index, in text: String) -> String.Index? {
        var cursor = index
        while cursor < text.endIndex {
            if text[cursor] == "$" {
                let nextIndex = text.index(cursor, offsetBy: 1, limitedBy: text.endIndex)
                let isDouble = nextIndex.map { text[$0] == "$" } ?? false
                if !isDouble { return cursor }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func findSequence(_ sequence: String, from index: String.Index, in text: String) -> String.Index? {
        var cursor = index
        while cursor < text.endIndex {
            if text[cursor...].hasPrefix(sequence) {
                return cursor
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}

private struct MarkdownLine {
    let text: String
    let range: Range<String.Index>
}

extension String {
    fileprivate var linesWithRanges: [MarkdownLine] {
        var result: [MarkdownLine] = []
        var start = startIndex

        while start <= endIndex {
            var cursor = start
            var isNewline = false
            while cursor < endIndex {
                if self[cursor] == "\n" {
                    isNewline = true
                    break
                }
                cursor = index(after: cursor)
            }

            let lineEnd = isNewline ? cursor : endIndex
            result.append(MarkdownLine(text: String(self[start..<lineEnd]), range: start..<lineEnd))

            if !isNewline { break }
            start = index(after: lineEnd)
        }
        return result
    }
}
