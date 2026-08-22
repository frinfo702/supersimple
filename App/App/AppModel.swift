import AppKit
import Foundation
import MarkdownEngine
import OSLog
import SupersimpleCore
import SwiftUI
import UniformTypeIdentifiers

struct ExternalNoteConflict: Identifiable {
    let noteID: UUID
    let diskNote: Note?
    let diskRecord: FileRecord?

    var id: UUID { noteID }
}

private struct DeletedNoteUndo {
    let note: Note
    let file: TrashedNoteFile
    let index: Int
    let wasSelected: Bool
}

/// Central application state. Owns the in-memory set of notes, the currently
/// edited body, the search index, and drives debounced atomic persistence.
@MainActor
@Observable
final class AppModel {

    // MARK: - Persistence surfaces

    static let log = Logger(subsystem: "com.frinfo702.supersimple", category: "AppModel")

    private let fileManager = NoteFileManager()
    private var repository: NoteRepository
    /// Last known on-disk revision for each loaded note. Saves must match this record.
    private var fileRecordsByID: [UUID: FileRecord] = [:]
    /// Last external revision already handled for a note whose local revision cannot yet
    /// be advanced (for example, while an unsaved edit is awaiting conflict resolution).
    /// This prevents repeated directory events from announcing the same disk contents.
    private var observedExternalRevisionByID: [UUID: String] = [:]
    private var searchIndex: NoteSearchIndex?
    /// Directory of `.md` note files. Skewed toward a user-chosen library root, but
    /// defaults (and stays backward compatible) with `Application Support/Supersimple/Notes`.
    private(set) var notesDirectory: URL
    private let appSupportURL: URL
    private let userDefaults: UserDefaults
    private let libraryChangeMonitor = LibraryChangeMonitor()
    /// Remaining folder-library layout for the current notes root.
    var libraryLayout: LibraryLayout { LibraryLayout(root: notesDirectory.deletingLastPathComponent()) }
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
    /// Cached word count for the current body, so the status overlay does not re-scan the
    /// whole document on every SwiftUI recompute.
    private(set) var currentWordCount: Int = 0
    private var wordCountCache: Int = 0 {
        didSet {
            if wordCountCache != currentWordCount {
                currentWordCount = wordCountCache
            }
        }
    }

    /// Search UI state. Independent of the open note; opening a row does not clear this.
    var searchQuery: String = ""
    var selectedTag: Tag?
    var searchResults: [SearchResult] = []

    /// Global search palette state. Kept separate from the sidebar filter so opening
    /// Command-K never destroys the user's current library view.
    var commandPalettePresented = false
    var commandPaletteQuery = ""
    var commandPaletteSelectedTag: Tag?
    var commandPaletteResults: [SearchResult] = []

    /// In-note find state. Match ranges are owned by MarkdownEngine; the app only
    /// stores the query, current result, and count displayed in the floating bar.
    var noteFindPresented = false
    var noteFindQuery = ""
    private(set) var noteFindCurrentIndex = 0
    private(set) var noteFindMatchCount = 0

    /// Confirmation target for the delete dialog. Independent of the current selection
    /// so a context-menu delete can target a row that is not open.
    var notePendingDelete: Note?

    /// Recoverable deletion and external-edit state shown by the main window.
    private var deletedNoteUndo: DeletedNoteUndo?
    private(set) var deletedNoteUndoTitle: String?
    var externalNoteConflict: ExternalNoteConflict?
    private(set) var externalChangeMessage: String?

    /// Notes fixed above the recency groups in the sidebar.
    private(set) var pinnedNoteIDs: Set<UUID>

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
    /// Bumped to focus the global Command-K search field.
    private(set) var commandPaletteFocusToken: UInt = 0
    /// Bumped to focus the in-note Command-F search field.
    private(set) var noteFindFocusToken: UInt = 0

    private var isBootstrapLoaded = false
    private var saveTask: Task<Void, Never>?
    /// IDs of notes with edits that have not yet been durably persisted. Per-note (not a
    /// single global flag) so a failed save on one note can never mark a *different* note
    /// as clean, and dirty state follows the note across selection switches.
    private var dirtyNoteIDs: Set<UUID> = []
    /// Monotonic token so a slow older search cannot overwrite a newer one's results.
    private var searchGeneration: UInt = 0
    private var paletteSearchGeneration: UInt = 0
    private var librarySearchTask: Task<Void, Never>?
    private var paletteSearchTask: Task<Void, Never>?
    private var noteFindRefreshTask: Task<Void, Never>?
    private var externalRefreshTask: Task<Void, Never>?
    private var deletionUndoTask: Task<Void, Never>?
    private var externalMessageTask: Task<Void, Never>?
    private let autosaveDebounce: Duration = .milliseconds(350)
    private let searchDebounce: Duration = .milliseconds(90)
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
        let pinnedStrings = self.userDefaults.stringArray(forKey: Self.pinnedNoteIDsKey) ?? []
        pinnedNoteIDs = Set(pinnedStrings.compactMap(UUID.init(uuidString:)))

        migratesSandboxContainer = notesDirectoryOverride == nil && appSupportURLOverride == nil

        if let override = appSupportURLOverride {
            appSupportURL = override
        } else {
            appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Supersimple", isDirectory: true)
        }

        let initialNotesDirectory: URL
        if let override = notesDirectoryOverride {
            initialNotesDirectory = override
        } else if let stored = self.userDefaults.string(forKey: Self.libraryRootKey), !stored.isEmpty {
            // A user-chosen library folder (iCloud Drive, mounted volume, …).
            initialNotesDirectory = LibraryLayout(root: URL(fileURLWithPath: stored, isDirectory: true)).notesDirectory
        } else {
            // Default: the classic Application Support location.
            initialNotesDirectory = LibraryLayout(root: appSupportURL).notesDirectory
        }
        notesDirectory = initialNotesDirectory
        let initialLayout = LibraryLayout(root: initialNotesDirectory.deletingLastPathComponent())
        repository = NoteRepository(layout: initialLayout, fileManager: fileManager)
        imageStore = ImageStore(imagesDirectory: initialLayout.attachmentsDirectory)
    }

    // MARK: - Library location

    /// UserDefaults key storing a user-chosen library root folder.
    private static let libraryRootKey = "libraryRootPath"
    private static let pinnedNoteIDsKey = "pinnedNoteIDs"

    /// The library root the user actively chose (or `nil` for the default location).
    var libraryRootPath: String? {
        userDefaults.string(forKey: Self.libraryRootKey)
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
        await loadLibrary()
    }

    /// (Re)loads the current `notesDirectory` into memory and rebuilds the index. Also
    /// called after the user switches the library folder.
    @MainActor
    @discardableResult
    private func loadLibrary(resetSelection: Bool = false) async -> Bool {
        libraryChangeMonitor.stop()
        externalRefreshTask?.cancel()
        externalRefreshTask = nil
        let directory = notesDirectory
        let root = directory.deletingLastPathComponent()
        // A persisted external location must not be recreated when its volume is absent.
        if libraryRootPath != nil, !FileManager.default.fileExists(atPath: root.path) {
            Self.log.error("Library root is unavailable at \(root.path, privacy: .public)")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try libraryLayout.createIfNeeded()
        } catch {
            Self.log.error(
                "Library unavailable at \(directory.path): \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Move pre-folder-library pasted images into the active library once. The source
        // remains untouched, so an interrupted migration can be retried safely.
        let legacyImages = appSupportURL.appendingPathComponent("Images", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyImages.path),
            legacyImages.standardizedFileURL != libraryLayout.attachmentsDirectory.standardizedFileURL
        {
            let migrator = LibraryMigrator()
            do {
                let report = try await migrator.migrateAttachments(from: legacyImages, layout: libraryLayout)
                if !report.problems.isEmpty {
                    Self.log.error("Legacy attachment migration reported \(report.problems.count) problem(s)")
                }
            } catch {
                Self.log.error(
                    "Legacy attachment migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let appSupport = appSupportURL

        let started = DispatchTime.now()
        let load: LoadOutcome
        do {
            load = try await Self.loadNotes(from: directory, fileManager: fileManager)
        } catch {
            // The notes directory is unavailable (mount gone, permission revoked). This is
            // NOT an empty library: do not fabricate a note the user will lose.
            Self.log.error(
                "Library unavailable at \(directory.path): \(error.localizedDescription, privacy: .public)")
            return false
        }
        if resetSelection {
            cancelPendingSave()
            currentNoteID = nil
            currentBody = ""
            wordCountCache = 0
            dirtyNoteIDs.removeAll()
            clearLibraryFilter()
        }
        notes = load.notes
        fileRecordsByID = load.fileRecords
        observedExternalRevisionByID.removeAll()
        searchIndex = await Self.rebuildIndex(notes: load.notes, appSupport: appSupport)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Self.log.info("Bootstrapped \(load.notes.count) notes in \(elapsed, format: .fixed(precision: 1)) ms")

        resumeLastSelection()
        if notes.isEmpty {
            createNote()
        } else if currentNoteID == nil {
            open(notes[0])
        }
        startExternalChangeMonitoring()
        return true
    }

    // MARK: - Library switching

    /// Presents a folder picker and, on confirmation, migrates the current notes into the
    /// chosen folder (as a browsable library) before switching to it.
    func chooseLibraryFolder() {
        guard flushNow() else {
            Self.log.error("Refusing to change library: unsaved edits could not be flushed.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.title = "Choose Notes Folder"
        panel.message = "supersimple will store your notes as plain .md files in this folder's Notes/ subfolder."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self.switchLibrary(to: url)
            }
        }
    }

    /// Migrates notes (+ pasted images) into a new root and switches the library there.
    @MainActor
    @discardableResult
    func switchLibrary(to root: URL) async -> Bool {
        guard flushNow() else {
            Self.log.error("Refusing to change library: unsaved edits could not be flushed.")
            presentLibraryError("The current note could not be saved.")
            return false
        }

        let layout = LibraryLayout(root: root)
        do {
            try layout.createIfNeeded()
        } catch {
            Self.log.error("Could not create library at \(root.path): \(error.localizedDescription, privacy: .public)")
            presentLibraryError("The folder could not be created.")
            return false
        }

        let migrator = LibraryMigrator()
        let sourceNotes = notesDirectory
        let sourceImages = libraryLayout.attachmentsDirectory
        let report: MigrationReport
        do {
            report = try await migrator.migrate(
                notesSource: sourceNotes,
                imagesSource: sourceImages,
                layout: layout
            )
        } catch {
            Self.log.error("Library migration failed: \(error.localizedDescription, privacy: .public)")
            presentLibraryError("The notes could not be copied to that folder.")
            return false
        }
        migrationReport = report

        let previousDirectory = notesDirectory
        let previousRepository = repository
        notesDirectory = layout.notesDirectory
        repository = NoteRepository(layout: layout, fileManager: fileManager)
        guard await loadLibrary(resetSelection: true) else {
            notesDirectory = previousDirectory
            repository = previousRepository
            presentLibraryError("The selected library could not be opened.")
            return false
        }
        imageStore.useImagesDirectory(layout.attachmentsDirectory)
        userDefaults.set(root.path, forKey: Self.libraryRootKey)
        return true
    }

    /// Reverts to the built-in Application Support location (migrating the current notes).
    @MainActor
    func useDefaultLibraryLocation() async {
        guard libraryRootPath != nil else { return }
        if await switchLibrary(to: appSupportURL) {
            userDefaults.removeObject(forKey: Self.libraryRootKey)
        }
    }

    func revealLibraryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([notesDirectory])
    }

    enum NotePathStyle {
        case relative
        case absolute
    }

    /// Returns the actual on-disk path when a loaded note kept a non-canonical filename.
    /// Relative paths are rooted at the selected library folder.
    func pathForCopying(_ note: Note, style: NotePathStyle) -> String {
        let fileURL = (fileRecordsByID[note.id]?.url ?? libraryLayout.noteURL(for: note.id))
            .standardizedFileURL
        if case .absolute = style { return fileURL.path }

        let rootPath = libraryLayout.root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard fileURL.path.hasPrefix(prefix) else { return fileURL.lastPathComponent }
        return String(fileURL.path.dropFirst(prefix.count))
    }

    func copyPath(of note: Note, style: NotePathStyle) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pathForCopying(note, style: style), forType: .string)
    }

    /// Latest result of a library migration, surfaced in Settings.
    private(set) var migrationReport: MigrationReport?

    private func presentLibraryError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Library Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Result of a load, keeping "empty" (valid) distinct from "unavailable" (an error).
    private struct LoadOutcome {
        var notes: [Note]
        var fileRecords: [UUID: FileRecord]
        var duplicateIDsEncountered: Int
    }

    /// Reads and decodes every note file off the main actor. Deduplicates by ID (the
    /// file that sorts last by `updatedAt` wins) so duplicate frontmatter UUIDs cannot
    /// crash searches that join by an assumed-unique ID dictionary.
    private nonisolated static func loadNotes(
        from directory: URL,
        fileManager: NoteFileManager
    ) async throws -> LoadOutcome {
        let urls = try fileManager.enumerateNoteURLs(in: directory)
        var byID: [UUID: (note: Note, record: FileRecord?)] = [:]
        for fileURL in urls {
            guard let text = try? fileManager.read(at: fileURL),
                let doc = try? FrontmatterCodec.decode(text)
            else { continue }
            let note = Note(
                id: doc.metadata.id,
                createdAt: doc.metadata.createdAt,
                updatedAt: doc.metadata.updatedAt,
                tags: doc.metadata.tags,
                body: doc.body,
                extraFields: doc.metadata.extraFields
            )
            let record = fileManager.fileRecord(at: fileURL)
            if let existing = byID[note.id], existing.note.updatedAt >= note.updatedAt {
                continue
            }
            byID[note.id] = (note, record)
        }
        let loaded = byID.values.sorted { $0.note.updatedAt > $1.note.updatedAt }
        var records: [UUID: FileRecord] = [:]
        for value in loaded {
            if let record = value.record { records[value.note.id] = record }
        }
        return LoadOutcome(
            notes: loaded.map(\.note),
            fileRecords: records,
            duplicateIDsEncountered: urls.count - loaded.count
        )
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
            wordCountCache = NoteStats.wordCount(note.body)
            return
        }
        // Persist the outgoing edit first. If it cannot be written (disk full, revoked
        // permission, unmounted volume) we must NOT switch away, otherwise the edit is
        // orphaned and later clobbered by a save of the new note.
        if !flushNow() {
            Self.log.error(
                "Blocked switching to \(note.title): could not persist unsaved edits.")
            return
        }
        dismissNoteFind(focusEditor: false)
        cancelPendingSave()
        currentNoteID = note.id
        currentBody = note.body
        wordCountCache = NoteStats.wordCount(note.body)
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
        librarySearchTask?.cancel()
        searchGeneration &+= 1
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

    // MARK: - Linked notes

    func note(matchingLink identifier: String) -> Note? {
        if let id = UUID(uuidString: identifier), let note = notes.first(where: { $0.id == id }) {
            return note
        }
        return notes.first {
            $0.title.compare(identifier, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func openLinkedNote(identifier: String) {
        guard let note = note(matchingLink: identifier) else { return }
        open(note)
        focusEditor()
    }

    func backlinks(to target: Note) -> [Note] {
        notes
            .filter { $0.id != target.id && NoteLink.extract(from: $0.body).contains { $0.points(to: target) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Creates a linked target without leaving the note currently being edited.
    @discardableResult
    func createLinkedNote(named rawTitle: String) -> Note? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.contains("|"), !title.contains("]") else { return nil }
        if let existing = note(matchingLink: title) { return existing }
        guard flushNow() else { return nil }

        let note = Note(body: "# \(title)")
        notes.insert(note, at: 0)
        if persist(note) { return note }
        notes.removeAll { $0.id == note.id }
        return nil
    }

    // MARK: - Pinning

    func isPinned(_ note: Note) -> Bool {
        pinnedNoteIDs.contains(note.id)
    }

    func togglePin(_ note: Note) {
        if pinnedNoteIDs.contains(note.id) {
            pinnedNoteIDs.remove(note.id)
        } else {
            pinnedNoteIDs.insert(note.id)
        }
        let stored = pinnedNoteIDs.map(\.uuidString).sorted()
        userDefaults.set(stored, forKey: Self.pinnedNoteIDsKey)
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
        // Do not create-and-switch if the outgoing note cannot be saved; that would
        // strand its unsaved edits on a note no longer selected.
        guard flushNow() else {
            Self.log.error("Blocked creating a note: could not persist unsaved edits.")
            return
        }
        if hasActiveFilter {
            clearLibraryFilter()
        }
        let note = Note()
        notes.insert(note, at: 0)
        open(note)
        if !persist(note) {
            // Persist failed (e.g. disk full). Keep it dirty so a later flush retries
            // until it durably lands or the user is told.
            dirtyNoteIDs.insert(note.id)
        }
    }

    func deleteNote(_ note: Note) {
        if currentNoteID == note.id {
            // Deleting the selected note discards its edits; make sure nothing is stranded
            // before we remove the file, but do not let a failed save abort a deletion the
            // user actively confirmed.
            flushNow()
        }
        guard let url = fileRecordsByID[note.id]?.url ?? fileURL(for: note.id) else { return }
        let wasSelected = currentNoteID == note.id
        let index = notes.firstIndex(where: { $0.id == note.id }) ?? 0
        let trashed: TrashedNoteFile
        do {
            trashed = try repository.moveToTrash(fileURL: url)
        } catch {
            Self.log.error("Failed to delete note \(note.id): \(error.localizedDescription, privacy: .public)")
            return
        }
        try? searchIndex?.delete(noteID: note.id)
        dirtyNoteIDs.remove(note.id)
        fileRecordsByID.removeValue(forKey: note.id)
        observedExternalRevisionByID.removeValue(forKey: note.id)

        notes.removeAll { $0.id == note.id }
        deletedNoteUndo = DeletedNoteUndo(note: note, file: trashed, index: index, wasSelected: wasSelected)
        deletedNoteUndoTitle = note.title
        scheduleDeletionUndoDismissal()

        if wasSelected {
            // Pick a deterministic neighbour so the editor never falls to a blank state
            // while other notes exist.
            let neighbor: Note? = {
                guard !notes.isEmpty else { return notes.first }
                if index < notes.count { return notes[index] }
                return notes[notes.count - 1]
            }()
            if let neighbor {
                currentNoteID = neighbor.id
                currentBody = neighbor.body
                wordCountCache = NoteStats.wordCount(neighbor.body)
                userDefaults.set(neighbor.id.uuidString, forKey: "lastNote")
                prefetchFavicons(in: neighbor.body)
            } else {
                currentNoteID = nil
                currentBody = ""
                wordCountCache = 0
            }
        }
    }

    func restoreLastDeletedNote() {
        guard let deletedNoteUndo else { return }
        do {
            let record = try repository.restore(deletedNoteUndo.file)
            let insertionIndex = min(deletedNoteUndo.index, notes.count)
            notes.insert(deletedNoteUndo.note, at: insertionIndex)
            fileRecordsByID[deletedNoteUndo.note.id] = record
            observedExternalRevisionByID.removeValue(forKey: deletedNoteUndo.note.id)
            try? searchIndex?.upsert(note: deletedNoteUndo.note)
            dismissDeletionUndo()
            if deletedNoteUndo.wasSelected {
                open(deletedNoteUndo.note)
                focusEditor()
            }
        } catch {
            Self.log.error(
                "Failed to restore note \(deletedNoteUndo.note.id): \(error.localizedDescription, privacy: .public)")
            presentLibraryError("The note could not be restored because its original path is no longer available.")
        }
    }

    func dismissDeletionUndo() {
        deletionUndoTask?.cancel()
        deletionUndoTask = nil
        deletedNoteUndo = nil
        deletedNoteUndoTitle = nil
    }

    private func scheduleDeletionUndoDismissal() {
        deletionUndoTask?.cancel()
        deletionUndoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.dismissDeletionUndo()
        }
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
    /// above). Marks the note dirty and schedules autosave.
    private func replaceCurrentBody(_ newBody: String) {
        guard let id = currentNoteID else { return }
        currentBody = newBody
        wordCountCache = NoteStats.wordCount(newBody)
        dirtyNoteIDs.insert(id)

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

    /// Save Now: immediate, unconditional persistence of the current edit. Returns `true`
    /// when the edit reached disk (so the dirty marker can be cleared), `false` otherwise.
    @discardableResult
    func saveNowPublic() -> Bool {
        guard let id = currentNoteID, dirtyNoteIDs.contains(id) else { return true }

        guard var note = currentNote() else { return true }
        note.body = currentBody
        note.updatedAt = Date()
        note.tags = TagNormalizer.extractTags(from: currentBody)

        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx] = note
        }
        // Only clear the dirty marker when persistence actually succeeded, so a failed
        // write can be retried with ⌘S (or on next switch/quits) instead of being
        // silently marked clean and lost.
        if persist(note) {
            dirtyNoteIDs.remove(id)
            return true
        }
        return false
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
            line = removeToken(token, from: line)
            // Drop now-empty lines that consisted only of the tag (plus its whitespace).
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func removeToken(_ token: String, from line: String) -> String {
        // Match `#name` (with optional leading whitespace/punctuation and trailing
        // whitespace) but NOT when it extends a longer word like `#tagfoo`. The matched
        // token plus its directly adjacent whitespace is removed, so neighbouring
        // entirely different `#tags` are left intact.
        let pattern = "(^|[\\s\\W])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}_-])\\s?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        // Keep the preceding character and remove only the token plus one adjacent trailing
        // space. Unrelated spacing is Markdown content and must remain byte-for-byte intact.
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
        do {
            let result = try repository.save(note: note, expected: fileRecordsByID[note.id])
            switch result {
            case .written(let landed):
                fileRecordsByID[note.id] = landed
                observedExternalRevisionByID.removeValue(forKey: note.id)
            case .conflict:
                Self.log.error(
                    "Refusing to overwrite externally changed note \(note.id, privacy: .public)")
                return false
            }
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
    /// before switching notes). Returns `true` when the current note's edits are safe.
    @discardableResult
    func flushNow() -> Bool {
        guard let id = currentNoteID, dirtyNoteIDs.contains(id) else { return true }
        return saveNowPublic()
    }

    // MARK: - External file changes

    private func startExternalChangeMonitoring() {
        libraryChangeMonitor.stop()
        libraryChangeMonitor.start(directory: notesDirectory) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalRefresh()
            }
        }
    }

    private func scheduleExternalRefresh() {
        externalRefreshTask?.cancel()
        externalRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.refreshExternalChanges()
        }
    }

    /// Reconciles the in-memory library with Markdown files changed by another editor,
    /// iCloud, the integrated terminal, or an AI agent.
    func refreshExternalChanges() async {
        let load: LoadOutcome
        do {
            load = try await Self.loadNotes(from: notesDirectory, fileManager: fileManager)
        } catch {
            Self.log.error("External refresh failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let allIDs = Set(fileRecordsByID.keys).union(load.fileRecords.keys)
        let changedIDs = allIDs.filter {
            !NoteFileManager.contentsMatch(fileRecordsByID[$0], load.fileRecords[$0])
        }
        guard !changedIDs.isEmpty else { return }

        // A dirty note deliberately keeps its old baseline until the user resolves the
        // conflict. Directory watchers can emit several events for one atomic write, so
        // remember the disk hash separately and handle each external revision only once.
        let newlyChangedIDs = changedIDs.filter { id in
            observedExternalRevisionByID[id] != Self.externalRevisionIdentifier(load.fileRecords[id])
        }
        guard !newlyChangedIDs.isEmpty else { return }
        for id in newlyChangedIDs {
            observedExternalRevisionByID[id] = Self.externalRevisionIdentifier(load.fileRecords[id])
        }

        let localByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let diskByID = Dictionary(uniqueKeysWithValues: load.notes.map { ($0.id, $0) })

        if let currentID = currentNoteID,
            dirtyNoteIDs.contains(currentID),
            newlyChangedIDs.contains(currentID)
        {
            externalNoteConflict = ExternalNoteConflict(
                noteID: currentID,
                diskNote: diskByID[currentID],
                diskRecord: load.fileRecords[currentID]
            )
        }

        var merged = load.notes
        for dirtyID in dirtyNoteIDs {
            guard let local = localByID[dirtyID] else { continue }
            if let index = merged.firstIndex(where: { $0.id == dirtyID }) {
                merged[index] = local
            } else {
                merged.append(local)
            }
        }
        merged.sort { $0.updatedAt > $1.updatedAt }
        notes = merged

        var reconciledRecords = load.fileRecords
        for dirtyID in dirtyNoteIDs {
            if let previous = fileRecordsByID[dirtyID] {
                reconciledRecords[dirtyID] = previous
            } else {
                reconciledRecords.removeValue(forKey: dirtyID)
            }
        }
        fileRecordsByID = reconciledRecords

        let reloadedIDs = newlyChangedIDs.filter { !dirtyNoteIDs.contains($0) }
        for id in reloadedIDs {
            // Clean notes now use the disk record as their normal baseline. Only
            // unresolved dirty revisions need the separate de-duplication record.
            observedExternalRevisionByID.removeValue(forKey: id)
        }

        if let currentID = currentNoteID, !dirtyNoteIDs.contains(currentID) {
            if let refreshed = diskByID[currentID] {
                currentBody = refreshed.body
                wordCountCache = NoteStats.wordCount(refreshed.body)
                prefetchFavicons(in: refreshed.body)
            } else {
                selectAfterExternalRemoval()
            }
        }

        guard !reloadedIDs.isEmpty else { return }

        searchIndex = await Self.rebuildIndex(notes: merged, appSupport: appSupportURL)
        if externalNoteConflict == nil {
            showExternalChangeMessage(
                reloadedIDs.count == 1
                    ? "Reloaded an external change"
                    : "Reloaded \(reloadedIDs.count) external changes"
            )
        }
    }

    private static func externalRevisionIdentifier(_ record: FileRecord?) -> String {
        record?.contentHash ?? "<deleted>"
    }

    func keepLocalVersionAfterConflict() {
        guard let conflict = externalNoteConflict,
            conflict.noteID == currentNoteID,
            var note = currentNote()
        else { return }
        if let diskRecord = conflict.diskRecord {
            fileRecordsByID[conflict.noteID] = diskRecord
        } else {
            fileRecordsByID.removeValue(forKey: conflict.noteID)
        }
        note.body = currentBody
        note.updatedAt = Date()
        note.tags = TagNormalizer.extractTags(from: currentBody)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if persist(note) {
            dirtyNoteIDs.remove(note.id)
            observedExternalRevisionByID.removeValue(forKey: note.id)
            externalNoteConflict = nil
            showExternalChangeMessage("Kept your version")
        }
    }

    func loadExternalVersionAfterConflict() {
        guard let conflict = externalNoteConflict else { return }
        dirtyNoteIDs.remove(conflict.noteID)
        if let diskNote = conflict.diskNote {
            if let index = notes.firstIndex(where: { $0.id == conflict.noteID }) {
                notes[index] = diskNote
            } else {
                notes.insert(diskNote, at: 0)
            }
            if let record = conflict.diskRecord {
                fileRecordsByID[conflict.noteID] = record
            }
            observedExternalRevisionByID.removeValue(forKey: conflict.noteID)
            if currentNoteID == conflict.noteID {
                currentBody = diskNote.body
                wordCountCache = NoteStats.wordCount(diskNote.body)
            }
            try? searchIndex?.upsert(note: diskNote)
        } else {
            notes.removeAll { $0.id == conflict.noteID }
            fileRecordsByID.removeValue(forKey: conflict.noteID)
            observedExternalRevisionByID.removeValue(forKey: conflict.noteID)
            try? searchIndex?.delete(noteID: conflict.noteID)
            if currentNoteID == conflict.noteID {
                selectAfterExternalRemoval()
            }
        }
        externalNoteConflict = nil
        showExternalChangeMessage("Loaded the external version")
    }

    private func selectAfterExternalRemoval() {
        if let next = notes.first {
            currentNoteID = next.id
            currentBody = next.body
            wordCountCache = NoteStats.wordCount(next.body)
            userDefaults.set(next.id.uuidString, forKey: "lastNote")
        } else {
            currentNoteID = nil
            currentBody = ""
            wordCountCache = 0
        }
    }

    private func showExternalChangeMessage(_ message: String) {
        externalMessageTask?.cancel()
        externalChangeMessage = message
        externalMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.externalChangeMessage = nil
        }
    }

    // MARK: - Search

    func performSearch() {
        let parsed = parsedSearch(searchQuery, selectedTag: selectedTag)
        searchGeneration &+= 1
        let generation = searchGeneration
        librarySearchTask?.cancel()
        guard !parsed.query.isEmpty || !parsed.tags.isEmpty, let index = searchIndex else {
            searchResults = []
            return
        }

        let givenQuery = parsed.query
        let gaveTags = parsed.tags
        librarySearchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: searchDebounce)
            } catch {
                return
            }
            // Run the (I/O + SQLite) query off the main actor; the detached closure only
            // touches Sendable values.
            let started = DispatchTime.now()
            let results = await Task.detached(priority: .userInitiated) { [index] in
                (try? index.search(givenQuery, tags: gaveTags)) ?? []
            }.value
            // Drop stale results: a later query (or a cleared field) superseded this one.
            guard generation == self.searchGeneration, !Task.isCancelled else { return }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            searchResults = results
            Self.log.info(
                "Search '\(givenQuery, privacy: .private)' returned \(results.count) in \(elapsed, format: .fixed(precision: 1)) ms"
            )
        }
    }

    func selectTag(_ tag: Tag?) {
        withAnimation(.easeOut(duration: 0.12)) {
            guard let tag else {
                selectedTag = nil
                return
            }
            if typedTags(in: searchQuery).contains(tag) {
                searchQuery = removingTag(tag, from: searchQuery)
                if selectedTag == tag { selectedTag = nil }
            } else {
                selectedTag = (selectedTag == tag) ? nil : tag
            }
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
            // Preserve search-score order rather than library order. Build the dictionary
            // with last-write-wins so an accidental duplicate ID never traps here.
            var byID: [UUID: Note] = [:]
            for note in notes { byID[note.id] = note }
            let order = searchResults.map(\.noteID)
            return order.compactMap { byID[$0] }
        }
        if let selectedTag {
            return libraryOrderedNotes.filter { $0.tags.contains(selectedTag) }
        }
        return libraryOrderedNotes
    }

    private var libraryOrderedNotes: [Note] {
        notes.sorted { lhs, rhs in
            let lhsPinned = pinnedNoteIDs.contains(lhs.id)
            let rhsPinned = pinnedNoteIDs.contains(rhs.id)
            if lhsPinned != rhsPinned { return lhsPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var pinnedVisibleNotes: [Note] {
        guard !isSearching else { return [] }
        return visibleNotes.filter { pinnedNoteIDs.contains($0.id) }
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

    var activeLibrarySearchTags: Set<Tag> {
        parsedSearch(searchQuery, selectedTag: selectedTag).tags
    }

    var commandPaletteActiveTags: Set<Tag> {
        parsedSearch(commandPaletteQuery, selectedTag: commandPaletteSelectedTag).tags
    }

    func openSearchResult(_ result: SearchResult) {
        guard let note = notes.first(where: { $0.id == result.noteID }) else { return }
        open(note)
    }

    func searchResult(for noteID: UUID) -> SearchResult? {
        searchResults.first { $0.noteID == noteID }
    }

    /// Recency buckets for the unfiltered (or tag-filtered) library. Search hits
    /// stay in relevance order and are not grouped.
    var groupedVisibleNotes: [(group: NoteRecencyGroup, notes: [Note])] {
        guard !isSearching else { return [] }
        var buckets: [NoteRecencyGroup: [Note]] = [:]
        for note in visibleNotes where !pinnedNoteIDs.contains(note.id) {
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
        librarySearchTask?.cancel()
        searchGeneration &+= 1
        searchQuery = ""
        searchResults = []
        searchFieldPresented = false
    }

    // MARK: - Command palette

    func presentCommandPalette() {
        dismissNoteFind(focusEditor: false)
        paletteSearchTask?.cancel()
        commandPalettePresented = true
        commandPaletteQuery = ""
        commandPaletteSelectedTag = nil
        commandPaletteResults = []
        paletteSearchGeneration &+= 1
        commandPaletteFocusToken &+= 1
    }

    func dismissCommandPalette() {
        paletteSearchTask?.cancel()
        paletteSearchGeneration &+= 1
        commandPalettePresented = false
        commandPaletteQuery = ""
        commandPaletteSelectedTag = nil
        commandPaletteResults = []
    }

    func performCommandPaletteSearch() {
        let parsed = parsedSearch(commandPaletteQuery, selectedTag: commandPaletteSelectedTag)
        paletteSearchGeneration &+= 1
        let generation = paletteSearchGeneration
        paletteSearchTask?.cancel()
        guard !parsed.query.isEmpty || !parsed.tags.isEmpty, let index = searchIndex else {
            commandPaletteResults = []
            return
        }

        let givenQuery = parsed.query
        let gaveTags = parsed.tags
        paletteSearchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: searchDebounce)
            } catch {
                return
            }
            let results = await Task.detached(priority: .userInitiated) { [index] in
                (try? index.search(givenQuery, tags: gaveTags)) ?? []
            }.value
            guard generation == self.paletteSearchGeneration,
                self.commandPalettePresented, !Task.isCancelled
            else { return }
            self.commandPaletteResults = results
        }
    }

    func selectCommandPaletteTag(_ tag: Tag) {
        if typedTags(in: commandPaletteQuery).contains(tag) {
            commandPaletteQuery = removingTag(tag, from: commandPaletteQuery)
            if commandPaletteSelectedTag == tag { commandPaletteSelectedTag = nil }
        } else {
            commandPaletteSelectedTag = commandPaletteSelectedTag == tag ? nil : tag
        }
        performCommandPaletteSearch()
    }

    func openFromCommandPalette(_ note: Note) {
        open(note)
        dismissCommandPalette()
        focusEditor()
    }

    // MARK: - Find in note

    func presentNoteFind() {
        guard currentNote() != nil else { return }
        dismissCommandPalette()
        noteFindPresented = true
        noteFindCurrentIndex = 0
        noteFindMatchCount = 0
        noteFindFocusToken &+= 1
        refreshNoteFind()
    }

    func noteFindQueryDidChange() {
        noteFindCurrentIndex = 0
        refreshNoteFind()
    }

    func scheduleNoteFindRefresh() {
        noteFindRefreshTask?.cancel()
        guard noteFindPresented, let noteID = currentNoteID else { return }
        noteFindRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: searchDebounce)
            } catch {
                return
            }
            guard noteFindPresented, currentNoteID == noteID, !Task.isCancelled else { return }
            refreshNoteFind()
        }
    }

    func moveNoteFind(by delta: Int) {
        guard noteFindMatchCount > 0 else {
            refreshNoteFind()
            return
        }
        noteFindCurrentIndex = (noteFindCurrentIndex + delta + noteFindMatchCount) % noteFindMatchCount
        refreshNoteFind()
    }

    func noteFindResultsDidChange(count: Int) {
        noteFindMatchCount = max(0, count)
        if noteFindMatchCount == 0 {
            noteFindCurrentIndex = 0
        } else {
            noteFindCurrentIndex = min(noteFindCurrentIndex, noteFindMatchCount - 1)
        }
    }

    func refreshNoteFind() {
        guard noteFindPresented else { return }
        NotificationCenter.default.post(
            name: EditorFindNotifications.query,
            object: nil,
            userInfo: [
                "query": noteFindQuery,
                "currentIndex": noteFindCurrentIndex,
            ]
        )
    }

    func dismissNoteFind(focusEditor shouldFocusEditor: Bool = true) {
        noteFindRefreshTask?.cancel()
        if noteFindPresented {
            NotificationCenter.default.post(name: EditorFindNotifications.clear, object: nil)
        }
        noteFindPresented = false
        noteFindQuery = ""
        noteFindCurrentIndex = 0
        noteFindMatchCount = 0
        if shouldFocusEditor {
            focusEditor()
        }
    }

    /// Extracts exact `#tag` tokens from a search while leaving the remaining words
    /// as full-text terms. Unknown partial tags are reserved for tag suggestions.
    private func parsedSearch(_ raw: String, selectedTag: Tag?) -> (query: String, tags: Set<Tag>) {
        var tags = Set<Tag>()
        if let selectedTag { tags.insert(selectedTag) }
        let knownTags = Set(allTags.map(\.tag))
        var terms: [Substring] = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            guard token.first == "#" else {
                terms.append(token)
                continue
            }
            let name = String(token.dropFirst())
            let tag = Tag(name: name)
            if !tag.name.isEmpty, knownTags.contains(tag) {
                tags.insert(tag)
            }
        }
        return (terms.joined(separator: " "), tags)
    }

    private func typedTags(in raw: String) -> Set<Tag> {
        parsedSearch(raw, selectedTag: nil).tags
    }

    private func removingTag(_ tag: Tag, from raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .filter { token in
                guard token.first == "#" else { return true }
                return Tag(name: String(token.dropFirst())) != tag
            }
            .joined(separator: " ")
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
        guard flushNow() else {
            throw NoteFileError.writeFailed(underlying: "refusing import while unsaved edits cannot be flushed")
        }
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
        if !persist(note) {
            dirtyNoteIDs.insert(note.id)
        }
        return note
    }

    /// Called on app termination to guarantee the last edits are on disk.
    /// Runs synchronously on the main actor so pending edits are flushed even when
    /// no window/view is alive.
    func shutdown() {
        cancelPendingSave()
        librarySearchTask?.cancel()
        paletteSearchTask?.cancel()
        noteFindRefreshTask?.cancel()
        libraryChangeMonitor.stop()
        externalRefreshTask?.cancel()
        deletionUndoTask?.cancel()
        externalMessageTask?.cancel()
        if let id = currentNoteID, dirtyNoteIDs.contains(id) {
            saveNowPublic()
        }
        searchIndex = nil
    }
}
