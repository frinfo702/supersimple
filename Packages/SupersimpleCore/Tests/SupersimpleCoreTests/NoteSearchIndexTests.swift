import Foundation
import Testing

@testable import SupersimpleCore

@Suite("FTS5 full-text search")
struct NoteSearchIndexTests {

    private func makeIndex() throws -> (index: NoteSearchIndex, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-search-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("search.db")
        let index = try NoteSearchIndex(databaseURL: dbURL)
        return (index, { try? FileManager.default.removeItem(at: dir) })
    }

    private func note(_ id: UUID, body: String, tags: [String] = []) -> Note {
        Note(
            id: id,
            createdAt: Date(),
            updatedAt: Date(),
            tags: Set(tags.map(Tag.init(name:))),
            body: body
        )
    }

    @Test("Indexes and finds notes with ranking")
    func basicSearch() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "# Swift Notes\nThe quick brown fox.", tags: ["swift"])
        let b = note(UUID(), body: "# Recipes\nA tasty brown sauce.", tags: ["cooking"])
        let c = note(UUID(), body: "Lorem ipsum dolor.")

        try index.upsert(note: a)
        try index.upsert(note: b)
        try index.upsert(note: c)

        let brown = index.search("brown")
        #expect(brown.count == 2)

        let swift = index.search("swift")
        #expect(swift.count >= 1)
        #expect(swift.contains { $0.noteID == a.id })
    }

    @Test("Filters by exact tag")
    func tagFilter() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "iOS development", tags: ["swift"])
        let b = note(UUID(), body: "Music production", tags: ["audio"])
        try index.upsert(note: a)
        try index.upsert(note: b)

        let result = index.search("", tags: [Tag(name: "swift")])
        #expect(result.contains { $0.noteID == a.id })
        #expect(!result.contains { $0.noteID == b.id })
    }

    @Test("Deletes a note from the index")
    func delete() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "delete me please")
        try index.upsert(note: a)
        #expect(!index.search("delete").isEmpty)

        try index.delete(noteID: a.id)
        #expect(index.search("delete").isEmpty)
    }

    @Test("Rebuilds the index from a list of notes")
    func rebuild() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "alpha content")
        let b = note(UUID(), body: "beta content")
        try index.upsert(note: a)
        try index.upsert(note: b)

        let c = note(UUID(), body: "gamma content")
        try index.rebuild(notes: [a, b, c])
        #expect(index.search("gamma").count == 1)
        #expect(index.search("alpha").count == 1)
    }

    @Test("Empty query returns no results")
    func emptyQuery() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }
        try index.upsert(note: note(UUID(), body: "anything"))
        #expect(index.search("   ").isEmpty)
        #expect(index.search("").isEmpty)
    }
}
