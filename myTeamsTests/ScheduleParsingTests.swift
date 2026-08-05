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
    @Test("An ESPN timestamp reads as UTC and shifts to Central time")
    func parsesEventDate() throws {
        let date = try #require(parseGameDate("2021-01-18T23:00Z"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)

        #expect(components.year == 2021)
        #expect(components.month == 1)
        #expect(components.day == 18)
        // 23:00 UTC, less the six-hour offset the feed's timestamps are read at.
        #expect(components.hour == 17)
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
