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
    /// The game has been off every board for `LiveActivityPlanner.
    /// offBoardTimeout`: end the activity showing `state`, its last content,
    /// and take it down soon after, not at the system's cap hours later.
    case expire(gameID: String, state: GameActivityState)
}

enum LiveActivityPlanner {
    /// ActivityKit lets an app run only a handful of activities at once;
    /// past this many, no new one is asked for.
    static let maxActivities = 6

    /// How long a running activity's game may be missing from every
    /// scoreboard before its activity is ended (`expire`). The center polls
    /// each favorite's board every minute while the app is open, so ten
    /// minutes without the game means it has left the boards (a finished
    /// game past the day's window, a favorite removed), not a slow poll.
    static let offBoardTimeout: TimeInterval = 10 * 60

    /// When each running activity's game was first found missing from
    /// `candidates`, carried from one look to the next: a game still missing
    /// keeps its date from `previous`, one newly missing is dated `now`, and
    /// one back on the boards, or no longer running, is dropped.
    static func offBoard(
        since previous: [String: Date],
        candidates: [LiveActivityCandidate],
        running: [String: GameActivityState],
        now: Date
    ) -> [String: Date] {
        let listed = Set(candidates.map(\.gameID))
        var result: [String: Date] = [:]
        for gameID in running.keys where !listed.contains(gameID) {
            result[gameID] = previous[gameID] ?? now
        }
        return result
    }

    /// What to do on one look at the scoreboards.
    ///
    /// - A running activity is updated when its game changed and ended once
    ///   the game is over (played out or called off). One whose game is not
    ///   on the boards is left alone, as the game may come back, until it
    ///   has been missing `offBoardTimeout` (`offBoardSince`); then it
    ///   expires.
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
    ///   - offBoardSince: when each running game missing from `candidates`
    ///     was first missed (`offBoard(since:candidates:running:now:)`).
    ///   - now: the current instant, against `offBoardSince`.
    ///   - canStart: whether a new activity may be asked for now (the app is
    ///     in the foreground and Live Activities are allowed).
    static func plan(
        candidates: [LiveActivityCandidate],
        running: [String: GameActivityState],
        retired: Set<String> = [],
        offBoardSince: [String: Date] = [:],
        now: Date = .distantPast,
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

        for (gameID, shown) in running.sorted(by: { $0.key < $1.key }) where !seen.contains(gameID) {
            guard let since = offBoardSince[gameID],
                  now.timeIntervalSince(since) >= offBoardTimeout
            else { continue }
            actions.append(.expire(gameID: gameID, state: shown))
            runningCount -= 1
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

/// The games whose Live Activity ended or was dismissed, kept across
/// launches so `LiveActivityPlanner` never offers them again.
///
/// Persisted retire, chosen over accepting a re-offer: a reader who swiped
/// a game's activity away, or saw it end, would otherwise get it back on
/// the next launch while the game is still on the boards — the app cannot
/// tell "dismissed" from "never started" once the in-memory set is gone. The
/// cost is that a game retired by mistake stays off the Lock Screen for the
/// rest of the day; a game is only ever worth one activity, so that is the
/// lesser surprise.
///
/// Each game is kept with the moment it was retired and dropped `horizon`
/// later — a day, past which the game is off the boards anyway — so the
/// store never outgrows a day's games.
struct RetiredLiveActivities {
    static let horizon: TimeInterval = 24 * 60 * 60
    static let defaultsKey = "liveActivities.retired"

    private let defaults: UserDefaults

    /// Kept in `defaults`: the App Group's (`SharedPaths.defaults`) in the
    /// app, a scratch suite in tests.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The games retired within `horizon` of `now`.
    func games(at now: Date) -> Set<String> {
        Set(entries(at: now).keys)
    }

    /// Records `gameID` as retired at `now`, and forgets the games retired
    /// more than `horizon` before.
    func retire(_ gameID: String, at now: Date) {
        var entries = entries(at: now)
        entries[gameID] = now
        defaults.set(entries.mapValues(\.timeIntervalSince1970), forKey: Self.defaultsKey)
    }

    private func entries(at now: Date) -> [String: Date] {
        let stored = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        var entries: [String: Date] = [:]
        for (gameID, value) in stored {
            guard let seconds = value as? Double else { continue }
            let retiredAt = Date(timeIntervalSince1970: seconds)
            if now.timeIntervalSince(retiredAt) < Self.horizon {
                entries[gameID] = retiredAt
            }
        }
        return entries
    }
}
