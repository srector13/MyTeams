//
//  FavoritesStoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// An in-memory stand-in for `NSUbiquitousKeyValueStore`.
private final class MemoryCloudStore: FavoritesCloudStore {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

/// A `UserDefaults` suite of its own, so tests never touch the App Group.
private func scratchDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "FavoritesStoreTests.\(UUID().uuidString)"))
}

private let seedIDs = [
    "basketball/mens-college-basketball:2305",
    "football/nfl:12",
    "baseball/mlb:7",
    "soccer/usa.1:186",
]

@Suite("Favorites")
struct FavoritesStoreTests {
    // MARK: Codec

    @Test("Favorites round-trip through JSON in order")
    func jsonRoundTrip() throws {
        let favorites = [
            FavoriteTeam(teamID: "soccer/usa.1:186", addedAt: Date(timeIntervalSince1970: 1_790_000_000), notify: false),
            FavoriteTeam(teamID: "football/nfl:12", addedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            FavoriteTeam(teamID: "basketball/mens-college-basketball:2305", addedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        ]
        let data = try #require(FavoritesCodec.encode(favorites))
        #expect(FavoritesCodec.decode(data) == favorites)
        #expect(FavoritesCodec.decode(data)?.map(\.teamID) == ["soccer/usa.1:186", "football/nfl:12", "basketball/mens-college-basketball:2305"])
        #expect(favorites[1].notify)  // defaults to true
        #expect(favorites[0].id == "soccer/usa.1:186")
    }

    @Test("Unreadable data decodes as nothing stored")
    func unreadableData() {
        #expect(FavoritesCodec.decode(nil) == nil)
        #expect(FavoritesCodec.decode(Data("not json".utf8)) == nil)
    }

    @Test("A fresh install is seeded once with the legacy teams")
    func seedsOnce() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()

        let first = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        #expect(first.source == .seeded)
        #expect(first.favorites.map(\.teamID) == seedIDs)
        #expect(defaults.bool(forKey: FavoritesCodec.seededKey))
        // The seed is mirrored to iCloud byte for byte.
        #expect(cloud.data(forKey: FavoritesCodec.key) == defaults.data(forKey: FavoritesCodec.key))

        let second = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: ["football/nfl:99"])
        #expect(second.source == .local)
        #expect(second.favorites == first.favorites)
    }

    @Test("An emptied list stays empty: the seed never runs twice")
    func emptiedListIsNotReseeded() throws {
        let defaults = try scratchDefaults()
        _ = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: nil, seedIDs: seedIDs)
        FavoritesCodec.save([], defaults: defaults, cloud: nil)
        let emptied = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: nil, seedIDs: seedIDs)
        #expect(emptied.source == .local)
        #expect(emptied.favorites.isEmpty)

        // Even with the list itself gone, the flag keeps the seed from rerunning.
        defaults.removeObject(forKey: FavoritesCodec.key)
        let missing = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: nil, seedIDs: seedIDs)
        #expect(missing.source == .empty)
        #expect(missing.favorites.isEmpty)
    }

    @Test("With nothing local, the iCloud copy is restored ahead of the seed")
    func cloudRestoreBeatsSeed() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        let synced = [FavoriteTeam(teamID: "hockey/nhl:25", addedAt: Date(timeIntervalSince1970: 1_750_000_000))]
        cloud.set(FavoritesCodec.encode(synced), forKey: FavoritesCodec.key)

        let loaded = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        #expect(loaded.source == .restoredFromCloud)
        #expect(loaded.favorites == synced)
        #expect(FavoritesCodec.storedIDs(in: defaults) == ["hockey/nhl:25"])
        #expect(defaults.bool(forKey: FavoritesCodec.seededKey))
    }

    @Test("A local list wins over a different iCloud copy")
    func localBeatsCloud() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        FavoritesCodec.save([FavoriteTeam(teamID: "football/nfl:12")], defaults: defaults, cloud: nil)
        cloud.set(FavoritesCodec.encode([FavoriteTeam(teamID: "hockey/nhl:25")]), forKey: FavoritesCodec.key)

        let loaded = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        #expect(loaded.source == .local)
        #expect(loaded.favorites.map(\.teamID) == ["football/nfl:12"])
    }

    // MARK: Store

    @MainActor
    @Test("Edits persist in order, mirror to iCloud and reload the widgets")
    func storeEdits() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        var reloads = 0
        let store = FavoritesStore(
            defaults: defaults,
            cloud: cloud,
            seedIDs: seedIDs,
            isExistingInstall: true,
            reloadWidgets: { reloads += 1 }
        )
        #expect(store.teamIDs == seedIDs)
        #expect(reloads == 0)

        store.remove("football/nfl:12")
        store.move(from: IndexSet(integer: 2), to: 0)  // Sporting to the front
        #expect(store.teamIDs == ["soccer/usa.1:186", "basketball/mens-college-basketball:2305", "baseball/mlb:7"])
        #expect(FavoritesCodec.storedIDs(in: defaults) == store.teamIDs)
        #expect(FavoritesCodec.decode(cloud.data(forKey: FavoritesCodec.key))?.map(\.teamID) == store.teamIDs)
        #expect(reloads == 2)

        store.remove("football/nfl:12")  // no longer followed: nothing to do
        #expect(reloads == 2)
        #expect(!store.isFavorite("football/nfl:12"))
        #expect(store.isFavorite("baseball/mlb:7"))
    }

    @MainActor
    @Test("Onboarding shows only on a fresh install, until completed")
    func onboardingGate() throws {
        let fresh = try scratchDefaults()
        let store = FavoritesStore(defaults: fresh, cloud: nil, seedIDs: seedIDs, isExistingInstall: false, reloadWidgets: {})
        #expect(store.needsOnboarding)
        store.completeOnboarding()
        #expect(!store.needsOnboarding)
        #expect(fresh.bool(forKey: FavoritesStore.onboardingKey))
        // Relaunch: the list is local now, so no sheet.
        #expect(!FavoritesStore(defaults: fresh, cloud: nil, seedIDs: seedIDs, isExistingInstall: false, reloadWidgets: {}).needsOnboarding)

        let upgraded = try scratchDefaults()
        #expect(!FavoritesStore(defaults: upgraded, cloud: nil, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {}).needsOnboarding)

        let restored = try scratchDefaults()
        let cloud = MemoryCloudStore()
        cloud.set(FavoritesCodec.encode([FavoriteTeam(teamID: "football/nfl:12")]), forKey: FavoritesCodec.key)
        #expect(!FavoritesStore(defaults: restored, cloud: cloud, seedIDs: seedIDs, isExistingInstall: false, reloadWidgets: {}).needsOnboarding)
    }
}
