import Foundation

/// A tag identifier. Tags are normalized lowercase tokens without the leading `#`.
public struct Tag: Hashable, Comparable, Sendable, Codable {
    public let name: String

    public init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func < (lhs: Tag, rhs: Tag) -> Bool {
        lhs.name < rhs.name
    }
}

public enum TagNormalizer {
    /// Splits a raw note body into `#tag` tokens.
    /// Supports `#word`, `#multi-word`. Nested `#a/b` stays flattened.
    public static func extractTags(from body: String) -> Set<Tag> {
        var result: Set<Tag> = []
        var index = body.startIndex

        while let hash = body[index...].firstIndex(of: "#") {
            let start = body.index(after: hash)
            var end = start
            var hasContent = false

            while end < body.endIndex {
                let c = body[end]
                if isTagToken(c) {
                    hasContent = true
                    end = body.index(after: end)
                } else {
                    break
                }
            }

            if hasContent {
                let token = String(body[start..<end])
                // Reject degenerate tokens that contain no letter or digit (e.g. "#-", "#_").
                if token.contains(where: { $0.isLetter || $0.isNumber }) {
                    result.insert(Tag(name: token))
                }
            }

            index = end < body.endIndex ? end : body.endIndex
            if index == body.endIndex { break }
        }

        return result
    }

    private static func isTagToken(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return c == "-" || c == "_"
    }

    /// Canonical tag used for display and dedup.
    public static func normalize(_ raw: String) -> String {
        Tag(name: raw).name
    }
}
