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
}
