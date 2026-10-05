//
//  FavoritesStoreNotificationTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

// `FavoritesStore`'s iCloud observer, driven through the real
// `NotificationCenter.default` rather than by calling `cloudDidChange`:
// the `object:` filter, the main-queue hop, and the `userInfo` casts.

/// An in-memory stand-in for `NSUbiquitousKeyValueStore`; each instance is
/// its own notification sender.
private final class MemoryCloudStore: FavoritesCloudStore {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    func synchronize() -> Bool { true }
}

/// Counts a store's widget reloads — the sign it merged a change — and
/// reports each one as it happens.
@MainActor
private final class ReloadCounter {
    private(set) var count = 0
    let reloads: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (reloads, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func reload() {
        count += 1
        continuation.yield()
    }
}

/// Waits for the next reload. Runs on the caller's actor, so the
/// (non-Sendable) iterator never crosses one.
private func nextReload(
    from iterator: inout AsyncStream<Void>.Iterator,
    isolation: isolated (any Actor)? = #isolation
) async {
    _ = await iterator.next(isolation: isolation)
}

private func scratchDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "FavoritesStoreNotificationTests.\(UUID().uuidString)"))
}

private let seedIDs = [
    "basketball/mens-college-basketball:2305",
    "football/nfl:12",
    "baseball/mlb:7",
]

/// What another device wrote: the seed plus the Royals' division rival.
private let remoteIDs = seedIDs + ["baseball/mlb:5"]

/// Posts `didChangeExternallyNotification` as iCloud does: the reason and
/// keys as Foundation objects.
@MainActor
private func postCloudChange(
    from sender: AnyObject?,
    reason: Any? = NSNumber(value: NSUbiquitousKeyValueStoreServerChange),
    keys: Any? = [FavoritesCodec.key] as NSArray
) {
    var userInfo: [AnyHashable: Any] = [:]
    if let reason {
        userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] = reason
    }
    if let keys {
        userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] = keys
    }
    NotificationCenter.default.post(
        name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: sender,
        userInfo: userInfo
    )
}

@Suite("Favorites: iCloud change notifications", .serialized, .timeLimit(.minutes(1)))
struct FavoritesStoreNotificationTests {
    /// A store over its own cloud, whose cloud already holds another
    /// device's list, so any merge it makes changes its favorites.
    @MainActor
    private func makeStore(_ counter: ReloadCounter) throws -> (FavoritesStore, MemoryCloudStore) {
        let cloud = MemoryCloudStore()
        let store = FavoritesStore(
            defaults: try scratchDefaults(),
            cloud: cloud,
            seedIDs: seedIDs,
            reloadWidgets: { counter.reload() }
        )
        // Written after launch, as a change from elsewhere would be.
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let remote = remoteIDs.map { FavoriteTeam(teamID: $0, addedAt: seedIDs.contains($0) ? FavoritesCodec.seedDate : t) }
        cloud.set(FavoritesCodec.encode(remote), forKey: FavoritesCodec.key)
        return (store, cloud)
    }

    @Test("A server change posted by the store's cloud is merged in")
    @MainActor
    func serverChangeMerges() async throws {
        let counter = ReloadCounter()
        var reloads = counter.reloads.makeAsyncIterator()
        let (store, cloud) = try makeStore(counter)
        #expect(store.teamIDs == seedIDs)

        postCloudChange(from: cloud)
        await nextReload(from: &reloads)
        #expect(store.teamIDs == remoteIDs)
        #expect(counter.count == 1)
    }

    @Test("The initial sync is merged too; the userInfo casts take Swift values as well as Foundation's")
    @MainActor
    func initialSyncAndSwiftValues() async throws {
        let counter = ReloadCounter()
        var reloads = counter.reloads.makeAsyncIterator()
        let (store, cloud) = try makeStore(counter)

        postCloudChange(
            from: cloud,
            reason: NSUbiquitousKeyValueStoreInitialSyncChange,
            keys: ["something.else", FavoritesCodec.key]
        )
        await nextReload(from: &reloads)
        #expect(store.teamIDs == remoteIDs)
    }

    @Test("A notification from another sender, or from none, is ignored", arguments: [false, true])
    @MainActor
    func otherSenderIgnored(senderIsNil: Bool) async throws {
        let counter = ReloadCounter()
        let (store, _) = try makeStore(counter)
        let control = ReloadCounter()
        var controlReloads = control.reloads.makeAsyncIterator()
        let (controlStore, controlCloud) = try makeStore(control)

        // Another store's cloud, or no object at all.
        let stranger = MemoryCloudStore()
        postCloudChange(from: senderIsNil ? nil : stranger)
        // Then one the control store takes. Main-queue observers run in
        // posting order, so once it has merged, the first has been
        // dispatched — to no one.
        postCloudChange(from: controlCloud)
        await nextReload(from: &controlReloads)
        #expect(controlStore.teamIDs == remoteIDs)

        #expect(counter.count == 0)
        #expect(store.teamIDs == seedIDs)
    }

    @Test("Each store hears only its own cloud")
    @MainActor
    func storesAreIsolated() async throws {
        let first = ReloadCounter()
        var firstReloads = first.reloads.makeAsyncIterator()
        let (firstStore, firstCloud) = try makeStore(first)
        let second = ReloadCounter()
        var secondReloads = second.reloads.makeAsyncIterator()
        let (secondStore, secondCloud) = try makeStore(second)
        let control = ReloadCounter()
        var controlReloads = control.reloads.makeAsyncIterator()
        let (controlStore, controlCloud) = try makeStore(control)

        postCloudChange(from: firstCloud)
        await nextReload(from: &firstReloads)
        #expect(firstStore.teamIDs == remoteIDs)
        // Once the control store has merged a notification posted after
        // it, the first one has been dispatched: not to the second store.
        postCloudChange(from: controlCloud)
        await nextReload(from: &controlReloads)
        #expect(controlStore.teamIDs == remoteIDs)
        #expect(second.count == 0)
        #expect(secondStore.teamIDs == seedIDs)

        // Its own notification, it merges.
        postCloudChange(from: secondCloud)
        await nextReload(from: &secondReloads)
        #expect(secondStore.teamIDs == remoteIDs)
        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    @Test("Account changes, quota violations, other keys and malformed userInfo are left alone", arguments: IgnoredCloudChange.allCases)
    @MainActor
    func ignoredChanges(change: IgnoredCloudChange) async throws {
        let counter = ReloadCounter()
        let (store, cloud) = try makeStore(counter)
        let control = ReloadCounter()
        var controlReloads = control.reloads.makeAsyncIterator()
        let (controlStore, controlCloud) = try makeStore(control)

        let userInfo = change.userInfo
        postCloudChange(from: cloud, reason: userInfo.reason, keys: userInfo.keys)
        // Once the control store has merged a good notification posted
        // after it, the ignored one has been handled.
        postCloudChange(from: controlCloud)
        await nextReload(from: &controlReloads)
        #expect(controlStore.teamIDs == remoteIDs)

        #expect(counter.count == 0)
        #expect(store.teamIDs == seedIDs)
    }
}

/// `didChangeExternallyNotification` userInfo that must not merge.
enum IgnoredCloudChange: CaseIterable, Sendable {
    case accountChange
    case quotaViolation
    case otherKeysOnly
    case noReason
    case noKeys
    case reasonNotANumber
    case keysNotAnArray

    var userInfo: (reason: Any?, keys: Any?) {
        let server = NSNumber(value: NSUbiquitousKeyValueStoreServerChange)
        let favoritesKey = [FavoritesCodec.key] as NSArray
        switch self {
        case .accountChange: return (NSNumber(value: NSUbiquitousKeyValueStoreAccountChange), favoritesKey)
        case .quotaViolation: return (NSNumber(value: NSUbiquitousKeyValueStoreQuotaViolationChange), favoritesKey)
        case .otherKeysOnly: return (server, ["something.else"] as NSArray)
        case .noReason: return (nil, favoritesKey)
        case .noKeys: return (server, nil)
        case .reasonNotANumber: return ("server" as NSString, favoritesKey)
        case .keysNotAnArray: return (server, FavoritesCodec.key as NSString)
        }
    }
}
