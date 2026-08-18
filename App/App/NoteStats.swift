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

    /// First meaningful body line for the library row: skips blanks and headings.
    static func preview(from body: String) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { continue }
            return String(trimmed.prefix(120))
        }
        return ""
    }

    /// Compact library timestamp: time today, "Yesterday", weekday this week, else a date.
    static func relativeUpdated(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
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
