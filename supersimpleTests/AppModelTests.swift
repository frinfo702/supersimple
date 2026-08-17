import Foundation
import SupersimpleCore
import SwiftUI
import Testing

@testable import supersimple

@MainActor
@Suite("AppModel end-to-end")
struct AppModelTests {

    private func makeModel(in dir: URL) throws -> (model: AppModel, cleanup: () -> Void) {
        let notesDir = dir.appendingPathComponent("Notes")
        let model = AppModel(notesDirectoryOverride: notesDir)
        return (model, { try? FileManager.default.removeItem(at: dir) })
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Creates a note and persists it to disk")
    func createAndPersist() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer { cleanup() }

        await model.bootstrap()

        model.createNote()
        #expect(model.currentNote() != nil)
        #expect(model.notes.count == 1)

        model.noteBodyEdited("# New Note\nSome body")
        model.flushNow()

        // Reload from the SAME directory to confirm persistence.
        let (model2, _) = try makeModel(in: dir)
        await model2.bootstrap()
        #expect(model2.notes.count == 1)
        #expect(model2.notes.first?.body.contains("Some body") == true)
    }

    @Test("Extracts tags from edited body")
    func tagExtraction() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer { cleanup() }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Work\nTagged with #swift and #obsidian.")
        model.flushNow()

        #expect(model.notes.first?.tags.contains(Tag(name: "swift")) == true)
        #expect(model.allTags.contains { $0.tag.name == "swift" })
    }

    @Test("Deletes a note and clears selection")
    func deleteNote() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer { cleanup() }
        await model.bootstrap()

        model.createNote()
        guard let note = model.currentNote() else {
            Issue.record("no current note")
            return
        }
        model.deleteNote(note)
        #expect(model.notes.isEmpty)
        #expect(model.currentNote() == nil)
    }

    @Test("Search finds a note after save")
    func searchAfterSave() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer { cleanup() }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Recipes\nHow to make apple crumble.")
        model.flushNow()

        model.searchQuery = "crumble"
        model.performSearch()
        #expect(model.visibleNotes.count == 1)
    }

    @Test("Empty state derives Untitled from a blank body")
    func untitledTitle() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer { cleanup() }
        await model.bootstrap()

        model.createNote()
        #expect(model.currentNote()?.title == "New Note")
    }
}
