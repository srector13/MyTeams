//
//  SoccerLineups.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// Both sides' lineups in a soccer game: the starting eleven, then the
/// substitutes who came on, with each player's goals and cards.
///
/// Read from the summary's `rosters[]`, one per side (`homeAway`). Each
/// roster entry flags `starter` and `subbedIn`; its `plays` mark the minute
/// of a substitution; its `stats` are this game's figures, read by name
/// (`totalGoals`, `yellowCards`, `redCards`).
struct SoccerLineups: Hashable, Sendable {
    struct Player: Hashable, Sendable, Identifiable {
        var athleteID: String
        var name: String
        var jersey: String
        /// The position's abbreviation as the feed gives it (`"G"`,
        /// `"CD-L"`, `"AM"`; every substitute is `"SUB"`).
        var position: String
        var starter: Bool
        /// The minute the player came on or went off (`"68'"`), or empty.
        var substitutedAt: String
        /// Whether a starter was taken off.
        var subbedOut: Bool
        var goals: Int
        var yellowCards: Int
        var redCards: Int

        var id: String { athleteID.isEmpty ? "\(name)#\(jersey)" : athleteID }
    }

    struct Lineup: Hashable, Sendable, Identifiable {
        /// `"home"` or `"away"`.
        var homeAway: String
        var name: String
        var abbreviation: String
        /// E.g. `"4-2-3-1"`, or empty when the feed gives none.
        var formation: String
        var starters: [Player]
        /// The substitutes who came on, in the order they did. Those left
        /// on the bench are not listed.
        var substitutes: [Player]

        var id: String { homeAway }
    }

    var home: Lineup
    var away: Lineup

    /// Both sides, home first as the sheet draws them.
    var lineups: [Lineup] { [home, away] }
}

extension SoccerLineups.Player {
    /// The lineup row read as one line for VoiceOver, saying what its
    /// symbols and colours show (D-6): "Kai Havertz, number 29, 1 goal,
    /// yellow card, substituted off, minute 81". A substitute "came on".
    var accessibilitySummary: String {
        var parts = [name]
        if !jersey.isEmpty {
            parts.append("number \(jersey)")
        }
        if goals > 0 {
            parts.append(goals == 1 ? "1 goal" : "\(goals) goals")
        }
        if yellowCards > 0 {
            parts.append(yellowCards == 1 ? "yellow card" : "\(yellowCards) yellow cards")
        }
        if redCards > 0 {
            parts.append(redCards == 1 ? "red card" : "\(redCards) red cards")
        }
        if !substitutedAt.isEmpty {
            // "68'" and "90'+3'" read as "68" and "90+3", not "prime".
            let minute = substitutedAt.filter { $0 != "'" && $0 != "′" }
            parts.append("\(starter ? "substituted off" : "came on"), minute \(minute)")
        }
        return parts.joined(separator: ", ")
    }
}

extension SoccerLineups {
    /// Reads a soccer summary's lineups, or `nil` when `rosters` does not
    /// list a home and an away side with at least one starter between them
    /// (before the team sheets are out).
    init?(summary json: JSON) {
        var sides: [String: Lineup] = [:]
        for (_, roster) in json["rosters"] {
            let side = roster["homeAway"].stringValue
            guard side == "home" || side == "away" else { continue }
            sides[side] = Lineup(roster: roster)
        }
        guard let home = sides["home"], let away = sides["away"],
              !(home.starters.isEmpty && away.starters.isEmpty)
        else { return nil }
        self.home = home
        self.away = away
    }
}

extension SoccerLineups.Lineup {
    fileprivate init(roster: JSON) {
        let team = roster["team"]
        let players = roster["roster"].arrayValue.map(SoccerLineups.Player.init(entry:))

        self.homeAway = roster["homeAway"].stringValue
        self.name = team["displayName"].stringValue
        self.abbreviation = team["abbreviation"].stringValue
        self.formation = roster["formation"].stringValue
        self.starters = players.filter(\.starter)

        // Stable by minute, so two players on together keep feed order.
        let cameOn = players.enumerated().filter { !$0.element.starter && !$0.element.substitutedAt.isEmpty }
        self.substitutes = cameOn
            .sorted { (minute($0.element.substitutedAt), $0.offset) < (minute($1.element.substitutedAt), $1.offset) }
            .map(\.element)
    }
}

/// The whole minutes of a match clock such as `"68'"` or `"90'+3'"`: its
/// leading figure, or zero when there is none.
private func minute(_ clock: String) -> Int {
    Int(clock.prefix { $0.isNumber }) ?? 0
}

extension SoccerLineups.Player {
    fileprivate init(entry: JSON) {
        let athlete = entry["athlete"]
        var stats: [String: Int] = [:]
        for (_, stat) in entry["stats"] {
            let name = stat["name"].stringValue
            if stats[name] == nil {
                stats[name] = stat["value"].int ?? stat["displayValue"].intValue
            }
        }
        // The substitution's minute, whichever way the player went.
        let substitution = entry["plays"].arrayValue.first { $0["substitution"].boolValue }

        self.athleteID = athlete["id"].stringValue
        self.name = athlete["displayName"].stringValue
        self.jersey = entry["jersey"].stringValue
        self.position = entry["position", "abbreviation"].stringValue
        self.starter = entry["starter"].boolValue
        self.substitutedAt = substitution?["clock", "displayValue"].stringValue ?? ""
        self.subbedOut = entry["subbedOut"].boolValue
        // The box score draws one icon per goal or card (`ForEach(0 ..< n)`),
        // so a negative count from a malformed feed would trap and a huge one
        // would build thousands of views. Nine is more than any match sees.
        func count(_ name: String) -> Int { max(0, min(stats[name] ?? 0, 9)) }
        self.goals = count("totalGoals")
        self.yellowCards = count("yellowCards")
        self.redCards = count("redCards")
    }
}
