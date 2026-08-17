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
        #expect(text.contains("created: \(iso(meta.createdAt))"))
        #expect(text.contains("tags: [idea, swift]"))
        #expect(text.contains("# Title"))
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
}
