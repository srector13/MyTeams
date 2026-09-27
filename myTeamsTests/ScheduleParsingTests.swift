//
//  ScheduleParsingTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 2/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

@Suite("Schedule parsing")
struct ScheduleParsingTests {
    @Test("An ESPN timestamp reads as the UTC instant it names")
    func parsesEventDate() throws {
        let date = try #require(parseGameDate("2021-01-18T23:00Z"))

        // Anchor the expectation to the instant itself, not to any zone: a
        // UTC calendar must read back the wall-clock fields of the raw
        // timestamp on a device set to *any* timezone. (An earlier version
        // asserted 17:00 UTC — the old parse-local-then-minus-6h behaviour —
        // which only held on a UTC machine and masked the timezone bug.)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        #expect(components.year == 2021)
        #expect(components.month == 1)
        #expect(components.day == 18)
        #expect(components.hour == 23)
        #expect(components.minute == 0)

        // And the same instant expressed independently, guarding against a
        // parser that drifts by whole hours in either direction.
        let expected = calendar.date(from: DateComponents(
            year: 2021, month: 1, day: 18, hour: 23, minute: 0
        ))
        #expect(date == expected)
    }

    @Test("A timestamp in an unexpected shape reads as no date")
    func rejectsMalformedDate() {
        #expect(parseGameDate("") == nil)
        #expect(parseGameDate("last Tuesday") == nil)
    }

    @Test("The next game is the first that has not been played")
    func findsNextGame() {
        let schedule = [
            game(pointer: 0, completed: true),
            game(pointer: 1, completed: true),
            game(pointer: 2, completed: false),
            game(pointer: 3, completed: false),
        ]
        #expect(getNextGame(schedule: schedule) == 2)
    }

    @Test("Cancelled and postponed fixtures count as played")
    func skipsAbandonedGames() {
        let schedule = [
            game(pointer: 0, completed: true),
            game(pointer: 1, completed: false, cancelled: true),
            game(pointer: 2, completed: false, postponed: true),
            game(pointer: 3, completed: false),
        ]
        #expect(getNextGame(schedule: schedule) == 3)
    }

    @Test("A finished season points at its last game rather than past the end")
    func clampsToEndOfSeason() {
        let schedule = [
            game(pointer: 0, completed: true),
            game(pointer: 1, completed: true),
        ]
        #expect(getNextGame(schedule: schedule) == 1)
    }

    @Test("A season-ending loss counts, even though the pointer clamps before it")
    func countsSeasonEndingLoss() {
        let schedule = [
            game(pointer: 0, completed: true, win: true),
            game(pointer: 1, completed: true, win: true),
            game(pointer: 2, completed: true, win: false),
        ]
        // The carousel pointer clamps to the last game, which under the old
        // `pointer < nextGame` rule made that finale invisible to the record.
        #expect(getNextGame(schedule: schedule) == 2)
        #expect(seasonRecord(games: schedule) == (wins: 2, losses: 1, draws: 0))
    }

    @Test("A completed game lost on the scoreboard counts as a loss")
    func unequalScoreIsLoss() {
        let schedule = [
            game(pointer: 0, completed: true, win: false, score: "1", opponentScore: "2"),
        ]
        #expect(seasonRecord(games: schedule) == (wins: 0, losses: 1, draws: 0))
    }

    @Test("A completed game with no winner and no scores still counts as a loss")
    func forfeitCountsAsLoss() {
        // No scoreline to call it level, so the old rule stands.
        let schedule = [
            game(pointer: 0, completed: true, win: false),
        ]
        #expect(seasonRecord(games: schedule) == (wins: 0, losses: 1, draws: 0))
    }

    @Test("A level MLS match is a draw, not a loss")
    func soccerDrawIsNotLoss() {
        // Neither side's winner flag is set on a 1-1 draw.
        let schedule = [
            game(pointer: 0, completed: true, win: true, score: "2", opponentScore: "0"),
            game(pointer: 1, completed: true, win: false, score: "1", opponentScore: "1"),
            game(pointer: 2, completed: true, win: false, score: "0", opponentScore: "3"),
        ]
        #expect(seasonRecord(games: schedule) == (wins: 1, losses: 1, draws: 1))

        // The soccer tab's date fallback counts a past, level fixture as a
        // draw too.
        let unflagged = game(
            pointer: 0, completed: false, score: "0", opponentScore: "0",
            date: Date().addingTimeInterval(-6 * 3600)
        )
        #expect(
            seasonRecord(games: [unflagged], pastDatesCountAsPlayed: true)
                == (wins: 0, losses: 0, draws: 1)
        )
    }

    @Test("A tied NFL game is a tie, not a loss")
    func footballTieIsNotLoss() {
        let tie = game(pointer: 0, completed: true, win: false, score: "20", opponentScore: "20")
        #expect(tie.isDraw)
        #expect(seasonRecord(games: [tie]) == (wins: 0, losses: 0, draws: 1))
    }

    @Test("Only a level, unwon scoreline is a draw")
    func drawDetection() {
        #expect(game(pointer: 0, completed: true, score: "1", opponentScore: "1").isDraw)
        #expect(!game(pointer: 0, completed: true, score: "2", opponentScore: "1").isDraw)
        // No scores published yet.
        #expect(!game(pointer: 0, completed: false).isDraw)
        #expect(!game(pointer: 0, completed: true, score: "1", opponentScore: "").isDraw)
        // A winner flag wins out over a level scoreline (e.g. a shootout).
        #expect(!game(pointer: 0, completed: true, win: true, score: "1", opponentScore: "1").isDraw)
    }

    @Test("A level game in progress is neither draw nor loss")
    func liveLevelGameExcluded() {
        let live = game(
            pointer: 0, completed: false, score: "1", opponentScore: "1",
            date: Date().addingTimeInterval(-1 * 3600)
        )
        #expect(seasonRecord(games: [live]) == (wins: 0, losses: 0, draws: 0))
        #expect(
            seasonRecord(games: [live], pastDatesCountAsPlayed: true)
                == (wins: 0, losses: 0, draws: 0)
        )
    }

    @Test("Unplayed games are neither win nor loss")
    func futureExcluded() {
        let later = Date().addingTimeInterval(86_400)
        let schedule = [
            game(pointer: 0, completed: true, win: true),
            game(pointer: 1, completed: false, date: later),
        ]
        #expect(seasonRecord(games: schedule) == (wins: 1, losses: 0, draws: 0))
    }

    @Test("Cancelled fixtures are losses only on the baseball rule")
    func abandonedFixtures() {
        let schedule = [
            game(pointer: 0, completed: false, cancelled: true),
            game(pointer: 1, completed: false, postponed: true),
        ]
        #expect(seasonRecord(games: schedule) == (wins: 0, losses: 0, draws: 0))
        #expect(
            seasonRecord(games: schedule, countingAbandonedAsLosses: true)
                == (wins: 0, losses: 2, draws: 0)
        )
    }

    @Test("A past start time stands in for played only on the date-only feed")
    func dateOnlySchedule() {
        let sixHoursAgo = Date().addingTimeInterval(-6 * 3600)
        let schedule = [
            game(pointer: 0, completed: false, date: sixHoursAgo),
        ]
        // Past the grace window: a fixture whose kickoff is hours gone counts
        // as played only where the feed ships no completion flag.
        #expect(seasonRecord(games: schedule) == (wins: 0, losses: 0, draws: 0))
        #expect(
            seasonRecord(games: schedule, pastDatesCountAsPlayed: true)
                == (wins: 0, losses: 1, draws: 0)
        )

        let inProgress = game(
            pointer: 0, completed: false,
            date: Date().addingTimeInterval(-2 * 3600)
        )
        #expect(
            seasonRecord(games: [inProgress], pastDatesCountAsPlayed: true)
                == (wins: 0, losses: 0, draws: 0)
        )
    }

    @Test("An empty schedule resolves to the placeholder index without trapping")
    func emptySchedule() {
        #expect(getNextGame(schedule: []) == 0)
        #expect(getNextGame(schedule: [], pastDatesCountAsPlayed: true) == 0)
    }

    @Test("A season whose flags never arrived points at its last game, not its opener")
    func pastSeasonWithoutFlagsClampsToEnd() {
        // What the soccer feed used to look like: every fixture unflagged and
        // weeks past. The date fallback walks the whole schedule and the
        // pointer clamps to the final game instead of silently returning 0.
        let lastWeek = Date().addingTimeInterval(-7 * 86_400)
        let schedule = (0..<3).map {
            game(pointer: $0, completed: false, date: lastWeek)
        }
        #expect(getNextGame(schedule: schedule, pastDatesCountAsPlayed: true) == 2)
        // Even with the fallback off (a completed-only feed), the clamp still
        // lands on the last game rather than the season opener.
        let flagged = (0..<3).map {
            game(pointer: $0, completed: true, date: lastWeek)
        }
        #expect(getNextGame(schedule: flagged) == 2)
    }

    @Test("The date fallback skips played fixtures and holds at a live one")
    func dateFallbackWalksPastKickoffs() {
        let now = Date()
        let schedule = [
            game(pointer: 0, completed: false, date: now.addingTimeInterval(-10 * 86_400)),
            game(pointer: 1, completed: false, date: now.addingTimeInterval(-5 * 3600)),
            game(pointer: 2, completed: false, date: now.addingTimeInterval(3 * 86_400)),
        ]
        // Games 0 and 1 are past their grace window; game 2 is next.
        #expect(getNextGame(schedule: schedule, pastDatesCountAsPlayed: true, now: now) == 2)
        // The same schedule without the fallback stops at the unflagged game 0.
        #expect(getNextGame(schedule: schedule, now: now) == 0)

        // A live fixture inside the four-hour window holds the pointer.
        let withLive = [
            game(pointer: 0, completed: false, date: now.addingTimeInterval(-10 * 86_400)),
            game(pointer: 1, completed: false, date: now.addingTimeInterval(-2 * 3600)),
            game(pointer: 2, completed: false, date: now.addingTimeInterval(3 * 86_400)),
        ]
        #expect(
            getNextGame(schedule: withLive, pastDatesCountAsPlayed: true, now: now) == 1
        )
    }

    @Test("Only games in the live window are polled for scores")
    func livePollingWindow() {
        let now = Date()
        // In progress: started two hours ago, feed has not flagged completion.
        #expect(shouldPollLiveScore(
            game: game(pointer: 0, completed: false, date: now.addingTimeInterval(-2 * 3600)),
            now: now
        ))
        // Starting in ten minutes: inside the fifteen-minute lead-in.
        #expect(shouldPollLiveScore(
            game: game(pointer: 0, completed: false, date: now.addingTimeInterval(10 * 60)),
            now: now
        ))
        // Tomorrow's fixture and last week's unflagged one are both out.
        #expect(!shouldPollLiveScore(
            game: game(pointer: 0, completed: false, date: now.addingTimeInterval(86_400)),
            now: now
        ))
        #expect(!shouldPollLiveScore(
            game: game(pointer: 0, completed: false, date: now.addingTimeInterval(-9 * 3600)),
            now: now
        ))
    }

    @Test("Finished, abandoned and unaddressable games are never polled")
    func livePollingExclusions() {
        let now = Date()
        let inWindow = now.addingTimeInterval(-3600)
        #expect(!shouldPollLiveScore(
            game: game(pointer: 0, completed: true, date: inWindow), now: now))
        #expect(!shouldPollLiveScore(
            game: game(pointer: 0, completed: false, cancelled: true, date: inWindow), now: now))
        #expect(!shouldPollLiveScore(
            game: game(pointer: 0, completed: false, postponed: true, date: inWindow), now: now))

        // No game id means the summary endpoint cannot be addressed.
        var anonymous = game(pointer: 0, completed: false, date: inWindow)
        anonymous.gameID = ""
        #expect(!shouldPollLiveScore(game: anonymous, now: now))
    }

    /// Two events: one carrying ESPN's event id, one with neither an event
    /// nor a competition id, which falls back to its date and opponent.
    static let scheduleFeed = """
    {"events": [
      {"id": "401700001", "date": "2026-11-04T01:00Z", "name": "Howard at Kansas",
       "competitions": [{"id": "401700001",
         "status": {"type": {"completed": false}},
         "competitors": [
           {"homeAway": "home", "team": {"id": "2305", "nickname": "Kansas"}},
           {"homeAway": "away", "team": {"id": "47", "nickname": "Howard"}}
         ]}]},
      {"date": "2026-11-08T01:00Z", "name": "Kansas at Duke",
       "competitions": [{
         "status": {"type": {"completed": false}},
         "competitors": [
           {"homeAway": "away", "team": {"id": "2305", "nickname": "Kansas"}},
           {"homeAway": "home", "team": {"id": "150", "nickname": "Duke"}}
         ]}]}
    ]}
    """

    @Test("Game ids are identical across two parses of the same feed")
    func deterministicGameIDs() {
        let first = parseSchedule(from: JSON(data: Data(Self.scheduleFeed.utf8)), team: .jayhawks)
        let second = parseSchedule(from: JSON(data: Data(Self.scheduleFeed.utf8)), team: .jayhawks)

        #expect(first.count == 2)
        #expect(first.map(\.id) == second.map(\.id))
        // Stable ids also make an unchanged refresh compare equal, so SwiftUI
        // sees nothing to redraw.
        #expect(first == second)

        #expect(first.first?.id == "401700001")
        #expect(first.last?.id == "2026-11-08T01:00Z|Duke|1")
        #expect(Set(first.map(\.id)).count == first.count)
    }

    private func game(
        pointer: Int,
        completed: Bool,
        win: Bool = false,
        cancelled: Bool = false,
        postponed: Bool = false,
        score: String = "",
        opponentScore: String = "",
        date: Date = .now
    ) -> Game {
        Game(
            team: "Jayhawks", opponent: "Bears", score: score, opponentScore: opponentScore,
            time: "", date: "", dateAsDate: date, opponentLogo: "", channel: "TBD",
            location: "", gameHome: true, gameID: "\(pointer)", pointer: pointer,
            gameWin: win, completed: completed, competitionName: "",
            cancelled: cancelled, postponed: postponed, gameClock: "",
            gamePeriod: "", gameHalftime: false
        )
    }
}
