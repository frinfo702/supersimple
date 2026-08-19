import Foundation

/// Copies Application Support out of the former App Sandbox container.
///
/// A real login shell cannot run inside the sandbox, so the app is now
/// unsandboxed. Notes that already lived under
/// `~/Library/Containers/…/Application Support/Supersimple` would otherwise
/// disappear from the unsandboxed support directory.
enum SandboxContainerMigration {
    static let bundleIdentifier = "com.frinfo702.supersimple"

    static func containerApplicationSupport(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/Supersimple",
            isDirectory: true
        )
    }

    /// Copies missing items from the sandbox container into `destination`.
    /// No-op when the destination already has notes, or the container is absent.
    static func migrateIfNeeded(
        to destination: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        let source = containerApplicationSupport(home: home)
        guard fileManager.fileExists(atPath: source.path) else { return }
        if hasMarkdownNotes(
            in: destination.appendingPathComponent("Notes", isDirectory: true), fileManager: fileManager)
        {
            return
        }

        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try? fileManager.copyItem(at: item, to: target)
        }
    }

    private static func hasMarkdownNotes(in notesDirectory: URL, fileManager: FileManager) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: notesDirectory.path) else {
            return false
        }
        return names.contains { $0.hasSuffix(".md") }
    }
}
