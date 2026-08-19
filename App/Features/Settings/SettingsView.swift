import AppKit
import SwiftUI

/// Settings opened from the app menu (⌘,) — same chrome as the main window.
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { themeManager.isDark(matching: colorScheme) }
    private var palette: PaletteColors { themeManager.paletteColors(isDark: isDark) }
    private var tokens: ColorTheme.Tokens { themeManager.selectedPalette.tokens(isDark: isDark) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                iconSection
                editorSection
                themeSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 52)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 560)
        .background(palette.background)
        .toolbarBackground(palette.background, for: .windowToolbar)
        .background(WindowChrome(title: "Settings", background: palette.nsBackground))
        .tint(palette.accent)
        .environment(\.palette, palette)
        .animation(nil, value: themeManager.preference)
        .animation(nil, value: themeManager.paletteID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-root")
    }

    // MARK: - Icon

    private var iconSection: some View {
        SettingsSection(title: "App Icon") {
            HStack(spacing: 12) {
                ForEach(AppIconOption.all) { option in
                    IconChoice(
                        option: option,
                        isSelected: themeManager.appIconID == option.id,
                        accent: tokens.accent.swiftUI
                    ) {
                        themeManager.appIconID = option.id
                    }
                }
            }
            .accessibilityIdentifier("settings-icon-grid")
        }
    }

    // MARK: - Editor

    private var editorSection: some View {
        SettingsSection(title: "Editor") {
            VStack(alignment: .leading, spacing: 18) {
                editorPreview
                labeledRow("Font") {
                    HStack(spacing: 8) {
                        ForEach(EditorFont.allCases) { font in
                            ChoiceChip(
                                title: font.shortName,
                                isSelected: themeManager.editorFont == font,
                                accent: tokens.accent.swiftUI,
                                font: font.swiftUIFont(ofSize: 13)
                            ) {
                                themeManager.editorFont = font
                            }
                            .help(font.displayName)
                            .accessibilityLabel(font.displayName)
                        }
                    }
                    .accessibilityIdentifier("settings-font-row")
                }
                labeledRow("Size") {
                    HStack(spacing: 8) {
                        ForEach(EditorFontSize.all, id: \.self) { size in
                            ChoiceChip(
                                title: "\(Int(size))",
                                isSelected: themeManager.editorFontSize == size,
                                accent: tokens.accent.swiftUI
                            ) {
                                themeManager.editorFontSize = size
                            }
                        }
                    }
                    .accessibilityIdentifier("settings-font-size-row")
                }
            }
        }
    }

    private var editorPreview: some View {
        Text("Start writing")
            .font(themeManager.editorFont.swiftUIFont(ofSize: themeManager.editorFontSize))
            .foregroundStyle(tokens.text.swiftUI.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tokens.editor.swiftUI)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tokens.hairline(isDark: isDark).swiftUI, lineWidth: AppTheme.Metric.hairlineWidth)
            )
            .accessibilityIdentifier("settings-editor-preview")
    }

    // MARK: - Theme

    private var themeSection: some View {
        SettingsSection(title: "Theme") {
            VStack(alignment: .leading, spacing: 16) {
                labeledRow("Appearance") {
                    HStack(spacing: 8) {
                        ForEach(ThemeManager.Preference.allCases) { preference in
                            ChoiceChip(
                                title: preference.label,
                                isSelected: themeManager.preference == preference,
                                accent: tokens.accent.swiftUI
                            ) {
                                themeManager.setPreferenceImmediately(preference)
                            }
                        }
                    }
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 12
                ) {
                    ForEach(ColorTheme.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: themeManager.paletteID == theme.id,
                            previewIsDark: isDark
                        ) {
                            themeManager.setPalette(theme.id)
                        }
                    }
                }
                .accessibilityIdentifier("settings-theme-grid")
            }
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tokens.muted.swiftUI)
            content()
        }
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.muted)
                .tracking(0.4)
            content()
        }
    }
}

private struct IconChoice: View {
    var option: AppIconOption
    var isSelected: Bool
    var accent: Color
    var action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let image = option.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(palette.muted.opacity(0.2))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(isSelected ? 0.22 : 0.12), radius: isSelected ? 8 : 5, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 2)
                        .padding(-4)
                }
                Text(option.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : palette.muted)
            }
        }
        .buttonStyle(.plain)
        .help(option.name)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-icon-\(option.id)")
    }
}

private struct ChoiceChip: View {
    var title: String
    var isSelected: Bool
    var accent: Color
    var font: Font = .system(size: 13, weight: .medium)
    var action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(isSelected ? Color.primary : palette.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                        .fill(isSelected ? palette.selection : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Metric.controlRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? accent.opacity(0.55) : palette.hairline,
                            lineWidth: AppTheme.Metric.hairlineWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemeCard: View {
    var theme: ColorTheme
    var isSelected: Bool
    var previewIsDark: Bool
    var action: () -> Void
    @Environment(\.palette) private var palette

    private var tokens: ColorTheme.Tokens { theme.tokens(isDark: previewIsDark) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                themePreview
                Text(theme.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : palette.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(theme.name)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-theme-\(theme.id)")
    }

    private var themePreview: some View {
        HStack(spacing: 0) {
            tokens.background.swiftUI
                .frame(width: 22)
            ZStack(alignment: .bottomLeading) {
                tokens.editor.swiftUI
                Text("Aa")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(tokens.text.swiftUI)
                    .padding(.leading, 10)
                    .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .top) {
            tokens.accent.swiftUI
                .frame(height: 3)
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? tokens.accent.swiftUI : palette.hairline,
                    lineWidth: isSelected ? 1.5 : AppTheme.Metric.hairlineWidth
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.06), radius: isSelected ? 6 : 3, y: 1)
    }
}
