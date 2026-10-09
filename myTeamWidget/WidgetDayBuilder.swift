//
//  WidgetDayBuilder.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// The "My Day" widget's rows and the Lock Screen's inline line (R-9), worked
// out as plain values so the tests can drive them. UI-free; compiled into
// both targets, like `WidgetScoreboardSnapshot`, so the app's tests reach it.

/// One game in the "My Day" widget: a favorite's game under way, today's, or
/// the next one.
struct WidgetDayRow: Identifiable, Hashable, Sendable, Codable {
    enum Kind: Hashable, Sendable, Codable {
        /// Under way, from a fresh scoreboard snapshot.
        case live
        /// Today's: finished, or still to start.
        case today
        /// After today, within Home's upcoming window.
        case next
    }

    let kind: Kind
    /// The favorite the game is listed for.
    let team: TeamRef
    /// ESPN's event id, `Game.gameID`; may be empty for a schedule entry
    /// without one, which then has no link.
    let gameID: String
    /// The league or cup whose scoreboard lists the game.
    let league: LeagueID
    let opponentName: String
    /// The opponent's ESPN id, for its crest; empty when the feed names none.
    let opponentID: String
    /// The score with the favorite's side first, "21–17"; `nil` before the
    /// game starts.
    let score: String?
    /// "Live · 12:34", "Final", "7:20 PM" or "Sat 7:20 PM".
    let status: String
    /// The scheduled start, when known.
    let start: Date?
    /// The channel, when the feed names one and the game is still to watch.
    let channel: String?
    /// The game on one line, as `.accessoryInline` shows it.
    let inline: String
    let id: String

    /// The R-3 link to the game's sheet over the favorite's page.
    var url: URL? {
        WidgetDeepLink.url(forGame: gameID, league: league, teamID: team.id)
    }
}

/// Builds the "My Day" rows from the favorites' seasons and the app's
/// scoreboard snapshots: games under way first, in favorites order; then
/// today's, in start order; then the next games, padding to `maxRows`.
///
/// Reads the seasons through Home's own window (`HomeFeed`), so the widget
/// and Home agree on what is today, upcoming and a result.
struct WidgetDayBuilder: Sendable {
    /// The most rows the large widget shows.
    static let maxRows = 6

    /// The day boundaries and the zone the times are written in.
    let calendar: Calendar
    /// A team's abbreviation from its league and ESPN id, for the opponent
    /// on the inline line; `nil` when unknown, and the name stands in.
    let abbreviation: @Sendable (LeagueID, String) -> String?

    private let timeFormatter: DateFormatter
    private let dayTimeFormatter: DateFormatter

    init(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        abbreviation: @escaping @Sendable (LeagueID, String) -> String? = { TeamCatalog.team(league: $0, espnID: $1)?.abbreviation }
    ) {
        self.calendar = calendar
        self.abbreviation = abbreviation
        // The reader's own 12- or 24-hour clock (A-13), as the widget's
        // other formatters.
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = calendar.timeZone
        time.setLocalizedDateFormatFromTemplate("jmm")
        timeFormatter = time
        let dayTime = DateFormatter()
        dayTime.locale = locale
        dayTime.timeZone = calendar.timeZone
        dayTime.setLocalizedDateFormatFromTemplate("EEEjmm")
        dayTimeFormatter = dayTime
    }

    // MARK: Rows

    /// Up to `maxRows` rows for `teams`, in order: live, today, next. Each
    /// game once, however many favorites play in it. None with no
    /// favorites.
    func rows(
        teams: [TeamRef],
        seasons: [TeamRef.ID: [Game]],
        snapshots: [WidgetScoreboardSnapshot],
        now: Date
    ) -> [WidgetDayRow] {
        let games = HomeFeed.games(teams: teams, seasons: seasons)
        let fresh = snapshots.filter { WidgetScoreboardCodec.isFresh($0, now: now) }
        var used: Set<String> = []
        var rows: [WidgetDayRow] = []

        // Under way, in favorites order.
        for team in teams {
            for snapshot in fresh
            where snapshot.teamID == team.id && snapshot.state == .inProgress && !snapshot.gameID.isEmpty {
                guard used.insert(snapshot.gameID).inserted else { continue }
                let scheduled = games.first { $0.team.id == team.id && $0.game.gameID == snapshot.gameID }?.game
                rows.append(liveRow(team: team, snapshot: snapshot, scheduled: scheduled))
            }
        }

        // Today's results and fixtures, in start order.
        let today = calendar.startOfDay(for: now)
        let days = HomeFeed.upcomingDays(games, now: now, calendar: calendar)
        let results = HomeFeed.results(games, now: now)
            .filter { calendar.isDate($0.game.dateAsDate, inSameDayAs: now) }
        let fixtures = days.first { $0.date == today }?.games ?? []
        for entry in (results + fixtures).sorted(by: { $0.game.dateAsDate < $1.game.dateAsDate })
        where used.insert(entry.id).inserted {
            if entry.game.completed {
                let snapshot = fresh.first { $0.gameID == entry.game.gameID && $0.state == .final }
                rows.append(resultRow(entry, snapshot: snapshot))
            } else {
                rows.append(fixtureRow(entry, kind: .today, now: now))
            }
        }

        // The next games, after today, to fill the widget.
        for entry in days.filter({ $0.date > today }).flatMap(\.games) {
            guard rows.count < Self.maxRows else { break }
            if used.insert(entry.id).inserted {
                rows.append(fixtureRow(entry, kind: .next, now: now))
            }
        }

        return Array(rows.prefix(Self.maxRows))
    }

    private func liveRow(team: TeamRef, snapshot: WidgetScoreboardSnapshot, scheduled: Game?) -> WidgetDayRow {
        let score = snapshot.score(for: team.espnID)
        return WidgetDayRow(
            kind: .live,
            team: team,
            gameID: snapshot.gameID,
            league: LeagueID(path: snapshot.league) ?? team.league,
            opponentName: scheduled?.opponent ?? snapshot.opponentName(of: team.espnID),
            opponentID: snapshot.opponentID(of: team.espnID),
            score: score,
            status: snapshot.statusText,
            start: snapshot.gameDate ?? scheduled?.dateAsDate,
            channel: scheduled.flatMap { Self.broadcast($0.channel) },
            inline: Self.inlineLive(team: team, snapshot: snapshot),
            id: snapshot.gameID
        )
    }

    /// A game finished today. The board's score, when the app saw the game
    /// end, else the schedule's.
    private func resultRow(_ entry: HomeGame, snapshot: WidgetScoreboardSnapshot?) -> WidgetDayRow {
        let game = entry.game
        let score = snapshot?.score(for: entry.team.espnID) ?? "\(game.score)–\(game.opponentScore)"
        return WidgetDayRow(
            kind: .today,
            team: entry.team,
            gameID: game.gameID,
            league: game.competition ?? entry.team.league,
            opponentName: game.opponent,
            opponentID: game.opponentID,
            score: score,
            status: "Final",
            start: game.dateAsDate,
            channel: nil,
            inline: Self.inlineFinal(team: entry.team, score: score),
            id: entry.id
        )
    }

    private func fixtureRow(_ entry: HomeGame, kind: WidgetDayRow.Kind, now: Date) -> WidgetDayRow {
        let game = entry.game
        let league = game.competition ?? entry.team.league
        return WidgetDayRow(
            kind: kind,
            team: entry.team,
            gameID: game.gameID,
            league: league,
            opponentName: game.opponent,
            opponentID: game.opponentID,
            score: nil,
            status: startText(game.dateAsDate, now: now),
            start: game.dateAsDate,
            channel: Self.broadcast(game.channel),
            inline: inlineUpcoming(
                team: entry.team,
                opponent: opponentAbbreviation(league: league, espnID: game.opponentID, name: game.opponent),
                start: game.dateAsDate,
                now: now
            ),
            id: entry.id
        )
    }

    // MARK: Control

    /// The R-3 link to the first favorite's game under way, in favorites
    /// order, for the "Open Live Game" control; `nil` with none under way on
    /// a fresh snapshot, when the control opens Home instead.
    static func liveGameURL(
        favoriteIDs: [TeamRef.ID],
        snapshots: [WidgetScoreboardSnapshot],
        now: Date
    ) -> URL? {
        let live = snapshots.filter { $0.state == .inProgress && WidgetScoreboardCodec.isFresh($0, now: now) }
        for id in favoriteIDs {
            guard let home = TeamRef.parse(id: id)?.league else { continue }
            for snapshot in live where snapshot.teamID == id {
                let league = LeagueID(path: snapshot.league) ?? home
                if let url = WidgetDeepLink.url(forGame: snapshot.gameID, league: league, teamID: id) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: Formatting

    /// A start time: "7:20 PM" today, "Sat 7:20 PM" on another day.
    func startText(_ start: Date, now: Date) -> String {
        calendar.isDate(start, inSameDayAs: now)
            ? timeFormatter.string(from: start)
            : dayTimeFormatter.string(from: start)
    }

    /// The opponent's abbreviation, or its name when the catalog has none.
    func opponentAbbreviation(league: LeagueID, espnID: String, name: String) -> String {
        guard !espnID.isEmpty, let known = abbreviation(league, espnID), !known.isEmpty else { return name }
        return known
    }

    /// "KC vs BUF 7:20 PM", or "KC vs BUF Sat 7:20 PM" for a later day.
    func inlineUpcoming(team: TeamRef, opponent: String, start: Date, now: Date) -> String {
        "\(Self.label(of: team)) vs \(opponent) \(startText(start, now: now))"
    }

    /// "KC 21–17 Q3": the favorite, the score its side first, and the
    /// stage, when the board gives one.
    static func inlineLive(team: TeamRef, snapshot: WidgetScoreboardSnapshot) -> String {
        let stage = shortStage(period: snapshot.period, clock: snapshot.clock, league: team.league.descriptor)
        return "\(label(of: team)) \(snapshot.score(for: team.espnID)) \(stage)"
    }

    /// "KC 24–17 Final".
    static func inlineFinal(team: TeamRef, score: String) -> String {
        "\(label(of: team)) \(score) Final"
    }

    /// "KC · No upcoming games": the favorite and a tile's one-line notice.
    static func inlineNotice(team: TeamRef, message: String) -> String {
        "\(label(of: team)) · \(message)"
    }

    /// The team as the inline line names it: its abbreviation, or its short
    /// name when the feed gave none.
    static func label(of team: TeamRef) -> String {
        team.abbreviation.isEmpty ? team.shortName : team.abbreviation
    }

    /// The stage in a few characters: "Q3", "H2", "P1", "OT", an inning
    /// ("7th"), soccer's clock ("67'"), or "Live" when the board says no
    /// more.
    static func shortStage(period: Int, clock: String, league: LeagueDescriptor) -> String {
        let clock = clock.trimmingCharacters(in: .whitespaces)
        switch league.kind {
        case .soccer:
            return clock.isEmpty || clock == "0:00" ? "Live" : clock
        case .baseball:
            return period > 0 ? ordinalString(period) : "Live"
        default:
            guard period > 0 else { return "Live" }
            switch league.periodStyle {
            case .quarters: return period <= 4 ? "Q\(period)" : "OT"
            case .halves: return period <= 2 ? "H\(period)" : "OT"
            case .periods: return period <= 3 ? "P\(period)" : "OT"
            case .unnamed: return "Live"
            }
        }
    }

    /// The channel as the schedule cards show it: hidden when the feed named
    /// none (`GameCardContent.broadcast(of:)`).
    static func broadcast(_ channel: String) -> String? {
        let channel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        return channel.isEmpty || channel == "TBD" ? nil : channel
    }
}

// MARK: - Degrading

/// The Team Schedule tile's text as last built from real data, kept so a
/// reload that fails shows it, dated, rather than nothing. The crests are
/// read again from `LogoStore` when it is shown.
struct WidgetCachedGame: Codable, Hashable, Sendable {
    var teamName: String
    var gameDate: String
    var gameTime: String
    var gameChannel: String?
    var message: String?
    var inline: String
}

/// A widget's last content built from real data, and when.
struct WidgetLastGood<Value: Codable>: Codable {
    var value: Value
    var savedAt: Date
}

/// Keeps each widget's last good content in the widget process's own
/// defaults (`.standard`), never the App Group's, so it is there whether or
/// not the install's signing profile carries the group.
enum WidgetLastGoodStore {
    static let dayKey = "widgetLastGood.day"

    static func teamKey(_ id: TeamRef.ID) -> String {
        "widgetLastGood.team.\(id)"
    }

    static func save<Value: Codable>(_ value: Value, at date: Date, key: String, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(WidgetLastGood(value: value, savedAt: date)) else { return }
        defaults.set(data, forKey: key)
    }

    /// The content saved under `key`; `nil` when none was, or it no longer
    /// decodes.
    static func load<Value: Codable>(
        _ type: Value.Type,
        key: String,
        from defaults: UserDefaults = .standard
    ) -> WidgetLastGood<Value>? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetLastGood<Value>.self, from: data)
    }
}

/// Where a widget's content came from.
enum WidgetContentSource: Hashable, Sendable {
    /// Built just now from real data.
    case fresh
    /// The last good copy, built at `since`.
    case cached(since: Date)
    /// Nothing to show: the caller draws its own labelled placeholder
    /// ("Couldn't update", "Shared data unavailable").
    case placeholder
}

/// What a widget's timeline shows: real data, else the last good copy with
/// its age, else the caller's labelled placeholder; never blank, and never
/// passing a copy or a guess off as current. `note` is the caption-sized
/// line the widget draws under its content.
struct WidgetContent<Value: Codable> {
    var value: Value?
    var source: WidgetContentSource
    var note: String?

    static func plan(
        fresh: Value?,
        lastGood: WidgetLastGood<Value>?,
        shared: SharedDataStatus,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> WidgetContent {
        // Read through any store but the project's group, or none, the
        // app's live scores never reach the widget, so even fresh content
        // says which store it has.
        let sharedNote = shared.note
        if let fresh {
            return WidgetContent(value: fresh, source: .fresh, note: sharedNote)
        }
        if let lastGood {
            return WidgetContent(
                value: lastGood.value,
                source: .cached(since: lastGood.savedAt),
                note: SharedDataStatus.dataFrom(lastGood.savedAt, now: now, calendar: calendar)
            )
        }
        return WidgetContent(value: nil, source: .placeholder, note: sharedNote)
    }
}

/// Why a widget has no team to show, and what it says instead.
enum WidgetMissingTeam: Hashable, Sendable {
    /// None chosen and none followed: the widget asks for one.
    case noneFollowed
    /// None chosen, and no store the app shares through is reachable, so
    /// "Add Teams" would be wrong.
    case sharedUnavailable
    /// None chosen, and the store the widget reaches holds nothing from
    /// the app: the two are not sharing one, so the favorites can't be
    /// read and "Add Teams" would be wrong too.
    case notShared(SharedStore)

    init(shared: SharedDataStatus) {
        switch shared {
        case .available, .fallback:
            self = .noneFollowed
        case .unshared(let store):
            self = .notShared(store)
        case .unavailable:
            self = .sharedUnavailable
        }
    }

    var title: String {
        switch self {
        case .noneFollowed: return "Add Teams"
        case .sharedUnavailable: return SharedDataStatus.unavailableTitle
        case .notShared: return "No data from myTeams"
        }
    }

    var detail: String {
        switch self {
        case .noneFollowed:
            return "Open myTeams to follow a team."
        case .sharedUnavailable:
            return SharedDataStatus.repairHint
        case .notShared(let store):
            return "\(store.label) reachable but empty. Open myTeams; reinstall if this stays."
        }
    }

    /// The Lock Screen's one line.
    var inline: String {
        switch self {
        case .noneFollowed: return "Add Teams in myTeams"
        case .sharedUnavailable: return "myTeams: shared data unavailable"
        case .notShared: return "myTeams: no shared data"
        }
    }

    /// Whether the widget says why it can't read the favorites, rather than
    /// asking for one.
    var isSharingProblem: Bool { self != .noneFollowed }
}
