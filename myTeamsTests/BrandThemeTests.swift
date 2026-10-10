//
//  BrandThemeTests.swift
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

/// The brand themes (`BrandTheme`): the designer's palettes, their storage,
/// their art, the alternate app icons they switch to, and the first-launch
/// step that offers them (`ThemeOnboarding`).
@Suite("Brand theme")
struct BrandThemeTests {
    /// The designer's `palettes.json`, by id: iconLight background, lanes,
    /// tee; iconDark background, lanes, tee; logoOnLight lanes, tee;
    /// logoOnDark lanes, tee; appIconName.
    static let expected: [String: [String]] = [
        "cobalt": ["#2443F2", "#92A1F8", "#FFFFFF", "#0E1016", "#5673FF", "#FFFFFF", "#2443F2", "#0E1016", "#5673FF", "#FFFFFF", "AppIcon-Cobalt"],
        "sky": ["#168FE0", "#8AC7F0", "#FFFFFF", "#0E1016", "#5CC0FF", "#FFFFFF", "#168FE0", "#0E1016", "#5CC0FF", "#FFFFFF", "AppIcon-Sky"],
        "teal": ["#0E8F84", "#86C7C2", "#FFFFFF", "#0E1016", "#2DD4BF", "#FFFFFF", "#0E8F84", "#0E1016", "#2DD4BF", "#FFFFFF", "AppIcon-Teal"],
        "green": ["#15964A", "#8ACAA4", "#FFFFFF", "#0E1016", "#3DDC84", "#FFFFFF", "#15964A", "#0E1016", "#3DDC84", "#FFFFFF", "AppIcon-Green"],
        "gold": ["#F5B81F", "#FADC8F", "#0E1016", "#0E1016", "#FFC83D", "#FFFFFF", "#B97A00", "#0E1016", "#FFC83D", "#FFFFFF", "AppIcon-Gold"],
        "orange": ["#E85A10", "#F4AC88", "#FFFFFF", "#0E1016", "#FF8A3D", "#FFFFFF", "#E85A10", "#0E1016", "#FF8A3D", "#FFFFFF", "AppIcon-Orange"],
        "red": ["#D92B3A", "#EC959C", "#FFFFFF", "#0E1016", "#FF5F66", "#FFFFFF", "#D92B3A", "#0E1016", "#FF5F66", "#FFFFFF", "AppIcon-Red"],
        "pink": ["#DB3287", "#ED98C3", "#FFFFFF", "#0E1016", "#FF74B5", "#FFFFFF", "#DB3287", "#0E1016", "#FF74B5", "#FFFFFF", "AppIcon-Pink"],
        "purple": ["#7A3FF2", "#BC9FF8", "#FFFFFF", "#0E1016", "#A283FF", "#FFFFFF", "#7A3FF2", "#0E1016", "#A283FF", "#FFFFFF", "AppIcon-Purple"],
        "graphite": ["#F2F2F5", "#A9ABB8", "#0E1016", "#0E1016", "#9698A6", "#FFFFFF", "#7C7E8C", "#0E1016", "#9698A6", "#FFFFFF", "AppIcon-Graphite"],
    ]

    /// The palettes' ids, in the designer's order.
    static let paletteIDs = ["cobalt", "sky", "teal", "green", "gold", "orange", "red", "pink", "purple", "graphite"]

    /// The checkout's app sources, found from this file's path: the
    /// simulator shares the Mac's file system.
    static let appSources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Hawk Nation")

    private func scratchDefaults() throws -> UserDefaults {
        let suite = "BrandThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: Cases

    @Test("Classic and the ten palettes, classic first and the only default")
    func cases() {
        #expect(BrandTheme.allCases.map(\.rawValue) == ["classic"] + Self.paletteIDs)
        #expect(BrandTheme.allCases.first == .classic)
        #expect(BrandTheme.allCases.filter(\.isDefault) == [.classic])
        #expect(BrandTheme.classic.palette == nil)
        for theme in BrandTheme.allCases where !theme.isDefault {
            #expect(theme.palette != nil, "\(theme) has no palette")
        }
        #expect(EnvironmentValues().brandTheme == .classic)
    }

    @Test("Titles are the designer's names")
    func titles() {
        #expect(BrandTheme.classic.title == "Classic")
        for theme in BrandTheme.allCases where !theme.isDefault {
            #expect(theme.title.lowercased() == theme.rawValue)
        }
    }

    // MARK: Storage

    @Test("Stored under settings.theme, as the theme's id")
    func storageKey() throws {
        #expect(BrandTheme.storageKey == "settings.theme")
        let defaults = try scratchDefaults()
        for theme in BrandTheme.allCases {
            defaults.set(theme.rawValue, forKey: BrandTheme.storageKey)
            #expect(BrandTheme.stored(in: defaults) == theme)
        }
    }

    @Test("Nothing stored, or an unknown id, reads as classic")
    func storedDefault() throws {
        let defaults = try scratchDefaults()
        #expect(BrandTheme.stored(in: defaults) == .classic)
        defaults.set("chartreuse", forKey: BrandTheme.storageKey)
        #expect(BrandTheme.stored(in: defaults) == .classic)
    }

    @Test("The retired accent and icon-style settings are dropped, not migrated")
    func retiredKeys() throws {
        #expect(BrandTheme.retiredStorageKeys == ["settings.brandAccent", "settings.brandIconStyle"])
        let defaults = try scratchDefaults()
        defaults.set("ocean", forKey: "settings.brandAccent")
        defaults.set("monogram", forKey: "settings.brandIconStyle")
        BrandTheme.removeRetiredSettings(from: defaults)
        #expect(defaults.object(forKey: "settings.brandAccent") == nil)
        #expect(defaults.object(forKey: "settings.brandIconStyle") == nil)
        #expect(BrandTheme.stored(in: defaults) == .classic)
    }

    // MARK: Palettes

    @Test("Every hex is the designer's, verbatim")
    func hexValues() throws {
        #expect(Set(Self.expected.keys) == Set(Self.paletteIDs))
        for id in Self.paletteIDs {
            let theme = try #require(BrandTheme(rawValue: id))
            let palette = try #require(theme.palette)
            let values = try #require(Self.expected[id])
            let actual = [
                palette.iconLight.background, palette.iconLight.lanes, palette.iconLight.tee,
                palette.iconDark.background, palette.iconDark.lanes, palette.iconDark.tee,
                palette.logoOnLight.lanes, palette.logoOnLight.tee,
                palette.logoOnDark.lanes, palette.logoOnDark.tee,
            ]
            #expect(actual == Array(values.prefix(10)), "\(id)'s colours differ from palettes.json")
        }
    }

    @Test("The accent is the logo's lanes: on light in light appearance, on dark in dark")
    func accent() throws {
        #expect(BrandTheme.classic.accentLightHex == nil)
        #expect(BrandTheme.classic.accentDarkHex == nil)
        #expect(BrandTheme.classic.accentUIColor == nil)
        #expect(BrandTheme.classic.accentColor == Color.accentColor)
        for id in Self.paletteIDs {
            let theme = try #require(BrandTheme(rawValue: id))
            let values = try #require(Self.expected[id])
            #expect(theme.accentLightHex == values[6])
            #expect(theme.accentDarkHex == values[8])

            let color = try #require(theme.accentUIColor)
            let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            #expect(Self.hex(light) == values[6].dropFirst().uppercased())
            #expect(Self.hex(dark) == values[8].dropFirst().uppercased())
        }
    }

    /// `color`'s sRGB channels as six hex digits.
    private static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    // MARK: Art

    @Test("Each palette's logo is its image set for the scheme; classic has none of its own")
    func logoNames() throws {
        #expect(BrandTheme.classic.logoImageName(for: .light) == nil)
        #expect(BrandTheme.classic.logoImageName(for: .dark) == nil)
        for id in Self.paletteIDs {
            let theme = try #require(BrandTheme(rawValue: id))
            #expect(theme.logoImageName(for: .light) == "myTeams-logo-\(id)-on-light")
            #expect(theme.logoImageName(for: .dark) == "myTeams-logo-\(id)-on-dark")
        }
    }

    @Test("Every logo and icon preview is in the asset catalog, and classic's logo is still the shipped one")
    func artLoads() throws {
        let shipped = try #require(UIImage(named: "myTeamsLogo"))
        for theme in BrandTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                if let name = theme.logoImageName(for: scheme) {
                    let logo = try #require(UIImage(named: name), "No image set \(name)")
                    // The shipped logo's aspect, so a frame holds across themes.
                    #expect(abs(logo.size.width / logo.size.height - shipped.size.width / shipped.size.height) < 0.01)
                }
                let preview = theme.iconPreviewImageName(for: scheme)
                #expect(UIImage(named: preview) != nil, "No image set \(preview)")
            }
        }
    }

    // MARK: App icons

    @Test("Each palette names its alternate icon; classic the primary")
    func appIconNames() throws {
        #expect(BrandTheme.classic.appIconName == nil)
        for id in Self.paletteIDs {
            let theme = try #require(BrandTheme(rawValue: id))
            let values = try #require(Self.expected[id])
            #expect(theme.appIconName == values[10])
            #expect(theme.appIconName == "AppIcon-\(theme.title)")
        }
        let names = BrandTheme.allCases.compactMap(\.appIconName)
        #expect(Set(names).count == Self.paletteIDs.count)
    }

    @Test("Info.plist's alternate icons are exactly the AppIcon-* sets in the asset catalog")
    func infoPlistMatchesAppIconSets() throws {
        let plistURL = Self.appSources.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        let assets = Self.appSources.appendingPathComponent("Resources/Assets.xcassets")
        let sets = try FileManager.default.contentsOfDirectory(atPath: assets.path)
            .filter { $0.hasPrefix("AppIcon-") && $0.hasSuffix(".appiconset") }
            .map { String($0.dropLast(".appiconset".count)) }
        #expect(Set(sets) == Set(BrandTheme.allCases.compactMap(\.appIconName)))
        // The primary icon is still there, and still the primary.
        #expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent("AppIcon.appiconset/Contents.json").path))

        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            let icons = try #require(plist[key] as? [String: Any], "No \(key)")
            let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
            #expect(primary["CFBundleIconName"] as? String == "AppIcon")

            let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
            #expect(Set(alternates.keys) == Set(sets), "\(key)'s alternates differ from the asset catalog")
            for (name, entry) in alternates {
                let entry = try #require(entry as? [String: Any])
                #expect(entry["CFBundleIconName"] as? String == name, "\(key).\(name) names another icon")
                let contents = assets.appendingPathComponent("\(name).appiconset/Contents.json")
                #expect(FileManager.default.fileExists(atPath: contents.path), "No \(name).appiconset")
            }
        }
    }

    @Test("The built app lists every theme's alternate icon")
    func bundleListsAlternateIcons() throws {
        // The tests run hosted in the app, so this is the app's Info.plist
        // as built, after the asset catalog compiler's additions.
        let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        for name in BrandTheme.allCases.compactMap(\.appIconName) {
            #expect(alternates[name] != nil, "The app doesn't list \(name)")
        }
    }

    // MARK: Onboarding

    @MainActor
    @Test("A fresh install is offered the theme step; an earlier install never is")
    func onboardingFreshAndExisting() throws {
        let fresh = try scratchDefaults()
        ThemeOnboarding.prepare(defaults: fresh, isExistingInstall: false, environment: [:])
        #expect(ThemeOnboarding.isPending(in: fresh))

        let existing = try scratchDefaults()
        ThemeOnboarding.prepare(defaults: existing, isExistingInstall: true, environment: [:])
        #expect(!ThemeOnboarding.isPending(in: existing))
        #expect(BrandTheme.stored(in: existing) == .classic)
    }

    @MainActor
    @Test("Once finished or skipped, the step is never offered again")
    func onboardingNeverRepeats() throws {
        #expect(ThemeOnboarding.completedKey == "onboarding.themeStep.completed")
        let defaults = try scratchDefaults()
        ThemeOnboarding.prepare(defaults: defaults, isExistingInstall: false, environment: [:])
        ThemeOnboarding.complete(in: defaults)
        for _ in 0..<2 {
            // Relaunched: a fresh install's signals or not, still done.
            ThemeOnboarding.prepare(defaults: defaults, isExistingInstall: false, environment: [:])
            #expect(!ThemeOnboarding.isPending(in: defaults))
        }
    }

    @MainActor
    @Test("An earlier install is detected from the settings it already stored")
    func existingInstallDetection() throws {
        let shared = try scratchDefaults()
        let defaults = try scratchDefaults()
        #expect(!ThemeOnboarding.isExistingInstall(defaults: defaults, sharedDefaults: shared))

        defaults.set("dark", forKey: AppAppearance.storageKey)
        #expect(ThemeOnboarding.isExistingInstall(defaults: defaults, sharedDefaults: shared))

        let accentOnly = try scratchDefaults()
        accentOnly.set("ocean", forKey: "settings.brandAccent")
        #expect(ThemeOnboarding.isExistingInstall(defaults: accentOnly, sharedDefaults: shared))

        let seeded = try scratchDefaults()
        seeded.set(true, forKey: FavoritesCodec.seededKey)
        #expect(ThemeOnboarding.isExistingInstall(defaults: try scratchDefaults(), sharedDefaults: seeded))
    }

    #if DEBUG
    @MainActor
    @Test("UI-test launches skip the step unless they ask for it")
    func onboardingLaunchEnvironment() throws {
        let uiTest = try scratchDefaults()
        ThemeOnboarding.prepare(defaults: uiTest, isExistingInstall: false, environment: ["MYTEAMS_FAVORITES": "none"])
        #expect(!ThemeOnboarding.isPending(in: uiTest))

        let asked = try scratchDefaults()
        ThemeOnboarding.complete(in: asked)
        ThemeOnboarding.prepare(defaults: asked, isExistingInstall: true, environment: ["MYTEAMS_ONBOARDING": "1", "MYTEAMS_FAVORITES": "none"])
        #expect(ThemeOnboarding.isPending(in: asked))
    }
    #endif
}
