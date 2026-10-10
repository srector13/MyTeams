//
//  BrandSettingsView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The brand: the accent colour (`BrandAccent`) and the style of the logo
/// (`BrandIconStyle`), each as a grid to pick from.
///
/// Reached from Settings' Appearance section. Every change applies at once,
/// app-wide: the root reads the same keys (`MyTeamsApp`).
struct BrandSettingsView: View {
    @AppStorage(BrandAccent.storageKey) private var brandAccent: BrandAccent = .classic
    @AppStorage(BrandIconStyle.storageKey) private var brandIconStyle: BrandIconStyle = .classic

    var body: some View {
        Form {
            Section {
                LabeledContent("Accent", value: brandAccent.title)
                    .accessibilityIdentifier("settings.brandAccent.current")
                BrandAccentPicker(selection: $brandAccent)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Colors the myTeams logo, buttons and highlights.")
            }

            Section {
                LabeledContent("Icon", value: brandIconStyle.title)
                    .accessibilityIdentifier("settings.brandIconStyle.current")
                BrandIconPicker(selection: $brandIconStyle)
            } header: {
                Text("Icon Style")
            } footer: {
                // iOS limits (`BrandAccent`): the icon is the bundle's, and
                // the launch screen is drawn before the app runs. Said once,
                // for both settings.
                Text("Changes the myTeams logo throughout the app, in the accent color. The App Store icon and the launch screen can't change with these settings.")
            }
        }
        .navigationTitle("Brand")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The brand accents as swatches, solids, gradients and specials in turn:
/// a tap picks one. Each swatch draws its fill, and the chosen one is
/// ringed and checked.
private struct BrandAccentPicker: View {
    @Binding var selection: BrandAccent

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: Theme.Spacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(BrandAccent.Style.allCases, id: \.self) { style in
                Text(style.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(BrandAccent.allCases.filter { $0.style == style }) { accent in
                        swatch(accent)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func swatch(_ accent: BrandAccent) -> some View {
        let selected = accent == selection
        return Button {
            selection = accent
        } label: {
            Circle()
                .fill(accent.fill)
                .frame(width: 36, height: 36)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(selected ? AnyShapeStyle(accent.fill) : AnyShapeStyle(Color.clear), lineWidth: 2)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        // A plain style, so the whole row isn't one tappable cell.
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.brandAccent.\(accent.rawValue)")
    }
}

/// The logo's styles as tiles: a tap picks one. Each tile draws the logo
/// in its style and the current accent, with the code every logo in the
/// app is drawn with (`BrandLogoMark`), and the chosen one is ringed and
/// checked, like the accent's swatches.
private struct BrandIconPicker: View {
    @Binding var selection: BrandIconStyle

    @Environment(\.brandAccent) private var accent

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: Theme.Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(BrandIconStyle.allCases) { style in
                candidate(style)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func candidate(_ style: BrandIconStyle) -> some View {
        let selected = style == selection
        return Button {
            selection = style
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                BrandLogoMark()
                    .environment(\.brandIconStyle, style)
                    .frame(width: 56)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(Theme.Spacing.s)
                    .background(Color(uiColor: .tertiarySystemFill), in: Theme.Radius.innerShape)
                    .overlay {
                        Theme.Radius.innerShape
                            .strokeBorder(selected ? accent.fill : AnyShapeStyle(Color.clear), lineWidth: 2)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body.weight(.bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, accent.primaryColor)
                                .padding(Theme.Spacing.xs)
                        }
                    }
                Text(style.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        // A plain style, so the whole row isn't one tappable cell.
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.brandIconStyle.\(style.rawValue)")
    }
}

#Preview {
    NavigationStack {
        BrandSettingsView()
    }
}
