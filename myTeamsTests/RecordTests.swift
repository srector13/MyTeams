//
//  RecordTests.swift
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

@Suite("Record formats")
struct RecordFormatTests {
    @Test("W-L shows ties only when there are some")
    func winLoss() {
        #expect(Record(wins: 10, losses: 6, format: .winLoss).summary == "10-6")
        #expect(Record(wins: 10, losses: 6, ties: 1, format: .winLoss).summary == "10-6-1")
        #expect(Record(wins: 0, losses: 0, format: .winLoss).summary == "0-0")
    }

    @Test("W-L-T always shows its third column")
    func winLossTie() {
        #expect(Record(wins: 4, losses: 1, ties: 0, format: .winLossTie).summary == "4-1-0")
        #expect(Record(wins: 6, losses: 17, ties: 3, format: .winLossTie).summary == "6-17-3")
    }

    @Test("W-L-OTL puts overtime losses third, and never mixes in ties")
    func winLossOvertimeLoss() {
        let record = Record(wins: 40, losses: 30, overtimeLosses: 12, points: 92, format: .winLossOvertimeLoss)
        #expect(record.summary == "40-30-12")
        #expect(record.gamesPlayed == 82)
        #expect(record.pointsLabel == "92 pts")
        #expect(Record(wins: 0, losses: 0, format: .winLossOvertimeLoss).summary == "0-0-0")
    }

    @Test("W-D-L-Pts orders draws before losses, then points")
    func winDrawLossPoints() {
        // Arsenal in epl_standings: 4 W, 0 D, 1 L, 12 pts.
        let arsenal = Record(wins: 4, losses: 1, ties: 0, points: 12, format: .winDrawLossPoints)
        #expect(arsenal.summary == "4-0-1, 12 pts")
        #expect(Record(wins: 0, losses: 4, ties: 1, points: 1, format: .winDrawLossPoints).summary == "0-1-4, 1 pt")
        #expect(Record(wins: 2, losses: 1, ties: 3, format: .winDrawLossPoints).summary == "2-3-1")
        #expect(Record(wins: 2, losses: 1, format: .winLoss).pointsLabel == nil)
    }

    @Test("The same games read differently per format")
    func sameGamesPerFormat() {
        func record(_ format: Record.Format) -> String {
            Record(wins: 5, losses: 2, ties: 1, overtimeLosses: 3, points: 16, format: format).summary
        }
        #expect(record(.winLoss) == "5-2-1")
        #expect(record(.winLossTie) == "5-2-1")
        #expect(record(.winLossOvertimeLoss) == "5-2-3")
        #expect(record(.winDrawLossPoints) == "5-1-2, 16 pts")
    }

    @Test("Each sport's schedule and standings formats")
    func formatsBySport() {
        #expect(SportKind.basketball.scheduleRecordFormat == .winLoss)
        #expect(SportKind.football.scheduleRecordFormat == .winLoss)
        #expect(SportKind.baseball.scheduleRecordFormat == .winLoss)
        #expect(SportKind.soccer.scheduleRecordFormat == .winLossTie)
        #expect(SportKind.hockey.scheduleRecordFormat == .winLossOvertimeLoss)

        #expect(SportKind.soccer.standingsRecordFormat == .winDrawLossPoints)
        #expect(SportKind.hockey.standingsRecordFormat == .winLossOvertimeLoss)
        #expect(SportKind.basketball.standingsRecordFormat == .winLoss)
        #expect(SportKind.football.standingsRecordFormat == .winLoss)

        #expect(LeagueDescriptor.nhl.regulationPeriods == 3)
        #expect(LeagueDescriptor.nba.regulationPeriods == 4)
        #expect(LeagueDescriptor.mensCollegeBasketball.regulationPeriods == 2)
        #expect(LeagueDescriptor.mlb.regulationPeriods == nil)
    }
}

// MARK: - Records from schedules

@Suite("Schedule records")
struct ScheduleRecordTests {
    /// The records the schedule header showed before `Record`, from the
    /// same fixtures `GoldenParserTests.seasonRecords` counts. Basketball,
    /// football and baseball read exactly as before; MLS keeps "6-17-3".
    @Test("The original leagues' headers are unchanged")
    func originalLeaguesUnchanged() throws {
        func games(_ fixture: String, _ team: TeamRef) throws -> [Game] {
            parseSchedule(from: try Fixture.json(fixture), team: team)
        }

        let kansas = scheduleRecord(games: try games("jayhawks_schedule_2026", .jayhawks), league: .mensCollegeBasketball)
        #expect(kansas == Record(wins: 23, losses: 10, format: .winLoss))
        #expect(kansas.summary == "23-10")

        #expect(scheduleRecord(games: try games("chiefs_schedule", .chiefs), league: .nfl).summary == "2-0")

        // MLB's rule, now read from the descriptor: the postponed game is a loss.
        #expect(scheduleRecord(games: try games("royals_schedule", .royals), league: .mlb).summary == "4-4")

        // `now` pinned as in GoldenParserTests: 6 W, 17 L, 3 D.
        let sporting = scheduleRecord(
            games: try games("sporting_schedule", .sporting),
            league: .mls,
            now: Date(timeIntervalSince1970: 1_790_532_000)
        )
        #expect(sporting == Record(wins: 6, losses: 17, ties: 3, format: .winLossTie))
        #expect(sporting.summary == "6-17-3")
    }

    @Test("A soccer header always shows its draws: Arsenal's 4-1 is now 4-1-0")
    func soccerShowsDraws() throws {
        // Deliberate change: the header used to drop a zero draws column
        // ("4-1"), which read like a basketball record.
        let games = parseSchedule(from: try Fixture.json("epl_schedule"), team: followed(.premierLeague, "359"))
        let record = scheduleRecord(games: games, league: .premierLeague)
        #expect(record == Record(wins: 4, losses: 1, ties: 0, format: .winLossTie))
        #expect(record.summary == "4-1-0")
    }

    @Test("Hockey: a loss after the third period is an overtime loss")
    func hockeyOvertimeLosses() throws {
        // nhl_schedule: the Ducks' four preseason games, all "Final" in
        // period 3 — won 6–2 (events[0]), then lost 1–2, 0–10 and 2–6.
        let ducks = followed(.nhl, "25")
        let games = parseSchedule(from: try Fixture.json("nhl_schedule"), team: ducks)
        let regulation = scheduleRecord(games: games, league: .nhl)
        #expect(regulation == Record(wins: 1, losses: 3, format: .winLossOvertimeLoss))
        #expect(regulation.summary == "1-3-0")

        // The 1–2 loss (events[1]) sent to overtime, the 2–6 one (events[3])
        // to a shootout.
        var overtime = games
        overtime[1].gamePeriod = "4"
        overtime[3].gamePeriod = "5"
        let record = scheduleRecord(games: overtime, league: .nhl)
        #expect(record == Record(wins: 1, losses: 1, overtimeLosses: 2, format: .winLossOvertimeLoss))
        #expect(record.summary == "1-1-2")

        // A win in overtime is still just a win.
        overtime[0].gamePeriod = "4"
        #expect(scheduleRecord(games: overtime, league: .nhl).summary == "1-1-2")
    }

    @Test("Cup ties are on the schedule but not in the league record")
    func cupTiesLeftOut() throws {
        let arsenal = followed(.premierLeague, "359")
        var games = parseSchedule(from: try Fixture.json("epl_schedule"), team: arsenal)
        // Brighton away (events[0], a 0–3 loss) filed under the Carabao Cup.
        games[0].competition = .soccer("eng.league_cup")
        #expect(!games[0].isLeagueGame(of: .premierLeague))
        #expect(games[1].isLeagueGame(of: .premierLeague))

        #expect(scheduleRecord(games: games, league: .premierLeague).summary == "4-0-0")
    }
}
