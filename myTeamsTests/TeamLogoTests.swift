//
//  TeamLogoTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The colour arithmetic behind the monogram badge and the header crest's
/// variant.
@Suite("Team logo colours")
struct TeamLogoTests {
    private func team(
        color: String,
        alternate: String,
        abbreviation: String = "TST",
        dark: Bool = false,
        league: LeagueID = .nfl
    ) -> TeamRef {
        TeamRef(
            league: league,
            espnID: "999",
            displayName: "Test Team",
            shortName: "Test",
            abbreviation: abbreviation,
            location: "Test",
            colorHex: color,
            alternateColorHex: alternate,
            logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/tst.png"),
            logoDarkURL: dark ? URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500-dark/tst.png") : nil,
            logoAsset: nil
        )
    }

    @Test("Relative luminance runs from black to white, per WCAG 2")
    func luminance() throws {
        #expect(TeamColors.relativeLuminance(hex: "000000") == 0)
        #expect(TeamColors.relativeLuminance(hex: "FFFFFF") == 1)
        #expect(TeamColors.relativeLuminance(hex: "#ffffff") == 1)
        // Pure green outweighs pure red, which outweighs pure blue.
        let red = try #require(TeamColors.relativeLuminance(hex: "FF0000"))
        let green = try #require(TeamColors.relativeLuminance(hex: "00FF00"))
        let blue = try #require(TeamColors.relativeLuminance(hex: "0000FF"))
        #expect(abs(red - 0.2126) < 0.0001)
        #expect(abs(green - 0.7152) < 0.0001)
        #expect(abs(blue - 0.0722) < 0.0001)
        #expect(TeamColors.relativeLuminance(hex: "") == nil)
        #expect(TeamColors.relativeLuminance(hex: "12345") == nil)
        #expect(TeamColors.relativeLuminance(hex: "GGGGGG") == nil)
    }

    @Test("Contrast ratios: 21:1 for black on white, 1:1 for a colour on itself")
    func contrast() throws {
        let ratio = try #require(TeamColors.contrastRatio("000000", "FFFFFF"))
        #expect(abs(ratio - 21) < 0.0001)
        #expect(TeamColors.contrastRatio("E31837", "E31837") == 1)
        #expect(TeamColors.contrastRatio("", "FFFFFF") == nil)
    }

    @Test("The badge text takes the alternate colour when it stands out")
    func textColour() {
        // Sporting navy with light blue: 8.0:1, so the light blue.
        #expect(TeamColors.monogramTextHex(for: team(color: "002A5C", alternate: "A7C6ED")) == "A7C6ED")
        // Chiefs red with gold is only 2.7:1; white (4.7:1) beats black (4.5:1).
        #expect(TeamColors.monogramTextHex(for: team(color: "e31837", alternate: "ffb612")) == "FFFFFF")
        // Navy with a near-navy alternate: too close, so white.
        #expect(TeamColors.monogramTextHex(for: team(color: "002A5C", alternate: "0B1C3A")) == "FFFFFF")
        // Yellow with no alternate: black reads better than white.
        #expect(TeamColors.monogramTextHex(for: team(color: "FFD700", alternate: "")) == "000000")
    }

    @Test("A colourless team gets a stable, dark fallback fill")
    func fallbackFill() {
        let colourless = team(color: "", alternate: "")
        let fill = TeamColors.fillHex(for: colourless)
        #expect(TeamColors.fallbackFills.contains(fill))
        #expect(TeamColors.fillHex(for: colourless) == fill)  // deterministic
        #expect(TeamColors.monogramTextHex(for: colourless) == "FFFFFF")
        #expect(TeamColors.fillHex(for: team(color: "0051BA", alternate: "")) == "0051BA")
        // FNV-1a's published test vector.
        #expect(TeamColors.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test("Teams with no abbreviation are badged with their sport's symbol")
    func symbols() {
        #expect(TeamColors.symbolName(for: .football) == "football.fill")
        #expect(TeamColors.symbolName(for: .basketball) == "basketball.fill")
        #expect(TeamColors.symbolName(for: .baseball) == "baseball.fill")
        #expect(TeamColors.symbolName(for: .soccer) == "soccerball")
        #expect(TeamColors.symbolName(for: .hockey) == "hockey.puck.fill")
        #expect(LeagueID(sport: "hockey", league: "nhl").descriptor.kind == .hockey)
    }

    @Test("The header crest goes dark on a dark background, if the team has a dark crest")
    func headerVariant() {
        #expect(TeamColors.logoVariant(for: team(color: "002A5C", alternate: "", dark: true), onBackground: "002A5C") == .dark)
        #expect(TeamColors.logoVariant(for: team(color: "002A5C", alternate: "", dark: false), onBackground: "002A5C") == .default)
        #expect(TeamColors.logoVariant(for: team(color: "FFD700", alternate: "", dark: true), onBackground: "FFD700") == .default)
        #expect(TeamColors.logoVariant(for: team(color: "", alternate: "", dark: true), onBackground: "") == .default)
    }
}
