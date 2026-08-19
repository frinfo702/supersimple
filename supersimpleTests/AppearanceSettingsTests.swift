import Foundation
import Testing

@testable import supersimple

@MainActor
@Suite("Appearance settings")
struct AppearanceSettingsTests {

    @Test("Catalog has 20 unique palettes including Default")
    func colorThemeCatalog() {
        #expect(ColorTheme.all.count == 20)
        let ids = ColorTheme.all.map(\.id)
        #expect(Set(ids).count == 20)
        #expect(ColorTheme.all[0].id == ColorTheme.defaultID)
        #expect(ColorTheme.all[0].name == "Default")
        #expect(ColorTheme.named("missing").id == ColorTheme.defaultID)
    }

    @Test("Default palette matches the original supersimple chrome")
    func defaultPaletteMatchesOriginal() {
        let theme = ColorTheme.named("default")
        #expect(theme.dark.background == ColorTheme.RGB(0.09, 0.09, 0.09))
        #expect(theme.dark.editor == ColorTheme.RGB(0.125, 0.125, 0.125))
        #expect(theme.dark.text == ColorTheme.RGB(0.94, 0.94, 0.94))
        #expect(theme.dark.muted == ColorTheme.RGB(0.58, 0.59, 0.51))
        #expect(theme.dark.accent == ColorTheme.RGB(0.82, 0.48, 0.38))
        #expect(theme.light.background == ColorTheme.RGB(0.91, 0.905, 0.875))
        #expect(theme.light.editor == ColorTheme.RGB(0.985, 0.98, 0.955))
        #expect(theme.light.text == ColorTheme.RGB(0.10, 0.10, 0.10))
        #expect(theme.light.muted == ColorTheme.RGB(0.37, 0.38, 0.31))
        #expect(theme.light.accent == ColorTheme.RGB(0.82, 0.48, 0.38))
    }

    @Test("Editor fonts resolve to a real face")
    func editorFontsResolve() {
        for font in EditorFont.allCases {
            let resolved = font.nsFont(ofSize: EditorFontSize.default)
            #expect(resolved.pointSize == EditorFontSize.default)
            if font != .sfPro {
                #expect(resolved.fontName == font.postScriptName)
            }
        }
        #expect(EditorFontSize.clamp(16.4) == 16)
        #expect(EditorFontSize.clamp(21.6) == 22)
    }

    @Test("App icon catalog is a closed set")
    func appIconCatalog() {
        #expect(AppIconOption.all.count == 9)
        #expect(AppIconOption.all.first?.id == "default")
        #expect(AppIconOption.named("ghost").id == "ghost")
        #expect(AppIconOption.named("missing").id == "default")
        #expect(Set(AppIconOption.all.map(\.id)).count == 9)
        #expect(Set(AppIconOption.all.map(\.assetName)).count == 9)
    }

    @Test("ThemeManager persists palette, font, size, and icon")
    func persistsAppearanceChoices() {
        let suite = "supersimple-appearance-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let previousPalette = PaletteStore.shared.currentID
        defer {
            PaletteStore.shared.currentID = previousPalette
            defaults.removePersistentDomain(forName: suite)
        }

        let first = ThemeManager(defaults: defaults)
        #expect(first.paletteID == ColorTheme.defaultID)
        #expect(first.editorFont == .sfPro)
        #expect(first.editorFontSize == EditorFontSize.default)
        #expect(first.appIconID == AppIconOption.default.id)

        first.setPalette("cursor")
        first.editorFont = .charter
        first.editorFontSize = 20
        first.appIconID = "ink"
        #expect(first.styleRevision == 1)
        #expect(PaletteStore.shared.currentID == "cursor")

        let second = ThemeManager(defaults: defaults)
        #expect(second.paletteID == "cursor")
        #expect(second.editorFont == .charter)
        #expect(second.editorFontSize == 20)
        #expect(second.appIconID == "ink")
    }

    @Test("Baked palette colors follow the selected theme without an appearance change")
    func bakedPaletteFollowsThemeID() {
        let darkDefault = PaletteColors(isDark: true, theme: ColorTheme.named("default"))
        let darkCursor = PaletteColors(isDark: true, theme: ColorTheme.named("cursor"))
        #expect(darkDefault != darkCursor)
        #expect(darkDefault.themeID == "default")
        #expect(darkCursor.themeID == "cursor")
        #expect(darkDefault.accent != darkCursor.accent)
        #expect(darkDefault.background != darkCursor.background)
    }

    @Test("Unknown persisted values fall back to defaults")
    func unknownValuesFallBack() {
        let suite = "supersimple-appearance-fallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("not-a-theme", forKey: "com.frinfo702.supersimple.palette")
        defaults.set("comic-sans", forKey: "com.frinfo702.supersimple.editorFont")
        defaults.set(99.0, forKey: "com.frinfo702.supersimple.editorFontSize")
        defaults.set("nope", forKey: "com.frinfo702.supersimple.appIcon")
        let previousPalette = PaletteStore.shared.currentID
        defer {
            PaletteStore.shared.currentID = previousPalette
            defaults.removePersistentDomain(forName: suite)
        }

        let manager = ThemeManager(defaults: defaults)
        #expect(manager.paletteID == ColorTheme.defaultID)
        #expect(manager.editorFont == .sfPro)
        #expect(manager.editorFontSize == 22)
        #expect(manager.appIconID == AppIconOption.default.id)
    }
}
