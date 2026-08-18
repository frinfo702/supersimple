import Foundation

/// Written by the sandboxed app before launching the helper. NSWorkspace drops
/// `OpenConfiguration.arguments` for sandboxed callers, so the helper reads this
/// file instead of argv.
struct PendingUpdateInstall: Codable, Equatable {
    var sourcePath: String
    var destinationPath: String
    var pid: Int32

    static let fileName = "pending-install.json"
    static let bundleIdentifier = "com.frinfo702.supersimple"

    static func fileURL(in stagingDirectory: URL) -> URL {
        stagingDirectory.appendingPathComponent(fileName)
    }

    static func searchURLs(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent(
                "Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/Supersimple/Updates/\(fileName)"
            ),
            home.appendingPathComponent("Library/Application Support/Supersimple/Updates/\(fileName)"),
        ]
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> PendingUpdateInstall {
        try JSONDecoder().decode(PendingUpdateInstall.self, from: Data(contentsOf: url))
    }

    static func loadFromKnownLocations(fileManager: FileManager = .default) -> (PendingUpdateInstall, URL)? {
        for url in searchURLs() where fileManager.fileExists(atPath: url.path) {
            if let value = try? load(from: url) { return (value, url) }
        }
        return nil
    }

    static func parseCommandLine(_ argv: [String]) -> PendingUpdateInstall? {
        var source: String?
        var destination: String?
        var pid: Int32?
        var index = 1
        while index < argv.count {
            let key = argv[index]
            let next = index + 1 < argv.count ? argv[index + 1] : nil
            switch key {
            case "--source":
                source = next
                index += 2
            case "--destination":
                destination = next
                index += 2
            case "--pid":
                if let next { pid = Int32(next) }
                index += 2
            default:
                index += 1
            }
        }
        guard let source, let destination, let pid else { return nil }
        return PendingUpdateInstall(sourcePath: source, destinationPath: destination, pid: pid)
    }
}
