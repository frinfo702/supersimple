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

        #expect(model.notes.count == 1)
        let id = try #require(model.currentNoteID)
        model.noteBodyEdited("# New Note\nSome body", for: id)
        model.flushNow()

        // Reload from the SAME directory to confirm persistence.
        let (model2, cleanup2) = try makeModel(in: dir)
        defer { cleanup2() }
        await model2.bootstrap()
        #expect(model2.notes.count == 1)
        #expect(model2.notes.first?.body.contains("Some body") == true)
    }

    @Test("Shutdown persists a dirty edit without waiting for autosave")
    func shutdownPersistsDirtyEdit() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        await model.bootstrap()
        let id = try #require(model.currentNoteID)
        model.noteBodyEdited("# Keep me\nThis must survive quit.", for: id)
        model.shutdown()

        let (model2, cleanup2) = try makeModel(in: dir)
        defer { cleanup2() }
        await model2.bootstrap()
        #expect(model2.notes.first?.body.contains("This must survive quit.") == true)
    }

    @Test("Switching notes persists the outgoing body immediately")
    func createNotePersistsPreviousBody() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        await model.bootstrap()
        let firstID = try #require(model.currentNoteID)
        model.noteBodyEdited("# First\nDo not drop this.", for: firstID)
        model.createNote()

        let (model2, cleanup2) = try makeModel(in: dir)
        defer { cleanup2() }
        await model2.bootstrap()
        #expect(model2.notes.contains { $0.id == firstID && $0.body.contains("Do not drop this.") })
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

        #expect(model.notes.count == 1)
        let firstID = model.currentNoteID
        model.createNote()

        #expect(model.notes.count == 2)
        #expect(model.currentNoteID != firstID)
        #expect(model.currentNote()?.body == "")
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

        #expect(model.notes.count == 1)
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

        guard let note = model.currentNote() else {
            Issue.record("no current note")
            return
        }
        model.deleteNote(note)
        #expect(model.notes.isEmpty)
        #expect(model.currentNote() == nil)
    }

    @Test("Loading two files with the same frontmatter id deduplicates instead of crashing")
    func duplicateNoteIDsDoNotCrashSearch() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        // Two distinct files sharing one frontmatter UUID (e.g. from a bad migration or
        // external copy). The loader must collapse these into one note, not crash when a
        // search joins by a unique-ID dictionary.
        let sharedID = UUID()
        let notes = LibraryLayout(root: dir).notesDirectory
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        for (i, title) in ["# First", "# Second"].enumerated() {
            let doc = MarkdownDocument(
                metadata: NoteMetadata(id: sharedID, createdAt: Date(), updatedAt: Date(), tags: []),
                body: title
            )
            try doc.fullText.write(
                to: notes.appendingPathComponent("shared-\(i).md"), atomically: true, encoding: .utf8)
        }

        await model.bootstrap()
        // Exactly one note wins (deduplication by id).
        #expect(model.notes.count == 1)
        #expect(model.notes.first?.id == sharedID)

        model.searchQuery = "First"
        model.performSearch()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.searchResults.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // visibleNotes uses a last-write-wins dictionary, so this never traps.
        #expect(model.visibleNotes.count >= 0)
    }

    @Test("Clearing the search invalidates an in-flight result")
    func clearSearchDropsStaleResults() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.searchQuery = "crumble"
        model.performSearch()
        // Clear before the detached query can finish; the stale completion must be dropped.
        model.clearLibraryFilter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.searchResults.isEmpty)
        #expect(!model.isSearching)
    }

    @Test("Persisted library root redirects the notes directory into the chosen folder")
    func persistedLibraryRootRedirectsNotes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let appSupport = dir.appendingPathComponent("AppSupport")
        let chosenRoot = dir.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: chosenRoot, withIntermediateDirectories: true)
        let suiteName = "supersimple-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Persist a chosen library root, then build a model (no overrides) so it must honor it.
        defaults.set(chosenRoot.path, forKey: "libraryRootPath")
        let model = AppModel(
            notesDirectoryOverride: nil,
            appSupportURLOverride: appSupport,
            userDefaults: defaults
        )
        let expected = LibraryLayout(root: chosenRoot).notesDirectory
        #expect(model.notesDirectory == expected)
        model.shutdown()
    }

    @Test("Switching libraries migrates notes into the new folder and loads them")
    func switchLibraryMigratesAndLoads() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notesDir = dir.appendingPathComponent("Notes")
        let appSupport = dir.appendingPathComponent("AppSupport")
        let suiteName = "supersimple-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let model = AppModel(
            notesDirectoryOverride: notesDir,
            appSupportURLOverride: appSupport,
            userDefaults: defaults
        )
        defer {
            model.shutdown()
            defaults.removePersistentDomain(forName: suiteName)
        }

        await model.bootstrap()
        model.noteBodyEdited("# First\nbody", for: model.currentNoteID!)
        model.flushNow()
        let firstID = try #require(model.currentNoteID)
        #expect(model.notes.count == 1)

        // Choose a fresh folder; migration copies the note there, then the model reloads.
        let newRoot = dir.appendingPathComponent("Library-\(UUID().uuidString)")
        await model.switchLibrary(to: newRoot)

        #expect(model.notesDirectory == LibraryLayout(root: newRoot).notesDirectory)
        #expect(model.libraryRootPath == newRoot.path)
        #expect(model.notes.count >= 1)
        #expect(FileManager.default.fileExists(atPath: LibraryLayout(root: newRoot).noteURL(for: firstID).path))
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

        #expect(model.currentNote()?.title == "Untitled")
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

        let firstID = model.currentNoteID!
        model.noteBodyEdited("body of A", for: firstID)
        model.flushNow()

        // Switch to a second note.
        model.createNote()
        let secondID = model.currentNoteID!

        // A delayed callback belonging to the OLD note must be ignored.
        model.noteBodyEdited("body of A (stale)", for: firstID)
        #expect(model.currentBody == "")
        #expect(model.visibleNotes.first { $0.id == secondID }?.body == "")
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

    @Test("Removing one tag leaves neighbouring tags intact")
    func removeTagPreservesSiblings() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.noteBodyEdited("# Notes\n#swift #obsidian", for: model.currentNoteID!)
        model.flushNow()

        model.toggleTagForCurrentNote(Tag(name: "swift"))
        model.flushNow()
        let remaining = model.currentNote()?.body ?? ""
        #expect(!remaining.contains("#swift"))
        // The sibling tag must survive (this regressed to `#other`/`other` logic before).
        #expect(remaining.contains("#obsidian"))
        #expect(model.currentNote()?.tags.contains(Tag(name: "obsidian")) == true)
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
        #expect(model.notes.count == 2)
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

        #expect(model.notes.count == 1)
        model.deleteCurrentNote()
        #expect(model.notes.isEmpty)
        #expect(model.currentNote() == nil)
    }

    @Test("Opening a note keeps the library filter")
    func openPreservesFilter() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.noteBodyEdited("# Alpha\nHello #work", for: model.currentNoteID!)
        model.flushNow()
        model.createNote()
        model.noteBodyEdited("# Beta\nOther", for: model.currentNoteID!)
        model.flushNow()

        let work = Tag(name: "work")
        model.selectTag(work)
        model.searchQuery = "Hello"
        model.performSearch()

        let tagged = try #require(model.notes.first { $0.tags.contains(work) })
        model.open(tagged)

        #expect(model.selectedTag == work)
        #expect(model.searchQuery == "Hello")
        #expect(model.currentNoteID == tagged.id)
    }

    @Test("Creating a note while filtered clears the filter so the note is visible")
    func createNoteClearsFilter() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        model.noteBodyEdited("# Alpha\nHello #work", for: model.currentNoteID!)
        model.flushNow()
        model.selectTag(Tag(name: "work"))
        #expect(model.hasActiveFilter)

        model.createNote()
        #expect(!model.hasActiveFilter)
        #expect(model.currentNote()?.body == "")
        #expect(model.visibleNotes.contains { $0.id == model.currentNoteID })
    }

    @Test("Empty library is seeded with one untitled note on bootstrap")
    func bootstrapSeedsEmptyLibrary() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        #expect(model.notes.count == 1)
        #expect(model.currentNote()?.title == "Untitled")
        #expect(model.currentNote()?.body == "")
    }

    @Test("Sidebar width is clamped to the design range")
    func sidebarWidthClamps() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        model.sidebarWidth = 120
        #expect(model.sidebarWidth == AppTheme.Metric.sidebarMinWidth)
        model.sidebarWidth = 900
        #expect(model.sidebarWidth == AppTheme.Metric.sidebarMaxWidth)
    }

    @Test("focusSearch presents the search field even if the sidebar was hidden")
    func focusSearchPresentsFieldFromHiddenSidebar() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        model.sidebarVisible = false
        model.focusSearch()
        #expect(model.sidebarVisible)
        #expect(model.searchFieldPresented)

        model.closeSearch()
        #expect(!model.searchFieldPresented)
    }

    @Test("Toggle terminal shows and hides the panel")
    func toggleTerminal() throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        #expect(!model.terminalVisible)
        model.toggleTerminal()
        #expect(model.terminalVisible)
        #expect(model.terminalFocusToken == 1)
        model.toggleTerminal()
        #expect(!model.terminalVisible)
        #expect(model.editorFocusToken == 1)
    }

    @Test("Terminal height is clamped to the design range")
    func terminalHeightClamps() throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }

        model.terminalHeight = 10
        #expect(model.terminalHeight == AppTheme.Metric.terminalMinHeight)
        model.terminalHeight = 900
        #expect(model.terminalHeight == AppTheme.Metric.terminalMaxHeight)
    }

    @Test("Word count is cached and follows edits and note switches")
    func wordCountCacheTracksBody() async throws {
        let dir = try makeTempDir()
        let (model, cleanup) = try makeModel(in: dir)
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: dir)
        }
        await model.bootstrap()

        let id = try #require(model.currentNoteID)
        model.noteBodyEdited("one two three", for: id)
        #expect(model.currentWordCount == 3)

        model.noteBodyEdited("one two three four five", for: id)
        #expect(model.currentWordCount == 5)
    }
}

@Suite("FaviconService")
struct FaviconServiceTests {
    @Test("Extracts hosts from markdown links and bare URLs")
    func extractsHosts() {
        let hosts = FaviconService.hosts(
            in: """
                See [GitHub](https://github.com/foo) and https://example.com/x
                Also [docs](example.org/path)
                """)
        #expect(hosts.contains("github.com"))
        #expect(hosts.contains("example.com"))
        #expect(hosts.contains("example.org"))
    }

    @Test("Ignores text that is not a link")
    func ignoresPlainText() {
        let hosts = FaviconService.hosts(in: "hello world, no urls here")
        #expect(hosts.isEmpty)
    }
}

@Suite("ImageStore fingerprint")
struct ImageStoreFingerprintTests {
    @Test("Fingerprint is stable until a paste lands, then changes")
    func fingerprintStability() throws {
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("supersimple-img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let store = ImageStore(appSupport: appSupport)

        // Repeated reads must not change: the wrapper calls this every editor update, and
        // a busy signal would restyle the whole document while typing.
        let before = store.fingerprint()
        #expect(store.fingerprint() == before)

        // A pasted image lands -> the set changed -> fingerprint must change.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        _ = store.savePastedImage(png, ext: "png")
        let after = store.fingerprint()
        #expect(after != before)
    }
}

@Suite("Line delete")
struct LineDeleteTests {
    @Test("paragraphRange covers the whole line including the newline")
    func paragraphRangeCoversLine() {
        let text = "alpha\nbeta\ngamma" as NSString
        let beta = text.range(of: "beta")
        let line = text.paragraphRange(for: beta)
        #expect(text.substring(with: line) == "beta\n")
    }

    @Test("paragraphRange spans every selected line")
    func paragraphRangeSpansSelection() {
        let text = "alpha\nbeta\ngamma" as NSString
        let start = text.range(of: "pha")
        let end = text.range(of: "ga")
        let selection = NSRange(location: start.location, length: NSMaxRange(end) - start.location)
        let line = text.paragraphRange(for: selection)
        #expect(text.substring(with: line) == "alpha\nbeta\ngamma")
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

    @Test("Preview skips headings and blank lines")
    func previewSkipsHeadings() {
        #expect(NoteStats.preview(from: "") == "")
        #expect(NoteStats.preview(from: "# Title\n\n# Another") == "")
        #expect(NoteStats.preview(from: "# Title\n\nThe body starts here") == "The body starts here")
    }

    @Test("Relative timestamps distinguish today, yesterday, and older")
    func relativeTimestamps() {
        let now = Date()
        #expect(
            NoteStats.relativeUpdated(now, now: now).contains(":")
                || NoteStats.relativeUpdated(now, now: now).contains("."))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(NoteStats.relativeUpdated(yesterday, now: now) == "Yesterday")
    }
}

@MainActor
@Suite("ThemeManager")
struct ThemeManagerTests {
    @Test("Explicit light/dark does not wait on the environment color scheme")
    func explicitPreferenceIgnoresEnvironmentScheme() {
        let manager = ThemeManager()
        let previous = manager.preference
        defer { manager.preference = previous }

        manager.preference = .light
        #expect(!manager.isDark(matching: .dark))
        #expect(!manager.isDark(matching: .light))

        manager.preference = .dark
        #expect(manager.isDark(matching: .light))
        #expect(manager.isDark(matching: .dark))
    }

    @Test("setPreferenceImmediately updates preference on the same turn")
    func setPreferenceImmediatelyWrites() {
        let manager = ThemeManager()
        let previous = manager.preference
        defer { manager.preference = previous }

        manager.setPreferenceImmediately(.dark)
        #expect(manager.preference == .dark)
        manager.setPreferenceImmediately(.light)
        #expect(manager.preference == .light)
    }
}

@Suite("SandboxContainerMigration")
struct SandboxContainerMigrationTests {
    @Test("Copies notes out of the sandbox container when the destination is empty")
    func copiesWhenDestinationEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home")
        let destination = root.appendingPathComponent("Support/Supersimple")
        let container = SandboxContainerMigration.containerApplicationSupport(home: home)
        let notes = container.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("# Hello\n".utf8).write(to: notes.appendingPathComponent("note.md"))

        SandboxContainerMigration.migrateIfNeeded(to: destination, home: home)

        let copied = destination.appendingPathComponent("Notes/note.md")
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(try String(contentsOf: copied, encoding: .utf8).contains("Hello"))
    }

    @Test("Leaves an existing unsandboxed library untouched")
    func skipsWhenDestinationHasNotes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home")
        let destination = root.appendingPathComponent("Support/Supersimple")
        let destNotes = destination.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: destNotes, withIntermediateDirectories: true)
        try Data("# Keep\n".utf8).write(to: destNotes.appendingPathComponent("keep.md"))

        let container = SandboxContainerMigration.containerApplicationSupport(home: home)
            .appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try Data("# Old\n".utf8).write(to: container.appendingPathComponent("old.md"))

        SandboxContainerMigration.migrateIfNeeded(to: destination, home: home)

        #expect(FileManager.default.fileExists(atPath: destNotes.appendingPathComponent("keep.md").path))
        #expect(!FileManager.default.fileExists(atPath: destNotes.appendingPathComponent("old.md").path))
    }
}
