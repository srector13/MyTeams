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
struct TeamLogo: View {
    let team: TeamRef
    let size: CGFloat
    /// The variant to draw regardless of the colour scheme. A `.dark` request
    /// for a team with no dark crest draws the default one.
    var forceVariant: LogoVariant?

    @Environment(\.colorScheme) private var colorScheme

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
