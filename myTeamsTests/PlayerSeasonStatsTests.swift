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
