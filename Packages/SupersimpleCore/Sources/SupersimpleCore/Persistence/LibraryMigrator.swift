import CryptoKit
import Foundation

public struct MigrationProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case unreadable(URL)
        case duplicateID
        case nameConflict(String)
    }
    public let kind: Kind
    public let noteID: String?
    public let source: URL
}

public struct MigrationReport: Sendable {
    public var copied: Int
    public var skipped: Int
    public var problems: [MigrationProblem]
    public init(copied: Int = 0, skipped: Int = 0, problems: [MigrationProblem] = []) {
        self.copied = copied
        self.skipped = skipped
        self.problems = problems
    }
}

/// Migrates an existing loose set of Markdown notes (plus an images folder) into a
/// `LibraryLayout`, writing canonical frontmatter, verifying landed bytes, and reporting
/// (never silently dropping) collisions and unreadable files. The source is left untouched.
public actor LibraryMigrator {
    private let fileManager = NoteFileManager()
    private let fm = FileManager.default

    public init() {}

    /// Migrates `.md` files under `notesSource` and image files under `imagesSource`
    /// (if present) into `layout`. Files already present as identical canonical documents
    /// are skipped. Files that parse with a valid UUID are stored under `Notes/<id>.md`.
    /// Duplicate IDs are given a fresh id so nothing is silently overwritten; the
    /// offending source is reported.
    @discardableResult
    public func migrate(notesSource: URL, imagesSource: URL?, layout: LibraryLayout) async throws -> MigrationReport {
        try layout.createIfNeeded()
        var report = MigrationReport()

        let noteURLs: [URL]
        if !fm.fileExists(atPath: notesSource.path) {
            noteURLs = []
        } else {
            do {
                noteURLs = try fileManager.enumerateNoteURLs(in: notesSource)
            } catch {
                report.problems.append(
                    MigrationProblem(kind: .unreadable(notesSource), noteID: nil, source: notesSource))
                noteURLs = []
            }
        }

        var usedIDs: Set<UUID> = []
        for url in noteURLs {
            guard let text = try? fm.stringContents(of: url) else {
                report.problems.append(MigrationProblem(kind: .unreadable(url), noteID: nil, source: url))
                continue
            }
            var doc = try FrontmatterCodec.decode(text)
            if persistedID(in: text) == nil {
                doc.metadata.id = stableID(for: url.lastPathComponent, text: text)
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let updatedAt =
                    values?.contentModificationDate ?? values?.creationDate ?? Date(timeIntervalSince1970: 0)
                doc.metadata.createdAt = values?.creationDate ?? updatedAt
                doc.metadata.updatedAt = updatedAt
            }

            let id: UUID
            if usedIDs.contains(doc.metadata.id) {
                report.problems.append(
                    MigrationProblem(kind: .duplicateID, noteID: doc.metadata.id.uuidString, source: url))
                id = UUID()
                doc.metadata.id = id
            } else {
                id = doc.metadata.id
            }
            usedIDs.insert(id)

            let target = layout.noteURL(for: id)
            writeIfDifferent(doc.fullText, source: url, to: target, report: &report, noteID: id)
        }

        if let imagesSource {
            migrateAttachments(from: imagesSource, layout: layout, report: &report)
        }

        return report
    }

    /// Migrates only legacy images into a library's canonical attachment directory.
    @discardableResult
    public func migrateAttachments(
        from imagesSource: URL,
        layout: LibraryLayout
    ) throws -> MigrationReport {
        try layout.createIfNeeded()
        var report = MigrationReport()
        migrateAttachments(from: imagesSource, layout: layout, report: &report)
        return report
    }

    private func writeIfDifferent(
        _ text: String,
        source src: URL,
        to dst: URL,
        report: inout MigrationReport,
        noteID: UUID
    ) {
        let data = Data(text.utf8)
        if fm.fileExists(atPath: dst.path) {
            if let existing = try? Data(contentsOf: dst), existing == data {
                report.skipped += 1
                return
            }
            report.problems.append(
                MigrationProblem(kind: .nameConflict(dst.lastPathComponent), noteID: noteID.uuidString, source: src))
            return
        }
        do {
            try fileManager.write(text, to: dst)
            guard let landed = try? Data(contentsOf: dst), landed == data else {
                throw NoteFileError.writeFailed(underlying: "post-write verification failed")
            }
            report.copied += 1
        } catch {
            report.problems.append(
                MigrationProblem(kind: .unreadable(src), noteID: noteID.uuidString, source: src))
        }
    }

    private func migrateAttachments(
        from imagesSource: URL,
        layout: LibraryLayout,
        report: inout MigrationReport
    ) {
        guard fm.fileExists(atPath: imagesSource.path) else { return }
        let names = (try? fm.contentsOfDirectory(atPath: imagesSource.path)) ?? []
        for name in names where NoteRepository.isSafeAttachmentName(name) {
            let src = imagesSource.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            let dst = layout.attachmentsDirectory.appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: dst.path) {
                    if NoteFileManager.contentsMatch(
                        fileManager.fileRecord(at: src), fileManager.fileRecord(at: dst))
                    {
                        report.skipped += 1
                    } else {
                        report.problems.append(
                            MigrationProblem(kind: .nameConflict(dst.lastPathComponent), noteID: nil, source: src))
                    }
                } else {
                    try copyFile(from: src, to: dst)
                    guard
                        NoteFileManager.contentsMatch(
                            fileManager.fileRecord(at: src), fileManager.fileRecord(at: dst))
                    else {
                        try? fm.removeItem(at: dst)
                        throw NoteFileError.writeFailed(underlying: "post-copy verification failed")
                    }
                    report.copied += 1
                }
            } catch {
                report.problems.append(
                    MigrationProblem(kind: .unreadable(src), noteID: nil, source: src))
            }
        }
    }

    /// Extracts a valid managed id from an opening frontmatter block without accepting an
    /// id-like line in the Markdown body.
    private func persistedID(in text: String) -> UUID? {
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let first = lines.first else { return nil }
        var opening = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if opening.hasPrefix("\u{FEFF}") { opening.removeFirst() }
        guard opening == "---" else { return nil }
        guard
            let close = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
            })
        else { return nil }
        for line in lines[1..<close] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "id" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return UUID(uuidString: value)
        }
        return nil
    }

    /// Produces a repeatable UUID for a plain Markdown source so retrying a migration does
    /// not create a second managed note for the same source file.
    private func stableID(for filename: String, text: String) -> UUID {
        let digest = SHA256.hash(data: Data((filename + "\u{0}" + text).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let uuidString =
            "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-"
            + "\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: uuidString)!
    }

    private func copyFile(from src: URL, to dst: URL) throws {
        let dir = dst.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try fm.copyItem(at: src, to: dst)
    }
}

extension FileManager {
    fileprivate func stringContents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
