import Foundation
import Testing

@testable import supersimple

private struct MockTransport: UpdateTransport {
    var releaseJSON: Data
    var zipURL: URL

    func get(url: URL) async throws -> Data { releaseJSON }

    func download(url: URL, to file: URL) async throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: zipURL, to: file)
    }
}

@MainActor
@Suite("AppUpdater")
struct AppUpdaterTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "supersimple-updater-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeZip(in dir: URL, bundleID: String = "com.frinfo702.supersimple") throws -> URL {
        let app = dir.appendingPathComponent("supersimple.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleIdentifier</key>
                <string>\(bundleID)</string>
            </dict>
            </plist>
            """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("supersimple.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return zip
    }

    private func releaseJSON(tag: String) -> Data {
        """
        {
          "tag_name": "\(tag)",
          "assets": [
            { "name": "supersimple.zip", "browser_download_url": "https://example.com/supersimple.zip" }
          ]
        }
        """.data(using: .utf8)!
    }

    @Test("Downloads a newer release and marks it ready")
    func downloadsNewerRelease() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zip = try makeZip(in: dir)
        let staging = dir.appendingPathComponent("staging")
        let updater = AppUpdater(
            currentVersion: "0.1.0",
            stagingDirectory: staging,
            transport: MockTransport(releaseJSON: releaseJSON(tag: "v0.1.0.4"), zipURL: zip),
            enabled: true
        )

        await updater.checkAndDownloadIfNeeded()

        #expect(updater.availableUpdateVersion == "0.1.0.4")
        #expect(FileManager.default.fileExists(atPath: updater.stagedAppURL.path))
    }

    @Test("Does not offer an update when already on the latest version")
    func skipsWhenCurrent() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zip = try makeZip(in: dir)
        let updater = AppUpdater(
            currentVersion: "0.1.0.4",
            stagingDirectory: dir.appendingPathComponent("staging"),
            transport: MockTransport(releaseJSON: releaseJSON(tag: "v0.1.0.4"), zipURL: zip),
            enabled: true
        )

        await updater.checkAndDownloadIfNeeded()

        #expect(updater.availableUpdateVersion == nil)
    }

    @Test("Does nothing when updates are disabled")
    func disabled() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zip = try makeZip(in: dir)
        let updater = AppUpdater(
            currentVersion: "0.1.0",
            stagingDirectory: dir.appendingPathComponent("staging"),
            transport: MockTransport(releaseJSON: releaseJSON(tag: "v9.0.0"), zipURL: zip),
            enabled: false
        )

        await updater.checkAndDownloadIfNeeded()

        #expect(updater.availableUpdateVersion == nil)
    }

    @Test("Rejects a zip whose app bundle id does not match")
    func rejectsWrongBundle() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let zip = try makeZip(in: dir, bundleID: "com.example.other")
        let updater = AppUpdater(
            currentVersion: "0.1.0",
            stagingDirectory: dir.appendingPathComponent("staging"),
            transport: MockTransport(releaseJSON: releaseJSON(tag: "v0.2.0"), zipURL: zip),
            enabled: true
        )

        await updater.checkAndDownloadIfNeeded()

        #expect(updater.availableUpdateVersion == nil)
        #expect(!FileManager.default.fileExists(atPath: updater.stagedAppURL.path))
    }

    @Test("shouldEnable is off in tests and DerivedData")
    func shouldEnableGates() {
        #expect(AppUpdater.shouldEnable(environment: ["SUPERSIMPLE_DISABLE_UPDATES": "1"]) == false)
        #expect(AppUpdater.shouldEnable(environment: ["XCTestConfigurationFilePath": "/tmp/xctest"]) == false)
        #expect(
            AppUpdater.shouldEnable(environment: [:], bundlePath: "/tmp/DerivedData/Build/supersimple.app") == false)
        #expect(AppUpdater.shouldEnable(environment: [:], bundlePath: "/Applications/supersimple.app") == true)
    }
}
