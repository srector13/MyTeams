//
//  BoxScoreParsingTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/24/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Covers the MLB and MLS box-score readers added after the M3 stub removal.
///
/// The fixtures mirror the shapes the live ESPN summary endpoints publish
/// (verified against games played, September 2026): baseball nests its team
/// statistics under named groups where the same stat name recurs across
/// groups, and its box score lists the away team first; soccer lists its
/// statistics flat, lists the home team first, and carries goals only on the
/// header competitors.
@Suite("Box score parsing")
struct BoxScoreParsingTests {
    /// An abridged MLB summary: White Sox (away) 9 at Royals (home) 1.
    /// `hits` deliberately appears in all three groups with different values
    /// so a reader that ignores the group name fails.
    static let mlb = JSON(data: Data("""
    {
      "header": {"competitions": [{
        "status": {"type": {"detail": "Final"}},
        "competitors": [
          {"homeAway": "home", "score": "1",
           "team": {"shortDisplayName": "Royals"}},
          {"homeAway": "away", "score": "9",
           "team": {"shortDisplayName": "White Sox"}}
        ]
      }]},
      "boxscore": {"teams": [
        {"homeAway": "away",
         "team": {"shortDisplayName": "White Sox"},
         "statistics": [
          {"name": "batting", "stats": [
            {"name": "runs", "displayValue": "9"},
            {"name": "hits", "displayValue": "12"}
          ]},
          {"name": "pitching", "stats": [
            {"name": "hits", "displayValue": "1"},
            {"name": "runs", "displayValue": "1"}
          ]},
          {"name": "fielding", "stats": [
            {"name": "hits", "displayValue": "0"},
            {"name": "errors", "displayValue": "0"}
          ]}
        ]},
        {"homeAway": "home",
         "team": {"shortDisplayName": "Royals"},
         "statistics": [
          {"name": "batting", "stats": [
            {"name": "runs", "displayValue": "1"},
            {"name": "hits", "displayValue": "7"}
          ]},
          {"name": "pitching", "stats": [
            {"name": "hits", "displayValue": "12"},
            {"name": "runs", "displayValue": "9"}
          ]},
          {"name": "fielding", "stats": [
            {"name": "hits", "displayValue": "0"},
            {"name": "errors", "displayValue": "2"}
          ]}
        ]}
      ]}
    }
    """.utf8))

    /// An abridged MLS summary: Sporting KC (home) 3, Philadelphia (away) 4,
    /// with the box score listing teams in the feed's home-first order.
    static let mls = JSON(data: Data("""
    {
      "header": {"competitions": [{
        "status": {"type": {"detail": "FT"}},
        "competitors": [
          {"homeAway": "home", "score": "3",
           "team": {"shortDisplayName": "Kansas City"}},
          {"homeAway": "away", "score": "4",
           "team": {"shortDisplayName": "Philadelphia"}}
        ]
      }]},
      "boxscore": {"teams": [
        {"homeAway": "home",
         "team": {"shortDisplayName": "Kansas City"},
         "statistics": [
          {"name": "foulsCommitted", "displayValue": "9"},
          {"name": "wonCorners", "displayValue": "6"},
          {"name": "possessionPct", "displayValue": "47.2"},
          {"name": "totalShots", "displayValue": "14"},
          {"name": "shotsOnTarget", "displayValue": "7"}
        ]},
        {"homeAway": "away",
         "team": {"shortDisplayName": "Philadelphia"},
         "statistics": [
          {"name": "foulsCommitted", "displayValue": "12"},
          {"name": "wonCorners", "displayValue": "3"},
          {"name": "possessionPct", "displayValue": "52.8"},
          {"name": "totalShots", "displayValue": "11"},
          {"name": "shotsOnTarget", "displayValue": "5"}
        ]}
      ]}
    }
    """.utf8))

    // MARK: - Baseball

    @Test("MLB lines read runs and hits from batting, errors from fielding")
    func baseballStats() throws {
        let lines = parseBaseballGameTeamStats(from: Self.mlb)
        #expect(lines.count == 2)

        let whiteSox = try #require(lines.first { $0.homeAway == "away" })
        #expect(whiteSox.name == "White Sox")
        #expect(whiteSox.runs == 9)
        #expect(whiteSox.hits == 12)  // batting hits, not pitching's 1
        #expect(whiteSox.errors == 0)

        let royals = try #require(lines.first { $0.homeAway == "home" })
        #expect(royals.name == "Royals")
        #expect(royals.runs == 1)
        #expect(royals.hits == 7)
        #expect(royals.errors == 2)
    }

    @Test("A baseball group name picks its own stat when names collide")
    func statisticGroupSelects() {
        let teams = Self.mlb["boxscore", "teams", 0, "statistics"]
        #expect(boxscoreStatistic(teams, named: "hits", in: "batting")["displayValue"].intValue == 12)
        #expect(boxscoreStatistic(teams, named: "hits", in: "pitching")["displayValue"].intValue == 1)
        #expect(boxscoreStatistic(teams, named: "hits", in: "fielding")["displayValue"].intValue == 0)
        // An absent group reads as zero, not a crash.
        #expect(boxscoreStatistic(teams, named: "hits", in: "baserunning").isNull)
    }

    // MARK: - Soccer

    @Test("MLS lines read goals from the header by side, events from the box score")
    func soccerStats() throws {
        let lines = parseSoccerGameTeamStats(from: Self.mls)
        #expect(lines.count == 2)

        let kc = try #require(lines.first { $0.homeAway == "home" })
        #expect(kc.name == "Kansas City")
        #expect(kc.goals == 3)  // from the header competitor, not the box score
        #expect(kc.shots == 14)
        #expect(kc.possessionPct == 47.2)
        #expect(kc.corners == 6)

        let philly = try #require(lines.first { $0.homeAway == "away" })
        #expect(philly.goals == 4)
        #expect(philly.shots == 11)
        #expect(philly.corners == 3)
    }

    @Test("Soccer goals follow the side label, not the listing order")
    func soccerAttributionIsOrderIndependent() throws {
        // The MLS box score's teams array is in no guaranteed order; the
        // header walk must attribute goals by homeAway. Flip both listings
        // and each line must keep its own goals.
        let flipped = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "competitors": [
              {"homeAway": "away", "score": "4", "team": {"shortDisplayName": "Philadelphia"}},
              {"homeAway": "home", "score": "3", "team": {"shortDisplayName": "Kansas City"}}
            ]
          }]},
          "boxscore": {"teams": [
            {"homeAway": "away", "team": {"shortDisplayName": "Philadelphia"},
             "statistics": [{"name": "totalShots", "displayValue": "11"},
                            {"name": "possessionPct", "displayValue": "52.8"},
                            {"name": "wonCorners", "displayValue": "3"}]},
            {"homeAway": "home", "team": {"shortDisplayName": "Kansas City"},
             "statistics": [{"name": "totalShots", "displayValue": "14"},
                            {"name": "possessionPct", "displayValue": "47.2"},
                            {"name": "wonCorners", "displayValue": "6"}]}
          ]}
        }
        """.utf8))

        let lines = parseSoccerGameTeamStats(from: flipped)
        let kc = try #require(lines.first { $0.name == "Kansas City" })
        #expect(kc.goals == 3)
        #expect(kc.homeAway == "home")
        #expect(lines.first { $0.name == "Philadelphia" }?.goals == 4)
    }

    // MARK: - Basketball

    @Test("Basketball totals include every overtime period")
    func basketballOvertimeCounts() throws {
        // An abridged NCAA summary: Kansas (home) 90, Baylor (away) 87 after
        // one overtime. The header carries one line score per half plus one
        // per overtime; the old reader summed only the two halves (78-78).
        let overtime = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "status": {"type": {"completed": true, "detail": "Final/OT"}},
            "competitors": [
              {"homeAway": "home", "score": "90",
               "team": {"id": "2305", "name": "Jayhawks"},
               "linescores": [{"displayValue": "38"}, {"displayValue": "40"},
                              {"displayValue": "12"}]},
              {"homeAway": "away", "score": "87",
               "team": {"id": "239", "name": "Bears"},
               "linescores": [{"displayValue": "45"}, {"displayValue": "33"},
                              {"displayValue": "9"}]}
            ]
          }]},
          "boxscore": {"teams": [
            {"team": {"name": "Bears"}, "statistics": []},
            {"team": {"name": "Jayhawks"}, "statistics": []}
          ]}
        }
        """.utf8))

        let lines = parseBasketballGameTeamStats(from: overtime, team: .jayhawks)
        #expect(lines.count == 2)
        let line = try #require(lines.first)
        #expect(line.score == 90)
        #expect(line.opponentScore == 87)
        #expect(line.gameClock == "Final/OT")
    }

    @Test("A regulation basketball game still sums its two halves")
    func basketballRegulation() throws {
        // Jayhawks listed second: the side lookup must still find them.
        let regulation = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "competitors": [
              {"team": {"id": "2", "name": "Wildcats"},
               "linescores": [{"displayValue": "30"}, {"displayValue": "31"}]},
              {"team": {"id": "2305", "name": "Jayhawks"},
               "linescores": [{"displayValue": "35"}, {"displayValue": "37"}]}
            ]
          }]},
          "boxscore": {"teams": [
            {"team": {"name": "Wildcats"}, "statistics": []},
            {"team": {"name": "Jayhawks"}, "statistics": []}
          ]}
        }
        """.utf8))

        let line = try #require(parseBasketballGameTeamStats(from: regulation, team: .jayhawks).first)
        #expect(line.score == 72)
        #expect(line.opponentScore == 61)
    }

    // MARK: - Live score

    /// An abridged in-progress MLB summary header: Royals (home) 3, Tigers
    /// (away) 5. The summary header publishes `score` as a bare string; the
    /// `{"displayValue": ...}` wrapper only appears on the schedule feed.
    static let liveMLB = JSON(data: Data("""
    {
      "header": {"competitions": [{
        "status": {"type": {"name": "STATUS_IN_PROGRESS", "state": "in",
                            "completed": false, "detail": "Bot 6th"}},
        "competitors": [
          {"homeAway": "home", "score": "3", "winner": false,
           "team": {"displayName": "Kansas City Royals"}},
          {"homeAway": "away", "score": "5", "winner": false,
           "team": {"displayName": "Detroit Tigers"}}
        ]
      }]}
    }
    """.utf8))

    @Test("A live score reads the header's bare-string scores by side")
    func liveScoreFromBareStrings() throws {
        let home = try #require(parseLiveGameScore(from: Self.liveMLB, team: .royals, isHome: true))
        #expect(home.score == 3)
        #expect(home.opponentScore == 5)

        // The same document read for the away side swaps the pair.
        let away = try #require(parseLiveGameScore(from: Self.liveMLB, team: .royals, isHome: false))
        #expect(away.score == 5)
        #expect(away.opponentScore == 3)
    }

    @Test("A final summary reads its scores the same way")
    func liveScoreFromCompletedGame() throws {
        let finished = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "status": {"type": {"name": "STATUS_FINAL", "state": "post",
                                "completed": true, "detail": "Final"}},
            "competitors": [
              {"homeAway": "home", "score": "24", "winner": true,
               "team": {"displayName": "Kansas City Chiefs"}},
              {"homeAway": "away", "score": "17", "winner": false,
               "team": {"displayName": "Denver Broncos"}}
            ]
          }]}
        }
        """.utf8))
        let score = try #require(parseLiveGameScore(from: finished, team: .chiefs, isHome: true))
        #expect(score.score == 24)
        #expect(score.opponentScore == 17)
    }

    @Test("A score wrapped in a displayValue object still reads")
    func liveScoreFromWrappedScore() throws {
        let wrapped = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "competitors": [
              {"homeAway": "home", "score": {"value": 2.0, "displayValue": "2"}},
              {"homeAway": "away", "score": {"value": 1.0, "displayValue": "1"}}
            ]
          }]}
        }
        """.utf8))
        let score = try #require(parseLiveGameScore(from: wrapped, team: .sporting, isHome: true))
        #expect(score.score == 2)
        #expect(score.opponentScore == 1)
    }

    @Test("A missing score reads as no live score, not 0–0")
    func liveScoreMissing() {
        // The polling loop keeps its last known figures when this is nil;
        // a zero here would overwrite them.
        let partial = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "competitors": [
              {"homeAway": "home", "score": "3"},
              {"homeAway": "away"}
            ]
          }]}
        }
        """.utf8))
        #expect(parseLiveGameScore(from: partial, team: .royals, isHome: true) == nil)
        #expect(parseLiveGameScore(from: JSON(data: Data()), team: .royals, isHome: true) == nil)
    }

    // MARK: - Degenerate documents

    @Test("A failed fetch parses to no lines rather than trapping")
    func missingDocuments() {
        let null = JSON(data: Data())
        #expect(parseBaseballGameTeamStats(from: null).isEmpty)
        #expect(parseSoccerGameTeamStats(from: null).isEmpty)
    }

    @Test("A pre-game summary parses to no lines")
    func noBoxscoreYet() {
        // A scheduled game's summary carries a header but no box score; the
        // detail view's `first(where:)` lookups must find nothing so its
        // "no statistics yet" branch renders.
        let headerOnly = JSON(data: Data("""
        {
          "header": {"competitions": [{
            "status": {"type": {"detail": "Scheduled"}},
            "competitors": [
              {"homeAway": "home", "score": "0", "team": {"shortDisplayName": "Royals"}},
              {"homeAway": "away", "score": "0", "team": {"shortDisplayName": "Pirates"}}
            ]
          }]}
        }
        """.utf8))
        #expect(parseBaseballGameTeamStats(from: headerOnly).isEmpty)
        #expect(parseSoccerGameTeamStats(from: headerOnly).isEmpty)
    }

    // MARK: - Detail sheet polling

    /// A summary whose header status carries `state` and `completed`.
    private func summary(state: String, completed: Bool) -> JSON {
        JSON(data: Data("""
        {"header": {"competitions": [{"status": {"type": {
          "state": "\(state)", "completed": \(completed)
        }}}]}}
        """.utf8))
    }

    @Test("The summary header's status decides the game phase")
    func gamePhase() {
        #expect(parseGamePhase(from: summary(state: "pre", completed: false)) == .pre)
        #expect(parseGamePhase(from: summary(state: "in", completed: false)) == .live)
        #expect(parseGamePhase(from: summary(state: "post", completed: true)) == .final)
        // A postponed game ends up "post" without ever completing.
        #expect(parseGamePhase(from: summary(state: "post", completed: false)) == .final)
        #expect(parseGamePhase(from: JSON(data: Data())) == .unknown)
    }

    @Test("Detail sheets poll live games, slow down pre-game and stop once final")
    func detailRefreshInterval() {
        func interval(_ json: JSON) -> Duration? {
            GameDetail<SoccerGameTeamStats>(json: json, team: .sporting, stats: []).refreshInterval
        }
        #expect(interval(summary(state: "in", completed: false)) == .seconds(10))
        #expect(interval(summary(state: "pre", completed: false)) == .seconds(60))
        #expect(interval(summary(state: "post", completed: true)) == nil)
        // No status is not "in progress": it is not polled at the live rate.
        #expect(interval(JSON(data: Data())) == .seconds(60))
    }

    @Test("Halftime, delays and suspensions pause the ten-second refresh")
    func pausedGames() {
        func summary(name: String) -> JSON {
            JSON(data: Data("""
            {"header": {"competitions": [{"status": {"type": {
              "name": "\(name)", "state": "in", "completed": false
            }}}]}}
            """.utf8))
        }
        for name in ["STATUS_HALFTIME", "STATUS_DELAYED", "STATUS_RAIN_DELAY", "STATUS_SUSPENDED"] {
            let paused = summary(name: name)
            #expect(parseGamePhase(from: paused) == .paused)
            #expect(GameDetail<SoccerGameTeamStats>(json: paused, team: .sporting, stats: []).refreshInterval == .seconds(60))
        }
        #expect(parseGamePhase(from: summary(name: "STATUS_IN_PROGRESS")) == .live)
        #expect(parseGamePhase(from: summary(name: "STATUS_END_PERIOD")) == .live)
    }
}

/// The game sheet draws every sport from one `BoxScore`: home score on the
/// left, then rows with the home side first. These pin what each sport's
/// typed lines reduce to, using the golden fixtures.
@Suite("Detail-sheet box score")
struct DetailSheetBoxScoreTests {
    private func row(_ boxScore: BoxScore, _ title: String) -> BoxScore.Row? {
        boxScore.rows.first { $0.title == title }
    }

    @Test("Basketball: lines are away then home; the scoreline follows gameHome")
    func basketball() throws {
        let lines = parseBasketballGameTeamStats(from: try Fixture.json("jayhawks_summary_final_401851305"), team: .jayhawks)
        // KU (47) is listed away at a neutral site; Houston (69) is home.
        let boxScore = try #require(BoxScore(basketball: lines, followedIsHome: false))
        #expect(boxScore.homeScore == 69)
        #expect(boxScore.awayScore == 47)
        #expect(boxScore.rows.map(\.title) == [
            "Field Goals", "Field Goal %", "Three Points", "Three Point %",
            "Free Throws", "Free Throw %", "Offensive Rebounds", "Defensive Rebounds",
            "Assists", "Blocks", "Steals", "Turnovers", "Fouls",
        ])
        #expect(row(boxScore, "Field Goals") == BoxScore.Row(title: "Field Goals", home: "22/53", away: "14/57"))
        #expect(row(boxScore, "Three Points") == BoxScore.Row(title: "Three Points", home: "10/18", away: "7/23"))
        #expect(row(boxScore, "Defensive Rebounds") == BoxScore.Row(title: "Defensive Rebounds", home: "32", away: "22"))

        #expect(BoxScore(basketball: Array(lines.prefix(1)), followedIsHome: true) == nil)
    }

    @Test("Football: the followed team's score lands on its own side")
    func football() throws {
        let lines = parseFootballGameTeamStats(from: try Fixture.json("chiefs_summary_final_401872945"), team: .chiefs)
        // Colts (30) away in lines[0], Chiefs (33) home in lines[1].
        let boxScore = try #require(BoxScore(football: lines, followedIsHome: true))
        #expect(boxScore.homeScore == 33)
        #expect(boxScore.awayScore == 30)
        #expect(boxScore.rows.map(\.title) == [
            "Total Yards", "Passing Yards", "Rushing Yards", "First Downs",
            "Drives", "Interceptions", "Possession Time", "Completion Attempts",
        ])
        #expect(row(boxScore, "Total Yards") == BoxScore.Row(title: "Total Yards", home: "523", away: "329"))
        #expect(row(boxScore, "Possession Time") == BoxScore.Row(title: "Possession Time", home: "37:00", away: "33:00"))
    }

    @Test("Baseball: sides come from each line's homeAway")
    func baseball() throws {
        let lines = parseBaseballGameTeamStats(from: try Fixture.json("royals_summary_final_401817094"))
        let boxScore = try #require(BoxScore(baseball: lines))
        #expect(boxScore.homeScore == 5)  // Royals
        #expect(boxScore.awayScore == 11)  // Guardians
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Runs", home: "5", away: "11"),
            BoxScore.Row(title: "Hits", home: "10", away: "14"),
            BoxScore.Row(title: "Errors", home: "2", away: "1"),
        ])

        #expect(BoxScore(baseball: lines.filter { $0.homeAway == "home" }) == nil)
    }

    @Test("Soccer: possession rounds to a whole percentage")
    func soccer() throws {
        let lines = parseSoccerGameTeamStats(from: try Fixture.json("sporting_summary_final_761450"))
        let boxScore = try #require(BoxScore(soccer: lines))
        #expect(boxScore.homeScore == 3)  // San Jose
        #expect(boxScore.awayScore == 0)  // Kansas City
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Goals", home: "3", away: "0"),
            BoxScore.Row(title: "Shots", home: "17", away: "7"),
            BoxScore.Row(title: "Possession", home: "44%", away: "56%"),
            BoxScore.Row(title: "Corner Kicks", home: "15", away: "3"),
        ])
    }

    // MARK: One fetch per refresh

    @Test("One summary request fills the box score, the venue and the phase")
    func oneFetchPerRefresh() async throws {
        let transport = RecordingTransport(always: try .fixture("chiefs_summary_live_401872952"))
        let load = await LeagueDescriptor.nfl.downloadGameSheet(
            gameID: "401872952",
            team: .chiefs,
            followedIsHome: false,
            client: HTTPClient(transport: transport)
        )

        #expect(transport.requestCount == 1)
        #expect(transport.urls.first?.absoluteString
            == "https://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event=401872952")

        let sheet = try #require(load.sheet)
        // The box score (boxscore.teams, header scores)…
        let boxScore = try #require(sheet.boxScore)
        #expect(boxScore.homeScore == 7)  // Dolphins
        #expect(boxScore.awayScore == 7)  // Chiefs
        #expect(row(boxScore, "Total Yards") == BoxScore.Row(title: "Total Yards", home: "101", away: "123"))
        // …and the venue (gameInfo.venue.address) come from the same document.
        #expect(sheet.info.city == "Miami Gardens")
        #expect(sheet.info.state == "FL")
        #expect(sheet.phase == .live)
        #expect(sheet.refreshInterval == .seconds(10))
    }

    @Test("A throttled refresh keeps no sheet and carries the response for pacing")
    func throttledRefresh() async {
        let transport = RecordingTransport(always: .status(429, headers: ["Retry-After": "90"]))
        let load = await LeagueDescriptor.nfl.downloadGameSheet(
            gameID: "401872952", team: .chiefs, followedIsHome: false,
            client: HTTPClient(transport: transport)
        )
        #expect(load.sheet == nil)
        #expect(load.response.isThrottled)

        var backoff = PollBackoff(base: GameSheet.retryInterval)
        #expect(backoff.delay(after: load.response) == .seconds(90))
        #expect(backoff.delay(after: FetchResponse(result: .failure(.httpError(status: 429)))) == .seconds(120))
    }
}
