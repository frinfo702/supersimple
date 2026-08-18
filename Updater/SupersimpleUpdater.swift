import Darwin
import Foundation

/// Unsandboxed helper: waits for the main app to quit, replaces the bundle, relaunches.
@main
enum SupersimpleUpdater {
    static func main() {
        guard let args = Arguments.parse(CommandLine.arguments) else {
            fputs("usage: SupersimpleUpdater --source <app> --destination <app> --pid <pid>\n", stderr)
            exit(2)
        }

        waitForExit(pid: args.pid, timeout: 20)

        do {
            try install(from: args.source, to: args.destination)
            try relaunch(args.destination)
            exit(0)
        } catch {
            fputs("supersimple updater failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func waitForExit(pid: Int32, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return }
            usleep(100_000)
        }
    }

    private static func install(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw POSIXError(.ENOENT)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw POSIXError(.EIO)
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

    private static func relaunch(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [app.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw POSIXError(.EIO)
        }
    }
}

private struct Arguments {
    var source: URL
    var destination: URL
    var pid: Int32

    static func parse(_ argv: [String]) -> Arguments? {
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
        return Arguments(
            source: URL(fileURLWithPath: source),
            destination: URL(fileURLWithPath: destination),
            pid: pid
        )
    }
}
