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

    // MARK: First launch (t_afe5c297)

    @Test("An empty seed writes nothing, to either store")
    func emptySeedWritesNothing() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()

        let first = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: [])
        #expect(first.source == .empty)
        #expect(first.favorites.isEmpty)
        #expect(defaults.data(forKey: FavoritesCodec.key) == nil)
        // No empty list in iCloud to stand in for another device's.
        #expect(cloud.writes == 0)
        #expect(defaults.bool(forKey: FavoritesCodec.seededKey))
    }

    @MainActor
    @Test("A fresh install follows no teams")
    func freshInstallIsEmpty() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        var reloads = 0
        // The app's own seed: none passed.
        let store = FavoritesStore(defaults: defaults, cloud: cloud, reloadWidgets: { reloads += 1 })
        #expect(store.teamIDs.isEmpty)
        #expect(store.favorites.isEmpty)
        #expect(FavoritesCodec.storedIDs(in: defaults) == nil)
        #expect(cloud.writes == 0)
        #expect(reloads == 0)

        // Relaunched, still none, and still nothing written.
        let relaunched = FavoritesStore(defaults: defaults, cloud: cloud, reloadWidgets: {})
        #expect(relaunched.teamIDs.isEmpty)
        #expect(cloud.writes == 0)
    }

    @MainActor
    @Test("Stored favorites survive the store starting again with no seed")
    func storedFavoritesArePreserved() throws {
        // An install an earlier build seeded, then the reader edited.
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        _ = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        let seeded = FavoritesStore(defaults: defaults, cloud: cloud, reloadWidgets: {})
        seeded.remove(seedIDs[2])
        let kept = [seedIDs[0], seedIDs[1], seedIDs[3]]
        #expect(seeded.teamIDs == kept)
        let stored = defaults.data(forKey: FavoritesCodec.key)
        let writes = cloud.writes

        for _ in 0..<2 {
            let relaunched = FavoritesStore(defaults: defaults, cloud: cloud, reloadWidgets: {})
            #expect(relaunched.teamIDs == kept)
        }
        // Read, not rewritten.
        #expect(defaults.data(forKey: FavoritesCodec.key) == stored)
        #expect(cloud.writes == writes)

        // A list emptied by the reader stays empty, and is not reseeded.
        let emptied = try scratchDefaults()
        FavoritesCodec.save([], defaults: emptied, cloud: nil)
        #expect(FavoritesStore(defaults: emptied, cloud: nil, reloadWidgets: {}).teamIDs.isEmpty)
    }

    @MainActor
    @Test("A fresh install takes the reader's iCloud favorites, at launch or when they arrive")
    func freshInstallRestoresFromCloud() throws {
        let synced = [
            FavoriteTeam(teamID: "football/nfl:12", addedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            FavoriteTeam(teamID: "hockey/nhl:25", addedAt: Date(timeIntervalSince1970: 1_790_000_100)),
        ]

        // Already in iCloud at first launch.
        let cloud = MemoryCloudStore()
        cloud.set(FavoritesCodec.encode(synced), forKey: FavoritesCodec.key)
        let restored = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, reloadWidgets: {})
        #expect(restored.teamIDs == synced.map(\.teamID))

        // Arriving after first launch, with the initial sync.
        let lateCloud = MemoryCloudStore()
        let defaults = try scratchDefaults()
        var reloads = 0
        let store = FavoritesStore(defaults: defaults, cloud: lateCloud, reloadWidgets: { reloads += 1 })
        #expect(store.teamIDs.isEmpty)
        lateCloud.set(FavoritesCodec.encode(synced), forKey: FavoritesCodec.key)
        receive(store, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        #expect(store.teamIDs == synced.map(\.teamID))
        #expect(FavoritesCodec.storedIDs(in: defaults) == synced.map(\.teamID))
        #expect(reloads == 1)

        // Or, missed while the app ran, at the next launch: no empty list
        // was stored locally to shadow it.
        let missedCloud = MemoryCloudStore()
        let missedDefaults = try scratchDefaults()
        _ = FavoritesStore(defaults: missedDefaults, cloud: missedCloud, reloadWidgets: {})
        missedCloud.set(FavoritesCodec.encode(synced), forKey: FavoritesCodec.key)
        let next = FavoritesStore(defaults: missedDefaults, cloud: missedCloud, reloadWidgets: {})
        #expect(next.teamIDs == synced.map(\.teamID))
    }

    @MainActor
    @Test("With no favorites, the queries answer empty and the first follow is the only one")
    func zeroFavoritesQueries() async throws {
        let store = FavoritesStore(defaults: try scratchDefaults(), cloud: nil, reloadWidgets: {})
        #expect(await store.teamRefs(within: .seconds(1)) { _ in nil }.isEmpty)
        #expect(!store.isFavorite(seedIDs[0]))
        #expect(!store.notify(for: seedIDs[0]))
        // Editing nothing does nothing.
        store.remove(seedIDs[0])
        store.setNotify(false, for: seedIDs[0])
        #expect(store.teamIDs.isEmpty)

        store.add(try #require(TeamCatalog.team(id: seedIDs[1])))
        #expect(store.teamIDs == [seedIDs[1]])
    }

    @MainActor
    @Test("Home with no favorites selects nothing and drops a widget link")
    func homeRoutingWithNoFavorites() {
        let resolved = HomeRouting.favoritesResolved(HomeRouting.State(selection: ""), teams: [])
        #expect(resolved.selection == "")

        // The last team unfollowed: the selection clears.
        let unfollowed = HomeRouting.favoritesResolved(HomeRouting.State(selection: seedIDs[0]), teams: [])
        #expect(unfollowed.selection == "")

        // A link to a team no longer followed is dropped, not left pending.
        let linked = HomeRouting.linkChanged(
            HomeRouting.State(selection: "", pendingLink: seedIDs[0]),
            teams: [],
            favoriteIDs: []
        )
        #expect(linked.pendingLink == nil)
        #expect(linked.selection == "")
        #expect(HomeTabs.barCount(teamCount: 0, barCapacity: HomeTabs.compactCapacity) == 0)
    }

    #if DEBUG
    @MainActor
    @Test("A UI-test launch names its favorites, or none")
    func launchFavorites() {
        #expect(FavoritesStore.launchFavoriteIDs(environment: [:]) == nil)
        #expect(FavoritesStore.launchFavoriteIDs(environment: ["MYTEAMS_FAVORITES": "none"]) == [])
        #expect(FavoritesStore.launchFavoriteIDs(environment: ["MYTEAMS_FAVORITES": ""]) == [])
        #expect(
            FavoritesStore.launchFavoriteIDs(environment: ["MYTEAMS_FAVORITES": "football/nfl:12, baseball/mlb:7,bogus"])
                == ["football/nfl:12", "baseball/mlb:7"]
        )
    }
    #endif

    // MARK: iCloud sync

    @MainActor
    @Test("A team added on one device appears on another")
    func addSyncs() throws {
        let cloud = MemoryCloudStore()
        let first3 = Array(seedIDs.prefix(3))
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: first3, reloadWidgets: {})
        let bDefaults = try scratchDefaults()
        var bReloads = 0
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: first3, reloadWidgets: { bReloads += 1 })
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
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        let bDefaults = try scratchDefaults()
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
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
        let a = FavoritesStore(defaults: aDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { addedAt })
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { removedAt })

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
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})

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
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: aCloud, seedIDs: seedIDs, reloadWidgets: {})
        a.remove(seedIDs[1])
        a.move(from: IndexSet(integer: 2), to: 0)

        // B's iCloud has not synced yet, so B seeds; then A's copy arrives.
        let bCloud = MemoryCloudStore()
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: bCloud, seedIDs: seedIDs, reloadWidgets: {})
        #expect(b.teamIDs == seedIDs)
        bCloud.values = aCloud.values
        receive(b, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        #expect(b.teamIDs == a.teamIDs)
    }

    // MARK: Alerts setting

    @Test("The alerts setting round-trips through JSON, and older lists read as never set")
    func notifyRoundTrip() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            FavoriteTeam(teamID: "football/nfl:12", addedAt: t, notify: false, notifyChangedAt: t + 60),
            FavoriteTeam(teamID: "baseball/mlb:7", addedAt: t),
        ]
        let data = try #require(FavoritesCodec.encode(entries))
        let decoded = try #require(FavoritesCodec.decodeEntries(data))
        #expect(decoded == entries)
        #expect(decoded[0].notify == false)
        #expect(decoded[0].notifyChangedAt == t + 60)
        #expect(decoded[0].notifySetAt == t + 60)
        // Never set: the follow's default, as of the follow.
        #expect(decoded[1].notifyChangedAt == nil)
        #expect(decoded[1].notifySetAt == t)

        // The key is left out while unset, so builds that predate it read
        // the same JSON as before.
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stored = try #require(object["favorites"] as? [[String: Any]])
        #expect(stored[0]["notifyChangedAt"] != nil)
        #expect(stored[1]["notifyChangedAt"] == nil)
    }

    @MainActor
    @Test("Turning alerts off persists, mirrors to iCloud and survives a relaunch")
    func setNotifyPersists() throws {
        let defaults = try scratchDefaults()
        let cloud = MemoryCloudStore()
        var reloads = 0
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = FavoritesStore(
            defaults: defaults,
            cloud: cloud,
            seedIDs: seedIDs,
            reloadWidgets: { reloads += 1 },
            now: { now }
        )
        let team = seedIDs[1]
        #expect(store.notify(for: team))

        store.setNotify(false, for: team)
        #expect(!store.notify(for: team))
        #expect(store.favorites.first { $0.teamID == team }?.notifyChangedAt == now)
        #expect(reloads == 1)
        #expect(FavoritesCodec.decode(defaults.data(forKey: FavoritesCodec.key))?.first { $0.teamID == team }?.notify == false)
        #expect(cloud.entries.first { $0.teamID == team }?.notify == false)
        // Order and the other teams are untouched.
        #expect(store.teamIDs == seedIDs)
        let others = store.favorites.filter { $0.teamID != team }
        #expect(others.allSatisfy { $0.notify })

        // Setting it the way it already is, or for a team not followed, is
        // not an edit.
        let writes = cloud.writes
        store.setNotify(false, for: team)
        store.setNotify(false, for: "football/nfl:99")
        #expect(reloads == 1)
        #expect(cloud.writes == writes)
        #expect(!store.notify(for: "football/nfl:99"))

        let relaunched = FavoritesStore(defaults: defaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        #expect(!relaunched.notify(for: team))
        #expect(relaunched.notify(for: seedIDs[0]))

        store.setNotify(true, for: team)
        #expect(store.notify(for: team))
        #expect(cloud.entries.first { $0.teamID == team }?.notify == true)
    }

    @MainActor
    @Test("An alerts setting is stamped after the follow, even with the clock behind")
    func setNotifyAfterFollow() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let store = FavoritesStore(defaults: try scratchDefaults(), cloud: nil, seedIDs: [], reloadWidgets: {}, now: { t })
        store.add(try #require(TeamCatalog.team(id: seedIDs[1])))
        store.setNotify(false, for: seedIDs[1])
        let entry = try #require(store.favorites.first)
        #expect(entry.notifySetAt > entry.addedAt)
    }

    @MainActor
    @Test("Alerts turned off on one device stay off on another, and are not undone")
    func notifySyncs() throws {
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        let bDefaults = try scratchDefaults()
        var bReloads = 0
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: { bReloads += 1 })
        let team = seedIDs[2]

        a.setNotify(false, for: team)
        receive(b)
        #expect(!b.notify(for: team))
        #expect(bReloads == 1)
        #expect(FavoritesCodec.decode(bDefaults.data(forKey: FavoritesCodec.key))?.first { $0.teamID == team }?.notify == false)

        // B's seed copy, still on, never wins it back.
        b.synchronize()
        receive(a)
        a.synchronize()
        #expect(!a.notify(for: team))
        #expect(!b.notify(for: team))
        #expect(cloud.entries.first { $0.teamID == team }?.notify == false)
    }

    @MainActor
    @Test("Alerts set on two devices apart resolve to the later setting", arguments: [true, false])
    func concurrentNotify(offIsLater: Bool) throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let x = seedIDs[3]
        let offAt = offIsLater ? t0 + 200 : t0 + 100
        let onAt = offIsLater ? t0 + 100 : t0 + 200
        // Both start with X's alerts off, set long ago.
        let start = seedIDs.map {
            FavoriteTeam(teamID: $0, addedAt: FavoritesCodec.seedDate, notify: $0 != x, notifyChangedAt: $0 == x ? t0 : nil)
        }
        let aDefaults = try scratchDefaults()
        FavoritesCodec.save(start, defaults: aDefaults, cloud: nil)
        let bDefaults = try scratchDefaults()
        FavoritesCodec.save(start, defaults: bDefaults, cloud: nil)
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: aDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { onAt })
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { offAt })

        // Offline, A turns X's alerts on; B turns them on and off again.
        // B's write reaches iCloud last.
        a.setNotify(true, for: x)
        b.setNotify(true, for: x)
        b.setNotify(false, for: x)
        receive(a)
        receive(b)

        #expect(a.notify(for: x) == !offIsLater)
        #expect(b.notify(for: x) == !offIsLater)
        #expect(cloud.entries.first { $0.teamID == x }?.notify == !offIsLater)
    }

    @Test("Following a team again resets its alerts, whatever an older copy says")
    func refollowResetsNotify() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let old = FavoriteTeam(teamID: "x", addedAt: t, notify: false, notifyChangedAt: t + 10)
        let refollowed = FavoriteTeam(teamID: "x", addedAt: t + 30)
        for merged in [FavoritesCodec.merge([refollowed], [old]), FavoritesCodec.merge([old], [refollowed])] {
            #expect(merged == [refollowed])
        }
    }

    @Test("An alerts setting never brings back a team removed on another device", arguments: [true, false])
    func notifyEditKeepsRemoval(removalIsLater: Bool) throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let removedAt = removalIsLater ? t + 200 : t + 100
        let setAt = removalIsLater ? t + 100 : t + 200
        let edited = FavoriteTeam(teamID: "x", addedAt: t, notify: false, notifyChangedAt: setAt)
        let removed = FavoriteTeam(teamID: "x", addedAt: t, removedAt: removedAt)
        for merged in [FavoritesCodec.merge([edited], [removed]), FavoritesCodec.merge([removed], [edited])] {
            let entry = try #require(merged.first)
            #expect(merged.count == 1)
            #expect(entry.isRemoved)
            #expect(entry.removedAt == removedAt)
            // The tombstone carries the setting, made after the follow.
            #expect(!entry.notify)
            #expect(entry.notifyChangedAt == setAt)
        }
    }

    // MARK: Unresolved favorites (A-4)

    @MainActor
    @Test("A favorite the catalog misses the deadline for stays, as a placeholder, and a link to it still lands")
    func unresolvedFavoriteKept() async throws {
        let store = FavoritesStore(defaults: try scratchDefaults(), cloud: nil, seedIDs: [seedIDs[1], blues], reloadWidgets: {})
        let teams = await store.teamRefs(within: .milliseconds(20)) { _ in
            try? await Task.sleep(for: .seconds(5))
            return nil
        }
        #expect(teams.map(\.id) == [seedIDs[1], blues])
        let placeholder = try #require(teams.last)
        #expect(placeholder == TeamRef.placeholder(id: blues))
        #expect(placeholder.league == .nhl)
        #expect(placeholder.espnID == "19")
        #expect(placeholder.logoURL == nil)

        // Home's routing: a link held while the favorites resolved lands.
        let routed = HomeRouting.favoritesResolved(
            HomeRouting.State(selection: seedIDs[1], pendingLink: blues),
            teams: teams.map(\.id)
        )
        #expect(routed == HomeRouting.State(selection: blues, pendingLink: nil))
    }

    // Not timed by the wall clock: hosted tests share the main actor and the
    // thread pool with the app's launch and with each other, which on CI
    // held a 50 ms answer back for over nine seconds. The lookup instead
    // waits on a gate opened only after the answer: were the deadline not
    // to hold, `teamRefs` would wait on the gate for good, and the time
    // limit fail the test.
    @MainActor
    @Test("The deadline holds even when the lookup ignores cancellation, and the late answer is announced", .timeLimit(.minutes(1)))
    func lateLookupResolves() async throws {
        let store = FavoritesStore(defaults: try scratchDefaults(), cloud: nil, seedIDs: [blues], reloadWidgets: {})
        let key = store.resolutionKey
        let gate = Gate()
        // As the catalog's shared load does: an unstructured task's value,
        // which cancelling the waiter does not cut short.
        let slowLookup: @Sendable (TeamRef.ID) async -> TeamRef? = { id in
            await Task {
                await gate.wait()
                return resolvedTeam(id)
            }.value
        }

        let placeholder = try #require(TeamRef.placeholder(id: blues))

        let first = await store.teamRefs(within: .milliseconds(50), lookup: slowLookup)
        #expect(first == [placeholder])
        #expect(store.lateResolutions == 0)
        #expect(store.resolutionKey == key)

        // The lookup lands: the key changes, so views ask again.
        await gate.open()
        await waitUntil { store.lateResolutions > 0 }
        #expect(store.lateResolutions == 1)
        #expect(store.resolutionKey != key)
        let second = await store.teamRefs(within: .seconds(5)) { resolvedTeam($0) }
        #expect(second.map(\.displayName) == ["St. Louis Blues"])
    }

    @MainActor
    @Test("A late lookup for a team unfollowed meanwhile changes nothing")
    func lateLookupForUnfollowedTeam() async throws {
        let store = FavoritesStore(defaults: try scratchDefaults(), cloud: nil, seedIDs: [blues], reloadWidgets: {})
        _ = await store.teamRefs(within: .milliseconds(20)) { id in
            try? await Task.sleep(for: .milliseconds(200))
            return resolvedTeam(id)
        }
        store.remove(blues)
        try await Task.sleep(for: .milliseconds(600))
        #expect(store.lateResolutions == 0)
    }

    // MARK: Order sync (A-8)

    @Test("The order's stamp round-trips, and lists without one read as never reordered")
    func orderStampRoundTrip() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [FavoriteTeam(teamID: "football/nfl:12", addedAt: t)]
        let stamped = try #require(FavoritesCodec.encode(entries, orderChangedAt: t + 60))
        #expect(FavoritesCodec.decodeOrderChangedAt(stamped) == t + 60)
        #expect(FavoritesCodec.decodeEntries(stamped) == entries)

        let unstamped = try #require(FavoritesCodec.encode(entries))
        #expect(FavoritesCodec.decodeOrderChangedAt(unstamped) == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: unstamped) as? [String: Any])
        #expect(object["orderChangedAt"] == nil)
        #expect(FavoritesCodec.decodeOrderChangedAt(nil) == nil)
    }

    @Test("Only the followed teams' order makes two lists differ")
    func sameListIsOrdered() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a = FavoriteTeam(teamID: "a", addedAt: t)
        let b = FavoriteTeam(teamID: "b", addedAt: t)
        let gone = FavoriteTeam(teamID: "gone", addedAt: t, removedAt: t + 1)
        let gone2 = FavoriteTeam(teamID: "gone2", addedAt: t, removedAt: t + 1)
        #expect(FavoritesCodec.sameEntries([a, b], [b, a]))
        #expect(!FavoritesCodec.sameList([a, b], [b, a]))
        #expect(FavoritesCodec.sameList([a, b, gone, gone2], [a, b, gone2, gone]))
    }

    @MainActor
    @Test("A reorder on one device reaches another, and is not echoed back")
    func reorderSyncs() throws {
        let cloud = MemoryCloudStore()
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { t })
        let bDefaults = try scratchDefaults()
        var bReloads = 0
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: { bReloads += 1 })

        a.move(from: IndexSet(integer: 3), to: 0)
        #expect(a.teamIDs.first == seedIDs[3])
        #expect(FavoritesCodec.decodeOrderChangedAt(cloud.data(forKey: FavoritesCodec.key)) == t)
        let writes = cloud.writes

        receive(b)
        #expect(b.teamIDs == a.teamIDs)
        #expect(FavoritesCodec.storedIDs(in: bDefaults) == a.teamIDs)
        #expect(FavoritesCodec.decodeOrderChangedAt(bDefaults.data(forKey: FavoritesCodec.key)) == t)
        #expect(bReloads == 1)
        #expect(cloud.writes == writes)

        // Nor again, or on coming back to the foreground.
        receive(b)
        b.synchronize()
        a.synchronize()
        #expect(cloud.writes == writes)
        #expect(bReloads == 1)
    }

    @MainActor
    @Test("Reorders made apart resolve to the later one on both devices", arguments: [true, false])
    func concurrentReorders(aIsLater: Bool) throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { aIsLater ? t0 + 200 : t0 + 100 })
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { aIsLater ? t0 + 100 : t0 + 200 })

        // Offline, A moves the last team to the front, B the first to the
        // back. B's write reaches iCloud last.
        a.move(from: IndexSet(integer: 3), to: 0)
        b.move(from: IndexSet(integer: 0), to: 4)
        let aOrder = a.teamIDs
        let bOrder = b.teamIDs
        #expect(aOrder != bOrder)
        receive(a)
        receive(b)

        let winner = aIsLater ? aOrder : bOrder
        #expect(a.teamIDs == winner)
        #expect(b.teamIDs == winner)
        #expect(FavoritesCodec.decode(cloud.data(forKey: FavoritesCodec.key))?.map(\.teamID) == winner)
    }

    @MainActor
    @Test("A reorder is stamped after the order it replaces, even with the clock behind")
    func reorderStampedAfterAdoptedOrder() throws {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let cloud = MemoryCloudStore()
        let a = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { t + 500 })
        let b = FavoritesStore(defaults: try scratchDefaults(), cloud: cloud, seedIDs: seedIDs, reloadWidgets: {}, now: { t })
        a.move(from: IndexSet(integer: 3), to: 0)
        receive(b)

        // B's clock is behind A's, yet B's later reorder still wins.
        b.move(from: IndexSet(integer: 0), to: 4)
        receive(a)
        #expect(a.teamIDs == b.teamIDs)
        #expect(a.teamIDs.last == seedIDs[3])
    }

    @MainActor
    @Test("Lists never reordered keep each device's own order, without writing back and forth")
    func unstampedOrdersStayPut() throws {
        let start = seedIDs.map { FavoriteTeam(teamID: $0, addedAt: FavoritesCodec.seedDate) }
        let aDefaults = try scratchDefaults()
        FavoritesCodec.save(start, defaults: aDefaults, cloud: nil)
        let bDefaults = try scratchDefaults()
        FavoritesCodec.save(start.reversed(), defaults: bDefaults, cloud: nil)
        let cloud = MemoryCloudStore()
        cloud.set(FavoritesCodec.encode(start), forKey: FavoritesCodec.key)

        let a = FavoritesStore(defaults: aDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        let b = FavoritesStore(defaults: bDefaults, cloud: cloud, seedIDs: seedIDs, reloadWidgets: {})
        let writes = cloud.writes
        receive(a)
        receive(b)
        #expect(a.teamIDs == seedIDs)
        #expect(b.teamIDs == seedIDs.reversed())
        #expect(cloud.writes == writes)
    }
}

// MARK: - Helpers for unresolved favorites

/// A favorite the bundled catalog does not know.
private let blues = "hockey/nhl:19"

/// `id` as the catalog would resolve it once loaded.
private func resolvedTeam(_ id: TeamRef.ID) -> TeamRef? {
    guard var team = TeamRef.placeholder(id: id) else { return nil }
    team.displayName = "St. Louis Blues"
    team.shortName = "Blues"
    team.abbreviation = "STL"
    team.colorHex = "002F87"
    return team
}

/// Holds lookups back until opened, then lets every one through.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// Polls `condition` for up to thirty seconds: generous, as a busy CI
/// simulator can hold the main actor for seconds at a time.
@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<3000 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
