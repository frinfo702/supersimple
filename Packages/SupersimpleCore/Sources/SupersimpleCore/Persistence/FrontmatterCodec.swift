import Foundation

public enum FrontmatterError: Error, Equatable, Sendable {
    case malformedBody
}

/// Concrete representation of the whole `.md` document stored on disk: an optional YAML
/// frontmatter block followed by the raw markdown body.
public struct MarkdownDocument: Equatable, Sendable {
    public var metadata: NoteMetadata
    public var body: String

    public init(metadata: NoteMetadata, body: String) {
        self.metadata = metadata
        self.body = body
    }

    public var fullText: String {
        FrontmatterCodec.encode(metadata, body: body)
    }
}

public struct NoteMetadata: Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: Set<Tag>
    /// Raw frontmatter lines this app does not manage (e.g. Obsidian `aliases`,
    /// `cssclasses`, custom keys). Preserved verbatim so nothing is lost on save.
    public var extraFields: [String]

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        tags: Set<Tag>,
        extraFields: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.extraFields = extraFields
    }
}

/// Encodes and decodes note metadata as an Obsidian-style YAML frontmatter block.
///
/// Layout on disk:
/// ```text
/// ---
/// id: 8B31...
/// created: 2026-08-17T10:00:00.123Z
/// updated: 2026-08-17T10:05:00.456Z
/// tags: [swift, idea]
/// ---
///
/// # body...
/// ```
public enum FrontmatterCodec {

    // MARK: - Encoding

    public static func encode(_ metadata: NoteMetadata, body: String) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(metadata.id.uuidString)")
        lines.append("created: \(Self.format(metadata.createdAt))")
        lines.append("updated: \(Self.format(metadata.updatedAt))")

        let sortedTags = metadata.tags.sorted().map(\.name)
        if !sortedTags.isEmpty {
            lines.append("tags: [\(sortedTags.joined(separator: ", "))]")
        }

        // Preserve unknown fields verbatim, skipping any that duplicate managed keys
        // (id/created/updated/tags) so they are not emitted twice.
        let managedPrefixes = ["id:", "created:", "updated:", "tags:"]
        for extra in metadata.extraFields {
            let trimmed = extra.trimmingCharacters(in: whitespace)
            let lower = trimmed.lowercased()
            if managedPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
            lines.append(extra)
        }

        lines.append("---")
        let header = lines.joined(separator: "\n")
        // Do NOT trim the body: leading indentation and trailing hard-break spaces
        // are semantically meaningful in Markdown.
        return body.isEmpty ? header : header + "\n\n" + body
    }

    // MARK: - Decoding

    public static func decode(_ text: String) throws -> MarkdownDocument {
        guard let (meta, body) = try FrontmatterDecoder.extract(text) else {
            // No (or malformed) frontmatter: the whole text is the body.
            let now = Date()
            return MarkdownDocument(
                metadata: NoteMetadata(id: UUID(), createdAt: now, updatedAt: now, tags: []),
                body: text
            )
        }
        return MarkdownDocument(metadata: meta, body: body)
    }

    /// Parses from a raw `Note` plus the original document text, detached from the file system.
    public static func document(note: Note) -> MarkdownDocument {
        MarkdownDocument(
            metadata: NoteMetadata(
                id: note.id,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                extraFields: note.extraFields
            ),
            body: note.body
        )
    }

    // MARK: - Date format (fractional seconds so rapid updates stay distinct)

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static let whitespace = CharacterSet.whitespaces
}

// MARK: - YAML frontmatter parsing

private enum FrontmatterDecoder {

    /// Splits `text` into lines together with their byte ranges in the original string.
    /// Handles both LF and CRLF endings without dropping the newline.
    private struct Line {
        let text: String  // without trailing newline
        let range: Range<String.Index>
    }

    private static func lines(in text: String) -> [Line] {
        var result: [Line] = []
        var start = text.startIndex
        while start < text.endIndex {
            var end = start
            while end < text.endIndex {
                let c = text[end]
                // Swift folds CRLF into a single Character, so test for both forms.
                if c == "\n" || c == "\r\n" || c == "\r" { break }
                end = text.index(after: end)
            }
            // `end` sits on the newline (or end-of-text). `start..<end` excludes it,
            // so no CR trimming is needed.
            var lineText = String(text[start..<end])
            if lineText.hasSuffix("\r") { lineText.removeLast() }
            result.append(Line(text: lineText, range: start..<end))
            if end == text.endIndex { break }
            // Advance past the newline (LF, CRLF, or lone CR) — each is one Character
            // in Swift, so a single-step offset suffices.
            start = text.index(end, offsetBy: 1)
        }
        return result
    }

    /// Extracts metadata from an opening `---` block. Returns `nil` when there is no
    /// frontmatter or when the opening `---` has no matching closing `---` on its own
    /// line (so the text is treated as an ordinary Markdown body, never swallowed).
    static func extract(_ text: String) throws -> (NoteMetadata, String)? {
        let all = lines(in: text)
        // The document must open with a `---` (possibly after a UTF-8 BOM) on the first line.
        guard let first = all.first else { return nil }
        let firstTrimmed = first.text.trimmingCharacters(in: .whitespaces)
        let cleaned = firstTrimmed.hasPrefix("\u{FEFF}") ? String(firstTrimmed.dropFirst()) : firstTrimmed
        guard cleaned == "---" else { return nil }

        guard all.count >= 2 else { return nil }

        // Find the closing `---` line.
        guard
            let closeIndex = all.dropFirst().firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces) == "---" }
            )
        else {
            // No closing delimiter: do NOT consume the body. Treat whole text as body.
            return nil
        }

        var meta = NoteMetadata(id: UUID(), createdAt: Date(), updatedAt: Date(), tags: [])
        var seenID = false
        var extras: [String] = []

        let bodyStart: String.Index
        let lastManagedLine = all[closeIndex].range.upperBound
        if lastManagedLine < text.endIndex {
            bodyStart = text.index(after: lastManagedLine)  // after the "\n" that ended `---`
        } else {
            bodyStart = text.endIndex
        }

        // Parse managed metadata; everything else is preserved as an extra line.
        for line in all[1..<closeIndex] {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                extras.append(line.text)
                continue
            }
            guard let colon = line.text.firstIndex(of: ":") else {
                extras.append(line.text)
                continue
            }
            let key = line.text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line.text[line.text.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "id":
                if let uuid = UUID(uuidString: value) {
                    meta.id = uuid
                    seenID = true
                }
            case "created":
                if let date = parseDate(value) { meta.createdAt = date }
            case "updated":
                if let date = parseDate(value) { meta.updatedAt = date }
            case "tags":
                meta.tags = parseTags(value)
            default:
                extras.append(line.text)
            }
        }

        if !seenID { meta.id = UUID() }

        // Body is everything after the closing `---` line. Drop exactly one blank
        // separator line if present (matching our own `header + "\n\n" + body` layout),
        // but never trim the body's own content.
        var body = String(text[bodyStart...])
        if body.hasPrefix("\n") {
            body.removeFirst()
        }

        return (
            NoteMetadata(
                id: meta.id,
                createdAt: meta.createdAt,
                updatedAt: meta.updatedAt,
                tags: meta.tags,
                extraFields: extras
            ), body
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        // Prefer fractional seconds; fall back to whole-second ISO 8601.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: value)
    }

    /// Parses `tags` in either `[a, b]` inline or bare `a, b` form, tolerating quotes.
    /// Never falls back to naive first/last-character stripping.
    private static func parseTags(_ value: String) -> Set<Tag> {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let inner: String
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            inner = String(trimmed.dropFirst().dropLast())
        } else {
            inner = trimmed
        }

        // Split on commas that are not inside quotes.
        var parts: [String] = []
        var current = ""
        var inQuote: Character?
        for ch in inner {
            if let quote = inQuote {
                current.append(ch)
                if ch == quote { inQuote = nil }
            } else {
                if ch == "\"" || ch == "'" {
                    inQuote = ch
                    current.append(ch)
                } else if ch == "," {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
        }
        parts.append(current)

        return Set(
            parts
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "") }
                .map(Tag.init(name:))
                .filter { !$0.name.isEmpty }
        )
    }
}
