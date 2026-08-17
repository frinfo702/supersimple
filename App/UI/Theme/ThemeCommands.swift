import AppKit
import SwiftUI

/// Appearance menu: System / Light / Dark, persisted across launches.
struct ThemeCommands: Commands {
    @Bindable var themeManager: ThemeManager

    var body: some Commands {
        CommandMenu("Appearance") {
            ForEach(ThemeManager.Preference.allCases) { preference in
                Button(preference.label) {
                    themeManager.preference = preference
                }
                .keyboardShortcut(preference.shortcut, modifiers: [.command, .shift])
            }
        }
    }
}

extension ThemeManager.Preference {
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .system: "s"
        case .light: "l"
        case .dark: "d"
        }
    }
}
