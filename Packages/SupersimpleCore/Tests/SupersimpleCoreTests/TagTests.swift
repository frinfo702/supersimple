import Foundation
import Testing

@testable import SupersimpleCore

@Suite("Tag normalization and extraction")
struct TagTests {

    @Test("Normalizes case and strips whitespace")
    func normalize() {
        #expect(Tag(name: "  Swift ").name == "swift")
        #expect(Tag(name: "Swift").name == "swift")
        #expect(TagNormalizer.normalize(" Swift ") == "swift")
    }

    @Test("Extracts inline tags from body")
    func extractTags() {
        let body = """
            # Project Notes
            Work on #swift and #obsidian-plugin, plus #multi-word.
            """
        let tags = TagNormalizer.extractTags(from: body)
        #expect(tags.contains(Tag(name: "swift")))
        #expect(tags.contains(Tag(name: "obsidian-plugin")))
        #expect(tags.contains(Tag(name: "multi-word")))
    }

    @Test("Ignores heading markers and empty tokens")
    func headingNotTag() {
        let body = "# Heading\nA lone # is not a tag."
        let tags = TagNormalizer.extractTags(from: body)
        #expect(tags.isEmpty)
    }
}
