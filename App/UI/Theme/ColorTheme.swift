import AppKit
import SwiftUI

/// A named light+dark palette. `default` matches the original supersimple chrome.
struct ColorTheme: Identifiable, Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
        var a: CGFloat

        init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }

        init(hex: UInt32, alpha: CGFloat = 1) {
            r = CGFloat((hex >> 16) & 0xFF) / 255
            g = CGFloat((hex >> 8) & 0xFF) / 255
            b = CGFloat(hex & 0xFF) / 255
            a = alpha
        }

        var nsColor: NSColor {
            NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
        }

        var swiftUI: Color {
            Color(red: r, green: g, blue: b, opacity: a)
        }

        var hex: String {
            func byte(_ channel: CGFloat) -> UInt8 {
                UInt8((min(max(channel, 0), 1) * 255).rounded())
            }
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }

        func blended(onto base: RGB) -> RGB {
            let alpha = min(max(a, 0), 1)
            return RGB(
                r * alpha + base.r * (1 - alpha),
                g * alpha + base.g * (1 - alpha),
                b * alpha + base.b * (1 - alpha)
            )
        }

        func mixed(toward other: RGB, amount: CGFloat) -> RGB {
            let t = min(max(amount, 0), 1)
            return RGB(
                r + (other.r - r) * t,
                g + (other.g - g) * t,
                b + (other.b - b) * t
            )
        }

        /// WCAG relative luminance in sRGB.
        var relativeLuminance: CGFloat {
            func linear(_ channel: CGFloat) -> CGFloat {
                let x = min(max(channel, 0), 1)
                return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }

        func contrastRatio(against other: RGB) -> CGFloat {
            let lighter = relativeLuminance + 0.05
            let darker = other.relativeLuminance + 0.05
            return max(lighter, darker) / min(lighter, darker)
        }

        /// Mix toward black or white until `minimum` contrast against `background`.
        func ensuringContrast(against background: RGB, minimum: CGFloat) -> RGB {
            if contrastRatio(against: background) >= minimum { return self }
            let ink = background.relativeLuminance > 0.5 ? RGB(0, 0, 0) : RGB(1, 1, 1)
            var low: CGFloat = 0
            var high: CGFloat = 1
            var best = ink
            for _ in 0..<16 {
                let mid = (low + high) / 2
                let candidate = mixed(toward: ink, amount: mid)
                if candidate.contrastRatio(against: background) >= minimum {
                    best = candidate
                    high = mid
                } else {
                    low = mid
                }
            }
            return best
        }
    }

    struct Tokens: Equatable, Sendable {
        var background: RGB
        var editor: RGB
        var text: RGB
        var muted: RGB
        var accent: RGB

        func hairline(isDark: Bool) -> RGB {
            isDark ? RGB(1, 1, 1, 0.08) : RGB(0, 0, 0, 0.10)
        }

        func selection(isDark: Bool) -> RGB {
            isDark ? RGB(1, 1, 1, 0.12) : RGB(0, 0, 0, 0.09)
        }

        func hover(isDark: Bool) -> RGB {
            isDark ? RGB(1, 1, 1, 0.045) : RGB(0, 0, 0, 0.04)
        }

        func searchHighlight(isDark: Bool) -> RGB {
            isDark ? RGB(hex: 0xFBBF24, alpha: 0.28) : RGB(hex: 0xFACC15, alpha: 0.36)
        }

        func searchCurrentHighlight(isDark: Bool) -> RGB {
            isDark ? RGB(hex: 0xFBBF24, alpha: 0.52) : RGB(hex: 0xFACC15, alpha: 0.60)
        }
    }

    var id: String
    var name: String
    var dark: Tokens
    var light: Tokens

    func tokens(isDark: Bool) -> Tokens {
        isDark ? dark : light
    }

    static let defaultID = "default"

    static var current: ColorTheme {
        named(PaletteStore.shared.currentID)
    }

    static func named(_ id: String) -> ColorTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [ColorTheme] = [
        ColorTheme(
            id: "default",
            name: "Default",
            dark: Tokens(
                background: RGB(0.09, 0.09, 0.09),
                editor: RGB(0.125, 0.125, 0.125),
                text: RGB(0.94, 0.94, 0.94),
                muted: RGB(0.58, 0.59, 0.51),
                accent: RGB(0.82, 0.48, 0.38)
            ),
            light: Tokens(
                background: RGB(0.91, 0.905, 0.875),
                editor: RGB(0.985, 0.98, 0.955),
                text: RGB(0.10, 0.10, 0.10),
                muted: RGB(0.37, 0.38, 0.31),
                accent: RGB(0.82, 0.48, 0.38)
            )
        ),
        ColorTheme(
            id: "cursor",
            name: "Cursor",
            dark: Tokens(
                background: RGB(hex: 0x141414),
                editor: RGB(hex: 0x1A1A1A),
                text: RGB(hex: 0xE6E6E6),
                muted: RGB(hex: 0x8A8A8A),
                accent: RGB(hex: 0x3B82F6)
            ),
            light: Tokens(
                background: RGB(hex: 0xF3F3F3),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x1A1A1A),
                muted: RGB(hex: 0x6B6B6B),
                accent: RGB(hex: 0x2563EB)
            )
        ),
        ColorTheme(
            id: "raycast",
            name: "Raycast",
            dark: Tokens(
                background: RGB(hex: 0x0D0D0D),
                editor: RGB(hex: 0x161616),
                text: RGB(hex: 0xF5F5F5),
                muted: RGB(hex: 0x8F8F8F),
                accent: RGB(hex: 0x8B5CF6)
            ),
            light: Tokens(
                background: RGB(hex: 0xF4F4F5),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x18181B),
                muted: RGB(hex: 0x71717A),
                accent: RGB(hex: 0x7C3AED)
            )
        ),
        ColorTheme(
            id: "linear",
            name: "Linear",
            dark: Tokens(
                background: RGB(hex: 0x0F0F10),
                editor: RGB(hex: 0x191A1B),
                text: RGB(hex: 0xF7F8F8),
                muted: RGB(hex: 0x8A8F98),
                accent: RGB(hex: 0x5E6AD2)
            ),
            light: Tokens(
                background: RGB(hex: 0xF3F4F6),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x1A1D23),
                muted: RGB(hex: 0x6B7280),
                accent: RGB(hex: 0x5E6AD2)
            )
        ),
        ColorTheme(
            id: "arc",
            name: "Arc",
            dark: Tokens(
                background: RGB(hex: 0x241E1B),
                editor: RGB(hex: 0x2F2723),
                text: RGB(hex: 0xF4EDE6),
                muted: RGB(hex: 0xA8988C),
                accent: RGB(hex: 0xFF6A3D)
            ),
            light: Tokens(
                background: RGB(hex: 0xF3EBE3),
                editor: RGB(hex: 0xFFF9F3),
                text: RGB(hex: 0x2A211C),
                muted: RGB(hex: 0x8A7A70),
                accent: RGB(hex: 0xE54D2E)
            )
        ),
        ColorTheme(
            id: "notion",
            name: "Notion",
            dark: Tokens(
                background: RGB(hex: 0x191919),
                editor: RGB(hex: 0x202020),
                text: RGB(hex: 0xE6E6E6),
                muted: RGB(hex: 0x9B9B9B),
                accent: RGB(hex: 0x4B8BDB)
            ),
            light: Tokens(
                background: RGB(hex: 0xF7F6F3),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x37352F),
                muted: RGB(hex: 0x787774),
                accent: RGB(hex: 0x2383E2)
            )
        ),
        ColorTheme(
            id: "obsidian",
            name: "Obsidian",
            dark: Tokens(
                background: RGB(hex: 0x1E1E1E),
                editor: RGB(hex: 0x252525),
                text: RGB(hex: 0xDADADA),
                muted: RGB(hex: 0x8B8B8B),
                accent: RGB(hex: 0x7F6DF2)
            ),
            light: Tokens(
                background: RGB(hex: 0xF0EEEA),
                editor: RGB(hex: 0xFBFAF8),
                text: RGB(hex: 0x2E2E2E),
                muted: RGB(hex: 0x6F6B66),
                accent: RGB(hex: 0x705DCF)
            )
        ),
        ColorTheme(
            id: "writer",
            name: "Writer",
            dark: Tokens(
                background: RGB(hex: 0x161616),
                editor: RGB(hex: 0x1C1C1C),
                text: RGB(hex: 0xE8E8E8),
                muted: RGB(hex: 0x8C8C8C),
                accent: RGB(hex: 0x6B9BD1)
            ),
            light: Tokens(
                background: RGB(hex: 0xEFEDE6),
                editor: RGB(hex: 0xFAF9F5),
                text: RGB(hex: 0x1A1A1A),
                muted: RGB(hex: 0x6A6A6A),
                accent: RGB(hex: 0x1A5FB4)
            )
        ),
        ColorTheme(
            id: "things",
            name: "Things",
            dark: Tokens(
                background: RGB(hex: 0x1C1C1E),
                editor: RGB(hex: 0x2C2C2E),
                text: RGB(hex: 0xF2F2F7),
                muted: RGB(hex: 0x8E8E93),
                accent: RGB(hex: 0x4C7DFF)
            ),
            light: Tokens(
                background: RGB(hex: 0xEFEBE4),
                editor: RGB(hex: 0xFFFCFA),
                text: RGB(hex: 0x1C1C1E),
                muted: RGB(hex: 0x6E6E73),
                accent: RGB(hex: 0x4D7CFE)
            )
        ),
        ColorTheme(
            id: "craft",
            name: "Craft",
            dark: Tokens(
                background: RGB(hex: 0x1A1D21),
                editor: RGB(hex: 0x22262C),
                text: RGB(hex: 0xE8ECF1),
                muted: RGB(hex: 0x8B95A3),
                accent: RGB(hex: 0x5B8DEF)
            ),
            light: Tokens(
                background: RGB(hex: 0xE8ECF1),
                editor: RGB(hex: 0xF7F8FA),
                text: RGB(hex: 0x1C232C),
                muted: RGB(hex: 0x6B7380),
                accent: RGB(hex: 0x3D6FD9)
            )
        ),
        ColorTheme(
            id: "bear",
            name: "Bear",
            dark: Tokens(
                background: RGB(hex: 0x1C1917),
                editor: RGB(hex: 0x26211E),
                text: RGB(hex: 0xF3EDE6),
                muted: RGB(hex: 0xA39488),
                accent: RGB(hex: 0xE35D6A)
            ),
            light: Tokens(
                background: RGB(hex: 0xF3EBE0),
                editor: RGB(hex: 0xFFFDF9),
                text: RGB(hex: 0x2A2420),
                muted: RGB(hex: 0x8A7D73),
                accent: RGB(hex: 0xC74853)
            )
        ),
        ColorTheme(
            id: "mocha",
            name: "Mocha",
            dark: Tokens(
                background: RGB(hex: 0x181825),
                editor: RGB(hex: 0x1E1E2E),
                text: RGB(hex: 0xCDD6F4),
                muted: RGB(hex: 0xA6ADC8),
                accent: RGB(hex: 0xCBA6F7)
            ),
            light: Tokens(
                background: RGB(hex: 0xE6E9EF),
                editor: RGB(hex: 0xEFF1F5),
                text: RGB(hex: 0x4C4F69),
                muted: RGB(hex: 0x6C6F85),
                accent: RGB(hex: 0x8839EF)
            )
        ),
        ColorTheme(
            id: "nord",
            name: "Nord",
            dark: Tokens(
                background: RGB(hex: 0x2E3440),
                editor: RGB(hex: 0x3B4252),
                text: RGB(hex: 0xECEFF4),
                muted: RGB(hex: 0xD8DEE9),
                accent: RGB(hex: 0x88C0D0)
            ),
            light: Tokens(
                background: RGB(hex: 0xE5E9F0),
                editor: RGB(hex: 0xECEFF4),
                text: RGB(hex: 0x2E3440),
                muted: RGB(hex: 0x4C566A),
                accent: RGB(hex: 0x5E81AC)
            )
        ),
        ColorTheme(
            id: "tokyo-night",
            name: "Tokyo Night",
            dark: Tokens(
                background: RGB(hex: 0x16161E),
                editor: RGB(hex: 0x1A1B26),
                text: RGB(hex: 0xC0CAF5),
                muted: RGB(hex: 0x565F89),
                accent: RGB(hex: 0x7AA2F7)
            ),
            light: Tokens(
                background: RGB(hex: 0xD5D6DB),
                editor: RGB(hex: 0xE1E2E7),
                text: RGB(hex: 0x343B58),
                muted: RGB(hex: 0x6C6E85),
                accent: RGB(hex: 0x34548A)
            )
        ),
        ColorTheme(
            id: "solarized",
            name: "Solarized",
            dark: Tokens(
                background: RGB(hex: 0x002B36),
                editor: RGB(hex: 0x073642),
                text: RGB(hex: 0x839496),
                muted: RGB(hex: 0x586E75),
                accent: RGB(hex: 0x268BD2)
            ),
            light: Tokens(
                background: RGB(hex: 0xEEE8D5),
                editor: RGB(hex: 0xFDF6E3),
                text: RGB(hex: 0x657B83),
                muted: RGB(hex: 0x93A1A1),
                accent: RGB(hex: 0x268BD2)
            )
        ),
        ColorTheme(
            id: "dracula",
            name: "Dracula",
            dark: Tokens(
                background: RGB(hex: 0x21222C),
                editor: RGB(hex: 0x282A36),
                text: RGB(hex: 0xF8F8F2),
                muted: RGB(hex: 0x6272A4),
                accent: RGB(hex: 0xBD93F9)
            ),
            light: Tokens(
                background: RGB(hex: 0xEDEDF2),
                editor: RGB(hex: 0xF8F8FC),
                text: RGB(hex: 0x282A36),
                muted: RGB(hex: 0x6272A4),
                accent: RGB(hex: 0x7C3AED)
            )
        ),
        ColorTheme(
            id: "gruvbox",
            name: "Gruvbox",
            dark: Tokens(
                background: RGB(hex: 0x1D2021),
                editor: RGB(hex: 0x282828),
                text: RGB(hex: 0xEBDBB2),
                muted: RGB(hex: 0xA89984),
                accent: RGB(hex: 0xFE8019)
            ),
            light: Tokens(
                background: RGB(hex: 0xEBDBB2),
                editor: RGB(hex: 0xFBF1C7),
                text: RGB(hex: 0x3C3836),
                muted: RGB(hex: 0x7C6F64),
                accent: RGB(hex: 0xAF3A03)
            )
        ),
        ColorTheme(
            id: "github",
            name: "GitHub",
            dark: Tokens(
                background: RGB(hex: 0x1C2128),
                editor: RGB(hex: 0x22272E),
                text: RGB(hex: 0xADBAC7),
                muted: RGB(hex: 0x768390),
                accent: RGB(hex: 0x539BF5)
            ),
            light: Tokens(
                background: RGB(hex: 0xF6F8FA),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x24292F),
                muted: RGB(hex: 0x57606A),
                accent: RGB(hex: 0x0969DA)
            )
        ),
        ColorTheme(
            id: "geist",
            name: "Geist",
            dark: Tokens(
                background: RGB(hex: 0x000000),
                editor: RGB(hex: 0x0A0A0A),
                text: RGB(hex: 0xEDEDED),
                muted: RGB(hex: 0x888888),
                accent: RGB(hex: 0xFFFFFF)
            ),
            light: Tokens(
                background: RGB(hex: 0xF2F2F2),
                editor: RGB(hex: 0xFFFFFF),
                text: RGB(hex: 0x000000),
                muted: RGB(hex: 0x666666),
                accent: RGB(hex: 0x000000)
            )
        ),
        ColorTheme(
            id: "midnight",
            name: "Midnight",
            dark: Tokens(
                background: RGB(hex: 0x0B1220),
                editor: RGB(hex: 0x111827),
                text: RGB(hex: 0xE5E7EB),
                muted: RGB(hex: 0x9CA3AF),
                accent: RGB(hex: 0xD4A574)
            ),
            light: Tokens(
                background: RGB(hex: 0xE8EEF6),
                editor: RGB(hex: 0xF7F9FC),
                text: RGB(hex: 0x0F172A),
                muted: RGB(hex: 0x64748B),
                accent: RGB(hex: 0xB45309)
            )
        ),
    ]
}

/// Process-wide selected palette so `NSColor` dynamic providers can resolve off the main thread.
final class PaletteStore: @unchecked Sendable {
    static let shared = PaletteStore()
    private let lock = NSLock()
    private var storedID = ColorTheme.defaultID

    var currentID: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedID
        }
        set {
            lock.lock()
            storedID = newValue
            lock.unlock()
        }
    }
}
