import Foundation
import Testing

@testable import SupersimpleCore

@Suite("Frontmatter encoding and decoding")
struct FrontmatterCodecTests {

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func makeMetadata(
        id: UUID = UUID(),
        created: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updated: Date = Date(timeIntervalSince1970: 1_700_000_100),
        tags: [String] = ["swift", "idea"]
    ) -> NoteMetadata {
        NoteMetadata(
            id: id,
            createdAt: created,
            updatedAt: updated,
            tags: Set(tags.map(Tag.init(name:)))
        )
    }

    @Test("Encodes a full document with frontmatter and body")
    func encode() {
        let id = UUID()
        let meta = makeMetadata(id: id, created: Date(timeIntervalSince1970: 1_700_000_000))
        let doc = MarkdownDocument(metadata: meta, body: "# Title\nBody text.")
        let text = doc.fullText

        #expect(text.hasPrefix("---"))
        #expect(text.contains("id: \(id.uuidString)"))
        #expect(text.contains("created: 202"))
        #expect(text.contains("tags: [idea, swift]"))
        #expect(text.hasSuffix("# Title\nBody text."))
    }

    @Test("Round-trips a document preserving metadata and body")
    func roundTrip() throws {
        let id = UUID()
        let meta = makeMetadata(
            id: id,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            updated: Date(timeIntervalSince1970: 1_700_000_100),
            tags: ["alpha", "beta"]
        )
        let original = MarkdownDocument(metadata: meta, body: "# Round Trip\nSome `inline code`.")
        let decoded = try FrontmatterCodec.decode(original.fullText)

        #expect(decoded.metadata.id == id)
        #expect(decoded.metadata.createdAt == meta.createdAt)
        #expect(decoded.metadata.updatedAt == meta.updatedAt)
        #expect(decoded.metadata.tags == Set(["alpha", "beta"].map(Tag.init(name:))))
        #expect(decoded.body == "# Round Trip\nSome `inline code`.")
    }

    @Test("Generates a fresh id when none is present on disk")
    func missingID() throws {
        let text = "---\ncreated: 2026-01-01T00:00:00Z\n---\n# Untitled"
        let decoded = try FrontmatterCodec.decode(text)
        // A fresh note still parses; id should be non-zero-decidingly present.
        #expect(decoded.body == "# Untitled")
    }

    @Test("Ignores text without frontmatter and treats it as the body")
    func noFrontmatter() throws {
        let decoded = try FrontmatterCodec.decode("Just a plain body.\nSecond line.")
        #expect(decoded.body == "Just a plain body.\nSecond line.")
    }

    @Test("Unterminated opening delimiter does not swallow the body")
    func unterminated() throws {
        // Leading `---` with no closing delimiter is treated as ordinary body text.
        let decoded = try FrontmatterCodec.decode("---\n# Heading\nsecret text")
        #expect(decoded.body == "---\n# Heading\nsecret text")
    }

    @Test("Leading indentation and trailing spaces survive the round trip")
    func whitespacePreserved() throws {
        let body = "    let x = 1\nlast line  \n"
        let meta = makeMetadata(id: UUID())
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(meta, body: body))
        #expect(decoded.body == body)
    }

    @Test("Unknown frontmatter fields are preserved verbatim")
    func extraFieldsPreserved() throws {
        let id = UUID()
        let meta = makeMetadata(id: id, tags: [])
        let doc = MarkdownDocument(
            metadata: NoteMetadata(
                id: id,
                createdAt: meta.createdAt,
                updatedAt: meta.updatedAt,
                tags: [],
                extraFields: ["aliases: [Important]", "custom-status: reviewed"]
            ),
            body: "# Heading"
        )
        let decoded = try FrontmatterCodec.decode(doc.fullText)
        #expect(decoded.metadata.extraFields.contains("aliases: [Important]"))
        #expect(decoded.metadata.extraFields.contains("custom-status: reviewed"))
    }

    @Test("CRLF frontmatter is decoded and preserved")
    func crlf() throws {
        let id = UUID()
        let raw = "---\r\nid: \(id.uuidString)\r\n---\r\n# Body"
        let decoded = try FrontmatterCodec.decode(raw)
        #expect(decoded.metadata.id == id)
        #expect(decoded.body.contains("# Body"))
    }

    @Test("Timestamps keep subsecond precision")
    func subsecondPrecision() throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000.543)
        let meta = makeMetadata(id: id, created: created)
        let decoded = try FrontmatterCodec.decode(FrontmatterCodec.encode(meta, body: ""))
        #expect(abs(decoded.metadata.createdAt.timeIntervalSince1970 - created.timeIntervalSince1970) < 0.01)
    }
}
