//
//  ThemeSettingsView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The brand theme (`BrandTheme`): one grid of the designer's palettes, each
/// tile showing the theme's logo, accent and app icon. A tap applies all
/// three together.
///
/// Reached from Settings' Appearance section. The accent and logo change at
/// once, app-wide: the root reads the same key (`MyTeamsApp`). The app icon
/// changes through iOS (`AppIconSwitcher`), which confirms it with an alert
/// of its own.
struct ThemeSettingsView: View {
    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic
    /// Whether iOS refused the last icon change.
    @State private var iconFailed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Theme", value: theme.title)
                    .accessibilityIdentifier("settings.theme.current")
                ThemePicker(selection: $theme, identifierPrefix: "settings.theme")
            } header: {
                Text("Palette")
            } footer: {
                Text(ThemePicker.iconNote)
            }

            if iconFailed {
                Section {
                    Label("The app icon couldn't change, so the classic icon stays. The theme still applies in the app.", systemImage: "exclamationmark.triangle")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.theme.iconFailed")
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: theme) { _, theme in
            Task {
                iconFailed = !(await AppIconSwitcher.apply(theme))
            }
        }
    }
}

/// The brand themes as tiles, classic first: a tap picks one. Each tile
/// draws the theme's own logo (`BrandLogoMark`), its accent and a preview
/// of its app icon, with the icon's name; the chosen one is ringed in its
/// accent and checked.
///
/// A lazy grid that grows with its container, so it can sit in a `Form` or
/// a `ScrollView` and scroll with it; nothing assumes the whole grid fits.
/// Shared by Settings (`ThemeSettingsView`) and onboarding
/// (`ThemeOnboardingView`).
struct ThemePicker: View {
    @Binding var selection: BrandTheme
    /// Each tile's accessibility identifier is this, a dot, and the
    /// theme's id.
    let identifierPrefix: String

    /// What changing the theme does to the app icon, said wherever the
    /// picker is.
    static let iconNote = "Changes the accent color, the myTeams logo and the app icon together. iOS shows a message of its own when the app icon changes. If the icon can't change, the classic icon stays. The launch screen always shows the classic logo."

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: Theme.Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(BrandTheme.allCases) { theme in
                tile(theme)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func tile(_ theme: BrandTheme) -> some View {
        let selected = theme == selection
        return Button {
            selection = theme
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                BrandLogoMark(theme: theme)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.s)
                    .background(Color(uiColor: .tertiarySystemFill), in: Theme.Radius.innerShape)

                HStack(spacing: Theme.Spacing.s) {
                    Image(theme.iconPreviewImageName(for: colorScheme))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 16, height: 16)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, theme.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(theme.title)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    Text(theme.appIconName ?? "AppIcon")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(Theme.Spacing.s)
            .overlay {
                Theme.Radius.innerShape
                    .strokeBorder(selected ? theme.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        // A plain style, so the whole row isn't one tappable cell.
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix).\(theme.rawValue)")
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}
