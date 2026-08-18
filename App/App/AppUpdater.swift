import AppKit
import Foundation
import OSLog
import SupersimpleCore

protocol UpdateTransport: Sendable {
    func get(url: URL) async throws -> Data
    func download(url: URL, to file: URL) async throws
}

struct URLSessionUpdateTransport: UpdateTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("supersimple", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        return data
    }

    func download(url: URL, to file: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("supersimple", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await session.download(for: request)
        try Self.checkHTTP(response)
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: file)
        try fm.moveItem(at: temp, to: file)
    }

    private static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

enum AppUpdaterError: Error {
    case missingAppBundle
    case invalidAppBundle
    case unzipFailed
    case helperMissing
}

enum UpdateCheckOutcome: Equatable {
    case disabled
    case alreadyChecking
    case upToDate
    case ready(String)
    case failed
}

/// Checks GitHub Releases, downloads a newer app zip in the background, and
/// relaunches via the unsandboxed helper when the user confirms.
@MainActor
@Observable
final class AppUpdater {
    static let log = Logger(subsystem: "com.frinfo702.supersimple", category: "AppUpdater")

    /// Non-nil once a newer build has been downloaded and is ready to install.
    private(set) var availableUpdateVersion: String?
    /// True while a GitHub check / zip download is in flight.
    private(set) var isChecking = false

    private let owner: String
    private let repo: String
    private let currentVersion: AppVersion
    private let stagingDirectory: URL
    private let runningBundleURL: URL
    private let expectedBundleIdentifier: String
    private let transport: any UpdateTransport
    private let fileManager: FileManager
    let enabled: Bool

    var stagedAppURL: URL {
        stagingDirectory.appendingPathComponent("supersimple.app", isDirectory: true)
    }

    private var stagedVersionURL: URL {
        stagingDirectory.appendingPathComponent("staged-version")
    }

    init(
        owner: String = "frinfo702",
        repo: String = "supersimple",
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0",
        stagingDirectory: URL? = nil,
        runningBundleURL: URL = Bundle.main.bundleURL,
        expectedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.frinfo702.supersimple",
        transport: any UpdateTransport = URLSessionUpdateTransport(),
        fileManager: FileManager = .default,
        enabled: Bool? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.currentVersion = AppVersion(parsing: currentVersion)
        if let stagingDirectory {
            self.stagingDirectory = stagingDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Supersimple/Updates", isDirectory: true)
            self.stagingDirectory = support
        }
        self.runningBundleURL = runningBundleURL
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.transport = transport
        self.fileManager = fileManager
        self.enabled = enabled ?? AppUpdater.shouldEnable()
    }

    var currentVersionString: String { currentVersion.displayString }

    static func shouldEnable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundlePath: String = Bundle.main.bundlePath
    ) -> Bool {
        if environment["SUPERSIMPLE_DISABLE_UPDATES"] == "1" { return false }
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if bundlePath.contains("DerivedData") { return false }
        return true
    }

    @discardableResult
    func checkAndDownloadIfNeeded() async -> UpdateCheckOutcome {
        guard enabled else { return .disabled }
        guard !isChecking else { return .alreadyChecking }
        isChecking = true
        defer { isChecking = false }
        do {
            let latestURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
            let data = try await transport.get(url: latestURL)
            let release = try GitHubRelease.parseLatest(data)
            guard currentVersion < release.version else {
                availableUpdateVersion = nil
                return .upToDate
            }
            if isAlreadyStaged(release.version) {
                availableUpdateVersion = release.version.displayString
                return .ready(release.version.displayString)
            }
            try await stage(release)
            availableUpdateVersion = release.version.displayString
            return .ready(release.version.displayString)
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    func installAndRelaunch() {
        guard availableUpdateVersion != nil, fileManager.fileExists(atPath: stagedAppURL.path) else { return }
        // Launch Services refuses apps a sandboxed process wrote (`spctl`:
        // "File created by an AppSandbox, exec/open not allowed"). The staged
        // zip lives in the container, so its nested helper cannot be opened —
        // that produces "The application “SupersimpleUpdater.app” can’t be opened."
        // The helper that shipped inside the running bundle is already trusted.
        guard let helper = Self.helperURL() else {
            Self.log.error("updater helper is missing from the app bundle")
            return
        }

        let destination = installDestination()
        let pending = PendingUpdateInstall(
            sourcePath: stagedAppURL.path,
            destinationPath: destination.path,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try pending.write(to: PendingUpdateInstall.fileURL(in: stagingDirectory))
        } catch {
            Self.log.error("failed to write pending install: \(error.localizedDescription, privacy: .public)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--source", stagedAppURL.path,
            "--destination", destination.path,
            "--pid", String(pending.pid),
        ]

        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Self.log.error(
                        "failed to launch updater helper: \(error.localizedDescription, privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func isAlreadyStaged(_ version: AppVersion) -> Bool {
        guard fileManager.fileExists(atPath: stagedAppURL.path) else { return false }
        guard let raw = try? String(contentsOf: stagedVersionURL, encoding: .utf8) else { return false }
        return AppVersion(parsing: raw) == version
    }

    private func stage(_ release: GitHubRelease) async throws {
        let zip = stagingDirectory.appendingPathComponent("supersimple.zip")
        let extract = stagingDirectory.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try await transport.download(url: release.zipURL, to: zip)

        let app = try await Task.detached { [expectedBundleIdentifier] in
            try Self.extractApp(from: zip, to: extract, expectedBundleIdentifier: expectedBundleIdentifier)
        }.value

        try? fileManager.removeItem(at: stagedAppURL)
        try fileManager.copyItem(at: app, to: stagedAppURL)
        try release.version.displayString.write(to: stagedVersionURL, atomically: true, encoding: .utf8)
        try? fileManager.removeItem(at: zip)
        try? fileManager.removeItem(at: extract)
    }

    nonisolated private static func extractApp(
        from zip: URL,
        to extract: URL,
        expectedBundleIdentifier: String
    ) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: extract)
        try fm.createDirectory(at: extract, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, extract.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppUpdaterError.unzipFailed }

        guard let app = findApp(in: extract, fileManager: fm) else {
            throw AppUpdaterError.missingAppBundle
        }
        try validate(app: app, expectedBundleIdentifier: expectedBundleIdentifier)
        return app
    }

    nonisolated private static func findApp(in directory: URL, fileManager: FileManager) -> URL? {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        if let direct = contents.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            if let nested = findApp(in: item, fileManager: fileManager) { return nested }
        }
        return nil
    }

    nonisolated private static func validate(app: URL, expectedBundleIdentifier: String) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
            let identifier = plist["CFBundleIdentifier"] as? String,
            identifier == expectedBundleIdentifier
        else {
            throw AppUpdaterError.invalidAppBundle
        }
    }

    static func helperURL(in bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.builtInPlugInsURL?.appendingPathComponent("SupersimpleUpdater.app", isDirectory: true),
            bundle.url(forResource: "SupersimpleUpdater", withExtension: "app"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func installDestination() -> URL {
        if runningBundleURL.path.contains("AppTranslocation") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/supersimple.app", isDirectory: true)
        }
        return runningBundleURL
    }
}
