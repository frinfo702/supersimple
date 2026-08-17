import AppKit
import CoreText
import MarkdownEngine

/// Lightweight, native `SyntaxHighlighter` for the Markdown engine.
///
/// Uses Geist Mono for code, a subtle block fill, and a compact regex-based
/// tokenizer for a handful of common languages. Deliberately free of any
/// JavaScript runtime and theme bundles, keeping the binary tiny.
final class NativeCodeHighlighter: SyntaxHighlighter {

    private struct TokenRule {
        let pattern: NSRegularExpression
        let color: NSColor
    }

    private let supportedLanguages: Set<String> = [
        "swift", "python", "js", "javascript", "ts", "typescript", "rust", "go",
        "c", "cpp", "csharp", "bash", "shell", "zsh", "ruby", "java", "kotlin",
        "sql", "json", "yaml", "yml", "html", "css", "xml",
    ]

    /// Returns a dynamic `NSColor` resolving to a dark-palette token in dark mode and an
    /// accessible, higher-contrast token in light mode.
    private static func tokenColor(dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(
                calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1.0
            )
        }
    }

    private func rules() -> [TokenRule] {
        let keywordRules: [(String, UInt32, UInt32)] = [
            (
                "\\b(?:func|class|struct|enum|let|var|if|else|guard|return|import|public|private|internal|init|self|switch|case|default|where|in|throws)\\b",
                0x58A6FF, 0x0550AE
            ),
            (
                "\\b(?:def|class|import|return|from|as|if|elif|else|for|while|try|except|lambda|None|True|False)\\b",
                0x58A6FF, 0x0550AE
            ),
            (
                "\\b(?:function|const|let|var|return|import|export|default|if|else|for|while|typeof|new|this)\\b",
                0x58A6FF, 0x0550AE
            ),
            (
                "\\b(?:fn|let|mut|const|pub|struct|enum|impl|trait|return|if|else|match|for|while|use|mod)\\b",
                0x58A6FF, 0x0550AE
            ),
            ("\\b(?:func|var|const|package|import|return|if|else|for|range|map|defer|go)\\b", 0x58A6FF, 0x0550AE),
            ("\\\"(?:\\\\.|[^\\\"\\\\])*\\\"|'(?:\\\\.|[^'\\\\])*'", 0xA5D6FF, 0x8B2C31),
            ("\\b(?:0x[0-9a-fA-F]+|[0-9]+(?:\\.[0-9]+)?)\\b", 0xF0883E, 0x9A4D00),
            ("(?m)^\\s*(?://|#|--|;;|//!|///)[^\\n]*$", 0x6E7681, 0x57606A),
            ("/\\*[\\s\\S]*?\\*/|/\\*|\\*/", 0x6E7681, 0x57606A),
        ]
        return keywordRules.map { rule($0.0, dark: $0.1, light: $0.2) }
    }

    private func rule(_ pattern: String, dark: UInt32, light: UInt32) -> TokenRule {
        TokenRule(
            pattern: (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression(),
            color: Self.tokenColor(dark: dark, light: light)
        )
    }

    // MARK: - SyntaxHighlighter

    func codeFont(size: CGFloat) -> NSFont {
        GeistCodeFont.font(ofSize: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func backgroundColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 0.5, alpha: 0.10)
                : NSColor(calibratedWhite: 0.0, alpha: 0.045)
        }
    }

    func highlight(code: String, language: String?) -> NSAttributedString? {
        guard let language, supportedLanguages.contains(language) else { return nil }

        let baseFont = codeFont(size: 14)
        let base = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let fullRange = NSRange(location: 0, length: (code as NSString).length)
        for rule in rules() {
            rule.pattern.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                base.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }
        return base
    }

    var appearanceDidChangeNotification: Notification.Name? {
        // Theme uses dynamic `NSColor`s, so a notification isn't strictly required.
        Notification.Name("AppleInterfaceThemeChangedNotification")
    }
}

/// Registers the bundled Geist Mono variable font and exposes it by PostScript name.
enum GeistCodeFont {
    static let postScriptName = "GeistMono-Regular"

    nonisolated(unsafe) private static var isRegistered = false
    private static let lock = NSLock()

    static func registerIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else { return }
        isRegistered = true
        guard let url = Bundle.main.url(forResource: "GeistMono", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(ofSize size: CGFloat) -> NSFont? {
        registerIfNeeded()
        if let named = NSFont(name: postScriptName, size: size) {
            return named
        }
        return NSFont(name: "GeistMono", size: size)
    }
}
