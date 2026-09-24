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

    private func game(
        pointer: Int,
        completed: Bool,
        cancelled: Bool = false,
        postponed: Bool = false
    ) -> Game {
        Game(
            team: "Jayhawks", opponent: "Bears", score: "", opponentScore: "",
            time: "", date: "", dateAsDate: .now, opponentLogo: "", channel: "TBD",
            location: "", gameHome: true, gameID: "\(pointer)", pointer: pointer,
            gameWin: false, completed: completed, competitionName: "",
            cancelled: cancelled, postponed: postponed, gameClock: "",
            gamePeriod: "", gameHalftime: false
        )
    }
}
