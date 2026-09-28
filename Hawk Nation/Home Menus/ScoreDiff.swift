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
// builds and tests on any Swift toolchain. `ScoreAlertEngine` feeds it.

/// One game as a score alert sees it.
struct ScoreSnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
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

    /// "Away 3 – Home 2 (2nd)", or "(Final)" once played out.
    var summary: String {
        let stage = state == .final ? "Final" : ScoreSnapshot.ordinal(period)
        return "\(awayName) \(awayScore) – \(homeName) \(homeScore) (\(stage))"
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
        case .periodEnd(_, let period, _): return "End of \(ScoreSnapshot.ordinal(period))"
        case .final: return "Final"
        }
    }
}

enum ScoreDiff {
    /// The events between two looks at the same games, keyed by game id, in
    /// game id order.
    ///
    /// - A game first seen under way starts; one first seen before its start
    ///   or already over says nothing (a final missed is not news at launch).
    /// - A game that drops off the board says nothing.
    /// - Going final reports only `final`, whatever else changed with it.
    /// - Under way, a new score and a new period each report; the score
    ///   comes first.
    static func diff(previous: [String: ScoreSnapshot], current: [String: ScoreSnapshot]) -> [ScoreEvent] {
        var events: [ScoreEvent] = []
        for gameID in current.keys.sorted() {
            guard let now = current[gameID] else { continue }
            guard let before = previous[gameID] else {
                if now.state == .inProgress {
                    events.append(.gameStart(gameID: gameID, snapshot: now))
                }
                continue
            }

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
struct ScoreAlertDebounce: Equatable, Sendable {
    var window: TimeInterval
    /// When each game last had an alert posted.
    private(set) var lastPosted: [String: Date] = [:]

    init(window: TimeInterval = 120) {
        self.window = window
    }

    /// Whether `event` may be posted at `now`; if so, records it as posted.
    mutating func admit(_ event: ScoreEvent, at now: Date) -> Bool {
        let gameID = event.gameID
        if !event.isFinal, let last = lastPosted[gameID], now.timeIntervalSince(last) < window {
            return false
        }
        lastPosted[gameID] = now
        return true
    }

    /// The events to post at `now`, in order, dropping those debounced.
    mutating func admit(_ events: [ScoreEvent], at now: Date) -> [ScoreEvent] {
        var admitted: [ScoreEvent] = []
        for event in events where admit(event, at: now) {
            admitted.append(event)
        }
        return admitted
    }
}
