//
//  StandingsTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Every captured standings document, its league, and the rows it holds
/// across all its tables (see FIXTURES.md, "New leagues (P3-a)").
private let capturedStandings: [(fixture: String, league: LeagueID, rows: Int, groups: Int)] = [
    ("nba_standings", .nba, 30, 2),
    ("wnba_standings", .wnba, 15, 2),
    ("nhl_standings", .nhl, 32, 2),
    // Trimmed to Big 12 and Sun Belt; Sun Belt is two division tables.
    ("ncaaf_standings", .collegeFootball, 30, 3),
    ("ncaaw_standings", .womensCollegeBasketball, 25, 2),
    ("epl_standings", .premierLeague, 20, 1),
    ("laliga_standings", .laLiga, 20, 1),
    ("ligamx_standings", .ligaMX, 18, 1),
    ("nwsl_standings", .nwsl, 16, 1),
]

private func standings(_ fixture: String, _ league: LeagueID) throws -> Standings {
    parseStandings(from: try Fixture.json(fixture), league: league)
}

/// A hand-written document, for shapes no fixture holds.
private func document(_ text: String) -> JSON {
    JSON(data: Data(text.utf8))
}

@Suite("Standings parsing")
struct StandingsParsingTests {
    @Test("Every captured tree parses into its tables, every row named and ranked by the league's shape")
    func everyFixture() throws {
        for captured in capturedStandings {
            let parsed = try standings(captured.fixture, captured.league)
            #expect(parsed.groups.count == captured.groups, "\(captured.fixture)")
            #expect(parsed.groups.reduce(0) { $0 + $1.entries.count } == captured.rows, "\(captured.fixture)")
            #expect(parsed.groups.allSatisfy { !$0.entries.isEmpty }, "\(captured.fixture)")
            for entry in parsed.groups.flatMap(\.entries) {
                #expect(!entry.teamID.isEmpty && !entry.name.isEmpty, "\(captured.fixture)")
                #expect(entry.record.format == captured.league.descriptor.kind.standingsRecordFormat)
            }
            let kind: StandingsKind = captured.league.descriptor.kind == .soccer ? .pointsTable : .records
            #expect(parsed.kind == kind, "\(captured.fixture)")
        }
    }

    // MARK: Soccer

    @Test("EPL: a points table, W-D-L and points, with goal difference and the qualification note")
    func eplTable() throws {
        let table = try standings("epl_standings", .premierLeague)
        #expect(table.kind == .pointsTable)
        // children[0].standings.seasonDisplayName
        #expect(table.seasonDisplayName == "2026-27 English Premier League")

        let group = try #require(table.groups.first)
        #expect(group.id == "1")
        #expect(group.name == "2026-27 English Premier League")
        #expect(group.entries.map(\.rank) == (1...20).map { Optional($0) })
        #expect(group.entries.first?.teamID == "382")  // Manchester City, 5-0-0, 15 pts

        // Arsenal (359), entries[1]: W 4, D (`ties`) 0, L 1, P 12, GD "+4",
        // note "Champions League" #81D6AC.
        let arsenal = try #require(table.entry(for: "359"))
        #expect(arsenal.name == "Arsenal")
        #expect(arsenal.abbreviation == "ARS")
        #expect(arsenal.rank == 2)
        #expect(arsenal.record == Record(wins: 4, losses: 1, ties: 0, points: 12, format: .winDrawLossPoints))
        #expect(arsenal.record.summary == "4-0-1, 12 pts")
        #expect(arsenal.record.gamesPlayed == 5)  // stats.gamesPlayed
        #expect(arsenal.goalDifference == "+4")
        #expect(arsenal.note == "Champions League")
        #expect(arsenal.noteColorHex == "81D6AC")
        // A points table keeps no games behind.
        #expect(arsenal.gamesBehind == "")
        #expect(arsenal.logoURL != nil)

        // Tottenham (367), last: W 0, D 2, L 3, 2 pts, relegation.
        let spurs = try #require(group.entries.last)
        #expect(spurs.teamID == "367")
        #expect(spurs.shortName == "Spurs")
        #expect(spurs.record.summary == "0-2-3, 2 pts")
        #expect(spurs.goalDifference == "-6")
        #expect(spurs.note == "Relegation")
    }

    @Test("NWSL: a draw-heavy table agrees with the feed's own W-D-L summary")
    func nwslTable() throws {
        // Every row's `overall` summary is W-D-L; the parser reads the named
        // stats, so the two must agree row for row.
        let json = try Fixture.json("nwsl_standings")
        let table = parseStandings(from: json, league: .nwsl)
        let summaries = json["children", 0, "standings", "entries"].arrayValue.map { entry in
            entry["stats"].arrayValue.first { $0["type"].stringValue == "total" }?["displayValue"].stringValue ?? ""
        }
        #expect(table.groups[0].entries.map { "\($0.record.wins)-\($0.record.ties)-\($0.record.losses)" } == summaries)

        // Angel City (21422): 12 W, 6 D, 8 L, 42 pts, sixth.
        let angelCity = try #require(table.entry(for: "21422"))
        #expect(angelCity.rank == 6)
        #expect(angelCity.record.summary == "12-6-8, 42 pts")
    }

    @Test("Bundesliga: rows marked with their zones, and one legend line per distinct note (C-2)")
    func bundesZones() throws {
        let table = try standings("bundes_standings", .bundesliga)
        #expect(table.kind == .pointsTable)
        let group = try #require(table.groups.first)
        #expect(group.entries.count == 18)

        // Rows 1-7 and 16-18 carry a note; 8th to 15th none.
        #expect(group.entries.map { $0.zone != nil } == (1...18).map { !(8...15).contains($0) })
        // Hamburg (127), 16th: note {"color": "#FEB4B5", "description": "Relegation playoff"}.
        let hamburg = try #require(table.entry(for: "127"))
        #expect(hamburg.rank == 16)
        #expect(hamburg.zone == StandingsZone(note: "Relegation playoff", colorHex: "FEB4B5"))
        // Werder Bremen (137), 8th: no note, so no bar.
        #expect(table.entry(for: "137")?.zone == nil)

        // Top of the table first. Europa League and Conference League
        // qualifying share a colour but each gets its own line.
        #expect(group.zones == [
            StandingsZone(note: "Champions League", colorHex: "81D6AC"),
            StandingsZone(note: "Europa League", colorHex: "B2BFD0"),
            StandingsZone(note: "Conference League qualifying", colorHex: "B2BFD0"),
            StandingsZone(note: "Relegation playoff", colorHex: "FEB4B5"),
            StandingsZone(note: "Relegation", colorHex: "FF7F84"),
        ])

        // A table with no notes has no legend.
        #expect(try standings("nba_standings", .nba).groups.allSatisfy(\.zones.isEmpty))
    }

    @Test("A soccer table goes by the league's name, not the season's, in its title and the header (B-8)")
    func soccerTableTitle() throws {
        let table = try standings("bundes_standings", .bundesliga)
        let group = try #require(table.groups.first)
        let leagueName = LeagueID.bundesliga.descriptor.displayName
        #expect(leagueName == "Bundesliga")
        // The feed names its one table after the season.
        #expect(group.name == "2026-27 German Bundesliga")
        #expect(group.title(kind: table.kind, leagueName: leagueName) == "Bundesliga")

        // SC Freiburg (126): 3 W, 1 D, 0 L, 10 pts, third.
        let freiburg = TeamRef(
            league: .bundesliga, espnID: "126",
            displayName: "SC Freiburg", shortName: "Freiburg", abbreviation: "SCF", location: "",
            colorHex: "", alternateColorHex: "",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        let summary = TeamHeaderSummary(
            team: freiburg, games: [], nextGame: 0,
            record: Record(wins: 3, losses: 0, ties: 1, format: .winLossTie), standings: table
        )
        #expect(summary.standing == "3rd in Bundesliga")
        #expect(TeamHeaderSummary.standing(of: "126", in: table, leagueName: leagueName) == "3rd in Bundesliga")

        // The schedule's record reads in the table's W-D-L order.
        let row = try #require(table.entry(for: "126"))
        #expect(row.record.summary == "3-1-0, 10 pts")
        #expect(Record(wins: 3, losses: 0, ties: 1, format: .winLossTie).summary == "3-1-0")

        // A conference keeps the feed's name: Kansas (2305), 16th in the Big 12.
        let ncaaf = try standings("ncaaf_standings", .collegeFootball)
        let big12 = try #require(ncaaf.group(containing: "2305"))
        #expect(big12.title(kind: ncaaf.kind, leagueName: "NCAA Football") == "Big 12 Conference")
        #expect(TeamHeaderSummary.standing(of: "2305", in: ncaaf, leagueName: "NCAA Football") == "16th in Big 12 Conference")
    }

    // MARK: Basketball

    @Test("NBA: two conferences in preseason, every seed 0 so feed order is kept")
    func nbaPreseason() throws {
        let table = try standings("nba_standings", .nba)
        #expect(table.kind == .records)
        #expect(table.seasonDisplayName == "2026-27")
        #expect(table.groups.map(\.name) == ["Eastern Conference", "Western Conference"])
        #expect(table.groups.map(\.id) == ["5", "6"])
        #expect(table.groups.map(\.abbreviation) == ["East", "West"])

        // Hawks (1), first in the East: 0-0, GB "-", seed 0.
        let hawks = try #require(table.entry(for: "1"))
        #expect(table.group(containing: "1")?.name == "Eastern Conference")
        #expect(table.groups[0].entries.first?.teamID == "1")
        #expect(hawks.rank == nil)
        #expect(hawks.record == Record(wins: 0, losses: 0, format: .winLoss))
        #expect(hawks.record.summary == "0-0")
        #expect(hawks.gamesBehind == "-")
        #expect(hawks.conferenceRecord == "0-0")
        // `points` there is not a points total, so it is not read.
        #expect(hawks.record.points == nil)
    }

    @Test("WNBA: a finished season, seeded, with clinchers")
    func wnbaFinal() throws {
        let table = try standings("wnba_standings", .wnba)
        // Dream (20): 30-14, East's first seed, clinched "x", W5.
        let dream = try #require(table.entry(for: "20"))
        #expect(dream.rank == 1)
        #expect(dream.record.summary == "30-14")
        #expect(dream.clincher == "x")
        #expect(dream.streak == "W5")
        #expect(dream.conferenceRecord == "15-5")
        // The WNBA's `points` (8.0 for the Dream) is games over .500.
        #expect(dream.record.points == nil)
        #expect(table.groups[1].entries.map(\.rank) == (1...8).map { Optional($0) })
    }

    @Test("NCAAW: last season's tables, reordered by seed from the feed's reverse order")
    func ncaawSeeded() throws {
        let table = try standings("ncaaw_standings", .womensCollegeBasketball)
        // children[i].standings.seasonDisplayName, not the root's 2026-27.
        #expect(table.seasonDisplayName == "2025-26")
        // America East lists seed 9 first; the table puts Vermont (1) there.
        #expect(table.groups[0].entries.first?.teamID == "261")
        #expect(table.groups[0].entries.map(\.rank) == (1...9).map { Optional($0) })

        // Kansas (2305) in the Big 12: 22-14, seed 11, 9 GB, 8-10 in conference.
        let kansas = try #require(table.entry(for: "2305"))
        #expect(table.group(containing: "2305")?.abbreviation == "big12")
        #expect(kansas.rank == 11)
        #expect(table.groups[1].entries.firstIndex { $0.teamID == "2305" } == 10)
        #expect(kansas.record.summary == "22-14")
        #expect(kansas.gamesBehind == "9")
        #expect(kansas.conferenceRecord == "8-10")
    }

    // MARK: Football

    @Test("NCAAF FBS: Sun Belt's divisions are found a level down, and losses come from the summary")
    func ncaafTree() throws {
        let table = try standings("ncaaf_standings", .collegeFootball)
        #expect(table.kind == .records)
        #expect(table.seasonDisplayName == "2026")
        // Big 12 has a table; Sun Belt (37) has none, only its two divisions.
        #expect(table.groups.map(\.name) == ["Big 12 Conference", "Sun Belt - East", "Sun Belt - West"])
        #expect(table.groups.map(\.id) == ["4", "167", "168"])
        #expect(table.groups.map(\.entries.count) == [16, 7, 7])

        // Kansas (2305): stats carry `wins` 1 but no `losses`; `overall` is
        // "1-2". Seed 16 of 16, 2.5 back, 0-1 in conference, L2.
        let kansas = try #require(table.entry(for: "2305"))
        #expect(kansas.record == Record(wins: 1, losses: 2, format: .winLoss))
        #expect(kansas.record.summary == "1-2")
        #expect(kansas.rank == 16)
        #expect(table.groups[0].entries.last?.teamID == "2305")
        #expect(kansas.gamesBehind == "2.5")
        #expect(kansas.conferenceRecord == "0-1")
        #expect(kansas.streak == "L2")

        // The same stat name repeats per split (`homerecord_wins` is also
        // named "wins"); reading by type keeps the overall one. Cincinnati
        // (2132): 4-0 overall, 4-0 at home, 0-0 away.
        let cincinnati = try #require(table.entry(for: "2132"))
        #expect(cincinnati.record.summary == "4-0")
        #expect(cincinnati.rank == 1)

        // UL Monroe (2433), last in the West, 0-4.
        #expect(table.groups[2].entries.last?.record.summary == "0-4")
    }

    // MARK: Hockey

    @Test("NHL: W-L-OTL with points, in preseason every column 0")
    func nhlPreseason() throws {
        let table = try standings("nhl_standings", .nhl)
        #expect(table.groups.map(\.name) == ["Eastern Conference", "Western Conference"])
        #expect(table.groups.map(\.id) == ["7", "8"])

        // Ducks (25), Western Conference entries[9]: `otLosses` 0,
        // `overall` "0-0-0, 0 PTS".
        let ducks = try #require(table.entry(for: "25"))
        #expect(table.group(containing: "25")?.name == "Western Conference")
        #expect(table.groups[1].entries[9].teamID == "25")
        #expect(ducks.name == "Anaheim Ducks")
        #expect(ducks.shortName == "Ducks")
        #expect(ducks.record == Record(wins: 0, losses: 0, overtimeLosses: 0, points: 0, format: .winLossOvertimeLoss))
        #expect(ducks.record.summary == "0-0-0")
        #expect(ducks.gamesBehind == "-")
        #expect(ducks.rank == nil)
    }

    @Test("NHL: overtime losses are their own column, read from otLosses, with points")
    func nhlOvertimeLosses() throws {
        // The capture is preseason, so the Ducks' row (children[1] entries[9])
        // is given a season: stats[11] wins 40, stats[4] losses 30,
        // stats[0] otLosses 12, stats[7] points 92. Only `value` changes.
        let row: [JSON.Index] = ["children", 1, "standings", "entries", 9, "stats"]
        var json = try Fixture.json("nhl_standings")
        for (index, value) in [(11, 40.0), (4, 30.0), (0, 12.0), (7, 92.0)] {
            json = json.setting(row + [.index(index), "value"], to: .number(value))
        }
        #expect(json[row + [0, "type"]].stringValue == "otlosses")
        #expect(json[row + [4, "type"]].stringValue == "losses")
        #expect(json[row + [7, "type"]].stringValue == "points")
        #expect(json[row + [11, "type"]].stringValue == "wins")

        let ducks = try #require(parseStandings(from: json, league: .nhl).entry(for: "25"))
        #expect(ducks.record.wins == 40)
        #expect(ducks.record.losses == 30)
        #expect(ducks.record.overtimeLosses == 12)
        #expect(ducks.record.points == 92)
        #expect(ducks.record.gamesPlayed == 82)
        #expect(ducks.record.summary == "40-30-12")
        #expect(ducks.record.pointsLabel == "92 pts")
    }

    @Test("NHL: without the named stats, the record falls back to the overall summary")
    func nhlSummaryFallback() throws {
        let json = document(#"""
        {"children": [{"id": "8", "name": "Western Conference", "standings": {"entries": [
          {"team": {"id": "25", "displayName": "Anaheim Ducks"},
           "stats": [
             {"type": "total", "name": "overall", "displayValue": "41-29-12, 94 PTS"},
             {"type": "points", "name": "points", "value": 94}
           ]}
        ]}}]}
        """#)
        let ducks = try #require(parseStandings(from: json, league: .nhl).entry(for: "25"))
        #expect(ducks.record.summary == "41-29-12")
        #expect(ducks.record.points == 94)
    }

    // MARK: Rankings fallback

    @Test("A college tree with no table falls back to the AP poll: rank and record")
    func rankingsFallback() throws {
        // The live FBS rankings (captured 2026-10-09): AP first, then the
        // coaches' poll, and no `children` — so no table to prefer.
        let json = try Fixture.json("ncaaf_rankings")
        #expect(json["rankings"].arrayValue.map { $0["type"].stringValue } == ["ap", "usa"])
        let polls = parseStandings(from: json, league: .collegeFootball)
        #expect(polls.kind == .rankings)
        #expect(polls.seasonDisplayName == "2026")
        #expect(polls.groups.map(\.name) == ["AP Top 25"])
        #expect(polls.groups.map(\.abbreviation) == ["AP Poll"])

        let poll = try #require(polls.groups.first)
        #expect(poll.entries.map(\.rank) == (1...25).map { Optional($0) })

        // Texas (251), first: location "Texas", name "Longhorns".
        let texas = try #require(polls.entry(for: "251"))
        #expect(texas.rank == 1)
        #expect(texas.name == "Texas Longhorns")
        #expect(texas.shortName == "Texas")
        #expect(texas.abbreviation == "TEX")
        #expect(texas.logoURL?.absoluteString == "https://a.espncdn.com/i/teamlogos/ncaa/500/251.png")
        #expect(texas.record.summary == "4-0")
        // Georgia (61), second, 5-0.
        #expect(polls.entry(for: "61")?.rank == 2)
        #expect(polls.entry(for: "61")?.record.summary == "5-0")

        // Ordered by `current`, not feed order: Texas pushed to 26th sorts
        // last. A tie shows as football's third column.
        let first: [JSON.Index] = ["rankings", 0, "ranks", 0]
        let reordered = json
            .setting(first + ["current"], to: .number(26))
            .setting(first + ["recordSummary"], to: .string("4-0-1"))
        let resorted = try #require(parseStandings(from: reordered, league: .collegeFootball).groups.first)
        #expect(resorted.entries.first?.teamID == "61")
        #expect(resorted.entries.last?.teamID == "251")
        #expect(resorted.entries.last?.record.summary == "4-0-1")

        // Without an AP poll, the first poll with ranks is read.
        let coachesOnly = json.setting(["rankings", 0, "ranks"], to: .array([]))
        #expect(parseRankings(from: coachesOnly, league: .collegeFootball).groups.map(\.name) == ["AFCA Coaches Poll"])
    }

    @Test("NCAAW's rankings are last season's final AP poll")
    func ncaawRankings() throws {
        let polls = parseRankings(from: try Fixture.json("ncaaw_rankings"), league: .womensCollegeBasketball)
        #expect(polls.seasonDisplayName == "2025-26")
        #expect(polls.groups.map(\.name) == ["AP Top 25"])
        // UCLA (26) first at 37-1, then South Carolina, UConn and Texas.
        #expect(polls.groups[0].entries.prefix(4).map(\.teamID) == ["26", "2579", "41", "251"])
        #expect(polls.entry(for: "251")?.record.summary == "35-4")
    }

    @Test("No tables and no polls is empty standings, not a crash")
    func emptyDocuments() {
        #expect(parseStandings(from: .null, league: .nba).isEmpty)
        #expect(parseStandings(from: document(#"{"children": []}"#), league: .nba).isEmpty)
        #expect(parseRankings(from: document(#"{"rankings": []}"#), league: .collegeFootball).isEmpty)
        #expect(Standings.empty.entry(for: "1") == nil)
    }

    @Test("Record summaries read as their numbers, dropping anything after a comma")
    func recordSummaries() {
        #expect(parseRecordSummary("4-0") == [4, 0])
        #expect(parseRecordSummary("16-6-4") == [16, 6, 4])
        #expect(parseRecordSummary("0-0-0, 0 PTS") == [0, 0, 0])
        #expect(parseRecordSummary("") == [])
        #expect(parseRecordSummary("-") == [])
    }
}

// MARK: - Streak and conference columns (R-5)

@Suite("Standings extra columns")
struct StandingsExtraColumnTests {
    @Test("Conf and Strk show where some row fills them in, after a record table's own columns")
    func shownWhenFilled() throws {
        // WNBA: every row has both (the Dream: "15-5", "W5").
        let wnba = try standings("wnba_standings", .wnba)
        for group in wnba.groups {
            #expect(group.extraColumns(kind: wnba.kind, isAccessibilitySize: false) == [.conferenceRecord, .streak])
        }
        // NCAAF: Big 12 and both Sun Belt divisions; Kansas "0-1", "L2".
        let ncaaf = try standings("ncaaf_standings", .collegeFootball)
        #expect(ncaaf.groups.allSatisfy {
            $0.extraColumns(kind: ncaaf.kind, isAccessibilitySize: false) == [.conferenceRecord, .streak]
        })

        // NHL rows carry a streak but no `vsconf`: Strk alone.
        let nhl = try standings("nhl_standings", .nhl)
        #expect(nhl.groups.allSatisfy { $0.entries.allSatisfy(\.conferenceRecord.isEmpty) })
        #expect(nhl.groups.allSatisfy {
            $0.extraColumns(kind: nhl.kind, isAccessibilitySize: false) == [.streak]
        })
    }

    @Test("No extra columns at accessibility sizes, in a soccer table or poll, or where every row is blank")
    func hidden() throws {
        let wnba = try standings("wnba_standings", .wnba)
        #expect(wnba.groups[0].extraColumns(kind: wnba.kind, isAccessibilitySize: true).isEmpty)

        let epl = try standings("epl_standings", .premierLeague)
        #expect(epl.groups[0].extraColumns(kind: epl.kind, isAccessibilitySize: false).isEmpty)

        let polls = parseRankings(from: try Fixture.json("ncaaf_rankings"), league: .collegeFootball)
        #expect(polls.groups[0].extraColumns(kind: polls.kind, isAccessibilitySize: false).isEmpty)

        // The NBA's preseason rows, their streak and conference record blanked.
        let nba = try standings("nba_standings", .nba)
        let blank = nba.groups[0].entries.map { entry in
            StandingsEntry(
                teamID: entry.teamID, name: entry.name, shortName: entry.shortName,
                abbreviation: entry.abbreviation, logoURL: entry.logoURL, record: entry.record,
                rank: entry.rank, gamesBehind: entry.gamesBehind, conferenceRecord: "",
                goalDifference: entry.goalDifference, streak: "", note: entry.note,
                noteColorHex: entry.noteColorHex, clincher: entry.clincher
            )
        }
        let group = StandingsGroup(id: "5", name: "Eastern Conference", abbreviation: "East", entries: blank)
        #expect(group.extraColumns(kind: .records, isAccessibilitySize: false).isEmpty)
        // One row with a streak is enough to show the column.
        var oneStreak = blank
        oneStreak[3] = nba.groups[0].entries[3]
        #expect(StandingsGroup(id: "5", name: "East", abbreviation: "East", entries: oneStreak)
            .extraColumns(kind: .records, isAccessibilitySize: false) == [.conferenceRecord, .streak])
    }
}

// MARK: - Poll ranks (R-5)

@Suite("Poll ranks")
struct PollRanksTests {
    @Test("The AP poll's ranks, by team id, prefix ranked names only")
    func apRanks() throws {
        let ranks = PollRanks.parse(from: try Fixture.json("ncaaf_rankings"), league: .collegeFootball)
        #expect(ranks.pollName == "AP Top 25")
        #expect(ranks.ranks.count == 25)
        #expect(ranks.rank(of: "251") == 1)    // Texas
        #expect(ranks.rank(of: "84") == 7)     // Indiana
        #expect(ranks.rank(of: "2305") == nil) // Kansas, unranked

        #expect(ranks.prefixed("Indiana", teamID: "84") == "#7 Indiana")
        #expect(ranks.prefixed("Kansas", teamID: "2305") == "Kansas")
        #expect(PollRanks.prefixed("Texas", rank: 1) == "#1 Texas")
        #expect(PollRanks.prefixed("Texas", rank: 0) == "Texas")
        #expect(PollRanks.prefixed("Texas", rank: nil) == "Texas")
        #expect(PollRanks.badge(rank: 22) == "#22")
        #expect(PollRanks.badge(rank: nil) == nil)

        // The women's poll: Texas fourth.
        let ncaaw = PollRanks.parse(from: try Fixture.json("ncaaw_rankings"), league: .womensCollegeBasketball)
        #expect(ncaaw.rank(of: "251") == 4)
    }

    @Test("Standings ranked by table, not poll, give no poll ranks")
    func tablesAreNotPolls() throws {
        #expect(PollRanks(try standings("ncaaf_standings", .collegeFootball)).isEmpty)
        #expect(PollRanks(Standings.empty).isEmpty)
        #expect(PollRanks.parse(from: .null, league: .collegeFootball).isEmpty)
    }

    @Test("The store asks once an hour per college league, never for a pro one, and retries a failure")
    func store() async throws {
        let ncaaf = LeagueID.collegeFootball.rankingsURL
        let poll = try RecordingTransport.Reply.fixture("ncaaf_rankings")
        let transport = RecordingTransport { url, _ in
            url.absoluteString == ncaaf ? poll : .status(503)
        }
        let clock = PollClock()
        let store = PollRankStore(client: HTTPClient(transport: transport), now: { clock.now })

        #expect(await store.ranks(for: .nba).isEmpty)
        #expect(transport.requestCount == 0)

        #expect(await store.ranks(for: .collegeFootball).rank(of: "84") == 7)
        #expect(await store.ranks(for: .collegeFootball).rank(of: "84") == 7)
        #expect(transport.urls.map(\.absoluteString) == [ncaaf])

        // An hour on, the poll is asked for again.
        clock.advance(by: PollRankStore.timeToLive + 1)
        _ = await store.ranks(for: .collegeFootball)
        #expect(transport.requestCount == 2)

        // A failure is empty, and not kept.
        #expect(await store.ranks(for: .womensCollegeBasketball).isEmpty)
        #expect(await store.ranks(for: .womensCollegeBasketball).isEmpty)
        #expect(transport.requestCount == 4)
    }
}

/// A settable clock for the poll store's time-to-live.
private final class PollClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_856_000)

    var now: Date { lock.withLock { current } }

    func advance(by interval: TimeInterval) {
        lock.withLock { current += interval }
    }
}

// MARK: - Seasons

@Suite("Standings seasons")
struct StandingsSeasonTests {
    /// Noon UTC on the given day.
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    @Test("Each league names its season as the feeds did on capture day")
    func captureDaySeasons() throws {
        // FIXTURES.md, "Seasons the feeds returned" (2026-09-28).
        let captured = try day(2026, 9, 28)
        let expected: [(LeagueID, Int)] = [
            (.nba, 2027), (.nhl, 2027), (.womensCollegeBasketball, 2027), (.mensCollegeBasketball, 2027),
            (.wnba, 2026), (.collegeFootball, 2026), (.nfl, 2026),
            (.premierLeague, 2026), (.laLiga, 2026), (.ligaMX, 2026), (.nwsl, 2026),
            (.mls, 2026), (.mlb, 2026),
        ]
        for (league, season) in expected {
            #expect(league.descriptor.standingsSeason(at: captured) == season, "\(league)")
        }
    }

    @Test("Seasons roll over in the league's month, not on New Year's Day")
    func rollovers() throws {
        // January: football and soccer are still in last year's season.
        let january = try day(2027, 1, 15)
        #expect(LeagueID.nfl.descriptor.standingsSeason(at: january) == 2026)
        #expect(LeagueID.premierLeague.descriptor.standingsSeason(at: january) == 2026)
        #expect(LeagueID.nba.descriptor.standingsSeason(at: january) == 2027)
        #expect(LeagueID.mls.descriptor.standingsSeason(at: january) == 2027)

        // July: the NBA names its next season; European soccer has rolled.
        let july = try day(2027, 7, 15)
        #expect(LeagueID.nba.descriptor.standingsSeason(at: july) == 2028)
        #expect(LeagueID.premierLeague.descriptor.standingsSeason(at: july) == 2027)
        #expect(LeagueID.nfl.descriptor.standingsSeason(at: july) == 2027)

        // A league without a descriptor leaves the season to the feed.
        #expect(LeagueID(sport: "hockey", league: "ahl").descriptor.standingsSeason(at: july) == nil)
    }

    @Test("The standings request names the computed season and the college group")
    func standingsRequest() throws {
        let captured = try day(2026, 9, 28)
        let base = "https://site.api.espn.com/apis/v2/sports"
        let season = LeagueID.womensCollegeBasketball.descriptor.standingsSeason(at: captured)
        #expect(LeagueID.womensCollegeBasketball.standingsURL(season: season)
            == "\(base)/basketball/womens-college-basketball/standings?group=50&season=2027")
        #expect(LeagueID.collegeFootball.rankingsURL
            == "https://site.api.espn.com/apis/site/v2/sports/football/college-football/rankings")
    }
}
