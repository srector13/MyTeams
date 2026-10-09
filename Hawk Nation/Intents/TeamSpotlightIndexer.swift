//
//  TeamSpotlightIndexer.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import CoreSpotlight
import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "spotlight")

/// Spotlight lists the indexed teams (R-12): typing "Chiefs" offers the
/// team, and choosing it runs the app's intent for it. App-only: the
/// widget's copy of `TeamEntity` is not indexed. The attributes are the
/// defaults, drawn from `displayRepresentation`: the team's name, and its
/// league.
extension TeamEntity: IndexedEntity {}

/// Keeps Spotlight's teams in step with the favorites: indexes them on
/// start, then again on each change to the list, here or from iCloud, and
/// drops the teams unfollowed since the last run. Also refreshes the Siri
/// phrases' team slot (`MyTeamsShortcuts`), which offers the favorites.
///
/// Watches `FavoritesStore.teamIDs` from outside the store, as
/// `ScoreAlertEngine` watches the scoreboards, so the store itself is
/// unchanged.
@MainActor
final class TeamSpotlightIndexer {
    static let shared = TeamSpotlightIndexer()

    /// The `UserDefaults` key of the ids last indexed, so a team unfollowed
    /// while the app was closed is dropped on the next launch.
    static let indexedKey = "spotlightIndexedTeamIDs.v1"

    private let store: FavoritesStore
    private let defaults: UserDefaults
    private var isStarted = false
    /// The favorites last sent to the index, to skip changes that leave
    /// the list as it was (an alert setting, say).
    private var lastIDs: [TeamRef.ID]?
    /// The indexing under way; each waits for the one before.
    private var work: Task<Void, Never>?

    init(store: FavoritesStore = .shared, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// Indexes the favorites now and on every change. Only the first call
    /// does anything.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe()
    }

    /// Reads the favorites once and re-arms for their next change.
    private func observe() {
        let ids = withObservationTracking {
            store.teamIDs
        } onChange: {
            // Called before the change lands; read it on the next turn.
            Task { @MainActor in
                self.observe()
            }
        }
        guard ids != lastIDs else { return }
        lastIDs = ids
        let defaults = self.defaults
        let previous = work
        work = Task {
            await previous?.value
            let indexed = defaults.stringArray(forKey: Self.indexedKey) ?? []
            if let now = await Self.index(ids, replacing: indexed) {
                defaults.set(now, forKey: Self.indexedKey)
            }
            MyTeamsShortcuts.updateAppShortcutParameters()
        }
    }

    /// Indexes the teams `ids` name, and removes those of `indexed` no
    /// longer among them. The ids indexed, or `nil` if Spotlight refused.
    nonisolated static func index(_ ids: [TeamRef.ID], replacing indexed: [TeamRef.ID]) async -> [TeamRef.ID]? {
        var entities: [TeamEntity] = []
        for id in ids {
            if let team = await WidgetTeams.resolve(id) {
                entities.append(TeamEntity(team: team))
            }
        }
        let current = entities.map(\.id)
        let removed = removedIDs(indexed: indexed, current: current)
        let index = CSSearchableIndex.default()
        do {
            if !removed.isEmpty {
                try await index.deleteAppEntities(identifiedBy: removed, ofType: TeamEntity.self)
            }
            if !entities.isEmpty {
                try await index.indexAppEntities(entities)
            }
            return current
        } catch {
            logger.error("Could not index the favorites in Spotlight: \(error.localizedDescription)")
            return nil
        }
    }

    /// The ids indexed before and not now, in their indexed order.
    nonisolated static func removedIDs(indexed: [TeamRef.ID], current: [TeamRef.ID]) -> [TeamRef.ID] {
        let kept = Set(current)
        return indexed.filter { !kept.contains($0) }
    }
}
