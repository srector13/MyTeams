//
//  CrossLeagueAcceptanceTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The P3 acceptance walkthrough: one team in each new sport — the Atlanta
/// Hawks (NBA), Anaheim Ducks (NHL), Arsenal (Premier League) and Kansas
/// (college football) — through every section of its page: schedule,
/// roster with a player's season line, news, standings, and the game sheet
/// of a finished game. Each section is read from the captured fixtures by
/// the parser the page uses, at the URL the registry builds for it.
///
/// Every value was derived first by `scripts/verify_acceptance_p3e.py`, a
/// port of these parsers run over the same files. See FIXTURES.md,
/// "Cross-league acceptance (P3-e)".

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

private func approx(_ value: Float, _ expected: Float, tolerance: Float = 0.001) -> Bool {
    abs(value - expected) <= tolerance
}

private func published(_ text: String) throws -> Date {
    try Date.ISO8601FormatStyle().parse(text)
}

private let site = "https://site.api.espn.com/apis/site/v2/sports"
private let standingsBase = "https://site.api.espn.com/apis/v2/sports"

/// A finished game's sheet, loaded the way the schedule card opens it: one
/// summary request, at the URL the team's league builds, read by the
/// league's sport's parser.
private func finishedGameSheet(
    _ team: TeamRef,
    fixture: String,
    gameID: String,
    followedIsHome: Bool
) async throws -> GameSheet {
    let transport = RecordingTransport(always: try .fixture(fixture))
    let load = await team.league.descriptor.downloadGameSheet(
        gameID: gameID,
        team: team,
        followedIsHome: followedIsHome,
        client: HTTPClient(transport: transport)
    )
    #expect(transport.requestCount == 1)
    #expect(transport.urls.first?.absoluteString == team.summaryURL(gameID: gameID))
    let sheet = try #require(load.sheet)
    #expect(sheet.phase == .final)
    // A finished game is not refetched.
    #expect(sheet.refreshInterval == nil)
    return sheet
}

// MARK: - NBA

@Suite("Acceptance: Atlanta Hawks (NBA)")
struct HawksAcceptanceTests {
    private let hawks = followed(.nba, "1")

    @Test("The registry's URLs are the ones the fixtures were captured from")
    func endpoints() {
        #expect(hawks.scheduleURL == "\(site)/basketball/nba/teams/1/schedule")
        #expect(hawks.rosterURL == "\(site)/basketball/nba/teams/1/roster")
        #expect(hawks.newsURL == "\(site)/basketball/nba/news?team=1&limit=25")
        #expect(hawks.league.standingsURL() == "\(standingsBase)/basketball/nba/standings")
        #expect(hawks.summaryURL(gameID: "401811028") == "\(site)/basketball/nba/summary?event=401811028")
    }

    @Test("Schedule: this preseason, and last season's results")
    func schedule() throws {
        // nba_schedule: the live feed, five preseason games, none played.
        let preseason = parseSchedule(from: try Fixture.json("nba_schedule"), team: hawks)
        #expect(preseason.map(\.gameID) == ["401898388", "401898394", "401898396", "401898402", "401898408"])
        #expect(scheduleRecord(games: preseason, league: .nba) == Record(wins: 0, losses: 0, format: .winLoss))
        #expect(getNextGame(schedule: preseason) == 0)

        // nba_schedule_2026 (?season=2026, trimmed to 12 of 82): events[11]
        // is Cleveland (5) at the Hawks, a 124–102 win on April 10.
        let lastSeason = parseSchedule(from: try Fixture.json("nba_schedule_2026"), team: hawks)
        #expect(lastSeason.count == 12)
        #expect(scheduleRecord(games: lastSeason, league: .nba).summary == "7-5")
        let game = try #require(lastSeason.first { $0.gameID == "401811028" })
        #expect(game.pointer == 11)
        #expect(game.team == "Hawks")
        #expect(game.opponent == "Cavaliers")
        #expect(game.opponentID == "5")
        #expect(game.gameHome)
        #expect(game.completed && game.gameWin)
        #expect(game.score == "124" && game.opponentScore == "102")
        #expect(game.location == "State Farm Arena")
        #expect(game.channel == "Prime Video")
        #expect(game.dateAsDate == parseGameDate("2026-04-10T23:00Z"))
        #expect(game.competition == nil)  // basketball feeds name no league
    }

    @Test("Roster: 18 players by surname, and a guard's season line from All Splits")
    func roster() throws {
        let roster = parseBasketballRoster(from: try Fixture.json("nba_roster"))
        #expect(roster.count == 18)
        #expect(roster.first?.name == "Nickeil Alexander-Walker")
        #expect(roster.last?.name == "Jalen Wilson")

        let daniels = try #require(roster.first { $0.playerID == "4869342" })
        #expect(daniels.name == "Dyson Daniels")
        #expect(daniels.number == "5")
        #expect(daniels.position == "Guard")
        #expect(daniels.hometown == "Bendigo, VIC")

        // nba_splits_4869342: All Splits, 76 games (not All Splits + Home).
        let season = parseBasketballPlayerStats(from: try Fixture.json("nba_splits_4869342"))
        #expect(season.gamesPlayed == 76)
        #expect(approx(season.avgPoints, 11.9))
        #expect(approx(season.avgAssists, 5.9))
    }

    @Test("News: 25 articles, newest first")
    func news() throws {
        let articles = parseNews(from: try Fixture.json("nba_news"))
        #expect(articles.count == 25)
        #expect(articles.first?.title == "2026 NBA free agency: Grades for offseason signings, extensions")
        let newest = try published("2026-09-26T16:55:13Z")
        #expect(articles.first?.publishedAt == newest)
        #expect(articles.allSatisfy { $0.url.scheme == "https" && $0.source == "ESPN" })
    }

    @Test("Standings: the preseason East, every column zero, unranked")
    func standings() throws {
        // The capture is preseason (FIXTURES.md, "Reading the standings"):
        // nothing here may assume a played game.
        let table = parseStandings(from: try Fixture.json("nba_standings"), league: .nba)
        let row = try #require(table.entry(for: "1"))
        #expect(table.group(containing: "1")?.name == "Eastern Conference")
        #expect(table.groups[0].entries.first?.teamID == "1")
        #expect(row.record == Record(wins: 0, losses: 0, format: .winLoss))
        #expect(row.record.summary == "0-0")
        #expect(row.rank == nil)
        #expect(row.gamesBehind == "-")
        #expect(row.conferenceRecord == "0-0")
        // The header's record agrees before a game is played.
        let preseason = parseSchedule(from: try Fixture.json("nba_schedule"), team: hawks)
        #expect(scheduleRecord(games: preseason, league: .nba) == row.record)
    }

    @Test("Game sheet: Cleveland at the Hawks, 124–102, four quarters")
    func boxScore() async throws {
        let sheet = try await finishedGameSheet(
            hawks, fixture: "nba_summary_final_401811028", gameID: "401811028", followedIsHome: true
        )
        let boxScore = try #require(sheet.boxScore)
        #expect(boxScore.homeScore == 124)
        #expect(boxScore.awayScore == 102)
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Field Goals", home: "45/93", away: "39/86"),
            BoxScore.Row(title: "Field Goal %", home: "48%", away: "45%"),
            BoxScore.Row(title: "Three Points", home: "16/44", away: "7/27"),
            BoxScore.Row(title: "Three Point %", home: "36%", away: "26%"),
            BoxScore.Row(title: "Free Throws", home: "18/25", away: "17/18"),
            BoxScore.Row(title: "Free Throw %", home: "72%", away: "94%"),
            BoxScore.Row(title: "Offensive Rebounds", home: "14", away: "9"),
            BoxScore.Row(title: "Defensive Rebounds", home: "32", away: "31"),
            BoxScore.Row(title: "Assists", home: "27", away: "25"),
            BoxScore.Row(title: "Blocks", home: "4", away: "6"),
            BoxScore.Row(title: "Steals", home: "12", away: "8"),
            BoxScore.Row(title: "Turnovers", home: "11", away: "19"),
            BoxScore.Row(title: "Fouls", home: "18", away: "20"),
        ])

        let linescore = try #require(sheet.linescore)
        #expect(linescore.periodLabels == ["1", "2", "3", "4"])
        #expect(linescore.home == Linescore.Line(homeAway: "home", abbreviation: "ATL", periods: ["27", "34", "35", "28"], total: "124"))
        #expect(linescore.away == Linescore.Line(homeAway: "away", abbreviation: "CLE", periods: ["22", "26", "17", "37"], total: "102"))

        #expect(sheet.hockey == nil && sheet.soccerLineups == nil)
        #expect(sheet.info.city == "Atlanta")
        #expect(sheet.info.state == "GA")
        #expect(sheet.info.attendance == "17517")
    }
}

// MARK: - NHL

@Suite("Acceptance: Anaheim Ducks (NHL)")
struct DucksAcceptanceTests {
    private let ducks = followed(.nhl, "25")

    @Test("The registry's URLs are the ones the fixtures were captured from")
    func endpoints() {
        #expect(ducks.scheduleURL == "\(site)/hockey/nhl/teams/25/schedule")
        #expect(ducks.rosterURL == "\(site)/hockey/nhl/teams/25/roster")
        #expect(ducks.newsURL == "\(site)/hockey/nhl/news?team=25&limit=25")
        #expect(ducks.league.standingsURL() == "\(standingsBase)/hockey/nhl/standings")
        #expect(ducks.summaryURL(gameID: "401879368") == "\(site)/hockey/nhl/summary?event=401879368")
        #expect(ducks.league.athleteSplitsURL(athleteID: "4588165")
            == "https://site.web.api.espn.com/apis/common/v3/sports/hockey/nhl/athletes/4588165/splits")
    }

    @Test("Schedule: four preseason games played, a 6–2 win over San Jose first")
    func schedule() throws {
        let games = parseSchedule(from: try Fixture.json("nhl_schedule"), team: ducks)
        #expect(games.map(\.gameID) == ["401879368", "401879369", "401879370", "401879371"])
        let allCompleted = games.allSatisfy(\.completed)
        #expect(allCompleted)
        #expect(getNextGame(schedule: games) == 3)  // all played: the last

        let opener = games[0]
        #expect(opener.team == "Ducks")
        #expect(opener.opponent == "Sharks")
        #expect(opener.opponentID == "18")
        #expect(opener.gameHome && opener.gameWin)
        #expect(opener.score == "6" && opener.opponentScore == "2")
        #expect(opener.location == "Honda Center")
        #expect(opener.gamePeriod == "3")  // regulation
        // All four are preseason (seasonType 1), which the record leaves out.
        #expect(scheduleRecord(games: games, league: .nhl).summary == "0-0-0")
    }

    @Test("Roster: 56 players by position group, with a skater's and a goalie's season line")
    func roster() throws {
        let roster = parseHockeyRoster(from: try Fixture.json("nhl_roster"))
        #expect(roster.count == 56)
        #expect(roster.first?.name == "Anthony Allain-Samake")
        #expect(Set(roster.filter { $0.position == "Goaltender" }.map(\.name))
            == ["Elijah Neuenschwander", "Lukas Dostal", "Tomas Suchanek", "Ville Husso"])

        let gauthier = try #require(roster.first { $0.playerID == "5080145" })
        #expect(gauthier.name == "Cutter Gauthier")
        #expect(gauthier.number == "61")
        #expect(gauthier.position == "Left Wing")
        #expect(gauthier.shoots == "Left")
        let dostal = try #require(roster.first { $0.playerID == "4588165" })
        #expect(dostal.number == "1")
        #expect(dostal.position == "Goaltender")

        // P3-d replaced the hockey sheet's placeholder with the splits line:
        // the skater's and the goalie's differ in every column.
        let skater = hockeySheetStats(from: parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_5080145")))
        #expect(skater.map(\.id) == hockeySkaterStatNames)
        #expect(skater.map(\.display) == ["76", "41", "28", "69", "-2", "28", "285", "11", "8", "0", "7", "49.0", "17:15"])
        let goalie = hockeySheetStats(from: parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_4588165")))
        #expect(goalie.map(\.id) == hockeyGoalieStatNames)
        #expect(goalie.map(\.display) == ["55", "30", "20", "4", "169", "3.10", "1513", "1344", ".888", "0", "58:21"])
    }

    @Test("News: 25 articles, newest first")
    func news() throws {
        let articles = parseNews(from: try Fixture.json("nhl_news"))
        #expect(articles.count == 25)
        #expect(articles.first?.title == "Lapsed fan's guide to the NHL season: Top teams, players, storylines for 2026-27")
        let newest = try published("2026-09-25T12:31:06Z")
        #expect(articles.first?.publishedAt == newest)
    }

    @Test("Standings: W-L-OTL in the West, all zero in preseason — and the header agrees")
    func standings() throws {
        let table = parseStandings(from: try Fixture.json("nhl_standings"), league: .nhl)
        let row = try #require(table.entry(for: "25"))
        #expect(table.group(containing: "25")?.name == "Western Conference")
        #expect(row.record == Record(wins: 0, losses: 0, overtimeLosses: 0, points: 0, format: .winLossOvertimeLoss))
        #expect(row.record.summary == "0-0-0")
        #expect(row.rank == nil)

        // Once a known gap (P3-e report): the header counted the four
        // preseason games the standings leave out, reading 1-3-0. It now
        // leaves them out too. (The table row also carries points, which the
        // header does not, so the two compare by summary.)
        let games = parseSchedule(from: try Fixture.json("nhl_schedule"), team: ducks)
        #expect(scheduleRecord(games: games, league: .nhl).summary == "0-0-0")
        #expect(scheduleRecord(games: games, league: .nhl).summary == row.record.summary)
    }

    @Test("Game sheet: Sharks at the Ducks, 6–2 — skater and goalie tables, three periods")
    func boxScore() async throws {
        let sheet = try await finishedGameSheet(
            ducks, fixture: "nhl_summary_final_401879368", gameID: "401879368", followedIsHome: true
        )
        let boxScore = try #require(sheet.boxScore)
        #expect(boxScore.homeScore == 6)
        #expect(boxScore.awayScore == 2)
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Shots", home: "32", away: "23"),
            BoxScore.Row(title: "Power Play", home: "1/3", away: "0/2"),
            BoxScore.Row(title: "Power Play %", home: "33.3%", away: "0.0%"),
            BoxScore.Row(title: "Faceoffs Won", home: "35", away: "25"),
            BoxScore.Row(title: "Faceoff %", home: "58.3%", away: "41.7%"),
            BoxScore.Row(title: "Hits", home: "17", away: "27"),
            BoxScore.Row(title: "Penalty Minutes", home: "9", away: "11"),
            BoxScore.Row(title: "Blocked Shots", home: "7", away: "12"),
        ])

        let hockey = try #require(sheet.hockey)
        #expect(hockey.home.teamID == "25")
        #expect(hockey.home.name == "Ducks")
        #expect(hockey.home.abbreviation == "ANA")
        #expect(hockey.away.teamID == "18")
        #expect(hockey.away.name == "Sharks")
        #expect(hockey.away.abbreviation == "SJ")
        #expect(hockey.home.forwards.count == 12 && hockey.home.defense.count == 6)
        #expect(hockey.away.forwards.count == 12 && hockey.away.defense.count == 6)
        for team in hockey.teams {
            #expect((team.forwards + team.defense).reduce(0) { $0 + $1.goals } == team.score)
        }

        // Beckett Sennecke's hat trick.
        let sennecke = try #require(hockey.home.forwards.first { $0.name == "Beckett Sennecke" })
        #expect(sennecke.jersey == "45")
        #expect(sennecke.position == "RW")
        #expect(sennecke.goals == 3 && sennecke.assists == 0)
        #expect(sennecke.timeOnIce == "14:50")

        // One goalie played all 60 minutes for Anaheim; San Jose split theirs.
        #expect(hockey.home.goalies.map(\.name) == ["Laurent Brossoit"])
        let brossoit = hockey.home.goalies[0]
        #expect(brossoit.shotsAgainst == 23 && brossoit.saves == 21 && brossoit.goalsAgainst == 2)
        #expect(brossoit.savePct == ".913")
        #expect(brossoit.timeOnIce == "60:00")
        #expect(hockey.away.goalies.map(\.name) == ["Matthew Davis", "Eric Comrie"])

        let linescore = try #require(sheet.linescore)
        #expect(linescore.periodLabels == ["1", "2", "3"])
        #expect(linescore.home == Linescore.Line(homeAway: "home", abbreviation: "ANA", periods: ["2", "2", "2"], total: "6"))
        #expect(linescore.away == Linescore.Line(homeAway: "away", abbreviation: "SJ", periods: ["1", "1", "0"], total: "2"))

        #expect(sheet.soccerLineups == nil)
        #expect(sheet.info.city == "Anaheim")
        #expect(sheet.info.attendance == "10000")
    }
}

// MARK: - Premier League

@Suite("Acceptance: Arsenal (Premier League)")
struct ArsenalAcceptanceTests {
    private let arsenal = followed(.premierLeague, "359")
    private let championsLeague = LeagueID.soccer("uefa.champions")

    @Test("The registry's URLs are the ones the fixtures were captured from, the cup's included")
    func endpoints() {
        #expect(arsenal.scheduleURL == "\(site)/soccer/eng.1/teams/359/schedule")
        #expect(championsLeague.scheduleURL(teamID: "359") == "\(site)/soccer/uefa.champions/teams/359/schedule")
        #expect(arsenal.league.descriptor.cupCompetitions.contains(championsLeague))
        #expect(arsenal.rosterURL == "\(site)/soccer/eng.1/teams/359/roster")
        #expect(arsenal.newsURL == "\(site)/soccer/eng.1/news?team=359&limit=25")
        #expect(arsenal.league.standingsURL() == "\(standingsBase)/soccer/eng.1/standings")
        #expect(arsenal.summaryURL(gameID: "401879301") == "\(site)/soccer/eng.1/summary?event=401879301")
    }

    @Test("Schedule: league and Champions League merged by kick-off; the tie is not in the record")
    func schedule() throws {
        let league = try Fixture.json("epl_schedule")
        let cup = try Fixture.json("ucl_schedule_359")
        let games = mergeSchedules(league: league, cups: [(competition: championsLeague, json: cup)], team: arsenal)
        #expect(games.map(\.gameID) == ["401879301", "401879295", "401879292", "401915423", "401878779", "401879274"])
        #expect(games.map(\.pointer) == Array(0 ..< 6))
        #expect(games.compactMap(\.competition) == [
            LeagueID.premierLeague, .premierLeague, .premierLeague, championsLeague, .premierLeague, .premierLeague,
        ])

        // ucl_schedule_359 events[0]: a 1–0 win at Napoli (114), Sep 9.
        let tie = games[3]
        #expect(tie.opponent == "Napoli")
        #expect(tie.opponentID == "114")
        #expect(!tie.gameHome && tie.gameWin)
        #expect(tie.score == "1" && tie.opponentScore == "0")
        #expect(tie.location == "Stadio Diego Armando Maradona")
        #expect(tie.channel == "Paramount+")
        #expect(!tie.isLeagueGame(of: .premierLeague))

        // The league record only: 4 W, 1 L, 0 D — not 5-1-0.
        #expect(scheduleRecord(games: games, league: .premierLeague) == Record(wins: 4, losses: 1, ties: 0, format: .winLossTie))
    }

    @Test("Roster: 27 players, season totals by name, five listed with none")
    func roster() throws {
        let roster = parseSoccerRoster(from: try Fixture.json("epl_roster"))
        #expect(roster.count == 27)
        #expect(roster.first?.name == "Kepa Arrizabalaga")
        #expect(roster.count { !$0.hasSeasonStats } == 5)

        let saka = try #require(roster.first { $0.playerID == "280555" })
        #expect(saka.name == "Bukayo Saka")
        #expect(saka.number == "7")
        #expect(saka.position == "Forward")
        #expect(saka.appearances == 5)
        #expect(saka.totalGoals == 3)
        #expect(saka.goalAssists == 0)

        // The athlete summary agrees: "5 (0)" starts, 3 goals.
        let summary = parseSoccerPlayerStats(from: try Fixture.json("epl_athlete_280555"), playerPosition: "Forward")
        #expect(summary.starts == "5")
        #expect(summary.goals == "3")
    }

    @Test("News: 24 articles — a plain-http match report is dropped")
    func news() throws {
        let json = try Fixture.json("epl_news")
        #expect(json["articles"].arrayValue.count == 25)
        let articles = parseNews(from: json)
        #expect(articles.count == 24)
        #expect(articles.first?.title == "Parma part ways with ex-Arsenal assistant Carlos Cuesta")
        let newest = try published("2026-09-27T18:01:25Z")
        #expect(articles.first?.publishedAt == newest)
        #expect(!articles.contains { $0.title.hasPrefix("Arsenal battered by brilliant Brighton") })
    }

    @Test("Standings: second on 12 points, and the table agrees with the schedule")
    func standings() throws {
        let table = parseStandings(from: try Fixture.json("epl_standings"), league: .premierLeague)
        #expect(table.kind == .pointsTable)
        let row = try #require(table.entry(for: "359"))
        #expect(row.rank == 2)
        #expect(row.record == Record(wins: 4, losses: 1, ties: 0, points: 12, format: .winDrawLossPoints))
        #expect(row.record.summary == "4-0-1, 12 pts")
        #expect(row.goalDifference == "+4")
        #expect(row.note == "Champions League")

        let league = try Fixture.json("epl_schedule")
        let cup = try Fixture.json("ucl_schedule_359")
        let games = mergeSchedules(league: league, cups: [(competition: championsLeague, json: cup)], team: arsenal)
        let header = scheduleRecord(games: games, league: .premierLeague)
        #expect(header.wins == row.record.wins)
        #expect(header.losses == row.record.losses)
        #expect(header.ties == row.record.ties)  // draws
    }

    @Test("Game sheet: Arsenal 3–0 Coventry — box score, halves and lineups")
    func boxScore() async throws {
        let sheet = try await finishedGameSheet(
            arsenal, fixture: "epl_summary_final_401879301", gameID: "401879301", followedIsHome: true
        )
        let boxScore = try #require(sheet.boxScore)
        #expect(boxScore.homeScore == 3)
        #expect(boxScore.awayScore == 0)
        // possessionPct 64.5 / 35.5, rounded half away from zero.
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Goals", home: "3", away: "0"),
            BoxScore.Row(title: "Shots", home: "20", away: "4"),
            BoxScore.Row(title: "Possession", home: "65%", away: "36%"),
            BoxScore.Row(title: "Corner Kicks", home: "8", away: "2"),
        ])

        let linescore = try #require(sheet.linescore)
        #expect(linescore.periodLabels == ["1", "2"])
        #expect(linescore.home == Linescore.Line(homeAway: "home", abbreviation: "ARS", periods: ["2", "1"], total: "3"))
        #expect(linescore.away == Linescore.Line(homeAway: "away", abbreviation: "COV", periods: ["0", "0"], total: "0"))

        let lineups = try #require(sheet.soccerLineups)
        #expect(lineups.home.formation == "4-2-3-1")
        #expect(lineups.away.formation == "4-1-4-1")
        #expect(lineups.home.starters.count == 11 && lineups.away.starters.count == 11)

        #expect(sheet.hockey == nil)
        #expect(sheet.info.city == "London")
        #expect(sheet.info.attendance == "60098")
    }
}

// MARK: - College football

@Suite("Acceptance: Kansas (college football)")
struct KansasFootballAcceptanceTests {
    private let kansas = followed(.collegeFootball, "2305")

    @Test("The registry's URLs are the ones the fixtures were captured from")
    func endpoints() {
        #expect(kansas.scheduleURL == "\(site)/football/college-football/teams/2305/schedule")
        #expect(kansas.rosterURL == "\(site)/football/college-football/teams/2305/roster")
        #expect(kansas.newsURL == "\(site)/football/college-football/news?team=2305&limit=25")
        #expect(kansas.league.standingsURL() == "\(standingsBase)/football/college-football/standings?group=80")
        #expect(kansas.summaryURL(gameID: "401856769") == "\(site)/football/college-football/summary?event=401856769")
    }

    @Test("Schedule: three played, 1–2, the next game is Middle Tennessee")
    func schedule() throws {
        let games = parseSchedule(from: try Fixture.json("ncaaf_schedule"), team: kansas)
        #expect(games.count == 12)
        #expect(games.prefix(4).map(\.gameID) == ["401856769", "401856678", "401856812", "401856807"])
        #expect(scheduleRecord(games: games, league: .collegeFootball) == Record(wins: 1, losses: 2, format: .winLoss))
        #expect(getNextGame(schedule: games) == 3)

        // events[0]: the 51–6 home opener against Long Island (2341), named
        // by `nickname` like the NFL's feeds.
        let opener = games[0]
        #expect(opener.team == "Kansas")
        #expect(opener.opponent == "Long Island")
        #expect(opener.opponentID == "2341")
        #expect(opener.gameHome && opener.gameWin)
        #expect(opener.score == "51" && opener.opponentScore == "6")
        #expect(opener.location == "David Booth Kansas Memorial Stadium")
        #expect(opener.channel == "ESPNU")
    }

    @Test("Roster: 100 players in three units, and the quarterback's season")
    func roster() throws {
        let roster = parseFootballRoster(from: try Fixture.json("ncaaf_roster"))
        #expect(roster.count == 100)
        #expect(roster.first?.name == "Jibreel Al-Amin")
        #expect(Set(roster.map(\.team)) == ["offense", "defense", "specialTeam"])

        let marshall = try #require(roster.first { $0.playerID == "5079604" })
        #expect(marshall.name == "Isaiah Marshall")
        #expect(marshall.number == "8")
        #expect(marshall.position == "Quarterback")
        #expect(marshall.team == "offense")
        #expect(marshall.hometown == "Southfield, MI")

        // ncaaf_splits_5079604: the Season row.
        let season = parseFootballPlayerStats(from: try Fixture.json("ncaaf_splits_5079604"))
        #expect(season.groups.map(\.title) == ["Passing", "Rushing"])
        #expect(season.groups[0].stats.first { $0.id == "passingYards" }?.display == "649")
        #expect(season.groups[0].stats.first { $0.id == "passingTouchdowns" }?.display == "5")
    }

    @Test("News: 19 articles — the plain-http previews and recaps are dropped")
    func news() throws {
        let json = try Fixture.json("ncaaf_news")
        #expect(json["articles"].arrayValue.count == 25)
        let articles = parseNews(from: json)
        #expect(articles.count == 19)
        #expect(articles.first?.title == "College Football Playoff 2026: Bubble Watch after Week 3")
        let newest = try published("2026-09-22T14:40:44Z")
        #expect(articles.first?.publishedAt == newest)
    }

    @Test("Standings: last in the Big 12, and the table's record is the header's")
    func standings() throws {
        let table = parseStandings(from: try Fixture.json("ncaaf_standings"), league: .collegeFootball)
        let row = try #require(table.entry(for: "2305"))
        #expect(table.group(containing: "2305")?.name == "Big 12 Conference")
        #expect(row.rank == 16)
        #expect(row.gamesBehind == "2.5")
        #expect(row.streak == "L2")
        #expect(row.conferenceRecord == "0-1")

        let games = parseSchedule(from: try Fixture.json("ncaaf_schedule"), team: kansas)
        #expect(row.record == scheduleRecord(games: games, league: .collegeFootball))
        #expect(row.record.summary == "1-2")
    }

    @Test("Game sheet: Kansas 51–6 Long Island — no Drives row, Comp/Att in full")
    func boxScore() async throws {
        let sheet = try await finishedGameSheet(
            kansas, fixture: "ncaaf_summary_final_401856769", gameID: "401856769", followedIsHome: true
        )
        let boxScore = try #require(sheet.boxScore)
        #expect(boxScore.homeScore == 51)
        #expect(boxScore.awayScore == 6)
        #expect(boxScore.rows == [
            BoxScore.Row(title: "Total Yards", home: "613", away: "146"),
            BoxScore.Row(title: "Passing Yards", home: "336", away: "111"),
            BoxScore.Row(title: "Rushing Yards", home: "277", away: "35"),
            BoxScore.Row(title: "First Downs", home: "29", away: "11"),
            BoxScore.Row(title: "Interceptions", home: "0", away: "0"),
            BoxScore.Row(title: "Possession Time", home: "33:06", away: "26:54"),
            BoxScore.Row(title: "Completion Attempts", home: "18/25", away: "10/20"),
        ])

        let linescore = try #require(sheet.linescore)
        #expect(linescore.periodLabels == ["1", "2", "3", "4"])
        #expect(linescore.home == Linescore.Line(homeAway: "home", abbreviation: "KU", periods: ["6", "24", "7", "14"], total: "51"))
        #expect(linescore.away == Linescore.Line(homeAway: "away", abbreviation: "LIU", periods: ["0", "0", "0", "6"], total: "6"))

        #expect(sheet.hockey == nil && sheet.soccerLineups == nil)
        #expect(sheet.info.city == "Lawrence")
        #expect(sheet.info.state == "KS")
        #expect(sheet.info.attendance == "30904")
    }
}
