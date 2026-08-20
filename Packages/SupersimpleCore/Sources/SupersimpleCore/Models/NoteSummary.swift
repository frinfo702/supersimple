import Foundation

/// Lightweight, sidebar-only representation of a note. Crucially it does **not** hold the
/// full body text, so a library of thousands of notes does not require loading every
/// document into memory. Title and preview are derived from the body at index/read time
/// and cached here.
public struct NoteSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: Set<Tag>
    public var extraFields: [String]
    /// Canonical source file (e.g. `<root>/Notes/<id>.md`).
    public let fileURL: URL
    /// Title shown in the sidebar (derived from the first heading).
    public var title: String
    /// Preview line shown under the title.
    public var preview: String
    /// File identity at the time this summary was read. Used to detect external edits.
    public var fileRecord: FileRecord?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        tags: Set<Tag>,
        extraFields: [String] = [],
        fileURL: URL,
        title: String,
        preview: String,
        fileRecord: FileRecord? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.extraFields = extraFields
        self.fileURL = fileURL
        self.title = title
        self.preview = preview
        self.fileRecord = fileRecord
    }

    /// Builds a summary from a decoded document plus its source file record without
    /// keeping the body around.
    public init(doc: MarkdownDocument, fileURL: URL, fileRecord: FileRecord?) {
        self.init(
            id: doc.metadata.id,
            createdAt: doc.metadata.createdAt,
            updatedAt: doc.metadata.updatedAt,
            tags: doc.metadata.tags,
            extraFields: doc.metadata.extraFields,
            fileURL: fileURL,
            title: Note.title(from: doc.body),
            preview: Note.preview(from: doc.body),
            fileRecord: fileRecord
        )
    }
}

/// A note fully loaded from disk, including its body. Loaded on demand for the editor only.
public struct NoteContent: Equatable, Sendable {
    public var summary: NoteSummary
    public var body: String

    public init(summary: NoteSummary, body: String) {
        self.summary = summary
        self.body = body
    }
}
