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
    case invalidNotePath
    case invalidAttachmentPath
    case saveFailed(underlying: String)
}

/// A recoverable move from the notes directory into the library trash.
public struct TrashedNoteFile: Equatable, Sendable {
    public let originalURL: URL
    public let trashURL: URL

    public init(originalURL: URL, trashURL: URL) {
        self.originalURL = originalURL
        self.trashURL = trashURL
    }
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
public final class NoteRepository: @unchecked Sendable {
    private let layout: LibraryLayout
    private let fileManager: NoteFileManager
    private let lock = NSRecursiveLock()

    public init(root: URL, fileManager: NoteFileManager = NoteFileManager()) {
        self.layout = LibraryLayout(root: root)
        self.fileManager = fileManager
    }

    public init(layout: LibraryLayout, fileManager: NoteFileManager = NoteFileManager()) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func createLayout() throws {
        lock.lock()
        defer { lock.unlock() }
        try layout.createIfNeeded()
    }

    // MARK: - Reading

    /// Enumerates notes, decoding only enough to build summaries. Returns `nil` when the
    /// directory is unavailable so the caller can distinguish "empty" from "broken".
    public func listSummaries() throws -> [NoteSummary]? {
        lock.lock()
        defer { lock.unlock() }
        let urls: [URL]
        do {
            urls = try fileManager.enumerateNoteURLs(in: layout.notesDirectory)
        } catch {
            throw RepositoryError.unavailable(underlying: String(describing: error))
        }
        var summaries: [NoteSummary] = []
        // Keep the newest revision so duplicate IDs do not crash the consuming code or
        // surface a stale copy based on filesystem enumeration order.
        var byID: [UUID: NoteSummary] = [:]
        for url in urls {
            guard let text = try? fileManager.read(at: url),
                let doc = try? FrontmatterCodec.decode(text)
            else { continue }
            let record = fileManager.fileRecord(at: url)
            let summary = NoteSummary(doc: doc, fileURL: url, fileRecord: record)
            if let existing = byID[doc.metadata.id], existing.updatedAt >= summary.updatedAt {
                continue
            }
            byID[doc.metadata.id] = summary
        }
        summaries = Array(byID.values)
        summaries.sort { $0.updatedAt > $1.updatedAt }
        return summaries
    }

    public func load(id: UUID) -> LoadResult {
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        defer { lock.unlock() }

        let url = saveURL(for: id, expected: expected)
        let current = fileManager.fileRecord(at: url)
        if !revisionAllowsWrite(
            current: current,
            expected: expected,
            fileExists: fileManager.fileExists(at: url)
        ) {
            return conflictResult(id: id, body: body, url: url, current: current)
        }

        let now = Date()
        let existingMetadata: NoteMetadata? = {
            guard let text = try? fileManager.read(at: url),
                let document = try? FrontmatterCodec.decode(text)
            else { return nil }
            return document.metadata
        }()
        let doc = MarkdownDocument(
            metadata: NoteMetadata(
                id: id,
                createdAt: existingMetadata?.createdAt ?? now,
                updatedAt: now,
                tags: TagNormalizer.extractTags(from: body),
                extraFields: existingMetadata?.extraFields ?? []
            ),
            body: body
        )
        return try write(
            acquired: SaveResult.Acquired(id: id, body: body),
            document: doc,
            to: url
        )
    }

    /// Saves a complete note while preserving its creation date and unmanaged frontmatter.
    public func save(note: Note, expected: FileRecord?) throws -> SaveResult {
        lock.lock()
        defer { lock.unlock() }

        let url = saveURL(for: note.id, expected: expected)
        let current = fileManager.fileRecord(at: url)
        if !revisionAllowsWrite(
            current: current,
            expected: expected,
            fileExists: fileManager.fileExists(at: url)
        ) {
            return conflictResult(id: note.id, body: note.body, url: url, current: current)
        }
        return try write(
            acquired: SaveResult.Acquired(id: note.id, body: note.body),
            document: FrontmatterCodec.document(note: note),
            to: url
        )
    }

    private func write(
        acquired: SaveResult.Acquired,
        document: MarkdownDocument,
        to url: URL
    ) throws -> SaveResult {
        do {
            try fileManager.write(document.fullText, to: url)
        } catch {
            throw RepositoryError.saveFailed(underlying: String(describing: error))
        }
        let landed =
            fileManager.fileRecord(at: url)
            ?? FileRecord(url: url, fileSize: 0, modificationDate: Date(), contentHash: "")
        return .written(landed)
    }

    private func revisionAllowsWrite(
        current: FileRecord?,
        expected: FileRecord?,
        fileExists: Bool
    ) -> Bool {
        if let expected {
            return NoteFileManager.contentsMatch(current, expected)
        }
        // A missing expected revision means the caller is creating a new note. Never
        // overwrite an existing file merely because the caller has no baseline record.
        return !fileExists
    }

    private func conflictResult(
        id: UUID,
        body: String,
        url: URL,
        current: FileRecord?
    ) -> SaveResult {
        let onDisk =
            current
            ?? FileRecord(
                url: url,
                fileSize: 0,
                modificationDate: Date(),
                contentHash: ""
            )
        return .conflict(SaveResult.Acquired(id: id, body: body), onDisk)
    }

    private func saveURL(for id: UUID, expected: FileRecord?) -> URL {
        guard let expected else { return layout.noteURL(for: id) }
        let expectedParent = expected.url.deletingLastPathComponent().standardizedFileURL
        if expectedParent == layout.notesDirectory.standardizedFileURL {
            return expected.url
        }
        return layout.noteURL(for: id)
    }

    /// Writes a fresh note (new id) and returns the landed record. Throws on disk failure.
    @discardableResult
    public func write(id: UUID, body: String) throws -> FileRecord {
        let note = Note(id: id, tags: TagNormalizer.extractTags(from: body), body: body)
        return try write(note: note)
    }

    /// Writes a fresh complete note and returns the landed record.
    @discardableResult
    public func write(note: Note) throws -> FileRecord {
        lock.lock()
        defer { lock.unlock() }

        let doc = FrontmatterCodec.document(note: note)
        let url = layout.noteURL(for: note.id)
        guard !fileManager.fileExists(at: url) else {
            throw RepositoryError.conflict(note.id)
        }
        try fileManager.write(doc.fullText, to: url)
        return fileManager.fileRecord(at: url)
            ?? FileRecord(url: url, fileSize: 0, modificationDate: Date(), contentHash: "")
    }

    // MARK: - Deletion / trash

    /// Moves an exact note file to the hidden library trash and returns the paths
    /// required to restore it. A unique suffix prevents rapid repeated deletes from
    /// colliding with an earlier trash entry.
    public func moveToTrash(fileURL: URL) throws -> TrashedNoteFile {
        lock.lock()
        defer { lock.unlock() }
        guard
            fileURL.deletingLastPathComponent().standardizedFileURL
                == layout.notesDirectory.standardizedFileURL
        else {
            throw RepositoryError.invalidNotePath
        }
        guard fileManager.fileExists(at: fileURL) else {
            throw RepositoryError.notFound(
                UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) ?? UUID())
        }
        do {
            try layout.createIfNeeded()
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let trashURL = layout.trashDirectory.appendingPathComponent(
                "\(stem)-\(UUID().uuidString).md",
                isDirectory: false
            )
            try FileManager.default.moveItem(at: fileURL, to: trashURL)
            return TrashedNoteFile(originalURL: fileURL, trashURL: trashURL)
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.saveFailed(underlying: String(describing: error))
        }
    }

    /// Restores a previously trashed note. Existing source files are never overwritten.
    @discardableResult
    public func restore(_ trashed: TrashedNoteFile) throws -> FileRecord {
        lock.lock()
        defer { lock.unlock() }
        guard
            trashed.originalURL.deletingLastPathComponent().standardizedFileURL
                == layout.notesDirectory.standardizedFileURL,
            trashed.trashURL.deletingLastPathComponent().standardizedFileURL
                == layout.trashDirectory.standardizedFileURL
        else {
            throw RepositoryError.invalidNotePath
        }
        guard fileManager.fileExists(at: trashed.trashURL) else {
            throw RepositoryError.unavailable(underlying: "trash entry is missing")
        }
        guard !fileManager.fileExists(at: trashed.originalURL) else {
            throw RepositoryError.conflict(
                UUID(uuidString: trashed.originalURL.deletingPathExtension().lastPathComponent) ?? UUID()
            )
        }
        do {
            try FileManager.default.moveItem(at: trashed.trashURL, to: trashed.originalURL)
        } catch {
            throw RepositoryError.saveFailed(underlying: String(describing: error))
        }
        guard let record = fileManager.fileRecord(at: trashed.originalURL) else {
            throw RepositoryError.unavailable(underlying: "restored file could not be read")
        }
        return record
    }

    /// Moves a note into the library's hidden Trash so accidental deletion is recoverable.
    public func delete(id: UUID) -> Bool {
        let url = layout.noteURL(for: id)
        return (try? moveToTrash(fileURL: url)) != nil
    }

    public func fileExists(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileManager.fileExists(at: layout.noteURL(for: id))
    }
}
