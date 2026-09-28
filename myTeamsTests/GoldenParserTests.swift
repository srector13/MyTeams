//
//  GoldenParserTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

// Golden tests: every parser run against real ESPN documents captured on
// 2026-09-27 (see FIXTURES.md), asserting exactly what the code produces
// today. They are the safety net for the Phase 1 refactor — any change in
// output fails here first.
//
// Each golden value carries its derivation: the fixture and the key path it
// was read from. Values are what the parser *does*, not what it should do.
// Where those differ the test is tagged `.knownBug`, marked `// KNOWN-BUG`,
// and says what the correct value would be; fixing the bug means updating
// that assertion on purpose.

extension Tag {
    /// Locks today's output of a known defect. See the `// KNOWN-BUG` note.
    @Tag static var knownBug: Self
    /// Runs a parser against a captured ESPN fixture.
    @Tag static var golden: Self
}

/// Float fields come from display strings through `Float`, so compare them
/// with a tolerance rather than exactly.
private func approx(_ value: Float, _ expected: Float, tolerance: Float = 0.001) -> Bool {
    abs(value - expected) <= tolerance
}

/// Parses one event from a schedule fixture the way the app does for `team`.
private func scheduledGame(_ fixture: String, event id: String, team: TeamRef) throws -> Game {
    let schedule = try Fixture.json(fixture)
    let (event, pointer) = try Fixture.event(id, in: schedule)
    return parseGame(from: event, team: team, pointer: pointer)
}

/// The path to an event's status `detail` string, for derived variants.
private let detailPath: [JSON.Index] = ["competitions", 0, "status", "type", "detail"]

/// Game date and time text follows the device locale; the literal golden
/// strings hold for US English, the locale the simulators run in.
private var isUSEnglish: Bool { Locale.current.identifier.hasPrefix("en_US") }

/// Game text is shown in the device's time zone (P2-b; it was pinned to US
/// Central). The literal golden strings are Central readings, so they are
/// checked only on a device set to Central; `displayed` checks every zone.
private var isUSCentral: Bool { TimeZone.current.identifier == "America/Chicago" }

/// `date` as the schedule's display formatters render it on this device.
private func displayed(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatter.timeZone = .current
    return formatter.string(from: date)
}

// MARK: - Schedule

@Suite("Golden: schedule parsing", .tags(.golden))
struct GoldenScheduleTests {
    @Test("A regulation final reads every Game field (KU, Final)")
    func jayhawksRegulationFinal() throws {
        // jayhawks_schedule_2026.json events[0] (id 401819882)
        let game = try scheduledGame("jayhawks_schedule_2026", event: "401819882", team: .jayhawks)

        #expect(game.eventID == "401819882")  // .id
        #expect(game.gameID == "401819882")  // .competitions[0].id
        #expect(game.id == "401819882")
        #expect(game.pointer == 0)
        #expect(game.team == "Kansas")  // competitors[0].team.nickname (team.id 2305)
        #expect(game.competitionName == "Green Bay Phoenix at Kansas Jayhawks")  // .name
        #expect(game.opponent == "Green Bay")  // competitors[1].team.nickname
        #expect(game.score == "94")  // competitors[0].score.displayValue
        #expect(game.opponentScore == "51")  // competitors[1].score.displayValue
        #expect(game.gameHome)  // competitors[0].homeAway == "home"
        #expect(game.gameWin)  // competitors[0].winner
        #expect(game.completed)  // status.type.completed
        #expect(!game.postponed && !game.cancelled)  // status.type.detail == "Final"
        #expect(!game.gameHalftime)  // status.type.description == "Final"
        #expect(game.gameClock == "0:00")  // status.displayClock
        #expect(game.gamePeriod == "2")  // status.period (2 halves)
        #expect(game.channel == "ESPN+")  // broadcasts[0].media.shortName
        #expect(game.location == "Allen Fieldhouse")  // venue.fullName
        // The competitors[1].team.logos entry whose rel is ["full", "default"]
        // (P2-a: chosen by rel; it was the last non-"dark" href, a 4096 px
        // guid/…/secondary_logo_white.png).
        #expect(game.opponentLogo == "https://a.espncdn.com/i/teamlogos/ncaa/500/2739.png")
        #expect(game.opponentID == "2739")  // competitors[1].team.id
        #expect(!game.isDraw)

        // .date "2025-11-04T01:00Z" is the UTC instant 1762218000.
        #expect(game.dateAsDate == Date(timeIntervalSince1970: 1_762_218_000))
        #expect(game.date == displayed(game.dateAsDate, "MMM dd, yyyy"))
        #expect(game.time == displayed(game.dateAsDate, "h:mm a"))
        if isUSEnglish && isUSCentral {
            // 01:00Z is 7:00 PM the previous evening in Central (CST, UTC-6).
            #expect(game.date == "Nov 03, 2025")
            #expect(game.time == "7:00 PM")
        }
    }

    @Test("Basketball overtime finals: the score includes OT and the period is 3")
    func jayhawksOvertimeFinals() throws {
        // jayhawks_schedule_2026.json id 401817259 — detail "Final/OT", KU away.
        let away = try scheduledGame("jayhawks_schedule_2026", event: "401817259", team: .jayhawks)
        #expect(away.opponent == "NC State")
        #expect(away.score == "77")  // competitors[1].score.displayValue
        #expect(away.opponentScore == "76")  // competitors[0].score.displayValue
        #expect(!away.gameHome)
        #expect(away.gameWin)
        #expect(away.completed)
        #expect(away.gamePeriod == "3")  // status.period: two halves + one OT
        #expect(!away.postponed && !away.cancelled)  // "Final/OT" is neither

        // jayhawks_schedule_2026.json id 401827601 — detail "Final/OT", KU home.
        let home = try scheduledGame("jayhawks_schedule_2026", event: "401827601", team: .jayhawks)
        #expect(home.opponent == "TCU")
        #expect(home.score == "104")
        #expect(home.opponentScore == "100")
        #expect(home.gameHome)
        #expect(home.gameWin)
        #expect(home.gamePeriod == "3")
    }

    // The NFL schedule feed names the Chiefs `nickname: "Chiefs"` while the
    // retired Team.chiefs.scheduleTeamName was "KC", so the name match never
    // found them (§7 #15). Matching competitors[*].team.id against the
    // TeamRef's ESPN id (12) fixes it.
    @Test("Chiefs schedule: the followed team is matched by ESPN id")
    func chiefsMatchedByID() throws {
        // chiefs_schedule.json events[0] (id 401872931): Chiefs (home) 31, Broncos 10.
        let game = try scheduledGame("chiefs_schedule", event: "401872931", team: .chiefs)
        #expect(game.opponent == "Broncos")  // competitors[1].team.nickname
        #expect(game.score == "31")  // competitors[0].score.displayValue
        #expect(game.opponentScore == "10")  // competitors[1].score.displayValue
        #expect(game.gameHome)  // competitors[0].homeAway
        #expect(game.gameWin)  // competitors[0].winner
        #expect(game.completed)
        #expect(game.team == "Chiefs")  // competitors[0].team.nickname

        // Away games list the Chiefs last; the opponent is still the host.
        // chiefs_schedule.json id 401872976: Raiders (home) v Chiefs (away).
        let away = try scheduledGame("chiefs_schedule", event: "401872976", team: .chiefs)
        #expect(away.opponent == "Raiders")  // competitors[0].team.nickname
        #expect(!away.gameHome)  // competitors[1].homeAway (Chiefs)
        // The competitors[0].team.logos entry whose rel is ["full", "default"]
        // (P2-a: was guid/…/secondary_logo_white.png).
        #expect(away.opponentLogo == "https://a.espncdn.com/i/teamlogos/nfl/500/lv.png")
        #expect(away.opponentID == "13")  // competitors[0].team.id
    }

    @Test("NFL overtime final (Final/OT) reads as completed with period 5")
    func chiefsOvertimeFinal() throws {
        // chiefs_schedule.json events[1] (id 401872945), status.type.detail "Final/OT"
        let game = try scheduledGame("chiefs_schedule", event: "401872945", team: .chiefs)
        #expect(game.completed)  // status.type.completed
        #expect(!game.postponed && !game.cancelled)
        #expect(game.gamePeriod == "5")  // status.period: four quarters + OT
        #expect(game.gameClock == "0:00")
        #expect(game.opponentScore == "30")  // competitors[1].score.displayValue (Colts)
        #expect(game.channel == "NBC")
        #expect(game.location == "Arrowhead Stadium")
        #expect(game.dateAsDate == Date(timeIntervalSince1970: 1_789_950_000))  // "2026-09-21T00:20Z"
        #expect(game.date == displayed(game.dateAsDate, "MMM dd, yyyy"))
        #expect(game.time == displayed(game.dateAsDate, "h:mm a"))
        if isUSEnglish && isUSCentral {
            #expect(game.date == "Sep 20, 2026")  // 19:20 CDT (UTC-5)
            #expect(game.time == "7:20 PM")
        }
    }

    @Test("An in-progress NFL game reads its clock and period, not completed")
    func chiefsLiveGame() throws {
        // chiefs_schedule.json events[2] (id 401872952), status.type.state "in",
        // detail "14:14 - 2nd Quarter", description "In Progress"
        let game = try scheduledGame("chiefs_schedule", event: "401872952", team: .chiefs)
        #expect(!game.completed)
        #expect(!game.postponed && !game.cancelled)
        #expect(!game.gameHalftime)  // description is "In Progress"
        #expect(game.gameClock == "14:14")  // status.displayClock
        #expect(game.gamePeriod == "2")  // status.period
        // The schedule feed carries no score objects for a live game
        // (competitors[*].score absent), so both read "".
        #expect(game.opponentScore == "")
        #expect(game.channel == "CBS")
        #expect(game.location == "Hard Rock Stadium")

        // Derived: the same event with description "Halftime" sets the flag.
        let schedule = try Fixture.json("chiefs_schedule")
        let (event, pointer) = try Fixture.event("401872952", in: schedule)
        let halftime = event.setting(
            ["competitions", 0, "status", "type", "description"], to: .string("Halftime")
        )
        let parsed = parseGame(from: halftime, team: .chiefs, pointer: pointer)
        #expect(parsed.gameHalftime)
    }

    @Test("A postponed MLB game is flagged postponed, not completed")
    func royalsPostponed() throws {
        // royals_schedule.json events[5] (id 401814790), status.type.detail "Postponed"
        let game = try scheduledGame("royals_schedule", event: "401814790", team: .royals)
        #expect(game.postponed)
        #expect(!game.cancelled)
        #expect(!game.completed)  // status.type.completed false
        #expect(game.opponent == "Brewers")  // competitors[1].team.shortDisplayName
        #expect(game.gameHome)
        #expect(!game.gameWin)
        #expect(game.score == "0")  // competitors[0].score.displayValue
        #expect(game.opponentScore == "0")
        #expect(game.gamePeriod == "1")
        #expect(game.channel == "Apple TV")
        // Shape pin: 0–0 with no winner reads as a draw. Harmless while every
        // caller (seasonRecord, GameView) checks postponed/completed first.
        #expect(game.isDraw)
    }

    @Test("A Canceled detail string sets cancelled (derived from a real event)")
    func royalsCanceled() throws {
        // royals_schedule.json id 401814790 with only status.type.detail
        // replaced by "Canceled" — no captured feed has a cancelled game.
        let schedule = try Fixture.json("royals_schedule")
        let (event, pointer) = try Fixture.event("401814790", in: schedule)
        let canceled = event.setting(detailPath, to: .string("Canceled"))
        let game = parseGame(from: canceled, team: .royals, pointer: pointer)
        #expect(game.cancelled)
        #expect(!game.postponed)
        #expect(!game.completed)
    }

    @Test("Detail strings other than Postponed/Canceled flag nothing")
    func unrecognisedDetailStrings() throws {
        // royals_schedule.json id 401815101: detail "Final/10" (extra innings)
        let extras = try scheduledGame("royals_schedule", event: "401815101", team: .royals)
        #expect(extras.completed)
        #expect(!extras.postponed && !extras.cancelled)
        #expect(extras.gamePeriod == "10")  // status.period
        #expect(extras.score == "11")  // competitors[0] (Royals, home)
        #expect(extras.opponentScore == "9")  // competitors[1] (Angels)
        #expect(extras.gameWin)

        // sporting_schedule.json events[0] (id 761836): detail "FT"
        let fullTime = try scheduledGame("sporting_schedule", event: "761836", team: .sporting)
        #expect(fullTime.completed)
        #expect(!fullTime.postponed && !fullTime.cancelled)
        #expect(fullTime.gameClock == "90'+5'")  // status.displayClock
        #expect(fullTime.score == "2")  // competitors[1] "Kansas City"
        #expect(fullTime.opponentScore == "0")  // competitors[0] "Houston"
        #expect(fullTime.opponent == "Houston")
        #expect(!fullTime.gameHome)
        #expect(fullTime.gameWin)

        // chiefs_schedule.json id 401872976: pre-game detail
        // "Sun, October 4th at 4:25 PM EDT"
        let pregame = try scheduledGame("chiefs_schedule", event: "401872976", team: .chiefs)
        #expect(!pregame.completed)
        #expect(!pregame.postponed && !pregame.cancelled)
        #expect(pregame.gamePeriod == "0")
    }

    // KNOWN-BUG (§7 #13): status is read from exact detail strings, so a
    // suspended game is neither postponed nor cancelled. Correct: read
    // status.type.name (STATUS_SUSPENDED) and treat it as abandoned.
    @Test("A Suspended detail string flags nothing", .tags(.knownBug))
    func suspendedIsUnflagged() throws {
        // royals_schedule.json id 401814790 with status.type.detail "Suspended"
        let schedule = try Fixture.json("royals_schedule")
        let (event, pointer) = try Fixture.event("401814790", in: schedule)
        let game = parseGame(
            from: event.setting(detailPath, to: .string("Suspended")),
            team: .royals, pointer: pointer
        )
        #expect(!game.postponed)  // KNOWN-BUG
        #expect(!game.cancelled)  // KNOWN-BUG
        #expect(!game.completed)
    }

    // KNOWN-BUG (§7 #14): an unreadable date leaves dateAsDate at "now" and
    // the date/time text empty, which puts an unplayed game in the live-poll
    // window. Correct: surface the missing date (nil / an explicit TBD) and
    // never poll it.
    @Test("An unreadable event date falls back to now", .tags(.knownBug))
    func unreadableDate() throws {
        // royals_schedule.json id 401817109 (the scheduled Royals game) with
        // .date replaced by "TBD"; everything else is the real event.
        let schedule = try Fixture.json("royals_schedule")
        let (event, pointer) = try Fixture.event("401817109", in: schedule)

        #expect(parseGameDate("TBD") == nil)

        let before = Date()
        let game = parseGame(
            from: event.setting(["date"], to: .string("TBD")),
            team: .royals, pointer: pointer
        )
        let after = Date()

        #expect(game.dateAsDate >= before && game.dateAsDate <= after)  // KNOWN-BUG: "now"
        #expect(game.date == "")
        #expect(game.time == "")
        // The id still comes from the event, so the card stays stable.
        #expect(game.eventID == "401817109")
        #expect(!game.completed)
        // …and "now" is inside the live window, so it would be polled.
        #expect(shouldPollLiveScore(game: game, now: after))  // KNOWN-BUG
    }

    // KNOWN-BUG (§7 #14): the "yyyy-MM-dd HH:mm" parse rejects an otherwise
    // valid timestamp that carries seconds, so it takes the fallback above.
    // Correct: accept ISO 8601 with or without seconds.
    @Test("A timestamp with seconds does not parse", .tags(.knownBug))
    func timestampWithSeconds() {
        // royals_schedule.json id 401817109 .date is "2026-09-27T19:10Z"; the
        // same instant with ":00" seconds appended.
        #expect(parseGameDate("2026-09-27T19:10Z") == Date(timeIntervalSince1970: 1_790_536_200))
        #expect(parseGameDate("2026-09-27T19:10:00Z") == nil)  // KNOWN-BUG
    }

    // KNOWN-BUG (M6): each competition overwrites the previous one's fields,
    // so an event carrying two competitions reports only the last and the
    // first game's result is lost. Correct: one Game per competition.
    // The only synthetic document in this suite — no captured feed has one.
    // Team ids are ESPN's MLB ids (Royals 7, Tigers 6, Twins 9).
    @Test("A two-competition event keeps only the last competition", .tags(.knownBug))
    func doubleheaderLastCompetitionWins() {
        let event = JSON(data: Data(#"""
        {
          "name": "Doubleheader",
          "date": "2021-01-18T23:00Z",
          "competitions": [
            {"id": "1", "venue": {"fullName": "First Arena"},
             "status": {"period": 9, "type": {"completed": true, "detail": "Final"}},
             "competitors": [
               {"homeAway": "home", "winner": true,
                "team": {"id": "7", "shortDisplayName": "Royals"}, "score": {"displayValue": "5"}},
               {"homeAway": "away",
                "team": {"id": "6", "shortDisplayName": "Tigers"}, "score": {"displayValue": "2"}}
             ]},
            {"id": "2", "venue": {"fullName": "Second Arena"},
             "status": {"period": 1, "type": {"completed": false, "detail": "Postponed"}},
             "competitors": [
               {"homeAway": "away", "winner": false,
                "team": {"id": "7", "shortDisplayName": "Royals"}, "score": {"displayValue": "0"}},
               {"homeAway": "home",
                "team": {"id": "9", "shortDisplayName": "Twins"}, "score": {"displayValue": "0"}}
             ]}
          ]
        }
        """#.utf8))

        let game = parseGame(from: event, team: .royals, pointer: 0)
        #expect(game.location == "Second Arena")
        #expect(game.gameID == "2")
        #expect(game.eventID == "2")  // no event id: the (last) competition id
        #expect(game.opponent == "Twins")
        #expect(game.score == "0")  // KNOWN-BUG: the 5–2 win is gone
        #expect(!game.gameWin)
        #expect(!game.gameHome)
        #expect(!game.completed)
        #expect(game.postponed)
        #expect(game.gamePeriod == "1")
    }

    @Test("An offseason feed with no events parses to no games")
    func offseason() throws {
        // jayhawks_schedule_offseason.json: "events": [] (season.year 2027)
        let games = parseSchedule(from: try Fixture.json("jayhawks_schedule_offseason"), team: .jayhawks)
        #expect(games.isEmpty)
    }

    @Test("Whole feeds parse one game per event, in feed order, with unique ids")
    func wholeFeeds() throws {
        // Event counts: len(.events) of each fixture.
        let feeds: [(String, TeamRef, Int)] = [
            ("chiefs_schedule", .chiefs, 17),
            ("jayhawks_schedule_2026", .jayhawks, 33),
            ("royals_schedule", .royals, 9),  // trimmed from 163; see FIXTURES.md
            ("sporting_schedule", .sporting, 26),
        ]
        for (fixture, team, count) in feeds {
            let json = try Fixture.json(fixture)
            let games = parseSchedule(from: json, team: team)
            #expect(games.count == count, "\(fixture)")
            #expect(games.map(\.pointer) == Array(0 ..< count), "\(fixture)")
            #expect(Set(games.map(\.id)).count == count, "\(fixture)")
            #expect(games.map(\.eventID) == json["events"].map { $0.1["id"].stringValue }, "\(fixture)")
        }
    }

    @Test("Season records from real feeds")
    func seasonRecords() throws {
        func games(_ fixture: String, _ team: TeamRef) throws -> [Game] {
            parseSchedule(from: try Fixture.json(fixture), team: team)
        }

        // jayhawks_schedule_2026.json: 33 finals, `winner` true on KU in 23.
        let kansas = seasonRecord(games: try games("jayhawks_schedule_2026", .jayhawks))
        #expect(kansas.wins == 23 && kansas.losses == 10 && kansas.draws == 0)

        // royals_schedule.json (trimmed): wins at events[2,3,4,6]; losses at
        // [0,1,7] plus the postponed [5] under the baseball rule; [8] unplayed.
        let royals = seasonRecord(games: try games("royals_schedule", .royals), countingAbandonedAsLosses: true)
        #expect(royals.wins == 4 && royals.losses == 4 && royals.draws == 0)

        // sporting_schedule.json: 26 "FT" games; level scorelines at ids
        // 761732 (1–1), 761585 (1–1), 761461 (2–2). `now` is pinned to
        // 2026-09-27T18:00Z so the date fallback is deterministic.
        let sporting = seasonRecord(
            games: try games("sporting_schedule", .sporting),
            pastDatesCountAsPlayed: true,
            now: Date(timeIntervalSince1970: 1_790_532_000)
        )
        #expect(sporting.wins == 6 && sporting.losses == 17 && sporting.draws == 3)
    }

    // Follows from chiefsMatchedByID: both played games (31–10, 33–30 OT)
    // carry `winner` on the Chiefs; the in-progress one is not yet played.
    @Test("Chiefs season record reads 2–0")
    func chiefsSeasonRecord() throws {
        let games = parseSchedule(from: try Fixture.json("chiefs_schedule"), team: .chiefs)
        let record = seasonRecord(games: games)
        #expect(record.wins == 2)
        #expect(record.losses == 0)
        #expect(record.draws == 0)
    }
}

// MARK: - Period labels

@Suite("Golden: period labels", .tags(.golden))
struct GoldenPeriodTests {
    @Test("Regulation periods are named for basketball, football and soccer")
    func regulationPeriods() throws {
        // Inputs are Game.gamePeriod from real schedule events, named by the
        // followed team's league (TeamRef.periodName).
        let kansas = try scheduledGame("jayhawks_schedule_2026", event: "401819882", team: .jayhawks)
        #expect(TeamRef.jayhawks.periodName(kansas.gamePeriod) == "2nd Half")  // "2", NCAAM halves
        #expect(TeamRef.jayhawks.periodName("1") == "1st Half")

        let chiefs = try scheduledGame("chiefs_schedule", event: "401872952", team: .chiefs)
        #expect(TeamRef.chiefs.periodName(chiefs.gamePeriod) == "2nd Quarter")  // "2", NFL quarters

        let sporting = try scheduledGame("sporting_schedule", event: "761836", team: .sporting)
        #expect(TeamRef.sporting.periodName(sporting.gamePeriod) == "2nd Half")  // "2", MLS halves
    }

    // KNOWN-BUG (§7 #12): period labels know only regulation periods.
    // Correct: "OT" for basketball period 3 and football period 5, and an
    // inning label ("Bot 10th" etc.) for baseball.
    @Test("Overtime periods and every baseball inning read as blank", .tags(.knownBug))
    func unnamedPeriods() throws {
        // jayhawks_schedule_2026.json id 401817259: "Final/OT", period 3
        let kansasOT = try scheduledGame("jayhawks_schedule_2026", event: "401817259", team: .jayhawks)
        #expect(TeamRef.jayhawks.periodName(kansasOT.gamePeriod) == "")  // KNOWN-BUG

        // chiefs_schedule.json id 401872945: "Final/OT", period 5
        let chiefsOT = try scheduledGame("chiefs_schedule", event: "401872945", team: .chiefs)
        #expect(TeamRef.chiefs.periodName(chiefsOT.gamePeriod) == "")  // KNOWN-BUG

        // royals_schedule.json id 401815101 ("Final/10", period 10) and
        // 401817094 ("Final", period 9)
        let extras = try scheduledGame("royals_schedule", event: "401815101", team: .royals)
        #expect(TeamRef.royals.periodName(extras.gamePeriod) == "")  // KNOWN-BUG
        let nine = try scheduledGame("royals_schedule", event: "401817094", team: .royals)
        #expect(TeamRef.royals.periodName(nine.gamePeriod) == "")  // KNOWN-BUG
    }
}

// MARK: - Summaries

@Suite("Golden: game summaries", .tags(.golden))
struct GoldenSummaryTests {
    // MARK: Live score

    @Test("Live score from final, in-game and pre-game summaries, all four sports")
    func liveScores() throws {
        // The header scores are bare strings: header.competitions[0].competitors[*].score
        // chiefs final 401872945: Chiefs home "33", Colts "30" (4 quarters + OT)
        #expect(try parseLiveGameScore(from: Fixture.json("chiefs_summary_final_401872945"), team: .chiefs, isHome: true)
            == LiveGameScore(score: 33, opponentScore: 30))
        // chiefs live 401872952 (state "in", 13:49 2nd Q): Dolphins home "7", Chiefs away "7"
        #expect(try parseLiveGameScore(from: Fixture.json("chiefs_summary_live_401872952"), team: .chiefs, isHome: false)
            == LiveGameScore(score: 7, opponentScore: 7))
        // jayhawks final 401851305: Houston home "69", Kansas away "47"
        #expect(try parseLiveGameScore(from: Fixture.json("jayhawks_summary_final_401851305"), team: .jayhawks, isHome: false)
            == LiveGameScore(score: 47, opponentScore: 69))
        // royals final 401817094: Royals home "5", Guardians "11"
        #expect(try parseLiveGameScore(from: Fixture.json("royals_summary_final_401817094"), team: .royals, isHome: true)
            == LiveGameScore(score: 5, opponentScore: 11))
        // sporting final 761450: San Jose home "3", Kansas City away "0"
        #expect(try parseLiveGameScore(from: Fixture.json("sporting_summary_final_761450"), team: .sporting, isHome: false)
            == LiveGameScore(score: 0, opponentScore: 3))
    }

    @Test("A pre-game summary has no score, so no live score")
    func liveScorePregame() throws {
        // header.competitions[0].competitors[*] carry no "score" key before kickoff.
        #expect(try parseLiveGameScore(from: Fixture.json("chiefs_summary_pregame_401872976"), team: .chiefs, isHome: false) == nil)
        #expect(try parseLiveGameScore(from: Fixture.json("royals_summary_pregame_401817109"), team: .royals, isHome: true) == nil)
    }

    @Test("Without homeAway the live score falls back to the team id")
    func liveScoreIDFallback() throws {
        // sporting_summary_final_761450.json with both header competitors'
        // homeAway removed; competitors[1].team.id is "186" (Kansas City).
        var sporting = try Fixture.json("sporting_summary_final_761450")
        for index in 0 ..< 2 {
            sporting = sporting.setting(["header", "competitions", 0, "competitors", .index(index), "homeAway"], to: .null)
        }
        #expect(parseLiveGameScore(from: sporting, team: .sporting, isHome: true)
            == LiveGameScore(score: 0, opponentScore: 3))

        // The NFL header competitors carry no shortDisplayName, which left
        // the retired name fallback with no followed team (nil). Every
        // header competitor carries team.id: competitors[0] is the Chiefs
        // (12) with "33", the Colts "30".
        var chiefs = try Fixture.json("chiefs_summary_final_401872945")
        for index in 0 ..< 2 {
            chiefs = chiefs.setting(["header", "competitions", 0, "competitors", .index(index), "homeAway"], to: .null)
        }
        #expect(parseLiveGameScore(from: chiefs, team: .chiefs, isHome: true)
            == LiveGameScore(score: 33, opponentScore: 30))
    }

    // The schedule's gameHome feeds isHome. With the Chiefs matched by id
    // (chiefsMatchedByID) a home game is flagged home, so its live score
    // reads the right way round.
    @Test("Chiefs home game: live score reads home-first end to end")
    func chiefsLiveScoreEndToEnd() throws {
        let game = try scheduledGame("chiefs_schedule", event: "401872945", team: .chiefs)
        #expect(game.gameHome)
        let summary = try Fixture.json("chiefs_summary_final_401872945")
        #expect(parseLiveGameScore(from: summary, team: .chiefs, isHome: game.gameHome)
            == LiveGameScore(score: 33, opponentScore: 30))
    }

    // MARK: Phase and refresh

    @Test("Game phase and detail refresh interval from pre, in and post summaries")
    func phases() throws {
        // header.competitions[0].status.type.{completed,state}
        let pregame = try Fixture.json("chiefs_summary_pregame_401872976")  // false, "pre"
        let live = try Fixture.json("chiefs_summary_live_401872952")  // false, "in"
        let final = try Fixture.json("chiefs_summary_final_401872945")  // true, "post"

        #expect(parseGamePhase(from: pregame) == .pre)
        #expect(parseGamePhase(from: live) == .live)
        #expect(parseGamePhase(from: final) == .final)
        #expect(try parseGamePhase(from: Fixture.json("royals_summary_pregame_401817109")) == .pre)
        #expect(try parseGamePhase(from: Fixture.json("sporting_summary_final_761450")) == .final)  // "FT"
        #expect(try parseGamePhase(from: Fixture.json("jayhawks_summary_final_401851305")) == .final)

        #expect(GameDetail(json: pregame, team: .chiefs, stats: parseFootballGameTeamStats(from: pregame, team: .chiefs)).refreshInterval == .seconds(60))
        #expect(GameDetail(json: live, team: .chiefs, stats: parseFootballGameTeamStats(from: live, team: .chiefs)).refreshInterval == .seconds(10))
        #expect(GameDetail(json: final, team: .chiefs, stats: parseFootballGameTeamStats(from: final, team: .chiefs)).refreshInterval == nil)
    }

    // MARK: Venue

    @Test("Venue details and accent colour, home and away")
    func gameInfo() throws {
        // gameInfo.venue.{images[0].href,address.city,address.state,capacity}, gameInfo.attendance.
        // No captured venue has a "capacity" key, so capacity is "" throughout.

        // Home (the followed team's boxscore.teams entry, by team.id, is
        // "home"): the team's own TeamRef.colorHex.
        #expect(try parseGameInfo(from: Fixture.json("chiefs_summary_final_401872945"), team: .chiefs) == GameInfo(
            venueImage: "https://a.espncdn.com/i/venues/nfl/day/3622.jpg",
            city: "Kansas City", state: "MO", capacity: "", attendance: "73351",
            gameColor: "E31837"  // TeamRef.chiefs.colorHex (227, 24, 55)
        ))
        #expect(try parseGameInfo(from: Fixture.json("royals_summary_final_401817094"), team: .royals) == GameInfo(
            venueImage: "https://a.espncdn.com/i/venues/mlb/day/7.jpg",
            city: "Kansas City", state: "Missouri", capacity: "", attendance: "24656",
            gameColor: "004687"  // TeamRef.royals.colorHex (0, 70, 135)
        ))
        #expect(try parseGameInfo(from: Fixture.json("royals_summary_pregame_401817109"), team: .royals) == GameInfo(
            venueImage: "https://a.espncdn.com/i/venues/mlb/day/7.jpg",
            city: "Kansas City", state: "Missouri", capacity: "", attendance: "",
            gameColor: "004687"
        ))

        // Away: the other boxscore.teams entry's team.color. Here the
        // followed team is listed first, so teams[1].
        #expect(try parseGameInfo(from: Fixture.json("chiefs_summary_live_401872952"), team: .chiefs) == GameInfo(
            venueImage: "https://a.espncdn.com/i/venues/nfl/day/3948.jpg",
            city: "Miami Gardens", state: "FL", capacity: "", attendance: "",
            gameColor: "008e97"  // boxscore.teams[1] Dolphins
        ))
        #expect(try parseGameInfo(from: Fixture.json("chiefs_summary_pregame_401872976"), team: .chiefs) == GameInfo(
            venueImage: "https://a.espncdn.com/i/venues/nfl/day/6501.jpg",
            city: "Las Vegas", state: "NV", capacity: "", attendance: "",
            gameColor: "000000"  // boxscore.teams[1] Raiders
        ))
        // KU at a neutral Kansas City site is listed "away", so away rules
        // apply; boxscore.teams[0] is Kansas (team.id 2305).
        #expect(try parseGameInfo(from: Fixture.json("jayhawks_summary_final_401851305"), team: .jayhawks) == GameInfo(
            venueImage: "",  // gameInfo.venue has no images
            city: "Kansas City", state: "MO", capacity: "", attendance: "19450",
            gameColor: "c8102e"  // boxscore.teams[1] Houston
        ))

        // Away, followed team listed second: teams[0].team.color.
        #expect(try parseGameInfo(from: Fixture.json("sporting_summary_final_761450"), team: .sporting) == GameInfo(
            venueImage: "",
            city: "San Jose, California", state: "", capacity: "", attendance: "16367",
            gameColor: "003da6"  // boxscore.teams[0] San Jose
        ))
    }

    // MARK: Basketball box score

    // Was KNOWN-BUG (§7 #11): the stats were read by position, and the
    // feed's list had shifted — assists read [10] (steals), and so on down
    // to largestLead reading [20] (pointsInPaint). Each is now read by name.
    @Test("KU final box score (regulation, KU listed second)")
    func basketballBoxScore() throws {
        // jayhawks_summary_final_401851305.json — detail "Final"
        let lines = parseBasketballGameTeamStats(from: try Fixture.json("jayhawks_summary_final_401851305"), team: .jayhawks)
        try #require(lines.count == 2)  // boxscore.teams

        // boxscore.teams[0] (Jayhawks, away) .statistics[name].displayValue
        let kansas = lines[0]
        #expect(kansas.name == "Jayhawks")
        #expect(kansas.fieldGoals == "14-57")  // fieldGoalsMade-fieldGoalsAttempted
        #expect(approx(kansas.fieldGoalPct, 25))
        #expect(kansas.threePoints == "7-23")
        #expect(approx(kansas.threePointPct, 30))
        #expect(kansas.freeThrows == "12-18")
        #expect(approx(kansas.freeThrowPct, 67))
        #expect(kansas.offensiveRebounds == 15)
        #expect(kansas.defensiveRebounds == 22)
        #expect(kansas.assists == 8)  // was 3, steals
        #expect(kansas.steals == 3)
        #expect(kansas.blocks == 2)
        #expect(kansas.turnOvers == 8)
        #expect(kansas.fouls == 11)
        #expect(kansas.largestLead == 0)
        #expect(kansas.projection == 0)  // no "predictor" in a final summary
        // Score: competitors[0].team.id is "248" (Houston), so KU is index 1;
        // linescores [25, 22] = 47 and Houston's [33, 36] = 69.
        #expect(kansas.score == 47)
        #expect(kansas.opponentScore == 69)
        #expect(kansas.gameClock == "Final")  // header…status.type.detail

        // boxscore.teams[1] (Cougars, home)
        let houston = lines[1]
        #expect(houston.name == "Cougars")
        #expect(houston.fieldGoals == "22-53")
        #expect(approx(houston.fieldGoalPct, 42))
        #expect(houston.threePoints == "10-18")
        #expect(approx(houston.threePointPct, 56))
        #expect(houston.freeThrows == "15-19")
        #expect(approx(houston.freeThrowPct, 79))
        #expect(houston.offensiveRebounds == 10)
        #expect(houston.defensiveRebounds == 32)
        #expect(houston.assists == 11)
        #expect(houston.steals == 4)
        #expect(houston.blocks == 4)
        #expect(houston.turnOvers == 8)
        #expect(houston.fouls == 15)
        #expect(houston.largestLead == 24)
        // Both lines carry KU's score first, whichever team they describe.
        #expect(houston.score == 47)
        #expect(houston.opponentScore == 69)
    }

    // MARK: Football box score

    @Test("NFL overtime final box score (Final/OT)")
    func footballOvertimeBoxScore() throws {
        // chiefs_summary_final_401872945.json
        let lines = parseFootballGameTeamStats(from: try Fixture.json("chiefs_summary_final_401872945"), team: .chiefs)
        try #require(lines.count == 2)

        // boxscore.teams[0] (Colts) .statistics[i].displayValue
        let colts = lines[0]
        #expect(colts.name == "Colts")
        #expect(colts.firstDowns == 24)  // [0] firstDowns
        #expect(colts.yards == 329)  // [7] totalYards
        #expect(colts.drives == 10)  // [9] totalDrives
        #expect(colts.passingYards == 210)  // [10] netPassingYards
        #expect(colts.completionAttempts == 22)  // [11] "22/31", leading figure
        #expect(colts.interceptions == 1)  // [13]
        #expect(colts.rushingYards == 119)  // [15]
        #expect(colts.possesionTime == "33:00")  // [24]

        // boxscore.teams[1] (Chiefs)
        let chiefs = lines[1]
        #expect(chiefs.name == "Chiefs")
        #expect(chiefs.firstDowns == 29)
        #expect(chiefs.yards == 523)
        #expect(chiefs.drives == 11)
        #expect(chiefs.passingYards == 371)
        #expect(chiefs.completionAttempts == 32)  // "32/47"
        #expect(chiefs.interceptions == 0)
        #expect(chiefs.rushingYards == 152)
        #expect(chiefs.possesionTime == "37:00")

        // header competitors[0] is the Chiefs: score "33" (linescores
        // 10+7+7+3 + OT 6), Colts "30" (7+13+0+7 + OT 3). The header total
        // already includes overtime.
        for line in lines {
            #expect(line.score == 33)
            #expect(line.opponentScore == 30)
            #expect(line.gameClock == "Final/OT")  // header…status.type.detail
        }
    }

    @Test("NFL in-game box score (state in, 2nd quarter)")
    func footballLiveBoxScore() throws {
        // chiefs_summary_live_401872952.json
        let lines = parseFootballGameTeamStats(from: try Fixture.json("chiefs_summary_live_401872952"), team: .chiefs)
        try #require(lines.count == 2)

        let chiefs = lines[0]  // boxscore.teams[0]
        #expect(chiefs.name == "Chiefs")
        #expect(chiefs.firstDowns == 6)
        #expect(chiefs.yards == 123)
        #expect(chiefs.drives == 2)
        #expect(chiefs.passingYards == 95)
        #expect(chiefs.completionAttempts == 7)  // "7/7"
        #expect(chiefs.interceptions == 0)
        #expect(chiefs.rushingYards == 28)
        #expect(chiefs.possesionTime == " 6:44")  // leading space is in the feed

        let dolphins = lines[1]  // boxscore.teams[1]
        #expect(dolphins.name == "Dolphins")
        #expect(dolphins.firstDowns == 7)
        #expect(dolphins.yards == 101)
        #expect(dolphins.drives == 1)
        #expect(dolphins.passingYards == 55)
        #expect(dolphins.completionAttempts == 5)  // "5/8"
        #expect(dolphins.rushingYards == 46)
        #expect(dolphins.possesionTime == " 9:27")

        // header competitors[0] is the Dolphins, so the Chiefs are [1]: "7"–"7".
        for line in lines {
            #expect(line.score == 7)
            #expect(line.opponentScore == 7)
            #expect(line.gameClock == "13:49 - 2nd Quarter")  // the in-game detail string
        }
    }

    // Before kickoff boxscore.teams[*].statistics holds eight season
    // *averages* (totalPointsPerGame … rushingYardsPerGameAllowed). The
    // positional reader used to show them as game stats (firstDowns read
    // "32.0", yards "90.0"); read by name, none of them is a game stat, so
    // every figure is zero until the game starts.
    @Test("NFL pre-game box score shows no season averages as game stats")
    func footballPregameBoxScore() throws {
        // chiefs_summary_pregame_401872976.json
        let lines = parseFootballGameTeamStats(from: try Fixture.json("chiefs_summary_pregame_401872976"), team: .chiefs)
        try #require(lines.count == 2)

        let chiefs = lines[0]
        #expect(chiefs.name == "Chiefs")
        #expect(chiefs.firstDowns == 0)  // not totalPointsPerGame "32.0"
        #expect(chiefs.yards == 0)  // not yardsPerGame / rushingYardsPerGameAllowed
        #expect(chiefs.drives == 0)
        #expect(chiefs.passingYards == 0)
        #expect(chiefs.rushingYards == 0)
        #expect(chiefs.possesionTime == "")

        let raiders = lines[1]
        #expect(raiders.name == "Raiders")
        #expect(raiders.firstDowns == 0)
        #expect(raiders.yards == 0)

        for line in lines {
            #expect(line.score == 0)  // header competitors carry no score yet
            #expect(line.opponentScore == 0)
            #expect(line.gameClock == "Sun, October 4th at 4:25 PM EDT")
        }
    }

    // MARK: Baseball and soccer box scores

    // Each count is the stat node's "displayValue" (MLB nodes also carry a
    // numeric "value"; MLS nodes carry only "displayValue").
    @Test("MLB final box score")
    func baseballBoxScore() throws {
        // royals_summary_final_401817094.json
        let lines = parseBaseballGameTeamStats(from: try Fixture.json("royals_summary_final_401817094"))
        try #require(lines.count == 2)

        // boxscore.teams[0]: away Guardians; batting.runs 11, batting.hits 14, fielding.errors 1
        #expect(lines[0].name == "Guardians")  // team.shortDisplayName
        #expect(lines[0].homeAway == "away")
        #expect(lines[0].id == "away")
        #expect(lines[0].runs == 11)
        #expect(lines[0].hits == 14)  // batting, not fielding's "hits" 0
        #expect(lines[0].errors == 1)

        // boxscore.teams[1]: home Royals; batting.runs 5, batting.hits 10, fielding.errors 2
        #expect(lines[1].name == "Royals")
        #expect(lines[1].homeAway == "home")
        #expect(lines[1].runs == 5)
        #expect(lines[1].hits == 10)
        #expect(lines[1].errors == 2)

        // The stat nodes themselves are found by group; their values are there.
        let royals = try Fixture.json("royals_summary_final_401817094")["boxscore", "teams", 1, "statistics"]
        #expect(boxscoreStatistic(royals, named: "runs", in: "batting")["value"].intValue == 5)
        #expect(boxscoreStatistic(royals, named: "hits", in: "batting")["value"].intValue == 10)
        #expect(boxscoreStatistic(royals, named: "errors", in: "fielding")["value"].intValue == 2)
    }

    @Test("MLB pre-game summary reads season totals")
    func baseballPregameBoxScore() throws {
        // royals_summary_pregame_401817109.json: boxscore.teams carry season
        // totals. Guardians batting.runs 676, batting.hits 1282, fielding.errors 86;
        // Royals 687, 1336, 76.
        let lines = parseBaseballGameTeamStats(from: try Fixture.json("royals_summary_pregame_401817109"))
        #expect(lines.map(\.name) == ["Guardians", "Royals"])
        #expect(lines.map(\.homeAway) == ["away", "home"])
        #expect(lines.map(\.runs) == [676, 687])
        #expect(lines.map(\.hits) == [1282, 1336])
        #expect(lines.map(\.errors) == [86, 76])
    }

    @Test("MLS final box score: goals from the header, the rest from the box score")
    func soccerBoxScore() throws {
        // sporting_summary_final_761450.json
        let lines = parseSoccerGameTeamStats(from: try Fixture.json("sporting_summary_final_761450"))
        try #require(lines.count == 2)

        // boxscore.teams[0]: home San Jose; header competitor (home) score "3";
        // totalShots "17", possessionPct "44.2", wonCorners "15".
        #expect(lines[0].name == "San Jose")
        #expect(lines[0].homeAway == "home")
        #expect(lines[0].goals == 3)
        #expect(lines[0].shots == 17)
        #expect(lines[0].possessionPct == 44.2)
        #expect(lines[0].corners == 15)

        // boxscore.teams[1]: away Kansas City; header (away) score "0";
        // totalShots "7", possessionPct "55.8", wonCorners "3".
        #expect(lines[1].name == "Kansas City")
        #expect(lines[1].homeAway == "away")
        #expect(lines[1].goals == 0)
        #expect(lines[1].shots == 7)
        #expect(lines[1].possessionPct == 55.8)
        #expect(lines[1].corners == 3)
    }
}

// MARK: - Rosters

@Suite("Golden: roster parsing", .tags(.golden))
struct GoldenRosterTests {
    @Test("KU roster: a flat athletes array, sorted by surname")
    func basketballRoster() throws {
        // jayhawks_roster.json: .athletes is an array of 13 athletes (no groups)
        let roster = parseBasketballRoster(from: try Fixture.json("jayhawks_roster"))
        #expect(roster.count == 13)
        #expect(roster.map(\.lastName) == [
            "Allen", "Bidunga", "Calderon", "Cross", "Dawson", "Evers", "Jackson",
            "Mbiya", "McDowell", "Ngala", "Rosario", "Thengvall", "Tiller",
        ])

        // The athlete whose splits are captured (_athletes.json "jayhawks").
        let jackson = try #require(roster.first { $0.playerID == "4872739" })
        #expect(jackson.name == "Elmarko Jackson")  // fullName
        #expect(jackson.number == "13")  // jersey
        #expect(jackson.numberInt == 13)
        #expect(jackson.height == "6' 3\"")  // displayHeight
        #expect(jackson.weight == "195 lbs")  // displayWeight
        #expect(jackson.position == "Guard")  // position.displayName
        #expect(jackson.grade == "Sophomore")  // experience.displayValue
        #expect(jackson.hometown == "Marlton, NJ")  // birthPlace.city, .state
        #expect(jackson.status == "Active")  // status.name
        #expect(jackson.photo == "https://a.espncdn.com/i/headshots/mens-college-basketball/players/full/4872739.png")

        // An international player: no birthPlace.state, so the country is used.
        let calderon = try #require(roster.first { $0.name == "Samis Calderon" })
        #expect(calderon.hometown == "Espirito Santo, Brazil")
        // No headshot.href: the generic silhouette.
        #expect(calderon.photo == "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png")

        // jayhawks_roster_2026.json (the 2025-26 postseason roster) has the same shape.
        #expect(try parseBasketballRoster(from: Fixture.json("jayhawks_roster_2026")).count == 13)
    }

    @Test("NFL roster: unit groups are flattened, the unit kept per player")
    func footballRoster() throws {
        // chiefs_roster.json: .athletes is 6 groups {position, items}:
        // offense 23, defense 23, specialTeam 3, injuredReserveOrOut 7,
        // suspended 0, practiceSquad 13 = 69.
        let roster = parseFootballRoster(from: try Fixture.json("chiefs_roster"))
        #expect(roster.count == 69)

        // Shape pin (M6): the group `position` is a bare string.
        var units: [String: Int] = [:]
        for player in roster { units[player.team, default: 0] += 1 }
        #expect(units == [
            "offense": 23, "defense": 23, "specialTeam": 3,
            "injuredReserveOrOut": 7, "practiceSquad": 13,
        ])
        #expect(roster.first?.lastName == "Allen")
        #expect(roster.last?.lastName == "Worthy")

        // _athletes.json "chiefs": 4912218, groups[0].items[0]
        let allen = try #require(roster.first { $0.playerID == "4912218" })
        #expect(allen.name == "Cyrus Allen")
        #expect(allen.number == "13")
        #expect(allen.numberInt == 13)
        #expect(allen.height == "5' 11\"")
        #expect(allen.weight == "180 lbs")
        #expect(allen.position == "Wide Receiver")
        #expect(allen.hometown == "New Orleans, LA")
        #expect(allen.college == "Cincinnati")  // college.name
        #expect(allen.age == "23")  // age is a number in the feed
        #expect(allen.debutYear == "")  // no debutYear key
        #expect(allen.team == "offense")
        #expect(allen.photo == "https://a.espncdn.com/i/headshots/nfl/players/full/4912218.png")

        // No jersey: number "" and numberInt sorts last (1000).
        let carter = try #require(roster.first { $0.playerID == "4605841" })
        #expect(carter.name == "Nathan Carter")
        #expect(carter.number == "")
        #expect(carter.numberInt == 1000)
        #expect(carter.team == "practiceSquad")
    }

    @Test("MLB roster: position groups are flattened")
    func baseballRoster() throws {
        // royals_roster.json: .athletes is 5 groups — Pitchers 14, Catchers 2,
        // Infielders 6, Outfielders 5, Designated Hitter 1 = 28.
        let roster = parseBaseballRoster(from: try Fixture.json("royals_roster"))
        #expect(roster.count == 28)
        #expect(roster.first?.lastName == "Bivens")
        #expect(roster.last?.lastName == "Witt Jr.")

        // _athletes.json "royals": 5136077
        let bivens = try #require(roster.first { $0.playerID == "5136077" })
        #expect(bivens.name == "Spencer Bivens")
        #expect(bivens.number == "76")
        #expect(bivens.numberInt == 76)
        #expect(bivens.height == "6' 4\"")
        #expect(bivens.weight == "220 lbs")
        #expect(bivens.position == "Relief Pitcher")
        #expect(bivens.hometown == "Virginia Beach, VA")
        #expect(bivens.debutYear == "2024")  // number in the feed
        #expect(bivens.college == "")
        #expect(bivens.batHand == "Right")  // bats.displayValue
        #expect(bivens.throwHand == "Right")  // throws.displayValue
        #expect(bivens.age == "32")

        let rave = try #require(roster.first { $0.name == "John Rave" })
        #expect(rave.photo == "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png")
        #expect(rave.batHand == "Left")
    }

    // KNOWN-BUG: the MLB (and NFL) hometown is always "city, state"; an
    // international player has no state, leaving a dangling ", ". Correct:
    // fall back to the country, as the basketball parser does
    // ("Santo Domingo, Dominican Republic").
    @Test("MLB hometown for a player born abroad ends in a bare comma", .tags(.knownBug))
    func baseballInternationalHometown() throws {
        // royals_roster.json Jose Cuas: birthPlace {city "Santo Domingo", country "Dominican Republic"}
        let roster = parseBaseballRoster(from: try Fixture.json("royals_roster"))
        let cuas = try #require(roster.first { $0.playerID == "35432" })
        #expect(cuas.hometown == "Santo Domingo, ")  // KNOWN-BUG
    }

    @Test("MLS roster: a flat array with season stats embedded by position")
    func soccerRoster() throws {
        // sporting_roster.json: .athletes is an array of 31 athletes
        let roster = parseSoccerRoster(from: try Fixture.json("sporting_roster"))
        #expect(roster.count == 31)

        // Two athletes (Capita, André Luiz) have no lastName and sort first.
        #expect(Set(roster.prefix(2).map(\.name)) == ["Capita", "André Luiz"])
        #expect(roster[2].lastName == "Afrifa")
        #expect(roster.last?.lastName == "Wolff")

        // _athletes.json "sporting": 249729 — a goalkeeper.
        // statistics.splits.categories: [0] general, [1] offensive, [2] goalKeeping
        let cleveland = try #require(roster.first { $0.playerID == "249729" })
        #expect(cleveland.name == "Stefan Cleveland")
        #expect(cleveland.number == "30")
        #expect(cleveland.numberInt == 30)
        #expect(cleveland.position == "Goalkeeper")
        #expect(cleveland.age == "32")
        #expect(cleveland.birthPlace == "N/A")  // birthPlace is {} for all 31
        #expect(cleveland.citizenshipCountry == "USA")  // citizenship: a bare string (M6 shape pin)
        #expect(cleveland.appearances == 17)  // [0][5] appearances
        #expect(cleveland.foulsSuffered == 2)  // [0][1]
        #expect(cleveland.saves == 59)  // [2][0] saves
        #expect(cleveland.goalsConceded == 38)  // [2][2] goalsConceded
        // saves + goalsConceded; the feed's own shotsFaced ([2][1]) is 0.
        #expect(cleveland.shotsFaced == 97)

        // An outfield player: Capita (id 297034), no headshot.
        let capita = try #require(roster.first { $0.playerID == "297034" })
        #expect(capita.lastName == "")
        #expect(capita.citizenshipCountry == "Angola")
        #expect(capita.photo == "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png")
        #expect(capita.fouls == 28)  // [0][0] foulsCommitted
        #expect(capita.yellowCards == 4)  // [0][3]
        #expect(capita.subAppearances == 1)  // [0][6] subIns
        #expect(capita.goalAssists == 1)  // [1][0]
        #expect(capita.offsides == 3)  // [1][1]
        #expect(capita.shotsOnTarget == 8)  // [1][2]
        #expect(capita.totalShots == 21)  // [1][3]
        #expect(capita.totalGoals == 2)  // [1][4]
        // Shape pin: outfield players carry a goalKeeping category too, with
        // goalsConceded 31 (conceded while on the pitch).
        #expect(capita.goalsConceded == 31)
        #expect(capita.shotsFaced == 31)
    }
}

// MARK: - Athlete splits

@Suite("Golden: athlete stats", .tags(.golden))
struct GoldenAthleteTests {
    @Test("KU season averages weight home and away splits by games played")
    func basketballSplits() throws {
        // jayhawks_splits_4872739.json splitCategories[0].splits: [0] Home
        // (18 games), [1] Away (14 games). Value = (home·18 + away·14) / 32.
        let stats = parseBasketballPlayerStats(from: try Fixture.json("jayhawks_splits_4872739"))
        #expect(stats.gamesPlayed == 32)  // stats[0]: 18 + 14
        #expect(approx(stats.avgMinutes, 17.9875))  // [1] 17.9 / 18.1
        #expect(approx(stats.fieldGoalPct, 36.71875))  // [3] 34.4 / 39.7
        #expect(approx(stats.threePointFieldGoalPct, 36.65625))  // [5] 31.8 / 42.9
        #expect(approx(stats.freeThrowPct, 82.55625))  // [7] 82.6 / 82.5
        #expect(approx(stats.avgOffensiveRebounds, 0.1))  // [8] 0.1 / 0.1
        #expect(approx(stats.avgDefensiveRebounds, 1.73125))  // [9] 1.6 / 1.9
        #expect(approx(stats.avgRebounds, 1.775))  // [10] 1.6 / 2.0
        #expect(approx(stats.avgAssists, 1.5125))  // [11] 1.6 / 1.4
        #expect(approx(stats.avgBlocks, 0.2125))  // [12] 0.3 / 0.1
        #expect(approx(stats.avgSteals, 0.79375))  // [13] 1.1 / 0.4
        #expect(approx(stats.avgFouls, 1.7625))  // [14] 1.5 / 2.1
        #expect(approx(stats.avgTurnovers, 0.93125))  // [15] 0.8 / 1.1
        #expect(approx(stats.avgPoints, 4.89375))  // [16] 3.8 / 6.3
    }

    @Test("MLB pitcher splits fill the pitching half only")
    func baseballPitcherSplits() throws {
        // royals_splits_5136077.json splitCategories[0].splits[0].stats
        // (names: ERA, wins, losses, saves, saveOpportunities, gamesPlayed,
        // gamesStarted, completeGames, innings, hits, runs, earnedRuns,
        // homeRuns, walks, strikeouts, opponentAvg).
        // Position from royals_roster.json: "Relief Pitcher".
        let stats = parseBaseballPlayerStats(from: try Fixture.json("royals_splits_5136077"), playerPosition: "Relief Pitcher")
        #expect(approx(stats.EarnedRunAverage, 9.39))  // "9.39"
        #expect(stats.wins == 0)
        #expect(stats.losses == 0)
        #expect(stats.saves == 0)
        #expect(stats.saveOpportunities == 0)
        #expect(stats.gamesPlayed == 6)
        #expect(stats.gamesStarted == 0)
        #expect(stats.completeGames == 0)
        #expect(approx(stats.innings, 7.2))  // "7.2" (baseball notation: 7⅔)
        #expect(stats.hits == 13)
        #expect(stats.runs == 10)
        #expect(stats.earnedRuns == 8)
        #expect(stats.homeRuns == 1)
        #expect(stats.walks == 6)
        #expect(stats.strikeouts == 12)
        #expect(approx(stats.opponentAvg, 0.371))  // ".371"

        // The batting half is untouched.
        #expect(stats.AtBats == 0 && stats.Hits == 0 && stats.OPS == 0)
    }

    @Test("NFL splits: an all-zero line renders no groups")
    func footballSplitsAllZero() throws {
        // chiefs_splits_4912218.json: 12 names (receiving, rushing, fumbles),
        // splitCategories[0].splits[0].stats all "0" / "0.0". Every name is
        // catalogued, so there is no "Statistics" group either.
        let stats = parseFootballPlayerStats(from: try Fixture.json("chiefs_splits_4912218"))
        #expect(stats.loaded)
        #expect(stats.groups.isEmpty)
    }

    @Test("NFL splits: a group appears once one of its stats is non-zero")
    func footballSplitsReceiving() throws {
        // chiefs_splits_4912218.json with only splits[0].stats[0]
        // (names[0] "receptions") changed from "0" to "3".
        let json = try Fixture.json("chiefs_splits_4912218")
            .setting(["splitCategories", 0, "splits", 0, "stats", 0], to: .string("3"))
        let stats = parseFootballPlayerStats(from: json)
        #expect(stats.loaded)
        // Rushing and Ball Security stay all-zero and are dropped.
        #expect(stats.groups.map(\.title) == ["Receiving"])

        // Catalogue order; "targets" is not in this feed's names.
        let receiving = try #require(stats.groups.first)
        #expect(receiving.stats.map(\.id) == [
            "receptions", "receivingYards", "yardsPerReception", "longReception", "receivingTouchdowns",
        ])
        #expect(receiving.stats.map(\.label) == ["Receptions", "Yards", "Avg / Catch", "Long", "Touchdowns"])
        #expect(receiving.stats.map(\.display) == ["3", "0", "0.0", "0", "0"])
        #expect(receiving.rows.map(\.count) == [3, 2])
    }

    @Test("NFL splits: a failed fetch reads as loaded with no groups")
    func footballSplitsEmptyDocument() {
        let stats = parseFootballPlayerStats(from: .null)
        #expect(stats.loaded)
        #expect(stats.groups.isEmpty)
    }

    @Test("MLS keeper headline stats; outfield players read N/A")
    func soccerAthlete() throws {
        // sporting_athlete_249729.json athlete.statsSummary.statistics[i].value:
        // [0] starts-subIns 17.0, [1] saves 59.0, [2] cleanSheet 1.0, [3] goalsConceded 38.0
        let json = try Fixture.json("sporting_athlete_249729")
        let keeper = parseSoccerPlayerStats(from: json, playerPosition: "Goalkeeper")  // athlete.position.displayName
        #expect(keeper == SoccerPlayerStats(starts: "17", saves: "59", cleanSheets: "1", goalsConceded: "38"))

        let outfield = parseSoccerPlayerStats(from: json, playerPosition: "Forward")
        #expect(outfield == SoccerPlayerStats(starts: "N/A", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A"))
    }
}

// MARK: - News

/// An ESPN `published` timestamp, read with the ISO 8601 style the parser uses.
private func espnDate(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601)
}

@Suite("Golden: news parsing", .tags(.golden))
struct GoldenNewsTests {
    @Test("Chiefs news: every https article in feed order, credited to ESPN")
    func chiefsNews() throws {
        // chiefs_news.json articles[]: 25 items. articles[9] is a game
        // Preview whose links.web.href is plain http, so it is skipped.
        let articles = parseNews(from: try Fixture.json("chiefs_news"))
        #expect(articles.count == 24)
        #expect(Set(articles.map(\.id)).count == 24)
        #expect(Set(articles.map(\.title)).count == 24)
        for article in articles {
            #expect(!article.title.isEmpty)
            #expect(article.url.scheme == "https")
            #expect(article.url.host() == "www.espn.com")
            #expect(article.source == "ESPN")
            #expect(article.content == nil)
            #expect(article.urlToImage?.scheme == "https")
        }
        #expect(!articles.contains { $0.url.absoluteString.contains("/nfl/preview") })

        // articles[0] (id 50034932, type Story)
        let first = try #require(articles.first)
        #expect(first.title == "Week 3 NFL highlights: Best plays, moments, touchdowns, more")
        #expect(first.articleDescription == "Sunday of Week 3 will feature 14 games, including an international game in Rio de Janeiro between the Ravens and Cowboys.")
        #expect(first.author == "NFL Nation")  // byline
        #expect(first.url.absoluteString == "https://www.espn.com/nfl/story/_/id/50034932/best-plays-moments-touchdowns-more")
        #expect(first.urlToImage?.absoluteString == "https://a.espncdn.com/photo/2026/0927/r1722527_608x342_16-9.jpg")  // images[0].url
        #expect(first.publishedAt == espnDate("2026-09-27T18:50:54Z"))

        // articles[4] (id 50028890, type Media): a video clip with a null byline.
        let clip = articles[4]
        #expect(clip.title == "Jeff Hafley credits Chiefs' striking offense to Kenneth Walker")
        #expect(clip.url.absoluteString == "https://www.espn.com/video/clip/_/id/50028890/jeff-hafley-credits-chiefs-striking-offense-kenneth-walker")
        #expect(clip.author == nil)
        #expect(clip.publishedAt == espnDate("2026-09-25T20:01:29Z"))

        // articles[24] (id 49996723, type HeadlineNews)
        let last = try #require(articles.last)
        #expect(last.title == "Chiefs laud Kenneth Walker III's impact through 2-0 start")
        #expect(last.author == "Nate Taylor")
        #expect(last.publishedAt == espnDate("2026-09-21T07:39:39Z"))
    }

    @Test("Articles without a headline, an https link or a date are skipped (derived)")
    func unusableArticles() throws {
        // chiefs_news.json articles[0], with one field altered per copy.
        let feed = try Fixture.json("chiefs_news")
        let story = feed["articles"][0]
        let href: [JSON.Index] = ["links", "web", "href"]
        let variants: [JSON] = [
            story.setting(["headline"], to: .null),
            story.setting(["headline"], to: .string("")),
            story.setting(href, to: .null),
            story.setting(href, to: .string("javascript:alert(1)")),
            story.setting(href, to: .string("espn://story/50034932")),
            story.setting(href, to: .string("http://www.espn.com/nfl/story/_/id/50034932")),
            story.setting(["published"], to: .string("not a date")),
        ]
        for variant in variants {
            #expect(parseNews(from: .object(["articles": .array([variant])])).isEmpty)
        }

        // A repeat of the same story is kept once.
        let doubled = parseNews(from: .object(["articles": .array([story, story])]))
        #expect(doubled.count == 1)

        // Missing images and byline leave those fields nil.
        let bare = story.setting(["images"], to: .array([])).setting(["byline"], to: .null)
        let article = try #require(parseNews(from: .object(["articles": .array([bare])])).first)
        #expect(article.urlToImage == nil)
        #expect(article.author == nil)
    }
}
