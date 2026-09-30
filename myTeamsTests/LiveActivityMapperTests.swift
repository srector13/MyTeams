//
//  LiveActivityMapperTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// K-State (2306) at Kansas (2305) on a scoreboard.
private func board(
    _ state: String,
    completed: Bool = false,
    home: Int? = 0,
    away: Int? = 0,
    period: Int = 0,
    clock: String = "0:00",
    id: String = "1"
) -> ScoreboardGame {
    ScoreboardGame(
        gameID: id,
        state: state,
        completed: completed,
        competitors: [
            ScoreboardCompetitor(teamID: "2305", homeAway: "home", score: home),
            ScoreboardCompetitor(teamID: "2306", homeAway: "away", score: away),
        ],
        period: period,
        teamNames: ["2305": "Kansas", "2306": "K-State"],
        clock: clock,
        startDate: Date(timeIntervalSince1970: 1_790_000_000)
    )
}

private func state(
    _ phase: GameActivityState.Phase,
    home: Int = 0,
    away: Int = 0,
    period: Int = 0,
    clock: String = ""
) -> GameActivityState {
    GameActivityState(homeScore: home, awayScore: away, period: period, clock: clock, phase: phase)
}

private func candidate(_ id: String, _ state: GameActivityState) -> LiveActivityCandidate {
    LiveActivityCandidate(
        info: GameActivityInfo(
            gameID: id, teamID: "2305", league: "football/college-football",
            homeName: "Kansas", awayName: "K-State", matchup: "K-State at Kansas",
            kickoff: nil
        ),
        state: state
    )
}

@Suite("Live Activity mapping")
struct LiveActivityMapperTests {
    @Test("A game under way shows its score, period and clock")
    func live() {
        let game = board("in", home: 14, away: 10, period: 3, clock: "8:21")
        let mapped = LiveActivityStateMapper.state(of: game, league: .collegeFootball)
        #expect(mapped == state(.live, home: 14, away: 10, period: 3, clock: "8:21"))
        #expect(mapped?.stage == "3rd · 8:21")
    }

    @Test("Soccer's running minute is the clock")
    func soccerClock() {
        let game = board("in", home: 1, away: 1, period: 2, clock: "90'+5'")
        let mapped = LiveActivityStateMapper.state(of: game, league: .premierLeague)
        #expect(mapped?.clock == "90'+5'")
        #expect(mapped?.stage == "2nd · 90'+5'")
    }

    @Test("No clock for baseball, nor one run out")
    func noClock() {
        let inning = board("in", home: 2, away: 3, period: 5, clock: "0:00")
        #expect(LiveActivityStateMapper.state(of: inning, league: .mlb) == state(.live, home: 2, away: 3, period: 5))
        #expect(LiveActivityStateMapper.state(of: inning, league: .mlb)?.stage == "5th")

        let baseballClock = board("in", period: 1, clock: "12:00")
        #expect(LiveActivityStateMapper.state(of: baseballClock, league: .mlb)?.clock == "")

        let endOfQuarter = board("in", home: 7, period: 1, clock: "0:00")
        #expect(LiveActivityStateMapper.state(of: endOfQuarter, league: .nfl)?.clock == "")
        #expect(LiveActivityStateMapper.shownClock("0.0", league: .nba) == "")
        #expect(LiveActivityStateMapper.shownClock(" 4:12 ", league: .nba) == "4:12")
    }

    @Test("Before the start: pending, 0–0, no clock")
    func pregame() {
        let game = board("pre", clock: "0.0")
        let mapped = LiveActivityStateMapper.state(of: game, league: .nba)
        #expect(mapped == state(.pending))
        #expect(mapped?.stage == "Pregame")
    }

    @Test("Played out is ended; called off is its own phase")
    func over() {
        let played = board("post", completed: true, home: 24, away: 17, period: 4, clock: "0:00")
        let mapped = LiveActivityStateMapper.state(of: played, league: .collegeFootball)
        #expect(mapped == state(.ended, home: 24, away: 17, period: 4))
        #expect(mapped?.stage == "Final")

        let postponed = board("post", completed: false, home: 3, away: 0, period: 2, clock: "5:00")
        #expect(LiveActivityStateMapper.state(of: postponed, league: .collegeFootball)?.phase == .calledOff)
    }

    @Test("A missing score reads 0, as the alerts read it")
    func missingScore() {
        let game = board("in", home: nil, away: 7, period: 1, clock: "10:00")
        #expect(LiveActivityStateMapper.state(of: game, league: .nfl)?.homeScore == 0)
    }

    @Test("Not home against away: nothing to show")
    func notTwoSided() {
        var game = board("in", period: 1)
        game.competitors[1].homeAway = "home"
        #expect(LiveActivityStateMapper.state(of: game, league: .nfl) == nil)
        #expect(LiveActivityStateMapper.info(of: game, teamID: "2305", league: .nfl) == nil)

        game.competitors.removeLast()
        #expect(LiveActivityStateMapper.candidate(for: game, teamID: "2305", league: .nfl) == nil)
    }

    @Test("The matchup: away at home, the followed team, the board's league, the kickoff")
    func info() {
        let game = board("in", period: 1, id: "401")
        let info = LiveActivityStateMapper.info(of: game, teamID: "2306", league: .collegeFootball)
        #expect(info == GameActivityInfo(
            gameID: "401", teamID: "2306", league: "football/college-football",
            homeName: "Kansas", awayName: "K-State", matchup: "K-State at Kansas",
            kickoff: Date(timeIntervalSince1970: 1_790_000_000)
        ))
    }

    @Test("Stage labels")
    func stages() {
        #expect(state(.live, period: 0).stage == "Live")
        #expect(state(.live, period: 2).stage == "2nd")
        #expect(state(.live, period: 4, clock: "0:48").stage == "4th · 0:48")
        #expect(state(.calledOff, period: 2).stage == "Called off")
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(GameActivityState.ordinal)
            == [1, 2, 3, 4, 11, 12, 13, 21, 22].map(ScoreSnapshot.ordinal))
    }

    @Test("Golden: Sunday night's NFL game, 0:48 left in the 4th")
    func nflFixture() throws {
        // nfl_scoreboard_20260927 id 401872962: Rams (14) at Broncos (7),
        // 26–23, status.displayClock "0:48", period 4, date 2026-09-28T00:20Z.
        let scoreboard = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let game = try #require(scoreboard.games.first { $0.gameID == "401872962" })
        #expect(game.clock == "0:48")
        #expect(game.startDate == parseGameDate("2026-09-28T00:20Z"))

        let candidate = try #require(LiveActivityStateMapper.candidate(for: game, teamID: "7", league: .nfl))
        #expect(candidate.info.matchup == "Rams at Broncos")
        #expect(candidate.info.league == "football/nfl")
        #expect(candidate.state == state(.live, home: 23, away: 26, period: 4, clock: "0:48"))
        #expect(candidate.state.stage == "4th · 0:48")
    }
}

@Suite("Live Activity planning")
struct LiveActivityPlannerTests {
    @Test("A live game with no activity starts one")
    func start() {
        let live = candidate("1", state(.live, home: 7, period: 1, clock: "3:00"))
        let actions = LiveActivityPlanner.plan(candidates: [live], running: [:], canStart: true)
        #expect(actions == [.start(live.info, live.state)])
    }

    @Test("Games not under way start nothing")
    func noStart() {
        let games = [
            candidate("1", state(.pending)),
            candidate("2", state(.ended, home: 3, period: 4)),
            candidate("3", state(.calledOff)),
        ]
        #expect(LiveActivityPlanner.plan(candidates: games, running: [:], canStart: true).isEmpty)
    }

    @Test("A running activity updates on a change, and only then")
    func update() {
        let before = state(.live, home: 7, period: 1, clock: "3:00")
        let after = state(.live, home: 7, period: 1, clock: "2:00")
        #expect(LiveActivityPlanner.plan(
            candidates: [candidate("1", before)], running: ["1": before], canStart: true
        ).isEmpty)
        #expect(LiveActivityPlanner.plan(
            candidates: [candidate("1", after)], running: ["1": before], canStart: true
        ) == [.update(gameID: "1", state: after)])
    }

    @Test("The final ends the activity with the final score")
    func end() {
        let played = state(.ended, home: 24, away: 17, period: 4)
        let actions = LiveActivityPlanner.plan(
            candidates: [candidate("1", played)],
            running: ["1": state(.live, home: 21, away: 17, period: 4, clock: "0:12")],
            canStart: true
        )
        #expect(actions == [.end(gameID: "1", state: played)])
    }

    @Test("A game called off mid-game ends its activity")
    func calledOff() {
        let off = state(.calledOff, home: 3, period: 2)
        let actions = LiveActivityPlanner.plan(
            candidates: [candidate("1", off)], running: ["1": state(.live, home: 3, period: 2)], canStart: true
        )
        #expect(actions == [.end(gameID: "1", state: off)])
    }

    @Test("A game off the boards keeps its activity")
    func offTheBoard() {
        #expect(LiveActivityPlanner.plan(
            candidates: [], running: ["1": state(.live, period: 1)], canStart: true
        ).isEmpty)
    }

    @Test("Off-board dates: kept while missing, set when newly missed, dropped once back or ended")
    func offBoardDates() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let later = start.addingTimeInterval(60)
        let live = state(.live, period: 1)
        let running = ["1": live, "2": live, "3": live]

        // "1" missing since the start, "2" newly missing, "3" still listed.
        let first = LiveActivityPlanner.offBoard(
            since: [:], candidates: [candidate("3", live)], running: running, now: start
        )
        #expect(first == ["1": start, "2": start])
        let second = LiveActivityPlanner.offBoard(
            since: ["1": start], candidates: [candidate("3", live)], running: running, now: later
        )
        #expect(second == ["1": start, "2": later])

        // "1" back on the boards; "2" no longer running.
        let third = LiveActivityPlanner.offBoard(
            since: second, candidates: [candidate("1", live)], running: ["1": live, "3": live], now: later
        )
        #expect(third == ["3": later])
    }

    @Test("Off the boards for ten minutes, the activity expires with its last content")
    func offBoardExpiry() {
        let since = Date(timeIntervalSince1970: 1_790_000_000)
        let shown = state(.live, home: 7, period: 3, clock: "4:00")
        #expect(LiveActivityPlanner.offBoardTimeout == 10 * 60)

        // Nine minutes and change: left alone.
        #expect(LiveActivityPlanner.plan(
            candidates: [], running: ["1": shown],
            offBoardSince: ["1": since], now: since.addingTimeInterval(9 * 60 + 59),
            canStart: true
        ).isEmpty)

        // Ten: expired, in the background too.
        let expired = LiveActivityPlanner.plan(
            candidates: [], running: ["1": shown],
            offBoardSince: ["1": since], now: since.addingTimeInterval(10 * 60),
            canStart: false
        )
        #expect(expired == [.expire(gameID: "1", state: shown)])

        // A listed game is never expired, whatever date it carries.
        #expect(LiveActivityPlanner.plan(
            candidates: [candidate("1", shown)], running: ["1": shown],
            offBoardSince: ["1": since], now: since.addingTimeInterval(60 * 60),
            canStart: true
        ).isEmpty)
    }

    @Test("An expiry in the same look frees its place")
    func expiryFreesPlace() {
        let since = Date(timeIntervalSince1970: 1_790_000_000)
        let live = state(.live, period: 2)
        let running = Dictionary(uniqueKeysWithValues: (1...6).map { ("r\($0)", live) })
        let fresh = candidate("new", state(.live, period: 1))
        let candidates = [fresh] + (2...6).map { candidate("r\($0)", live) }
        let actions = LiveActivityPlanner.plan(
            candidates: candidates, running: running,
            offBoardSince: ["r1": since], now: since.addingTimeInterval(LiveActivityPlanner.offBoardTimeout),
            canStart: true
        )
        #expect(actions == [.expire(gameID: "r1", state: live), .start(fresh.info, fresh.state)])
    }

    @Test("Tracked from look to look, a game that stays off the boards expires once, ten minutes after it was first missed")
    func offBoardAcrossLooks() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let shown = state(.live, home: 3, period: 2)
        let running = ["1": shown]
        var since: [String: Date] = [:]
        var expiredAt: [Int] = []
        // One look a minute, as the center polls, the game gone throughout.
        for minute in 0...12 {
            let now = start.addingTimeInterval(TimeInterval(minute * 60))
            since = LiveActivityPlanner.offBoard(since: since, candidates: [], running: running, now: now)
            let actions = LiveActivityPlanner.plan(
                candidates: [], running: running, offBoardSince: since, now: now, canStart: true
            )
            if actions == [.expire(gameID: "1", state: shown)] {
                expiredAt.append(minute)
                break
            }
            #expect(actions.isEmpty)
        }
        #expect(expiredAt == [10])
    }

    @Test("In the background: updates and ends, but no starts")
    func background() {
        let changed = state(.live, home: 3, period: 2)
        let actions = LiveActivityPlanner.plan(
            candidates: [candidate("1", changed), candidate("2", state(.live, period: 1))],
            running: ["1": state(.live, period: 2)],
            canStart: false
        )
        #expect(actions == [.update(gameID: "1", state: changed)])
    }

    @Test("A retired game never starts again")
    func retired() {
        let live = candidate("1", state(.live, period: 1))
        #expect(LiveActivityPlanner.plan(
            candidates: [live], running: [:], retired: ["1"], canStart: true
        ).isEmpty)
    }

    @Test("No more than six at once, the first candidates first")
    func limit() {
        let running = Dictionary(uniqueKeysWithValues: (1...5).map { ("r\($0)", state(.live, period: 1)) })
        let candidates = (1...5).map { candidate("r\($0)", state(.live, period: 1)) }
            + [candidate("a", state(.live, period: 1)), candidate("b", state(.live, period: 1))]
        let actions = LiveActivityPlanner.plan(candidates: candidates, running: running, canStart: true)
        #expect(LiveActivityPlanner.maxActivities == 6)
        #expect(actions == [.start(candidates[5].info, candidates[5].state)])

        let full = running.merging(["a": state(.live, period: 1)]) { old, _ in old }
        #expect(LiveActivityPlanner.plan(candidates: candidates, running: full, canStart: true).isEmpty)
    }

    @Test("An end in the same look frees its place")
    func endFreesPlace() {
        let running = Dictionary(uniqueKeysWithValues: (1...6).map { ("r\($0)", state(.live, period: 4)) })
        let played = state(.ended, home: 1, period: 4)
        let fresh = candidate("new", state(.live, period: 1))
        let candidates = [fresh, candidate("r1", played)]
            + (2...6).map { candidate("r\($0)", state(.live, period: 4)) }
        let actions = LiveActivityPlanner.plan(candidates: candidates, running: running, canStart: true)
        #expect(actions == [.end(gameID: "r1", state: played), .start(fresh.info, fresh.state)])
    }

    @Test("A game listed twice starts once")
    func duplicate() {
        let live = candidate("1", state(.live, period: 1))
        var other = live
        other.info.teamID = "2306"
        let actions = LiveActivityPlanner.plan(candidates: [live, other], running: [:], canStart: true)
        #expect(actions == [.start(live.info, live.state)])
    }
}
