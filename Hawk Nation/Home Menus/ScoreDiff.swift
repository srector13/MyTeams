//
//  ScoreDiff.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// The score-alert event model: plain values in, events out. Nothing here
// knows about the network, the scoreboard center or UserNotifications, so it
// builds and tests without them; beyond plain values it reads only the
// league's period rules (`LeagueDescriptor`), to name periods.
// `ScoreAlertEngine` feeds it.

/// One game as a score alert sees it. Codable, so the engine's last look
/// at each game outlives the launch (`ScoreAlertMemory`).
struct ScoreSnapshot: Equatable, Sendable, Codable {
    enum State: Equatable, Sendable, Codable {
        /// Not started, or called off.
        case scheduled
        case inProgress
        /// Played out.
        case final
    }

    var homeName: String
    var awayName: String
    var homeScore: Int
    var awayScore: Int
    /// The quarter, half, period or inning; 0 before the start.
    var period: Int
    var state: State
    /// How the game's league names its periods; plain ordinals where the
    /// league is not known.
    var periodNaming: PeriodNaming = .ordinal

    /// Where the game stands, by its league's rules (A-11): "3rd Period",
    /// "OT", "Extra Time", "7th"; "Live" under way before the board gives a
    /// period, "Pregame" before the start, "Final" once played out. The
    /// alerts' summary and the Live Activity's stage both read it.
    var stageLabel: String {
        switch state {
        case .scheduled: return "Pregame"
        case .final: return "Final"
        case .inProgress: return period > 0 ? periodNaming.label(period) : "Live"
        }
    }

    /// "Away 3 – Home 2 (2nd Half)", or "(Final)" once played out.
    var summary: String {
        "\(awayName) \(awayScore) – \(homeName) \(homeScore) (\(stageLabel))"
    }

    /// "1st", "2nd", "3rd", "4th", … "11th", "12th", "13th", "21st".
    static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}

/// How a league names its periods in alerts and on the Live Activity:
/// "1st Half", "3rd Quarter", "2nd Period"; past regulation, "OT", "2OT" …,
/// or soccer's "Extra Time" and "Penalties"; and plain ordinals ("7th")
/// where periods go unnamed, as baseball's innings do.
///
/// A copy of `LeagueDescriptor.liveCardPeriodLabel` (`Linescore.swift`), the
/// schedule cards' label, kept here rather than moved so the two files can
/// change apart; keep them in step. Unlike the card's, it never reads blank:
/// an unnamed period falls back to its ordinal.
///
/// Baseball's top or bottom of the inning is not on `ScoreboardGame` (the
/// board's `status.type.shortDetail` is not parsed), so innings read "7th".
struct PeriodNaming: Equatable, Sendable {
    var style: LeagueDescriptor.PeriodStyle
    /// Whether the periods past regulation are extra time and penalties
    /// rather than overtimes.
    var hasExtraTime: Bool

    /// Plain ordinals for every period: for a game whose league is unknown.
    static let ordinal = PeriodNaming(style: .unnamed, hasExtraTime: false)

    init(style: LeagueDescriptor.PeriodStyle, hasExtraTime: Bool) {
        self.style = style
        self.hasExtraTime = hasExtraTime
    }

    /// The naming of `league`'s games. A cup with no descriptor of its own
    /// (`"eng.fa"`) has unnamed periods, so its sport's usual ones stand in:
    /// soccer's halves, hockey's periods, football's quarters. Basketball
    /// plays halves in college and quarters elsewhere, so it keeps ordinals.
    init(league: LeagueID) {
        let descriptor = league.descriptor
        var style = descriptor.periodStyle
        if style == .unnamed {
            switch descriptor.kind {
            case .soccer: style = .halves
            case .hockey: style = .periods
            case .football: style = .quarters
            default: break
            }
        }
        self.init(style: style, hasExtraTime: descriptor.kind == .soccer)
    }

    /// The regulation periods' names, in order; empty where they go unnamed.
    private var regulationNames: [String] {
        switch style {
        case .halves: ["1st Half", "2nd Half"]
        case .quarters: ["1st Quarter", "2nd Quarter", "3rd Quarter", "4th Quarter"]
        case .periods: ["1st Period", "2nd Period", "3rd Period"]
        case .unnamed: []
        }
    }

    /// The name of period `period`, counted from 1.
    func label(_ period: Int) -> String {
        let names = regulationNames
        if period >= 1 && period <= names.count {
            return names[period - 1]
        }
        if !names.isEmpty && period > names.count {
            let extra = period - names.count
            if hasExtraTime {
                return extra <= 2 ? "Extra Time" : "Penalties"
            }
            return extra <= 1 ? "OT" : "\(extra)OT"
        }
        return ScoreSnapshot.ordinal(period)
    }
}

// Coded by hand: `LeagueDescriptor.PeriodStyle` is not Codable, and is
// written here by name.
extension PeriodNaming: Codable {
    private enum CodingKeys: String, CodingKey {
        case style
        case hasExtraTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let style: LeagueDescriptor.PeriodStyle
        switch try container.decode(String.self, forKey: .style) {
        case "halves": style = .halves
        case "quarters": style = .quarters
        case "periods": style = .periods
        default: style = .unnamed
        }
        self.init(style: style, hasExtraTime: try container.decode(Bool.self, forKey: .hasExtraTime))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let name: String
        switch style {
        case .halves: name = "halves"
        case .quarters: name = "quarters"
        case .periods: name = "periods"
        case .unnamed: name = "unnamed"
        }
        try container.encode(name, forKey: .style)
        try container.encode(hasExtraTime, forKey: .hasExtraTime)
    }
}

/// Something worth an alert, between two looks at a game.
enum ScoreEvent: Equatable, Sendable {
    case gameStart(gameID: String, snapshot: ScoreSnapshot)
    case scoreChange(gameID: String, previous: ScoreSnapshot, snapshot: ScoreSnapshot)
    /// `period` is the one that ended; `snapshot` is the game now.
    case periodEnd(gameID: String, period: Int, snapshot: ScoreSnapshot)
    case final(gameID: String, snapshot: ScoreSnapshot)

    var gameID: String {
        switch self {
        case .gameStart(let gameID, _),
             .scoreChange(let gameID, _, _),
             .periodEnd(let gameID, _, _),
             .final(let gameID, _):
            return gameID
        }
    }

    /// The game as of the event.
    var snapshot: ScoreSnapshot {
        switch self {
        case .gameStart(_, let snapshot),
             .scoreChange(_, _, let snapshot),
             .periodEnd(_, _, let snapshot),
             .final(_, let snapshot):
            return snapshot
        }
    }

    var isFinal: Bool {
        if case .final = self { return true }
        return false
    }

    /// The alert's title line.
    var title: String {
        switch self {
        case .gameStart: return "Game started"
        case .scoreChange: return "Score update"
        case .periodEnd(_, let period, let snapshot): return "End of \(snapshot.periodNaming.label(period))"
        case .final: return "Final"
        }
    }
}

enum ScoreDiff {
    /// The events between two looks at the same games, keyed by game id, in
    /// game id order.
    ///
    /// - A game first seen, in whatever state, says nothing: its look is only
    ///   the seed for the next. The engine keeps its looks across launches
    ///   for a day (`ScoreAlertMemory`), so a launch into the background
    ///   (R-1) diffs against the last look rather than seeding again; a game
    ///   it has never seen, or not for a day, is first seen, and one already
    ///   under way is no more news than a final missed. Only a game seen
    ///   before its start and then under way starts.
    /// - A game that drops off the board says nothing.
    /// - Going final reports only `final`, whatever else changed with it.
    /// - Under way, a new score and a new period each report; the score
    ///   comes first.
    static func diff(previous: [String: ScoreSnapshot], current: [String: ScoreSnapshot]) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        for gameID in current.keys.sorted() {
            guard let now = current[gameID], let before = previous[gameID] else { continue }

            switch (before.state, now.state) {
            case (.scheduled, .inProgress):
                events.append(.gameStart(gameID: gameID, snapshot: now))
            case (.scheduled, .final), (.inProgress, .final):
                events.append(.final(gameID: gameID, snapshot: now))
            case (.inProgress, .inProgress):
                if before.homeScore != now.homeScore || before.awayScore != now.awayScore {
                    events.append(.scoreChange(gameID: gameID, previous: before, snapshot: now))
                }
                if now.period > before.period {
                    events.append(.periodEnd(gameID: gameID, period: before.period, snapshot: now))
                }
            default:
                break
            }
        }
        return events
    }
}

/// At most one alert per game per `window`, except `final`, which always
/// goes. The clock is the caller's, so tests pass their own dates.
///
/// An event inside its game's window is held, not dropped (A-12): the
/// game's snapshot has already moved past it, so a dropped goal would never
/// be told. Each game holds one event, the latest, coalesced with any held
/// before it (`coalesce`), and it goes out on the first look past the
/// window, folded into that look's own news for the game if there is any.
/// A final carries the latest score, so it clears whatever its game held.
struct ScoreAlertDebounce: Equatable, Sendable {
    var window: TimeInterval
    /// When each game last had an alert posted.
    private(set) var lastPosted: [String: Date] = [:]
    /// The event each game is holding until its window ends, by game id.
    private(set) var held: [String: ScoreEvent] = [:]

    /// - Parameter lastPosted: when each game last had an alert posted, as
    ///   kept from an earlier launch (`ScoreAlertMemory`), so a relaunch
    ///   does not reopen a game's window early.
    init(window: TimeInterval = 120, lastPosted: [String: Date] = [:]) {
        self.window = window
        self.lastPosted = lastPosted
    }

    /// Whether `event` may be posted at `now`; if so, records it as posted.
    /// One that may not is held (`held`).
    mutating func admit(_ event: ScoreEvent, at now: Date) -> Bool {
        admitting(event, at: now) != nil
    }

    /// What to post for `event` at `now`: the event, coalesced with
    /// whatever its game was holding, recorded as posted; or `nil` while
    /// the game's window is open, the event held in its place.
    mutating func admitting(_ event: ScoreEvent, at now: Date) -> ScoreEvent? {
        let gameID = event.gameID
        if event.isFinal {
            held[gameID] = nil
            lastPosted[gameID] = now
            return event
        }
        let coalesced = Self.coalesce(held[gameID], with: event)
        if let last = lastPosted[gameID], now.timeIntervalSince(last) < window {
            held[gameID] = coalesced
            return nil
        }
        held[gameID] = nil
        lastPosted[gameID] = now
        return coalesced
    }

    /// The held events whose window has ended by `now`, in game id order,
    /// recorded as posted. Games in `except` keep holding: their news in
    /// the same look picks the held event up (`admitting`).
    mutating func release(at now: Date, except: Set<String> = []) -> [ScoreEvent] {
        var released: [ScoreEvent] = []
        for gameID in held.keys.sorted() where !except.contains(gameID) {
            guard let event = held[gameID] else { continue }
            if let last = lastPosted[gameID], now.timeIntervalSince(last) < window {
                continue
            }
            held[gameID] = nil
            lastPosted[gameID] = now
            released.append(event)
        }
        return released
    }

    /// When the first held event's window ends; `nil` with nothing held.
    var nextRelease: Date? {
        held.keys.compactMap { lastPosted[$0]?.addingTimeInterval(window) }.min()
    }

    /// The events to post at `now`, in order: those held whose window has
    /// ended, then `events`, holding those debounced.
    mutating func admit(_ events: [ScoreEvent], at now: Date) -> [ScoreEvent] {
        var admitted = release(at: now, except: Set(events.map(\.gameID)))
        for event in events {
            if let posted = admitting(event, at: now) {
                admitted.append(posted)
            }
        }
        return admitted
    }

    /// One event standing for `held` and the later `event`: the later one,
    /// as it carries the game now. A held score update stays a score
    /// update, from the score last told to the score now, so a period's end
    /// after it does not hide that the score moved.
    static func coalesce(_ held: ScoreEvent?, with event: ScoreEvent) -> ScoreEvent {
        guard let held, held.gameID == event.gameID, !event.isFinal else { return event }
        if case .scoreChange(let gameID, let previous, _) = held {
            return .scoreChange(gameID: gameID, previous: previous, snapshot: event.snapshot)
        }
        return event
    }
}
