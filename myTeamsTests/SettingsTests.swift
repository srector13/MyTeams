//
//  SettingsTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
import Testing

@testable import myTeams

/// The appearance choice and its storage (`AppAppearance`), and the About
/// section's version line (`AboutInfo`).
@Suite("Settings")
struct SettingsTests {
    @Test("The appearance is stored under a fixed key")
    func storageKeyIsStable() {
        // Changing it would drop every reader's choice.
        #expect(AppAppearance.storageKey == "settings.appearance")
    }

    @Test("Each appearance forces its scheme; System forces none")
    func schemes() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("An appearance survives a round trip through UserDefaults")
    func roundTrip() throws {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for option in AppAppearance.allCases {
            defaults.set(option.rawValue, forKey: AppAppearance.storageKey)
            let stored = defaults.string(forKey: AppAppearance.storageKey) ?? ""
            let read = AppAppearance(rawValue: stored)
            #expect(read == option)
        }
    }

    @Test("An unknown stored value isn't an appearance")
    func unknownValue() {
        #expect(AppAppearance(rawValue: "sepia") == nil)
    }

    @Test("The version line shows the version and the build")
    func versionText() {
        let info: [String: Any] = ["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "7"]
        #expect(AboutInfo.versionText(info: info) == "2.0.0 (7)")
    }

    @Test("A missing version or build shows a dash")
    func versionTextMissing() {
        #expect(AboutInfo.versionText(info: nil) == "– (–)")
        #expect(AboutInfo.versionText(info: ["CFBundleVersion": "7"]) == "– (7)")
    }
}
