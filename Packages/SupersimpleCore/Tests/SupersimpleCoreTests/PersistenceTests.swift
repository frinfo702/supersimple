import Foundation
import Testing

@testable import SupersimpleCore

@Suite("Note file persistence and markdown scanning")
struct PersistenceTests {

    @Test("Writes and reads back atomically")
    func writeRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = NoteFileManager()
        let url = dir.appendingPathComponent("note.md")
        try manager.write("hello world", to: url)
        #expect(manager.fileExists(at: url))
        #expect(try manager.read(at: url) == "hello world")
    }

    @Test("Deletes a file, ignoring a missing one")
    func delete() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = NoteFileManager()
        let url = dir.appendingPathComponent("note.md")
        try manager.write("content", to: url)
        manager.delete(at: url)
        #expect(!manager.fileExists(at: url))
        // Deleting a non-existent file should not throw.
        manager.delete(at: url)
    }

    @Test("Lists only markdown files")
    func list() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = NoteFileManager()
        try manager.write("a", to: dir.appendingPathComponent("1.md"))
        try manager.write("b", to: dir.appendingPathComponent("2.md"))
        try manager.write("c", to: dir.appendingPathComponent("x.txt"))

        let urls = manager.existingNoteURLs(in: dir)
        #expect(urls.count == 2)
    }

    @Test("Scanner detects code fences and skips math inside them")
    func mathScannerIgnoresCode() {
        let body = """
            $$x + y$$

            ```swift
            let s = "$notmath"
            ```
            """
        let segments = MarkdownScanner.mathSegments(in: body)
        // Block math outside code is captured; the $ inside code is not.
        #expect(segments.contains { $0.isInline == false })
        #expect(!segments.contains { $0.isInline && $0.content.contains("notmath") })
    }

    @Test("Scanner finds block and inline math")
    func mathScannerBlockAndInline() {
        let body = "Inline $a^2 + b^2 = c^2$ here, then block:\n\n$$E = mc^2$$"
        let segments = MarkdownScanner.mathSegments(in: body)
        #expect(segments.contains { $0.isInline && $0.content == "a^2 + b^2 = c^2" })
        #expect(segments.contains { $0.isInline == false && $0.content == "E = mc^2" })
    }

    @Test("Note derives title from first heading")
    func noteTitle() {
        let note = Note(body: "# My Heading\nSome body")
        #expect(note.title == "My Heading")
        let untitled = Note(body: "")
        #expect(untitled.title == "Untitled")
        let firstLine = Note(body: "No heading\njust text")
        #expect(firstLine.title == "No heading")
    }
}
