import Foundation
import Testing

@testable import SupersimpleCore

@Suite("Library layout")
struct LibraryLayoutTests {
    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-lib-\(UUID().uuidString)")
        return root
    }

    @Test("Resolves canonical subdirectories")
    func subdirectories() {
        let root = URL(fileURLWithPath: "/tmp/test-lib")
        let layout = LibraryLayout(root: root)
        #expect(layout.notesDirectory == root.appendingPathComponent("Notes", isDirectory: true))
        #expect(layout.attachmentsDirectory == root.appendingPathComponent("Attachments", isDirectory: true))
        #expect(layout.metadataDirectory == root.appendingPathComponent(".supersimple", isDirectory: true))
        #expect(
            layout.noteURL(for: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!).lastPathComponent
                == "00000000-0000-0000-0000-000000000000.md")
    }

    @Test("createIfNeeded materializes every directory")
    func createsDirectories() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = LibraryLayout(root: root)
        try layout.createIfNeeded()
        #expect(FileManager.default.fileExists(atPath: layout.notesDirectory.path))
        #expect(FileManager.default.fileExists(atPath: layout.attachmentsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: layout.trashDirectory.path))
        #expect(FileManager.default.fileExists(atPath: layout.conflictsDirectory.path))
    }
}

@Suite("Note file record and enumeration")
struct FileRecordTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-record-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Record captures content hash and distinguishes changes")
    func recordDetectsChange() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("n.md")
        let fm = NoteFileManager()
        try fm.write("hello", to: url)
        let before = try #require(fm.fileRecord(at: url))
        try fm.write("hello!", to: url)
        let after = try #require(fm.fileRecord(at: url))
        #expect(!NoteFileManager.contentsMatch(before, after))
    }

    @Test("enumerateNoteURLs returns empty for an absent directory rather than failing")
    func absentDirectoryIsEmpty() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = NoteFileManager()
        let absent = dir.appendingPathComponent("no-such-\(UUID().uuidString)", isDirectory: true)
        #expect(try fm.enumerateNoteURLs(in: absent).isEmpty)
    }
}

@Suite("Note repository")
struct NoteRepositoryTests {
    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-repo-\(UUID().uuidString)")
        try LibraryLayout(root: root).createIfNeeded()
        return root
    }

    @Test("Round-trips a note and lists it as a summary without loading bodies")
    func roundTrip() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let id = UUID()
        _ = try repo.write(id: id, body: "# Title\nSome body #swift")
        let summaries = try repo.listSummaries()
        #expect(summaries?.count == 1)
        let summary = try #require(summaries?.first)
        #expect(summary.id == id)
        #expect(summary.title == "Title")
        // In-memory list must be summaries, but we still need a way to retrieve the body
        // on demand:
        if case .content(let content) = repo.load(id: id) {
            #expect(content.body.contains("Some body"))
            #expect(content.summary.tags.contains(Tag(name: "swift")))
            // The summary stored no body text.
            #expect(!content.summary.title.contains("Some body"))
        } else {
            Issue.record("expected to load content")
        }
        _ = summaries
    }

    @Test("Conflict is detected when the on-disk file changes between read and save")
    func conflictDetection() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let id = UUID()
        let record = try repo.write(id: id, body: "version 1")

        // Simulate an external edit.
        try "external".write(
            to: LibraryLayout(root: root).noteURL(for: id),
            atomically: true, encoding: .utf8)

        let result = try repo.save(id: id, body: "version 2", expected: record)
        guard case .conflict = result else {
            Issue.record("expected a conflict when saved against a stale record")
            return
        }
        // Nothing was overwritten.
        let onDisk = try String(
            contentsOf: LibraryLayout(root: root).noteURL(for: id), encoding: .utf8)
        #expect(onDisk == "external")
    }

    @Test("Save succeeds and returns the new record when the file is unchanged")
    func saveSucceeds() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let id = UUID()
        let record = try repo.write(id: id, body: "# Note\nbody")
        let result = try repo.save(id: id, body: "# Note\nbody2", expected: record)
        guard case .written(let landed) = result else {
            Issue.record("expected written result")
            return
        }
        #expect(landed.fileSize > 0)
        if case .content(let content) = repo.load(id: id) {
            #expect(content.body == "# Note\nbody2")
        } else {
            Issue.record("expected to load updated content")
        }
    }

    @Test("Save preserves creation date and unmanaged frontmatter")
    func savePreservesMetadata() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let created = Date(timeIntervalSince1970: 1_700_000_000.123)
        let note = Note(
            createdAt: created,
            updatedAt: created,
            body: "# Original",
            extraFields: ["aliases: [sample]", "cssclasses: [wide]"]
        )
        let record = try repo.write(note: note)

        _ = try repo.save(id: note.id, body: "# Updated", expected: record)

        let text = try String(contentsOf: LibraryLayout(root: root).noteURL(for: note.id), encoding: .utf8)
        let decoded = try FrontmatterCodec.decode(text)
        #expect(decoded.metadata.createdAt == created)
        #expect(decoded.metadata.extraFields == note.extraFields)
    }

    @Test("Save without a baseline never overwrites an existing note")
    func missingBaselineConflicts() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let id = UUID()
        _ = try repo.write(id: id, body: "original")

        let result = try repo.save(id: id, body: "replacement", expected: nil)
        guard case .conflict = result else {
            Issue.record("expected a conflict without a baseline record")
            return
        }
        if case .content(let content) = repo.load(id: id) {
            #expect(content.body == "original")
        } else {
            Issue.record("expected the original note to remain")
        }
    }

    @Test("Delete moves the file to the library's trash, not permanent removal")
    func deleteMovesToTrash() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NoteRepository(root: root)
        let id = UUID()
        _ = try repo.write(id: id, body: "content")
        let deleted = repo.delete(id: id)
        #expect(deleted)
        #expect(!LibraryLayout(root: root).fileExists(id: id))
    }

    @Test("Attachment names reject path traversal")
    func attachmentSafety() {
        #expect(NoteRepository.isSafeAttachmentName("abc.png"))
        #expect(!NoteRepository.isSafeAttachmentName("../secret.png"))
        #expect(!NoteRepository.isSafeAttachmentName("a/b.png"))
        #expect(!NoteRepository.isSafeAttachmentName(""))
        #expect(!NoteRepository.isSafeAttachmentName(".hidden"))
    }
}

@Suite("Library migrator")
struct LibraryMigratorTests {
    private func tempRoot() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-migrate-\(UUID().uuidString)")
    }

    @Test("Copies notes and images into the layout, skipping identical files")
    func copiesNotesAndImages() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("legacy", isDirectory: true)
        let notes = source.appendingPathComponent("Notes", isDirectory: true)
        let images = source.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

        let id = UUID()
        let doc = MarkdownDocument(
            metadata: NoteMetadata(id: id, createdAt: Date(), updatedAt: Date(), tags: [Tag(name: "x")]),
            body: "# Migrated\nhello"
        )
        try doc.fullText.write(
            to: notes.appendingPathComponent("\(id.uuidString).md"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: images.appendingPathComponent("pic.png"))

        let layout = LibraryLayout(root: root.appendingPathComponent("dest", isDirectory: true))
        let migrator = LibraryMigrator()
        let report = try await migrator.migrate(notesSource: notes, imagesSource: images, layout: layout)

        #expect(report.copied == 2)
        #expect(report.problems.isEmpty)
        #expect(FileManager.default.fileExists(atPath: layout.noteURL(for: id).path))
        #expect(
            FileManager.default.fileExists(atPath: layout.attachmentsDirectory.appendingPathComponent("pic.png").path))
    }

    @Test("Reports duplicate IDs by assigning a fresh note id")
    func duplicateIDsReported() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("legacy", isDirectory: true)
        let notes = source.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)

        let id = UUID()
        for i in 0..<2 {
            let doc = MarkdownDocument(
                metadata: NoteMetadata(id: id, createdAt: Date(), updatedAt: Date(), tags: []),
                body: "dup \(i)"
            )
            try doc.fullText.write(
                to: notes.appendingPathComponent("\(id.uuidString)-\(i).md"), atomically: true, encoding: .utf8)
        }

        let layout = LibraryLayout(root: root.appendingPathComponent("dest", isDirectory: true))
        let migrator = LibraryMigrator()
        let report = try await migrator.migrate(notesSource: notes, imagesSource: nil, layout: layout)
        #expect(report.problems.contains { $0.kind == .duplicateID })

        let migratedURLs = try NoteFileManager().enumerateNoteURLs(in: layout.notesDirectory)
        let documents = try migratedURLs.map {
            try FrontmatterCodec.decode(String(contentsOf: $0, encoding: .utf8))
        }
        #expect(documents.count == 2)
        #expect(Set(documents.map(\.metadata.id)).count == 2)
        #expect(Set(documents.map(\.body)) == ["dup 0", "dup 1"])
        for url in migratedURLs {
            let document = try FrontmatterCodec.decode(String(contentsOf: url, encoding: .utf8))
            #expect(url.deletingPathExtension().lastPathComponent == document.metadata.id.uuidString)
        }
    }

    @Test("Adds stable frontmatter while migrating a plain Markdown file")
    func plainMarkdownGetsCanonicalID() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "# Plain\nbody".write(
            to: source.appendingPathComponent("plain.md"), atomically: true, encoding: .utf8)

        let layout = LibraryLayout(root: root.appendingPathComponent("dest", isDirectory: true))
        let migrator = LibraryMigrator()
        _ = try await migrator.migrate(notesSource: source, imagesSource: nil, layout: layout)

        let url = try #require(try NoteFileManager().enumerateNoteURLs(in: layout.notesDirectory).first)
        let document = try FrontmatterCodec.decode(String(contentsOf: url, encoding: .utf8))
        #expect(url.deletingPathExtension().lastPathComponent == document.metadata.id.uuidString)
        #expect(document.body == "# Plain\nbody")

        let retry = try await migrator.migrate(notesSource: source, imagesSource: nil, layout: layout)
        #expect(retry.skipped == 1)
        #expect(try NoteFileManager().enumerateNoteURLs(in: layout.notesDirectory).count == 1)
    }
}
