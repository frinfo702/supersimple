import AppKit
import QuartzCore
import SwiftUI

/// Controls the app-level color scheme preference (System / Light / Dark),
/// persisted in `UserDefaults` and exposed to SwiftUI via `preferredColorScheme`.
@MainActor
@Observable
final class ThemeManager {
    enum Preference: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private static let key = "com.frinfo702.supersimple.theme"

    var preference: Preference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.key)
            apply()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? Preference.system.rawValue
        preference = Preference(rawValue: raw) ?? .system
        // Defer the first application until after launch so `NSApp` exists and the
        // explicit nil (system) round-trip is safe.
        DispatchQueue.main.async { [weak self] in
            self?.apply()
        }
    }

    /// True when the resolved scheme is dark (explicit preference, or system).
    func isDark(matching colorScheme: ColorScheme) -> Bool {
        switch preference {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    /// Assigns `preference` without SwiftUI interpolating toolbar chrome.
    func setPreferenceImmediately(_ newValue: Preference) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            preference = newValue
        }
    }

    /// Toggles Light ↔ Dark, resolving `.system` from the current effective appearance.
    func cycle() {
        setPreferenceImmediately(currentlyDark ? .light : .dark)
    }

    private var currentlyDark: Bool {
        switch preference {
        case .dark: true
        case .light: false
        case .system: NSApp.effectiveAppearance.isDark
        }
    }

    private func apply() {
        let appearance: NSAppearance?
        switch preference {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        // AppKit otherwise fades the titlebar/toolbar a beat after SwiftUI content.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            NSApp.appearance = appearance
            for window in NSApp.windows {
                window.animations["appearance"] = NSNull()
                window.appearance = appearance
            }
        }
        CATransaction.commit()
    }
}
