import Foundation
import SQLite3
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

    private func execute(_ sql: String, on database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchError.databaseUnavailable
        }
    }

    private func scalarText(at databaseURL: URL, sql: String) throws -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            let database
        else {
            if let database { sqlite3_close_v2(database) }
            throw SearchError.databaseUnavailable
        }
        defer { sqlite3_close_v2(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else {
            throw SearchError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
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

        let brown = try index.search("brown")
        #expect(brown.count == 2)

        let swift = try index.search("swift")
        #expect(swift.count >= 1)
        #expect(swift.contains { $0.noteID == a.id })
    }

    @Test("Ranks repeated matches and highlights snippets")
    func rankedHighlightedSearch() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let weak = note(UUID(), body: "# Needle\nA single match.")
        let strong = note(UUID(), body: "# Needle needle needle\nRepeated matches.")
        try index.rebuild(notes: [weak, strong])

        let results = try index.search("needle")

        #expect(results.map(\.noteID) == [strong.id, weak.id])
        #expect(results[0].score < results[1].score)
        #expect(results.allSatisfy { $0.score != 0 })
        #expect(results.allSatisfy { $0.snippet.contains("[Needle]") })
    }

    @Test("Finds Japanese substrings in titles and bodies")
    func japaneseSubstringSearch() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let titleMatch = note(UUID(), body: "# 京都旅行案内\n春の旅程です。")
        let bodyMatch = note(UUID(), body: "# Search notes\n日本語検索を改善します。")
        let unrelated = note(UUID(), body: "# Recipes\n夕食の献立です。")
        try index.rebuild(notes: [titleMatch, bodyMatch, unrelated])

        let titleResults = try index.search("都旅行")
        #expect(titleResults.contains { $0.noteID == titleMatch.id })
        #expect(!titleResults.contains { $0.noteID == unrelated.id })

        let bodyResults = try index.search("本語検")
        #expect(bodyResults.contains { $0.noteID == bodyMatch.id })
        #expect(!bodyResults.contains { $0.noteID == unrelated.id })
    }

    @Test("Finds one- and two-character Unicode queries")
    func shortUnicodeSearch() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let cat = note(UUID(), body: "# 動物\n黒猫と暮らす。")
        let search = note(UUID(), body: "# 技術\n検索機能を作る。")
        try index.rebuild(notes: [cat, search])

        #expect(try index.search("猫").contains { $0.noteID == cat.id })
        #expect(try index.search("検索").contains { $0.noteID == search.id })
    }

    @Test("Finds Latin substrings")
    func latinSubstringSearch() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let swift = note(UUID(), body: "Swift programming")
        let kotlin = note(UUID(), body: "Kotlin programming")
        try index.rebuild(notes: [swift, kotlin])

        let results = try index.search("ift")
        #expect(results.contains { $0.noteID == swift.id })
        #expect(!results.contains { $0.noteID == kotlin.id })
    }

    @Test("Treats LIKE wildcards as literal query text")
    func escapedLikeWildcards() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let percent = note(UUID(), body: "Progress is 100% complete")
        let underscore = note(UUID(), body: "literal_name")
        let plain = note(UUID(), body: "plain text")
        try index.rebuild(notes: [percent, underscore, plain])

        let percentResults = try index.search("%")
        #expect(percentResults.map(\.noteID) == [percent.id])

        let underscoreResults = try index.search("_")
        #expect(underscoreResults.map(\.noteID) == [underscore.id])
    }

    @Test("Filters by exact tag")
    func tagFilter() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "iOS development", tags: ["swift"])
        let b = note(UUID(), body: "Music production", tags: ["audio"])
        try index.upsert(note: a)
        try index.upsert(note: b)

        let result = try index.search("", tags: [Tag(name: "swift")])
        #expect(result.contains { $0.noteID == a.id })
        #expect(!result.contains { $0.noteID == b.id })
    }

    @Test("Deletes a note from the index")
    func delete() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "delete me please")
        try index.upsert(note: a)
        let before = try index.search("delete")
        #expect(!before.isEmpty)

        try index.delete(noteID: a.id)
        let after = try index.search("delete")
        #expect(after.isEmpty)
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
        #expect(try index.search("gamma").count == 1)
        #expect(try index.search("alpha").count == 1)
    }

    @Test("Empty query returns no results")
    func emptyQuery() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }
        try index.upsert(note: note(UUID(), body: "anything"))
        #expect(try index.search("   ").isEmpty)
        #expect(try index.search("").isEmpty)
    }

    @Test("Tag filtering is exact, not substring")
    func exactTag() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        let a = note(UUID(), body: "content", tags: ["swift-ui"])
        let b = note(UUID(), body: "content", tags: ["swift"])
        try index.upsert(note: a)
        try index.upsert(note: b)

        // Filtering for `swift` must not match `swift-ui`.
        let onlySwift = try index.search("", tags: [Tag(name: "swift")])
        #expect(onlySwift.contains { $0.noteID == b.id })
        #expect(!onlySwift.contains { $0.noteID == a.id })

        let onlyFramework = try index.search("", tags: [Tag(name: "swift-ui")])
        #expect(onlyFramework.contains { $0.noteID == a.id })
    }

    @Test("Deleted notes are excluded from the index")
    func deletedExcluded() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }

        var deleted = note(UUID(), body: "private secret")
        deleted.isDeleted = true
        try index.upsert(note: deleted)
        #expect(try index.search("secret").isEmpty)
    }

    @Test("Body-only matches produce a body snippet, not an empty one")
    func bodySnippet() throws {
        let (index, cleanup) = try makeIndex()
        defer { cleanup() }
        // No heading: the match lives in the body, so the snippet must come from the body
        // column (2), not the title column.
        let n = note(UUID(), body: "A long paragraph about habitat fragmentation and こんにちは.")
        try index.upsert(note: n)

        let ja = try index.search("こんにちは")
        #expect(ja.contains { $0.noteID == n.id })
        if let hit = ja.first(where: { $0.noteID == n.id }) {
            #expect(hit.snippet.contains("こんにちは"), "Expected a body snippet, got '\(hit.snippet)'")
        }

        let en = try index.search("fragmentation")
        if let hit = en.first(where: { $0.noteID == n.id }) {
            #expect(hit.snippet.contains("fragmentation"))
        }
    }

    @Test("Migrates an existing unicode61 index")
    func legacyDatabaseMigration() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-search-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let databaseURL = dir.appendingPathComponent("search.db")
        let noteID = UUID()

        do {
            var legacyDatabase: OpaquePointer?
            guard sqlite3_open(databaseURL.path, &legacyDatabase) == SQLITE_OK, let legacyDatabase else {
                if let legacyDatabase { sqlite3_close_v2(legacyDatabase) }
                throw SearchError.databaseUnavailable
            }
            defer { sqlite3_close_v2(legacyDatabase) }
            try execute(
                "CREATE VIRTUAL TABLE notes_fts USING fts5(noteID UNINDEXED, title, body, tokenize = 'unicode61');",
                on: legacyDatabase)
            try execute(
                "CREATE TABLE note_tags (noteID TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY(noteID, tag));",
                on: legacyDatabase)
            try execute(
                "INSERT INTO notes_fts(noteID, title, body) VALUES ('\(noteID.uuidString)', 'Legacy', '移行前の保存データ');",
                on: legacyDatabase)
        }

        let index = try NoteSearchIndex(databaseURL: databaseURL)
        #expect(try index.search("保存デ").contains { $0.noteID == noteID })

        let ftsSchema = try scalarText(
            at: databaseURL,
            sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes_fts';")
        #expect(ftsSchema?.lowercased().contains("unicode61") != true)
        #expect(try scalarText(at: databaseURL, sql: "PRAGMA user_version;") == "1")
    }
}
