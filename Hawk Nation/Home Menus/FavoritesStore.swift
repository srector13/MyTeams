//
//  FavoritesStore.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
import WidgetKit

/// The teams the reader follows, in the order the crest bar shows them.
///
/// Persisted by `FavoritesCodec` in the App Group's `UserDefaults` (which the
/// widget reads) and mirrored to iCloud key-value storage. Every change
/// reloads the widgets' timelines; adding a team also moves its crests into
/// `LogoStore`'s favorites directory, where the OS cannot purge them.
///
/// Changes other devices make arrive through
/// `NSUbiquitousKeyValueStore.didChangeExternallyNotification` and are merged
/// in with `FavoritesCodec.merge`: the union of both lists, with each team's
/// last add or remove winning. Removed teams are kept as tombstones so their
/// removal syncs too.
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    /// Set in the shared defaults once the "Pick your teams" sheet has been
    /// dismissed.
    static let onboardingKey = "onboarding.completed.v2"

    /// The favorites, in display order.
    private(set) var favorites: [FavoriteTeam]

    /// Unfollowed teams, stored alongside `favorites` so the removals reach
    /// other devices.
    private var tombstones: [FavoriteTeam]

    /// Whether `favorites` is this install's seed, not yet edited. The first
    /// iCloud copy to arrive then sets the order, as a restore would have.
    private var seedIsProvisional: Bool

    /// Whether to open the "Pick your teams" sheet at launch: a fresh install
    /// that has never finished onboarding. Installs whose favorites were
    /// restored from iCloud, or that a previous build already ran on, skip it.
    var needsOnboarding: Bool

    private let defaults: UserDefaults
    private let cloud: (any FavoritesCloudStore)?
    private let reloadWidgets: @MainActor () -> Void
    private let now: @MainActor () -> Date

    init(
        defaults: UserDefaults = SharedPaths.defaults,
        cloud: (any FavoritesCloudStore)? = NSUbiquitousKeyValueStore.default,
        seedIDs: [TeamRef.ID] = FavoriteTeams.seedIDs,
        isExistingInstall: Bool = UserDefaults.standard.object(forKey: LogoStore.seededDefaultsKey) != nil,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.reloadWidgets = reloadWidgets
        self.now = now
        let loaded = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        favorites = loaded.favorites
        tombstones = FavoritesCodec.decodeEntries(defaults.data(forKey: FavoritesCodec.key))?.filter(\.isRemoved) ?? []
        seedIsProvisional = loaded.source == .seeded
        needsOnboarding = loaded.source == .seeded
            && !isExistingInstall
            && !defaults.bool(forKey: Self.onboardingKey)
        observeCloud()
        synchronize()
    }

    // MARK: Queries

    var teamIDs: [TeamRef.ID] { favorites.map(\.teamID) }

    func isFavorite(_ id: TeamRef.ID) -> Bool {
        favorites.contains { $0.teamID == id }
    }

    /// The favorites as teams, in order. Ids the catalog cannot resolve
    /// within a couple of seconds are left out rather than holding up the
    /// crest bar.
    func teamRefs() async -> [TeamRef] {
        let ids = teamIDs
        let resolved = await withTaskGroup(of: (Int, TeamRef?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    (index, await FavoritesStore.resolve(id, within: .seconds(2)))
                }
            }
            var teams: [Int: TeamRef] = [:]
            for await (index, team) in group {
                teams[index] = team
            }
            return teams
        }
        return ids.indices.compactMap { resolved[$0] }
    }

    /// One team from the catalog, or `nil` after `deadline`. The seed teams
    /// resolve from the bundle without waiting.
    nonisolated static func resolve(_ id: TeamRef.ID, within deadline: Duration) async -> TeamRef? {
        if let seed = TeamCatalog.team(id: id) {
            return await RemoteTeamCatalog.shared.refreshedSeed(seed)
        }
        return await withTaskGroup(of: TeamRef?.self) { group in
            group.addTask { await RemoteTeamCatalog.shared.team(id: id) }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: Editing

    /// Follows the team if it is not followed, and unfollows it if it is.
    func toggle(_ team: TeamRef) {
        if isFavorite(team.id) {
            remove(team.id)
        } else {
            add(team)
        }
    }

    /// Appends the team to the favorites. Does nothing if already followed.
    func add(_ team: TeamRef) {
        guard !isFavorite(team.id) else { return }
        // Stamped after any earlier removal, whole seconds included (the JSON
        // keeps no fractions), so the add wins the merge on other devices.
        let removedAt = tombstones.first { $0.teamID == team.id }?.removedAt
        tombstones.removeAll { $0.teamID == team.id }
        let addedAt = max(now(), removedAt.map { $0 + 1 } ?? .distantPast)
        favorites.append(FavoriteTeam(teamID: team.id, addedAt: addedAt))
        didChange()
        Task.detached(priority: .utility) {
            await LogoStore.promoteToFavorites(team)
        }
    }

    /// Unfollows the team, leaving a tombstone for other devices.
    func remove(_ teamID: TeamRef.ID) {
        guard let index = favorites.firstIndex(where: { $0.teamID == teamID }) else { return }
        var removed = favorites.remove(at: index)
        // Never before `addedAt`, which another device's clock may have set.
        removed.removedAt = max(now(), removed.addedAt)
        tombstones.removeAll { $0.teamID == teamID }
        tombstones.append(removed)
        didChange()
    }

    /// Reorders the favorites, as `List`'s `.onMove` reports it.
    func move(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        didChange()
    }

    /// Records that the onboarding sheet was dismissed.
    func completeOnboarding() {
        needsOnboarding = false
        defaults.set(true, forKey: Self.onboardingKey)
    }

    private func didChange() {
        seedIsProvisional = false
        FavoritesCodec.save(favorites + tombstones, defaults: defaults, cloud: cloud)
        reloadWidgets()
    }

    // MARK: iCloud

    /// Asks iCloud for changes, then merges in the copy it already holds.
    /// Called at launch and each time the app comes to the foreground.
    func synchronize() {
        guard let cloud else { return }
        cloud.synchronize()
        mergeFromCloud()
    }

    /// Handles `didChangeExternallyNotification`: merges iCloud's copy when
    /// the server sent new favorites. Account changes and quota violations
    /// are left alone.
    func cloudDidChange(reason: Int?, changedKeys: [String]) {
        guard reason == NSUbiquitousKeyValueStoreServerChange
                || reason == NSUbiquitousKeyValueStoreInitialSyncChange,
              changedKeys.contains(FavoritesCodec.key)
        else { return }
        mergeFromCloud()
    }

    private func observeCloud() {
        guard let cloud else { return }
        // Never removed: the app's store lives as long as the process, and
        // the handler does nothing once a test's store is gone.
        _ = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated {
                self?.cloudDidChange(reason: reason, changedKeys: keys)
            }
        }
    }

    /// Merges iCloud's copy with the local one. The result is written to the
    /// shared defaults if it differs from them, and back to iCloud only if it
    /// differs from iCloud's copy, so receiving a change never echoes it.
    private func mergeFromCloud() {
        guard let cloud,
              let remote = FavoritesCodec.decodeEntries(cloud.data(forKey: FavoritesCodec.key))
        else { return }
        // The stored copy rather than `favorites`: its dates have been
        // through the same JSON as `remote`'s.
        let local = FavoritesCodec.decodeEntries(defaults.data(forKey: FavoritesCodec.key))
            ?? favorites + tombstones
        let merged = seedIsProvisional
            ? FavoritesCodec.merge(remote, local)
            : FavoritesCodec.merge(local, remote)
        let followed = merged.filter { !$0.isRemoved }
        // The tombstones' order means nothing; the followed teams' does.
        if followed != local.filter({ !$0.isRemoved }) || !FavoritesCodec.sameEntries(merged, local) {
            FavoritesCodec.save(merged, defaults: defaults, cloud: nil)
            favorites = followed
            tombstones = merged.filter(\.isRemoved)
            seedIsProvisional = false
            reloadWidgets()
        }
        if !FavoritesCodec.sameEntries(merged, remote) {
            cloud.set(FavoritesCodec.encode(merged), forKey: FavoritesCodec.key)
        }
    }
}
