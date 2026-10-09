//
//  CalendarEventBuilder.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// One game as a calendar event, before EventKit sees it (R-7).
///
/// Plain values, so the tests can check what a game becomes without an
/// event store; `CalendarWriter` copies them onto an `EKEvent`.
struct EventDraft: Identifiable, Equatable, Sendable {
    /// ESPN's event id, `Game.eventID`. The key a later sync finds the
    /// event by, through the marker in `notes`.
    var eventID: String
    /// "Chiefs vs Bills".
    var title: String
    var start: Date
    var end: Date
    /// The venue, or `nil` where the feed named none.
    var location: String?
    /// The channel, a link back to the game in the app, and the marker
    /// line, one to a line.
    var notes: String
    /// Whether the feed has no real start time for the game yet. A season
    /// sync leaves such games out rather than writing a guessed time.
    var isTBD: Bool

    var id: String { eventID }

    /// The fields a sync compares to decide whether a stored event has
    /// moved or changed.
    var snapshot: CalendarEventBuilder.Snapshot {
        CalendarEventBuilder.Snapshot(title: title, start: start, end: end, location: location, notes: notes)
    }
}

/// Turns schedule games into calendar events (R-7): the title, start and a
/// length by sport, the venue, and notes holding the channel, a
/// `myteams://game/` link and the event id that a season sync finds the
/// event by again.
///
/// Pure, like `GameCardContent`, whose rules it borrows for the channel,
/// the venue and whether a game is still to come.
enum CalendarEventBuilder {
    /// Starts the notes line that names a game's ESPN event id. A season
    /// sync reads it back to find the events it wrote before, so a
    /// rescheduled game is moved rather than added twice. EventKit's own
    /// `url` field would do, but some calendar accounts drop it; notes
    /// survive every account.
    static let markerPrefix = "myTeams-event:"

    /// What a sync compares between a game's draft and the event already
    /// in the calendar.
    struct Snapshot: Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var location: String?
        var notes: String
    }

    /// What a sync does with one game.
    enum SyncAction: Equatable, Sendable {
        /// No event carries the game's marker yet.
        case add
        /// An event does, but the game has moved or its details changed.
        case update
        /// The event already says what the draft says.
        case unchanged
    }

    /// How long to block out for a game, by sport: the playing time plus
    /// breaks and the usual stoppages, rounded to the half hour. A guess,
    /// but a better one than the hour a calendar defaults to.
    static func duration(for kind: SportKind) -> TimeInterval {
        let hours: Double
        switch kind {
        // Two 45-minute halves, the interval and added time.
        case .soccer: hours = 2
        // Four quarters of stop-start play, and halftime.
        case .football: hours = 3.5
        case .basketball: hours = 2.5
        case .baseball: hours = 3
        // Three periods and two intermissions.
        case .hockey: hours = 2.5
        case .other: hours = 3
        }
        return hours * 60 * 60
    }

    /// The draft for one of `team`'s games.
    static func draft(for game: Game, team: TeamRef) -> EventDraft {
        let start = game.dateAsDate
        return EventDraft(
            eventID: game.eventID,
            title: title(for: game, team: team),
            start: start,
            end: start.addingTimeInterval(duration(for: team.league.descriptor.kind)),
            location: GameCardContent.venue(of: game),
            notes: notes(for: game, team: team),
            isTBD: isTBD(game)
        )
    }

    /// "Chiefs vs Bills": the team and opponent as the schedule card names
    /// them, the team falling back to its short name where the event leaves
    /// it out, and an unnamed opponent reading "TBD", as on the card.
    static func title(for game: Game, team: TeamRef) -> String {
        let named = game.team.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamName = named.isEmpty ? team.shortName : named
        let opponent = game.opponent.isEmpty ? "TBD" : game.opponent
        return "\(teamName) vs \(opponent)"
    }

    /// The channel, when the feed named one; the link that opens the game's
    /// sheet in the app; and the marker. One to a line, the marker last.
    static func notes(for game: Game, team: TeamRef) -> String {
        var lines: [String] = []
        if let broadcast = GameCardContent.broadcast(of: game) {
            lines.append("TV: \(broadcast)")
        }
        if let link = deepLink(for: game, team: team) {
            lines.append("Open in myTeams: \(link.absoluteString)")
        }
        if !game.eventID.isEmpty {
            lines.append(marker(for: game.eventID))
        }
        return lines.joined(separator: "\n")
    }

    /// The same `myteams://game/` link the score alerts and the Live
    /// Activity open (R-3), naming the competition whose board lists the
    /// game: the cup for a cup tie, else the team's league. `nil` for an
    /// event id the link can't hold, such as the parser's stand-in for an
    /// event without one.
    static func deepLink(for game: Game, team: TeamRef) -> URL? {
        WidgetDeepLink.url(forGame: game.eventID, league: game.competition ?? team.league, teamID: team.id)
    }

    /// The notes line naming `eventID`: `"myTeams-event:401"`.
    static func marker(for eventID: String) -> String {
        "\(markerPrefix)\(eventID)"
    }

    /// The event id a marker line in `notes` names, or `nil` without one.
    static func eventID(inNotes notes: String?) -> String? {
        guard let notes else { return nil }
        for line in notes.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(markerPrefix) {
                let id = String(trimmed.dropFirst(markerPrefix.count))
                return id.isEmpty ? nil : id
            }
        }
        return nil
    }

    /// The zone ESPN's placeholder times are midnight in.
    private static let placeholderCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    /// Whether the game has no real start time yet. The schedule feed
    /// gives an undecided kickoff (a college game awaiting television, a
    /// playoff date) as midnight US Eastern, "04:00Z" or "05:00Z", and
    /// flags it `timeValid: false`, which the parser doesn't keep; the card
    /// reads "TBD" only when the date is missing altogether. Midnight
    /// Eastern to the minute stands for the flag: a game that truly starts
    /// then is rare enough that leaving it out of a season sync, where the
    /// reader can still add it by hand, is the lesser harm than a season of
    /// midnight events.
    static func isTBD(_ game: Game) -> Bool {
        if game.date.isEmpty { return true }
        let time = placeholderCalendar.dateComponents([.hour, .minute], from: game.dateAsDate)
        return time.hour == 0 && time.minute == 0
    }

    /// Whether a game can go on the calendar from its card: one still to
    /// come, by the card's own rule, so not played, under way, cancelled or
    /// postponed.
    static func isUpcoming(_ game: Game, now: Date = Date()) -> Bool {
        GameCardContent.phase(of: game, now: now) == .upcoming
    }

    /// The drafts a season sync writes: every game still to come that has a
    /// real start time and an event id to find it by, in schedule order.
    static func seasonDrafts(for games: [Game], team: TeamRef, now: Date = Date()) -> [EventDraft] {
        games
            .filter { isUpcoming($0, now: now) && !$0.eventID.isEmpty }
            .map { draft(for: $0, team: team) }
            .filter { !$0.isTBD }
    }

    /// The name of the calendar a season sync writes `team`'s games to:
    /// "myTeams – Kansas City Chiefs". Found by this title on a later sync.
    static func calendarTitle(for team: TeamRef) -> String {
        "myTeams – \(team.displayName)"
    }

    /// What to do with `draft` given the event, if any, that already
    /// carries its marker.
    static func action(for draft: EventDraft, existing: Snapshot?) -> SyncAction {
        guard let existing else { return .add }
        return existing == draft.snapshot ? .unchanged : .update
    }
}
