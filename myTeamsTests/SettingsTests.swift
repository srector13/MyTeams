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

/// Around Your Leagues' settings (`HomeLeaguesSettings`): their keys, their
/// defaults, and a round trip through `UserDefaults` in the form the views'
/// `@AppStorage` writes.
@Suite("Home league settings")
struct HomeLeaguesSettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "HomeLeaguesSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test("The settings are stored under fixed keys")
    func storageKeys() {
        // Changing one would drop every reader's choice.
        #expect(HomeLeaguesSettings.scopeKey == "home.leagues.scope")
        #expect(HomeLeaguesSettings.hiddenLeaguesKey == "home.leagues.hidden")
        #expect(HomeLeaguesSettings.limitKey == "home.leagues.limit")
        #expect(HomeLeaguesSettings.rankedOnlyKey == "home.leagues.top25")
        #expect(HomeLeaguesSettings.includesMyTeamsKey == "home.leagues.includeMine")
    }

    @Test("Nothing stored reads as the defaults: today, every league, five games, Top 25 only, not my teams")
    func defaults() throws {
        try withDefaults { defaults in
            let read = HomeLeaguesSettings(defaults: defaults)
            #expect(read == .standard)
            #expect(read.scope == .today)
            #expect(read.hiddenLeagues.isEmpty)
            #expect(read.limit == .five)
            #expect(read.rankedOnly)
            #expect(!read.includesMyTeams)
        }
    }

    @Test("Settings survive a round trip through UserDefaults")
    func roundTrip() throws {
        try withDefaults { defaults in
            let settings = HomeLeaguesSettings(
                scope: .week,
                hiddenLeagues: [.premierLeague, .collegeFootball],
                limit: .all,
                rankedOnly: false,
                includesMyTeams: true
            )
            settings.write(to: defaults)
            #expect(HomeLeaguesSettings(defaults: defaults) == settings)
            // The plain forms `@AppStorage` reads back.
            #expect(defaults.string(forKey: HomeLeaguesSettings.scopeKey) == "week")
            #expect(defaults.integer(forKey: HomeLeaguesSettings.limitKey) == 0)
            #expect(defaults.string(forKey: HomeLeaguesSettings.hiddenLeaguesKey) == "football/college-football,soccer/eng.1")
            #expect(defaults.bool(forKey: HomeLeaguesSettings.includesMyTeamsKey))

            for limit in HomeLeaguesGameLimit.allCases {
                var changed = settings
                changed.limit = limit
                changed.write(to: defaults)
                #expect(HomeLeaguesSettings(defaults: defaults).limit == limit)
            }
        }
    }

    @Test("Unreadable stored values fall back to the defaults")
    func unreadable() throws {
        try withDefaults { defaults in
            defaults.set("fortnight", forKey: HomeLeaguesSettings.scopeKey)
            defaults.set(7, forKey: HomeLeaguesSettings.limitKey)
            defaults.set("soccer/eng.1,,bogus, football/nfl ", forKey: HomeLeaguesSettings.hiddenLeaguesKey)
            let read = HomeLeaguesSettings(defaults: defaults)
            #expect(read.scope == .today)
            #expect(read.limit == .five)
            #expect(read.hiddenLeagues == [.premierLeague, .nfl])
        }
    }

    @Test("Leagues are stored switched off, so a newly followed team's league shows; unfollowed ones are forgotten")
    func hiddenLeagues() {
        var settings = HomeLeaguesSettings.standard
        settings.hiddenLeagues = [.nfl]
        #expect(!settings.shows(.nfl))
        #expect(settings.shows(.premierLeague))
        #expect(settings.ranksOnly(.collegeFootball))
        #expect(!settings.ranksOnly(.nfl))

        let ids = ["football/nfl:12", "soccer/eng.1:359", "football/nfl:7", "bogus"]
        #expect(HomeLeaguesSettings.favoriteLeagues(teamIDs: ids) == [.nfl, .premierLeague])

        // The NFL is no longer followed: its switch is forgotten.
        let stored = HomeLeaguesSettings.storage(hiddenLeagues: [.nfl, .premierLeague])
        #expect(HomeLeaguesSettings.pruned(storage: stored, favoriteLeagues: [.premierLeague]) == "soccer/eng.1")
        #expect(HomeLeaguesSettings.pruned(storage: stored, favoriteLeagues: [.nfl, .premierLeague]) == nil)
        // No favorites to go by: nothing is pruned.
        #expect(HomeLeaguesSettings.pruned(storage: stored, favoriteLeagues: []) == nil)
    }
}
