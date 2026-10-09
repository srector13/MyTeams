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
    clock: String = "",
    label: String? = nil
) -> GameActivityState {
    GameActivityState(homeScore: home, awayScore: away, period: period, clock: clock, phase: phase, periodLabel: label)
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
        #expect(mapped == state(.live, home: 14, away: 10, period: 3, clock: "8:21", label: "3rd Quarter"))
        #expect(mapped?.stage == "3rd Quarter · 8:21")
    }

    @Test("Soccer's running minute is the clock")
    func soccerClock() {
        let game = board("in", home: 1, away: 1, period: 2, clock: "90'+5'")
        let mapped = LiveActivityStateMapper.state(of: game, league: .premierLeague)
        #expect(mapped?.clock == "90'+5'")
        #expect(mapped?.stage == "2nd Half · 90'+5'")
    }

    @Test("Past regulation the stage follows the league: overtime, or extra time")
    func pastRegulation() {
        let hockey = board("in", home: 2, away: 2, period: 4, clock: "3:12")
        #expect(LiveActivityStateMapper.state(of: hockey, league: .nhl)?.stage == "OT · 3:12")
        let shootout = board("in", home: 2, away: 2, period: 5, clock: "0:00")
        #expect(LiveActivityStateMapper.state(of: shootout, league: .nhl)?.stage == "2OT")

        let football = board("in", home: 20, away: 20, period: 5, clock: "8:00")
        #expect(LiveActivityStateMapper.state(of: football, league: .nfl)?.stage == "OT · 8:00")

        let cupTie = board("in", home: 1, away: 1, period: 3, clock: "95'")
        #expect(LiveActivityStateMapper.state(of: cupTie, league: .championsLeague)?.stage == "Extra Time · 95'")
        #expect(LiveActivityStateMapper.state(of: cupTie, league: .soccer("eng.fa"))?.stage == "Extra Time · 95'")
        let penalties = board("in", home: 1, away: 1, period: 5, clock: "120'")
        #expect(LiveActivityStateMapper.state(of: penalties, league: .premierLeague)?.stage == "Penalties · 120'")
    }

    @Test("The stage and the alerts' summary read the same")
    func stageMatchesAlerts() throws {
        let game = board("in", home: 2, away: 2, period: 4, clock: "3:12")
        let mapped = try #require(LiveActivityStateMapper.state(of: game, league: .nhl))
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: game, league: .nhl))
        #expect(mapped.periodLabel == snapshot.stageLabel)
        #expect(snapshot.summary == "K-State 2 – Kansas 2 (OT)")
    }

    @Test("No clock for baseball, nor one run out")
    func noClock() {
        let inning = board("in", home: 2, away: 3, period: 5, clock: "0:00")
        #expect(LiveActivityStateMapper.state(of: inning, league: .mlb) == state(.live, home: 2, away: 3, period: 5, label: "5th"))
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
        #expect(LiveActivityStateMapper.info(of: game, teamID: "2305", homeLeague: .nfl, league: .nfl) == nil)

        game.competitors.removeLast()
        #expect(LiveActivityStateMapper.candidate(for: game, teamID: "2305", homeLeague: .nfl, league: .nfl) == nil)
    }

    @Test("The matchup: away at home, the followed team, the board's league, the kickoff")
    func info() {
        let game = board("in", period: 1, id: "401")
        let info = LiveActivityStateMapper.info(of: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball)
        #expect(info == GameActivityInfo(
            gameID: "401", teamID: "2306", league: "football/college-football",
            homeName: "Kansas", awayName: "K-State", matchup: "K-State at Kansas",
            kickoff: Date(timeIntervalSince1970: 1_790_000_000),
            favoriteID: "football/college-football:2306"
        ))
    }

    @Test("Stage labels")
    func stages() {
        #expect(state(.live, period: 0).stage == "Live")
        #expect(state(.live, period: 2).stage == "2nd")
        #expect(state(.live, period: 4, clock: "0:48").stage == "4th · 0:48")
        #expect(state(.calledOff, period: 2).stage == "Called off")
        // The app's label wins over the ordinal; only live shows it.
        #expect(state(.live, period: 4, clock: "3:12", label: "OT").stage == "OT · 3:12")
        #expect(state(.ended, period: 4, label: "OT").stage == "Final")
    }

    @Test("Golden: Sunday night's NFL game, 0:48 left in the 4th")
    func nflFixture() throws {
        // nfl_scoreboard_20260927 id 401872962: Rams (14) at Broncos (7),
        // 26–23, status.displayClock "0:48", period 4, date 2026-09-28T00:20Z.
        let scoreboard = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let game = try #require(scoreboard.games.first { $0.gameID == "401872962" })
        #expect(game.clock == "0:48")
        #expect(game.startDate == parseGameDate("2026-09-28T00:20Z"))

        let candidate = try #require(LiveActivityStateMapper.candidate(for: game, teamID: "7", homeLeague: .nfl, league: .nfl))
        #expect(candidate.info.matchup == "Rams at Broncos")
        #expect(candidate.info.league == "football/nfl")
        #expect(candidate.info.favoriteID == "football/nfl:7")
        #expect(candidate.info.deepLink == WidgetDeepLink.url(forTeamID: "football/nfl:7"))
        #expect(candidate.state == state(.live, home: 23, away: 26, period: 4, clock: "0:48", label: "4th Quarter"))
        #expect(candidate.state.stage == "4th Quarter · 0:48")
    }

    // MARK: The followed team's identity (B-13)

    /// K-State as a catalog lookup would give it: not one of the bundle's
    /// seed teams.
    private func kState(abbreviation: String = "KSU", colorHex: String = "512888") -> TeamRef {
        TeamRef(
            league: .collegeFootball, espnID: "2306",
            displayName: "Kansas State Wildcats", shortName: "K-State",
            abbreviation: abbreviation, location: "Kansas State",
            colorHex: colorHex, alternateColorHex: "FFFFFF",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
    }

    @Test("The followed team's abbreviation and colour ride in the static attributes")
    func identity() throws {
        let game = board("in", period: 1, id: "401")
        let info = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball, favorite: kState()
        ))
        #expect(info.favoriteAbbreviation == "KSU")
        #expect(info.favoriteColorHex == "512888")
        #expect(info.favoriteID == "football/college-football:2306")

        // Through the candidate as well, as the manager asks.
        let candidate = try #require(LiveActivityStateMapper.candidate(
            for: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball, favorite: kState()
        ))
        #expect(candidate.info == info)
    }

    @Test("A blank abbreviation or an unreadable colour is left out")
    func blankIdentity() throws {
        let game = board("in", period: 1)
        let blank = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball,
            favorite: kState(abbreviation: " ", colorHex: "")
        ))
        #expect(blank.favoriteAbbreviation == nil)
        #expect(blank.favoriteColorHex == nil)

        let odd = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball,
            favorite: kState(colorHex: "purple")
        ))
        #expect(odd.favoriteAbbreviation == "KSU")
        #expect(odd.favoriteColorHex == nil)
    }

    @Test("A team that isn't the followed one marks nothing; without one, nothing either")
    func mismatchedIdentity() throws {
        let game = board("in", period: 1)
        // K-State given for a Kansas activity.
        let other = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "2305", homeLeague: .collegeFootball, league: .collegeFootball, favorite: kState()
        ))
        #expect(other.favoriteAbbreviation == nil)
        #expect(other.favoriteColorHex == nil)

        let unknown = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "2306", homeLeague: .collegeFootball, league: .collegeFootball
        ))
        #expect(unknown.favoriteAbbreviation == nil)
        #expect(unknown.favoriteColorHex == nil)
    }

    @Test("A cup tie keeps the team's identity from its home league")
    func cupTieIdentity() throws {
        let arsenal = TeamRef(
            league: .premierLeague, espnID: "359",
            displayName: "Arsenal", shortName: "Arsenal", abbreviation: "ARS", location: "Arsenal",
            colorHex: "E20520", alternateColorHex: "FFFFFF",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        var game = board("in", period: 1, id: "401915423")
        game.competitors = [
            ScoreboardCompetitor(teamID: "114", homeAway: "home", score: 0),
            ScoreboardCompetitor(teamID: "359", homeAway: "away", score: 1),
        ]
        let info = try #require(LiveActivityStateMapper.info(
            of: game, teamID: "359", homeLeague: .premierLeague, league: .championsLeague, favorite: arsenal
        ))
        #expect(info.league == "soccer/uefa.champions")
        #expect(info.favoriteAbbreviation == "ARS")
        #expect(info.favoriteColorHex == "E20520")
    }

    @Test("Attributes and content from an older build, without the new fields, still decode")
    func olderPayloads() throws {
        let info = Data("""
        {"gameID":"1","teamID":"2305","league":"football/nfl","homeName":"Kansas",\
        "awayName":"K-State","matchup":"K-State at Kansas","favoriteID":"football/nfl:2305"}
        """.utf8)
        let decoded = try JSONDecoder().decode(GameActivityInfo.self, from: info)
        #expect(decoded.favoriteAbbreviation == nil)
        #expect(decoded.favoriteColorHex == nil)
        #expect(decoded.favoriteID == "football/nfl:2305")

        let content = Data("""
        {"homeScore":2,"awayScore":3,"period":4,"clock":"1:00","phase":"live"}
        """.utf8)
        let state = try JSONDecoder().decode(GameActivityState.self, from: content)
        #expect(state.periodLabel == nil)
        #expect(state.stage == "4th · 1:00")

        // And the new fields round-trip.
        var stored = decoded
        stored.favoriteAbbreviation = "KU"
        stored.favoriteColorHex = "0051BA"
        let roundTrip = try JSONDecoder().decode(GameActivityInfo.self, from: JSONEncoder().encode(stored))
        #expect(roundTrip == stored)
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

@Suite("Live Activity retired games")
struct RetiredLiveActivitiesTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func scratchDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "RetiredLiveActivitiesTests.\(UUID().uuidString)"))
    }

    @Test("A game retired in one launch is still retired in the next, and never restarted")
    func persistsAcrossLaunches() throws {
        let defaults = try scratchDefaults()
        RetiredLiveActivities(defaults: defaults).retire("1", at: start)

        // The next launch: a new store over the same defaults, the game
        // still live on the boards.
        let relaunched = RetiredLiveActivities(defaults: defaults)
        let retired = relaunched.games(at: start.addingTimeInterval(60 * 60))
        #expect(retired == ["1"])

        let live = candidate("1", state(.live, home: 7, period: 2))
        let other = candidate("2", state(.live, period: 1))
        let actions = LiveActivityPlanner.plan(
            candidates: [live, other], running: [:], retired: retired, canStart: true
        )
        #expect(actions == [.start(other.info, other.state)])
    }

    @Test("Retired games are forgotten a day later, and dropped from the store")
    func horizon() throws {
        let defaults = try scratchDefaults()
        let store = RetiredLiveActivities(defaults: defaults)
        #expect(RetiredLiveActivities.horizon == 24 * 60 * 60)
        #expect(store.games(at: start).isEmpty)

        store.retire("old", at: start)
        store.retire("new", at: start.addingTimeInterval(12 * 60 * 60))
        let justBefore = start.addingTimeInterval(RetiredLiveActivities.horizon - 1)
        #expect(store.games(at: justBefore) == ["old", "new"])
        let dayLater = start.addingTimeInterval(RetiredLiveActivities.horizon)
        #expect(store.games(at: dayLater) == ["new"])

        // The next write prunes what has aged out, so the store stays small.
        store.retire("newer", at: dayLater)
        let stored = defaults.dictionary(forKey: RetiredLiveActivities.defaultsKey) ?? [:]
        #expect(Set(stored.keys) == ["new", "newer"])
    }

    @Test("Retiring again restarts the game's day")
    func retireAgain() throws {
        let store = RetiredLiveActivities(defaults: try scratchDefaults())
        store.retire("1", at: start)
        store.retire("1", at: start.addingTimeInterval(20 * 60 * 60))
        #expect(store.games(at: start.addingTimeInterval(30 * 60 * 60)) == ["1"])
    }
}
