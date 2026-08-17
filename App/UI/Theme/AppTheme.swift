import SwiftUI

/// Central design tokens for the Superlogical-inspired visual language.
enum AppTheme {

    enum Color {
        /// Warm accent used sparingly for focus and selection.
        static let accent = NSColor(
            calibratedRed: 0.96, green: 0.56, blue: 0.43, alpha: 1.0
        )
        static let background = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedWhite: 0.025, alpha: 1.0)
                : NSColor(calibratedRed: 0.95, green: 0.945, blue: 0.92, alpha: 1.0)
        }
        static let sidebarBackground = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedRed: 0.035, green: 0.036, blue: 0.032, alpha: 1.0)
                : NSColor(calibratedRed: 0.91, green: 0.905, blue: 0.875, alpha: 1.0)
        }
        static let editorSurface = NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(calibratedRed: 0.065, green: 0.065, blue: 0.06, alpha: 0.97)
                : NSColor(calibratedRed: 0.985, green: 0.98, blue: 0.955, alpha: 0.98)
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
                ? NSColor(calibratedWhite: 1.0, alpha: 0.07)
                : NSColor(calibratedWhite: 0.0, alpha: 0.1)
        }
        static let selectionFill = NSColor(name: nil) { appearance in
            appearance.isDark
                ? accent.withAlphaComponent(0.13)
                : accent.withAlphaComponent(0.18)
        }
    }

    static let editorGradient = LinearGradient(
        stops: [
            .init(color: SwiftUI.Color(red: 0.9, green: 0.34, blue: 0.5), location: 0),
            .init(color: SwiftUI.Color(red: 0.72, green: 0.47, blue: 0.88), location: 0.25),
            .init(color: SwiftUI.Color(red: 0.96, green: 0.48, blue: 0.3), location: 0.5),
            .init(color: SwiftUI.Color(red: 0.95, green: 0.68, blue: 0.22), location: 0.73),
            .init(color: SwiftUI.Color(red: 0.35, green: 0.59, blue: 0.4), location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Metric {
        static let sidebarWidth: CGFloat = 300
        static let editorMinWidth: CGFloat = 560
        static let readingWidth: CGFloat = 720
        static let hairlineWidth: CGFloat = 1
        static let controlRadius: CGFloat = 10
        static let editorRadius: CGFloat = 30
        static let editorSurfaceRadius: CGFloat = 23
    }
}

extension NSAppearance {
    fileprivate var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Color {
    static let supersimpleAccent = Color(nsColor: AppTheme.Color.accent)
    static let supersimpleMuted = Color(nsColor: AppTheme.Color.mutedText)
}
