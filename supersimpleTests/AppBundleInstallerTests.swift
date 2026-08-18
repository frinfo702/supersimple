import Foundation
import Testing

@testable import supersimple

@Suite("AppBundleInstaller")
struct AppBundleInstallerTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "supersimple-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeApp(at url: URL, marker: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try marker.write(to: contents.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    @Test("Replaces an existing app bundle instead of nesting inside it")
    func replacesExistingApp() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.app", isDirectory: true)
        let destination = dir.appendingPathComponent("supersimple.app", isDirectory: true)
        try makeApp(at: source, marker: "new")
        try makeApp(at: destination, marker: "old")

        try AppBundleInstaller.replace(source: source, destination: destination)

        let marker = try String(
            contentsOf: destination.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
        #expect(marker == "new")
        #expect(
            !FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("source.app").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("supersimple.app").path))
    }

    @Test("Creates the destination when it does not exist")
    func copiesWhenMissing() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.app", isDirectory: true)
        let destination = dir.appendingPathComponent("Apps/supersimple.app", isDirectory: true)
        try makeApp(at: source, marker: "new")

        try AppBundleInstaller.replace(source: source, destination: destination)

        let marker = try String(
            contentsOf: destination.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
        #expect(marker == "new")
    }
}

@Suite("PendingUpdateInstall")
struct PendingUpdateInstallTests {
    @Test("Round-trips JSON and parses command-line arguments")
    func roundTripAndArgv() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let pending = PendingUpdateInstall(
            sourcePath: "/tmp/source.app",
            destinationPath: "/tmp/dest.app",
            pid: 4242
        )
        let url = PendingUpdateInstall.fileURL(in: dir)
        try pending.write(to: url)
        #expect(try PendingUpdateInstall.load(from: url) == pending)

        let parsed = PendingUpdateInstall.parseCommandLine([
            "SupersimpleUpdater",
            "--source", "/tmp/source.app",
            "--destination", "/tmp/dest.app",
            "--pid", "4242",
        ])
        #expect(parsed == pending)
    }
}
