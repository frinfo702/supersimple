import Foundation

/// Replaces an `.app` bundle. `ditto src dest` would nest `src` inside an existing
/// `dest` directory, so we copy to a sibling temp and swap.
enum AppBundleInstaller {
    static func replace(
        source: URL,
        destination: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw POSIXError(.ENOENT)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).new")
        try? fileManager.removeItem(at: temp)
        try ditto(from: source, to: temp)

        var lastError: Error = POSIXError(.EIO)
        for _ in 0..<8 {
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: temp, to: destination)
                lastError = POSIXError(.EIO)
                break
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        if fileManager.fileExists(atPath: temp.path) {
            throw lastError
        }

        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", destination.path]
        do {
            try xattr.run()
            xattr.waitUntilExit()
        } catch {
            // Quarantine stripping is best-effort; the copy still installed.
        }
    }

    private static func ditto(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw POSIXError(.EIO) }
    }
}
