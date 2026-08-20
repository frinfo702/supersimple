import CryptoKit
import Foundation

public enum NoteFileError: Error, Sendable, Equatable {
    case invalidPath
    case writeFailed(underlying: String)
    case readFailed(underlying: String)
    case directoryUnavailable(underlying: String)
}

/// Static snapshot of a file's identity at read time. Used to detect external edits
/// (another editor, iCloud sync, a second app instance) before overwriting.
public struct FileRecord: Equatable, Hashable, Sendable {
    public let url: URL
    public let fileSize: Int64
    public let modificationDate: Date
    /// Hex SHA-256 of the raw file bytes.
    public let contentHash: String

    public init(url: URL, fileSize: Int64, modificationDate: Date, contentHash: String) {
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.contentHash = contentHash
    }
}

/// Responsibilities for reading and writing `.md` documents to and from a notes directory,
/// using atomic replacements so a crash can never leave a half-written file on disk.
public final class NoteFileManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func notesDirectoryURL(under baseURL: URL? = nil) -> URL {
        let base =
            baseURL
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("Supersimple/Notes", isDirectory: true)
        createDirectoryIfNeeded(at: base)
        return base
    }

    private func createDirectoryIfNeeded(at url: URL) {
        lock.lock()
        defer { lock.unlock() }
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// File URL for a note id inside a notes directory.
    public func fileURL(for id: UUID, notesDirectory: URL) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).md")
    }

    /// Reads the raw text at a file URL.
    public func read(at url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NoteFileError.readFailed(underlying: "not UTF-8")
            }
            return text
        } catch let error as NoteFileError {
            throw error
        } catch {
            throw NoteFileError.readFailed(underlying: String(describing: error))
        }
    }

    /// Writes `text` to `url` atomically and synchronizes the result to stable storage.
    ///
    /// User documents (as opposed to the derived search cache) are intentionally *not*
    /// excluded from backup: this app's Markdown files are the source of truth and should
    /// be recoverable through normal backup mechanisms.
    public func write(_ text: String, to url: URL) throws {
        createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            synchronizeFile(at: url)
        } catch {
            throw NoteFileError.writeFailed(underlying: String(describing: error))
        }
    }

    /// Opens the file for writing and calls `synchronizeFile()` to flush dirty pages.
    /// A directory entry syncing (rename durability) is best-effort on this platform.
    private func synchronizeFile(at url: URL) {
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.synchronize()
        } catch {
            // Non-fatal: atomic rename already prevents partial file contents.
        }
    }

    /// Deletes the file at `url`. Throws for non-"not found" failures so callers
    /// can distinguish a successful delete from an I/O error.
    public func delete(at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw NoteFileError.writeFailed(underlying: String(describing: error))
        }
    }

    public func fileExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileManager.fileExists(atPath: url.path)
    }

    /// All note-file URLs currently present in a notes directory.
    public func existingNoteURLs(in notesDirectory: URL) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let urls =
            (try? fileManager.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "md" }
    }

    /// Throwing enumeration that distinguishes a genuinely empty directory from an
    /// unavailable one (missing mount, revoked permission, I/O failure). Callers must
    /// not treat these the same way — an unavailable library is not "no notes".
    public func enumerateNoteURLs(in notesDirectory: URL) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return urls.filter { $0.pathExtension.lowercased() == "md" }
        } catch {
            // A directory that does not exist yet is "empty", not an error — the parent
            // chain is creatable. Any other failure (mount gone, permission denied) means
            // the library is genuinely unavailable and must be surfaced, not swept under
            // "no notes".
            if !fileManager.fileExists(atPath: notesDirectory.path) {
                return []
            }
            throw NoteFileError.directoryUnavailable(underlying: String(describing: error))
        }
    }

    /// Captures the identity of the file at `url`, or `nil` when it is absent/invalid.
    public func fileRecord(at url: URL) -> FileRecord? {
        lock.lock()
        defer { lock.unlock() }
        return Self.record(at: url, fileManager: fileManager)
    }

    fileprivate static func record(at url: URL, fileManager: FileManager) -> FileRecord? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return FileRecord(
            url: url,
            fileSize: Int64(data.count),
            modificationDate: values.contentModificationDate ?? Date.distantPast,
            contentHash: hash
        )
    }

    /// Whether two records describe identical file contents (hash is authoritative,
    /// robust against clock-skewed modification dates).
    public static func contentsMatch(_ lhs: FileRecord?, _ rhs: FileRecord?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.contentHash == rhs.contentHash
    }
}
