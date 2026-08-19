import AppKit
import SwiftUI

/// Snapshot of the active palette for the current light/dark mode.
///
/// Dynamic `NSColor(name:)` tokens cache until appearance changes, so palettes
/// are baked into value-typed colors and pushed through the environment.
struct PaletteColors: Equatable {
    var themeID: String
    var isDark: Bool
    var background: Color
    var editor: Color
    var text: Color
    var muted: Color
    var accent: Color
    var hairline: Color
    var selection: Color
    var hover: Color
    var nsBackground: NSColor
    var nsText: NSColor
    var nsMuted: NSColor
    var nsAccent: NSColor

    static func == (lhs: PaletteColors, rhs: PaletteColors) -> Bool {
        lhs.themeID == rhs.themeID && lhs.isDark == rhs.isDark
    }

    init(isDark: Bool, theme: ColorTheme = ColorTheme.current) {
        themeID = theme.id
        self.isDark = isDark
        let tokens = theme.tokens(isDark: isDark)
        background = tokens.background.swiftUI
        editor = tokens.editor.swiftUI
        text = tokens.text.swiftUI
        muted = tokens.muted.swiftUI
        accent = tokens.accent.swiftUI
        hairline = tokens.hairline(isDark: isDark).swiftUI
        selection = tokens.selection(isDark: isDark).swiftUI
        hover = tokens.hover(isDark: isDark).swiftUI
        nsBackground = tokens.background.nsColor
        nsText = tokens.text.nsColor
        nsMuted = tokens.muted.nsColor
        nsAccent = tokens.accent.nsColor
    }
}

private struct PaletteColorsKey: EnvironmentKey {
    static let defaultValue = PaletteColors(isDark: true)
}

extension EnvironmentValues {
    var palette: PaletteColors {
        get { self[PaletteColorsKey.self] }
        set { self[PaletteColorsKey.self] = newValue }
    }
}

/// Central design tokens. Two surfaces: a slightly sunken library, and paper for writing.
///
/// Hue is reserved for links. Selection, hover, and chrome are value shifts of
/// the same charcoal / taupe — never the system accent.
enum AppTheme {

    enum Metric {
        static let sidebarWidth: CGFloat = 248
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarMaxWidth: CGFloat = 340
        static let editorMinWidth: CGFloat = 560
        static let terminalHeight: CGFloat = 220
        static let terminalMinHeight: CGFloat = 120
        static let terminalMaxHeight: CGFloat = 480
        static let readingWidth: CGFloat = 640
        static let hairlineWidth: CGFloat = 0.5
        static let controlRadius: CGFloat = 8
        static let bodyFontSize: CGFloat = EditorFontSize.default
    }

    static func colors(isDark: Bool, theme: ColorTheme) -> PaletteColors {
        PaletteColors(isDark: isDark, theme: theme)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
