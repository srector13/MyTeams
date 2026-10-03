//
//  ThemeTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/3/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import Testing

@testable import myTeams

/// The arithmetic behind the theme's accessibility primitives: scrim
/// opacity and contrast-picked ink.
@Suite("Theme")
struct ThemeTests {
    @Test("Scrims keep their opacity by default")
    func scrimDefault() {
        #expect(Theme.scrimOpacity(0.5, contrast: .standard, reduceTransparency: false) == 0.5)
    }

    @Test("Increase Contrast moves a scrim a third of the way to opaque")
    func scrimIncreasedContrast() {
        let raised = Theme.scrimOpacity(0.4, contrast: .increased, reduceTransparency: false)
        #expect(abs(raised - 0.6) < 0.0001)
        #expect(Theme.scrimOpacity(1, contrast: .increased, reduceTransparency: false) == 1)
    }

    @Test("Reduce Transparency makes a scrim opaque")
    func scrimReduceTransparency() {
        #expect(Theme.scrimOpacity(0.2, contrast: .standard, reduceTransparency: true) == 1)
        #expect(Theme.scrimOpacity(0.2, contrast: .increased, reduceTransparency: true) == 1)
    }

    @Test("Radii nest concentrically")
    func radiiConcentric() {
        // A card inset Spacing.s inside its card, and the page's cards
        // inset Spacing.m inside the page, keep their corners concentric.
        #expect(Theme.Radius.card - Theme.Radius.inner == Theme.Spacing.s)
        #expect(Theme.Radius.page - Theme.Radius.card == Theme.Spacing.m)
    }

    @Test("Ink reaches 4.5:1 on any team colour", arguments: [
        "0051BA", "FFB612", "FFFFFF", "000000", "E31837", "7F7F7F", "00A3E0", "FFCD00",
    ])
    func inkContrast(background: String) throws {
        let ink = TeamColors.inkHex(on: background)
        let ratio = try #require(TeamColors.contrastRatio(ink, background))
        #expect(ratio >= TeamColors.minimumInkContrast)
    }

    @Test("Ink prefers the alternate colour only when it reads")
    func inkAlternate() {
        // Gold on navy reads; gold on white doesn't.
        #expect(TeamColors.inkHex(on: "002244", alternate: "FFB612") == "FFB612")
        #expect(TeamColors.inkHex(on: "FFFFFF", alternate: "FFB612") == "000000")
        #expect(TeamColors.inkHex(on: "0051BA", alternate: "not a colour") == "FFFFFF")
    }
}
