import AppKit
import Foundation
import MarkdownEngine
import OSLog
import SupersimpleCore
import SwiftUI
import UniformTypeIdentifiers

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
    private let appSupportURL: URL
    private let userDefaults: UserDefaults
    /// Stores pasted images and serves them to the editor's `![[name]]` embeds.
    let imageStore: ImageStore
    /// Fetches and caches site favicons for links.
    let faviconService = FaviconService()

    // MARK: - Observable state

    /// All notes known by the app (including the currently edited one).
    private(set) var notes: [Note] = []
    /// The note currently open in the editor.
    var currentNoteID: UUID?
    /// The live body text backed by the editor binding.
    var currentBody: String = ""

    /// Search UI state. Independent of the open note; opening a row does not clear this.
    var searchQuery: String = ""
    var selectedTag: Tag?
    var searchResults: [SearchResult] = []

    /// Confirmation target for the delete dialog. Independent of the current selection
    /// so a context-menu delete can target a row that is not open.
    var notePendingDelete: Note?

    /// Whether the sidebar column is shown.
    var sidebarVisible: Bool {
        didSet {
            userDefaults.set(sidebarVisible, forKey: "sidebarVisible")
        }
    }

    /// User-resized library column width, clamped to the design range.
    var sidebarWidth: CGFloat {
        didSet {
            let clamped = Self.clampSidebarWidth(sidebarWidth)
            if clamped != sidebarWidth {
                sidebarWidth = clamped
                return
            }
            userDefaults.set(Double(clamped), forKey: "sidebarWidth")
        }
    }

    /// Whether the libghostty login-shell panel is shown.
    var terminalVisible: Bool {
        didSet {
            userDefaults.set(terminalVisible, forKey: "terminalVisible")
        }
    }

    /// User-resized terminal panel height, clamped to the design range.
    var terminalHeight: CGFloat {
        didSet {
            let clamped = Self.clampTerminalHeight(terminalHeight)
            if clamped != terminalHeight {
                terminalHeight = clamped
                return
            }
            userDefaults.set(Double(clamped), forKey: "terminalHeight")
        }
    }

    /// Bumped to move keyboard focus into the terminal surface.
    private(set) var terminalFocusToken: UInt = 0

    /// True while the library search field should stay on screen (empty query included).
    private(set) var searchFieldPresented = false
    /// Bumped to move keyboard focus into the library search field.
    private(set) var searchFocusToken: UInt = 0
    /// Bumped to move keyboard focus into the editor.
    private(set) var editorFocusToken: UInt = 0

    private var isBootstrapLoaded = false
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private let autosaveDebounce: Duration = .milliseconds(350)
    /// Production storage only — tests pass directory overrides and must not
    /// copy the user's real sandbox container into the temp fixture.
    private let migratesSandboxContainer: Bool

    // MARK: - Init / bootstrap

    /// - Parameters:
    ///   - notesDirectoryOverride: Redirects the notes directory (used by tests).
    ///   - appSupportURLOverride: Redirects the search DB location (used by tests).
    ///   - userDefaults: Isolated defaults for tests. Production uses `.standard`
    ///     so last-note / sidebar state actually reach disk.
    init(
        notesDirectoryOverride: URL? = nil,
        appSupportURLOverride: URL? = nil,
        userDefaults: UserDefaults? = nil
    ) {
        if let userDefaults {
            self.userDefaults = userDefaults
        } else if ProcessInfo.processInfo.environment["SUPERSIMPLE_UI_TEST"] == "1" {
            let suite = "com.frinfo702.supersimple.uitest"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            self.userDefaults = defaults
        } else {
            self.userDefaults = .standard
        }
        sidebarVisible = self.userDefaults.object(forKey: "sidebarVisible") as? Bool ?? true
        if let storedWidth = self.userDefaults.object(forKey: "sidebarWidth") as? Double {
            sidebarWidth = Self.clampSidebarWidth(CGFloat(storedWidth))
        } else {
            sidebarWidth = AppTheme.Metric.sidebarWidth
        }
        terminalVisible = self.userDefaults.object(forKey: "terminalVisible") as? Bool ?? false
        if let storedHeight = self.userDefaults.object(forKey: "terminalHeight") as? Double {
            terminalHeight = Self.clampTerminalHeight(CGFloat(storedHeight))
        } else {
            terminalHeight = AppTheme.Metric.terminalHeight
        }

        migratesSandboxContainer = notesDirectoryOverride == nil && appSupportURLOverride == nil

        if let override = notesDirectoryOverride {
            notesDirectory = override
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("Supersimple", isDirectory: true)
            notesDirectory = base.appendingPathComponent("Notes", isDirectory: true)
        }

        if let override = appSupportURLOverride {
            appSupportURL = override
        } else {
            appSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0].appendingPathComponent("Supersimple", isDirectory: true)
        }
        imageStore = ImageStore(appSupport: appSupportURL)
    }

    /// Paste handler for the editor: saves a pasted image and returns the `![[name]]`
    /// embed to insert, or `nil` to fall through to the default text paste.
    func pasteImageHandler(_ pasteboard: NSPasteboard) -> String? {
        guard let png = PasteboardImageReader.imageData(from: pasteboard) else { return nil }
        guard let name = imageStore.savePastedImage(png, ext: "png") else { return nil }
        return "![[\(name)]]"
    }

    /// Loads all notes from disk and rebuilds the search index on first use.
    /// Heavy file I/O and index construction are moved off the main actor.
    func bootstrap() async {
        guard !isBootstrapLoaded else { return }
        isBootstrapLoaded = true

        if migratesSandboxContainer {
            SandboxContainerMigration.migrateIfNeeded(to: appSupportURL)
        }

        let directory = notesDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appSupport = appSupportURL

        let started = DispatchTime.now()
        let loaded = await Self.loadNotes(from: directory, fileManager: fileManager)
        notes = loaded
        searchIndex = await Self.rebuildIndex(notes: loaded, appSupport: appSupport)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Self.log.info("Bootstrapped \(loaded.count) notes in \(elapsed, format: .fixed(precision: 1)) ms")

        resumeLastSelection()
        if notes.isEmpty {
            createNote()
        } else if currentNoteID == nil {
            open(notes[0])
        }
    }

    /// Reads and decodes every note file off the main actor.
    private nonisolated static func loadNotes(
        from directory: URL,
        fileManager: NoteFileManager
    ) async -> [Note] {
        let urls = fileManager.existingNoteURLs(in: directory)
        var loaded: [Note] = []
        for fileURL in urls {
            guard let text = try? fileManager.read(at: fileURL),
                let doc = try? FrontmatterCodec.decode(text)
            else { continue }
            loaded.append(
                Note(
                    id: doc.metadata.id,
                    createdAt: doc.metadata.createdAt,
                    updatedAt: doc.metadata.updatedAt,
                    tags: doc.metadata.tags,
                    body: doc.body,
                    extraFields: doc.metadata.extraFields
                )
            )
        }
        return loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private nonisolated static func rebuildIndex(
        notes: [Note],
        appSupport: URL
    ) async -> NoteSearchIndex? {
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("search.db")
        guard let index = try? NoteSearchIndex(databaseURL: dbURL) else { return nil }
        try? index.rebuild(notes: notes)
        return index
    }

    private func resumeLastSelection() {
        if let last = userDefaults.string(forKey: "lastNote"),
            let id = UUID(uuidString: last),
            let note = notes.first(where: { $0.id == id })
        {
            open(note)
        }
    }

    // MARK: - Selection

    func currentNote() -> Note? {
        guard let id = currentNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    /// Opens a note in the editor without touching the library filter.
    func open(_ note: Note) {
        if currentNoteID == note.id {
            currentBody = note.body
            return
        }
        flushNow()
        cancelPendingSave()
        currentNoteID = note.id
        currentBody = note.body
        userDefaults.set(note.id.uuidString, forKey: "lastNote")
        prefetchFavicons(in: note.body)
    }

    /// Backwards-compatible alias for ``open(_:)``.
    func select(_ note: Note) {
        open(note)
    }

    var hasActiveFilter: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || selectedTag != nil
    }

    func clearLibraryFilter() {
        searchQuery = ""
        searchResults = []
        selectedTag = nil
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func focusSearch() {
        if !sidebarVisible {
            sidebarVisible = true
        }
        searchFieldPresented = true
        searchFocusToken &+= 1
    }

    func focusEditor() {
        editorFocusToken &+= 1
    }

    func toggleTerminal() {
        terminalVisible.toggle()
        if terminalVisible {
            terminalFocusToken &+= 1
        } else {
            focusEditor()
        }
    }

    func requestDelete(_ note: Note? = nil) {
        notePendingDelete = note ?? currentNote()
    }

    /// Extracts hostnames from a body and prefetches their favicons.
    func prefetchFavicons(in body: String) {
        let hosts = FaviconService.hosts(in: body)
        if !hosts.isEmpty {
            faviconService.prefetch(hosts: Array(hosts))
        }
    }

    // MARK: - Create / delete

    func createNote() {
        flushNow()
        if hasActiveFilter {
            clearLibraryFilter()
        }
        let note = Note()
        notes.insert(note, at: 0)
        open(note)
        persist(note)
    }

    func deleteNote(_ note: Note) {
        flushNow()
        guard let url = fileURL(for: note.id) else { return }
        do {
            try fileManager.delete(at: url)
        } catch {
            Self.log.error("Failed to delete note \(note.id): \(error.localizedDescription, privacy: .public)")
            return
        }
        try? searchIndex?.delete(noteID: note.id)

        if currentNoteID == note.id {
            currentNoteID = nil
            currentBody = ""
        }
        notes.removeAll { $0.id == note.id }
    }

    /// Deletes the currently selected note, if any.
    func deleteCurrentNote() {
        guard let note = currentNote() else { return }
        deleteNote(note)
    }

    // MARK: - Editing

    /// Applies an edit received from the editor, but only when it belongs to the
    /// currently selected note. The editor defers its binding sync onto the main
    /// queue, so an outgoing note's delayed callback must not clobber the new note.
    func noteBodyEdited(_ newBody: String, for noteID: UUID) {
        guard currentNoteID == noteID else { return }
        guard newBody != currentBody else { return }
        replaceCurrentBody(newBody)
    }

    /// Unconditionally replaces the current body (used by tag editing and the caller
    /// above). Marks dirty, updates the in-memory thumbnail, and schedules autosave.
    private func replaceCurrentBody(_ newBody: String) {
        guard let id = currentNoteID else { return }
        currentBody = newBody
        isDirty = true

        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx].body = newBody
            notes[idx].updatedAt = Date()
        }
        prefetchFavicons(in: newBody)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = Task { [weak self, delay = autosaveDebounce] in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled {
                self?.saveNowPublic()
            }
        }
        saveTask = task
    }

    private func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// Save Now: immediate, unconditional persistence of the current edit.
    func saveNowPublic() {
        guard let id = currentNoteID, isDirty else { return }

        guard var note = currentNote() else { return }
        note.body = currentBody
        note.updatedAt = Date()
        note.tags = TagNormalizer.extractTags(from: currentBody)

        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx] = note
        }
        // Only clear dirty when persistence actually succeeded, so a failed write can
        // be retried with ⌘S instead of being silently marked clean.
        if persist(note) {
            isDirty = false
        }
    }

    /// Applies a tag by editing the note body (append `#tag` when absent).
    func toggleTagForCurrentNote(_ tag: Tag) {
        guard let note = currentNote() else { return }

        var result = currentBody
        if note.tags.contains(tag) {
            // Remove whole-word `#tag` occurrences without damaging `#tagfoo`.
            result = removeTag(tag.name, from: result)
        } else {
            if result.isEmpty {
                result = "# \(tag.name)"
            } else {
                result += "\n#\(tag.name)"
            }
        }
        // `replaceCurrentBody` bypasses the equality guard, so this always persists.
        replaceCurrentBody(result)
    }

    private func removeTag(_ name: String, from text: String) -> String {
        let token = "#" + name
        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            let cleaned = removeToken(token, from: line)
            // Avoid leaving a dangling `#` at the boundary of a longer word/word.
            line = cleaned.replacingOccurrences(of: " #", with: " ")
            // Drop now-empty lines that consisted only of the tag.
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            } else {
                lines.append(line)
            }
        }
        // Remove the whole token when it is the first thing on the line.
        return lines.joined(separator: "\n")
    }

    private func removeToken(_ token: String, from line: String) -> String {
        // Match `#name` preceded by start-of-line, whitespace, or punctuation,
        // and not followed by another alphanumeric/`_`/`-` (would extend the word).
        let pattern = "(^|[\\s\\W])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}_-])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL? {
        fileManager.fileURL(for: id, notesDirectory: notesDirectory)
    }

    /// Persists a note. Returns `true` when the file write succeeded. A search
    /// index failure is logged but does not discard the document on disk.
    @discardableResult
    func persist(_ note: Note) -> Bool {
        let doc = FrontmatterCodec.document(note: note)
        guard let url = fileURL(for: note.id) else { return true }
        do {
            try fileManager.write(doc.fullText, to: url)
        } catch {
            Self.log.error("Failed to persist note \(note.id): \(error.localizedDescription, privacy: .public)")
            return false
        }
        do {
            try searchIndex?.upsert(note: note)
        } catch {
            Self.log.error("Search index update failed for \(note.id): \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    /// Immediate, unconditional persistence regardless of dirty flag (used by ⌘S and
    /// before switching notes).
    func flushNow() {
        if isDirty {
            saveNowPublic()
        }
    }

    // MARK: - Search

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let index = searchIndex else {
            searchResults = []
            return
        }
        var tags = Set<Tag>()
        if let selectedTag { tags.insert(selectedTag) }

        let givenQuery = query
        let gaveTags = tags
        Task { @MainActor in
            // Run the (I/O + SQLite) query off the main actor; the detached closure only
            // touches Sendable values.
            let started = DispatchTime.now()
            let results = await Task.detached(priority: .userInitiated) { [index] in
                (try? index.search(givenQuery, tags: gaveTags)) ?? []
            }.value
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            searchResults = results
            Self.log.info(
                "Search '\(givenQuery, privacy: .private)' returned \(results.count) in \(elapsed, format: .fixed(precision: 1)) ms"
            )
        }
    }

    func selectTag(_ tag: Tag?) {
        withAnimation(.easeOut(duration: 0.12)) {
            selectedTag = (self.selectedTag == tag) ? nil : tag
        }
        // If a search is active, incorporate the tag filter immediately.
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            performSearch()
        }
    }

    /// The ordered list shown in the sidebar: search hits when searching (kept in
    /// relevance order), otherwise the tag-filtered set of notes.
    var visibleNotes: [Note] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            // Preserve search-score order rather than library order.
            let order = searchResults.map(\.noteID)
            let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
            return order.compactMap { byID[$0] }
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
        open(note)
    }

    /// Recency buckets for the unfiltered (or tag-filtered) library. Search hits
    /// stay in relevance order and are not grouped.
    var groupedVisibleNotes: [(group: NoteRecencyGroup, notes: [Note])] {
        guard !isSearching else { return [] }
        var buckets: [NoteRecencyGroup: [Note]] = [:]
        for note in visibleNotes {
            buckets[NoteRecencyGroup.group(for: note.updatedAt), default: []].append(note)
        }
        return NoteRecencyGroup.allCases.compactMap { group in
            guard let notes = buckets[group], !notes.isEmpty else { return nil }
            return (group, notes)
        }
    }

    static func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, AppTheme.Metric.sidebarMinWidth), AppTheme.Metric.sidebarMaxWidth)
    }

    static func clampTerminalHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, AppTheme.Metric.terminalMinHeight), AppTheme.Metric.terminalMaxHeight)
    }

    func closeSearch() {
        searchQuery = ""
        searchResults = []
        searchFieldPresented = false
    }

    // MARK: - Export / import

    func exportMarkdown(for note: Note) -> String {
        note.body
    }

    func exportFilename(for note: Note) -> String {
        NoteStats.sanitizedFilename(note.title) + ".md"
    }

    func writeExport(of note: Note, to url: URL) throws {
        try exportMarkdown(for: note).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Presents a save panel and writes the current note as a `.md` file.
    func presentExportPanel() {
        flushNow()
        guard let note = currentNote() else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = exportFilename(for: note)
        panel.title = "Export Note"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try self.writeExport(of: note, to: url)
                } catch {
                    Self.log.error("Failed to export note: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Presents an open panel and imports each chosen Markdown file as a new note.
    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.title = "Import Notes"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    do {
                        try self.importNote(from: url)
                    } catch {
                        Self.log.error(
                            "Failed to import \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }
    }

    /// Creates a new note from a Markdown file. Always assigns a fresh id so
    /// importing a previously-exported file cannot collide with an existing note.
    @discardableResult
    func importNote(from url: URL) throws -> Note {
        flushNow()
        let text = try String(contentsOf: url, encoding: .utf8)
        let doc = try FrontmatterCodec.decode(text)
        var note = Note()
        note.body = doc.body
        note.tags = TagNormalizer.extractTags(from: note.body)
        notes.insert(note, at: 0)
        if hasActiveFilter {
            clearLibraryFilter()
        }
        open(note)
        persist(note)
        return note
    }

    /// Called on app termination to guarantee the last edits are on disk.
    /// Runs synchronously on the main actor so pending edits are flushed even when
    /// no window/view is alive.
    func shutdown() {
        cancelPendingSave()
        if isDirty {
            saveNowPublic()
        }
        searchIndex = nil
    }
}
