//
//  WidgetScoreboardWriter.swift
//  myTeams
//
//  Created by Stephen Rector on 10/5/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import WidgetKit

/// Writes the favorites' games under way or just finished to the App Group
/// for the widget (`WidgetScoreboardSnapshot`, C-5).
///
/// Watches `LeagueScoreboardCenter.games` as `ScoreAlertEngine` does, so it
/// writes on the center's own poll cadence — once a minute per league with a
/// favorite's game in the live window, while the app is open — and costs no
/// requests of its own. Each write restamps the snapshots, keeping them
/// fresh for the widget; the widget's timelines are reloaded only when a
/// score or state actually changes.
@MainActor
final class WidgetScoreboardWriter {
    static let shared = WidgetScoreboardWriter()

    private let center: LeagueScoreboardCenter
    private let favorites: @MainActor () -> [FavoriteTeam]
    private let now: @MainActor () -> Date
    private let defaults: UserDefaults
    private let reloadWidgets: @MainActor () -> Void

    /// The last snapshots written, unstamped, to tell a change from a poll
    /// that found the same scores.
    private var lastWritten: [WidgetScoreboardSnapshot] = []
    private var isStarted = false

    init(
        center: LeagueScoreboardCenter = .shared,
        favorites: @escaping @MainActor () -> [FavoriteTeam] = { FavoritesStore.shared.favorites },
        now: @escaping @MainActor () -> Date = { Date() },
        defaults: UserDefaults = SharedPaths.defaults,
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.center = center
        self.favorites = favorites
        self.now = now
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets
    }

    /// Begins watching the scoreboards. Calling it again does nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe()
    }

    /// Reads the games once and re-arms for their next change.
    private func observe() {
        let games = withObservationTracking {
            center.games
        } onChange: {
            // Called before the change lands; read it on the next turn.
            Task { @MainActor in
                self.observe()
            }
        }
        update(games)
    }

    private func update(_ games: [LeagueID: [ScoreboardGame]]) {
        // Nothing polled yet (a fresh launch): keep what an earlier session
        // wrote, which goes stale on its own.
        guard !games.isEmpty else { return }
        let stamp = now()
        let snapshots = Self.snapshots(in: games, favoriteIDs: favorites().map(\.teamID), updated: stamp)
        WidgetScoreboardCodec.write(snapshots, to: defaults)

        let unstamped = snapshots.map { snapshot -> WidgetScoreboardSnapshot in
            var snapshot = snapshot
            snapshot.updated = .distantPast
            return snapshot
        }
        if unstamped != lastWritten {
            lastWritten = unstamped
            reloadWidgets()
        }
    }

    /// Every favorite's game under way or played out on `games`, in its
    /// league and its cups, stamped `updated`. A game two favorites play is
    /// written once for each, since a widget follows one team.
    nonisolated static func snapshots(
        in games: [LeagueID: [ScoreboardGame]],
        favoriteIDs: [TeamRef.ID],
        updated: Date
    ) -> [WidgetScoreboardSnapshot] {
        var result: [WidgetScoreboardSnapshot] = []
        for teamID in favoriteIDs {
            guard let team = TeamRef.parse(id: teamID) else { continue }
            let competitions = [team.league] + team.league.descriptor.cupCompetitions
            for competition in competitions {
                for game in games[competition] ?? []
                where game.competitors.contains(where: { $0.teamID == team.espnID }) {
                    if let snapshot = snapshot(of: game, league: competition, teamID: teamID, updated: updated) {
                        result.append(snapshot)
                    }
                }
            }
        }
        return result
    }

    /// A two-team game under way or played out, as the widget reads it. A
    /// game not started, or called off (`"post"` without `completed`), has
    /// nothing to show over the schedule and gives `nil`.
    nonisolated static func snapshot(
        of game: ScoreboardGame,
        league: LeagueID,
        teamID: TeamRef.ID,
        updated: Date
    ) -> WidgetScoreboardSnapshot? {
        guard game.competitors.count == 2,
              let home = game.competitors.first(where: { $0.homeAway == "home" }),
              let away = game.competitors.first(where: { $0.homeAway == "away" })
        else { return nil }

        let state: WidgetScoreboardSnapshot.State
        if game.state == "in" {
            state = .inProgress
        } else if game.state == "post" && game.completed {
            state = .final
        } else {
            return nil
        }

        return WidgetScoreboardSnapshot(
            gameID: game.gameID,
            league: league.path,
            teamID: teamID,
            homeTeamID: home.teamID,
            awayTeamID: away.teamID,
            homeName: game.teamNames[home.teamID] ?? "Home",
            awayName: game.teamNames[away.teamID] ?? "Away",
            homeScore: home.score ?? 0,
            awayScore: away.score ?? 0,
            state: state,
            clock: game.clock,
            period: game.period,
            gameDate: game.startDate,
            updated: updated
        )
    }
}
