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

    public init(id: UUID, createdAt: Date, updatedAt: Date, tags: Set<Tag>) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }
}

/// Encodes and decodes note metadata as an Obsidian-style YAML frontmatter block.
///
/// Layout on disk:
/// ```text
/// ---
/// id: 8B31...
/// created: 2026-08-17T10:00:00Z
/// updated: 2026-08-17T10:05:00Z
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
        lines.append("created: \(ISO8601DateFormatter().string(from: metadata.createdAt))")
        lines.append("updated: \(ISO8601DateFormatter().string(from: metadata.updatedAt))")

        let sortedTags = metadata.tags.sorted().map(\.name)
        if !sortedTags.isEmpty {
            lines.append("tags: [\(sortedTags.joined(separator: ", "))]")
        }

        lines.append("---")
        let header = lines.joined(separator: "\n")
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? header : header + "\n\n" + trimmed
    }

    // MARK: - Decoding

    public static func decode(_ text: String) throws -> MarkdownDocument {
        var body = text
        var metadata: NoteMetadata?

        if FrontmatterDecoder.detect(text) {
            if let (meta, rest) = try FrontmatterDecoder.extract(text) {
                metadata = meta
                body = rest
            }
        }

        let resolved =
            metadata
            ?? {
                let now = Date()
                return NoteMetadata(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    tags: []
                )
            }()

        let normalizedBody = String(body.trimmingCharacters(in: .whitespacesAndNewlines))
        return MarkdownDocument(metadata: resolved, body: normalizedBody)
    }

    /// Parses from a raw `Note` plus the original document text, detached from the file system.
    public static func document(note: Note) -> MarkdownDocument {
        MarkdownDocument(
            metadata: .init(
                id: note.id,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags
            ),
            body: note.body
        )
    }
}

// MARK: - YAML frontmatter parsing

private enum FrontmatterDecoder {
    /// A document has frontmatter if it opens with a `---` line.
    static func detect(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return false }
        return first.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// Extracts metadata from the opening `---` block. Returns `nil` when no frontmatter
    /// exists or when the block is malformed; a partially-readable metadata is preferred
    /// over throwing so a corrupt file still opens.
    static func extract(_ text: String) throws -> (NoteMetadata, String)? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines.removeFirst()

        var index = 0
        var meta = NoteMetadata(id: UUID(), createdAt: Date(), updatedAt: Date(), tags: [])
        var seenID = false

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line == "---" {
                break
            }
            guard !line.isEmpty else { continue }

            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...]
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
                    break
                }
            }
        }

        let bodyLines = lines.dropFirst(index)
        let body = bodyLines.joined(separator: "\n")

        // If no `id:` was present, the note is new on disk; generate one.
        if !seenID {
            meta.id = UUID()
        }
        return (meta, body)
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func parseTags(_ value: String) -> Set<Tag> {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let inner = trimmed.dropFirst().dropLast()  // drop [ ]
        let parts = inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return Set(parts.filter { !$0.isEmpty }.map(Tag.init(name:)))
    }
}
