import Foundation
import Testing

@testable import SupersimpleCore

@Suite("GitHubRelease")
struct GitHubReleaseTests {

    @Test("Picks supersimple.zip from a latest-release payload")
    func parseLatestZip() throws {
        let json = """
            {
              "tag_name": "v0.1.0.4",
              "assets": [
                { "name": "notes.txt", "browser_download_url": "https://example.com/notes.txt" },
                { "name": "supersimple.zip", "browser_download_url": "https://example.com/supersimple.zip" }
              ]
            }
            """.data(using: .utf8)!

        let release = try GitHubRelease.parseLatest(json)
        #expect(release.tagName == "v0.1.0.4")
        #expect(release.version == AppVersion(parsing: "0.1.0.4"))
        #expect(release.zipURL.absoluteString == "https://example.com/supersimple.zip")
    }

    @Test("Falls back to the first zip when the canonical name is missing")
    func parseFallbackZip() throws {
        let json = """
            {
              "tag_name": "v1.2.3",
              "assets": [
                { "name": "supersimple-mac.zip", "browser_download_url": "https://example.com/mac.zip" }
              ]
            }
            """.data(using: .utf8)!

        let release = try GitHubRelease.parseLatest(json)
        #expect(release.zipName == "supersimple-mac.zip")
    }

    @Test("Throws when the release has no zip asset")
    func missingZip() {
        let json = """
            {
              "tag_name": "v0.1.0",
              "assets": [
                { "name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt" }
              ]
            }
            """.data(using: .utf8)!

        #expect(throws: GitHubReleaseError.missingZipAsset) {
            try GitHubRelease.parseLatest(json)
        }
    }
}
