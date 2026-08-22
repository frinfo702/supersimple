import Foundation

/// A wiki-style reference stored in a note body.
///
/// Stable references use `[[Title|UUID]]`; unresolved references may contain only
/// `[[Title]]`. Image embeds (`![[image.png]]`) are intentionally excluded.
public struct NoteLink: Equatable, Sendable {
    public let title: String
    public let targetID: UUID?

    public init(title: String, targetID: UUID?) {
        self.title = title
        self.targetID = targetID
    }

    public static func extract(from body: String) -> [NoteLink] {
        let range = NSRange(location: 0, length: (body as NSString).length)
        return regex.matches(in: body, range: range).compactMap { match in
            guard let titleRange = Range(match.range(at: 1), in: body) else { return nil }
            let title = String(body[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let targetID: UUID?
            if match.range(at: 2).location != NSNotFound,
                let idRange = Range(match.range(at: 2), in: body)
            {
                targetID = UUID(uuidString: String(body[idRange]))
            } else {
                targetID = nil
            }
            return NoteLink(title: title, targetID: targetID)
        }
    }

    public func points(to note: Note) -> Bool {
        if let targetID { return targetID == note.id }
        return title.compare(note.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"(?<!!)\[\[([^\]|\r\n]*)(?:\|([^\]\r\n]+))?\]\]"#
    )
}
