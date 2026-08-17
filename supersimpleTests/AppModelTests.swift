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
        let appSupport = dir.appendingPathComponent("AppSupport")
        let suiteName = "supersimple-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let model = AppModel(
            notesDirectoryOverride: notesDir,
            appSupportURLOverride: appSupport,
            userDefaults: defaults
        )
        return (
            model,
            {
                model.shutdown()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
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
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        await model.bootstrap()

        model.createNote()
        #expect(model.currentNote() != nil)
        #expect(model.notes.count == 1)

        model.noteBodyEdited("# New Note\nSome body", for: model.currentNoteID!)
        model.flushNow()

        // Reload from the SAME directory to confirm persistence.
        let (model2, cleanup2) = try makeModel(in: dir)
        defer { cleanup2() }
        await model2.bootstrap()
        #expect(model2.notes.count == 1)
        #expect(model2.notes.first?.body.contains("Some body") == true)
    }

    @Test("New note action creates and selects a fresh note")
    func createActionSelectsFreshNote() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        let firstID = model.currentNoteID
        model.createNote()

        #expect(model.notes.count == 2)
        #expect(model.currentNoteID != firstID)
        #expect(model.currentNote()?.body == "# New Note")
        #expect(model.notes.first?.id == model.currentNoteID)
    }

    @Test("Extracts tags from edited body")
    func tagExtraction() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Work\nTagged with #swift and #obsidian.", for: model.currentNoteID!)
        model.flushNow()

        #expect(model.notes.first?.tags.contains(Tag(name: "swift")) == true)
        #expect(model.allTags.contains { $0.tag.name == "swift" })
    }

    @Test("Deletes a note and clears selection")
    func deleteNote() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
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
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Recipes\nHow to make apple crumble.", for: model.currentNoteID!)
        model.flushNow()

        model.searchQuery = "crumble"
        model.performSearch()
        // Search runs off the main actor; wait for the async result.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.searchResults.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.visibleNotes.count == 1)
    }

    @Test("Empty state derives Untitled from a blank body")
    func untitledTitle() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        #expect(model.currentNote()?.title == "New Note")
    }

    @Test("A stale editor callback does not overwrite the newly selected note")
    func staleCallbackIgnored() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        let firstID = model.currentNoteID!
        model.noteBodyEdited("body of A", for: firstID)
        model.flushNow()

        // Switch to a second note.
        model.createNote()
        let secondID = model.currentNoteID!

        // A delayed callback belonging to the OLD note must be ignored.
        model.noteBodyEdited("body of A (stale)", for: firstID)
        #expect(model.currentBody == "# New Note")
        #expect(model.visibleNotes.first { $0.id == secondID }?.body == "# New Note")
        // The first note's persisted body is untouched.
        #expect(model.notes.first { $0.id == firstID }?.body == "body of A")
    }

    @Test("Toggling a tag edits the body and persists it")
    func toggleTagPersists() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Work\nTagged with #swift.", for: model.currentNoteID!)
        model.flushNow()

        // Removing should be reflected and persisted.
        model.toggleTagForCurrentNote(Tag(name: "swift"))
        model.flushNow()
        let editedBody = model.currentNote()?.body ?? ""
        #expect(!editedBody.contains("#swift"))

        // Re-add it.
        model.toggleTagForCurrentNote(Tag(name: "swift"))
        model.flushNow()
        #expect(model.currentNote()?.body.contains("#swift") == true)
    }

    @Test("Exports the note body and a sanitized filename")
    func exportNoteBody() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        model.noteBodyEdited("# Recipes / Ideas\nHow to make apple crumble.", for: model.currentNoteID!)
        model.flushNow()

        let note = try #require(model.currentNote())
        #expect(model.exportMarkdown(for: note) == note.body)
        #expect(model.exportFilename(for: note) == "Recipes - Ideas.md")

        let out = dir.appendingPathComponent("export.md")
        try model.writeExport(of: note, to: out)
        #expect(try String(contentsOf: out, encoding: .utf8) == note.body)
    }

    @Test("Imports a markdown file as a new note")
    func importMarkdownFile() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        let source = dir.appendingPathComponent("incoming.md")
        try "# Imported\nHello #inbox".write(to: source, atomically: true, encoding: .utf8)

        let note = try model.importNote(from: source)
        #expect(note.title == "Imported")
        #expect(note.body.contains("Hello #inbox"))
        #expect(note.tags.contains(Tag(name: "inbox")))
        #expect(model.notes.count == 1)
        #expect(model.currentNoteID == note.id)
    }

    @Test("deleteCurrentNote removes the selected note")
    func deleteCurrentNote() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.createNote()
        #expect(model.notes.count == 1)
        model.deleteCurrentNote()
        #expect(model.notes.isEmpty)
        #expect(model.currentNote() == nil)
    }

    @Test("Bottom bar visibility can be toggled")
    func bottomBarVisibilityToggles() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        #expect(model.bottomBarVisible)
        model.bottomBarVisible = false
        #expect(!model.bottomBarVisible)
        model.bottomBarVisible = true
        #expect(model.bottomBarVisible)
    }
}

@Suite("NoteStats")
struct NoteStatsTests {
    @Test("Counts words and characters")
    func counts() {
        #expect(NoteStats.wordCount("") == 0)
        #expect(NoteStats.wordCount("  \n  ") == 0)
        #expect(NoteStats.wordCount("one two three") == 3)
        #expect(NoteStats.characterCount("hi") == 2)
    }

    @Test("Sanitizes filenames")
    func filenames() {
        #expect(NoteStats.sanitizedFilename("Recipes / Ideas") == "Recipes - Ideas")
        #expect(NoteStats.sanitizedFilename("   ") == "Untitled")
        #expect(NoteStats.sanitizedFilename("a:b?c") == "a-b-c")
    }
}
