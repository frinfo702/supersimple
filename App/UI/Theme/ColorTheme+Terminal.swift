import CoreGraphics
import GhosttyTerminal

extension ColorTheme {
    /// Contrast floor so `# comments` (usually ANSI black / bright-black) stay
    /// readable on the editor surface. UI `background` is too close to `editor`.
    static let terminalCommentContrast: CGFloat = 3

    /// Ghostty light+dark configs whose chrome tracks this palette.
    func terminalTheme() -> TerminalTheme {
        TerminalTheme(
            light: Self.terminalConfiguration(tokens: light, isDark: false),
            dark: Self.terminalConfiguration(tokens: dark, isDark: true)
        )
    }

    private static func terminalConfiguration(tokens: Tokens, isDark: Bool) -> TerminalConfiguration {
        let background = tokens.editor.hex
        let foreground = tokens.text.hex
        let cursor = tokens.accent.hex
        let selection = tokens.selection(isDark: isDark).blended(onto: tokens.editor).hex
        let ansi = ANSIPalette(tokens: tokens, isDark: isDark)

        return TerminalConfiguration { builder in
            builder.withBackground(background)
            builder.withForeground(foreground)
            builder.withCursorColor(cursor)
            builder.withCursorText(background)
            builder.withSelectionBackground(selection)
            builder.withSelectionForeground(foreground)
            builder.withMinimumContrast(Double(ColorTheme.terminalCommentContrast))
            for index in 0...15 {
                builder.withPalette(index, color: ansi[index])
            }
        }
    }
}

extension ColorTheme.Tokens {
    /// ANSI 0. Shell comments are often `fg=black` / `fg=black,bold`.
    func terminalBlack() -> ColorTheme.RGB {
        ColorTheme.RGB(0, 0, 0).ensuringContrast(
            against: editor,
            minimum: ColorTheme.terminalCommentContrast
        )
    }

    /// ANSI 8 (bright black) — the other common comment color.
    func terminalBrightBlack() -> ColorTheme.RGB {
        muted.ensuringContrast(
            against: editor,
            minimum: ColorTheme.terminalCommentContrast
        )
    }

    func terminalWhite(isDark: Bool) -> ColorTheme.RGB {
        isDark ? text : editor
    }
}

/// 16-color set: contrast-safe black/white in 0/7/8/15, Afterglow/Alabaster hues elsewhere.
private struct ANSIPalette {
    private let colors: [String]

    init(tokens: ColorTheme.Tokens, isDark: Bool) {
        let hues = isDark ? Self.darkHues : Self.lightHues
        colors = [
            tokens.terminalBlack().hex,
            hues[0], hues[1], hues[2], hues[3], hues[4], hues[5],
            tokens.terminalWhite(isDark: isDark).hex,
            tokens.terminalBrightBlack().hex,
            hues[6], hues[7], hues[8], hues[9], hues[10], hues[11],
            tokens.terminalWhite(isDark: isDark).hex,
        ]
    }

    subscript(index: Int) -> String { colors[index] }

    private static let darkHues = [
        "#AC4142", "#7E8E50", "#E4B567", "#6C99BB", "#9F4E86", "#7DD5CF",
        "#AC4142", "#7E8E50", "#E4B567", "#6C99BB", "#9F4E86", "#7DD5CF",
    ]

    private static let lightHues = [
        "#AA3731", "#448C27", "#CB8800", "#325CC0", "#7A3E9D", "#0083B2",
        "#F03E31", "#60CB00", "#FFBC5D", "#007ACC", "#E64CE6", "#00AACB",
    ]
}
