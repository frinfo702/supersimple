import Foundation

/// Display and export helpers derived from a note body / title.
enum NoteStats {
    /// Whitespace-separated word count. Empty or whitespace-only bodies are 0.
    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func characterCount(_ text: String) -> Int {
        text.count
    }

    /// A filesystem-safe stem for an exported `.md` file, derived from the note title.
    static func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        return String(trimmed.prefix(80))
    }
}
