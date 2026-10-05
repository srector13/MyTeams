//
//  WidgetScoreboardSnapshot.swift
//  myTeams
//
//  Created by Stephen Rector on 10/5/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// A favorite's game under way or just finished, as the app last saw it on a
/// live scoreboard, for the widget (C-5).
///
/// The widget cannot poll the scoreboards itself, so the app writes these to
/// the App Group's defaults (`WidgetScoreboardCodec`) on its own poll
/// cadence (`WidgetScoreboardWriter`), and the widget reads them back when it
/// builds a timeline. Compiled into both targets, like `LogoStore`.
struct WidgetScoreboardSnapshot: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case inProgress
        case final
    }

    /// The competition id, which is the schedule's `Game.gameID`.
    var gameID: String
    /// The board the game was on (`LeagueID.path`): the favorite's league, or
    /// one of its cups.
    var league: String
    /// The favorite the game was seen for: its `TeamRef.id`, in its home
    /// league.
    var teamID: String
    /// Each side's ESPN team id.
    var homeTeamID: String
    var awayTeamID: String
    var homeName: String
    var awayName: String
    var homeScore: Int
    var awayScore: Int
    var state: State
    /// `status.displayClock`, e.g. `"12:34"` or `"67'"`; may be empty.
    var clock: String
    /// The quarter, half, period or inning.
    var period: Int
    /// The game's scheduled start, when the board gave one.
    var gameDate: Date?
    /// When the app wrote this look at the game.
    var updated: Date

    /// Whether `espnID` plays at home in this game.
    func isHome(_ espnID: String) -> Bool { homeTeamID == espnID }

    /// The other side's name, as `espnID` sees the game.
    func opponentName(of espnID: String) -> String {
        isHome(espnID) ? awayName : homeName
    }

    /// The other side's ESPN id, as `espnID` sees the game.
    func opponentID(of espnID: String) -> String {
        isHome(espnID) ? awayTeamID : homeTeamID
    }

    /// The score with `espnID`'s side first, e.g. `"2–1"`.
    func score(for espnID: String) -> String {
        isHome(espnID) ? "\(homeScore)–\(awayScore)" : "\(awayScore)–\(homeScore)"
    }

    /// "Final", or "Live" with the clock when the sport keeps one.
    var statusText: String {
        switch state {
        case .final:
            return "Final"
        case .inProgress:
            let clock = clock.trimmingCharacters(in: .whitespaces)
            return clock.isEmpty || clock == "0:00" ? "Live" : "Live · \(clock)"
        }
    }
}

/// Reads and writes the snapshots in the App Group's defaults.
enum WidgetScoreboardCodec {
    static let defaultsKey = "widgetScoreboardSnapshots.v1"

    /// How long a snapshot stays good. The app polls once a minute while it
    /// is open and not at all in the background, so an older one describes a
    /// game nobody has looked at since.
    static let staleAfter: TimeInterval = 30 * 60

    static func encode(_ snapshots: [WidgetScoreboardSnapshot]) -> Data? {
        try? JSONEncoder().encode(snapshots)
    }

    /// The snapshots in `data`; none when it is missing or unreadable.
    static func decode(_ data: Data?) -> [WidgetScoreboardSnapshot] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([WidgetScoreboardSnapshot].self, from: data)) ?? []
    }

    static func write(_ snapshots: [WidgetScoreboardSnapshot], to defaults: UserDefaults = SharedPaths.defaults) {
        guard let data = encode(snapshots) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func read(from defaults: UserDefaults = SharedPaths.defaults) -> [WidgetScoreboardSnapshot] {
        decode(defaults.data(forKey: defaultsKey))
    }

    /// Whether `snapshot` was written within `staleAfter` of `now`. One
    /// stamped in the future (a clock change) is not trusted either.
    static func isFresh(_ snapshot: WidgetScoreboardSnapshot, now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.updated)
        return age <= staleAfter && age >= -60
    }
}

/// The game a widget features: the one under way, else the last result,
/// else the next game (C-5).
enum WidgetFeaturedGame: Hashable, Sendable {
    /// A game under way, from a fresh snapshot.
    case live(WidgetScoreboardSnapshot)
    /// A game finished today, from a fresh snapshot.
    case result(WidgetScoreboardSnapshot)
    /// A game finished today, from the schedule, when no snapshot has it.
    case scheduleResult(Game)
    /// The next game not yet started.
    case next(Game)
    /// Nothing under way, finished today or still to play.
    case none

    /// Picks the featured game for `teamID` from the app's snapshots and the
    /// team's schedule.
    ///
    /// Snapshots for other teams, and stale ones, are ignored, so without a
    /// fresh snapshot this is the schedule alone: today's last finished game,
    /// else the earliest game not yet started (and not called off).
    static func pick(
        teamID: String,
        snapshots: [WidgetScoreboardSnapshot],
        schedule: [Game],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> WidgetFeaturedGame {
        let fresh = snapshots.filter { $0.teamID == teamID && WidgetScoreboardCodec.isFresh($0, now: now) }
        let start = { (snapshot: WidgetScoreboardSnapshot) in snapshot.gameDate ?? snapshot.updated }

        if let live = fresh.filter({ $0.state == .inProgress }).max(by: { start($0) < start($1) }) {
            return .live(live)
        }

        let snapshotResult = fresh
            .filter { $0.state == .final && calendar.isDate(start($0), inSameDayAs: now) }
            .max { start($0) < start($1) }
        let scheduleResult = schedule
            .filter {
                $0.completed && !$0.cancelled && !$0.postponed
                    && $0.dateAsDate <= now && calendar.isDate($0.dateAsDate, inSameDayAs: now)
            }
            .max { $0.dateAsDate < $1.dateAsDate }
        switch (snapshotResult, scheduleResult) {
        case let (snapshot?, game?):
            // The board's look wins for the same game, or a later one.
            return game.dateAsDate > start(snapshot) && game.gameID != snapshot.gameID
                ? .scheduleResult(game)
                : .result(snapshot)
        case let (snapshot?, nil):
            return .result(snapshot)
        case let (nil, game?):
            return .scheduleResult(game)
        case (nil, nil):
            break
        }

        // A fixture the app counts as played (cancelled or postponed) is
        // never offered as the next game.
        if let next = schedule
            .filter({ $0.dateAsDate >= now && !$0.cancelled && !$0.postponed })
            .min(by: { $0.dateAsDate < $1.dateAsDate }) {
            return .next(next)
        }
        return .none
    }
}
