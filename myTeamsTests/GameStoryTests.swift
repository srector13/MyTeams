//
//  GameStoryTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// A team known only by league and id, as a favorite the catalog has not
/// named yet.
private func followed(_ league: LeagueID, _ espnID: String) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: espnID, shortName: espnID, abbreviation: "", location: "",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

private func story(_ fixture: String) throws -> GameStory {
    GameStory(summary: try Fixture.json(fixture))
}

// MARK: - Timeline

@Suite("Game story timeline")
struct GameStoryTimelineTests {
    /// chiefs_summary_final_401872945: Colts (away, 11) at Chiefs (home, 12),
    /// 33–30 in overtime. Football reads `scoringPlays`.
    @Test("NFL: scoringPlays, in order, with running score and points")
    func nfl() throws {
        let story = try story("chiefs_summary_final_401872945")
        let timeline = story.timeline
        #expect(timeline.count == 13)

        let first = try #require(timeline.first)
        #expect(first.period == 1)
        #expect(first.periodLabel == "")
        #expect(first.clock == "8:25")
        #expect(first.teamID == "11")
        #expect(first.homeAway == "away")
        #expect(first.kind == .score)
        #expect(first.text == "Tyler Warren 1 Yd pass from Daniel Jones (Spencer Shrader Kick)")
        #expect(first.homeScore == 0)
        #expect(first.awayScore == 7)
        #expect(first.points == 7)
        #expect(first.athleteIDs.isEmpty)

        let last = try #require(timeline.last)
        #expect(last.period == 5)
        #expect(last.clock == "0:00")
        #expect(last.teamID == "12")
        #expect(last.homeAway == "home")
        // The feed's trailing space is trimmed.
        #expect(last.text == "Harrison Butker 40 Yd Field Goal")
        #expect(last.homeScore == 33)
        #expect(last.awayScore == 30)
        #expect(last.points == 3)

        #expect(story.abbreviation(teamID: "12") == "KC")
        #expect(story.homeAbbreviation == "KC")
    }

    /// nba_summary_final_401811028: Cavaliers (away, 5) at Hawks (home, 1),
    /// 124–102. Basketball reads `plays` filtered to `scoringPlay`.
    @Test("NBA: scoring plays from plays, with athletes and period names")
    func nba() throws {
        let timeline = try story("nba_summary_final_401811028").timeline
        #expect(timeline.count == 119)

        let first = try #require(timeline.first)
        #expect(first.period == 1)
        #expect(first.periodLabel == "1st Quarter")
        #expect(first.clock == "11:45")
        #expect(first.teamID == "5")
        #expect(first.homeAway == "away")
        #expect(first.text == "Evan Mobley makes 6-foot layup (James Harden assists)")
        #expect(first.athleteIDs == ["4432158", "3992"])
        #expect(first.homeScore == 0)
        #expect(first.awayScore == 2)
        #expect(first.points == 2)

        let last = try #require(timeline.last)
        #expect(last.periodLabel == "4th Quarter")
        #expect(last.clock == "47.2")
        #expect(last.text == "Corey Kispert makes free throw 2 of 3")
        #expect(last.homeScore == 124)
        #expect(last.awayScore == 102)
        #expect(last.points == 1)
    }

    /// royals_summary_final_401817094: Guardians (away, 5) won 11–5 at the
    /// Royals (home, 7). Baseball has no clock; the half names the period.
    @Test("MLB: scoring plays with the inning's half, no clock, repeat athletes dropped")
    func mlb() throws {
        let timeline = try story("royals_summary_final_401817094").timeline
        #expect(timeline.count == 15)

        let first = try #require(timeline.first)
        #expect(first.periodLabel == "Bottom 1st Inning")
        #expect(first.clock == "")
        #expect(first.teamID == "7")
        #expect(first.homeAway == "home")
        #expect(first.text == "Jensen scored on throwing error by catcher Bailey, Witt Jr. stole third.")
        #expect(first.homeScore == 1)
        #expect(first.awayScore == 0)

        let last = try #require(timeline.last)
        #expect(last.period == 9)
        #expect(last.periodLabel == "Top 9th Inning")
        #expect(last.text == "Lowe singled to left, Adell scored and Ramírez scored, Genao to second.")
        #expect(last.homeScore == 5)
        #expect(last.awayScore == 11)
        #expect(last.points == 2)
        // The feed lists 40538 twice (batter and runner).
        #expect(last.athleteIDs == ["5136077", "40538", "5204351"])
    }

    /// ncaaf_summary_final_401856769: home 2305 won 51–6 over 2341.
    @Test("NCAAF: scoringPlays")
    func ncaaf() throws {
        let timeline = try story("ncaaf_summary_final_401856769").timeline
        #expect(timeline.count == 10)

        let first = try #require(timeline.first)
        #expect(first.period == 1)
        #expect(first.clock == "5:59")
        #expect(first.teamID == "2305")
        #expect(first.homeAway == "home")
        #expect(first.text == "Yasin Willis 5 Yd Run (Two-Point Pass Conversion Failed)")
        #expect(first.homeScore == 6)
        #expect(first.awayScore == 0)
        #expect(first.points == 6)

        let last = try #require(timeline.last)
        #expect(last.period == 4)
        #expect(last.clock == "1:56")
        #expect(last.teamID == "2341")
        #expect(last.text == "Will Johnson 39 Yd Field Goal")
        #expect(last.homeScore == 51)
        #expect(last.awayScore == 6)
        #expect(last.points == 3)
    }

    /// epl_summary_final_401879301: Arsenal (home, 359) 3–0 Coventry City
    /// (away, 388). Soccer reads `keyEvents`: three goals and two yellow
    /// cards; substitutions, kick-off and delays are left out.
    @Test("EPL: keyEvents goals and cards, running score counted by team id")
    func epl() throws {
        let timeline = try story("epl_summary_final_401879301").timeline
        #expect(timeline.map(\.kind) == [.score, .score, .yellowCard, .yellowCard, .score])
        #expect(timeline.map(\.clock) == ["15'", "23'", "27'", "34'", "49'"])

        let first = try #require(timeline.first)
        #expect(first.period == 1)
        #expect(first.teamID == "359")
        #expect(first.homeAway == "home")
        #expect(first.text.hasPrefix("Goal! Arsenal 1, Coventry City 0. Kai Havertz (Arsenal)"))
        #expect(first.athleteIDs == ["231182", "298329"])
        #expect(first.homeScore == 1)
        #expect(first.awayScore == 0)
        #expect(first.points == 1)

        let card = timeline[2]
        #expect(card.teamID == "388")
        #expect(card.homeAway == "away")
        #expect(card.text == "Caleb Yirenkyi (Coventry City) is shown the yellow card for a bad foul.")
        #expect(card.homeScore == nil)
        #expect(card.points == nil)

        let last = try #require(timeline.last)
        #expect(last.period == 2)
        #expect(last.homeScore == 3)
        #expect(last.awayScore == 0)
    }

    /// The goals counted from `keyEvents` add up to the header's score in
    /// every soccer fixture.
    @Test("Soccer: counted goals match the final score", arguments: [
        ("bundes_summary_final_401884790", 7, 0),
        ("laliga_summary_final_401882926", 3, 0),
        ("ligamx_summary_final_401877018", 0, 0),
        ("ligue1_summary_final_401876449", 1, 2),
        ("nwsl_summary_final_401853969", 2, 1),
        ("premiere_summary_final_401885704", 5, 0),
        ("seriea_summary_final_401874753", 2, 2),
        ("sporting_summary_final_761450", 3, 0),
        ("uclleague_summary_final_401915423", 0, 1),
        ("wsl_summary_final_401902895", 0, 3),
    ] as [(String, Int, Int)])
    func soccerScores(fixture: String, home: Int, away: Int) throws {
        let goals = try story(fixture).timeline.filter { $0.kind == .score }
        #expect(goals.count == home + away)
        #expect((goals.last?.homeScore ?? 0) == home)
        #expect((goals.last?.awayScore ?? 0) == away)
    }

    /// nhl_summary_final_401881922: Canadiens (away, 10) won 4–1 at Toronto.
    @Test("NHL: goals from plays")
    func nhl() throws {
        let timeline = try story("nhl_summary_final_401881922").timeline
        #expect(timeline.count == 5)
        let first = try #require(timeline.first)
        #expect(first.periodLabel == "2nd")
        #expect(first.clock == "0:51")
        #expect(first.teamID == "10")
        #expect(first.athleteIDs.first == "2562602")
        #expect(timeline.last?.homeScore == 1)
        #expect(timeline.last?.awayScore == 4)
    }
}

// MARK: - Win probability

@Suite("Game story win probability")
struct GameStoryWinProbabilityTests {
    @Test("Final summaries: every point, first and last", arguments: [
        ("chiefs_summary_final_401872945", 211, 0.7693, 1.0),
        ("nba_summary_final_401811028", 473, 0.506, 1.0),
        ("royals_summary_final_401817094", 81, 0.531, 0.0),
        ("ncaaf_summary_final_401856769", 173, 0.9902, 1.0),
        ("wnba_summary_final_401857143", 396, 0.65, 1.0),
    ] as [(String, Int, Double, Double)])
    func finals(fixture: String, count: Int, first: Double, last: Double) throws {
        let points = try story(fixture).winProbability
        #expect(points.count == count)
        #expect(points.first?.homeWinPercentage == first)
        #expect(points.last?.homeWinPercentage == last)
        #expect(points.map(\.index) == Array(0..<count))
    }

    @Test("Soccer and hockey carry none")
    func none() throws {
        #expect(try story("epl_summary_final_401879301").winProbability.isEmpty)
        #expect(try story("nhl_summary_final_401881922").winProbability.isEmpty)
    }
}

// MARK: - Injuries

@Suite("Game story injuries")
struct GameStoryInjuryTests {
    @Test("NFL: both teams, home first, status and details")
    func nfl() throws {
        let injuries = try story("chiefs_summary_final_401872945").injuries
        #expect(injuries.map(\.teamID) == ["12", "11"])
        #expect(injuries.map(\.homeAway) == ["home", "away"])
        #expect(injuries.map(\.injuries.count) == [5, 5])

        let home = injuries[0]
        #expect(home.name == "Kansas City Chiefs")
        let smith = try #require(home.injuries.first)
        #expect(smith.athleteID == "4361340")
        #expect(smith.name == "Tyreke Smith")
        #expect(smith.position == "DE")
        #expect(smith.status == "Out")
        #expect(smith.injury == "Coach's Decision")
        // "Not Specified" reads as nothing.
        #expect(smith.detail == "")

        let caldwell = try #require(home.injuries.last)
        #expect(caldwell.name == "Jeff Caldwell")
        #expect(caldwell.status == "Injured Reserve")
        #expect(caldwell.injury == "Knee")
        #expect(caldwell.detail == "Soreness")
        #expect(caldwell.side == "Left")
        #expect(caldwell.returnDate == "2027-02-15")

        let away = injuries[1]
        #expect(away.name == "Indianapolis Colts")
        #expect(away.injuries.first?.name == "Darius Slayton")
        #expect(away.injuries.first?.position == "WR")
        #expect(away.injuries.first?.status == "Out")
    }

    @Test("NBA: uneven reports")
    func nba() throws {
        let injuries = try story("nba_summary_final_401811028").injuries
        #expect(injuries.map(\.teamID) == ["1", "5"])
        #expect(injuries.map(\.injuries.count) == [4, 1])
        let veesaar = try #require(injuries[0].injuries.first)
        #expect(veesaar.name == "Henri Veesaar")
        #expect(veesaar.position == "C")
        #expect(veesaar.status == "Out")
        #expect(veesaar.returnDate == "2027-07-01")
        #expect(injuries[1].injuries.first?.name == "Peyton Watson")
        #expect(injuries[1].injuries.first?.status == "Day-To-Day")
    }

    @Test("MLB: statuses as the feed writes them")
    func mlb() throws {
        let injuries = try story("royals_summary_final_401817094").injuries
        #expect(injuries.map(\.teamID) == ["7", "5"])
        #expect(injuries.map(\.injuries.count) == [5, 2])
        #expect(injuries[0].injuries.first?.name == "Steven Cruz")
        #expect(injuries[0].injuries.first?.position == "RP")
        #expect(injuries[0].injuries.first?.status == "Paternity")
        #expect(injuries[1].injuries.first?.name == "Rhys Hoskins")
        #expect(injuries[1].injuries.first?.status == "10-Day-IL")
    }

    @Test("NCAAF and soccer carry none")
    func none() throws {
        #expect(try story("ncaaf_summary_final_401856769").injuries.isEmpty)
        #expect(try story("epl_summary_final_401879301").injuries.isEmpty)
    }
}

// MARK: - Pre-game and empty documents

@Suite("Game story before kick-off")
struct GameStoryPregameTests {
    @Test("Pre-game summaries: injuries only, no timeline or win probability", arguments: [
        "royals_summary_pregame_401817109",
        "chiefs_summary_pregame_401872976",
        "nba_summary_pregame_401902644",
    ])
    func pregame(fixture: String) throws {
        let story = try story(fixture)
        #expect(story.timeline.isEmpty)
        #expect(story.winProbability.isEmpty)
        #expect(story.injuries.count == 2)
        #expect(!story.isEmpty)
    }

    @Test("Royals pre-game: the injury report")
    func royalsPregame() throws {
        let injuries = try story("royals_summary_pregame_401817109").injuries
        #expect(injuries.map(\.teamID) == ["7", "5"])
        #expect(injuries.map(\.injuries.count) == [5, 2])
        #expect(injuries[1].injuries.last?.name == "Colin Holderman")
        #expect(injuries[1].injuries.last?.status == "15-Day-IL")
    }

    @Test("NCAAW pre-game: an empty story")
    func ncaawPregame() throws {
        #expect(try story("ncaaw_summary_pregame_401926040").isEmpty)
    }

    @Test("A document with none of the lists")
    func emptyDocument() {
        #expect(GameStory(summary: JSON.null).isEmpty)
        #expect(GameStory(summary: JSON.null) == .empty)
    }
}

// MARK: - The sheet

@Suite("Game sheet story")
struct GameSheetStoryTests {
    @Test("gameSheet carries the story for every sport")
    func sheet() throws {
        let nfl = LeagueDescriptor.nfl.gameSheet(
            from: try Fixture.json("chiefs_summary_final_401872945"),
            team: followed(.nfl, "12"), followedIsHome: true
        )
        #expect(nfl.story.timeline.count == 13)
        #expect(nfl.story.winProbability.count == 211)

        let epl = LeagueDescriptor.premierLeague.gameSheet(
            from: try Fixture.json("epl_summary_final_401879301"),
            team: followed(LeagueDescriptor.premierLeague.id, "359"), followedIsHome: true
        )
        #expect(epl.story.timeline.count == 5)
    }

    @Test("A timeline athlete resolves to the soccer lineup's player")
    func soccerPlayer() throws {
        let json = try Fixture.json("epl_summary_final_401879301")
        let lineups = try #require(SoccerLineups(summary: json))
        let scorer = try #require(GameStory(summary: json).timeline.first?.athleteIDs.first)
        let player = try #require(GameSheetPlayer(athleteID: scorer, soccerLineups: lineups, hockey: nil))
        #expect(player.id == "231182")
        guard case .soccer = player else {
            Issue.record("expected a soccer player")
            return
        }
    }

    @Test("A timeline athlete resolves to the hockey box score's skater")
    func hockeyPlayer() throws {
        let json = try Fixture.json("nhl_summary_final_401881922")
        let hockey = try #require(HockeyBoxScore(summary: json))
        let scorer = try #require(GameStory(summary: json).timeline.first?.athleteIDs.first)
        let player = try #require(GameSheetPlayer(athleteID: scorer, soccerLineups: nil, hockey: hockey))
        #expect(player.id == "2562602")
        guard case .hockey = player else {
            Issue.record("expected a hockey player")
            return
        }
    }

    @Test("An athlete no table lists opens nothing")
    func unknownPlayer() throws {
        let hockey = try #require(HockeyBoxScore(summary: try Fixture.json("nhl_summary_final_401881922")))
        #expect(GameSheetPlayer(athleteID: "0", soccerLineups: nil, hockey: hockey) == nil)
        #expect(GameSheetPlayer(athleteID: "", soccerLineups: nil, hockey: hockey) == nil)
    }
}
