import Foundation

/// A GitHub Releases payload reduced to the zip we can install.
public struct GitHubRelease: Equatable, Sendable {
    public let tagName: String
    public let version: AppVersion
    public let zipURL: URL
    public let zipName: String

    public init(tagName: String, version: AppVersion, zipURL: URL, zipName: String) {
        self.tagName = tagName
        self.version = version
        self.zipURL = zipURL
        self.zipName = zipName
    }

    /// Decodes `/repos/{owner}/{repo}/releases/latest` JSON and picks `supersimple.zip`,
    /// falling back to the first `.zip` asset.
    public static func parseLatest(_ data: Data) throws -> GitHubRelease {
        let dto = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        guard
            let asset = dto.assets.first(where: { $0.name.lowercased() == "supersimple.zip" })
                ?? dto.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
        else {
            throw GitHubReleaseError.missingZipAsset
        }
        return GitHubRelease(
            tagName: dto.tagName,
            version: AppVersion(parsing: dto.tagName),
            zipURL: asset.browserDownloadURL,
            zipName: asset.name
        )
    }
}

public enum GitHubReleaseError: Error, Equatable {
    case missingZipAsset
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
