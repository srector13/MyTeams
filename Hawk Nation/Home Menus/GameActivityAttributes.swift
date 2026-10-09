//
//  GameActivityAttributes.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// A game's Live Activity, shared by the app (which starts, updates and ends
// it: `LiveActivityManager`) and the widget extension (which draws it:
// `GameLiveActivity`). Compiled into both targets.
//
// The two halves are plain Foundation values so the app's mapping from a
// scoreboard (`LiveActivityStateMapper`) builds and tests without
// ActivityKit; `GameActivityAttributes` only wraps them for the system.

/// What a game's Live Activity knows from its start: the matchup.
struct GameActivityInfo: Codable, Hashable, Sendable {
    /// The competition id, `ScoreboardGame.gameID`. One activity per game.
    var gameID: String
    /// The followed team's ESPN id.
    var teamID: String
    /// The path of the league or cup whose scoreboard lists the game,
    /// `LeagueID.path`, e.g. `"football/nfl"`.
    var league: String
    var homeName: String
    var awayName: String
    /// "Rams at Broncos".
    var matchup: String
    /// The scheduled start, when the scoreboard gives one.
    var kickoff: Date?
    /// The followed team's `TeamRef.id`, in its home league: what a tap on
    /// the activity opens (`deepLink`). Kept apart from `league`, which for a
    /// cup tie is the cup — Arsenal on the Champions League board is
    /// `"soccer/eng.1:359"`, not `"soccer/uefa.champions:359"`. `nil` for an
    /// activity started before it was kept, which opens the app as it is.
    var favoriteID: String? = nil
    /// The followed team's abbreviation, e.g. `"ARS"`, for the compact
    /// Dynamic Island's mark (B-13) where the bundled catalog doesn't know
    /// the team. `nil` when unknown at the start, or for an activity started
    /// before it was kept. Static, set once when the activity is asked for:
    /// a few bytes, well inside the payload budget.
    var favoriteAbbreviation: String? = nil
    /// The followed team's primary colour, six hex digits, for the island's
    /// keyline where the bundled catalog doesn't know the team. `nil` when
    /// the team has none.
    var favoriteColorHex: String? = nil

    /// The `myteams://team/` link to the followed team's page, if known.
    var deepLink: URL? {
        favoriteID.flatMap(WidgetDeepLink.url(forTeamID:))
    }
}

/// What a game's Live Activity shows now. Mapped from a scoreboard game by
/// `LiveActivityStateMapper`.
struct GameActivityState: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        /// Not started.
        case pending
        case live
        /// Played out.
        case ended
        /// Over without being played out: postponed, suspended, cancelled.
        case calledOff
    }

    var homeScore: Int
    var awayScore: Int
    /// The quarter, half, period or inning; 0 before the start.
    var period: Int
    /// The game clock while live, e.g. `"12:34"` or `"67'"`; empty where the
    /// sport keeps none or it has run out.
    var clock: String
    var phase: Phase
    /// The period while live, named by the league's rules (A-11): "4th
    /// Quarter", "OT", "Extra Time", "7th". Formatted by the app
    /// (`ScoreSnapshot.stageLabel`), which knows the league; `nil` from an
    /// older build, which falls back to the ordinal.
    var periodLabel: String? = nil

    /// "4th Quarter · 0:48", "OT", "Final".
    var stage: String {
        switch phase {
        case .pending: return "Pregame"
        case .ended: return "Final"
        case .calledOff: return "Called off"
        case .live:
            let period = periodLabel ?? (self.period > 0 ? ordinalString(self.period) : "Live")
            return clock.isEmpty ? period : "\(period) · \(clock)"
        }
    }
}

#if canImport(ActivityKit)
/// A followed game's Live Activity: the Lock Screen banner and the Dynamic
/// Island.
struct GameActivityAttributes: ActivityAttributes {
    typealias ContentState = GameActivityState

    var game: GameActivityInfo
}
#endif
