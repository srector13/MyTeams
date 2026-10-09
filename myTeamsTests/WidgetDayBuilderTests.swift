//
//  WidgetDayBuilderTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The "My Day" widget's rows, the Lock Screen's inline line and the "Open
/// Live Game" control's link (`WidgetDayBuilder`, R-9), from fixture
/// seasons and scoreboard snapshots.
@Suite("Widget day builder")
struct WidgetDayBuilderTests {
    /// Tuesday, Oct 6, 2026, 16:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_302_400)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let jayhawks = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")!
    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")!
    private let royals = TeamCatalog.seeded(league: .mlb, espnID: "7")!

    /// UTC, US English, and "BUF" for ESPN id 2 in any league.
    private let builder = WidgetDayBuilder(
        calendar: WidgetDayBuilderTests.calendar,
        locale: Locale(identifier: "en_US_POSIX"),
        abbreviation: { _, espnID in espnID == "2" ? "BUF" : nil }
    )

    private func at(hours: Double) -> Date {
        Self.now.addingTimeInterval(hours * 3600)
    }

    private func game(
        id: String,
        start: Date,
        opponent: String = "Bills",
        opponentID: String = "2",
        completed: Bool = false,
        channel: String = ""
    ) -> Game {
        Game(
            team: "Chiefs", opponent: opponent, opponentID: opponentID, score: completed ? "24" : "",
            opponentScore: completed ? "17" : "", time: "", date: "Oct 06, 2026", dateAsDate: start,
            opponentLogo: "", channel: channel, location: "", gameHome: true, gameID: id, pointer: 0,
            gameWin: completed, completed: completed, competitionName: "", cancelled: false,
            postponed: false, gameClock: "", gamePeriod: "", gameHalftime: false
        )
    }

    /// `team` at home against the Bills (ESPN id 2).
    private func snapshot(
        _ gameID: String,
        team: TeamRef,
        score: (Int, Int) = (21, 17),
        state: WidgetScoreboardSnapshot.State = .inProgress,
        clock: String = "7:20",
        period: Int = 3,
        updated: Date = WidgetDayBuilderTests.now.addingTimeInterval(-60)
    ) -> WidgetScoreboardSnapshot {
        WidgetScoreboardSnapshot(
            gameID: gameID, league: team.league.path, teamID: team.id,
            homeTeamID: team.espnID, awayTeamID: "2", homeName: team.shortName, awayName: "Bills",
            homeScore: score.0, awayScore: score.1, state: state, clock: clock, period: period,
            gameDate: nil, updated: updated
        )
    }

    /// The formatters may write a narrow no-break space before "PM".
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: Ordering

    @Test func liveGamesComeFirstInFavoritesOrder() {
        let seasons: [TeamRef.ID: [Game]] = [
            jayhawks.id: [game(id: "k1", start: at(hours: 2))],
            // The live game is in the Chiefs' season too: listed once.
            chiefs.id: [game(id: "c1", start: at(hours: -1))],
        ]
        let rows = builder.rows(
            teams: [jayhawks, chiefs, royals],
            seasons: seasons,
            snapshots: [snapshot("r1", team: royals, period: 7), snapshot("c1", team: chiefs)],
            now: Self.now
        )

        #expect(rows.map(\.id) == ["c1", "r1", "k1"])
        #expect(rows.map(\.kind) == [.live, .live, .today])
        #expect(rows[0].score == "21–17")
        #expect(rows[0].status == "Live · 7:20")
        #expect(rows[0].url?.absoluteString == "myteams://game/football/nfl:c1?team=football/nfl:12")
    }

    @Test func staleSnapshotsAreNotLive() {
        let stale = snapshot("c1", team: chiefs, updated: Self.now.addingTimeInterval(-2 * 3600))
        let rows = builder.rows(teams: [chiefs], seasons: [:], snapshots: [stale], now: Self.now)
        #expect(rows.isEmpty)
    }

    @Test func todayGroupsResultsAndFixturesInStartOrder() {
        let seasons: [TeamRef.ID: [Game]] = [
            chiefs.id: [
                game(id: "yesterday", start: at(hours: -20), completed: true),
                game(id: "evening", start: at(hours: 4)),
                game(id: "morning", start: at(hours: -14), completed: true),
                game(id: "afternoon", start: at(hours: 2), channel: "ESPN"),
                game(id: "tomorrow", start: at(hours: 24)),
            ],
        ]
        // The board saw the morning game end 27–20.
        let final = snapshot("morning", team: chiefs, score: (27, 20), state: .final, updated: Self.now.addingTimeInterval(-600))
        let rows = builder.rows(teams: [chiefs], seasons: seasons, snapshots: [final], now: Self.now)

        #expect(rows.map(\.id) == ["morning", "afternoon", "evening", "tomorrow"])
        #expect(rows.map(\.kind) == [.today, .today, .today, .next])
        #expect(rows[0].status == "Final")
        #expect(rows[0].score == "27–20")
        #expect(plain(rows[1].status) == "6:00 PM")
        #expect(rows[1].channel == "ESPN")
        #expect(rows[1].score == nil)
        #expect(plain(rows[3].status) == "Wed 4:00 PM")
    }

    @Test func scheduleScoreStandsInWithoutASnapshot() {
        let seasons: [TeamRef.ID: [Game]] = [chiefs.id: [game(id: "morning", start: at(hours: -6), completed: true)]]
        let rows = builder.rows(teams: [chiefs], seasons: seasons, snapshots: [], now: Self.now)
        #expect(rows.map(\.score) == ["24–17"])
        #expect(rows.map(\.inline) == ["KC 24–17 Final"])
    }

    @Test func nextGamesPadToSix() {
        let seasons: [TeamRef.ID: [Game]] = [
            chiefs.id: (1...5).map { game(id: "c\($0)", start: at(hours: Double($0) * 24)) },
            royals.id: (1...5).map { game(id: "r\($0)", start: at(hours: Double($0) * 24 + 1)) },
        ]
        let rows = builder.rows(
            teams: [chiefs, royals],
            seasons: seasons,
            snapshots: [snapshot("live", team: chiefs)],
            now: Self.now
        )

        #expect(rows.count == WidgetDayBuilder.maxRows)
        #expect(rows.map(\.id) == ["live", "c1", "r1", "c2", "r2", "c3"])
        #expect(rows.dropFirst().allSatisfy { $0.kind == .next })
    }

    @Test func nextGamesStayInsideHomesWindow() {
        let seasons: [TeamRef.ID: [Game]] = [
            chiefs.id: [
                game(id: "soon", start: at(hours: 48)),
                game(id: "late", start: at(hours: 8 * 24)),
            ],
        ]
        let rows = builder.rows(teams: [chiefs], seasons: seasons, snapshots: [], now: Self.now)
        #expect(rows.map(\.id) == ["soon"])
    }

    @Test func liveRowsAreCappedAtSix() {
        let snapshots = (1...8).map { snapshot("g\($0)", team: chiefs) }
        let rows = builder.rows(teams: [chiefs], seasons: [:], snapshots: snapshots, now: Self.now)
        #expect(rows.count == 6)
    }

    // MARK: Inline

    @Test func inlineLiveLine() {
        #expect(WidgetDayBuilder.inlineLive(team: chiefs, snapshot: snapshot("c1", team: chiefs)) == "KC 21–17 Q3")
        #expect(WidgetDayBuilder.inlineLive(team: chiefs, snapshot: snapshot("c1", team: chiefs, period: 5)) == "KC 21–17 OT")
        #expect(WidgetDayBuilder.inlineLive(team: royals, snapshot: snapshot("r1", team: royals, score: (3, 2), period: 7)) == "KC 3–2 7th")
        #expect(WidgetDayBuilder.inlineLive(team: jayhawks, snapshot: snapshot("k1", team: jayhawks, score: (41, 38), period: 2)) == "KU 41–38 H2")
    }

    @Test func shortStages() {
        #expect(WidgetDayBuilder.shortStage(period: 2, clock: "67'", league: .mls) == "67'")
        #expect(WidgetDayBuilder.shortStage(period: 1, clock: "", league: .premierLeague) == "Live")
        #expect(WidgetDayBuilder.shortStage(period: 2, clock: "12:00", league: .nhl) == "P2")
        #expect(WidgetDayBuilder.shortStage(period: 0, clock: "", league: .nfl) == "Live")
    }

    @Test func inlineUpcomingLine() {
        let today = builder.inlineUpcoming(team: chiefs, opponent: "BUF", start: at(hours: 3 + 20.0 / 60), now: Self.now)
        #expect(plain(today) == "KC vs BUF 7:20 PM")
        let saturday = builder.inlineUpcoming(team: chiefs, opponent: "BUF", start: at(hours: 4 * 24 + 3 + 20.0 / 60), now: Self.now)
        #expect(plain(saturday) == "KC vs BUF Sat 7:20 PM")
    }

    @Test func inlineRowUsesOpponentAbbreviationOrName() {
        let seasons: [TeamRef.ID: [Game]] = [
            chiefs.id: [
                game(id: "bills", start: at(hours: 3 + 20.0 / 60)),
                game(id: "raiders", start: at(hours: 5), opponent: "Raiders", opponentID: "13"),
            ],
        ]
        let rows = builder.rows(teams: [chiefs], seasons: seasons, snapshots: [], now: Self.now)
        #expect(rows.map { plain($0.inline) } == ["KC vs BUF 7:20 PM", "KC vs Raiders 9:00 PM"])
    }

    @Test func inlineFinalAndNotice() {
        #expect(WidgetDayBuilder.inlineFinal(team: chiefs, score: "24–17") == "KC 24–17 Final")
        #expect(WidgetDayBuilder.inlineNotice(team: chiefs, message: "No upcoming games") == "KC · No upcoming games")
    }

    // MARK: No favorites

    @Test func noFavoritesNoRows() {
        let rows = builder.rows(
            teams: [],
            seasons: [chiefs.id: [game(id: "c1", start: at(hours: 2))]],
            snapshots: [snapshot("c1", team: chiefs)],
            now: Self.now
        )
        #expect(rows.isEmpty)
        #expect(WidgetDayBuilder.liveGameURL(favoriteIDs: [], snapshots: [snapshot("c1", team: chiefs)], now: Self.now) == nil)
    }

    // MARK: Control

    @Test func controlOpensFirstFavoritesLiveGame() {
        let snapshots = [snapshot("r1", team: royals), snapshot("c1", team: chiefs)]
        let url = WidgetDayBuilder.liveGameURL(favoriteIDs: [jayhawks.id, chiefs.id, royals.id], snapshots: snapshots, now: Self.now)
        #expect(url?.absoluteString == "myteams://game/football/nfl:c1?team=football/nfl:12")
    }

    @Test func controlHasNoGameWithoutAFreshLiveOne() {
        let finished = snapshot("c1", team: chiefs, state: .final)
        let stale = snapshot("c2", team: chiefs, updated: Self.now.addingTimeInterval(-2 * 3600))
        #expect(WidgetDayBuilder.liveGameURL(favoriteIDs: [chiefs.id], snapshots: [finished, stale], now: Self.now) == nil)
    }
}
