import Foundation

public enum NoteFileError: Error, Sendable, Equatable {
    case invalidPath
    case writeFailed(underlying: String)
    case readFailed(underlying: String)
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

    /// Writes `text` to `url` atomically, flushing to disk before returning.
    public func write(_ text: String, to url: URL) throws {
        createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            // Ensure the write reaches stable storage before the caller reports success.
            var mutable = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? mutable.setResourceValues(resourceValues)
        } catch {
            throw NoteFileError.writeFailed(underlying: String(describing: error))
        }
    }

    /// Deletes the file at `url`, ignoring a missing file.
    public func delete(at url: URL) {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
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
}
