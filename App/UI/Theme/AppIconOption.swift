import AppKit

/// Built-in Dock / app icons. Images live in the asset catalog as `AppIcon*`.
struct AppIconOption: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var assetName: String

    static let `default` = AppIconOption(id: "default", name: "Default", assetName: "AppIconDefault")

    static let all: [AppIconOption] = [
        .default,
        AppIconOption(id: "paper", name: "Paper", assetName: "AppIconPaper"),
        AppIconOption(id: "ink", name: "Ink", assetName: "AppIconInk"),
        AppIconOption(id: "ember", name: "Ember", assetName: "AppIconEmber"),
        AppIconOption(id: "moss", name: "Moss", assetName: "AppIconMoss"),
        AppIconOption(id: "violet", name: "Violet", assetName: "AppIconViolet"),
        AppIconOption(id: "frost", name: "Frost", assetName: "AppIconFrost"),
        AppIconOption(id: "noir", name: "Noir", assetName: "AppIconNoir"),
        AppIconOption(id: "ghost", name: "Ghost", assetName: "AppIconGhost"),
    ]

    static func named(_ id: String) -> AppIconOption {
        all.first { $0.id == id } ?? .default
    }

    var image: NSImage? {
        NSImage(named: assetName)
    }
}
