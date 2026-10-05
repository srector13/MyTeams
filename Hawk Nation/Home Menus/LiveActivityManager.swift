//
//  LiveActivityManager.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation
import Observation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "liveActivities")

/// Keeps a Live Activity on the Lock Screen and in the Dynamic Island for
/// each favorite's game under way.
///
/// Rides the same trigger as the score alerts (`ScoreAlertEngine`): each
/// change to `LeagueScoreboardCenter.games`. On each, the favorites' games
/// are read as activity content (`LiveActivityStateMapper`) and
/// `LiveActivityPlanner` decides what to start, update and end:
///
/// - a live game gets an activity, while the app is in the foreground (the
///   only time ActivityKit lets one start) and fewer than
///   `LiveActivityPlanner.maxActivities` are running;
/// - a running one is updated as the score, period or clock moves;
/// - the final (or a game called off) ends it, left on the Lock Screen for
///   `dismissalGrace` with the last score;
/// - a game gone from every board for `LiveActivityPlanner.offBoardTimeout`
///   ends it too, taken down after `offBoardDismissalGrace`.
///
/// Every favorite counts, those with alerts on (`FavoriteTeam.notify`)
/// first, so they win the places when more games are live than fit.
///
/// Foreground-driven only: with the app suspended, activities keep their
/// last content and turn stale after `staleAfter`. Push updates are P4-e.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// How long a finished game's activity stays on the Lock Screen.
    static let dismissalGrace: TimeInterval = 10 * 60
    /// How long an activity whose game left the boards
    /// (`LiveActivityAction.expire`) stays on the Lock Screen: briefly, as
    /// its last score is no longer current.
    static let offBoardDismissalGrace: TimeInterval = 60
    /// How long content stays good without an update. The center polls
    /// every minute while it runs; past this, the app has stopped.
    static let staleAfter: TimeInterval = 10 * 60

    private let center: LeagueScoreboardCenter
    private let favorites: @MainActor () -> [FavoriteTeam]
    private let isForeground: @MainActor () -> Bool
    private let now: @MainActor () -> Date

    /// The running activities, by game id.
    private var activities: [String: Activity<GameActivityAttributes>] = [:]
    /// What each running activity was last given, by game id.
    private var shown: [String: GameActivityState] = [:]
    /// Games whose activity ended, or that the reader dismissed; none is
    /// started again. Loaded from, and written through to, `retiredStore`,
    /// so a dismissed game stays dismissed across launches.
    private var retired: Set<String> = []
    private let retiredStore: RetiredLiveActivities
    /// When each running activity's game was first missing from the boards,
    /// by game id (`LiveActivityPlanner.offBoard`).
    private var offBoardSince: [String: Date] = [:]
    /// The favorites as the catalog knows them, by `TeamRef.id`: their
    /// abbreviation and colour mark a new activity's Dynamic Island (B-13).
    /// Resolved off the scoreboard's path (`resolveFavorite`), so a look
    /// never waits on the network; a game that starts before its team has
    /// resolved gets the generic mark, as the attributes are fixed at start.
    private var favoriteTeams: [TeamRef.ID: TeamRef] = [:]
    private var resolvingFavorites: Set<TeamRef.ID> = []
    /// The last update or end asked of each game's activity, by game id. The
    /// next waits for it, so they reach ActivityKit in the order asked
    /// (A-18): two unordered tasks could otherwise land an older score last.
    private var activityWork: [String: Task<Void, Never>] = [:]
    /// The number of the latest update asked of each game's activity. An
    /// update still waiting its turn when a later one is asked is skipped:
    /// the later one carries the newer state.
    private var latestUpdate: [String: Int] = [:]
    private var updateCount = 0
    private var isStarted = false

    init(
        center: LeagueScoreboardCenter = .shared,
        favorites: @escaping @MainActor () -> [FavoriteTeam] = { FavoritesStore.shared.favorites },
        isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        now: @escaping @MainActor () -> Date = { Date() },
        retiredStore: RetiredLiveActivities = RetiredLiveActivities(defaults: SharedPaths.defaults)
    ) {
        self.center = center
        self.favorites = favorites
        self.isForeground = isForeground
        self.now = now
        self.retiredStore = retiredStore
    }

    /// Takes over the activities still running from an earlier launch and
    /// begins watching the scoreboards. Calling it again does nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        retired = retiredStore.games(at: now())
        recover()
        observe()
    }

    /// Picks up the activities a previous launch left running, one per
    /// game; any second one for a game is ended, and so is one for a game
    /// already retired (its end was asked for but never landed). Those that
    /// finished while the app was away — dismissed, or timed out — retire
    /// their games.
    private func recover() {
        for activity in Activity<GameActivityAttributes>.activities {
            let gameID = activity.attributes.game.gameID
            guard Self.isRunning(activity) else {
                retire(gameID)
                continue
            }
            if activities[gameID] == nil && !retired.contains(gameID) {
                activities[gameID] = activity
                shown[gameID] = activity.content.state
            } else {
                let activityID = activity.id
                Task {
                    await Self.end(activityID, with: nil, dismissAt: nil)
                }
            }
        }
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
        forgetFinished()
        let canStart = isForeground() && ActivityAuthorizationInfo().areActivitiesEnabled
        let candidates = self.candidates(in: games)
        let now = self.now()
        offBoardSince = LiveActivityPlanner.offBoard(
            since: offBoardSince, candidates: candidates, running: shown, now: now
        )
        let actions = LiveActivityPlanner.plan(
            candidates: candidates,
            running: shown,
            retired: retired,
            offBoardSince: offBoardSince,
            now: now,
            canStart: canStart
        )
        for action in actions {
            apply(action)
        }
    }

    /// Every favorite's games, in its league and its cups: favorites with
    /// alerts on first, then the rest, each in favorites order.
    private func candidates(in games: [LeagueID: [ScoreboardGame]]) -> [LiveActivityCandidate] {
        let all = favorites()
        let ordered = all.filter(\.notify) + all.filter { !$0.notify }
        var result: [LiveActivityCandidate] = []
        for favorite in ordered {
            guard let team = TeamRef.parse(id: favorite.teamID) else { continue }
            let resolved = favoriteTeam(favorite.teamID)
            let competitions = [team.league] + team.league.descriptor.cupCompetitions
            for competition in competitions {
                for game in games[competition] ?? [] {
                    guard game.competitors.contains(where: { $0.teamID == team.espnID }),
                          // The link is built from the favorite's own league
                          // here, where it is known; the competition may be
                          // a cup.
                          let candidate = LiveActivityStateMapper.candidate(
                            for: game, teamID: team.espnID, homeLeague: team.league, league: competition,
                            favorite: resolved
                          )
                    else { continue }
                    result.append(candidate)
                }
            }
        }
        return result
    }

    /// The favorite `id` as the catalog knows it, if it has resolved: the
    /// bundle's seed teams at once, any other once `FavoritesStore.resolve`
    /// answers, which this asks for the first time it is missed.
    private func favoriteTeam(_ id: TeamRef.ID) -> TeamRef? {
        if let team = favoriteTeams[id] {
            return team
        }
        resolveFavorite(id)
        return TeamCatalog.team(id: id)
    }

    /// Looks `id` up in the background; one that cannot be found within
    /// the deadline is asked for again on a later look.
    private func resolveFavorite(_ id: TeamRef.ID) {
        guard resolvingFavorites.insert(id).inserted else { return }
        Task {
            let team = await FavoritesStore.resolve(id, within: .seconds(5))
            self.resolvingFavorites.remove(id)
            if let team {
                self.favoriteTeams[id] = team
            }
        }
    }

    /// Drops the activities that ended outside the app — dismissed from the
    /// Lock Screen, or timed out by the system — and never restarts them.
    private func forgetFinished() {
        for (gameID, activity) in activities where !Self.isRunning(activity) {
            activities[gameID] = nil
            shown[gameID] = nil
            retire(gameID)
        }
    }

    /// Never starts `gameID`'s activity again, this launch or the next.
    private func retire(_ gameID: String) {
        retired.insert(gameID)
        retiredStore.retire(gameID, at: now())
    }

    private func apply(_ action: LiveActivityAction) {
        switch action {
        case .start(let info, let state):
            do {
                let activity = try Activity.request(
                    attributes: GameActivityAttributes(game: info),
                    content: content(state),
                    pushType: nil
                )
                activities[info.gameID] = activity
                shown[info.gameID] = state
            } catch {
                logger.error("Could not start a Live Activity for \(info.gameID): \(error.localizedDescription)")
            }

        case .update(let gameID, let state):
            guard let activity = activities[gameID] else { return }
            shown[gameID] = state
            let activityID = activity.id
            let staleDate = now().addingTimeInterval(Self.staleAfter)
            updateCount += 1
            let sequence = updateCount
            latestUpdate[gameID] = sequence
            enqueue(gameID) {
                // Superseded while it waited: a later update has the
                // newer state, and goes next.
                guard self.latestUpdate[gameID] == sequence else { return }
                await Self.update(activityID, to: state, staleDate: staleDate)
            }

        case .end(let gameID, let state):
            end(gameID, showing: state, grace: Self.dismissalGrace)

        case .expire(let gameID, let state):
            end(gameID, showing: state, grace: Self.offBoardDismissalGrace)
        }
    }

    /// Ends `gameID`'s activity, lingering `grace` with `state`, and never
    /// starts it again.
    private func end(_ gameID: String, showing state: GameActivityState, grace: TimeInterval) {
        guard let activity = activities.removeValue(forKey: gameID) else { return }
        shown[gameID] = nil
        offBoardSince[gameID] = nil
        // Any update still waiting is older than the end's own state.
        latestUpdate[gameID] = nil
        retire(gameID)
        let activityID = activity.id
        let dismissAt = now().addingTimeInterval(grace)
        enqueue(gameID) {
            await Self.end(activityID, with: state, dismissAt: dismissAt)
        }
    }

    /// Runs `work` on `gameID`'s activity after everything asked of it
    /// before (`activityWork`), on the main actor; ActivityKit's own calls
    /// leave it (`update(_:to:staleDate:)`, `end(_:with:dismissAt:)`).
    private func enqueue(_ gameID: String, _ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = activityWork[gameID]
        activityWork[gameID] = Task {
            await previous?.value
            await work()
        }
    }

    private func content(_ state: GameActivityState) -> ActivityContent<GameActivityState> {
        ActivityContent(state: state, staleDate: now().addingTimeInterval(Self.staleAfter))
    }

    // The activity is found again by id off the main actor, so only
    // sendable values cross into the task.

    nonisolated private static func update(_ activityID: String, to state: GameActivityState, staleDate: Date) async {
        for activity in Activity<GameActivityAttributes>.activities where activity.id == activityID {
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        }
    }

    /// Ends the activity showing `state`, if given, until `dismissAt`, or at
    /// once without one.
    nonisolated private static func end(_ activityID: String, with state: GameActivityState?, dismissAt: Date?) async {
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy
        if let dismissAt {
            policy = .after(dismissAt)
        } else {
            policy = .immediate
        }
        for activity in Activity<GameActivityAttributes>.activities where activity.id == activityID {
            await activity.end(content, dismissalPolicy: policy)
        }
    }

    private static func isRunning(_ activity: Activity<GameActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }
}
#endif
