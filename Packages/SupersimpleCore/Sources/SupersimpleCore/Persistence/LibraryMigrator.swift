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

/// Copies an existing loose set of Markdown notes (plus an images folder) into a
/// `LibraryLayout`, verifying byte hashes and reporting (never silently dropping)
/// collisions and unreadable files. The source is left untouched for safety.
public actor LibraryMigrator {
    private let fileManager = NoteFileManager()
    private let fm = FileManager.default

    public init() {}

    /// Migrates `.md` files under `notesSource` and image files under `imagesSource`
    /// (if present) into `layout`. Files already present as byte-identical content are
    /// skipped. Files that parse with a valid UUID are stored under `Notes/<id>.md`.
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
            let doc: MarkdownDocument
            if let parsed = try? FrontmatterCodec.decode(text) {
                doc = parsed
            } else {
                doc = MarkdownDocument(
                    metadata: NoteMetadata(id: UUID(), createdAt: Date(), updatedAt: Date(), tags: []),
                    body: text
                )
            }

            let id: UUID
            if usedIDs.contains(doc.metadata.id) {
                report.problems.append(
                    MigrationProblem(kind: .duplicateID, noteID: doc.metadata.id.uuidString, source: url))
                id = UUID()
            } else {
                id = doc.metadata.id
            }
            usedIDs.insert(id)

            let target = layout.noteURL(for: id)
            copyIfDifferent(from: url, to: target, report: &report, noteID: id)
        }

        if let imagesSource, fm.fileExists(atPath: imagesSource.path) {
            let names = (try? fm.contentsOfDirectory(atPath: imagesSource.path)) ?? []
            for name in names where NoteRepository.isSafeAttachmentName(name) {
                let src = imagesSource.appendingPathComponent(name)
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
                        report.copied += 1
                    }
                } catch {
                    report.problems.append(
                        MigrationProblem(kind: .unreadable(src), noteID: nil, source: src))
                }
            }
        }

        return report
    }

    private func copyIfDifferent(from src: URL, to dst: URL, report: inout MigrationReport, noteID: UUID) {
        if fm.fileExists(atPath: dst.path) {
            if NoteFileManager.contentsMatch(fileManager.fileRecord(at: src), fileManager.fileRecord(at: dst)) {
                report.skipped += 1
                return
            }
            report.problems.append(
                MigrationProblem(kind: .nameConflict(dst.lastPathComponent), noteID: noteID.uuidString, source: src))
            return
        }
        do {
            try copyFile(from: src, to: dst)
            report.copied += 1
        } catch {
            report.problems.append(
                MigrationProblem(kind: .unreadable(src), noteID: noteID.uuidString, source: src))
        }
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
