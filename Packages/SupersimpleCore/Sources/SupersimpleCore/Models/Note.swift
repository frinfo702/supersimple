import Foundation

public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: Set<Tag>
    /// The markdown body, excluding any YAML frontmatter.
    public var body: String
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: Set<Tag> = [],
        body: String = "",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.body = body
        self.isDeleted = isDeleted
    }

    /// Derives the display title from the first Markdown heading, falling back to a placeholder.
    /// The body is inspected lazily; the result is not cached in the model.
    public var title: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            var count = 0
            var candidate = stripped
            while candidate.hasPrefix("#"), count < stripped.count {
                count += 1
                candidate = String(candidate.dropFirst())
            }
            if count > 0 {
                let rest = candidate.trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        // First non-empty line as fallback.
        for line in trimmed.split(separator: "\n") {
            let first = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !first.isEmpty { return String(first.prefix(60)) }
        }
        return "Untitled"
    }
}
