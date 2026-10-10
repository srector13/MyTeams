//
//  BrandIconStyleTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
import Testing
import UIKit

@testable import myTeams

/// The logo's styles (`BrandIconStyle`): their storage, their default and
/// the art the drawn ones are cut from.
@Suite("Brand icon style")
struct BrandIconStyleTests {
    @Test("The style is stored under a fixed key")
    func storageKeyIsStable() {
        // Changing it would drop every reader's choice.
        #expect(BrandIconStyle.storageKey == "settings.brandIconStyle")
    }

    @Test("There are at least five styles, the shipped logo among them")
    func styleCount() {
        let all = BrandIconStyle.allCases
        #expect(all.count >= 5)
        #expect(all.contains(.classic))
    }

    @Test("Raw values are stable, so stored choices still read")
    func rawValuesAreStable() {
        #expect(BrandIconStyle.classic.rawValue == "classic")
        #expect(BrandIconStyle.archesOnly.rawValue == "archesOnly")
        #expect(BrandIconStyle.barCrest.rawValue == "barCrest")
        #expect(BrandIconStyle.monogram.rawValue == "monogram")
        #expect(BrandIconStyle.outline.rawValue == "outline")
        #expect(BrandIconStyle.tile.rawValue == "tile")
    }

    @Test("Raw values and titles are unique, and every title says something")
    func uniqueness() {
        let all = BrandIconStyle.allCases
        #expect(Set(all.map(\.rawValue)).count == all.count)
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.id)).count == all.count)
        for style in all {
            #expect(!style.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(style)")
        }
    }

    @Test("A style survives a round trip through UserDefaults")
    func roundTrip() throws {
        let suite = "BrandIconStyleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for style in BrandIconStyle.allCases {
            defaults.set(style.rawValue, forKey: BrandIconStyle.storageKey)
            let stored = defaults.string(forKey: BrandIconStyle.storageKey) ?? ""
            #expect(BrandIconStyle(rawValue: stored) == style)
        }
    }

    @Test("Nothing stored reads as the shipped logo")
    func unreadDefaultIsClassic() throws {
        let suite = "BrandIconStyleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // What `@AppStorage(…) = .classic` falls back to.
        let stored = defaults.string(forKey: BrandIconStyle.storageKey)
        #expect(stored == nil)
        let read: BrandIconStyle = stored.flatMap(BrandIconStyle.init(rawValue:)) ?? .classic
        #expect(read == .classic)
    }

    @Test("An unknown stored value isn't a style")
    func unknownValue() {
        #expect(BrandIconStyle(rawValue: "wordmark") == nil)
    }

    @Test("The default is the shipped logo, alone")
    func defaultIsClassic() {
        #expect(BrandIconStyle.classic.isDefault)
        #expect(BrandIconStyle.allCases.filter(\.isDefault) == [.classic])
    }

    @Test("The environment draws the shipped logo until the root says otherwise")
    func environmentDefault() {
        #expect(EnvironmentValues().brandIconStyle == .classic)
    }

    @Test("The drawn styles' art ships, on the logo's canvas")
    func styleLayers() throws {
        let logo = try #require(UIImage(named: "myTeamsLogo"))
        #expect(abs(logo.size.width / logo.size.height - BrandIconStyle.canvasAspect) < 0.01)
        for name in ["myTeamsLogoArches", "myTeamsLogoBars", "myTeamsLogoMonoWhite"] {
            let layer = try #require(UIImage(named: name), "\(name)")
            #expect(layer.size == logo.size, "\(name)")
        }
    }
}
