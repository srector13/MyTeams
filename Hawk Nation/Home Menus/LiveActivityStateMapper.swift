//
//  LiveActivityStateMapper.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// The Live Activity model: scoreboard games in, activity content and the
// starts, updates and ends to make out. Nothing here knows about ActivityKit
// or the scoreboard center, so it builds and tests on any Swift toolchain.
// `LiveActivityManager` feeds it on each scoreboard fan-out.

/// Reads a scoreboard game as a Live Activity shows it.
enum LiveActivityStateMapper {
    /// `game` now. Scores, period and state are the score alerts' reading of
    /// it (`ScoreAlertEngine.snapshot(of:)`), so an activity and an alert
    /// never disagree; `nil` for a game that is not two teams, home and away.
    ///
    /// - Parameter league: the league or cup whose scoreboard lists the
    ///   game. Baseball keeps no clock, so its `"0:00"` is never shown.
    static func state(of game: ScoreboardGame, league: LeagueID) -> GameActivityState? {
        guard let snapshot = ScoreAlertEngine.snapshot(of: game) else { return nil }

        let phase: GameActivityState.Phase
        switch snapshot.state {
        case .inProgress: phase = .live
        case .final: phase = .ended
        // The alerts read a game called off as never started; an activity
        // already showing it has to be told it is over.
        case .scheduled: phase = game.state == "post" ? .calledOff : .pending
        }

        return GameActivityState(
            homeScore: snapshot.homeScore,
            awayScore: snapshot.awayScore,
            period: snapshot.period,
            clock: phase == .live ? shownClock(game.clock, league: league) : "",
            phase: phase
        )
    }

    /// The matchup of `game` as `teamID` (an ESPN id) follows it; `nil` for
    /// a game that is not two teams, home and away.
    static func info(of game: ScoreboardGame, teamID: String, league: LeagueID) -> GameActivityInfo? {
        guard let snapshot = ScoreAlertEngine.snapshot(of: game) else { return nil }
        return GameActivityInfo(
            gameID: game.gameID,
            teamID: teamID,
            league: league.path,
            homeName: snapshot.homeName,
            awayName: snapshot.awayName,
            matchup: "\(snapshot.awayName) at \(snapshot.homeName)",
            kickoff: game.startDate
        )
    }

    /// The clock worth showing: none for baseball, nor one run out (`"0:00"`,
    /// or `"0.0"` as some boards write it).
    static func shownClock(_ clock: String, league: LeagueID) -> String {
        let clock = clock.trimmingCharacters(in: .whitespaces)
        guard league.sport != "baseball", !["0:00", "0.0", "0"].contains(clock) else { return "" }
        return clock
    }

    /// The Live Activity for a followed game, or `nil` for one it cannot
    /// show.
    static func candidate(for game: ScoreboardGame, teamID: String, league: LeagueID) -> LiveActivityCandidate? {
        guard let info = info(of: game, teamID: teamID, league: league),
              let state = state(of: game, league: league)
        else { return nil }
        return LiveActivityCandidate(info: info, state: state)
    }
}

/// A followed game on the scoreboard, as its Live Activity would show it.
struct LiveActivityCandidate: Equatable, Sendable {
    var info: GameActivityInfo
    var state: GameActivityState

    var gameID: String { info.gameID }
}

/// Something to do to a game's Live Activity.
enum LiveActivityAction: Equatable, Sendable {
    case start(GameActivityInfo, GameActivityState)
    case update(gameID: String, state: GameActivityState)
    /// `state` is the last one to show while the activity lingers.
    case end(gameID: String, state: GameActivityState)
}

enum LiveActivityPlanner {
    /// ActivityKit lets an app run only a handful of activities at once;
    /// past this many, no new one is asked for.
    static let maxActivities = 6

    /// What to do on one look at the scoreboards.
    ///
    /// - A running activity is updated when its game changed and ended once
    ///   the game is over (played out or called off). One whose game is not
    ///   on the boards is left alone; the game may come back.
    /// - A live game with no activity starts one if `canStart`, it was not
    ///   `retired`, and fewer than `limit` would then be running. Ends in
    ///   the same look free their places first; starts go in `candidates`
    ///   order, so the caller puts the games it cares most about first.
    /// - A game listed twice (two followed teams playing each other) counts
    ///   once, as its first listing.
    ///
    /// - Parameters:
    ///   - running: the state each running activity last showed, by game id.
    ///   - retired: games whose activity ended or was dismissed; never
    ///     started again.
    ///   - canStart: whether a new activity may be asked for now (the app is
    ///     in the foreground and Live Activities are allowed).
    static func plan(
        candidates: [LiveActivityCandidate],
        running: [String: GameActivityState],
        retired: Set<String> = [],
        canStart: Bool,
        limit: Int = maxActivities
    ) -> [LiveActivityAction] {
        var seen: Set<String> = []
        let games = candidates.filter { seen.insert($0.gameID).inserted }

        var actions: [LiveActivityAction] = []
        var runningCount = running.count
        for game in games {
            guard let shown = running[game.gameID] else { continue }
            switch game.state.phase {
            case .ended, .calledOff:
                actions.append(.end(gameID: game.gameID, state: game.state))
                runningCount -= 1
            case .pending, .live:
                if game.state != shown {
                    actions.append(.update(gameID: game.gameID, state: game.state))
                }
            }
        }

        guard canStart else { return actions }
        for game in games where running[game.gameID] == nil {
            guard game.state.phase == .live,
                  !retired.contains(game.gameID),
                  runningCount < limit
            else { continue }
            actions.append(.start(game.info, game.state))
            runningCount += 1
        }
        return actions
    }
}
