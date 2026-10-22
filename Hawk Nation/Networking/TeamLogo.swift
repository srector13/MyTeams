//
//  TeamLogo.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Team logo

/// A team's crest, for any team ESPN lists.
///
/// Resolves, in order:
/// 1. the crest stored in `LogoStore` (for the chosen variant);
/// 2. the crest from ESPN's CDN, sized through the combiner, via the same
///    cache `RemoteImage` gives headshots — and stored for next time;
/// 3. while that loads or if it fails: the stored default crest, then the
///    bundled asset (only the seed teams have one), then a `MonogramTeam`.
///
/// The dark crest is used in Dark Mode when the feed lists one; callers that
/// sit the crest on a team-coloured background choose with `forceVariant`.
/// A crest with no dark variant whose main colour would sink into Dark
/// Mode's cards (a navy or purple crest) gets a thin light outline, where
/// the app supplies the rule (`crestOutlineRule`); the widget draws none.
struct TeamLogo: View {
    let team: TeamRef
    let size: CGFloat
    /// The variant to draw regardless of the colour scheme. A `.dark` request
    /// for a team with no dark crest draws the default one.
    var forceVariant: LogoVariant?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.crestOutlineRule) private var outlineRule

    /// Bumped when a crest lands in `LogoStore`, so the body reads it again.
    @State private var storeRevision = 0

    init(team: TeamRef, size: CGFloat, forceVariant: LogoVariant? = nil) {
        self.team = team
        self.size = size
        self.forceVariant = forceVariant
    }

    private var variant: LogoVariant {
        let wanted = forceVariant ?? (colorScheme == .dark ? .dark : .default)
        return wanted == .dark && LogoStore.sourceURL(for: team, variant: .dark) == nil ? .default : wanted
    }

    var body: some View {
        let _ = storeRevision
        let chosen = variant
        let outlined = forceVariant == nil
            && colorScheme == .dark
            && chosen == .default
            && (outlineRule?(team) ?? false)
        Group {
            if let stored = LogoStore.image(for: team, variant: chosen) {
                Image(uiImage: stored)
                    .resizable()
            } else if let remote = LogoStore.combinerURL(team, size: Int(max(64, size * 3)), variant: chosen) {
                RemoteImage(url: remote, showsProgress: false) {
                    offlineFallback
                }
            } else {
                offlineFallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(CrestOutline(isOn: outlined))
        .frame(width: size, height: size)
        .task(id: "\(team.id)|\(chosen.rawValue)") {
            guard LogoStore.url(for: team, variant: chosen) == nil else { return }
            if await LogoStore.prefetched(team, variant: chosen) {
                storeRevision += 1
            }
        }
        .accessibilityHidden(true)
    }

    /// What shows while the remote crest loads, or when there is none.
    @ViewBuilder
    private var offlineFallback: some View {
        if let stored = LogoStore.image(for: team, variant: .default) {
            Image(uiImage: stored)
                .resizable()
        } else if let asset = team.logoAsset {
            Image(asset)
                .resizable()
        } else {
            MonogramTeam(team: team, size: size)
        }
    }
}

extension EnvironmentValues {
    /// Whether a crest with no dark variant needs `TeamLogo`'s light outline
    /// in Dark Mode. The app measures the stored crest (`BarCrest`); `nil`,
    /// as in the widget, draws none.
    @Entry var crestOutlineRule: (@MainActor @Sendable (TeamRef) -> Bool)? = nil
}

/// A one-point light outline traced around a crest's shape: four offset
/// copies under it, as the bar's outlined crest is drawn.
private struct CrestOutline: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            let ink = Color.white.opacity(0.85)
            content
                .shadow(color: ink, radius: 0, x: 1, y: 0)
                .shadow(color: ink, radius: 0, x: -1, y: 0)
                .shadow(color: ink, radius: 0, x: 0, y: 1)
                .shadow(color: ink, radius: 0, x: 0, y: -1)
        } else {
            content
        }
    }
}

// MARK: - Monogram

/// The badge drawn for a team with no crest: a disc in the team colour with
/// its abbreviation, or its sport's symbol when it has none (roadmap §4.4).
/// Deterministic: the same team always draws the same badge.
struct MonogramTeam: View {
    let team: TeamRef
    let size: CGFloat

    var body: some View {
        let fill = Color(hexString: TeamColors.fillHex(for: team))
        let ink = Color(hexString: TeamColors.monogramTextHex(for: team))
        ZStack {
            Circle()
                .fill(fill)
            if team.abbreviation.isEmpty {
                Image(systemName: TeamColors.symbolName(for: team.league.descriptor.kind))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ink)
                    .padding(size * 0.22)
            } else {
                // Proportional to the badge, not to Dynamic Type: the text
                // is part of the crest artwork (the one fixed size X-1 keeps).
                Text(team.abbreviation)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(team.displayName)
    }
}

// MARK: - Colour helpers

/// Colour arithmetic for badges and crest backgrounds, on the feeds'
/// six-digit hex strings.
enum TeamColors {
    /// Fills for teams the feed gives no colour, picked by a stable hash of
    /// the team id. Dark enough that white reads on every one.
    static let fallbackFills = [
        "1F4E79", "7B1E3A", "2E5E3E", "5B2A86",
        "8A4B08", "1B5E6B", "6B1B1B", "3A3A6B",
    ]

    /// The relative luminance (WCAG 2) of a hex colour, 0 (black) to 1
    /// (white), or `nil` for anything that is not six hex digits.
    static func relativeLuminance(hex: String) -> Double? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(value >> 16) + 0.7152 * linear(value >> 8) + 0.0722 * linear(value)
    }

    /// The WCAG contrast ratio of two hex colours, 1 to 21.
    static func contrastRatio(_ first: String, _ second: String) -> Double? {
        guard let a = relativeLuminance(hex: first), let b = relativeLuminance(hex: second) else { return nil }
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The badge fill: the team colour, or a hash-picked fallback.
    static func fillHex(for team: TeamRef) -> String {
        if relativeLuminance(hex: team.colorHex) != nil { return team.colorHex }
        return fallbackFills[Int(stableHash(team.id) % UInt64(fallbackFills.count))]
    }

    /// The badge's text colour: the team's alternate colour when it stands
    /// out from the fill (contrast 3:1 or better, WCAG's large-text bar),
    /// otherwise white or black, whichever contrasts more.
    static func monogramTextHex(for team: TeamRef) -> String {
        let fill = fillHex(for: team)
        if let ratio = contrastRatio(team.alternateColorHex, fill), ratio >= 3 {
            return team.alternateColorHex
        }
        let white = contrastRatio("FFFFFF", fill) ?? 21
        let black = contrastRatio("000000", fill) ?? 1
        return white >= black ? "FFFFFF" : "000000"
    }

    /// The crest variant to draw over a background of `backgroundHex` (the
    /// page header draws the crest over the team's own colour): the dark
    /// crest on a dark background (luminance under 0.5), when there is one.
    static func logoVariant(for team: TeamRef, onBackground backgroundHex: String) -> LogoVariant {
        guard LogoStore.sourceURL(for: team, variant: .dark) != nil,
              let luminance = relativeLuminance(hex: backgroundHex),
              luminance < 0.5
        else { return .default }
        return .dark
    }

    /// The grouped surfaces a team accent (a bar, a dash, a track's fill, a
    /// followed row's tint) is drawn on: the lighter of the two in light
    /// mode and the lighter of the two in dark (the inset card), which are
    /// the harder of each pair to stand out on.
    static let lightAccentSurfaceHex = "F2F2F7"
    static let darkAccentSurfaceHex = "2C2C2E"

    /// WCAG's bar for marks that aren't text (bars, rules, outlines).
    static let minimumAccentContrast = 3.0

    /// `hex` moved `fraction` of the way to `target`, channel by channel.
    static func mixHex(_ hex: String, toward target: String, by fraction: Double) -> String {
        func channels(_ hex: String) -> [Double]? {
            let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            return [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)]
        }
        guard let from = channels(hex), let to = channels(target) else { return hex }
        let t = min(max(fraction, 0), 1)
        return zip(from, to)
            .map { String(format: "%02X", Int(($0 + ($1 - $0) * t).rounded())) }
            .joined()
    }

    /// A colour's hue in degrees, or `nil` for a grey (or not a colour).
    static func hue(hex: String) -> Double? {
        let digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingPrefix("#")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), spread = high - low
        guard spread > 0.08 else { return nil }
        let raw: Double
        if high == r { raw = (g - b) / spread }
        else if high == g { raw = (b - r) / spread + 2 }
        else { raw = (r - g) / spread + 4 }
        let degrees = raw * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// A team accent that reads on `surfaceHex` (3:1, `minimumAccentContrast`):
    /// the team colour when it already does; else its alternate colour when
    /// that does and is the same family of colour (within 30° of hue, so a
    /// navy's light blue, never a red's gold); else the team colour moved
    /// towards white on a dark surface, or black on a light one, until it
    /// does. Navy, the Royals' blue and the Jayhawks' blue vanish on a
    /// dark card at their own strength (1.0 to 1.9:1).
    static func accentHex(_ baseHex: String, alternate: String? = nil, on surfaceHex: String) -> String {
        if let ratio = contrastRatio(baseHex, surfaceHex), ratio >= minimumAccentContrast { return baseHex }
        if let alternate,
           let ratio = contrastRatio(alternate, surfaceHex), ratio >= minimumAccentContrast,
           let baseHue = hue(hex: baseHex), let alternateHue = hue(hex: alternate) {
            let gap = abs(baseHue - alternateHue)
            if min(gap, 360 - gap) <= 30 { return alternate }
        }
        let target = (relativeLuminance(hex: surfaceHex) ?? 0) < 0.5 ? "FFFFFF" : "000000"
        for step in 1...20 {
            let candidate = mixHex(baseHex, toward: target, by: Double(step) / 20)
            if let ratio = contrastRatio(candidate, surfaceHex), ratio >= minimumAccentContrast {
                return candidate
            }
        }
        return target
    }

    /// The team's accent for marks on content cards: `accentHex(_:alternate:on:)`
    /// against the light grouped surface in light mode and the dark one in
    /// dark mode, so a team-colour bar, dash, track or row tint stays
    /// visible in both.
    static func accent(for team: TeamRef) -> Color {
        let fill = fillHex(for: team)
        let alternate = team.alternateColorHex
        let light = accentHex(fill, alternate: alternate, on: lightAccentSurfaceHex)
        let dark = accentHex(fill, alternate: alternate, on: darkAccentSurfaceHex)
        let lightColor = UIColor(Color(hexString: light))
        let darkColor = UIColor(Color(hexString: dark))
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }

    /// The SF Symbol badging a team with no abbreviation.
    static func symbolName(for kind: SportKind) -> String {
        switch kind {
        case .football: "football.fill"
        case .basketball: "basketball.fill"
        case .baseball: "baseball.fill"
        case .soccer: "soccerball"
        case .hockey: "hockey.puck.fill"
        case .other: "sportscourt.fill"
        }
    }

    /// FNV-1a over the UTF-8 bytes. `Hasher` is seeded per launch, so it
    /// cannot pick a colour that stays put.
    static func stableHash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
    }
}
