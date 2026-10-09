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
/// removal syncs too. The order is stamped when the reader reorders, and the
/// newer order wins.
@MainActor
@Observable
final class FavoritesStore {
    static let shared: FavoritesStore = {
        #if DEBUG
        if let ids = launchFavoriteIDs(environment: ProcessInfo.processInfo.environment) {
            // A UI-test launch: its favorites, local only, so the run
            // neither reads nor writes iCloud.
            let preset = ids.map { FavoriteTeam(teamID: $0, addedAt: FavoritesCodec.seedDate) }
            FavoritesCodec.save(preset, defaults: SharedPaths.defaults, cloud: nil)
            return FavoritesStore(cloud: nil)
        }
        #endif
        return FavoritesStore()
    }()

    #if DEBUG
    /// The launch-environment key UI tests set to start from a known list:
    /// comma-separated `TeamRef.id`s, replacing whatever is stored. A value
    /// naming no team (`"none"`) starts with no favorites, as a fresh
    /// install does. Read only in Debug builds.
    static let launchFavoritesKey = "MYTEAMS_FAVORITES"

    /// The favorites a launch environment asks for, or `nil` to load the
    /// stored ones.
    static func launchFavoriteIDs(environment: [String: String]) -> [TeamRef.ID]? {
        guard let value = environment[launchFavoritesKey] else { return nil }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { TeamRef.parse(id: $0) != nil }
    }
    #endif

    /// The favorites, in display order.
    private(set) var favorites: [FavoriteTeam]

    /// Unfollowed teams, stored alongside `favorites` so the removals reach
    /// other devices.
    private var tombstones: [FavoriteTeam]

    /// When the reader last reordered `favorites`, here or on another
    /// device. `nil` until anyone has. The newer order wins a merge (A-8).
    private var orderChangedAt: Date?

    /// Whether `favorites` is this install's seed, not yet edited. The first
    /// iCloud copy to arrive then sets the order, as a restore would have.
    /// Only ever with a seed passed in: the app's is empty.
    private var seedIsProvisional: Bool

    /// Counts the favorites `teamRefs()` stood a placeholder in for that
    /// have since resolved. Views can key their lookup on it, alongside
    /// `teamIDs`, to swap the placeholder for the real team (A-4).
    private(set) var lateResolutions = 0

    /// Favorites whose lookup outlived `teamRefs()`'s deadline and is still
    /// running, so each is waited on once.
    @ObservationIgnored private var pendingLookups: Set<TeamRef.ID> = []

    private let defaults: UserDefaults
    private let cloud: (any FavoritesCloudStore)?
    private let reloadWidgets: @MainActor () -> Void
    private let now: @MainActor () -> Date

    init(
        defaults: UserDefaults = SharedPaths.defaults,
        cloud: (any FavoritesCloudStore)? = NSUbiquitousKeyValueStore.default,
        // None: a fresh install starts empty, on the home screen's "Add
        // Teams" (t_afe5c297). Tests pass some to start from a list.
        seedIDs: [TeamRef.ID] = [],
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
        orderChangedAt = FavoritesCodec.decodeOrderChangedAt(defaults.data(forKey: FavoritesCodec.key))
        seedIsProvisional = loaded.source == .seeded
        observeCloud()
        synchronize()
    }

    // MARK: Queries

    var teamIDs: [TeamRef.ID] { favorites.map(\.teamID) }

    /// What `teamRefs()` answers from: the favorites, and how many
    /// placeholders have resolved since. See `resolutionKey`.
    struct ResolutionKey: Equatable, Sendable {
        let teamIDs: [TeamRef.ID]
        let lateResolutions: Int
    }

    /// Changes whenever `teamRefs()` could answer differently: the favorites
    /// change, or a favorite it stood a placeholder in for resolves. A view
    /// keys its `.task(id:)` on it to swap placeholders for teams (A-4).
    var resolutionKey: ResolutionKey {
        ResolutionKey(teamIDs: teamIDs, lateResolutions: lateResolutions)
    }

    func isFavorite(_ id: TeamRef.ID) -> Bool {
        favorites.contains { $0.teamID == id }
    }

    /// The followed ids that name `team`'s club in any league: the same
    /// sport and ESPN id (`TeamSearch.clubGroups`). Bayern followed under
    /// the UCL counts when search lists Bayern under the Bundesliga.
    func followedClubIDs(of team: TeamRef) -> [TeamRef.ID] {
        teamIDs.filter { id in
            guard let parsed = TeamRef.parse(id: id) else { return false }
            return parsed.league.sport == team.league.sport && parsed.espnID == team.espnID
        }
    }

    /// The favorites as teams, in order. A favorite the catalog cannot
    /// resolve within a couple of seconds is not held up for, nor left out
    /// (A-4): it stands as `TeamRef.placeholder(id:)`, its sport's monogram,
    /// so its tab and the deep links to it still work. When its lookup
    /// lands, `lateResolutions` goes up.
    func teamRefs() async -> [TeamRef] {
        await teamRefs(within: .seconds(2)) { await RemoteTeamCatalog.shared.team(id: $0) }
    }

    /// `teamRefs()` with its deadline and catalog lookup given, for tests.
    func teamRefs(
        within deadline: Duration,
        lookup: @escaping @Sendable (TeamRef.ID) async -> TeamRef?
    ) async -> [TeamRef] {
        let ids = teamIDs
        let resolved = await withTaskGroup(of: (Int, TeamRef?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    (index, await FavoritesStore.resolve(id, within: deadline, lookup: lookup))
                }
            }
            var teams: [Int: TeamRef] = [:]
            for await (index, team) in group {
                teams[index] = team
            }
            return teams
        }
        return ids.indices.compactMap { index -> TeamRef? in
            if let team = resolved[index] { return team }
            awaitLateLookup(ids[index], lookup: lookup)
            return TeamRef.placeholder(id: ids[index])
        }
    }

    /// Waits out a lookup that missed `teamRefs()`'s deadline, and counts
    /// it in `lateResolutions` if it finds the team still followed.
    private func awaitLateLookup(_ id: TeamRef.ID, lookup: @escaping @Sendable (TeamRef.ID) async -> TeamRef?) {
        guard pendingLookups.insert(id).inserted else { return }
        Task {
            let team = await lookup(id)
            pendingLookups.remove(id)
            if team != nil, isFavorite(id) {
                lateResolutions += 1
            }
        }
    }

    /// One team from the catalog, or `nil` after `deadline`. The seed teams
    /// resolve from the bundle without waiting.
    ///
    /// Not a task group: a group waits for its losing child, and the
    /// catalog's lookup awaits a shared load that ignores cancellation, so
    /// a fetch in flight would hold the answer well past the deadline. The
    /// lookup carries on after `nil` is returned, and the catalog keeps
    /// what it loads.
    nonisolated static func resolve(
        _ id: TeamRef.ID,
        within deadline: Duration,
        lookup: @escaping @Sendable (TeamRef.ID) async -> TeamRef? = { await RemoteTeamCatalog.shared.team(id: $0) }
    ) async -> TeamRef? {
        if let seed = TeamCatalog.team(id: id) {
            return await RemoteTeamCatalog.shared.refreshedSeed(seed)
        }
        let (answers, continuation) = AsyncStream.makeStream(of: TeamRef?.self)
        let lookupTask = Task {
            continuation.yield(await lookup(id))
            continuation.finish()
        }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.yield(nil)
            continuation.finish()
        }
        defer {
            lookupTask.cancel()
            timer.cancel()
        }
        for await answer in answers {
            return answer
        }
        return nil
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

    /// Whether game alerts are wanted for a followed team.
    func notify(for teamID: TeamRef.ID) -> Bool {
        favorites.first { $0.teamID == teamID }?.notify ?? false
    }

    /// Turns game alerts on or off for a followed team. Does nothing for a
    /// team not followed, or already set that way.
    func setNotify(_ notify: Bool, for teamID: TeamRef.ID) {
        guard let index = favorites.firstIndex(where: { $0.teamID == teamID }),
              favorites[index].notify != notify
        else { return }
        favorites[index].notify = notify
        // A whole second past the follow at least (the JSON keeps no
        // fractions), so the setting outweighs the follow's default on other
        // devices.
        favorites[index].notifyChangedAt = max(now(), favorites[index].addedAt + 1)
        didChange()
    }

    /// The kinds of game alert a followed team sends (R-6): `nil` for the
    /// global kinds (`AlertPreferences`), or the team's own; `[]` for off,
    /// or a team not followed.
    func alertKinds(for teamID: TeamRef.ID) -> AlertMask? {
        guard let favorite = favorites.first(where: { $0.teamID == teamID }) else { return [] }
        return favorite.alertKinds
    }

    /// Sets the kinds of game alert a followed team sends: `nil` to follow
    /// the global kinds again, `[]` to turn its alerts off. Stamped and
    /// merged across devices as `setNotify` is. Does nothing for a team not
    /// followed, or already set that way.
    func setAlertKinds(_ kinds: AlertMask?, for teamID: TeamRef.ID) {
        guard let index = favorites.firstIndex(where: { $0.teamID == teamID }),
              favorites[index].alertKinds != kinds
        else { return }
        favorites[index].alertKinds = kinds
        favorites[index].notifyChangedAt = max(now(), favorites[index].addedAt + 1)
        didChange()
    }

    /// Reorders the favorites, as `List`'s `.onMove` reports it, and stamps
    /// the order so it reaches the reader's other devices (A-8).
    func move(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        // A whole second past the order it replaces at least (the JSON keeps
        // no fractions), so it wins on every device, however close behind.
        orderChangedAt = max(now(), orderChangedAt.map { $0 + 1 } ?? .distantPast)
        didChange()
    }

    private func didChange() {
        seedIsProvisional = false
        FavoritesCodec.save(favorites + tombstones, orderChangedAt: orderChangedAt, defaults: defaults, cloud: cloud)
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
    ///
    /// The order is the local one unless iCloud's was set later (or this is
    /// a provisional seed): then the reorder made on another device is
    /// adopted. Lists whose orders were never set keep their own (A-8).
    private func mergeFromCloud() {
        guard let cloud,
              let remoteData = cloud.data(forKey: FavoritesCodec.key),
              let remote = FavoritesCodec.decodeEntries(remoteData)
        else { return }
        // The stored copy rather than `favorites`: its dates have been
        // through the same JSON as `remote`'s.
        let localData = defaults.data(forKey: FavoritesCodec.key)
        let local = FavoritesCodec.decodeEntries(localData) ?? favorites + tombstones
        let localOrderAt = FavoritesCodec.decodeOrderChangedAt(localData)
        let remoteOrderAt = FavoritesCodec.decodeOrderChangedAt(remoteData)
        let remoteOrderIsNewer = (remoteOrderAt ?? .distantPast) > (localOrderAt ?? .distantPast)
        let merged = seedIsProvisional || remoteOrderIsNewer
            ? FavoritesCodec.merge(remote, local)
            : FavoritesCodec.merge(local, remote)
        let mergedOrderAt = remoteOrderIsNewer ? remoteOrderAt : localOrderAt
        // An order-only difference is a change too.
        if !FavoritesCodec.sameList(merged, local) || mergedOrderAt != localOrderAt {
            FavoritesCodec.save(merged, orderChangedAt: mergedOrderAt, defaults: defaults, cloud: nil)
            favorites = merged.filter { !$0.isRemoved }
            tombstones = merged.filter(\.isRemoved)
            orderChangedAt = mergedOrderAt
            seedIsProvisional = false
            reloadWidgets()
        }
        // Orders of the same age are each device's own, so only an order
        // set later than iCloud's is sent; anything else would echo back
        // and forth.
        if !FavoritesCodec.sameEntries(merged, remote) || mergedOrderAt != remoteOrderAt {
            cloud.set(FavoritesCodec.encode(merged, orderChangedAt: mergedOrderAt), forKey: FavoritesCodec.key)
        }
    }
}
