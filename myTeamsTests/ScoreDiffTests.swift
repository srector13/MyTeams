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

    @Test("A game first seen says nothing, under way, before its start or over")
    func newGameAppearing() {
        let live = game(.inProgress, home: 3, away: 0, period: 1)
        let events = ScoreDiff.diff(
            previous: [:],
            current: ["1": live, "2": game(.scheduled), "3": game(.final, home: 1, away: 2, period: 2)]
        )
        #expect(events.isEmpty)
        #expect(live.summary == "K-State 0 – Kansas 3 (1st)")
    }

    @Test("Relaunched mid-game: the first look seeds quietly, the next change alerts")
    func relaunchMidGame() {
        // The snapshots died with the last launch; the game is under way.
        let seed = game(.inProgress, home: 7, away: 3, period: 2)
        #expect(ScoreDiff.diff(previous: [:], current: ["1": seed]).isEmpty)

        // What happens next reads against the seed, as before the relaunch.
        let scored = game(.inProgress, home: 7, away: 10, period: 2)
        #expect(ScoreDiff.diff(previous: ["1": seed], current: ["1": scored]) == [
            .scoreChange(gameID: "1", previous: seed, snapshot: scored),
        ])
    }

    @Test("A game first seen before its start still starts once under way")
    func seededThenStarted() {
        let pregame = game(.scheduled)
        #expect(ScoreDiff.diff(previous: [:], current: ["1": pregame]).isEmpty)

        let started = game(.inProgress, period: 1)
        #expect(ScoreDiff.diff(previous: ["1": pregame], current: ["1": started]) == [
            .gameStart(gameID: "1", snapshot: started),
        ])
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
        let pregame = game(.scheduled)
        let events = ScoreDiff.diff(previous: ["a": pregame, "b": pregame], current: ["b": a, "a": a])
        #expect(events.map(\.gameID) == ["a", "b"])
    }

    @Test("Ordinals")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(ScoreSnapshot.ordinal) == [
            "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd",
        ])
    }
}

@Suite("Score stage labels")
struct ScoreStageLabelTests {
    private func label(_ league: LeagueID, _ period: Int) -> String {
        PeriodNaming(league: league).label(period)
    }

    @Test("Regulation periods are named as the league names them")
    func regulation() {
        #expect(label(.nfl, 4) == "4th Quarter")
        #expect(label(.collegeFootball, 2) == "2nd Quarter")
        #expect(label(.nba, 3) == "3rd Quarter")
        #expect(label(.mensCollegeBasketball, 2) == "2nd Half")
        #expect(label(.nhl, 3) == "3rd Period")
        #expect(label(.premierLeague, 1) == "1st Half")
    }

    @Test("Past regulation: overtimes, or soccer's extra time and penalties")
    func pastRegulation() {
        #expect(label(.nhl, 4) == "OT")
        #expect(label(.nhl, 5) == "2OT")
        #expect(label(.nfl, 5) == "OT")
        #expect(label(.nba, 6) == "2OT")
        #expect(label(.mensCollegeBasketball, 3) == "OT")
        #expect(label(.premierLeague, 3) == "Extra Time")
        #expect(label(.premierLeague, 4) == "Extra Time")
        #expect(label(.championsLeague, 5) == "Penalties")
    }

    @Test("Innings, and a league with no names, read as ordinals")
    func ordinalFallback() {
        #expect(label(.mlb, 7) == "7th")
        #expect(label(.mlb, 11) == "11th")
        #expect(PeriodNaming.ordinal.label(4) == "4th")
        #expect(label(LeagueID(sport: "lacrosse", league: "pll"), 2) == "2nd")
    }

    @Test("A cup without a descriptor of its own takes its sport's periods")
    func undescribedCup() {
        let faCup = LeagueID.soccer("eng.fa")
        #expect(label(faCup, 2) == "2nd Half")
        #expect(label(faCup, 3) == "Extra Time")
    }

    @Test("Alerts after an overtime say so: \"End of OT\", not \"End of 4th\"")
    func overtimeAlert() {
        let naming = PeriodNaming(league: .nhl)
        let shootout = ScoreSnapshot(
            homeName: "Blues", awayName: "Jets", homeScore: 2, awayScore: 2,
            period: 5, state: .inProgress, periodNaming: naming
        )
        #expect(ScoreEvent.periodEnd(gameID: "1", period: 4, snapshot: shootout).title == "End of OT")
        #expect(ScoreEvent.periodEnd(gameID: "1", period: 3, snapshot: shootout).title == "End of 3rd Period")
        #expect(shootout.summary == "Jets 2 – Blues 2 (2OT)")

        var extraTime = shootout
        extraTime.periodNaming = PeriodNaming(league: .premierLeague)
        extraTime.period = 3
        #expect(extraTime.stageLabel == "Extra Time")
        #expect(extraTime.summary == "Jets 2 – Blues 2 (Extra Time)")
    }

    @Test("Before a period, before the start, and played out")
    func otherStages() {
        let naming = PeriodNaming(league: .nfl)
        var snapshot = ScoreSnapshot(
            homeName: "Kansas", awayName: "K-State", homeScore: 0, awayScore: 0,
            period: 0, state: .inProgress, periodNaming: naming
        )
        #expect(snapshot.stageLabel == "Live")
        snapshot.state = .scheduled
        #expect(snapshot.stageLabel == "Pregame")
        snapshot.state = .final
        snapshot.period = 5
        #expect(snapshot.stageLabel == "Final")
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
        let first = debounce.admit(score("1"), at: start)
        #expect(first)
        let early = debounce.admit(score("1"), at: start.addingTimeInterval(60))
        #expect(!early)
        let edge = debounce.admit(score("1"), at: start.addingTimeInterval(119))
        #expect(!edge)
        let reopened = debounce.admit(score("1"), at: start.addingTimeInterval(120))
        #expect(reopened)
    }

    @Test("Games are debounced separately")
    func perGame() {
        var debounce = ScoreAlertDebounce()
        let one = debounce.admit(score("1"), at: start)
        #expect(one)
        let two = debounce.admit(score("2"), at: start)
        #expect(two)
    }

    @Test("A final always goes, and restarts the window")
    func finalOverridesDebounce() {
        var debounce = ScoreAlertDebounce()
        let over = ScoreEvent.final(gameID: "1", snapshot: game(.final, home: 7, period: 4))
        let scored = debounce.admit(score("1"), at: start)
        #expect(scored)
        let finalAdmitted = debounce.admit(over, at: start.addingTimeInterval(5))
        #expect(finalAdmitted)
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
        let admitted = debounce.admit(events, at: start)
        #expect(admitted.map(\.gameID) == ["1", "2"])
        // The period's end is held, not dropped.
        #expect(debounce.held["1"] == .periodEnd(gameID: "1", period: 1, snapshot: snapshot))
    }

    @Test("Two goals in two minutes: the second is held, and posted with the latest score once the window ends")
    func heldGoalPostsLater() {
        var debounce = ScoreAlertDebounce(window: 120)
        let kickoff = game(.inProgress, period: 1)
        let one = game(.inProgress, home: 1, period: 1)
        let two = game(.inProgress, home: 2, period: 1)
        let three = game(.inProgress, home: 2, away: 1, period: 1)

        let firstGoal = ScoreEvent.scoreChange(gameID: "1", previous: kickoff, snapshot: one)
        let posted = debounce.admit([firstGoal], at: start)
        #expect(posted == [firstGoal])

        // A minute on, a second goal: inside the window, so held.
        let secondGoal = debounce.admit(
            [.scoreChange(gameID: "1", previous: one, snapshot: two)], at: start.addingTimeInterval(60)
        )
        #expect(secondGoal.isEmpty)
        // Then a reply: still inside, coalesced with the goal held — from
        // the score last told to the score now.
        let reply = debounce.admit(
            [.scoreChange(gameID: "1", previous: two, snapshot: three)], at: start.addingTimeInterval(90)
        )
        #expect(reply.isEmpty)
        let coalesced = ScoreEvent.scoreChange(gameID: "1", previous: one, snapshot: three)
        #expect(debounce.held["1"] == coalesced)

        // A look with no news before the window ends posts nothing.
        let early = debounce.admit([], at: start.addingTimeInterval(119))
        #expect(early.isEmpty)

        // The first look past it posts the held event, and restarts the
        // window.
        let followUp = debounce.admit([], at: start.addingTimeInterval(125))
        #expect(followUp == [coalesced])
        #expect(debounce.held.isEmpty)
        #expect(debounce.lastPosted["1"] == start.addingTimeInterval(125))
        let later = debounce.admit([], at: start.addingTimeInterval(400))
        #expect(later.isEmpty)
    }

    @Test("Past the window, a held score folds into the game's new event and stays a score update")
    func heldScoreFoldsIntoNews() {
        var debounce = ScoreAlertDebounce(window: 120)
        let before = game(.inProgress, home: 7, period: 1)
        let scored = game(.inProgress, home: 14, period: 1)
        let nextPeriod = game(.inProgress, home: 14, period: 2)

        let first = debounce.admit(score("1"), at: start)
        #expect(first)
        let held = ScoreEvent.scoreChange(gameID: "1", previous: before, snapshot: scored)
        let holding = debounce.admit([held], at: start.addingTimeInterval(30))
        #expect(holding.isEmpty)

        let posted = debounce.admit(
            [.periodEnd(gameID: "1", period: 1, snapshot: nextPeriod)], at: start.addingTimeInterval(150)
        )
        #expect(posted == [.scoreChange(gameID: "1", previous: before, snapshot: nextPeriod)])
        #expect(debounce.held.isEmpty)
    }

    @Test("A final clears what its game was holding: it carries the latest score")
    func finalClearsHeld() {
        var debounce = ScoreAlertDebounce(window: 120)
        let first = debounce.admit(score("1"), at: start)
        #expect(first)
        let early = debounce.admit(score("1"), at: start.addingTimeInterval(30))
        #expect(!early)
        #expect(debounce.held["1"] != nil)

        let over = ScoreEvent.final(gameID: "1", snapshot: game(.final, home: 7, period: 4))
        let fullTime = debounce.admit([over], at: start.addingTimeInterval(40))
        #expect(fullTime == [over])
        #expect(debounce.held.isEmpty)
        let later = debounce.admit([], at: start.addingTimeInterval(300))
        #expect(later.isEmpty)
    }

    @Test("A game's held event goes out on a look that only brings another game's news")
    func releasedAlongsideOtherGames() {
        var debounce = ScoreAlertDebounce(window: 120)
        let first = debounce.admit(score("1"), at: start)
        #expect(first)
        let early = debounce.admit(score("1"), at: start.addingTimeInterval(60))
        #expect(!early)

        let posted = debounce.admit([score("2")], at: start.addingTimeInterval(130))
        #expect(posted == [score("1"), score("2")])
    }
}

/// A `league` game under way as the engine reads it (R-6): its periods
/// named, its clock, and its league's close-game rule.
private func late(
    _ league: LeagueID,
    home: Int,
    away: Int,
    period: Int,
    clock: String,
    state: ScoreSnapshot.State = .inProgress
) -> ScoreSnapshot {
    ScoreSnapshot(
        homeName: "Home", awayName: "Away",
        homeScore: home, awayScore: away,
        period: period, state: state,
        periodNaming: PeriodNaming(league: league),
        clock: clock,
        lateGame: LateGameRule(league: league)
    )
}

@Suite("Close games late and overtime")
struct CloseLateTests {
    @Test("Each sport's thresholds come from its league")
    func leagueThresholds() {
        #expect(LeagueID.premierLeague.descriptor.closeGameMargin == 1)
        #expect(LeagueID.nhl.descriptor.closeGameMargin == 1)
        #expect(LeagueID.nba.descriptor.closeGameMargin == 8)
        #expect(LeagueID.nfl.descriptor.closeGameMargin == 8)
        #expect(LeagueID.mlb.descriptor.closeGameMargin == nil)
        #expect(LeagueID.nfl.descriptor.regulationPeriods == 4)
        #expect(LeagueID.mensCollegeBasketball.descriptor.regulationPeriods == 2)
        #expect(LeagueID.nhl.descriptor.regulationPeriods == 3)
        // A cup with no descriptor of its own takes its sport's regulation.
        #expect(LateGameRule(league: .soccer("eng.fa"))?.regulationPeriods == 2)
        #expect(LateGameRule(league: .mlb) == nil)
        #expect(LateGameRule(league: LeagueID(sport: "lacrosse", league: "pll")) == nil)
    }

    @Test("Football and basketball: the last regulation period, within 8, five minutes or less left")
    func countdownThresholds() throws {
        let nfl = try #require(LateGameRule(league: .nfl))
        #expect(nfl.isCloseLate(late(.nfl, home: 20, away: 12, period: 4, clock: "4:59")))
        #expect(nfl.isCloseLate(late(.nfl, home: 20, away: 12, period: 4, clock: "5:00")))
        #expect(!nfl.isCloseLate(late(.nfl, home: 21, away: 12, period: 4, clock: "4:59")))
        #expect(!nfl.isCloseLate(late(.nfl, home: 20, away: 12, period: 4, clock: "5:01")))
        #expect(!nfl.isCloseLate(late(.nfl, home: 20, away: 12, period: 3, clock: "1:00")))
        // Run out: the period is over, not late.
        #expect(!nfl.isCloseLate(late(.nfl, home: 20, away: 20, period: 4, clock: "0:00")))
        #expect(!nfl.isCloseLate(late(.nfl, home: 20, away: 20, period: 4, clock: "")))
        #expect(!nfl.isCloseLate(late(.nfl, home: 20, away: 20, period: 4, clock: "1:00", state: .final)))

        let nba = try #require(LateGameRule(league: .nba))
        #expect(nba.isCloseLate(late(.nba, home: 101, away: 99, period: 4, clock: "45.3")))
        #expect(!nba.isCloseLate(late(.nba, home: 101, away: 99, period: 2, clock: "45.3")))

        // College men play halves: the second is the last.
        let college = try #require(LateGameRule(league: .mensCollegeBasketball))
        #expect(college.isCloseLate(late(.mensCollegeBasketball, home: 60, away: 55, period: 2, clock: "3:10")))
        #expect(!college.isCloseLate(late(.mensCollegeBasketball, home: 30, away: 25, period: 1, clock: "3:10")))
    }

    @Test("Hockey: the 3rd period, within a goal, five minutes or less left")
    func hockeyThresholds() throws {
        let nhl = try #require(LateGameRule(league: .nhl))
        #expect(nhl.isCloseLate(late(.nhl, home: 3, away: 2, period: 3, clock: "4:12")))
        #expect(!nhl.isCloseLate(late(.nhl, home: 4, away: 2, period: 3, clock: "4:12")))
        #expect(!nhl.isCloseLate(late(.nhl, home: 3, away: 2, period: 3, clock: "6:00")))
        #expect(!nhl.isCloseLate(late(.nhl, home: 3, away: 2, period: 2, clock: "4:12")))
    }

    @Test("Soccer: the second half from the 80th minute, stoppage time included, within a goal")
    func soccerThresholds() throws {
        let epl = try #require(LateGameRule(league: .premierLeague))
        #expect(epl.isCloseLate(late(.premierLeague, home: 1, away: 1, period: 2, clock: "80'")))
        #expect(epl.isCloseLate(late(.premierLeague, home: 2, away: 1, period: 2, clock: "90'+3'")))
        #expect(!epl.isCloseLate(late(.premierLeague, home: 1, away: 1, period: 2, clock: "79'")))
        #expect(!epl.isCloseLate(late(.premierLeague, home: 3, away: 1, period: 2, clock: "88'")))
        #expect(!epl.isCloseLate(late(.premierLeague, home: 1, away: 1, period: 1, clock: "45'+2'")))
        #expect(!epl.isCloseLate(late(.premierLeague, home: 1, away: 1, period: 2, clock: "HT")))
    }

    @Test("A close game late alerts once, however long it stays close")
    func closeLateOnce() {
        let early = late(.nfl, home: 20, away: 17, period: 4, clock: "6:10")
        let lateLook = late(.nfl, home: 20, away: 17, period: 4, clock: "4:50")
        let first = ScoreDiff.advance(previous: ["1": early], current: ["1": lateLook])
        #expect(first.events == [.closeLate(gameID: "1", snapshot: lateLook)])
        #expect(first.events.first?.title == "Close game late")
        #expect(first.snapshots["1"]?.closeLateTold == true)

        // Tied up, still late: a score update, and no second close-game alert.
        let tied = late(.nfl, home: 20, away: 20, period: 4, clock: "2:00")
        let second = ScoreDiff.advance(previous: first.snapshots, current: ["1": tied])
        #expect(second.events == [.scoreChange(gameID: "1", previous: lateLook, snapshot: tied)])
        #expect(second.snapshots["1"]?.closeLateTold == true)

        // Without the latch carried, the same look would have alerted again.
        #expect(ScoreDiff.diff(previous: ["1": lateLook], current: ["1": tied]).contains { $0.isHeadline })
    }

    @Test("Late but not close says nothing until the margin closes, then alerts once")
    func closeLateWhenMarginCloses() {
        let wide = late(.nba, home: 100, away: 85, period: 4, clock: "4:00")
        let wider = late(.nba, home: 100, away: 88, period: 4, clock: "3:00")
        let first = ScoreDiff.advance(previous: ["1": wide], current: ["1": wider])
        #expect(first.events.allSatisfy { !$0.isHeadline })

        let close = late(.nba, home: 100, away: 94, period: 4, clock: "2:00")
        let second = ScoreDiff.advance(previous: first.snapshots, current: ["1": close])
        #expect(second.events.contains(.closeLate(gameID: "1", snapshot: close)))

        let wideAgain = late(.nba, home: 104, away: 94, period: 4, clock: "1:30")
        let closeAgain = late(.nba, home: 104, away: 100, period: 4, clock: "0:40")
        let third = ScoreDiff.advance(previous: second.snapshots, current: ["1": wideAgain])
        let fourth = ScoreDiff.advance(previous: third.snapshots, current: ["1": closeAgain])
        #expect((third.events + fourth.events).allSatisfy { !$0.isHeadline })
    }

    @Test("A game first seen close and late says nothing; one with no league rule never alerts")
    func closeLateNeedsALookBeforeAndARule() {
        let lateLook = late(.nhl, home: 2, away: 1, period: 3, clock: "3:00")
        #expect(ScoreDiff.diff(previous: [:], current: ["1": lateLook]).isEmpty)

        var unruled = lateLook
        unruled.lateGame = nil
        var before = unruled
        before.clock = "8:00"
        #expect(ScoreDiff.diff(previous: ["1": before], current: ["1": unruled]).isEmpty)
    }

    @Test("Crossing out of regulation is overtime, or extra time; told once, and no close-game alert after it")
    func overtime() {
        let endOfThird = late(.nhl, home: 2, away: 2, period: 3, clock: "0:00")
        let overtime = late(.nhl, home: 2, away: 2, period: 4, clock: "5:00")
        let crossing = ScoreDiff.advance(previous: ["1": endOfThird], current: ["1": overtime])
        #expect(crossing.events == [
            .periodEnd(gameID: "1", period: 3, snapshot: overtime),
            .overtime(gameID: "1", snapshot: overtime),
        ])
        #expect(crossing.events.last?.title == "Overtime")
        #expect(crossing.snapshots["1"]?.closeLateTold == true)

        // Late in overtime, and into a shootout: nothing more of either.
        let lateInOT = late(.nhl, home: 2, away: 2, period: 4, clock: "0:30")
        let shootout = late(.nhl, home: 2, away: 2, period: 5, clock: "0:00")
        let later = ScoreDiff.advance(previous: crossing.snapshots, current: ["1": lateInOT])
        #expect(later.events.isEmpty)
        let last = ScoreDiff.advance(previous: later.snapshots, current: ["1": shootout])
        #expect(last.events == [.periodEnd(gameID: "1", period: 4, snapshot: shootout)])

        let ucl = LeagueID.soccer("uefa.champions")
        let fullTime = late(ucl, home: 1, away: 1, period: 2, clock: "90'+4'")
        let extraTime = late(ucl, home: 1, away: 1, period: 3, clock: "91'")
        let events = ScoreDiff.diff(previous: ["1": fullTime], current: ["1": extraTime])
        #expect(events.last == .overtime(gameID: "1", snapshot: extraTime))
        #expect(events.last?.title == "Extra time")
    }

    @Test("A close-game or overtime alert stands for its game's score and period end in the same look")
    func headlines() {
        let before = late(.nfl, home: 17, away: 10, period: 4, clock: "6:00")
        let now = late(.nfl, home: 17, away: 14, period: 4, clock: "4:00")
        let other = game(.inProgress, home: 7, away: 3, period: 2)
        let events: [ScoreEvent] = [
            .scoreChange(gameID: "1", previous: before, snapshot: now),
            .closeLate(gameID: "1", snapshot: now),
            .scoreChange(gameID: "2", previous: other, snapshot: other),
        ]
        #expect(ScoreDiff.headlines(events) == [
            .closeLate(gameID: "1", snapshot: now),
            .scoreChange(gameID: "2", previous: other, snapshot: other),
        ])
        // With no headline, nothing is dropped.
        #expect(ScoreDiff.headlines(Array(events.dropFirst(2))) == Array(events.dropFirst(2)))
    }

    @Test("A look kept by an older build reads, with no clock, rule or latch; a new one round-trips them")
    func snapshotDecoding() throws {
        var told = late(.nhl, home: 2, away: 1, period: 3, clock: "3:00")
        told.closeLateTold = true
        let data = try JSONEncoder().encode(told)

        let roundTripped = try JSONDecoder().decode(ScoreSnapshot.self, from: data)
        #expect(roundTripped == told)
        #expect(roundTripped.clock == "3:00")
        #expect(roundTripped.lateGame == LateGameRule(league: .nhl))
        #expect(roundTripped.closeLateTold)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["clock"] = nil
        object["lateGame"] = nil
        object["closeLateTold"] = nil
        let older = try JSONDecoder().decode(ScoreSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older == told)
        #expect(older.clock == "")
        #expect(older.lateGame == nil)
        #expect(!older.closeLateTold)
    }
}
