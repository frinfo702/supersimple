import Foundation

/// Describes the on-disk layout of a user-visible note library.
///
/// The library is a normal, browsable folder so it can live on iCloud Drive, a mounted
/// volume, or the local disk and be opened from the integrated Terminal or read by an AI
/// agent. The `.md` files and `Attachments` are the source of truth; the SQLite search
/// index is a derived cache that lives *outside* the library (under the app cache dir).
///
/// ```text
/// <root>/
///   Notes/          <UUID>.md
///   Attachments/    <UUID>.<ext>
///   .supersimple/
///     library.json
///     Conflicts/
///     Trash/
/// ```
public struct LibraryLayout: Sendable {
    public let root: URL
    /// Name of the notes subdirectory.
    public static let notesDirectoryName = "Notes"
    public static let attachmentsDirectoryName = "Attachments"
    public static let metadataDirectoryName = ".supersimple"
    public static let conflictsDirectoryName = "Conflicts"
    public static let trashDirectoryName = "Trash"

    public init(root: URL) {
        self.root = root
    }

    public var notesDirectory: URL {
        root.appendingPathComponent(Self.notesDirectoryName, isDirectory: true)
    }

    public var attachmentsDirectory: URL {
        root.appendingPathComponent(Self.attachmentsDirectoryName, isDirectory: true)
    }

    public var metadataDirectory: URL {
        root.appendingPathComponent(Self.metadataDirectoryName, isDirectory: true)
    }

    public var conflictsDirectory: URL {
        metadataDirectory.appendingPathComponent(Self.conflictsDirectoryName, isDirectory: true)
    }

    public var trashDirectory: URL {
        metadataDirectory.appendingPathComponent(Self.trashDirectoryName, isDirectory: true)
    }

    /// Canonical file URL for a note id inside `Notes/`.
    public func noteURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).md", isDirectory: false)
    }

    /// Whether a note file currently exists on disk.
    public func fileExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: noteURL(for: id).path)
    }

    /// Creates every directory in the layout (including the hidden metadata dir).
    public func createIfNeeded() throws {
        let fm = FileManager.default
        for dir in [notesDirectory, attachmentsDirectory, metadataDirectory, conflictsDirectory, trashDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
