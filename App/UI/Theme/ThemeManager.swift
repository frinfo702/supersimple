import AppKit
import QuartzCore
import SwiftUI

/// Controls appearance: System / Light / Dark, color palette, note typography, and Dock icon.
/// Persisted in `UserDefaults` and exposed to SwiftUI via `preferredColorScheme`.
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

    private static let themeKey = "com.frinfo702.supersimple.theme"
    private static let paletteKey = "com.frinfo702.supersimple.palette"
    private static let fontKey = "com.frinfo702.supersimple.editorFont"
    private static let fontSizeKey = "com.frinfo702.supersimple.editorFontSize"
    private static let iconKey = "com.frinfo702.supersimple.appIcon"

    private let defaults: UserDefaults

    var preference: Preference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.themeKey)
            apply()
            styleRevision += 1
        }
    }

    var paletteID: String {
        didSet {
            defaults.set(paletteID, forKey: Self.paletteKey)
            PaletteStore.shared.currentID = paletteID
            styleRevision += 1
            invalidateChrome()
        }
    }

    var editorFont: EditorFont {
        didSet { defaults.set(editorFont.rawValue, forKey: Self.fontKey) }
    }

    var editorFontSize: CGFloat {
        didSet { defaults.set(editorFontSize, forKey: Self.fontSizeKey) }
    }

    var appIconID: String {
        didSet {
            defaults.set(appIconID, forKey: Self.iconKey)
            applyIcon()
        }
    }

    /// Bumped when the color palette changes so the live editor restyles in place.
    var styleRevision: Int = 0

    var selectedPalette: ColorTheme { ColorTheme.named(paletteID) }
    var selectedIcon: AppIconOption { AppIconOption.named(appIconID) }

    func paletteColors(isDark: Bool) -> PaletteColors {
        AppTheme.colors(isDark: isDark, theme: selectedPalette)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.themeKey) ?? Preference.system.rawValue
        preference = Preference(rawValue: raw) ?? .system

        let paletteRaw = defaults.string(forKey: Self.paletteKey) ?? ColorTheme.defaultID
        paletteID = ColorTheme.all.contains(where: { $0.id == paletteRaw }) ? paletteRaw : ColorTheme.defaultID

        let fontRaw = defaults.string(forKey: Self.fontKey) ?? EditorFont.sfPro.rawValue
        editorFont = EditorFont(rawValue: fontRaw) ?? .sfPro

        let sizeRaw = defaults.object(forKey: Self.fontSizeKey) as? Double
        editorFontSize = EditorFontSize.clamp(CGFloat(sizeRaw ?? Double(EditorFontSize.default)))

        let iconRaw = defaults.string(forKey: Self.iconKey) ?? AppIconOption.default.id
        appIconID = AppIconOption.all.contains(where: { $0.id == iconRaw }) ? iconRaw : AppIconOption.default.id

        PaletteStore.shared.currentID = paletteID

        // Defer the first application until after launch so `NSApp` exists and the
        // explicit nil (system) round-trip is safe.
        DispatchQueue.main.async { [weak self] in
            self?.apply()
            self?.applyIcon()
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

    func setPalette(_ id: String) {
        guard paletteID != id else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            paletteID = id
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

    private func invalidateChrome() {
        for window in NSApp.windows {
            window.contentView?.needsDisplay = true
            for view in window.contentView?.subviews ?? [] {
                view.needsDisplay = true
            }
        }
    }

    private func applyIcon() {
        // The bundled AppIcon is masked by the system. A raster
        // `applicationIconImage` bypasses that mask, so Default restores nil.
        if selectedIcon.id == AppIconOption.default.id {
            NSApp.applicationIconImage = nil
            return
        }
        if let image = selectedIcon.image {
            NSApp.applicationIconImage = image
        }
    }
}
