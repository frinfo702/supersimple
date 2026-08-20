import AppKit
import Foundation
import GhosttyTerminal
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

        let system = NSFont.systemFont(ofSize: EditorFontSize.default)
        let resolved = EditorFont.sfPro.nsFont(ofSize: EditorFontSize.default)
        #expect(resolved.ascender - resolved.descender == system.ascender - system.descender)
    }

    @Test("Ghost glyph sits inside the macOS icon plate, not on the hem")
    func ghostIconFitsMacIconGrid() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Assets.xcassets/AppIconGhost.imageset/icon.png")
        guard let image = NSImage(contentsOf: url),
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let bounds = lightPixelBounds(of: cg)
        else {
            Issue.record("Ghost icon PNG is missing")
            return
        }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let padTop = bounds.minY / height
        let padBottom = (height - bounds.maxY) / height
        let padLeft = bounds.minX / width
        let fillWidth = bounds.width / width

        #expect(padTop > 0.14)
        #expect(padBottom > 0.14)
        #expect(padLeft > 0.14)
        #expect(abs(padTop - padBottom) < 0.08)
        #expect(fillWidth < 0.58)
    }

    private func lightPixelBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard
                let ctx = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) > 40 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(
            x: minX, y: minY,
            width: maxX - minX + 1, height: maxY - minY + 1
        )
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
        #expect(first.styleRevision == 3)
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

    @Test("Search highlights are yellow and distinct from row selection")
    func searchHighlightsAreDistinctFromSelection() {
        for theme in ColorTheme.all {
            for isDark in [false, true] {
                let tokens = theme.tokens(isDark: isDark)
                let highlight = tokens.searchHighlight(isDark: isDark)
                let currentHighlight = tokens.searchCurrentHighlight(isDark: isDark)
                let selection = tokens.selection(isDark: isDark)

                #expect(highlight.r > highlight.b)
                #expect(highlight.g > highlight.b)
                #expect(highlight != selection)
                #expect(currentHighlight != selection)
                #expect(currentHighlight.a > highlight.a)
            }
        }
    }

    @Test("Terminal chrome follows each palette's editor and text tokens")
    func terminalThemeFollowsPalette() {
        for theme in ColorTheme.all {
            let terminal = theme.terminalTheme()
            #expect(terminal.dark.rendered.contains("background = \(theme.dark.editor.hex)"))
            #expect(terminal.dark.rendered.contains("foreground = \(theme.dark.text.hex)"))
            #expect(terminal.dark.rendered.contains("cursor-color = \(theme.dark.accent.hex)"))
            #expect(terminal.light.rendered.contains("background = \(theme.light.editor.hex)"))
            #expect(terminal.light.rendered.contains("foreground = \(theme.light.text.hex)"))
            #expect(terminal.light.rendered.contains("cursor-color = \(theme.light.accent.hex)"))
            #expect(terminal.dark != terminal.light)
        }
        #expect(ColorTheme.named("default").terminalTheme() != ColorTheme.named("nord").terminalTheme())
    }

    @Test("ANSI black and bright-black stay readable on the terminal background")
    func terminalCommentColorsContrast() {
        let floor = ColorTheme.terminalCommentContrast
        for theme in ColorTheme.all {
            for isDark in [false, true] {
                let tokens = theme.tokens(isDark: isDark)
                let black = tokens.terminalBlack()
                let comment = tokens.terminalBrightBlack()
                #expect(black.contrastRatio(against: tokens.editor) >= floor)
                #expect(comment.contrastRatio(against: tokens.editor) >= floor)
                #expect(black.hex != tokens.editor.hex)
                #expect(black.hex != tokens.background.hex)

                let rendered = (isDark ? theme.terminalTheme().dark : theme.terminalTheme().light).rendered
                #expect(rendered.contains("palette = 0=\(black.hex)"))
                #expect(rendered.contains("palette = 8=\(comment.hex)"))
                #expect(rendered.contains("minimum-contrast = 3"))
            }
        }
    }

    @Test("Near-black on the editor surface is lifted to comment contrast")
    func ensuringContrastLiftsFaintInk() {
        let editor = ColorTheme.named("default").dark.editor
        let faint = ColorTheme.named("default").dark.background
        #expect(faint.contrastRatio(against: editor) < ColorTheme.terminalCommentContrast)
        let lifted = faint.ensuringContrast(
            against: editor,
            minimum: ColorTheme.terminalCommentContrast
        )
        #expect(lifted.contrastRatio(against: editor) >= ColorTheme.terminalCommentContrast)
    }

    @Test("RGB hex rounds to 8-bit sRGB")
    func rgbHexEncoding() {
        #expect(ColorTheme.RGB(hex: 0x1A1B26).hex == "#1A1B26")
        #expect(ColorTheme.RGB(0, 0, 0, 0.5).blended(onto: ColorTheme.RGB(1, 1, 1)).hex == "#808080")
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
