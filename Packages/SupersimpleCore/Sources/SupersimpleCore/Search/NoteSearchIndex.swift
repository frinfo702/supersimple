import Foundation
import SQLite3

public struct SearchResult: Equatable, Sendable, Identifiable {
    public let noteID: UUID
    public let title: String
    public let snippet: String
    public let score: Double
    public let matchTags: Set<Tag>

    public var id: UUID { noteID }
}

public enum SearchError: Error, Sendable, Equatable {
    case databaseUnavailable
}

/// Full-text index built on SQLite FTS5, backed by the system-provided SQLite.
///
/// Documents are indexed title + tags + raw body and ranked with BM25. The index is
/// a derived cache that can always be rebuilt from the `.md` files on disk.
public final class NoteSearchIndex: @unchecked Sendable {

    private let lock = NSLock()
    private var database: OpaquePointer?

    /// Holds a destructor that tells SQLite to copy the bound text (transient binding).
    private let transientDestructor: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            throw SearchError.databaseUnavailable
        }
        database = db
        try execute("PRAGMA journal_mode=WAL;")
        try execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(noteID UNINDEXED, title, tags, body, tokenize = 'unicode61');"
        )
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    // MARK: - Mutation

    public func upsert(note: Note) throws {
        // FTS5 has no unique constraint on a plain (UNINDEXED) content column, so an
        // UPSERT is invalid. Delete-then-insert keeps the index free of duplicates.
        try execute("DELETE FROM notes_fts WHERE noteID = ?", arguments: [note.id.uuidString])
        let sql = "INSERT INTO notes_fts(noteID, title, tags, body) VALUES (?, ?, ?, ?)"
        try execute(sql, arguments: [note.id.uuidString, note.title, note.tags.joinedNames, note.body])
    }

    public func delete(noteID: UUID) throws {
        try execute("DELETE FROM notes_fts WHERE noteID = ?", arguments: [noteID.uuidString])
    }

    /// Rebuilds the index from a list of notes. Safe to call on an existing index.
    public func rebuild(notes: [Note]) throws {
        try execute("DELETE FROM notes_fts;")
        for note in notes where !note.isDeleted {
            try upsert(note: note)
        }
    }

    // MARK: - Query

    public func search(
        _ rawQuery: String,
        tags: Set<Tag> = [],
        limit: Int = 100
    ) -> [SearchResult] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !tags.isEmpty else { return [] }

        var matchTerms: [String] = []
        if !trimmed.isEmpty {
            matchTerms.append(quote(phrase(matching: trimmed)))
        }
        if !tags.isEmpty {
            let tagTerms = tags.sorted().map { quote($0.name) }.joined(separator: " ")
            matchTerms.append("tags:(" + tagTerms + ")")
        }
        let matchExpression = matchTerms.joined(separator: " AND ")

        var sql = """
            SELECT noteID, title, tags, snippet(notes_fts, 3, '[', ']', '…', 24) AS snip, bm25(notes_fts) AS score
            FROM notes_fts
            WHERE notes_fts MATCH ?
            """
        var args: [String] = [matchExpression]
        if !tags.isEmpty {
            sql += " AND tags MATCH ?"
            args.append(quote(tags.sorted().map(\.name).joined(separator: " ")))
        }
        sql += " ORDER BY score LIMIT ?"
        args.append(String(limit))

        return queryRows(sql: sql, arguments: args)
    }

    // MARK: - Private helpers

    /// Wraps a user phrase so FTS5 treats it as a single quoted term.
    private func phrase(matching term: String) -> String {
        let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped
    }

    private func quote(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\""
    }

    private func queryRows(sql: String, arguments: [String]) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        var result: [SearchResult] = []

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (index, arg) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, transientDestructor)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idText = columnText(statement, index: 0),
                let noteID = UUID(uuidString: idText),
                let title = columnText(statement, index: 1)
            else { continue }
            let snippet = columnText(statement, index: 3) ?? ""
            let score = sqlite3_column_double(statement, 4)
            let tags = parseTags(columnText(statement, index: 2) ?? "")
            result.append(
                SearchResult(noteID: noteID, title: title, snippet: snippet, score: score, matchTags: tags)
            )
        }
        return result.sorted { $0.score < $1.score }
    }

    private func parseTags(_ text: String) -> Set<Tag> {
        Set(text.split(separator: " ").map { Tag(name: String($0)) })
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func execute(_ sql: String, arguments: [String] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw SearchError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, transientDestructor)
        }
        let rc = sqlite3_step(statement)
        // SQLITE_ROW (a pragma or query returned a row) and SQLITE_DONE are both fine.
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SearchError.databaseUnavailable
        }
    }
}

extension Set where Element == Tag {
    /// A space-separated list of tag names for indexing.
    var joinedNames: String {
        sorted().map(\.name).joined(separator: " ")
    }
}
