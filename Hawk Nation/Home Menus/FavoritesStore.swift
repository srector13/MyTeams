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
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    /// Set in the shared defaults once the "Pick your teams" sheet has been
    /// dismissed.
    static let onboardingKey = "onboarding.completed.v2"

    /// The favorites, in display order.
    private(set) var favorites: [FavoriteTeam]

    /// Whether to open the "Pick your teams" sheet at launch: a fresh install
    /// that has never finished onboarding. Installs whose favorites were
    /// restored from iCloud, or that a previous build already ran on, skip it.
    var needsOnboarding: Bool

    private let defaults: UserDefaults
    private let cloud: (any FavoritesCloudStore)?
    private let reloadWidgets: @MainActor () -> Void

    init(
        defaults: UserDefaults = SharedPaths.defaults,
        cloud: (any FavoritesCloudStore)? = NSUbiquitousKeyValueStore.default,
        seedIDs: [TeamRef.ID] = FavoriteTeams.seedIDs,
        isExistingInstall: Bool = UserDefaults.standard.object(forKey: LogoStore.seededDefaultsKey) != nil,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.reloadWidgets = reloadWidgets
        let loaded = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: cloud, seedIDs: seedIDs)
        favorites = loaded.favorites
        needsOnboarding = loaded.source == .seeded
            && !isExistingInstall
            && !defaults.bool(forKey: Self.onboardingKey)
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
        favorites.append(FavoriteTeam(teamID: team.id))
        didChange()
        Task.detached(priority: .utility) {
            await LogoStore.promoteToFavorites(team)
        }
    }

    func remove(_ teamID: TeamRef.ID) {
        let before = favorites.count
        favorites.removeAll { $0.teamID == teamID }
        guard favorites.count != before else { return }
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
        FavoritesCodec.save(favorites, defaults: defaults, cloud: cloud)
        reloadWidgets()
    }
}
