import SwiftUI

/// Central design tokens. Two surfaces: a slightly sunken library, and paper for writing.
///
/// Hue is reserved for links. Selection, hover, and chrome are value shifts of
/// the same charcoal / taupe — never the system accent.
enum AppTheme {

    enum Color {
        /// Warm ink for links only. Not used as a fill.
        static let accent = NSColor(
            calibratedRed: 0.82, green: 0.48, blue: 0.38, alpha: 1.0
        )
        /// Window chrome and library. Charcoal in dark, warm taupe in light.
        static let background = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 0.09, alpha: 1.0)
                : NSColor(calibratedRed: 0.91, green: 0.905, blue: 0.875, alpha: 1.0)
        }
        static let sidebarBackground = background
        static let editorSurface = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 0.125, alpha: 1.0)
                : NSColor(calibratedRed: 0.985, green: 0.98, blue: 0.955, alpha: 1.0)
        }
        static let editorText = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 0.94, alpha: 1.0)
                : NSColor(calibratedWhite: 0.1, alpha: 1.0)
        }
        static let mutedText = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedRed: 0.58, green: 0.59, blue: 0.51, alpha: 1.0)
                : NSColor(calibratedRed: 0.37, green: 0.38, blue: 0.31, alpha: 1.0)
        }
        static let hairline = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.08)
                : NSColor(calibratedWhite: 0.0, alpha: 0.1)
        }
        /// Selected library row: a lift of the sidebar, not a tint.
        static let selectionFill = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
                : NSColor(calibratedWhite: 0.0, alpha: 0.09)
        }
        static let hoverFill = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.045)
                : NSColor(calibratedWhite: 0.0, alpha: 0.04)
        }
    }

    enum Metric {
        static let sidebarWidth: CGFloat = 248
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarMaxWidth: CGFloat = 340
        static let editorMinWidth: CGFloat = 560
        static let readingWidth: CGFloat = 640
        static let hairlineWidth: CGFloat = 0.5
        static let controlRadius: CGFloat = 8
        static let bodyFontSize: CGFloat = 17
    }

    /// SwiftUI colors resolved for a known scheme. Use these in the toolbar so
    /// chrome does not wait on AppKit's appearance fade.
    static func backgroundColor(isDark: Bool) -> SwiftUI.Color {
        isDark
            ? SwiftUI.Color(white: 0.09)
            : SwiftUI.Color(red: 0.91, green: 0.905, blue: 0.875)
    }

    static func sidebarBackgroundColor(isDark: Bool) -> SwiftUI.Color {
        backgroundColor(isDark: isDark)
    }

    static func mutedColor(isDark: Bool) -> SwiftUI.Color {
        isDark
            ? SwiftUI.Color(red: 0.58, green: 0.59, blue: 0.51)
            : SwiftUI.Color(red: 0.37, green: 0.38, blue: 0.31)
    }

    static func textColor(isDark: Bool) -> SwiftUI.Color {
        isDark
            ? SwiftUI.Color(white: 0.94)
            : SwiftUI.Color(white: 0.1)
    }

    /// Re-export a hairline `Color` for SwiftUI overlay usage.
    static var hairline: SwiftUI.Color { SwiftUI.Color(nsColor: Color.hairline) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension SwiftUI.Color {
    static let supersimpleAccent = Color(nsColor: AppTheme.Color.accent)
    static let supersimpleMuted = Color(nsColor: AppTheme.Color.mutedText)
}
