import Darwin
import Foundation

/// Unsandboxed helper: waits for the main app to quit, replaces the bundle, relaunches.
@main
enum SupersimpleUpdater {
    static func main() {
        guard let request = loadRequest() else {
            log("usage: SupersimpleUpdater --source <app> --destination <app> --pid <pid>")
            exit(2)
        }

        log("waiting for pid \(request.install.pid)")
        waitForExit(pid: request.install.pid, timeout: 30)
        Thread.sleep(forTimeInterval: 0.4)

        do {
            let source = URL(fileURLWithPath: request.install.sourcePath)
            let destination = URL(fileURLWithPath: request.install.destinationPath)
            log("install \(source.path) -> \(destination.path)")
            try AppBundleInstaller.replace(source: source, destination: destination)
            try? FileManager.default.removeItem(at: request.fileURL)
            log("relaunch \(destination.path)")
            try relaunch(destination)
            exit(0)
        } catch {
            log("supersimple updater failed: \(error)")
            exit(1)
        }
    }

    private static func loadRequest() -> (install: PendingUpdateInstall, fileURL: URL)? {
        if let parsed = PendingUpdateInstall.parseCommandLine(CommandLine.arguments) {
            let fileURL =
                PendingUpdateInstall.loadFromKnownLocations()?.1
                ?? PendingUpdateInstall.searchURLs()[0]
            return (parsed, fileURL)
        }
        return PendingUpdateInstall.loadFromKnownLocations()
    }

    private static func waitForExit(pid: Int32, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return }
            usleep(100_000)
        }
        log("timed out waiting for pid \(pid); installing anyway")
    }

    private static func relaunch(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", app.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw POSIXError(.EIO)
        }
    }

    private static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        fputs(line, stderr)
        for pendingURL in PendingUpdateInstall.searchURLs() {
            let logURL = pendingURL.deletingLastPathComponent().appendingPathComponent("updater.log")
            let dir = logURL.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            let previous = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            try? (previous + line).write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
