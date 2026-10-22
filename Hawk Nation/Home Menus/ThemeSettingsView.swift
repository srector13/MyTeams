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
/// Reached from Settings' Display section. The accent and logo change at
/// once, app-wide: the root reads the same key (`MyTeamsApp`). The app icon
/// changes through iOS (`AppIconSwitcher`), which confirms it with an alert
/// of its own, so it changes once, as the reader leaves the screen, rather
/// than with every tile tried.
///
/// The selected tile says which theme is on, so there's no row repeating
/// it (S3); the screen opens scrolled to that tile.
struct ThemeSettingsView: View {
    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic
    /// Whether iOS refused the last icon change.
    @State private var iconFailed = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Accent & App Icon")
                        .font(Theme.Typography.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Palette.metadata)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .accessibilityAddTraits(.isHeader)
                        // The theme screen's marker for the UI tests, as the
                        // "Theme" row that used to repeat the title was.
                        .accessibilityIdentifier("settings.theme.current")

                    ThemePicker(selection: $theme, identifierPrefix: "settings.theme")

                    Text(ThemePicker.iconNote)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.metadata)
                        .padding(.horizontal, Theme.Spacing.xs)

                    if iconFailed {
                        Label("The app icon couldn't change, so the classic icon stays. The theme still applies in the app.", systemImage: "exclamationmark.triangle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.metadata)
                            .padding(.top, Theme.Spacing.s)
                            .accessibilityIdentifier("settings.theme.iconFailed")
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Surface.content)
            .onAppear {
                // Opens on the theme that's on, however far down the grid.
                proxy.scrollTo(theme, anchor: .center)
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Shown again if the icon couldn't follow the theme last time.
            iconFailed = AppIconSwitcher.currentTheme != theme && !theme.isDefault
        }
        .onDisappear {
            Task {
                await AppIconSwitcher.apply(theme)
            }
        }
    }
}

/// The brand themes as tiles, classic first: a tap picks one. Each tile
/// draws the theme's own logo (`BrandLogoMark`), its accent and a preview
/// of its app icon, with the theme's name in full-strength text; the
/// chosen one is ringed in its accent and checked (O4).
///
/// A lazy grid that grows with its container, so it can sit in a
/// `ScrollView` and scroll with it; nothing assumes the whole grid fits.
/// One column at accessibility text sizes, where two would squeeze the
/// names (A3). Each tile is identified by its theme, for
/// `ScrollViewProxy.scrollTo`. Shared by Settings (`ThemeSettingsView`)
/// and onboarding (`ThemeOnboardingView`).
struct ThemePicker: View {
    @Binding var selection: BrandTheme
    /// Each tile's accessibility identifier is this, a dot, and the
    /// theme's id.
    let identifierPrefix: String

    /// What changing the theme does to the app icon, said wherever the
    /// picker is.
    static let iconNote = "Changes the accent color and the myTeams logo right away. The app icon follows when you're done, and iOS confirms the change with a message of its own."

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: Theme.Spacing.m)]
            : [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: Theme.Spacing.m)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(BrandTheme.allCases) { theme in
                tile(theme)
                    .id(theme)
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
                        .fill(theme.swatchColor)
                        .frame(width: 16, height: 16)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, theme.swatchColor)
                            // A mark, not text: it keeps its size at the
                            // largest text sizes (A3).
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    }
                }

                // Full strength whether picked or not: the ring and the
                // check say which is picked, not a dimmed name (O4).
                Text(theme.title)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
            }
            .padding(Theme.Spacing.s)
            .background(Theme.Surface.contentCard, in: Theme.Radius.innerShape)
            .overlay {
                Theme.Radius.innerShape
                    .strokeBorder(selected ? theme.swatchColor : Color.clear, lineWidth: 2)
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
