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

/// An in-memory stand-in for `NSUbiquitousKeyValueStore`. Stores sharing one
/// play devices on one iCloud account: the last write wins, and
/// `receive(_:)` delivers it as the server would.
private final class MemoryCloudStore: FavoritesCloudStore {
    var values: [String: Any] = [:]
    /// How many times `set(_:forKey:)` has been called.
    var writes = 0

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
        writes += 1
    }

    func synchronize() -> Bool { true }

    /// Every stored favorites entry, tombstones included.
    var entries: [FavoriteTeam] {
        FavoritesCodec.decodeEntries(data(forKey: FavoritesCodec.key)) ?? []
    }
}

/// Tells `store` that iCloud's favorites changed, as
/// `didChangeExternallyNotification` does.
@MainActor
private func receive(_ store: FavoritesStore, reason: Int = NSUbiquitousKeyValueStoreServerChange) {
    store.cloudDidChange(reason: reason, changedKeys: [FavoritesCodec.key])
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

    @Test("A v1 list, a bare array, decodes as entries with no tombstones")
    func decodesV1() throws {
        let v1 = Data("""
            [{"teamID":"football/nfl:12","addedAt":"2026-01-01T00:00:00Z","notify":true},
             {"teamID":"baseball/mlb:7","addedAt":"2026-02-01T00:00:00Z","notify":false}]
            """.utf8)
        let entries = try #require(FavoritesCodec.decodeEntries(v1))
        #expect(entries.map(\.teamID) == ["football/nfl:12", "baseball/mlb:7"])
        #expect(entries.allSatisfy { $0.removedAt == nil && !$0.isRemoved })
        #expect(FavoritesCodec.decode(v1) == entries)

        // Re-encoded, it is the v2 shape.
        let v2 = try #require(FavoritesCodec.encode(entries))
        let object = try #require(try JSONSerialization.jsonObject(with: v2) as? [String: Any])
        #expect((object["favorites"] as? [Any])?.count == 2)
        #expect(FavoritesCodec.decodeEntries(v2) == entries)
    }

    @Test("A merge keeps the local order and appends remote-only teams oldest first")
    func mergeOrder() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let local = [
            FavoriteTeam(teamID: "b", addedAt: t),
            FavoriteTeam(teamID: "a", addedAt: t + 10),
            FavoriteTeam(teamID: "gone", addedAt: t, removedAt: t + 5),
        ]
        let remote = [
            FavoriteTeam(teamID: "a", addedAt: t + 10),
            FavoriteTeam(teamID: "d", addedAt: t + 30),
            FavoriteTeam(teamID: "c", addedAt: t + 20),
            FavoriteTeam(teamID: "b", addedAt: t),
        ]
        let merged = FavoritesCodec.merge(local, remote)
        #expect(merged.filter { !$0.isRemoved }.map(\.teamID) == ["b", "a", "c", "d"])
        #expect(merged.filter(\.isRemoved).map(\.teamID) == ["gone"])
        // Either way round, the same entries.
        #expect(FavoritesCodec.sameEntries(merged, FavoritesCodec.merge(remote, local)))
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

    // MARK: iCloud sync

    @MainActor
    @Test("A team added on one device appears on another")
    func addSyncs() throws {
        let cloud = MemoryCloudStore()
        let first3 = Array(seedIDs.prefix(3))
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: first3, isExistingInstall: true, reloadWidgets: {})
        let bDefaults = try scratchDefaults()
        var bReloads = 0
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: first3, isExistingInstall: true, reloadWidgets: { bReloads += 1 })
        #expect(b.teamIDs == first3)

        a.add(try #require(TeamCatalog.team(id: seedIDs[3])))
        receive(b)
        #expect(b.teamIDs == seedIDs)
        #expect(FavoritesCodec.storedIDs(in: bDefaults) == seedIDs)
        #expect(bReloads == 1)

        // Changes to other keys, and account changes, are not merges.
        b.cloudDidChange(reason: NSUbiquitousKeyValueStoreServerChange, changedKeys: ["something.else"])
        b.cloudDidChange(reason: NSUbiquitousKeyValueStoreAccountChange, changedKeys: [FavoritesCodec.key])
        #expect(bReloads == 1)
    }

    @MainActor
    @Test("A team removed on one device is removed on another, and its tombstone kept")
    func removeSyncs() throws {
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {})
        let bDefaults = try scratchDefaults()
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {})
        let removed = seedIDs[1]

        a.remove(removed)
        receive(b)
        #expect(!b.isFavorite(removed))
        #expect(b.teamIDs == a.teamIDs)
        #expect(FavoritesCodec.storedIDs(in: bDefaults) == a.teamIDs)

        // The removal travels as a tombstone, in iCloud and in B's own copy.
        let tombstone = try #require(cloud.entries.first { $0.teamID == removed })
        #expect(tombstone.isRemoved)
        let bEntries = try #require(FavoritesCodec.decodeEntries(bDefaults.data(forKey: FavoritesCodec.key)))
        #expect(bEntries.first { $0.teamID == removed }?.isRemoved == true)
    }

    @MainActor
    @Test("An add and a remove made apart resolve to the later one", arguments: [true, false])
    func concurrentAddAndRemove(removeIsLater: Bool) throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let x = seedIDs[3]
        let others = seedIDs.prefix(3).map { FavoriteTeam(teamID: $0, addedAt: FavoritesCodec.seedDate) }
        // Offline, the devices disagree: A has unfollowed X, B still follows it.
        let aDefaults = try scratchDefaults()
        FavoritesCodec.save(others + [FavoriteTeam(teamID: x, addedAt: t0 - 100, removedAt: t0)], defaults: aDefaults, cloud: nil)
        let bDefaults = try scratchDefaults()
        FavoritesCodec.save(others + [FavoriteTeam(teamID: x, addedAt: t0 - 100)], defaults: bDefaults, cloud: nil)

        let addedAt = removeIsLater ? t0 + 100 : t0 + 200
        let removedAt = removeIsLater ? t0 + 200 : t0 + 100
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: aDefaults, cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {}, now: { addedAt })
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {}, now: { removedAt })

        // A follows X again; B unfollows it. B's write reaches iCloud last.
        a.add(try #require(TeamCatalog.team(id: x)))
        b.remove(x)
        receive(a)
        receive(b)

        #expect(a.isFavorite(x) == !removeIsLater)
        #expect(b.isFavorite(x) == !removeIsLater)
        #expect(a.teamIDs == b.teamIDs)
        #expect(cloud.entries.first { $0.teamID == x }?.isRemoved == removeIsLater)
    }

    @MainActor
    @Test("Receiving a change never writes it back to iCloud")
    func receiveDoesNotEcho() throws {
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {})
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {})

        a.remove(seedIDs[0])
        a.move(from: IndexSet(integer: 2), to: 0)
        let sent = try #require(cloud.data(forKey: FavoritesCodec.key))
        let writes = cloud.writes

        receive(b)
        #expect(!b.isFavorite(seedIDs[0]))
        #expect(cloud.writes == writes)
        #expect(cloud.data(forKey: FavoritesCodec.key) == sent)

        // Nor does receiving it again, or coming back to the foreground.
        receive(b)
        b.synchronize()
        #expect(cloud.writes == writes)
    }

    @MainActor
    @Test("A fresh install's seed gives way to the iCloud copy when it arrives")
    func seedYieldsToCloud() throws {
        let aCloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: aCloud, seedIDs: seedIDs, isExistingInstall: true, reloadWidgets: {})
        a.remove(seedIDs[1])
        a.move(from: IndexSet(integer: 2), to: 0)

        // B's iCloud has not synced yet, so B seeds; then A's copy arrives.
        let bCloud = MemoryCloudStore()
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: bCloud, seedIDs: seedIDs, isExistingInstall: false, reloadWidgets: {})
        #expect(b.teamIDs == seedIDs)
        bCloud.values = aCloud.values
        receive(b, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        #expect(b.teamIDs == a.teamIDs)
    }
}
