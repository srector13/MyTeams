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
/// opacity, the placeholder pulse, launch-time accessibility stand-ins
/// and contrast-picked ink.
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

    @Test("A gradient scrim adapts stop by stop and keeps its locations")
    func gradientScrim() {
        let stops = [
            Theme.ScrimStop(opacity: 0.6, location: 0),
            Theme.ScrimStop(opacity: 0.85, location: 1),
        ]
        #expect(Theme.scrimStops(stops, contrast: .standard, reduceTransparency: false) == stops)

        let raised = Theme.scrimStops(stops, contrast: .increased, reduceTransparency: false)
        #expect(raised.map(\.location) == [0, 1])
        #expect(abs(raised[0].opacity - (0.6 + 0.4 / 3)) < 0.0001)
        #expect(abs(raised[1].opacity - (0.85 + 0.15 / 3)) < 0.0001)

        let flat = Theme.scrimStops(stops, contrast: .standard, reduceTransparency: true)
        #expect(flat.map(\.opacity) == [1, 1])
        #expect(flat.map(\.location) == [0, 1])
    }

    @Test("Placeholders pulse between their floor and peak, and rest still under Reduce Motion")
    func placeholderPulse() {
        #expect(Theme.Placeholder.opacity(raised: false, reduceMotion: false) == Theme.Placeholder.minOpacity)
        #expect(Theme.Placeholder.opacity(raised: true, reduceMotion: false) == Theme.Placeholder.maxOpacity)
        // Still, in the pulse's own tone, whichever end it was headed for.
        let resting = Theme.Placeholder.opacity(raised: false, reduceMotion: true)
        #expect(resting == Theme.Placeholder.opacity(raised: true, reduceMotion: true))
        #expect(resting > Theme.Placeholder.minOpacity)
        #expect(resting < Theme.Placeholder.maxOpacity)
    }

    @Test("Launch accessibility settings are off unless a key is \"1\"")
    func launchAccessibility() {
        let none = Theme.LaunchAccessibility(environment: [:])
        #expect(!none.increaseContrast)
        #expect(!none.reduceTransparency)
        #expect(!none.reduceMotion)

        let all = Theme.LaunchAccessibility(environment: [
            Theme.LaunchAccessibility.increaseContrastKey: "1",
            Theme.LaunchAccessibility.reduceTransparencyKey: "1",
            Theme.LaunchAccessibility.reduceMotionKey: "1",
        ])
        #expect(all.increaseContrast)
        #expect(all.reduceTransparency)
        #expect(all.reduceMotion)

        let motionOnly = Theme.LaunchAccessibility(environment: [
            Theme.LaunchAccessibility.reduceMotionKey: "1",
            Theme.LaunchAccessibility.increaseContrastKey: "0",
        ])
        #expect(motionOnly.reduceMotion)
        #expect(!motionOnly.increaseContrast)
        #expect(!motionOnly.reduceTransparency)
    }

    @Test("A followed row's wash strengthens under Increase Contrast")
    func selectionWash() {
        let standard = Theme.selectionWashOpacity(contrast: .standard)
        let increased = Theme.selectionWashOpacity(contrast: .increased)
        #expect(standard == 0.15)
        #expect(increased > standard)
        #expect(increased < 0.5)
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
