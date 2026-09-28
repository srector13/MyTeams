//
//  SportBoxScoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
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

/// nhl_summary_final_401881922.json: Montreal (away, team 10) won 4–1 at
/// Toronto (home, team 21), preseason, September 19 2026.
private func nhlSummary() throws -> JSON {
    try Fixture.json("nhl_summary_final_401881922")
}

// MARK: - Hockey box score

@Suite("Hockey box score")
struct HockeyBoxScoreTests {
    @Test("Sides, names and scores come from homeAway and the header")
    func sides() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))

        // boxscore.teams lists Montreal (away) first; home is still Toronto.
        #expect(boxScore.home.teamID == "21")
        #expect(boxScore.home.name == "Maple Leafs")
        #expect(boxScore.home.abbreviation == "TOR")
        #expect(boxScore.home.score == 1)
        #expect(boxScore.away.teamID == "10")
        #expect(boxScore.away.name == "Canadiens")
        #expect(boxScore.away.score == 4)
        #expect(boxScore.teams.map(\.homeAway) == ["home", "away"])
    }

    @Test("Player groups split into forwards, defense and goalies by group name")
    func groups() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))
        for team in boxScore.teams {
            // "forwards" 12, "defenses" 6, "skaters" empty, "goalies" 2.
            #expect(team.forwards.count == 12)
            #expect(team.defense.count == 6)
            #expect(team.goalies.count == 2)
            #expect(team.defense.allSatisfy { $0.position == "D" })
            #expect(team.forwards.allSatisfy { ["C", "LW", "RW"].contains($0.position) })
        }
    }

    @Test("A forward's line reads by key: G, A, P, TOI, +/-, S, PIM")
    func forward() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))
        let danault = try #require(boxScore.away.forwards.first { $0.name == "Phillip Danault" })
        #expect(danault.athleteID == "2562602")
        #expect(danault.shortName == "P. Danault")
        #expect(danault.jersey == "24")
        #expect(danault.position == "C")
        #expect(danault.goals == 2)
        #expect(danault.assists == 0)
        #expect(danault.points == 2)
        #expect(danault.timeOnIce == "18:00")
        #expect(danault.plusMinus == 2)
        #expect(danault.shots == 4)
        #expect(danault.penaltyMinutes == 0)

        // A fighting major and a minor: 7 PIM on a 1-assist night.
        let xhekaj = try #require(boxScore.away.forwards.first { $0.name == "Florian Xhekaj" })
        #expect(xhekaj.assists == 1)
        #expect(xhekaj.points == 1)
        #expect(xhekaj.penaltyMinutes == 7)
        #expect(xhekaj.timeOnIce == "11:59")
    }

    @Test("A defenseman's minus reads negative")
    func defenseman() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))
        let raddysh = try #require(boxScore.home.defense.first { $0.name == "Darren Raddysh" })
        #expect(raddysh.jersey == "43")
        #expect(raddysh.goals == 1)
        #expect(raddysh.assists == 0)
        #expect(raddysh.plusMinus == -2)
        #expect(raddysh.timeOnIce == "24:05")
        #expect(raddysh.shots == 1)
        #expect(raddysh.penaltyMinutes == 2)
    }

    @Test("Goalies read their own keys: SA, SV, GA, SV%, TOI")
    func goalies() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))

        // Montreal split the game; the goalie list's keys are not a
        // skater's (goalsAgainst, shotsAgainst, … saves, savePct …).
        let montembeault = try #require(boxScore.away.goalies.first { $0.name == "Sam Montembeault" })
        #expect(montembeault.shotsAgainst == 13)
        #expect(montembeault.saves == 13)
        #expect(montembeault.goalsAgainst == 0)
        #expect(montembeault.savePct == "1.000")
        #expect(montembeault.timeOnIce == "31:19")

        let kahkonen = try #require(boxScore.away.goalies.first { $0.name == "Kaapo Kahkonen" })
        #expect(kahkonen.shotsAgainst == 12)
        #expect(kahkonen.saves == 11)
        #expect(kahkonen.goalsAgainst == 1)
        #expect(kahkonen.savePct == ".917")

        let stolarz = try #require(boxScore.home.goalies.first { $0.name == "Anthony Stolarz" })
        #expect(stolarz.shotsAgainst == 17)
        #expect(stolarz.saves == 15)
        #expect(stolarz.goalsAgainst == 2)
        #expect(stolarz.savePct == ".882")
        #expect(stolarz.timeOnIce == "30:20")
    }

    @Test("Skaters' goals add up to each side's score")
    func goalsMatchScore() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))
        for team in boxScore.teams {
            let goals = (team.forwards + team.defense).reduce(0) { $0 + $1.goals }
            #expect(goals == team.score)
        }
    }

    @Test("Team statistics: shots, power play, faceoffs, hits, PIM, blocks")
    func teamStats() throws {
        let boxScore = try #require(HockeyBoxScore(summary: nhlSummary()))
        #expect(boxScore.home.stats == HockeyBoxScore.TeamStats(
            shots: 25, powerPlayGoals: 1, powerPlayOpportunities: 6, powerPlayPct: "16.7",
            faceoffsWon: 20, faceoffPct: "45.5", hits: 27, penaltyMinutes: 11, blockedShots: 15
        ))
        #expect(boxScore.away.stats == HockeyBoxScore.TeamStats(
            shots: 29, powerPlayGoals: 0, powerPlayOpportunities: 3, powerPlayPct: "0.0",
            faceoffsWon: 24, faceoffPct: "54.5", hits: 24, penaltyMinutes: 17, blockedShots: 11
        ))
    }

    @Test("The comparison strip puts home first")
    func comparisonStrip() throws {
        let boxScore = BoxScore(hockey: try #require(HockeyBoxScore(summary: nhlSummary())))
        #expect(boxScore.homeScore == 1)
        #expect(boxScore.awayScore == 4)
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Shots", home: "25", away: "29"),
            BoxScore.Row(title: "Power Play", home: "1/6", away: "0/3"),
            BoxScore.Row(title: "Power Play %", home: "16.7%", away: "0.0%"),
            BoxScore.Row(title: "Faceoffs Won", home: "20", away: "24"),
            BoxScore.Row(title: "Faceoff %", home: "45.5%", away: "54.5%"),
            BoxScore.Row(title: "Hits", home: "27", away: "24"),
            BoxScore.Row(title: "Penalty Minutes", home: "11", away: "17"),
            BoxScore.Row(title: "Blocked Shots", home: "15", away: "11"),
        ])
    }

    @Test("Stats are zipped with keys by name, whatever order the keys come in")
    func keyOrderIndependent() throws {
        // The goalie group with its keys (and every athlete's stats)
        // reversed must read the same figures.
        let summary = try nhlSummary()
        let group = summary["boxscore", "players", 0, "statistics", 3]
        try #require(group["name"].stringValue == "goalies")

        func backwards(_ node: JSON) -> JSON { .array(Array(node.arrayValue.reversed())) }
        var flipped = group.setting(["keys"], to: backwards(group["keys"]))
        for index in group["athletes"].arrayValue.indices {
            let path: [JSON.Index] = ["athletes", .index(index), "stats"]
            flipped = flipped.setting(path, to: backwards(group[path]))
        }

        let original = BoxscorePlayerGroup(group)
        let shuffled = BoxscorePlayerGroup(flipped)
        #expect(shuffled.name == "goalies")
        #expect(shuffled.entries.map(\.stats) == original.entries.map(\.stats))
        #expect(shuffled.entries.first?.int("saves") == 13)
    }

    @Test("An athlete with no stats (a scratch) is left out; missing keys read zero")
    func scratchesAndMissingKeys() {
        let group = BoxscorePlayerGroup(JSON(data: Data("""
        {"name": "forwards", "keys": ["goals", "assists"],
         "athletes": [
           {"athlete": {"id": "1", "displayName": "Played"}, "stats": ["1", "2"]},
           {"athlete": {"id": "2", "displayName": "Scratched"}, "stats": []}
         ]}
        """.utf8)))
        #expect(group.entries.count == 1)
        #expect(group.entries[0].int("goals") == 1)
        #expect(group.entries[0].int("penaltyMinutes") == 0)
        #expect(group.entries[0].string("timeOnIce") == "")
    }

    @Test("A summary without both sides has no hockey box score")
    func missingSides() {
        #expect(HockeyBoxScore(summary: JSON(data: Data())) == nil)
        #expect(HockeyBoxScore(summary: JSON(data: Data("""
        {"boxscore": {"teams": [{"homeAway": "home", "team": {"id": "21"}}]}}
        """.utf8))) == nil)
    }

    @Test("An NHL summary fills the hockey sheet: strip, tables and a 3-period linescore")
    func gameSheet() async throws {
        let transport = RecordingTransport(always: try .fixture("nhl_summary_final_401881922"))
        let load = await LeagueDescriptor.nhl.downloadGameSheet(
            gameID: "401881922",
            team: followed(.nhl, "10"),
            followedIsHome: false,
            client: HTTPClient(transport: transport)
        )

        #expect(transport.requestCount == 1)
        #expect(transport.urls.first?.absoluteString
            == "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=401881922")

        let sheet = try #require(load.sheet)
        #expect(sheet.boxScore?.homeScore == 1)
        #expect(sheet.boxScore?.awayScore == 4)
        #expect(sheet.hockey?.away.forwards.count == 12)
        #expect(sheet.linescore?.periodLabels == ["1", "2", "3"])
        #expect(sheet.soccerLineups == nil)
        #expect(sheet.phase == .final)
        #expect(sheet.refreshInterval == nil)
    }
}

// MARK: - Linescore

@Suite("Linescore period counts")
struct LinescoreTests {
    @Test("NHL renders 3 periods from its format; NBA 4 from the same code path")
    func periodCountFromFormat() throws {
        // format.regulation.periods is 3 for the NHL summary…
        let nhl = try #require(Linescore(summary: nhlSummary(), league: .nhl))
        #expect(nhl.periodCount == 3)
        #expect(nhl.periodLabels == ["1", "2", "3"])
        #expect(nhl.home == Linescore.Line(homeAway: "home", abbreviation: "TOR", periods: ["0", "1", "0"], total: "1"))
        #expect(nhl.away == Linescore.Line(homeAway: "away", abbreviation: "MTL", periods: ["0", "1", "3"], total: "4"))

        // …and 4 for the NBA one, a pre-game summary with no period scored
        // yet: every column is still drawn, empty.
        let nba = try #require(Linescore(summary: Fixture.json("nba_summary_pregame_401902644"), league: .nba))
        #expect(nba.periodCount == 4)
        #expect(nba.periodLabels == ["1", "2", "3", "4"])
        #expect(nba.home.abbreviation == "TOR")
        #expect(nba.home.periods == ["-", "-", "-", "-"])
        #expect(nba.home.total == "-")  // the header has no score yet
    }

    @Test("The format decides the count even against the registry's style")
    func formatBeatsRegistry() throws {
        // The NHL summary read with the NBA's descriptor still has three
        // periods: its own format.regulation.periods wins.
        let linescore = try #require(Linescore(summary: nhlSummary(), league: .nba))
        #expect(linescore.periodCount == 3)

        // With the format removed, the league's regulation length decides.
        let formatless = try nhlSummary().setting(["format"], to: .null)
        #expect(Linescore(summary: formatless, league: .nhl)?.periodCount == 3)
        #expect(Linescore(summary: formatless, league: .nba)?.periodCount == 4)
    }

    @Test("A finished WNBA game fills its four quarters")
    func wnbaFinal() throws {
        let linescore = try #require(Linescore(summary: Fixture.json("wnba_summary_final_401857143"), league: .wnba))
        #expect(linescore.periodLabels == ["1", "2", "3", "4"])
        #expect(linescore.home == Linescore.Line(homeAway: "home", abbreviation: "IND", periods: ["17", "18", "28", "35"], total: "98"))
        #expect(linescore.away == Linescore.Line(homeAway: "away", abbreviation: "DAL", periods: ["15", "22", "29", "21"], total: "87"))
    }

    @Test("Periods past regulation are labelled OT; baseball numbers its innings")
    func overtimeColumns() throws {
        // NFL overtime: four quarters from the format, plus the OT period
        // the competitors have a score for.
        let nfl = try #require(Linescore(summary: Fixture.json("chiefs_summary_final_401872945"), league: .nfl))
        #expect(nfl.periodLabels == ["1", "2", "3", "4", "OT"])
        #expect(nfl.home.periods == ["10", "7", "7", "3", "6"])

        // An NHL overtime game on the league scoreboard, which carries no
        // format: the registry's three periods, then OT.
        let scoreboard = try Fixture.json("nhl_scoreboard_20260919")
        let overtime = try #require(Linescore(
            competitors: scoreboard["events", 1, "competitions", 0, "competitors"],
            regulationPeriods: LeagueDescriptor.nhl.regulationPeriods
        ))
        #expect(overtime.periodLabels == ["1", "2", "3", "OT"])
        #expect(overtime.home.periods == ["2", "0", "1", "1"])
        #expect(overtime.home.total == "4")

        // Nine innings, from MLB's format; extras would be "10", not "OT".
        let mlb = try #require(Linescore(summary: Fixture.json("royals_summary_final_401817094"), league: .mlb))
        #expect(mlb.periodLabels == (1 ... 9).map { "\($0)" })
        let extras = try #require(Linescore(
            competitors: Fixture.json("royals_summary_final_401817094")["header", "competitions", 0, "competitors"],
            regulationPeriods: 8,
            numbersExtraPeriods: true
        ))
        #expect(extras.periodLabels.last == "9")
    }

    @Test("A pre-game scoreboard with no linescores still sizes from regulation")
    func scoreboardPregame() throws {
        let scoreboard = try Fixture.json("nba_scoreboard_20261003")
        let linescore = try #require(Linescore(
            competitors: scoreboard["events", 0, "competitions", 0, "competitors"],
            regulationPeriods: LeagueDescriptor.nba.regulationPeriods
        ))
        #expect(linescore.periodCount == 4)
        #expect(linescore.away.periods == ["-", "-", "-", "-"])
        #expect(linescore.away.total == "0")  // the scoreboard publishes "0"
    }

    @Test("Soccer halves and college football quarters come from their formats")
    func otherSports() throws {
        let epl = try #require(Linescore(summary: Fixture.json("epl_summary_final_401879301"), league: .premierLeague))
        #expect(epl.periodLabels == ["1", "2"])
        #expect(epl.home.total == "3")

        let ncaaf = try #require(Linescore(summary: Fixture.json("ncaaf_summary_final_401864494"), league: .collegeFootball))
        #expect(ncaaf.periodLabels == ["1", "2", "3", "4"])
        #expect(ncaaf.away.periods == ["0", "0", "3", "23"])
    }

    @Test("No sides, or nothing to size by, is no linescore")
    func degenerate() {
        #expect(Linescore(summary: JSON(data: Data()), league: .nhl) == nil)
        let bare = JSON(data: Data("""
        [{"homeAway": "home"}, {"homeAway": "away"}]
        """.utf8))
        #expect(Linescore(competitors: bare, regulationPeriods: nil) == nil)
        #expect(Linescore(competitors: bare, regulationPeriods: 3)?.periodCount == 3)
    }
}

// MARK: - Game card labels

@Suite("Game card period labels")
struct GameCardPeriodLabelTests {
    @Test("Regulation periods take the registry's names per style")
    func regulation() {
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("1") == "1st Period")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("3") == "3rd Period")
        #expect(LeagueDescriptor.nba.liveCardPeriodLabel("4") == "4th Quarter")
        #expect(LeagueDescriptor.wnba.liveCardPeriodLabel("2") == "2nd Quarter")
        #expect(LeagueDescriptor.mensCollegeBasketball.liveCardPeriodLabel("2") == "2nd Half")
        #expect(LeagueDescriptor.premierLeague.liveCardPeriodLabel("1") == "1st Half")
        #expect(LeagueDescriptor.nfl.liveCardPeriodLabel("3") == "3rd Quarter")
    }

    @Test("Past regulation reads OT, 2OT …, counted from each style's length")
    func overtime() {
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("4") == "OT")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("5") == "2OT")
        #expect(LeagueDescriptor.nba.liveCardPeriodLabel("5") == "OT")
        #expect(LeagueDescriptor.nba.liveCardPeriodLabel("7") == "3OT")
        #expect(LeagueDescriptor.mensCollegeBasketball.liveCardPeriodLabel("3") == "OT")
        #expect(LeagueDescriptor.nfl.liveCardPeriodLabel("5") == "OT")
        // periodName itself still names regulation only.
        #expect(LeagueDescriptor.nhl.periodName("4") == "")
    }

    @Test("Unnamed periods and missing periods stay blank")
    func blank() {
        #expect(LeagueDescriptor.mlb.liveCardPeriodLabel("10") == "")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("") == "")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("0") == "")
    }

    @Test("A live NHL schedule game's card reads period and clock")
    func liveNHLGame() throws {
        // nhl_schedule.json event 401879368 (Sharks at Ducks, final),
        // rewound to the second period.
        let schedule = try Fixture.json("nhl_schedule")
        let (event, pointer) = try Fixture.event("401879368", in: schedule)
        let status: [JSON.Index] = ["competitions", 0, "status"]
        let live = event
            .setting(status + ["period"], to: .number(2))
            .setting(status + ["displayClock"], to: .string("7:45"))
            .setting(status + ["type", "completed"], to: .bool(false))
            .setting(status + ["type", "description"], to: .string("In Progress"))
            .setting(status + ["type", "detail"], to: .string("7:45 - 2nd Period"))

        let ducks = followed(.nhl, "25")
        let game = parseGame(from: live, team: ducks, pointer: pointer)
        #expect(!game.completed)
        #expect(!game.gameHalftime)
        #expect(game.gameClock == "7:45")
        #expect(ducks.league.descriptor.liveCardPeriodLabel(game.gamePeriod) == "2nd Period")

        let overtime = parseGame(from: live.setting(status + ["period"], to: .number(4)), team: ducks, pointer: pointer)
        #expect(ducks.league.descriptor.liveCardPeriodLabel(overtime.gamePeriod) == "OT")
    }

    @Test("The NHL scoreboard gives the card its live score")
    func scoreboardScore() throws {
        let board = parseScoreboard(from: try Fixture.json("nhl_scoreboard_20260919"))
        let leafs = board.lines(for: "21")
        let line = try #require(leafs.first { $0.gameID == "401881922" })
        #expect(line.opponentID == "10")
        #expect(line.score == LiveGameScore(score: 1, opponentScore: 4))
    }
}

// MARK: - Soccer lineups

@Suite("Soccer lineups")
struct SoccerLineupsTests {
    @Test("Starters, substitutes in minute order, goals and cards")
    func premierLeague() throws {
        // epl_summary_final_401879301.json: Arsenal 3–0 Coventry.
        let lineups = try #require(SoccerLineups(summary: Fixture.json("epl_summary_final_401879301")))

        let arsenal = lineups.home
        #expect(arsenal.abbreviation == "ARS")
        #expect(arsenal.formation == "4-2-3-1")
        #expect(arsenal.starters.count == 11)
        #expect(arsenal.substitutes.map(\.name) == [
            "Noni Madueke", "Martín Zubimendi",  // 68'
            "Mikel Merino", "Eberechi Eze",  // 76'
            "Piero Hincapié",  // 81'
        ])
        #expect(arsenal.substitutes.first?.substitutedAt == "68'")

        let havertz = try #require(arsenal.starters.first { $0.name == "Kai Havertz" })
        #expect(havertz.goals == 1)
        #expect(havertz.yellowCards == 0)
        let gabriel = try #require(arsenal.starters.first { $0.name == "Gabriel Magalhães" })
        #expect(gabriel.yellowCards == 1)
        #expect(gabriel.goals == 0)
        let calafiori = try #require(arsenal.starters.first { $0.name == "Riccardo Calafiori" })
        #expect(calafiori.subbedOut)
        #expect(calafiori.substitutedAt == "81'")
        #expect(arsenal.starters.reduce(0) { $0 + $1.goals } == 3)

        let coventry = lineups.away
        #expect(coventry.formation == "4-1-4-1")
        #expect(coventry.substitutes.map(\.name) == ["Victor Torp", "Jack Rudoni", "Taiwo Awoniyi", "Gustavo Hamer"])
        #expect(coventry.starters.first { $0.name == "Caleb Yirenkyi" }?.yellowCards == 1)
    }

    @Test("Every soccer summary captured has both lineups")
    func everyLeague() throws {
        for name in [
            "epl_summary_final_401879301", "laliga_summary_final_401882926",
            "ligamx_summary_final_401877018", "nwsl_summary_final_401853969",
            "sporting_summary_final_761450",
        ] {
            let lineups = try #require(SoccerLineups(summary: Fixture.json(name)), "\(name)")
            #expect(lineups.home.starters.count == 11, "\(name)")
            #expect(lineups.away.starters.count == 11, "\(name)")
        }
    }

    @Test("A summary with no rosters has no lineups")
    func noRosters() {
        #expect(SoccerLineups(summary: JSON(data: Data())) == nil)
    }
}

// MARK: - The new leagues through the shared readers

@Suite("New leagues through the shared box-score readers")
struct NewLeagueBoxScoreTests {
    @Test("WNBA box score reads by name, as NCAA basketball does")
    func wnba() throws {
        // wnba_summary_final_401857143.json: Fever (home, team 5) 98, Wings 87.
        let lines = parseBasketballGameTeamStats(from: try Fixture.json("wnba_summary_final_401857143"), team: followed(.wnba, "5"))
        try #require(lines.count == 2)
        let wings = lines[0]  // boxscore.teams[0], away
        #expect(wings.fieldGoals == "31-72")
        #expect(wings.assists == 18)
        #expect(wings.steals == 3)
        #expect(wings.blocks == 6)
        #expect(wings.turnOvers == 10)
        #expect(wings.fouls == 19)
        #expect(wings.largestLead == 5)
        #expect(wings.score == 98)  // the followed Fever's, first
        #expect(wings.opponentScore == 87)

        let boxScore = try #require(BoxScore(basketball: lines, followedIsHome: true))
        #expect(boxScore.homeScore == 98)
        #expect(boxScore.awayScore == 87)
        #expect(boxScore.rows.first { $0.title == "Assists" } == BoxScore.Row(title: "Assists", home: "14", away: "18"))
    }

    @Test("College football reads its 15 statistics by name")
    func collegeFootball() throws {
        // ncaaf_summary_final_401864494.json: USC (home, 30) 42, San José State 26.
        let lines = parseFootballGameTeamStats(from: try Fixture.json("ncaaf_summary_final_401864494"), team: followed(.collegeFootball, "30"))
        try #require(lines.count == 2)
        let spartans = lines[0]
        #expect(spartans.yards == 336)
        #expect(spartans.passingYards == 234)
        #expect(spartans.rushingYards == 102)
        #expect(spartans.firstDowns == 19)
        #expect(spartans.drives == 0)  // no totalDrives in college feeds
        #expect(spartans.possesionTime == "22:45")
        #expect(spartans.completionAttempts == 21)
        let trojans = lines[1]
        #expect(trojans.yards == 505)
        #expect(trojans.interceptions == 1)
        #expect(trojans.possesionTime == "37:15")
        #expect(trojans.score == 42)
        #expect(trojans.opponentScore == 26)
    }

    @Test("Bug: a college football sheet drew a Drives row of zeros, and Comp/Att showed completions alone")
    func collegeFootballRows() throws {
        // ncaaf_summary_final_401864494.json: no `totalDrives` in either
        // side's statistics; completionAttempts "21/32" (SJSU, away),
        // "30/36" (USC, home).
        let lines = parseFootballGameTeamStats(
            from: try Fixture.json("ncaaf_summary_final_401864494"), team: followed(.collegeFootball, "30")
        )
        #expect(lines.map(\.completionAttemptsDisplay) == ["21/32", "30/36"])
        #expect(lines.map(\.drives) == [0, 0])
        #expect(lines[0].completionAttempts == 21)  // still the leading figure

        let boxScore = try #require(BoxScore(football: lines, followedIsHome: true))
        #expect(boxScore.rows.map(\.title) == [
            "Total Yards", "Passing Yards", "Rushing Yards", "First Downs",
            "Interceptions", "Possession Time", "Completion Attempts",
        ])
        #expect(boxScore.rows.last == BoxScore.Row(title: "Completion Attempts", home: "30/36", away: "21/32"))

        // The NFL lists drives, so its sheet keeps the row.
        let nfl = parseFootballGameTeamStats(from: try Fixture.json("chiefs_summary_final_401872945"), team: .chiefs)
        let nflBox = try #require(BoxScore(football: nfl, followedIsHome: true))
        #expect(nflBox.rows.first { $0.title == "Drives" } == BoxScore.Row(title: "Drives", home: "11", away: "10"))
        #expect(nflBox.rows.last == BoxScore.Row(title: "Completion Attempts", home: "32/47", away: "22/31"))
    }
}
