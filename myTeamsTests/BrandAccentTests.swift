//
//  BrandAccentTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
import Testing
import UIKit

@testable import myTeams

/// The brand accent presets (`BrandAccent`): their storage, their stops and
/// the colour arithmetic behind the tint, and the logo layers they recolour.
@Suite("Brand accent")
struct BrandAccentTests {
    @Test("The accent is stored under a fixed key")
    func storageKeyIsStable() {
        // Changing it would drop every reader's choice.
        #expect(BrandAccent.storageKey == "settings.brandAccent")
    }

    @Test("There are at least 24 presets: solids, gradients and specials")
    func presetCount() {
        let all = BrandAccent.allCases
        #expect(all.count >= 24)
        #expect(all.filter { $0.style == .solid }.count >= 12)
        #expect(all.filter { $0.style == .gradient }.count >= 8)
        #expect(all.filter { $0.style == .special }.count >= 3)
    }

    @Test("Every preset has at least one stop, each six hex digits")
    func stopsAreValid() {
        for accent in BrandAccent.allCases {
            #expect(!accent.hexStops.isEmpty, "\(accent)")
            #expect(accent.stops.count == accent.hexStops.count, "\(accent)")
            for stop in accent.hexStops {
                #expect(TeamColors.relativeLuminance(hex: stop) != nil, "\(accent): \(stop)")
            }
        }
    }

    @Test("Raw values and titles are unique")
    func uniqueness() {
        let all = BrandAccent.allCases
        #expect(Set(all.map(\.rawValue)).count == all.count)
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("An accent survives a round trip through UserDefaults")
    func roundTrip() throws {
        let suite = "BrandAccentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for accent in BrandAccent.allCases {
            defaults.set(accent.rawValue, forKey: BrandAccent.storageKey)
            let stored = defaults.string(forKey: BrandAccent.storageKey) ?? ""
            #expect(BrandAccent(rawValue: stored) == accent)
        }
    }

    @Test("An unknown stored value isn't an accent")
    func unknownValue() {
        #expect(BrandAccent(rawValue: "chartreuse") == nil)
    }

    @Test("The default is the shipped blue, alone")
    func defaultIsShippedBlue() {
        #expect(BrandAccent.classic.isDefault)
        #expect(BrandAccent.allCases.filter(\.isDefault) == [.classic])
        #expect(BrandAccent.classic.hexStops == ["0051BA"])
        #expect(BrandAccent.classic.primaryHex == BrandAccent.shippedHex)
        #expect(BrandAccent.classic.style == .solid)
        // It tints with the asset itself, dark and contrast variants and all.
        #expect(BrandAccent.classic.primaryColor == Color.accentColor)
        #expect(BrandAccent.classic.stops == [Color.accentColor])
    }

    @Test("The shipped hex is the asset catalog's AccentColor")
    func shippedHexMatchesAsset() throws {
        let asset = try #require(UIColor(named: "AccentColor"))
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(asset.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(abs(red - 0.000) < 0.002)
        #expect(abs(green - 0.318) < 0.002)
        #expect(abs(blue - 0.729) < 0.002)
        #expect(BrandAccent.shippedHex == "0051BA")  // 0, 81, 186
    }

    @Test("A solid's primary colour is its only stop")
    func solidPrimary() {
        for accent in BrandAccent.allCases where accent.style == .solid {
            #expect(accent.hexStops.count == 1)
            #expect(accent.primaryHex == accent.hexStops[0], "\(accent)")
        }
    }

    @Test("A gradient's primary colour is its darkest stop")
    func gradientPrimary() {
        for accent in BrandAccent.allCases where accent.style != .solid {
            #expect(accent.hexStops.contains(accent.primaryHex), "\(accent)")
            let primary = TeamColors.relativeLuminance(hex: accent.primaryHex) ?? 1
            for stop in accent.hexStops {
                #expect(primary <= (TeamColors.relativeLuminance(hex: stop) ?? 0), "\(accent): \(stop)")
            }
        }
        #expect(BrandAccent.ocean.primaryHex == "0051BA")
        #expect(BrandAccent.citrus.primaryHex == "E86A10")
        #expect(BrandAccent.spectrum.primaryHex == "8E24AA")
    }

    @Test("The darkest stop keeps the first of equals and skips bad hex")
    func darkestHex() {
        #expect(BrandAccent.darkestHex(in: ["FFFFFF", "000000", "000000"]) == "000000")
        #expect(BrandAccent.darkestHex(in: ["123456", "abc"]) == "123456")
        #expect(BrandAccent.darkestHex(in: []) == BrandAccent.shippedHex)
    }

    @Test("Lightening moves each channel toward white")
    func lightened() {
        #expect(BrandAccent.lightened("000000", by: 0) == "000000")
        #expect(BrandAccent.lightened("000000", by: 1) == "FFFFFF")
        #expect(BrandAccent.lightened("000000", by: 0.5) == "808080")
        #expect(BrandAccent.lightened("#0051BA", by: 0.3) == "4D85CF")
        #expect(BrandAccent.lightened("FF0000", by: 2) == "FFFFFF")
        #expect(BrandAccent.lightened("nope", by: 0.5) == "nope")
    }

    @Test("Dark appearance lifts dark stops and leaves light ones")
    func darkModeHex() {
        #expect(BrandAccent.darkModeHex("13294B") == BrandAccent.lightened("13294B", by: BrandAccent.darkLift))
        #expect(BrandAccent.darkModeHex("FDD835") == "FDD835")
        for accent in BrandAccent.allCases {
            for stop in accent.hexStops {
                let lifted = TeamColors.relativeLuminance(hex: BrandAccent.darkModeHex(stop)) ?? 0
                let original = TeamColors.relativeLuminance(hex: stop) ?? 0
                #expect(lifted >= original, "\(accent): \(stop)")
            }
        }
    }

    @Test("An accent reads on a bar only if every stop does")
    func readsOnBar() {
        #expect(BrandAccent.gold.reads(onHex: "000000", minimum: 2))
        #expect(!BrandAccent.navy.reads(onHex: "000000", minimum: 2))
        // Its yellow stop is lost on white.
        #expect(!BrandAccent.spectrum.reads(onHex: "FFFFFF", minimum: 2))
    }

    @Test("The logo's recolour layers ship at the logo's own size")
    func logoLayers() throws {
        let logo = try #require(UIImage(named: "myTeamsLogo"))
        let arches = try #require(UIImage(named: "myTeamsLogoArches"))
        let bars = try #require(UIImage(named: "myTeamsLogoBars"))
        // Same canvas, so the arches line up over the bars.
        #expect(arches.size == logo.size)
        #expect(bars.size == logo.size)
        // A mask: drawn in whatever colour it's given.
        #expect(arches.renderingMode == .alwaysTemplate)
    }
}
