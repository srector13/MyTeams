//
//  BrandAccent.swift
//  myTeams
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

/// The reader's brand accent: the colour, or gradient, that stands in for
/// the app's brand blue (`AccentColor` in the asset catalog) as the tint
/// app-wide and on the myTeams logo's arches. Stored in `UserDefaults` under
/// `storageKey` and applied to the whole app at the root (`MyTeamsApp`,
/// `View.brandAccent(_:)`), like `AppAppearance`.
///
/// `classic` is the shipped blue and changes nothing: it tints with the
/// asset's own colour (with its dark and Increase Contrast variants) and
/// draws the logo's original art.
///
/// What can't follow the choice, iOS limits rather than ours:
/// - the app icon, which is the bundle's own (there's no alternate-icon
///   mechanism here, and an alternate icon would be one fixed picture
///   each, not a colour);
/// - the system launch screen, Info.plist's `UILaunchScreen`, which iOS
///   draws from the bundle before any of the app's code runs. `SplashView`,
///   drawn right after it, does follow.
///
/// The colour arithmetic is on the six-digit hex strings the rest of the
/// app uses (`TeamColors`), and pure, so it can be unit-tested.
enum BrandAccent: String, CaseIterable, Identifiable, Sendable {
    /// The shipped brand blue.
    case classic

    // Solids.
    case scarlet
    case crimson
    case orange
    case gold
    case kellyGreen
    case forest
    case teal
    case sky
    case navy
    case purple
    case hotPink
    case graphite

    // Two-stop gradients.
    case ocean
    case berry
    case ember
    case aurora
    case twilight
    case citrus
    case canopy
    case royal

    // Three stops or more.
    case sunset
    case northernLights
    case neon
    case spectrum

    /// The `UserDefaults` key the choice is stored under.
    static let storageKey = "settings.brandAccent"

    /// The asset catalog's `AccentColor`, light appearance: sRGB
    /// 0.000/0.318/0.729.
    static let shippedHex = "0051BA"

    var id: String { rawValue }

    /// Whether this is the shipped blue, which leaves the app as it was.
    var isDefault: Bool { self == .classic }

    var title: String {
        switch self {
        case .classic: "myTeams Blue"
        case .scarlet: "Scarlet"
        case .crimson: "Crimson"
        case .orange: "Orange"
        case .gold: "Gold"
        case .kellyGreen: "Kelly Green"
        case .forest: "Forest"
        case .teal: "Teal"
        case .sky: "Sky"
        case .navy: "Navy"
        case .purple: "Purple"
        case .hotPink: "Hot Pink"
        case .graphite: "Graphite"
        case .ocean: "Ocean"
        case .berry: "Berry"
        case .ember: "Ember"
        case .aurora: "Aurora"
        case .twilight: "Twilight"
        case .citrus: "Citrus"
        case .canopy: "Canopy"
        case .royal: "Royal"
        case .sunset: "Sunset"
        case .northernLights: "Northern Lights"
        case .neon: "Neon"
        case .spectrum: "Spectrum"
        }
    }

    /// The colours, light appearance, as six-digit hex: one for a solid,
    /// first to last along the gradient otherwise.
    var hexStops: [String] {
        switch self {
        case .classic: [Self.shippedHex]
        case .scarlet: ["D50A0A"]
        case .crimson: ["9E1B32"]
        case .orange: ["E35205"]
        case .gold: ["B8860B"]
        case .kellyGreen: ["00843D"]
        case .forest: ["154734"]
        case .teal: ["007C80"]
        case .sky: ["0077C8"]
        case .navy: ["13294B"]
        case .purple: ["4F2683"]
        case .hotPink: ["D6246E"]
        case .graphite: ["53565A"]
        case .ocean: ["0051BA", "00A6D6"]
        case .berry: ["7B1FA2", "E31C79"]
        case .ember: ["C8102E", "F7931E"]
        case .aurora: ["00A388", "6A4BC4"]
        case .twilight: ["2B2E83", "C33764"]
        case .citrus: ["E86A10", "F2C200"]
        case .canopy: ["134E5E", "4E9A6A"]
        case .royal: ["4F2683", "0051BA"]
        case .sunset: ["C2185B", "F4511E", "FFB300"]
        case .northernLights: ["00A388", "1E88E5", "8E24AA"]
        case .neon: ["00C2A8", "9B5DE5", "F15BB5"]
        case .spectrum: ["E53935", "FB8C00", "FDD835", "43A047", "1E88E5", "8E24AA"]
        }
    }

    /// How the choice is drawn, and grouped in Settings.
    enum Style: Sendable, CaseIterable {
        case solid
        case gradient
        case special

        var title: String {
            switch self {
            case .solid: "Solids"
            case .gradient: "Gradients"
            case .special: "Specials"
            }
        }
    }

    var style: Style {
        switch hexStops.count {
        case ...1: .solid
        case 2: .gradient
        default: .special
        }
    }

    /// The solid colour that represents the choice where one colour has to
    /// do — the tint on buttons, symbols and selection — light appearance:
    /// its darkest stop, the one that reads best on the app's light
    /// backgrounds. A solid's only stop.
    var primaryHex: String { Self.darkestHex(in: hexStops) }

    // MARK: Colour arithmetic

    /// The stop of lowest relative luminance; the first of equals. The
    /// shipped blue for an empty list, which no case has.
    static func darkestHex(in stops: [String]) -> String {
        let measured = stops.compactMap { hex in
            TeamColors.relativeLuminance(hex: hex).map { (hex: hex, luminance: $0) }
        }
        // `min(by:)` keeps the first of equals.
        return measured.min { $0.luminance < $1.luminance }?.hex ?? shippedHex
    }

    /// `hex` moved `fraction` (0...1) of the way to white, channel by
    /// channel, rounded. `hex` unchanged if it isn't six hex digits.
    static func lightened(_ hex: String, by fraction: Double) -> String {
        guard let value = rgb(hex) else { return hex }
        let t = min(max(fraction, 0), 1)
        let channels = [value >> 16, value >> 8, value].map { channel -> Int in
            let c = Double(channel & 0xFF)
            return Int((c + (255 - c) * t).rounded())
        }
        return String(format: "%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    /// Below this luminance a stop is lifted in dark appearance, as the
    /// shipped blue's own dark variant is, so the tint still reads on the
    /// dark backgrounds.
    static let darkLiftThreshold = 0.2

    /// How far toward white `darkModeHex(_:)` lifts a dark stop.
    static let darkLift = 0.3

    /// The stop to draw in dark appearance: dark ones lifted toward white,
    /// the rest as they are.
    static func darkModeHex(_ hex: String) -> String {
        guard let luminance = TeamColors.relativeLuminance(hex: hex), luminance < darkLiftThreshold else {
            return hex
        }
        return lightened(hex, by: darkLift)
    }

    /// Whether every stop reaches `minimum` contrast with `backgroundHex`,
    /// so the accent can stand on that colour (a team page's bar) by itself.
    func reads(onHex backgroundHex: String, minimum: Double) -> Bool {
        hexStops.allSatisfy { stop in
            (TeamColors.contrastRatio(stop, backgroundHex) ?? 1) >= minimum
        }
    }

    private static func rgb(_ hex: String) -> UInt32? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    // MARK: Colours

    /// `primaryHex` as a colour that follows the appearance; the asset's
    /// `AccentColor` itself for the shipped blue.
    var primaryColor: Color {
        isDefault ? .accentColor : Self.adaptiveColor(primaryHex)
    }

    /// The gradient's colours, following the appearance; a single colour
    /// for a solid.
    var stops: [Color] {
        isDefault ? [.accentColor] : hexStops.map(Self.adaptiveColor)
    }

    /// The fill for the logo's arches and the Settings swatches: the colour
    /// for a solid, a diagonal gradient otherwise.
    var fill: AnyShapeStyle {
        guard style != .solid else { return AnyShapeStyle(primaryColor) }
        return AnyShapeStyle(LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// `hex` in light appearance, `darkModeHex(hex)` in dark.
    private static func adaptiveColor(_ hex: String) -> Color {
        let dark = darkModeHex(hex)
        return Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : hex)
        })
    }

    private static func uiColor(_ hex: String) -> UIColor {
        let value = rgb(hex) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension EnvironmentValues {
    /// The reader's brand accent, set at the root (`View.brandAccent(_:)`).
    @Entry var brandAccent: BrandAccent = .classic
}

// MARK: - Root

extension View {
    /// Applies `accent` to everything under the view: the SwiftUI tint
    /// (`.tint` shape styles, controls, links), `\.brandAccent` for the
    /// logo, and the window's UIKit tint (alerts, menus, sheets UIKit
    /// presents). For the app's root view only.
    ///
    /// The shipped blue overrides nothing: the tint is the asset's
    /// `AccentColor` either way, and the window is left alone.
    func brandAccent(_ accent: BrandAccent) -> some View {
        tint(accent.primaryColor)
            .environment(\.brandAccent, accent)
            .background {
                WindowTint(color: accent.isDefault ? nil : UIColor(accent.primaryColor))
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

/// The myTeams logo with its arches in the reader's accent: the T's bars
/// as drawn for the appearance (`myTeamsLogoBars`), with the arches
/// (`myTeamsLogoArches`, a template mask split from the same art) filled
/// over them with the accent's colour or gradient.
///
/// The shipped blue draws the original full-colour art (`art`), unchanged.
/// Resizable and aspect-fit, like the `Image` it stands in for: frame it.
struct BrandLogoMark: View {
    /// The full-colour art for the shipped blue.
    var art: String = "myTeamsLogo"

    @Environment(\.brandAccent) private var accent

    var body: some View {
        if accent.isDefault {
            Image(art)
                .resizable()
                .scaledToFit()
        } else {
            Image("myTeamsLogoBars")
                .resizable()
                .scaledToFit()
                .overlay {
                    BrandArches(fill: accent.fill)
                }
        }
    }
}

/// The logo's arches in `fill`, the size of the whole logo's canvas, to lay
/// over its bars.
struct BrandArches: View {
    let fill: AnyShapeStyle

    var body: some View {
        Rectangle()
            .fill(fill)
            .mask {
                Image("myTeamsLogoArches")
                    .resizable()
                    .scaledToFit()
            }
    }
}
