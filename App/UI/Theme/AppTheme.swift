import SwiftUI

/// Central design tokens for the minimalist (Superlogical-inspired) look.
/// Colors are dynamic `NSColor`s so light/dark mode is handled natively.
enum AppTheme {

    enum Color {
        /// Warm, restrained accent used sparingly (selection, focus). ~`#C7745A`.
        static let accent = NSColor(
            calibratedRed: 0.78, green: 0.455, blue: 0.353, alpha: 1.0
        )
        /// Near-black canvas background for dark mode. ~`#0E0E0E`.
        static let background = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.060, alpha: 1.0)
                : NSColor(calibratedWhite: 0.97, alpha: 1.0)
        }
        /// Sidebar fill, subtly darker than the canvas.
        static let sidebarBackground = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.080, alpha: 1.0)
                : NSColor(calibratedWhite: 0.93, alpha: 1.0)
        }
        /// Fine hairline separators.
        static let hairline = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.07)
                : NSColor(calibratedWhite: 0.0, alpha: 0.08)
        }
        /// Row highlight behind the selected note / hovered tag.
        static let selectionFill = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                : NSColor.controlAccentColor.withAlphaComponent(0.13)
        }
    }

    enum Metric {
        static let sidebarWidth: CGFloat = 280
        static let readingWidth: CGFloat = 680
        static let hairlineWidth: CGFloat = 1
        static let cornerRadius: CGFloat = 6
    }
}

extension Color {
    static let supersimpleAccent = Color(nsColor: AppTheme.Color.accent)
}
