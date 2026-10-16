//
//  PlayerSeasonStatsTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Player season statistics for every sport, from the P3-d athlete fixtures
/// (`{key}_athlete_{id}`, `{key}_splits_{id}`) and the P3-a rosters. See
/// FIXTURES.md, "Player statistics (P3-d)".

private func approx(_ value: Float, _ expected: Float, tolerance: Float = 0.001) -> Bool {
    abs(value - expected) <= tolerance
}

/// A player sheet grid's cells as (title, info) pairs, in reading order.
private func cells(_ grid: PlayerSheetGrid) -> [(title: String, info: String)] {
    grid.sections.flatMap(\.rows).flatMap { $0 }.compactMap { cell -> (title: String, info: String)? in
        switch cell {
        case .stat(let title, let info), .fact(let title, let info):
            return title.isEmpty ? nil : (title, info)
        case .percentage(let title, let progress):
            return (title, "\(progress)")
        }
    }
}

// MARK: - Soccer

@Suite("Player stats: soccer outfield players", .tags(.golden))
struct SoccerOutfieldStatsTests {
    @Test("Every soccer league's athlete summary gives an outfield player real numbers")
    func athleteSummaries() throws {
        // {key}_athlete_{id}.json athlete.statsSummary.statistics, by name:
        // starts-subIns (value; displayValue "S (B)"), totalGoals, goalAssists, totalShots.
        let expected: [(fixture: String, position: String, stats: SoccerPlayerStats)] = [
            ("epl_athlete_280555", "Forward", SoccerPlayerStats(  // Bukayo Saka, "5 (0)"
                starts: "5", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A",
                substituteAppearances: "0", goals: "3", assists: "0", shots: "15")),
            ("laliga_athlete_231050", "Forward", SoccerPlayerStats(  // Raphinha, "7 (0)"
                starts: "7", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A",
                substituteAppearances: "0", goals: "12", assists: "3", shots: "25")),
            ("ligamx_athlete_93184", "Forward", SoccerPlayerStats(  // Henry Martín, "7 (0)"
                starts: "7", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A",
                substituteAppearances: "0", goals: "3", assists: "2", shots: "13")),
            ("nwsl_athlete_402432", "Midfielder", SoccerPlayerStats(  // Maiara Niehues, "15 (4)"
                starts: "15", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A",
                substituteAppearances: "4", goals: "9", assists: "0", shots: "46")),
            ("mls_athlete_293695", "Forward", SoccerPlayerStats(  // Calvin Harris, "23 (2)"
                starts: "23", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A",
                substituteAppearances: "2", goals: "4", assists: "6", shots: "48")),
        ]
        for (fixture, position, stats) in expected {
            let json = try Fixture.json(fixture)
            #expect(json["athlete"]["position"]["displayName"].stringValue == position, "\(fixture)")
            let parsed = parseSoccerPlayerStats(from: json, playerPosition: position)
            #expect(parsed == stats, "\(fixture)")
            #expect(parsed.hasFigures)
            // Goals, assists and appearances parse to real numbers.
            #expect(Int(parsed.goals) != nil && Int(parsed.assists) != nil && Int(parsed.starts) != nil, "\(fixture)")
        }
    }

    @Test("Soccer rosters read by name: the new leagues' outfield totals")
    func rosters() throws {
        // epl_roster.json Bukayo Saka (280555): general {foulsCommitted 2,
        // foulsSuffered 15, appearances 5, subIns 0}, offensive {goalAssists 0,
        // offsides 4, shotsOnTarget 9, totalShots 15, totalGoals 3}.
        let arsenal = parseSoccerRoster(from: try Fixture.json("epl_roster"))
        let saka = try #require(arsenal.first { $0.playerID == "280555" })
        #expect(saka.hasSeasonStats)
        #expect(saka.appearances == 5)
        #expect(saka.subAppearances == 0)
        #expect(saka.totalGoals == 3)
        #expect(saka.goalAssists == 0)
        #expect(saka.totalShots == 15)
        #expect(saka.shotsOnTarget == 9)
        #expect(saka.offsides == 4)
        #expect(saka.fouls == 2)
        #expect(saka.foulsSuffered == 15)

        // William Saliba (277385) has no `statistics` block at all.
        let saliba = try #require(arsenal.first { $0.playerID == "277385" })
        #expect(!saliba.hasSeasonStats)
        #expect(saliba.appearances == 0)

        // laliga_roster.json Raphinha (231050): 7 appearances, 12 goals, 3 assists.
        let raphinha = try #require(parseSoccerRoster(from: try Fixture.json("laliga_roster")).first { $0.playerID == "231050" })
        #expect(raphinha.appearances == 7)
        #expect(raphinha.totalGoals == 12)
        #expect(raphinha.goalAssists == 3)

        // ligamx_roster.json Henry Martín (93184): 7, 3 goals, 2 assists, 2 yellow cards.
        let martin = try #require(parseSoccerRoster(from: try Fixture.json("ligamx_roster")).first { $0.playerID == "93184" })
        #expect(martin.appearances == 7)
        #expect(martin.totalGoals == 3)
        #expect(martin.goalAssists == 2)
        #expect(martin.yellowCards == 2)
    }

    @Test("A soccer sheet counts substitute appearances once")
    func sheetAppearances() throws {
        // nwsl_roster.json Maiara Niehues (402432): appearances 19, subIns 4.
        // Her athlete summary says 15 starts, 4 off the bench: `appearances`
        // is every appearance, so 15 started and 19 played.
        let roster = parseSoccerRoster(from: try Fixture.json("nwsl_roster"))
        let niehues = try #require(roster.first { $0.playerID == "402432" })
        #expect(niehues.appearances == 19)
        #expect(niehues.subAppearances == 4)
        #expect(niehues.totalGoals == 9)
        #expect(niehues.redCards == 1)
        #expect(niehues.yellowCards == 1)

        let sheet = cells(niehues.placeholderStatistics)
        #expect(sheet.first { $0.title == "Games Started" }?.info == "15")
        #expect(sheet.first { $0.title == "Games Played" }?.info == "19")
        #expect(sheet.first { $0.title == "Total Goals" }?.info == "9")
    }

    @Test("A player listed without totals waits for the athlete summary")
    func sheetWithoutRosterStats() throws {
        let arsenal = parseSoccerRoster(from: try Fixture.json("epl_roster"))
        let saliba = try #require(arsenal.first { $0.playerID == "277385" })
        #expect(saliba.placeholderStatistics.sections.isEmpty)
    }
}

// MARK: - Hockey

@Suite("Player stats: hockey season lines", .tags(.golden))
struct HockeySeasonStatsTests {
    @Test("A skater's line is read by name from the All Splits row")
    func skater() throws {
        // nhl_splits_5080145.json (Cutter Gauthier, LW): names/displayNames/labels,
        // splitCategories[0] "split", splits[0] "All Splits".
        let line = parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_5080145"))
        #expect(line.loaded)
        #expect(line.title == "2025-26 Splits")
        #expect(line.stats.count == 15)
        #expect(line.stat("games")?.display == "76")
        #expect(line.stat("goals")?.display == "41")
        #expect(line.stat("goals")?.label == "Goals")
        #expect(line.stat("goals")?.abbreviation == "G")
        #expect(line.stat("assists")?.display == "28")
        #expect(line.stat("points")?.display == "69")
        #expect(line.stat("plusMinus")?.display == "-2")
        #expect(line.stat("timeOnIcePerGame")?.display == "17:15")
        #expect(line.stat("savePct") == nil)

        // Not the Home row (36 games, 24 goals).
        let sheet = hockeySheetStats(from: line)
        #expect(sheet.map(\.id) == hockeySkaterStatNames)
        #expect(sheet.prefix(4).map(\.display) == ["76", "41", "28", "69"])
    }

    @Test("A goalie's line gets the goaltending stats")
    func goalie() throws {
        // nhl_splits_4588165.json (Lukas Dostal, G): All Splits.
        let line = parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_4588165"))
        #expect(line.stats.count == 12)
        let sheet = hockeySheetStats(from: line)
        #expect(sheet.map(\.id) == hockeyGoalieStatNames)
        #expect(sheet.map(\.display) == ["55", "30", "20", "4", "169", "3.10", "1513", "1344", ".888", "0", "58:21"])
        #expect(line.stat("savePct")?.label == "Save Percentage")
    }

    @Test("A document with no season row, or none at all, is loaded and empty")
    func noSeasonRow() throws {
        // ncaaw_splits_5108548.json lists only Home and Away.
        let college = parseSplitsSeasonLine(from: try Fixture.json("ncaaw_splits_5108548"))
        #expect(college.loaded && college.stats.isEmpty)

        let failed = parseSplitsSeasonLine(from: .null)
        #expect(failed.loaded && failed.stats.isEmpty)
        #expect(hockeySheetStats(from: failed).isEmpty)
    }
}

// MARK: - Basketball and college football

@Suite("Player stats: the new basketball and football leagues", .tags(.golden))
struct NewLeagueAthleteStatsTests {
    @Test("NBA: the All Splits row alone, not All Splits plus Home")
    func nba() throws {
        // nba_splits_4869342.json (Dyson Daniels): splits All Splits (76 GP),
        // Home (37), Road (39), … Reading [0] and [1] as home and away gave
        // 113 games.
        let stats = parseBasketballPlayerStats(from: try Fixture.json("nba_splits_4869342"))
        #expect(stats.gamesPlayed == 76)
        #expect(approx(stats.avgPoints, 11.9))
        #expect(approx(stats.avgMinutes, 33.2))
        #expect(approx(stats.avgRebounds, 6.8))
        #expect(approx(stats.avgAssists, 5.9))
        #expect(approx(stats.avgSteals, 2.0))
        #expect(approx(stats.fieldGoalPct, 51.7))
        #expect(approx(stats.threePointFieldGoalPct, 18.8))
        #expect(approx(stats.freeThrowPct, 61.5))
    }

    @Test("WNBA: a lone All Splits row")
    func wnba() throws {
        // wnba_splits_3058901.json (Allisha Gray): one row, All Splits.
        let stats = parseBasketballPlayerStats(from: try Fixture.json("wnba_splits_3058901"))
        #expect(stats.gamesPlayed == 44)
        #expect(approx(stats.avgPoints, 19.0))
        #expect(approx(stats.avgMinutes, 32.6))
        #expect(approx(stats.avgRebounds, 3.5))
        #expect(approx(stats.avgAssists, 2.6))
    }

    @Test("NCAAW: home and away weighted by games, as in men's college basketball")
    func ncaaw() throws {
        // ncaaw_splits_5108548.json (Sania Copeland): Home 17 GP 3.1 PTS 18.0 MIN,
        // Away 14 GP 2.6 PTS 19.4 MIN.
        let stats = parseBasketballPlayerStats(from: try Fixture.json("ncaaw_splits_5108548"))
        #expect(stats.gamesPlayed == 31)
        #expect(approx(stats.avgPoints, (3.1 * 17 + 2.6 * 14) / 31))
        #expect(approx(stats.avgMinutes, (18.0 * 17 + 19.4 * 14) / 31))
    }

    @Test("NCAAF: a quarterback's passing and rushing from the Season row")
    func ncaaf() throws {
        // ncaaf_splits_5079604.json (Isaiah Marshall, QB): splits Season, Home.
        let stats = parseFootballPlayerStats(from: try Fixture.json("ncaaf_splits_5079604"))
        #expect(stats.loaded)
        #expect(stats.groups.map(\.title) == ["Passing", "Rushing"])
        let passing = try #require(stats.groups.first)
        #expect(passing.stats.map(\.id) == [
            "completions", "passingAttempts", "completionPct", "passingYards", "yardsPerPassAttempt",
            "longPassing", "passingTouchdowns", "interceptions", "sacks", "QBRating",
        ])
        #expect(passing.stats.map(\.display) == ["44", "82", "53.7", "649", "7.9", "47", "5", "3", "5", "132.8"])
        #expect(stats.groups[1].stats.map(\.display) == ["40", "124", "3.1", "13", "0"])
    }
}

// MARK: - Baseball

@Suite("Player stats: baseball season lines", .tags(.golden))
struct BaseballSeasonStatsTests {
    @Test("A pitcher's figures follow their names when ESPN reorders and inserts columns")
    func pitcherByName() throws {
        // royals_splits_5136077.json: a reliever's ERA "9.39", 6 games,
        // "7.2" innings, 12 strikeouts, ".371" against. The variant moves ERA
        // to the end and puts a column the parser does not know first (A-16).
        let splits = try Fixture.json("royals_splits_5136077")
        let names = splits["names"].arrayValue
        let values = splits["splitCategories", 0, "splits", 0, "stats"].arrayValue
        #expect(names.first?.stringValue == "ERA")

        let reordered = splits
            .setting(["names"], to: .array([JSON.string("WHIP")] + names.dropFirst() + [names[0]]))
            .setting(
                ["splitCategories", 0, "splits", 0, "stats"],
                to: .array([JSON.string("2.48")] + values.dropFirst() + [values[0]])
            )

        for document in [splits, reordered] {
            let stats = parseBaseballPlayerStats(from: document, playerPosition: "Relief Pitcher")
            #expect(approx(stats.EarnedRunAverage, 9.39))
            #expect(stats.gamesPlayed == 6)
            #expect(approx(stats.innings, 7.2))
            #expect(stats.hits == 13)
            #expect(stats.earnedRuns == 8)
            #expect(stats.strikeouts == 12)
            #expect(approx(stats.opponentAvg, 0.371))
        }
    }

    @Test("A batter's figures are read by name")
    func batterByName() {
        // The batting names are the fixture's
        // extraPlayerPageAthleteSplits.batting.names, here listed backwards.
        let document = JSON(data: Data("""
        {"names": ["OPS", "slugAvg", "onBasePct", "avg", "caughtStealing",
                   "stolenBases", "strikeouts", "hitByPitch", "walks", "RBIs",
                   "homeRuns", "triples", "doubles", "hits", "runs", "atBats"],
         "splitCategories": [{"splits": [{"stats": [
           ".812", ".455", ".357", ".281", "2", "11", "98", "4", "51", "77",
           "24", "3", "28", "142", "80", "505"]}]}]}
        """.utf8))
        let stats = parseBaseballPlayerStats(from: document, playerPosition: "Shortstop")
        #expect(stats.AtBats == 505)
        #expect(stats.Hits == 142)
        #expect(stats.HomeRuns == 24)
        #expect(stats.RBIs == 77)
        #expect(stats.StolenBases == 11)
        #expect(approx(stats.Avg, 0.281))
        #expect(approx(stats.OPS, 0.812))
        // The pitching half is untouched.
        #expect(stats.EarnedRunAverage == 0 && stats.wins == 0)
    }

    @Test("A document without names is still read by position")
    func positionalFallback() {
        let document = JSON(data: Data("""
        {"splitCategories": [{"splits": [{"stats": ["3.45", "12", "8"]}]}]}
        """.utf8))
        let stats = parseBaseballPlayerStats(from: document, playerPosition: "Starting Pitcher")
        #expect(approx(stats.EarnedRunAverage, 3.45))
        #expect(stats.wins == 12)
        #expect(stats.losses == 8)
        #expect(stats.saves == 0)
    }
}

// MARK: - Seasons

@Suite("Player stats: the seasons a splits document offers", .tags(.golden))
struct AthleteSeasonsTests {
    @Test("The season filter's options, newest first, and the one the document is for")
    func splitsSeasons() throws {
        // nhl_splits_5080145.json filters: season value "2026", options
        // 2026 "2025-26", 2025 "2024-25", 2024 "2023-24".
        let line = parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_5080145"))
        #expect(line.seasons.options.map(\.value) == ["2026", "2025", "2024"])
        #expect(line.seasons.options.map(\.label) == ["2025-26", "2024-25", "2023-24"])
        #expect(line.seasons.selected == "2026")

        // Every splits parser carries them.
        let nba = parseBasketballPlayerStats(from: try Fixture.json("nba_splits_4869342"))
        #expect(nba.seasons.options.map(\.value) == ["2026", "2025", "2024", "2023"])
        let pitcher = parseBaseballPlayerStats(from: try Fixture.json("royals_splits_5136077"), playerPosition: "Relief Pitcher")
        #expect(pitcher.seasons.options.map(\.label) == ["2026", "2025", "2024"])
        let football = parseFootballPlayerStats(from: try Fixture.json("ncaaf_splits_5079604"))
        #expect(football.seasons.options.map(\.value) == ["2026", "2025"])

        // chiefs_splits_4912218.json lists one season: nothing to pick.
        #expect(parseAthleteSeasons(from: try Fixture.json("chiefs_splits_4912218")).options.count == 1)
    }

    @Test("A document without a season filter, or a failed fetch, offers none")
    func noSeasons() {
        #expect(parseAthleteSeasons(from: .null) == .empty)
        #expect(parseSplitsSeasonLine(from: .null).seasons == .empty)
    }
}

// MARK: - Game logs

/// A fixture `gameDate` as the instant it names, from its Unix time.
private func utc(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite("Player stats: game logs", .tags(.golden))
struct GameLogTests {
    @Test("NFL quarterback: newest first, opponent, result and the passing line")
    func nflQuarterback() throws {
        // nfl_gamelog_3139477.json (Patrick Mahomes): 2026 Regular Season,
        // weeks 4 back to 1.
        let log = parseGameLog(from: try Fixture.json("nfl_gamelog_3139477"))
        #expect(log.loaded)
        #expect(log.rows.map(\.id) == ["401872976", "401872952", "401872945", "401872931"])

        let latest = try #require(log.rows.first)
        #expect(latest.date == utc(1_791_145_500))  // 2026-10-04T20:25:00.000+00:00
        #expect(latest.opponentID == "13")
        #expect(latest.opponentName == "Las Vegas Raiders")
        #expect(latest.opponentAbbreviation == "LV")
        #expect(!latest.isHome)
        #expect(latest.opponentSummary == "@ LV")
        #expect(latest.result == "W")
        #expect(latest.resultSummary == "W 30-27")
        #expect(latest.seasonType == "2026 Regular Season")
        #expect(latest.stats["passingYards"] == "225")
        #expect(latest.stats["passingTouchdowns"] == "2")
        #expect(latest.stats["QBRating"] == "97.2")
        #expect(latest.stats.count == 16)

        // Week 3 went to overtime at home.
        let colts = log.rows[2]
        #expect(colts.date == utc(1_789_950_000))  // 2026-09-21T00:20:00.000+00:00
        #expect(colts.isHome && colts.opponentAbbreviation == "IND")
        #expect(colts.resultSummary == "W 33-30 OT")
        #expect(colts.stats["passingYards"] == "382")

        #expect(log.headlineColumns.map(\.id) == ["passingYards", "passingTouchdowns", "interceptions", "QBRating"])
        #expect(log.headlineColumns.map(\.label) == ["YDS", "TD", "INT", "RTG"])
        #expect(log.headlineColumns.first?.displayName == "Passing Yards")
        #expect(log.seasons.selected == "2026")
    }

    @Test("NFL tight end: the receiving line, though his rushing columns match as many")
    func nflTightEnd() throws {
        // nfl_gamelog_15847.json (Travis Kelce): receiving, then rushing.
        let log = parseGameLog(from: try Fixture.json("nfl_gamelog_15847"))
        #expect(log.headlineColumns.map(\.id) == ["receptions", "receivingYards", "receivingTouchdowns", "receivingTargets"])
        let latest = try #require(log.rows.first)
        #expect(latest.opponentAbbreviation == "LV")
        #expect(latest.stats["receptions"] == "2")
        #expect(latest.stats["receivingYards"] == "15")
        #expect(latest.stats["receivingTargets"] == "4")
    }

    @Test("NBA: postseason before regular season before preseason")
    func nba() throws {
        // nba_gamelog_4869342.json (Dyson Daniels): 2025-26 Postseason
        // (Conference Quarterfinals ×6, an empty "total" category), Regular
        // Season (april … october, 76), Preseason (2).
        let log = parseGameLog(from: try Fixture.json("nba_gamelog_4869342"))
        #expect(log.rows.count == 84)

        let latest = try #require(log.rows.first)
        #expect(latest.id == "401869393")
        #expect(latest.date == utc(1_777_590_000))  // 2026-04-30T23:00:00.000+00:00
        #expect(latest.opponentID == "18")
        #expect(latest.opponentName == "New York Knicks")
        #expect(latest.isHome)
        #expect(latest.resultSummary == "L 140-89")
        #expect(latest.note == "East 1st Round - Game 6")
        #expect(latest.seasonType == "2025-26 Postseason")
        #expect(latest.stats["points"] == "3")
        #expect(latest.stats["fieldGoalsMade-fieldGoalsAttempted"] == "1-4")
        #expect(latest.stats["minutes"] == "15")

        #expect(log.rows[1].stats["points"] == "17")
        #expect(log.rows[1].opponentSummary == "@ NY")

        let regular = log.rows[6]
        #expect(regular.id == "401811028")
        #expect(regular.seasonType == "2025-26 Regular Season")
        #expect(regular.opponentAbbreviation == "CLE" && regular.resultSummary == "W 124-102")
        #expect(regular.note.isEmpty)

        #expect(log.rows.last?.id == "401812679")
        #expect(log.rows.last?.seasonType == "2025-26 Preseason")

        #expect(log.headlineColumns.map(\.id) == ["points", "totalRebounds", "assists", "minutes"])
        #expect(log.seasons.options.first?.value == "2027")
        #expect(log.seasons.selected == "2026")
    }

    @Test("MLB batter: AB, H, HR, RBI, and the running slash line in each row")
    func mlbBatter() throws {
        // mlb_gamelog_42403.json (Bobby Witt Jr.): 2026 Regular Season,
        // september … march, 144 games.
        let log = parseGameLog(from: try Fixture.json("mlb_gamelog_42403"))
        #expect(log.rows.count == 144)

        let latest = try #require(log.rows.first)
        #expect(latest.id == "401817109")
        #expect(latest.date == utc(1_790_536_200))  // 2026-09-27T19:10:00.000+00:00
        #expect(latest.opponentID == "5" && latest.opponentAbbreviation == "CLE")
        #expect(latest.isHome)
        #expect(latest.resultSummary == "W 3-2")
        #expect(latest.stats["atBats"] == "4")
        #expect(latest.stats["hits"] == "0")
        #expect(latest.stats["avg"] == ".281")
        #expect(latest.stats["OPS"] == ".800")

        let previous = log.rows[1]
        #expect(previous.date == utc(1_790_464_200))  // 2026-09-26T23:10:00.000+00:00
        #expect(previous.resultSummary == "L 11-5")
        #expect(previous.stats["hits"] == "2" && previous.stats["doubles"] == "1")

        #expect(log.headlineColumns.map(\.id) == ["atBats", "hits", "homeRuns", "RBIs"])
        #expect(log.headlineColumns.map(\.label) == ["AB", "H", "HR", "RBI"])
    }

    @Test("MLB pitcher: the pitching line, by name")
    func mlbPitcher() throws {
        // mlb_gamelog_5136077.json (Royals reliever): six games.
        let log = parseGameLog(from: try Fixture.json("mlb_gamelog_5136077"))
        #expect(log.rows.count == 6)
        let latest = try #require(log.rows.first)
        #expect(latest.id == "401817094")
        #expect(latest.stats["innings"] == "0.2")
        #expect(latest.stats["walks"] == "2")
        #expect(latest.stats["ERA"] == "9.39")
        #expect(log.rows[3].stats["saves-blownSaves-holds"] == "HLD(1)")
        #expect(log.headlineColumns.map(\.id) == ["innings", "hits", "earnedRuns", "strikeouts"])
    }

    @Test("NHL: a skater's and a goalie's lines in the same three games")
    func nhl() throws {
        // nhl_gamelog_5080145.json (Cutter Gauthier) and
        // nhl_gamelog_4588165.json (Lukas Dostal): 2026-27, October.
        let skater = parseGameLog(from: try Fixture.json("nhl_gamelog_5080145"))
        #expect(skater.rows.map(\.opponentAbbreviation) == ["EDM", "FLA", "VGK"])
        let latest = try #require(skater.rows.first)
        #expect(latest.date == utc(1_791_424_800))  // 2026-10-08T02:00:00.000+00:00
        #expect(latest.isHome && latest.resultSummary == "L 5-2")
        #expect(latest.stats["plusMinus"] == "-2")
        #expect(latest.stats["timeOnIcePerGame"] == "24:10")
        #expect(skater.rows[1].resultSummary == "W 3-2 OT")
        #expect(skater.rows[1].stats["goals"] == "2")
        #expect(skater.headlineColumns.map(\.id) == ["goals", "assists", "points", "plusMinus"])

        let goalie = parseGameLog(from: try Fixture.json("nhl_gamelog_4588165"))
        #expect(goalie.rows.first?.stats["saves"] == "12")
        #expect(goalie.rows.first?.stats["savePct"] == ".706")
        #expect(goalie.headlineColumns.map(\.id) == ["saves", "goalsAgainst", "savePct"])
    }

    @Test("EPL: five league matches with goals, assists and shots")
    func epl() throws {
        // epl_gamelog_280555.json (Bukayo Saka): 2026-27 English Premier League.
        let log = parseGameLog(from: try Fixture.json("epl_gamelog_280555"))
        #expect(log.rows.map(\.opponentAbbreviation) == ["BHA", "SUN", "CHE", "AVL", "COV"])
        let latest = try #require(log.rows.first)
        #expect(latest.date == utc(1_789_826_400))  // 2026-09-19T14:00:00.000+00:00
        #expect(latest.opponentID == "331" && latest.opponentName == "Brighton & Hove Albion")
        #expect(!latest.isHome)
        #expect(latest.resultSummary == "L 3-0")
        #expect(latest.stats["totalShots"] == "2")
        #expect(log.rows[1].stats["totalGoals"] == "1")
        #expect(log.headlineColumns.map(\.id) == ["totalGoals", "goalAssists", "totalShots", "shotsOnTarget"])
    }

    @Test("A failed fetch is a loaded, empty log; an unknown line shows its first columns")
    func edges() {
        let failed = parseGameLog(from: .null)
        #expect(failed.loaded && failed.rows.isEmpty && failed.headlineColumns.isEmpty)

        let document = JSON(data: Data("""
        {"names": ["a", "b", "c", "d", "e"], "labels": ["A", "B", "C", "D", "E"],
         "events": {"1": {"atVs": "@", "gameDate": "2026-10-04T20:25Z", "score": "1-1", "gameResult": "D"}},
         "seasonTypes": [{"displayName": "S", "categories": [
           {"type": "event", "events": [{"eventId": "1", "stats": ["1", "2", "3", "4", "5"]},
                                        {"eventId": "1", "stats": ["9", "9", "9", "9", "9"]},
                                        {"eventId": "2", "stats": ["9", "9", "9", "9", "9"]}]},
           {"type": "total", "totals": ["1", "2", "3", "4", "5"]}]}]}
        """.utf8))
        let log = parseGameLog(from: document)
        // The repeat of game 1 and game 2, missing from `events`, are dropped.
        #expect(log.rows.count == 1)
        #expect(log.rows.first?.stats["a"] == "1")
        #expect(log.rows.first?.date == utc(1_791_145_500))
        #expect(log.rows.first?.resultSummary == "D 1-1")
        #expect(log.headlineColumns.map(\.label) == ["A", "B", "C", "D"])
    }
}

// MARK: - Baseball slash line

@Suite("Player stats: the baseball slash line")
struct BaseballSlashLineTests {
    @Test("Rates read as the box score prints them")
    func format() {
        var stats = BaseballPlayerStats.empty
        stats.Avg = 0.281
        stats.OnBasePct = 0.357
        stats.SlugAvg = 0.455
        #expect(baseballSlashLine(stats) == ".281/.357/.455")

        stats.SlugAvg = 1
        #expect(baseballSlashLine(stats) == ".281/.357/1.000")
        #expect(baseballSlashLine(.empty) == ".000/.000/.000")
    }
}

// MARK: - Player sheet

@Suite("Player sheet: every sport's About card says Hometown", .tags(.golden))
struct PlayerSheetHometownTests {
    /// The About card's fact titles, in reading order.
    private func titles(_ grid: PlayerSheetGrid) -> [String] {
        grid.sections.flatMap(\.rows).flatMap { $0 }.map(\.title)
    }

    @Test("Basketball, football, baseball and hockey title the fact alike")
    func hometown() throws {
        // Was "HomeTown", and baseball's "Home Town".
        let basketball = try #require(parseBasketballRoster(from: try Fixture.json("jayhawks_roster")).first)
        let football = try #require(parseFootballRoster(from: try Fixture.json("chiefs_roster")).first)
        let baseball = try #require(parseBaseballRoster(from: try Fixture.json("royals_roster")).first)
        let hockey = try #require(parseHockeyRoster(from: try Fixture.json("nhl_roster")).first)
        for about in [basketball.about, football.about, baseball.about, hockey.about] {
            #expect(titles(about).contains("Hometown"))
            #expect(!titles(about).contains("HomeTown") && !titles(about).contains("Home Town"))
        }
    }

    @Test("A season line with no games yet reads as empty; one with figures doesn't")
    func noFigures() throws {
        // jayhawks_roster.json Jackson (4872739) before the sheet's fetch: the
        // basketball placeholder, every figure 0.0 and every ring 0%.
        let roster = parseBasketballRoster(from: try Fixture.json("jayhawks_roster"))
        let jackson = try #require(roster.first { $0.playerID == "4872739" })
        #expect(jackson.placeholderStatistics.hasNoFigures)

        // nwsl_roster.json Maiara Niehues (402432): 19 appearances, 9 goals.
        let niehues = try #require(parseSoccerRoster(from: try Fixture.json("nwsl_roster")).first { $0.playerID == "402432" })
        #expect(!niehues.placeholderStatistics.hasNoFigures)
    }
}

@Suite("Player sheet: empty seasons, missing facts and grid columns")
struct PlayerSheetGridTests {
    @Test("Zero however it's written, or missing, is no figure")
    func emptyFigures() {
        let zeros = PlayerSheetGrid(rows: [
            [
                .stat(title: "Average Points", info: "0.0"),
                .stat(title: "Slash Line", info: ".000/.000/.000"),
                .stat(title: "Time On Ice Per Game", info: "0:00"),
            ],
            [
                .stat(title: "Goals", info: "N/A"),
                .stat(title: "Assists", info: " -- "),
                .percentage(title: "Save Percentage", progress: .nan),
                .percentage(title: "Field Goal Percentage", progress: 0),
            ],
        ])
        #expect(zeros.hasNoFigures)

        // One real figure, even a negative one, is a season.
        var plusMinus = zeros
        plusMinus.sections[0].rows[0].append(.stat(title: "Plus/Minus", info: "-2"))
        #expect(!plusMinus.hasNoFigures)
        var ring = zeros
        ring.sections[0].rows[0].append(.percentage(title: "Free Throw Percentage", progress: 0.5))
        #expect(!ring.hasNoFigures)

        // "0" games played is empty whatever else the line says.
        let noGames = PlayerSheetGrid(rows: [[
            .stat(title: "Games Played", info: "0"),
            .stat(title: "Average Points", info: "12.0"),
        ]])
        #expect(noGames.hasNoFigures)

        // A grid with no cells has its own message.
        #expect(!PlayerSheetGrid(sections: []).hasNoFigures)
    }

    @Test("Missing facts and Position are left off the About card")
    func aboutFacts() {
        let about = PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: "Guard"),
                .fact(title: "Class", info: "N/A"),
                .fact(title: "Status", info: "n/a "),
            ],
            [
                .fact(title: "Height", info: " -- "),
                .fact(title: "Weight", info: "-"),
                .fact(title: "Hometown", info: " Lawrence, KS "),
            ],
            [
                .fact(title: "Age", info: ""),
            ],
        ])
        #expect(about.aboutFacts.map(\.title) == ["Hometown"])
        #expect(about.aboutFacts.map(\.info) == ["Lawrence, KS"])

        // A box-score player with nothing known: no facts, so no card.
        let unknown = PlayerSheetGrid(rows: [[
            .fact(title: "Position", info: "Forward"),
            .fact(title: "Height", info: "N/A"),
        ]])
        #expect(unknown.aboutFacts.isEmpty)
    }

    @Test("A lone cell on the last row gives up a column when that fills every row")
    func columnCount() {
        // Basketball's ten remaining cells: 3+3+3+1 becomes 2+2+2+2+2.
        #expect(PlayerSheetGrid.columnCount(fitting: 3, cells: 10) == 2)
        #expect(PlayerSheetGrid.columnCount(fitting: 3, cells: 4) == 2)
        #expect(PlayerSheetGrid.columnCount(fitting: 4, cells: 9) == 3)
        // Already even, or no fewer columns would do better.
        #expect(PlayerSheetGrid.columnCount(fitting: 3, cells: 9) == 3)
        #expect(PlayerSheetGrid.columnCount(fitting: 3, cells: 7) == 3)
        #expect(PlayerSheetGrid.columnCount(fitting: 3, cells: 1) == 3)
        #expect(PlayerSheetGrid.columnCount(fitting: 2, cells: 5) == 2)
        // Never fewer than one, as at the largest text sizes.
        #expect(PlayerSheetGrid.columnCount(fitting: 0, cells: 3) == 1)
    }
}

// MARK: - Player sheet redesign

/// The titles of a grid's cells, in reading order.
private func cellTitles(_ sections: [PlayerSheetGrid.Section]) -> [String] {
    sections.flatMap(\.rows).flatMap { $0 }.map(\.title)
}

@Suite("Player sheet: key statistics by sport and position", .tags(.golden))
struct PlayerSheetKeyStatTests {
    @Test("A soccer outfield player leads with goals, assists, appearances and starts")
    func soccerOutfield() throws {
        // nwsl_roster.json Maiara Niehues (402432): 19 appearances, 4 off
        // the bench, 9 goals, 0 assists, 46 shots, 2 offsides, 0 own goals.
        let niehues = try #require(parseSoccerRoster(from: try Fixture.json("nwsl_roster")).first { $0.playerID == "402432" })
        let grid = niehues.placeholderStatistics
        let featured = grid.featuredCells(for: niehues.featuredStatistics)
        #expect(featured.map(\.cell.title) == ["Total Goals", "Goal Assists", "Games Played", "Games Started"])
        #expect(featured.map(\.feature.abbreviation) == ["Goals", "Assists", "Apps", "Starts"])
        // VoiceOver: "Goals, 9".
        #expect(featured.map(\.spokenTitle) == ["Goals", "Assists", "Appearances", "Starts"])
        #expect(featured.map(\.cell.displayValue) == ["9", "0", "19", "15"])

        let rest = grid.remainingSections(excluding: featured)
        #expect(rest.map(\.title) == ["Appearances", "Attacking", "Discipline"])
        let titles = cellTitles(rest)
        #expect(!titles.contains("Total Goals") && !titles.contains("Games Played"))
        // Offsides has two; no own goals, so no row for them.
        #expect(titles.contains("Offsides"))
        #expect(!titles.contains("Own Goals"))
        #expect(titles.contains("Shot Accuracy") && titles.contains("Conversion Rate"))

        let cells = rest.flatMap(\.rows).flatMap { $0 }
        #expect(cells.first { $0.title == "Goals per Game" }?.displayValue == "0.47")
        #expect(cells.first { $0.title == "Shots per Game" }?.displayValue == "2.42")
        let accuracy = try #require(cells.first { $0.title == "Shot Accuracy" }?.barFraction)
        #expect(abs(accuracy - 16.0 / 46.0) < 0.0001)
        #expect(cells.first { $0.title == "Yellow Cards" }?.glyph == .yellowCard)
        #expect(cells.first { $0.title == "Red Cards" }?.glyph == .redCard)
        #expect(cells.first { $0.title == "Fouls Committed" }?.glyph == nil)
    }

    @Test("A goalkeeper leads with saves, goals conceded, appearances and starts")
    func soccerKeeper() throws {
        // sporting_roster.json Stefan Cleveland (249729, Goalkeeper): 17
        // appearances, none off the bench, 59 saves, 38 conceded. The roster
        // has no clean sheets, so that tile is skipped.
        let cleveland = try #require(parseSoccerRoster(from: try Fixture.json("sporting_roster")).first { $0.playerID == "249729" })
        #expect(isSoccerGoalkeeper(cleveland.position))
        let grid = cleveland.placeholderStatistics
        let featured = grid.featuredCells(for: cleveland.featuredStatistics)
        #expect(featured.map(\.cell.title) == ["Goals Saved", "Goals Conceded", "Games Played", "Starts"])
        #expect(featured.map(\.spokenTitle) == ["Saves", "Goals conceded", "Appearances", "Starts"])
        #expect(featured.map(\.cell.displayValue) == ["59", "38", "17", "17"])

        let rest = grid.remainingSections(excluding: featured)
        #expect(rest.map(\.title) == ["Goalkeeping", "Discipline"])
        let cells = rest.flatMap(\.rows).flatMap { $0 }
        let saves = try #require(cells.first { $0.title == "Save Percentage" }?.barFraction)
        #expect(abs(saves - 59.0 / 97.0) < 0.0001)
    }

    @Test("A football player's key stats come from his position's group")
    func football() {
        // "Yards" and "Touchdowns" are in every group: each feature looks
        // only in its own.
        let grid = PlayerSheetGrid(sections: [
            PlayerSheetGrid.Section(title: "Passing", rows: [[
                .stat(title: "Yards", info: "3,512"),
                .stat(title: "Touchdowns", info: "28"),
                .stat(title: "Interceptions", info: "9"),
                .stat(title: "Rating", info: "101.2"),
                .stat(title: "Completions", info: "301"),
            ]]),
            PlayerSheetGrid.Section(title: "Rushing", rows: [[
                .stat(title: "Yards", info: "311"),
                .stat(title: "Touchdowns", info: "4"),
                .stat(title: "Avg / Carry", info: "5.2"),
            ]]),
            PlayerSheetGrid.Section(title: "Receiving", rows: [[
                .stat(title: "Receptions", info: "1"),
                .stat(title: "Yards", info: "6"),
            ]]),
        ])

        let passer = grid.featuredCells(for: footballKeyStats(position: "Quarterback"))
        #expect(passer.map(\.cell.displayValue) == ["3,512", "28", "9", "101.2"])
        #expect(passer.allSatisfy { $0.section == 0 })
        #expect(passer.map(\.spokenTitle) == ["Passing yards", "Passing touchdowns", "Interceptions thrown", "Passer rating"])
        let rest = grid.remainingSections(excluding: passer)
        // The rushing and receiving yards stay in their groups.
        #expect(rest.map(\.title) == ["Passing", "Rushing", "Receiving"])
        #expect(cellTitles(rest) == ["Completions", "Yards", "Touchdowns", "Avg / Carry", "Receptions", "Yards"])

        let runner = grid.featuredCells(for: footballKeyStats(position: "Running Back"))
        #expect(runner.map(\.cell.displayValue) == ["311", "4", "5.2", "1"])
        #expect(runner.map(\.feature.abbreviation) == ["Rush Yds", "Rush TD", "YPC", "Rec"])

        let receiver = grid.featuredCells(for: footballKeyStats(position: "Wide Receiver"))
        #expect(Array(receiver.map(\.feature.abbreviation).prefix(2)) == ["Rec", "Rec Yds"])
        #expect(Array(receiver.map(\.cell.displayValue).prefix(2)) == ["1", "6"])
    }

    @Test("Baseball: a pitcher's ERA, W-L, strikeouts and WHIP; a batter's AVG, HR, RBI and OPS")
    func baseball() throws {
        let roster = parseBaseballRoster(from: try Fixture.json("royals_roster"))
        let pitcher = try #require(roster.first { $0.position.contains("Pitcher") })
        let pitching = pitcher.placeholderStatistics.featuredCells(for: pitcher.featuredStatistics)
        #expect(pitching.map(\.cell.title) == ["Earned Run Avg.", "Win-Loss Record", "Strikeouts", "WHIP"])
        // A line of zeros is still no season (`hasNoFigures`).
        #expect(pitcher.placeholderStatistics.hasNoFigures)

        let batter = try #require(roster.first { !$0.position.contains("Pitcher") })
        let batting = batter.placeholderStatistics.featuredCells(for: batter.featuredStatistics)
        #expect(batting.map(\.feature.abbreviation) == ["AVG", "HR", "RBI", "OPS"])
        #expect(batting.map(\.cell.displayValue) == [".000", "0", "0", ".000"])
    }

    @Test("Basketball's per-game line and hockey's skater line")
    func basketballAndHockey() throws {
        let jackson = try #require(parseBasketballRoster(from: try Fixture.json("jayhawks_roster")).first { $0.playerID == "4872739" })
        let tiles = jackson.placeholderStatistics.featuredCells(for: jackson.featuredStatistics)
        #expect(tiles.map(\.feature.abbreviation) == ["PPG", "RPG", "APG", "MPG"])

        // nhl_splits_5080145.json (Cutter Gauthier): 41 G, 28 A, 69 PTS, -2.
        let line = parseSplitsSeasonLine(from: try Fixture.json("nhl_splits_5080145"))
        let skater = PlayerSheetGrid(rows: [hockeySheetStats(from: line).map { PlayerSheetCell.stat(title: $0.label, info: $0.display) }])
        let hockey = try #require(parseHockeyRoster(from: try Fixture.json("nhl_roster")).first)
        let featured = skater.featuredCells(for: hockey.featuredStatistics)
        #expect(featured.map(\.feature.abbreviation) == ["G", "A", "PTS", "+/-"])
        #expect(featured.map(\.cell.displayValue) == ["41", "28", "69", "-2"])
    }

    @Test("A quiet stat shows once it isn't zero")
    func quietCells() {
        let grid = PlayerSheetGrid(sections: [
            PlayerSheetGrid.Section(title: "Discipline", rows: [[
                .stat(title: "Own Goals", info: "0"),
                .stat(title: "Offsides", info: "3"),
                .stat(title: "Red Cards", info: "0"),
            ]]),
            PlayerSheetGrid.Section(title: "Quiet", rows: [[
                .stat(title: "Own Goals", info: "0"),
            ]]),
        ])
        let rest = grid.remainingSections(excluding: [])
        // Red cards say something at zero; a section left empty goes.
        #expect(rest.map(\.title) == ["Discipline"])
        #expect(cellTitles(rest) == ["Offsides", "Red Cards"])
    }
}

@Suite("Player sheet: rates, totals from the game log, avatars and flags")
struct PlayerSheetHelperTests {
    @Test("Rates a game, and the baseball rates")
    func rates() {
        #expect(perGameRate(9, games: 19) == "0.47")
        #expect(perGameRate(0, games: 8) == "0.00")
        #expect(perGameRate(3, games: 0) == "N/A")

        #expect(baseballRate(0.281) == ".281")
        #expect(baseballRate(1) == "1.000")
        // 76.1 innings is 76 and a third.
        #expect(abs(baseballInnings(76.1) - (76 + 1.0 / 3)) < 0.0001)
        #expect(abs(baseballInnings(5.2) - (5 + 2.0 / 3)) < 0.0001)
        #expect(baseballInnings(0) == 0)
        // royals_splits_5136077-shaped line: 35 walks, 61 hits, 76.1 IP.
        #expect(baseballWHIP(walks: 35, hits: 61, innings: 76.1) == "1.26")
        #expect(baseballWHIP(walks: 0, hits: 0, innings: 0) == "N/A")
    }

    @Test("A season summed from the game log: counts only, headline first", .tags(.golden))
    func logTotals() throws {
        // epl_gamelog_280555.json (Bukayo Saka): five matches, 3 goals on
        // 15 shots, 9 on target, 2 fouls, 15 fouled, 4 offsides.
        let log = parseGameLog(from: try Fixture.json("epl_gamelog_280555"))
        let totals = log.summedTotals
        #expect(totals.map(\.id) == [
            "totalGoals", "goalAssists", "totalShots", "shotsOnTarget",
            "foulsCommitted", "foulsSuffered", "offsides", "yellowCards", "redCards",
        ])
        #expect(totals.map(\.display) == ["3", "0", "15", "9", "2", "15", "4", "0", "0"])
        #expect(totals.prefix(4).map(\.abbreviation) == ["G", "A", "SH", "SOT"])
        #expect(totals.first?.label == "Total Goals")

        // The crest each game's opponent is drawn with.
        #expect(log.rows.first?.opponentLogo == "https://a.espncdn.com/i/teamlogos/soccer/500/331.png")
    }

    @Test("Summing skips rates, dashes and an empty log; half a sack keeps its place")
    func logTotalsShapes() {
        func game(_ id: String, _ stats: [String: String]) -> GameLogRow {
            GameLogRow(
                id: id, date: nil, opponentID: "", opponentName: "", opponentAbbreviation: "",
                isHome: true, result: "", score: "", note: "", seasonType: "", stats: stats
            )
        }
        let log = AthleteGameLog(
            columns: [
                GameLogColumn(id: "totalTackles", label: "TOT", displayName: "Total Tackles"),
                GameLogColumn(id: "sacks", label: "SACK", displayName: "Sacks"),
                GameLogColumn(id: "yardsPerReception", label: "AVG", displayName: "Yards Per Reception"),
                GameLogColumn(id: "fumblesForced", label: "FF", displayName: "Forced Fumbles"),
            ],
            rows: [
                game("1", ["totalTackles": "4", "sacks": "0.5", "yardsPerReception": "12.0", "fumblesForced": "-"]),
                game("2", ["totalTackles": "6", "sacks": "1", "yardsPerReception": "8.0", "fumblesForced": "-"]),
            ],
            seasons: .empty,
            loaded: true
        )
        let totals = log.summedTotals
        #expect(totals.map(\.id) == ["totalTackles", "sacks"])
        #expect(totals.map(\.display) == ["10", "1.5"])

        #expect(AthleteGameLog.empty.summedTotals.isEmpty)
        #expect(gameLogTotalsCaption(games: 4) == "From the last 4 games")
        #expect(gameLogTotalsCaption(games: 1) == "From the last game")
    }

    @Test("A goal, touchdown or home run is picked out once there is one")
    func emphasis() {
        #expect(gameLogEmphasizes(columnID: "totalGoals", value: "2"))
        #expect(gameLogEmphasizes(columnID: "receivingTouchdowns", value: "1"))
        #expect(!gameLogEmphasizes(columnID: "totalGoals", value: "0"))
        #expect(!gameLogEmphasizes(columnID: "totalShots", value: "5"))
        #expect(!gameLogEmphasizes(columnID: "homeRuns", value: "–"))
    }

    @Test("The jersey avatar shows the number, else the position, else the name")
    func avatarLabel() {
        #expect(jerseyAvatarLabel(number: "11", position: "Forward", name: "André Luiz") == "11")
        #expect(jerseyAvatarLabel(number: " ", position: "Wide Receiver", name: "Cyrus Allen") == "WR")
        #expect(jerseyAvatarLabel(number: "", position: "", name: "André Luiz") == "AL")
        #expect(jerseyAvatarLabel(number: "", position: "", name: "") == "")
        #expect(positionInitials("Starting Pitcher") == "SP")
        #expect(positionInitials("Forward") == "F")
        #expect(nameInitials("Felix Anudike-Uzomah") == "FA")
        #expect(isSoccerGoalkeeper("Goalkeeper"))
        #expect(!isSoccerGoalkeeper("Forward"))
    }

    @Test("A nationality's flag, where the name maps to one")
    func flags() {
        #expect(countryFlag("Brazil") == "\u{1F1E7}\u{1F1F7}")
        #expect(countryFlag("USA") == "\u{1F1FA}\u{1F1F8}")
        #expect(countryFlag(" Colombia ") == "\u{1F1E8}\u{1F1F4}")
        #expect(countryFlag("England") == "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}")
        #expect(countryFlag("Northern Ireland") == nil)
        #expect(countryFlag("N/A") == nil)
        #expect(countryFlag("") == nil)
        #expect(countryFlag("Atlantis") == nil)
        #expect(regionalIndicatorFlag("br") == "\u{1F1E7}\u{1F1F7}")
        #expect(regionalIndicatorFlag("B1") == nil)
        #expect(regionalIndicatorFlag("USA") == nil)
    }

    @Test("Every About fact has a symbol")
    func factSymbols() {
        #expect(playerFactSymbol("Height") == "ruler")
        #expect(playerFactSymbol("Citizenship") == "flag")
        #expect(playerFactSymbol("Something New") == "info.circle")
    }
}
