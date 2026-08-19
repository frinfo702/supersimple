import AppKit
import SwiftUI

/// Note-body fonts that resolve to a real face on every supported macOS.
enum EditorFont: String, CaseIterable, Identifiable, Sendable {
    case sfPro
    case charter
    case iowan
    case avenirNext
    case palatino

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sfPro: "SF Pro"
        case .charter: "Charter"
        case .iowan: "Iowan Old Style"
        case .avenirNext: "Avenir Next"
        case .palatino: "Palatino"
        }
    }

    /// Compact chip label used in Settings.
    var shortName: String {
        switch self {
        case .sfPro: "SF Pro"
        case .charter: "Charter"
        case .iowan: "Iowan"
        case .avenirNext: "Avenir"
        case .palatino: "Palatino"
        }
    }

    /// PostScript name consumed by the Markdown engine's `NSFont(name:size:)`.
    var postScriptName: String {
        switch self {
        case .sfPro: ".AppleSystemUIFont"
        case .charter: "Charter-Roman"
        case .iowan: "IowanOldStyle-Roman"
        case .avenirNext: "AvenirNext-Regular"
        case .palatino: "Palatino-Roman"
        }
    }

    func nsFont(ofSize size: CGFloat) -> NSFont {
        NSFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
    }

    func swiftUIFont(ofSize size: CGFloat) -> Font {
        Font(nsFont(ofSize: size))
    }
}

enum EditorFontSize {
    static let `default`: CGFloat = 17
    static let all: [CGFloat] = [15, 16, 17, 18, 20, 22]

    static func clamp(_ value: CGFloat) -> CGFloat {
        let nearest = all.min(by: { abs($0 - value) < abs($1 - value) }) ?? `default`
        return nearest
    }
}
