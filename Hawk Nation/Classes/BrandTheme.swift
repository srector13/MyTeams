//
//  BrandTheme.swift
//  myTeams
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "brandTheme")

/// The reader's brand theme: one of the designer's palettes, which sets the
/// app's tint, the myTeams logo drawn in the app and the iOS app icon
/// together. Stored in `UserDefaults` under `storageKey` and applied to the
/// whole app at the root (`MyTeamsApp`, `View.brandTheme(_:)`), like
/// `AppAppearance`.
///
/// `classic` is the shipped blue and changes nothing: it tints with the
/// asset catalog's own `AccentColor`, draws the shipped `myTeamsLogo` art
/// and keeps the primary app icon.
///
/// Every other theme's colours are the designer's (`palettes.json`), copied
/// here verbatim. Its accent is the logo's lanes: `logoOnLight.lanes` in
/// light appearance, `logoOnDark.lanes` in dark. Its logo is the image set
/// `myTeams-logo-<id>-on-light` / `-on-dark`, and its icon the
/// `AppIcon-<Name>` alternate icon (Info.plist's `CFBundleAlternateIcons`).
///
/// Not "Theme": that is the app's design-system namespace (`Theme.swift`).
enum BrandTheme: String, CaseIterable, Identifiable, Sendable {
    /// The shipped brand blue, logo and icon.
    case classic
    case cobalt
    case sky
    case teal
    case green
    case gold
    case orange
    case red
    case pink
    case purple
    case graphite

    /// The `UserDefaults` key the theme's `rawValue` is stored under.
    static let storageKey = "settings.theme"

    /// Keys the retired accent and icon-style settings were stored under.
    /// Not carried over: `removeRetiredSettings(from:)` drops them, and
    /// every install starts on `classic`.
    static let retiredStorageKeys = ["settings.brandAccent", "settings.brandIconStyle"]

    var id: String { rawValue }

    /// Whether this is the shipped look, which leaves the app as it was.
    var isDefault: Bool { self == .classic }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .cobalt: "Cobalt"
        case .sky: "Sky"
        case .teal: "Teal"
        case .green: "Green"
        case .gold: "Gold"
        case .orange: "Orange"
        case .red: "Red"
        case .pink: "Pink"
        case .purple: "Purple"
        case .graphite: "Graphite"
        }
    }

    /// The theme stored in `defaults`; `classic` when none is, or an id
    /// this build doesn't know.
    static func stored(in defaults: UserDefaults = .standard) -> BrandTheme {
        defaults.string(forKey: storageKey).flatMap(BrandTheme.init(rawValue:)) ?? .classic
    }

    /// Drops the retired accent and icon-style settings.
    static func removeRetiredSettings(from defaults: UserDefaults = .standard) {
        for key in retiredStorageKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Palette

    /// An app icon's colours, as the designer drew them: the background,
    /// the arches ("lanes") and the T ("tee").
    struct IconColors: Equatable, Sendable {
        let background: String
        let lanes: String
        let tee: String
    }

    /// A logo's colours, on a light or a dark background.
    struct LogoColors: Equatable, Sendable {
        let lanes: String
        let tee: String
    }

    /// A theme's colours, as `#RRGGBB`, from the designer's `palettes.json`.
    struct Palette: Equatable, Sendable {
        let iconLight: IconColors
        let iconDark: IconColors
        let logoOnLight: LogoColors
        let logoOnDark: LogoColors
    }

    /// The designer's colours; `nil` for `classic`, which is the asset
    /// catalog's.
    var palette: Palette? {
        switch self {
        case .classic:
            nil
        case .cobalt:
            Palette(
                iconLight: .init(background: "#2443F2", lanes: "#92A1F8", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#5673FF", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#2443F2", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#5673FF", tee: "#FFFFFF")
            )
        case .sky:
            Palette(
                iconLight: .init(background: "#168FE0", lanes: "#8AC7F0", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#5CC0FF", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#168FE0", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#5CC0FF", tee: "#FFFFFF")
            )
        case .teal:
            Palette(
                iconLight: .init(background: "#0E8F84", lanes: "#86C7C2", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#2DD4BF", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#0E8F84", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#2DD4BF", tee: "#FFFFFF")
            )
        case .green:
            Palette(
                iconLight: .init(background: "#15964A", lanes: "#8ACAA4", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#3DDC84", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#15964A", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#3DDC84", tee: "#FFFFFF")
            )
        case .gold:
            Palette(
                iconLight: .init(background: "#F5B81F", lanes: "#FADC8F", tee: "#0E1016"),
                iconDark: .init(background: "#0E1016", lanes: "#FFC83D", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#B97A00", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#FFC83D", tee: "#FFFFFF")
            )
        case .orange:
            Palette(
                iconLight: .init(background: "#E85A10", lanes: "#F4AC88", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#FF8A3D", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#E85A10", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#FF8A3D", tee: "#FFFFFF")
            )
        case .red:
            Palette(
                iconLight: .init(background: "#D92B3A", lanes: "#EC959C", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#FF5F66", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#D92B3A", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#FF5F66", tee: "#FFFFFF")
            )
        case .pink:
            Palette(
                iconLight: .init(background: "#DB3287", lanes: "#ED98C3", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#FF74B5", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#DB3287", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#FF74B5", tee: "#FFFFFF")
            )
        case .purple:
            Palette(
                iconLight: .init(background: "#7A3FF2", lanes: "#BC9FF8", tee: "#FFFFFF"),
                iconDark: .init(background: "#0E1016", lanes: "#A283FF", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#7A3FF2", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#A283FF", tee: "#FFFFFF")
            )
        case .graphite:
            Palette(
                iconLight: .init(background: "#F2F2F5", lanes: "#A9ABB8", tee: "#0E1016"),
                iconDark: .init(background: "#0E1016", lanes: "#9698A6", tee: "#FFFFFF"),
                logoOnLight: .init(lanes: "#7C7E8C", tee: "#0E1016"),
                logoOnDark: .init(lanes: "#9698A6", tee: "#FFFFFF")
            )
        }
    }

    /// The alternate app icon (`AppIcon-<Name>.appiconset`, listed in
    /// Info.plist); `nil` for `classic`, the primary icon.
    var appIconName: String? {
        switch self {
        case .classic: nil
        case .cobalt: "AppIcon-Cobalt"
        case .sky: "AppIcon-Sky"
        case .teal: "AppIcon-Teal"
        case .green: "AppIcon-Green"
        case .gold: "AppIcon-Gold"
        case .orange: "AppIcon-Orange"
        case .red: "AppIcon-Red"
        case .pink: "AppIcon-Pink"
        case .purple: "AppIcon-Purple"
        case .graphite: "AppIcon-Graphite"
        }
    }

    /// The tint, light appearance: the logo's lanes on light.
    var accentLightHex: String? { palette?.logoOnLight.lanes }

    /// The tint, dark appearance: the logo's lanes on dark.
    var accentDarkHex: String? { palette?.logoOnDark.lanes }

    /// The logo's image set for `scheme`: `myTeams-logo-<id>-on-light` or
    /// `-on-dark`. `nil` for `classic`, whose art is the shipped
    /// `myTeamsLogo` (or the art a caller names, `BrandLogoMark.art`).
    func logoImageName(for scheme: ColorScheme) -> String? {
        guard !isDefault else { return nil }
        return "myTeams-logo-\(rawValue)-on-\(scheme == .dark ? "dark" : "light")"
    }

    /// A preview of the theme's app icon for `scheme`, for the theme
    /// pickers: `myTeams-icon-<id>-light` or `-dark`, the designer's icon
    /// art (for `classic`, the primary `AppIcon`'s own PNGs). An alternate
    /// app icon can't be loaded as an image, so the previews are image sets
    /// of their own.
    func iconPreviewImageName(for scheme: ColorScheme) -> String {
        "myTeams-icon-\(rawValue)-\(scheme == .dark ? "dark" : "light")"
    }

    // MARK: Colours

    /// The tint as a UIKit colour that follows the appearance; `nil` for
    /// `classic`, which keeps the asset's `AccentColor`.
    var accentUIColor: UIColor? {
        guard let light = accentLightHex.flatMap(Self.uiColor),
              let dark = accentDarkHex.flatMap(Self.uiColor) else { return nil }
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    /// The tint: the asset's `AccentColor` for `classic`, the lanes
    /// otherwise, following the appearance.
    var accentColor: Color {
        accentUIColor.map { Color(uiColor: $0) } ?? .accentColor
    }

    /// A `#RRGGBB` (or bare six-digit) colour; `nil` for anything else.
    private static func uiColor(_ hex: String) -> UIColor? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension EnvironmentValues {
    /// The reader's brand theme, set at the root (`View.brandTheme(_:)`).
    @Entry var brandTheme: BrandTheme = .classic
}

// MARK: - Root

extension View {
    /// Applies `theme` to everything under the view: the SwiftUI tint
    /// (`.tint` shape styles, controls, links), `\.brandTheme` for the
    /// logo, and the window's UIKit tint (alerts, menus, sheets UIKit
    /// presents). For the app's root view only.
    ///
    /// `classic` overrides nothing: the tint is the asset's `AccentColor`
    /// either way, and the window is left alone.
    func brandTheme(_ theme: BrandTheme) -> some View {
        tint(theme.accentColor)
            .environment(\.brandTheme, theme)
            .background {
                WindowTint(color: theme.accentUIColor)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Sets its window's `tintColor`, which UIKit's own views inherit;
/// `nil` puts back the one the window had.
private struct WindowTint: UIViewRepresentable {
    let color: UIColor?

    func makeUIView(context: Context) -> WindowTintView {
        WindowTintView()
    }

    func updateUIView(_ view: WindowTintView, context: Context) {
        view.color = color
    }

    final class WindowTintView: UIView {
        var color: UIColor? {
            didSet { apply() }
        }

        /// Whether this view has set the window's tint, so the shipped
        /// blue never touches it.
        private var overrides = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window, color != nil || overrides else { return }
            window.tintColor = color
            overrides = color != nil
        }
    }
}

// MARK: - Logo

/// The myTeams logo in the reader's theme: the designer's art for the
/// theme and the colour scheme on screen (`BrandTheme.logoImageName(for:)`),
/// or, for `classic`, `art` — the shipped `myTeamsLogo`, whose asset picks
/// its own light and dark variants — unchanged.
///
/// Resizable and aspect-fit, like the `Image` it stands in for: frame it.
/// Every theme's art is on the shipped logo's canvas (1592 x 1120 against
/// 798 x 561, the same aspect), so a frame holds across themes.
struct BrandLogoMark: View {
    /// The art for `classic`.
    var art: String = "myTeamsLogo"
    /// The theme to draw; the environment's (the reader's) when `nil`. The
    /// theme pickers pass each tile's own.
    var theme: BrandTheme?

    @Environment(\.brandTheme) private var environmentTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image((theme ?? environmentTheme).logoImageName(for: colorScheme) ?? art)
            .resizable()
            .scaledToFit()
    }
}

// MARK: - App icon

/// Switches the iOS app icon to a theme's (`BrandTheme.appIconName`): the
/// primary icon for `classic`, an `AppIcon-<Name>` alternate otherwise.
///
/// iOS tells the reader with an alert of its own each time the icon
/// changes; the app can't suppress it. Errors are logged and otherwise
/// ignored — the theme still applies in the app — and if a themed icon
/// can't be set while another themed icon is showing, the icon falls back
/// to the classic one rather than staying on a theme the reader left.
@MainActor
enum AppIconSwitcher {
    /// The theme whose icon iOS shows, from `alternateIconName`; `classic`
    /// for the primary icon, or an alternate this build doesn't name.
    static var currentTheme: BrandTheme {
        guard let name = UIApplication.shared.alternateIconName else { return .classic }
        return BrandTheme.allCases.first { $0.appIconName == name } ?? .classic
    }

    /// Asks iOS for `theme`'s icon, unless it is already showing or the
    /// device can't change icons. Whether the icon is `theme`'s afterwards.
    @discardableResult
    static func apply(_ theme: BrandTheme) async -> Bool {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return theme.isDefault }
        let name = theme.appIconName
        guard application.alternateIconName != name else { return true }
        guard let error = await setAlternateIconName(name) else { return true }
        logger.error("Could not set the app icon \(name ?? "AppIcon", privacy: .public): \(error.localizedDescription, privacy: .public)")
        // Back to the classic icon, so the icon never shows a theme other
        // than the reader's.
        if name != nil, application.alternateIconName != nil {
            _ = await setAlternateIconName(nil)
        }
        return false
    }

    /// `UIApplication.setAlternateIconName(_:completionHandler:)`, its
    /// error returned rather than thrown.
    private static func setAlternateIconName(_ name: String?) async -> (any Error)? {
        await withCheckedContinuation { continuation in
            UIApplication.shared.setAlternateIconName(name) { error in
                continuation.resume(returning: error)
            }
        }
    }
}
