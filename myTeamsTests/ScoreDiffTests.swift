//
//  ScoreDiffTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Kansas at home to Kansas State, as the diff sees it.
private func game(
    _ state: ScoreSnapshot.State,
    home: Int = 0,
    away: Int = 0,
    period: Int = 0
) -> ScoreSnapshot {
    ScoreSnapshot(
        homeName: "Kansas", awayName: "K-State",
        homeScore: home, awayScore: away,
        period: period, state: state
    )
}

@Suite("Score diff")
struct ScoreDiffTests {
    @Test("Nothing changed, nothing to say")
    func noChange() {
        let board = ["1": game(.inProgress, home: 7, away: 3, period: 2)]
        #expect(ScoreDiff.diff(previous: board, current: board).isEmpty)
        #expect(ScoreDiff.diff(previous: [:], current: [:]).isEmpty)
    }

    @Test("Kickoff starts the game")
    func gameStart() {
        let started = game(.inProgress, period: 1)
        let events = ScoreDiff.diff(previous: ["1": game(.scheduled)], current: ["1": started])
        #expect(events == [.gameStart(gameID: "1", snapshot: started)])
    }

    @Test("A new score reports both figures")
    func scoreChange() {
        let before = game(.inProgress, home: 7, away: 3, period: 2)
        let after = game(.inProgress, home: 14, away: 3, period: 2)
        let events = ScoreDiff.diff(previous: ["1": before], current: ["1": after])
        #expect(events == [.scoreChange(gameID: "1", previous: before, snapshot: after)])
    }

    @Test("A new period ends the one before")
    func periodEnd() {
        let after = game(.inProgress, home: 7, away: 3, period: 3)
        let events = ScoreDiff.diff(
            previous: ["1": game(.inProgress, home: 7, away: 3, period: 2)],
            current: ["1": after]
        )
        #expect(events == [.periodEnd(gameID: "1", period: 2, snapshot: after)])
        #expect(events[0].title == "End of 2nd")
    }

    @Test("A score and a new period in one look report the score first")
    func scoreThenPeriod() {
        let before = game(.inProgress, home: 7, away: 3, period: 1)
        let after = game(.inProgress, home: 7, away: 10, period: 2)
        let events = ScoreDiff.diff(previous: ["1": before], current: ["1": after])
        #expect(events == [
            .scoreChange(gameID: "1", previous: before, snapshot: after),
            .periodEnd(gameID: "1", period: 1, snapshot: after),
        ])
    }

    @Test("Going final says only final, whatever else changed")
    func goingFinal() {
        let after = game(.final, home: 21, away: 17, period: 4)
        let events = ScoreDiff.diff(
            previous: ["1": game(.inProgress, home: 14, away: 17, period: 4)],
            current: ["1": after]
        )
        #expect(events == [.final(gameID: "1", snapshot: after)])
        #expect(after.summary == "K-State 17 – Kansas 21 (Final)")
    }

    @Test("A final stays quiet on later looks")
    func finalIsOnce() {
        let over = game(.final, home: 21, away: 17, period: 4)
        #expect(ScoreDiff.diff(previous: ["1": over], current: ["1": over]).isEmpty)
    }

    @Test("A game first seen under way starts; before its start or over, it does not")
    func newGameAppearing() {
        let live = game(.inProgress, home: 3, away: 0, period: 1)
        let events = ScoreDiff.diff(
            previous: [:],
            current: ["1": live, "2": game(.scheduled), "3": game(.final, home: 1, away: 2, period: 2)]
        )
        #expect(events == [.gameStart(gameID: "1", snapshot: live)])
        #expect(live.summary == "K-State 0 – Kansas 3 (1st)")
    }

    @Test("A game dropping off the board says nothing")
    func gameDisappearing() {
        let events = ScoreDiff.diff(
            previous: ["1": game(.inProgress, home: 7, away: 3, period: 2)],
            current: [:]
        )
        #expect(events.isEmpty)
    }

    @Test("Events come in game id order")
    func ordering() {
        let a = game(.inProgress, period: 1)
        let events = ScoreDiff.diff(previous: [:], current: ["b": a, "a": a])
        #expect(events.map(\.gameID) == ["a", "b"])
    }

    @Test("Ordinals")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(ScoreSnapshot.ordinal) == [
            "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd",
        ])
    }
}

@Suite("Score alert debounce")
struct ScoreAlertDebounceTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func score(_ gameID: String) -> ScoreEvent {
        let snapshot = game(.inProgress, home: 7, period: 1)
        return .scoreChange(gameID: gameID, previous: snapshot, snapshot: snapshot)
    }

    @Test("One alert per game per window")
    func window() {
        var debounce = ScoreAlertDebounce(window: 120)
        #expect(debounce.admit(score("1"), at: start))
        #expect(!debounce.admit(score("1"), at: start.addingTimeInterval(60)))
        #expect(!debounce.admit(score("1"), at: start.addingTimeInterval(119)))
        #expect(debounce.admit(score("1"), at: start.addingTimeInterval(120)))
    }

    @Test("Games are debounced separately")
    func perGame() {
        var debounce = ScoreAlertDebounce()
        #expect(debounce.admit(score("1"), at: start))
        #expect(debounce.admit(score("2"), at: start))
    }

    @Test("A final always goes, and restarts the window")
    func finalOverridesDebounce() {
        var debounce = ScoreAlertDebounce()
        let over = ScoreEvent.final(gameID: "1", snapshot: game(.final, home: 7, period: 4))
        #expect(debounce.admit(score("1"), at: start))
        #expect(debounce.admit(over, at: start.addingTimeInterval(5)))
        #expect(debounce.lastPosted["1"] == start.addingTimeInterval(5))
    }

    @Test("Of one look's events, only the first per game goes")
    func batch() {
        var debounce = ScoreAlertDebounce()
        let snapshot = game(.inProgress, home: 7, period: 2)
        let events: [ScoreEvent] = [
            .scoreChange(gameID: "1", previous: snapshot, snapshot: snapshot),
            .periodEnd(gameID: "1", period: 1, snapshot: snapshot),
            .gameStart(gameID: "2", snapshot: snapshot),
        ]
        #expect(debounce.admit(events, at: start).map(\.gameID) == ["1", "2"])
    }
}
