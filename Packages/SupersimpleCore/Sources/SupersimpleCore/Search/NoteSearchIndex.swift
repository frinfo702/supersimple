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
/// Documents are indexed title + body with FTS5 (BM25-ranked). Tags live in a
/// separate plain table with exact-equality semantics, because FTS5 tokenization
/// (which splits on `-`) cannot express "exactly this tag". The index is a derived
/// cache that can always be rebuilt from the `.md` files on disk.
public final class NoteSearchIndex: @unchecked Sendable {

    private let lock = NSLock()
    private var database: OpaquePointer?

    /// Holds a destructor that tells SQLite to copy the bound text (transient binding).
    private let transientDestructor: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        // SQLite may return a handle even on failure; it must be closed.
        guard status == SQLITE_OK, let db else {
            if let db { sqlite3_close_v2(db) }
            throw SearchError.databaseUnavailable
        }
        database = db
        try execute("PRAGMA journal_mode=WAL;")
        try execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(noteID UNINDEXED, title, body, tokenize = 'unicode61');"
        )
        try execute(
            "CREATE TABLE IF NOT EXISTS note_tags (noteID TEXT NOT NULL, tag TEXT NOT NULL, PRIMARY KEY(noteID, tag));"
        )
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    // MARK: - Mutation

    public func upsert(note: Note) throws {
        try withTransaction {
            // Deleted notes are removed from the index entirely.
            try deleteRow(noteID: note.id)
            guard !note.isDeleted else { return }
            try execute(
                "INSERT INTO notes_fts(noteID, title, body) VALUES (?, ?, ?)",
                arguments: [note.id.uuidString, note.title, note.body])
            for tag in note.tags {
                try execute(
                    "INSERT OR REPLACE INTO note_tags(noteID, tag) VALUES (?, ?)",
                    arguments: [note.id.uuidString, tag.name])
            }
        }
    }

    public func delete(noteID: UUID) throws {
        try withTransaction {
            try deleteRow(noteID: noteID)
        }
    }

    /// Rebuilds the index from a list of notes atomically. Safe to call on an existing
    /// index; searches never observe a partially rebuilt state.
    public func rebuild(notes: [Note]) throws {
        try withTransaction {
            try execute("DELETE FROM notes_fts;")
            try execute("DELETE FROM note_tags;")
            for note in notes where !note.isDeleted {
                try execute(
                    "INSERT INTO notes_fts(noteID, title, body) VALUES (?, ?, ?)",
                    arguments: [note.id.uuidString, note.title, note.body])
                for tag in note.tags {
                    try execute(
                        "INSERT OR REPLACE INTO note_tags(noteID, tag) VALUES (?, ?)",
                        arguments: [note.id.uuidString, tag.name])
                }
            }
        }
    }

    private func deleteRow(noteID: UUID) throws {
        try execute("DELETE FROM notes_fts WHERE noteID = ?", arguments: [noteID.uuidString])
        try execute("DELETE FROM note_tags WHERE noteID = ?", arguments: [noteID.uuidString])
    }

    // MARK: - Query

    public func search(
        _ rawQuery: String,
        tags: Set<Tag> = [],
        limit: Int = 100
    ) throws -> [SearchResult] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !tags.isEmpty else { return [] }

        // Tag-only search: query the exact tag table directly (no FTS MATCH, so
        // bm25/snippet are unavailable and must not be referenced).
        if trimmed.isEmpty {
            return try queryByTags(tags, limit: limit)
        }

        var conditions: [String] = []
        var args: [String] = []
        conditions.append("noteID IN (SELECT noteID FROM notes_fts WHERE notes_fts MATCH ?)")
        args.append(quote(phrase(matching: trimmed)))

        for tag in tags.sorted() {
            conditions.append("noteID IN (SELECT noteID FROM note_tags WHERE tag = ?)")
            args.append(tag.name)
        }

        let sql = """
            SELECT noteID, title, snippet(notes_fts, 1, '[', ']', '…', 24) AS snip, bm25(notes_fts) AS score
            FROM notes_fts
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY score LIMIT ?
            """
        args.append(String(limit))
        return try queryRows(sql: sql, arguments: args)
    }

    /// Exact-tag lookup with no full-text component. Orders by note title for stability.
    private func queryByTags(_ tags: Set<Tag>, limit: Int) throws -> [SearchResult] {
        guard !tags.isEmpty else { return [] }
        var sql = """
            SELECT DISTINCT t.noteID, n.title
            FROM note_tags t
            JOIN notes_fts n ON n.noteID = t.noteID
            WHERE \(tags.sorted().map { _ in "t.noteID IN (SELECT noteID FROM note_tags WHERE tag = ?)" }.joined(separator: " AND "))
            ORDER BY n.title
            LIMIT ?
            """
        var args = tags.sorted().map(\.name)
        args.append(String(limit))

        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else { throw SearchError.databaseUnavailable }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in args.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, transientDestructor)
        }
        var rows: [SearchResult] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                guard
                    let idText = columnText(statement, index: 0),
                    let noteID = UUID(uuidString: idText),
                    let title = columnText(statement, index: 1)
                else { continue }
                rows.append(SearchResult(noteID: noteID, title: title, snippet: "", score: 0, matchTags: []))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SearchError.databaseUnavailable
            }
        }
        return rows
    }

    // MARK: - Private helpers

    /// Wraps a user phrase so FTS5 treats it as a single quoted term.
    private func phrase(matching term: String) -> String {
        term.replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func queryRows(sql: String, arguments: [String]) throws -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw SearchError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }

        for (index, arg) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, transientDestructor)
        }

        var result: [SearchResult] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                guard
                    let idText = columnText(statement, index: 0),
                    let noteID = UUID(uuidString: idText),
                    let title = columnText(statement, index: 1)
                else { continue }
                let snippet = columnText(statement, index: 2) ?? ""
                let score = sqlite3_column_double(statement, 3)
                result.append(
                    SearchResult(noteID: noteID, title: title, snippet: snippet, score: score, matchTags: [])
                )
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SearchError.databaseUnavailable
            }
        }
        return result.sorted { $0.score < $1.score }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    /// Runs `body` inside a wrapped transaction, holding the lock across BEGIN..COMMIT
    /// so concurrent callers cannot interleave and produce duplicate/partial rows.
    private func withTransaction(_ body: () throws -> Void) rethrows {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_exec(database, "BEGIN;", nil, nil, nil)
        defer { sqlite3_exec(database, "COMMIT;", nil, nil, nil) }
        try body()
    }

    /// Executes a single (already-wrapped or single-statement) statement with optional args.
    private func execute(_ sql: String, arguments: [String] = []) throws {
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
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SearchError.databaseUnavailable
        }
    }
}

extension Set where Element == Tag {
    /// A space-separated list of tag names for index rebuild fallbacks.
    var joinedNames: String {
        sorted().map(\.name).joined(separator: " ")
    }
}
