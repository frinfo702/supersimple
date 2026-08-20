import CryptoKit
import Foundation

public enum SaveResult: Equatable, Sendable {
    case written(FileRecord)
    /// The file on disk changed since the caller wrote/reloaded it. The caller's edit was
    /// NOT written; it must reconcile before retrying.
    case conflict(Acquired, FileRecord)

    public struct Acquired: Equatable, Sendable {
        public let id: UUID
        public let body: String
        public init(id: UUID, body: String) {
            self.id = id
            self.body = body
        }
    }
}

public enum RepositoryError: Error, Sendable {
    case unavailable(underlying: String)
    case notFound(UUID)
    case conflict(UUID)
    case invalidAttachmentPath
    case saveFailed(underlying: String)
}

/// Result of a load: the content, or a description of why it could not be produced.
public enum LoadResult: Sendable {
    case content(NoteContent)
    case notFound
    case unreadable
    case invalid(noteID: String?)
}

/// Thread-safe, file-first access to a `LibraryLayout`. Routes all source-of-truth I/O
/// through atomic, revision-aware writes so concurrent editors, iCloud sync, and a second
/// app instance cannot silently overwrite each other.
actor NoteRepository {
    private let layout: LibraryLayout
    private let fileManager: NoteFileManager

    public init(root: URL, fileManager: NoteFileManager = NoteFileManager()) {
        self.layout = LibraryLayout(root: root)
        self.fileManager = fileManager
    }

    public init(layout: LibraryLayout, fileManager: NoteFileManager = NoteFileManager()) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func createLayout() throws {
        try layout.createIfNeeded()
    }

    // MARK: - Reading

    /// Enumerates notes, decoding only enough to build summaries. Returns `nil` when the
    /// directory is unavailable so the caller can distinguish "empty" from "broken".
    public func listSummaries() throws -> [NoteSummary]? {
        let urls: [URL]
        do {
            urls = try fileManager.enumerateNoteURLs(in: layout.notesDirectory)
        } catch {
            throw RepositoryError.unavailable(underlying: String(describing: error))
        }
        var summaries: [NoteSummary] = []
        // Keep the last-write-wins so duplicate IDs do not crash the consuming code.
        var byID: [UUID: NoteSummary] = [:]
        for url in urls {
            guard let text = try? fileManager.read(at: url),
                let doc = try? FrontmatterCodec.decode(text)
            else { continue }
            let record = fileManager.fileRecord(at: url)
            let summary = NoteSummary(doc: doc, fileURL: url, fileRecord: record)
            byID[doc.metadata.id] = summary
        }
        summaries = Array(byID.values)
        summaries.sort { $0.updatedAt > $1.updatedAt }
        return summaries
    }

    public func load(id: UUID) -> LoadResult {
        let url = layout.noteURL(for: id)
        guard let text = try? fileManager.read(at: url) else {
            return fileManager.fileExists(at: url) ? .unreadable : .notFound
        }
        guard let doc = try? FrontmatterCodec.decode(text) else {
            return .invalid(noteID: id.uuidString)
        }
        let record = fileManager.fileRecord(at: url)
        let summary = NoteSummary(doc: doc, fileURL: url, fileRecord: record)
        return .content(NoteContent(summary: summary, body: doc.body))
    }

    /// Reads a `.md`/attachment by name from the attachments directory.
    public func attachmentURL(named name: String) -> URL? {
        guard Self.isSafeAttachmentName(name) else { return nil }
        return layout.attachmentsDirectory.appendingPathComponent(name, isDirectory: false)
    }

    public static func isSafeAttachmentName(_ name: String) -> Bool {
        let cleaned = (name as NSString).lastPathComponent
        guard cleaned == name, !name.isEmpty else { return false }
        return !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\")
            && !name.components(separatedBy: "/").contains("..")
    }

    // MARK: - Writing

    /// Saves `body` for `id` with an optional expected revision. When `expected` matches
    /// the file on disk (or the file is absent), the write succeeds atomically and
    /// `.written` is returned. When the file changed underneath, `.conflict` is returned
    /// and nothing is overwritten. Disk failures propagate as errors so callers can retry.
    public func save(id: UUID, body: String, expected: FileRecord?) throws -> SaveResult {
        let now = Date()
        let doc = MarkdownDocument(
            metadata: NoteMetadata(
                id: id,
                createdAt: now,
                updatedAt: now,
                tags: TagNormalizer.extractTags(from: body)
            ),
            body: body
        )
        return try save(aquired: SaveResult.Acquired(id: id, body: body), doc: doc, expected: expected)
    }

    private func save(aquired: SaveResult.Acquired, doc: MarkdownDocument, expected: FileRecord?) throws -> SaveResult {
        let url = layout.noteURL(for: aquired.id)
        let current = fileManager.fileRecord(at: url)
        if let expected, !NoteFileManager.contentsMatch(current, expected) {
            // File changed under us — record the intended write so the caller can reconcile
            // without touching the on-disk content.
            let onDisk = current ?? FileRecord(url: url, fileSize: 0, modificationDate: Date(), contentHash: "")
            return .conflict(aquired, onDisk)
        }
        do {
            try fileManager.write(doc.fullText, to: url)
        } catch {
            throw RepositoryError.saveFailed(underlying: String(describing: error))
        }
        let landed =
            fileManager.fileRecord(at: url)
            ?? FileRecord(url: url, fileSize: 0, modificationDate: Date(), contentHash: "")
        return .written(landed)
    }

    /// Writes a fresh note (new id) and returns the landed record. Throws on disk failure.
    @discardableResult
    public func write(id: UUID, body: String) throws -> FileRecord {
        let now = Date()
        let doc = MarkdownDocument(
            metadata: NoteMetadata(
                id: id,
                createdAt: now,
                updatedAt: now,
                tags: TagNormalizer.extractTags(from: body)
            ),
            body: body
        )
        let url = layout.noteURL(for: id)
        try fileManager.write(doc.fullText, to: url)
        return fileManager.fileRecord(at: url)
            ?? FileRecord(url: url, fileSize: 0, modificationDate: Date(), contentHash: "")
    }

    // MARK: - Deletion / trash

    /// Moves a note into the library's hidden Trash so accidental deletion is recoverable.
    public func delete(id: UUID) -> Bool {
        let url = layout.noteURL(for: id)
        guard fileManager.fileExists(at: url) else { return false }
        do {
            try layout.createIfNeeded()
            let trashURL = layout.trashDirectory
                .appendingPathComponent("\(id.uuidString)-\(Int(Date().timeIntervalSince1970)).md", isDirectory: false)
            try FileManager.default.moveItem(at: url, to: trashURL)
            return true
        } catch {
            return false
        }
    }

    public func fileExists(id: UUID) -> Bool {
        fileManager.fileExists(at: layout.noteURL(for: id))
    }
}
