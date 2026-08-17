import Foundation
import OSLog
import SupersimpleCore
import SwiftUI

/// Central application state. Owns the in-memory set of notes, the currently
/// edited body, the search index, and drives debounced atomic persistence.
@MainActor
@Observable
final class AppModel {

    // MARK: - Persistence surfaces

    static let log = Logger(subsystem: "com.frinfo702.supersimple", category: "AppModel")

    private let fileManager = NoteFileManager()
    private var searchIndex: NoteSearchIndex?
    private let notesDirectory: URL

    // MARK: - Observable state

    /// All notes known by the app (including the currently edited one).
    private(set) var notes: [Note] = []
    /// The note currently open in the editor.
    var currentNoteID: UUID?
    /// The live body text backed by the editor binding.
    var currentBody: String = ""

    /// Search UI state.
    var searchQuery: String = ""
    var selectedTag: Tag?
    var searchResults: [SearchResult] = []

    /// Whether the sidebar column is shown.
    var sidebarVisible: Bool {
        didSet {
            UserDefaults.standard.set(sidebarVisible, forKey: "com.frinfo702.supersimple.sidebarVisible")
        }
    }

    private var isBootstrapLoaded = false
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private let autosaveDebounce: Duration = .milliseconds(350)

    // MARK: - Init / bootstrap

    init(notesDirectoryOverride: URL? = nil) {
        sidebarVisible =
            UserDefaults.standard.object(forKey: "com.frinfo702.supersimple.sidebarVisible") as? Bool ?? true
        if let override = notesDirectoryOverride {
            notesDirectory = override
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("Supersimple", isDirectory: true)
            notesDirectory = base.appendingPathComponent("Notes", isDirectory: true)
        }
    }

    /// Loads all notes from disk and rebuilds the search index on first use.
    func bootstrap() async {
        guard !isBootstrapLoaded else { return }
        isBootstrapLoaded = true

        let url = notesDirectory
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )

        let started = DispatchTime.now()
        let loaded = loadNotes(from: url)
        notes = loaded
        await rebuildSearchIndex(notes: loaded)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Self.log.info("Bootstrapped \(loaded.count) notes in \(elapsed, format: .fixed(precision: 1)) ms")

        resumeLastSelection()
    }

    private func loadNotes(from directory: URL) -> [Note] {
        let urls = fileManager.existingNoteURLs(in: directory)
        var loaded: [Note] = []
        for fileURL in urls {
            guard let text = try? fileManager.read(at: fileURL),
                let doc = try? FrontmatterCodec.decode(text)
            else { continue }
            loaded.append(note(from: doc))
        }
        return loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func note(from doc: MarkdownDocument) -> Note {
        Note(
            id: doc.metadata.id,
            createdAt: doc.metadata.createdAt,
            updatedAt: doc.metadata.updatedAt,
            tags: doc.metadata.tags,
            body: doc.body
        )
    }

    private func rebuildSearchIndex(notes: [Note]) async {
        let dbURL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Supersimple/search.db")

        let index =
            (try? NoteSearchIndex(databaseURL: dbURL))
            ?? (try? NoteSearchIndex(
                databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "supersimple-search-\(UUID().uuidString).db")))
        searchIndex = index
        try? index?.rebuild(notes: notes)
    }

    private func resumeLastSelection() {
        if let last = UserDefaults.standard.string(forKey: "com.frinfo702.supersimple.lastNote"),
            let id = UUID(uuidString: last),
            let note = notes.first(where: { $0.id == id })
        {
            select(note)
        }
    }

    // MARK: - Selection

    func currentNote() -> Note? {
        guard let id = currentNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    /// Switches the editor to a note, flushing any pending edits first.
    func select(_ note: Note) {
        flushNow()
        currentNoteID = note.id
        currentBody = note.body
        selectedTag = nil
        searchQuery = ""
        UserDefaults.standard.set(note.id.uuidString, forKey: "com.frinfo702.supersimple.lastNote")
    }

    // MARK: - Create / delete

    func createNote() {
        flushNow()
        var note = Note()
        // A fresh note starts with the title-markdown so it displays a real name.
        note.body = "# New Note"
        notes.insert(note, at: 0)
        select(note)
        persist(note)
    }

    func deleteNote(_ note: Note) {
        flushNow()
        guard let url = fileURL(for: note.id) else { return }
        fileManager.delete(at: url)
        try? searchIndex?.delete(noteID: note.id)

        if currentNoteID == note.id {
            currentNoteID = nil
            currentBody = ""
        }
        notes.removeAll { $0.id == note.id }
    }

    // MARK: - Editing

    /// Called by the editor binding on every body change.
    func noteBodyEdited(_ newBody: String) {
        guard let id = currentNoteID else { return }
        guard newBody != currentBody else { return }

        currentBody = newBody
        isDirty = true

        // Update in-memory thumbnail for the sidebar instantly.
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].body = newBody
            notes[idx].updatedAt = Date()
        }

        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autosaveDebounce ?? .milliseconds(350))
            if !Task.isCancelled {
                self?.saveNow()
            }
        }
    }

    func flushNow() {
        guard isDirty else { return }
        saveNow()
    }

    /// Immediate, unconditional persistence of the current edit.
    func saveNowPublic() {
        saveNow()
    }

    private func saveNow() {
        guard currentNoteID != nil, isDirty else { return }
        defer { isDirty = false }

        guard var note = currentNote() else { return }
        note.body = currentBody
        note.updatedAt = Date()
        note.tags = TagNormalizer.extractTags(from: currentBody)

        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        }
        persist(note)
    }

    /// Applies a tag by editing the note body (append `#tag` when absent).
    func toggleTagForCurrentNote(_ tag: Tag) {
        guard let note = currentNote() else { return }
        if note.tags.contains(tag) {
            // Remove the #tag token from the body if it exists inline.
            let tokenToRemove = "#" + tag.name
            currentBody = currentBody.replacingOccurrences(
                of: tokenToRemove, with: "", options: [.anchored, .literal]
            )
            // Strip late occurrences too, preserving line structure.
            currentBody =
                currentBody
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    line.replacingOccurrences(of: tokenToRemove, with: "")
                }
                .joined(separator: "\n")
        } else {
            if currentBody.isEmpty {
                currentBody = "# \(tag.name)"
            } else {
                currentBody += "\n#\(tag.name)"
            }
        }
        noteBodyEdited(currentBody)
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL? {
        fileManager.fileURL(for: id, notesDirectory: notesDirectory)
    }

    private func persist(_ note: Note) {
        let doc = FrontmatterCodec.document(note: note)
        guard let url = fileURL(for: note.id) else { return }
        do {
            try fileManager.write(doc.fullText, to: url)
            try searchIndex?.upsert(note: note)
        } catch {
            Self.log.error("Failed to persist note \(note.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Search

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard let index = searchIndex, !query.isEmpty else {
            searchResults = []
            return
        }
        var tags = Set<Tag>()
        if let selectedTag { tags.insert(selectedTag) }
        let started = DispatchTime.now()
        let results = index.search(query, tags: tags)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Self.log.info(
            "Search '\(query, privacy: .public)' returned \(results.count) in \(elapsed, format: .fixed(precision: 1)) ms"
        )
        searchResults = results
    }

    /// The ordered list shown in the sidebar: search hits when searching,
    /// otherwise the tag-filtered set of notes.
    var visibleNotes: [Note] {
        if !searchQuery.isEmpty {
            let ids = Set(searchResults.map(\.noteID))
            return notes.filter { ids.contains($0.id) }
        }
        if let selectedTag {
            return notes.filter { $0.tags.contains(selectedTag) }
        }
        return notes
    }

    /// All tags across every note, sorted with counts.
    var allTags: [(tag: Tag, count: Int)] {
        var counts: [Tag: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    func openSearchResult(_ result: SearchResult) {
        guard let note = notes.first(where: { $0.id == result.noteID }) else { return }
        select(note)
    }

    func closeSearch() {
        searchQuery = ""
        searchResults = []
    }

    /// Called on app termination to guarantee the last edits are on disk.
    func shutdown() {
        flushNow()
        searchIndex = nil
    }
}
