//
//  AppIntentsTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

// The App Intents (R-12) through the plain code their `perform()` hands
// to: the intents themselves need the system's App Intents metadata to run.

private let chiefsID = TeamRef.id(league: .nfl, espnID: "12")
private let royalsID = TeamRef.id(league: .mlb, espnID: "7")

@Suite("App Intents: next game")
struct NextGameIntentTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    /// Sunday, Oct 4, 2026, 18:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_136_800)

    private func chiefs() throws -> TeamRef {
        try #require(TeamCatalog.seeded(league: .nfl, espnID: "12"))
    }

    private func time(_ date: Date) -> String {
        NextGameAnswer.format(date, template: "jmm", calendar: Self.calendar, locale: Self.locale)
    }

    private func snapshot(state: WidgetScoreboardSnapshot.State) -> WidgetScoreboardSnapshot {
        WidgetScoreboardSnapshot(
            gameID: "401", league: "football/nfl", teamID: chiefsID,
            homeTeamID: "12", awayTeamID: "13", homeName: "Chiefs", awayName: "Raiders",
            homeScore: 17, awayScore: 24, state: state, clock: "4:12", period: 3,
            gameDate: Self.now.addingTimeInterval(-3_600), updated: Self.now.addingTimeInterval(-60)
        )
    }

    @Test("Answers with the next game in the fixture schedule, served through FixtureTransport")
    func nextGameFromFixtures() async throws {
        let chiefs = try chiefs()
        let client = HTTPClient(transport: FixtureTransport(directory: try Fixture.directory()))
        let parsed = parseSchedule(from: try Fixture.json("chiefs_schedule"), team: chiefs)
        let upcoming = try #require(
            parsed
                .filter { !$0.cancelled && !$0.postponed }
                .min { $0.dateAsDate < $1.dateAsDate }
        )
        // Two days before the season's first game: it is the next one.
        let now = upcoming.dateAsDate.addingTimeInterval(-2 * 24 * 60 * 60)

        let answer = await NextGameAnswer.load(
            for: chiefs,
            now: now,
            calendar: Self.calendar,
            locale: Self.locale,
            schedule: { team in
                await client.fetch(team.scheduleURL).map(empty: []) { parseSchedule(from: $0, team: team) }
            },
            snapshots: []
        )

        #expect(answer.kind == .next)
        #expect(answer.opponent == upcoming.opponent)
        #expect(answer.kickoff == upcoming.dateAsDate)
        // The dialog: who, when on the reader's clock, and against whom.
        #expect(answer.speech.hasPrefix("\(chiefs.shortName) play next on "))
        #expect(answer.speech.contains(time(upcoming.dateAsDate)))
        #expect(answer.speech.contains("against \(upcoming.opponent)"))
        // The snippet: the opponent first, then when.
        #expect(answer.snippetLines.first == "vs \(upcoming.opponent)")
        #expect(answer.snippetLines.dropFirst().first?.hasPrefix("On ") == true)
    }

    @Test("A schedule that fails to load says so; one with nothing left says the season is over")
    func noGame() throws {
        let chiefs = try chiefs()
        let failed = NextGameAnswer.answer(for: chiefs, featured: .none, schedule: nil, now: Self.now)
        #expect(failed.kind == .failed)
        #expect(failed.speech.contains("couldn't load"))
        #expect(failed.snippetLines == ["Couldn't update"])

        let over = NextGameAnswer.answer(for: chiefs, featured: .none, schedule: [], now: Self.now)
        #expect(over.kind == .seasonOver)
        #expect(over.speech == "\(chiefs.shortName) have no games left on their schedule.")
        #expect(over.snippetLines == ["No upcoming games"])
    }

    @Test("A game under way or finished today is answered with its score")
    func liveAndResult() throws {
        let chiefs = try chiefs()
        let live = NextGameAnswer.answer(for: chiefs, featured: .live(snapshot(state: .inProgress)), schedule: [], now: Self.now)
        #expect(live.kind == .live)
        #expect(live.opponent == "Raiders")
        #expect(live.speech == "\(chiefs.shortName) are playing Raiders right now: 17–24, Live · 4:12.")
        #expect(live.snippetLines == ["vs Raiders", "17–24 · Live · 4:12"])

        let result = NextGameAnswer.answer(for: chiefs, featured: .result(snapshot(state: .final)), schedule: [], now: Self.now)
        #expect(result.kind == .result)
        #expect(result.speech == "\(chiefs.shortName) played Raiders today: Final, 17–24.")
    }

    @Test("When is said relative to today: today, tomorrow, a weekday, then a date")
    func spokenWhen() {
        func when(_ offset: TimeInterval) -> (String, String) {
            let date = Self.now.addingTimeInterval(offset)
            return (
                NextGameAnswer.spokenWhen(date, now: Self.now, calendar: Self.calendar, locale: Self.locale),
                time(date)
            )
        }
        let hour: TimeInterval = 60 * 60
        let (today, todayTime) = when(2 * hour)
        #expect(today == "today at \(todayTime)")
        let (tomorrow, tomorrowTime) = when(23 * hour)
        #expect(tomorrow == "tomorrow at \(tomorrowTime)")
        // Wednesday, Oct 7.
        let (weekday, weekdayTime) = when(3 * 24 * hour)
        #expect(weekday == "on Wednesday at \(weekdayTime)")
        // Sunday, Oct 18: more than a week out.
        let (dated, datedTime) = when(14 * 24 * hour)
        #expect(dated == "on Sunday, October 18 at \(datedTime)")
    }
}

@Suite("App Intents: open team")
struct OpenTeamIntentTests {
    @Test("The link the intent opens parses back to the team, through the app's own parser")
    func linkParses() throws {
        let url = try #require(OpenTeamIntent.link(for: chiefsID))
        #expect(url.scheme == WidgetDeepLink.scheme)
        #expect(WidgetDeepLink.teamID(from: url) == chiefsID)
        #expect(WidgetDeepLink.linkedTeamID(from: url) == chiefsID)
        #expect(WidgetDeepLink.game(from: url) == nil)
        #expect(OpenTeamIntent.link(for: "not-a-team") == nil)
    }

    @Test("Home routes the intent's link to the team's page")
    func linkRoutes() throws {
        let url = try #require(OpenTeamIntent.link(for: chiefsID))
        let id = try #require(WidgetDeepLink.teamID(from: url))
        let favorites = [royalsID, chiefsID]
        let state = HomeRouting.State(selection: royalsID, pendingLink: id)
        let next = HomeRouting.linkChanged(state, teams: favorites, favoriteIDs: favorites)
        #expect(next.selection == chiefsID)
        #expect(next.pendingLink == nil)
    }
}

@Suite("App Intents: team entities and Spotlight")
struct TeamEntityTests {
    @Test("An entity is identified by its team's TeamRef.id")
    func identity() throws {
        let chiefs = try #require(TeamCatalog.seeded(league: .nfl, espnID: "12"))
        #expect(TeamEntity(team: chiefs).id == chiefsID)
        #expect(TeamEntity(team: chiefs).team == chiefs)
    }

    @Test("Search results become one entity per team")
    func searchEntities() throws {
        let chiefs = try #require(TeamCatalog.seeded(league: .nfl, espnID: "12"))
        let royals = try #require(TeamCatalog.seeded(league: .mlb, espnID: "7"))
        let ids = TeamEntityQuery.entities(for: [chiefs, royals]).map(\.id)
        #expect(Set(ids) == [chiefsID, royalsID])
    }

    @Test("A malformed id resolves to no entity")
    func malformedID() async throws {
        let entities = try await TeamEntityQuery().entities(for: ["not-a-team"])
        #expect(entities.isEmpty)
    }

    @Test("Teams unfollowed since the last indexing are removed from Spotlight")
    func removedIDs() {
        #expect(TeamSpotlightIndexer.removedIDs(indexed: [chiefsID, royalsID], current: [royalsID]) == [chiefsID])
        #expect(TeamSpotlightIndexer.removedIDs(indexed: [], current: [chiefsID]).isEmpty)
        #expect(TeamSpotlightIndexer.removedIDs(indexed: [chiefsID], current: [chiefsID]).isEmpty)
    }
}
