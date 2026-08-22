import Foundation
import MarkdownEngine
import SupersimpleCore

/// Immutable resolver snapshot rebuilt from the app's note list by SwiftUI.
/// Keeping it value-only makes editor callbacks safe to use off the main actor.
struct NoteWikiLinkResolver: WikiLinkResolver {
    private let idsByNormalizedTitle: [String: UUID]
    private let titlesByID: [UUID: String]
    private let revision: String

    init(notes: [Note]) {
        var idsByNormalizedTitle: [String: UUID] = [:]
        var titlesByID: [UUID: String] = [:]
        for note in notes {
            let normalized = Self.normalize(note.title)
            if idsByNormalizedTitle[normalized] == nil {
                idsByNormalizedTitle[normalized] = note.id
            }
            titlesByID[note.id] = note.title
        }
        self.idsByNormalizedTitle = idsByNormalizedTitle
        self.titlesByID = titlesByID
        revision =
            titlesByID
            .map { "\($0.key.uuidString):\($0.value)" }
            .sorted()
            .joined(separator: "|")
    }

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard let id = idsByNormalizedTitle[Self.normalize(displayName)] else { return nil }
        return WikiLinkResolution(id: id.uuidString, exists: true)
    }

    func name(forID id: String) -> String? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return titlesByID[uuid]
    }

    func fingerprint() -> AnyHashable {
        revision
    }

    private static func normalize(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
