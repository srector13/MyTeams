//
//  CalendarEventBuilderTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// What a game becomes on the calendar (`CalendarEventBuilder`, R-7): its
/// title, length by sport, venue, notes and marker, and which games a
/// season sync writes.
@Suite("Calendar events")
struct CalendarEventBuilderTests {
    private let chiefs = TeamRef(
        league: .nfl, espnID: "12",
        displayName: "Kansas City Chiefs", shortName: "Chiefs", abbreviation: "KC", location: "Kansas City",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )

    private let arsenal = TeamRef(
        league: .premierLeague, espnID: "359",
        displayName: "Arsenal", shortName: "Arsenal", abbreviation: "ARS", location: "London",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )

    /// Sunday, Oct 4, 2026, 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_115_200)

    /// Wednesday, Oct 7, 2026, 00:15 UTC: a Tuesday-night kickoff in the
    /// US, nowhere near the midnight-Eastern placeholder.
    static let kickoff = Date(timeIntervalSince1970: 1_791_332_100)

    private func game(
        eventID: String = "401",
        team: String = "Chiefs",
        opponent: String = "Raiders",
        start: Date = CalendarEventBuilderTests.kickoff,
        date: String = "Oct 07, 2026",
        channel: String = "ESPN",
        location: String = "Arrowhead Stadium",
        completed: Bool = false,
        cancelled: Bool = false,
        postponed: Bool = false,
        competition: LeagueID? = nil
    ) -> Game {
        Game(
            eventID: eventID, team: team, opponent: opponent, score: "", opponentScore: "",
            time: "", date: date, dateAsDate: start, opponentLogo: "", channel: channel,
            location: location, gameHome: true, gameID: eventID, pointer: 0,
            gameWin: false, completed: completed, competitionName: "",
            cancelled: cancelled, postponed: postponed, gameClock: "",
            gamePeriod: "", gameHalftime: false, competition: competition
        )
    }

    // MARK: One game

    @Test("The title is the team and opponent as the card names them")
    func title() {
        #expect(CalendarEventBuilder.draft(for: game(), team: chiefs).title == "Chiefs vs Raiders")
        // A team the event leaves unnamed falls back to its short name; an
        // unnamed opponent reads TBD, as on the card.
        #expect(CalendarEventBuilder.title(for: game(team: "", opponent: ""), team: chiefs) == "Chiefs vs TBD")
    }

    @Test("A game lasts as long as its sport usually takes")
    func durationBySport() {
        let hour: TimeInterval = 3_600
        #expect(CalendarEventBuilder.duration(for: .soccer) == 2 * hour)
        #expect(CalendarEventBuilder.duration(for: .football) == 3.5 * hour)
        #expect(CalendarEventBuilder.duration(for: .basketball) == 2.5 * hour)
        #expect(CalendarEventBuilder.duration(for: .baseball) == 3 * hour)
        #expect(CalendarEventBuilder.duration(for: .hockey) == 2.5 * hour)

        let nfl = CalendarEventBuilder.draft(for: game(), team: chiefs)
        #expect(nfl.start == Self.kickoff)
        #expect(nfl.end.timeIntervalSince(nfl.start) == 3.5 * hour)
        let epl = CalendarEventBuilder.draft(for: game(), team: arsenal)
        #expect(epl.end.timeIntervalSince(epl.start) == 2 * hour)
    }

    @Test("The venue is the location, and a blank one is left out")
    func location() {
        #expect(CalendarEventBuilder.draft(for: game(), team: chiefs).location == "Arrowhead Stadium")
        #expect(CalendarEventBuilder.draft(for: game(location: "  "), team: chiefs).location == nil)
    }

    @Test("The notes carry the channel, the game's link and the marker")
    func notes() throws {
        let notes = CalendarEventBuilder.draft(for: game(), team: chiefs).notes
        let lines = notes.components(separatedBy: "\n")
        #expect(lines.first == "TV: ESPN")
        #expect(lines.last == "myTeams-event:401")

        // The link is R-3's own, opening the game's sheet over the team.
        let link = try #require(CalendarEventBuilder.deepLink(for: game(), team: chiefs))
        #expect(lines.contains("Open in myTeams: \(link.absoluteString)"))
        let target = try #require(WidgetDeepLink.game(from: link))
        #expect(target == WidgetDeepLink.GameTarget(league: .nfl, eventID: "401", teamID: chiefs.id))
    }

    @Test("A feed with no channel leaves the TV line out")
    func notesWithoutChannel() {
        let notes = CalendarEventBuilder.draft(for: game(channel: "TBD"), team: chiefs).notes
        #expect(!notes.contains("TV:"))
        #expect(!notes.contains("TBD"))
    }

    @Test("A cup tie's link names the cup's board")
    func cupLink() throws {
        let cup = LeagueID.soccer("uefa.champions")
        let link = try #require(CalendarEventBuilder.deepLink(for: game(competition: cup), team: arsenal))
        #expect(WidgetDeepLink.game(from: link)?.league == cup)
        #expect(WidgetDeepLink.game(from: link)?.teamID == arsenal.id)
    }

    // MARK: Marker

    @Test("The marker reads back as the event id it was written for")
    func markerRoundTrip() {
        let notes = CalendarEventBuilder.draft(for: game(eventID: "401873006"), team: chiefs).notes
        #expect(CalendarEventBuilder.eventID(inNotes: notes) == "401873006")
        #expect(CalendarEventBuilder.eventID(inNotes: "Bring snacks\n  myTeams-event:77  \nmore") == "77")
        #expect(CalendarEventBuilder.eventID(inNotes: "Bring snacks") == nil)
        #expect(CalendarEventBuilder.eventID(inNotes: "myTeams-event:") == nil)
        #expect(CalendarEventBuilder.eventID(inNotes: nil) == nil)
    }

    @Test("A sync adds a new game, moves a rescheduled one and leaves the rest")
    func syncAction() {
        let draft = CalendarEventBuilder.draft(for: game(), team: chiefs)
        #expect(CalendarEventBuilder.action(for: draft, existing: nil) == .add)
        #expect(CalendarEventBuilder.action(for: draft, existing: draft.snapshot) == .unchanged)

        var moved = draft.snapshot
        moved.start = draft.start.addingTimeInterval(-86_400)
        moved.end = draft.end.addingTimeInterval(-86_400)
        #expect(CalendarEventBuilder.action(for: draft, existing: moved) == .update)

        var retitled = draft.snapshot
        retitled.notes = "myTeams-event:401"
        #expect(CalendarEventBuilder.action(for: draft, existing: retitled) == .update)
    }

    @Test("The season calendar is named for the team")
    func calendarTitle() {
        #expect(CalendarEventBuilder.calendarTitle(for: chiefs) == "myTeams – Kansas City Chiefs")
    }

    // MARK: TBD and the season

    @Test("A missing date or ESPN's midnight-Eastern placeholder is TBD")
    func tbd() {
        #expect(!CalendarEventBuilder.isTBD(game()))
        #expect(CalendarEventBuilder.isTBD(game(date: "")))
        // 2027-01-03T05:00Z and 2026-10-10T04:00Z: midnight in New York
        // in winter and in summer.
        #expect(CalendarEventBuilder.isTBD(game(start: Date(timeIntervalSince1970: 1_798_952_400))))
        #expect(CalendarEventBuilder.isTBD(game(start: Date(timeIntervalSince1970: 1_791_604_800))))
        #expect(CalendarEventBuilder.draft(for: game(date: ""), team: chiefs).isTBD)
    }

    @Test("A season sync writes only games still to come with a real time")
    func seasonFilter() {
        let games = [
            game(eventID: "1"),
            game(eventID: "2", completed: true),
            game(eventID: "3", cancelled: true),
            game(eventID: "4", postponed: true),
            // Under way.
            game(eventID: "5", start: Self.now.addingTimeInterval(-3_600)),
            game(eventID: "6", date: ""),
            game(eventID: ""),
            game(eventID: "8", start: Self.kickoff.addingTimeInterval(7 * 86_400)),
        ]
        let drafts = CalendarEventBuilder.seasonDrafts(for: games, team: chiefs, now: Self.now)
        #expect(drafts.map(\.eventID) == ["1", "8"])
    }

    @Test("The Chiefs fixture: twelve games to add, the live one and the TBD playoffs left out")
    func seasonFixture() throws {
        let games = parseSchedule(from: try Fixture.json("chiefs_schedule"), team: chiefs)
        // 2026-09-27 18:00 UTC, during the game at Miami (401872952).
        let now = Date(timeIntervalSince1970: 1_790_532_000)
        let drafts = CalendarEventBuilder.seasonDrafts(for: games, team: chiefs, now: now)

        #expect(drafts.count == 12)
        #expect(drafts.first?.eventID == "401872976")
        #expect(drafts.last?.eventID == "401873153")
        #expect(!drafts.contains { $0.eventID == "401872952" })
        // Weeks 17 and 18, whose kickoffs ESPN hasn't set (timeValid false).
        #expect(!drafts.contains { $0.eventID == "401873158" || $0.eventID == "401873178" })

        let raiders = try #require(drafts.first)
        #expect(raiders.title == "Chiefs vs Raiders")
        #expect(raiders.location == "Allegiant Stadium")
        #expect(raiders.notes.hasPrefix("TV: CBS\n"))
        #expect(CalendarEventBuilder.eventID(inNotes: raiders.notes) == "401872976")
    }
}
