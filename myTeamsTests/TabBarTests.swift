//
//  TabBarTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Where the "Teams" tab sits among the favorites' tabs in the system tab
/// bar (`HomeTabs.editIndex`).
@Suite("Tab bar")
struct TabBarTests {
    @Test("The Teams tab comes last while every tab fits the bar")
    func editLastWhileTheBarHoldsAll() {
        #expect(HomeTabs.editIndex(teamCount: 0, barCapacity: HomeTabs.compactCapacity) == 0)
        #expect(HomeTabs.editIndex(teamCount: 1, barCapacity: HomeTabs.compactCapacity) == 1)
        #expect(HomeTabs.editIndex(teamCount: 4, barCapacity: HomeTabs.compactCapacity) == 4)
    }

    @Test("Past the bar's capacity the Teams tab takes the last slot before More")
    func editBeforeMoreOnceTheyOverflow() {
        // Five favorites and Teams make six: the bar shows four and More.
        #expect(HomeTabs.editIndex(teamCount: 5, barCapacity: HomeTabs.compactCapacity) == 3)
        #expect(HomeTabs.editIndex(teamCount: 12, barCapacity: HomeTabs.compactCapacity) == 3)
    }

    @Test("With no limit on the bar the Teams tab comes last")
    func editLastWithoutALimit() {
        #expect(HomeTabs.editIndex(teamCount: 12, barCapacity: nil) == 12)
    }

    @Test("The Teams tab's value can't be a team's")
    func editValueIsNotATeamID() {
        // A team's id is "<leaguePath>:<espnID>".
        #expect(!HomeTabs.edit.contains(":"))
        #expect(HomeTabs.edit == "teamPicker.edit")
    }
}

/// What a team page's header says under the team's name
/// (`TeamHeaderSummary`).
@Suite("Team page header")
struct TeamHeaderSummaryTests {
    private let chiefs = TeamRef.chiefs

    private func game(pointer: Int, opponent: String = "Raiders", home: Bool = true, completed: Bool) -> Game {
        Game(
            team: "Chiefs", opponent: opponent, score: "", opponentScore: "",
            time: "", date: "", dateAsDate: .now, opponentLogo: "", channel: "",
            location: "", gameHome: home, gameID: "\(pointer)", pointer: pointer,
            gameWin: false, completed: completed, competitionName: "",
            cancelled: false, postponed: false, gameClock: "",
            gamePeriod: "", gameHalftime: false
        )
    }

    private func entry(_ teamID: String, rank: Int?) -> StandingsEntry {
        StandingsEntry(
            teamID: teamID, name: teamID, shortName: teamID, abbreviation: teamID,
            logoURL: nil, record: Record(wins: 0, losses: 0, format: .winLoss), rank: rank,
            gamesBehind: "", conferenceRecord: "", goalDifference: "", streak: "",
            note: "", noteColorHex: "", clincher: ""
        )
    }

    private func standings(_ kind: StandingsKind, rank: Int?) -> Standings {
        Standings(kind: kind, seasonDisplayName: "", groups: [
            StandingsGroup(id: "1", name: "AFC West", abbreviation: "AFCW", entries: [
                entry("13", rank: 1), entry("12", rank: rank),
            ]),
        ])
    }

    @Test("Nothing to say before the feeds load")
    func empty() {
        let summary = TeamHeaderSummary(
            team: chiefs, games: [], nextGame: 0,
            record: Record(wins: 0, losses: 0, format: .winLoss), standings: nil
        )
        #expect(summary == TeamHeaderSummary())
        #expect(summary.recordLine == nil)
    }

    @Test("The record and the table position share a line")
    func recordLine() {
        let summary = TeamHeaderSummary(
            team: chiefs, games: [game(pointer: 0, completed: true)], nextGame: 0,
            record: Record(wins: 10, losses: 6, format: .winLoss), standings: standings(.records, rank: 2)
        )
        #expect(summary.record == "10-6")
        #expect(summary.standing == "2nd in AFC West")
        #expect(summary.recordLine == "10-6 · 2nd in AFC West")
        #expect(TeamHeaderSummary(record: "4-1-0").recordLine == "4-1-0")
    }

    @Test("A poll gives a rank; an unranked team or one not in the table gives nothing")
    func standing() {
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.rankings, rank: 5)) == "No. 5 in AFC West")
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.pointsTable, rank: 13)) == "13th in AFC West")
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.records, rank: nil)) == nil)
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.records, rank: 0)) == nil)
        #expect(TeamHeaderSummary.standing(of: "99", in: standings(.records, rank: 2)) == nil)
    }

    @Test("The next game reads vs at home and at away, until the season is played out")
    func nextGame() throws {
        let home = try #require(TeamHeaderSummary.upcoming(games: [game(pointer: 0, completed: false)], nextGame: 0))
        #expect(home.hasPrefix("vs Raiders · "))
        let away = try #require(TeamHeaderSummary.upcoming(
            games: [game(pointer: 0, completed: true), game(pointer: 1, opponent: "Broncos", home: false, completed: false)],
            nextGame: 1
        ))
        #expect(away.hasPrefix("at Broncos · "))
        // `getNextGame` clamps to the last game once all are played.
        #expect(TeamHeaderSummary.upcoming(games: [game(pointer: 0, completed: true)], nextGame: 0) == nil)
        #expect(TeamHeaderSummary.upcoming(games: [], nextGame: 0) == nil)
    }
}
