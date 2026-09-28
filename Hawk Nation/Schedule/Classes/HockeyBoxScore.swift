//
//  HockeyBoxScore.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// One named group of a box score's player statistics — hockey's
/// `"forwards"`, `"defenses"`, `"skaters"` and `"goalies"` — with each
/// athlete's figures keyed by name.
///
/// The feed gives every group parallel `keys`, `labels` and `descriptions`
/// arrays, and each athlete a bare `stats` array in the same order as
/// `keys`. The two are zipped here, so a reader asks for `"goals"` rather
/// than for a position that differs between groups (a goalie's list is not
/// a skater's) and could shift under it.
struct BoxscorePlayerGroup: Sendable {
    /// One athlete's line in the group.
    struct Entry: Sendable {
        /// The feed's `athlete` object: `id`, `displayName`, `jersey`,
        /// `position` ….
        var athlete: JSON
        /// The athlete's figures by key, as the feed shows them.
        var stats: [String: String]

        /// The figure for `key` as shown, or empty when the group has no
        /// such key.
        func string(_ key: String) -> String { stats[key] ?? "" }

        /// The figure for `key` as a whole number: `"-2"` is -2, and an
        /// absent or unreadable figure is zero.
        func int(_ key: String) -> Int { Int(stats[key] ?? "") ?? 0 }
    }

    /// The group's `name`, e.g. `"forwards"`.
    var name: String
    var keys: [String]
    /// Athletes with figures, in feed order. One listed with an empty
    /// `stats` array (a scratch, or a goalie who never went in) is left
    /// out.
    var entries: [Entry]

    init(_ group: JSON) {
        let keys = group["keys"].arrayValue.map(\.stringValue)
        self.name = group["name"].stringValue
        self.keys = keys
        self.entries = group["athletes"].arrayValue.compactMap { (athlete: JSON) -> Entry? in
            let values = athlete["stats"].arrayValue.map(\.stringValue)
            guard !values.isEmpty else { return nil }
            var stats: [String: String] = [:]
            // A key the feed repeats keeps its first figure.
            for (key, value) in zip(keys, values) where stats[key] == nil {
                stats[key] = value
            }
            return Entry(athlete: athlete["athlete"], stats: stats)
        }
    }
}

/// A hockey game's box score as the detail sheet draws it: each team's
/// comparison statistics, then its skaters, split forwards and defense, and
/// its goalies.
///
/// Read from the summary's `boxscore`: `teams[]` carries each side's
/// name-keyed team statistics and its `homeAway`; `players[]` carries the
/// named stat groups (`BoxscorePlayerGroup`), matched to a side by
/// `team.id`. The score is the header competitor's for the same side.
struct HockeyBoxScore: Hashable, Sendable {
    struct Skater: Hashable, Sendable, Identifiable {
        var athleteID: String
        var name: String
        var shortName: String
        var jersey: String
        /// The position's abbreviation: `"C"`, `"LW"`, `"RW"`, `"D"`.
        var position: String
        /// As the feed shows it, e.g. `"17:38"`.
        var timeOnIce: String
        var goals: Int
        var assists: Int
        var plusMinus: Int
        var shots: Int
        var penaltyMinutes: Int

        var points: Int { goals + assists }

        var id: String { athleteID.isEmpty ? "\(name)#\(jersey)" : athleteID }
    }

    struct Goalie: Hashable, Sendable, Identifiable {
        var athleteID: String
        var name: String
        var shortName: String
        var jersey: String
        var timeOnIce: String
        var shotsAgainst: Int
        var saves: Int
        var goalsAgainst: Int
        /// As the feed shows it, e.g. `".917"`.
        var savePct: String

        var id: String { athleteID.isEmpty ? "\(name)#\(jersey)" : athleteID }
    }

    /// The figures the sheet compares side by side.
    struct TeamStats: Hashable, Sendable {
        var shots: Int
        var powerPlayGoals: Int
        var powerPlayOpportunities: Int
        /// As the feed shows it, e.g. `"16.7"`.
        var powerPlayPct: String
        var faceoffsWon: Int
        /// As the feed shows it, e.g. `"54.5"`.
        var faceoffPct: String
        var hits: Int
        var penaltyMinutes: Int
        var blockedShots: Int
    }

    struct Team: Hashable, Sendable, Identifiable {
        var teamID: String
        var name: String
        var abbreviation: String
        /// `"home"` or `"away"`.
        var homeAway: String
        var score: Int
        var stats: TeamStats
        var forwards: [Skater]
        var defense: [Skater]
        var goalies: [Goalie]

        var id: String { homeAway }
    }

    var home: Team
    var away: Team

    /// Both sides, home first as the sheet draws them.
    var teams: [Team] { [home, away] }
}

extension HockeyBoxScore {
    /// Reads a hockey summary document's box score, or `nil` when its
    /// `boxscore.teams` does not list both a home and an away side.
    ///
    /// A summary from before the puck drops lists the sides with no player
    /// groups; its tables come out empty.
    init?(summary json: JSON) {
        var sides: [String: Team] = [:]
        for (_, entry) in json["boxscore", "teams"] {
            let side = entry["homeAway"].stringValue
            guard side == "home" || side == "away" else { continue }
            sides[side] = Team(boxscoreTeam: entry, summary: json)
        }
        guard let home = sides["home"], let away = sides["away"] else { return nil }
        self.home = home
        self.away = away
    }
}

extension HockeyBoxScore.Team {
    /// One side, from its `boxscore.teams` entry and the rest of the
    /// summary.
    fileprivate init(boxscoreTeam entry: JSON, summary json: JSON) {
        let teamID = entry["team", "id"].stringValue
        let side = entry["homeAway"].stringValue
        let team = entry["team"]
        let shortName = team["shortDisplayName"].stringValue

        self.teamID = teamID
        self.name = shortName.isEmpty ? team["displayName"].stringValue : shortName
        self.abbreviation = team["abbreviation"].stringValue
        self.homeAway = side
        self.stats = HockeyBoxScore.TeamStats(statistics: entry["statistics"])

        var score = 0
        for (_, competitor) in json["header", "competitions", 0, "competitors"]
        where competitor["homeAway"].stringValue == side {
            score = competitorScore(competitor) ?? 0
        }
        self.score = score

        // `players` lists the sides in no promised order; match by team.
        let players = json["boxscore", "players"]
            .first(where: { $0.1["team", "id"].stringValue == teamID })?.1 ?? .null

        var forwards: [HockeyBoxScore.Skater] = []
        var defense: [HockeyBoxScore.Skater] = []
        var goalies: [HockeyBoxScore.Goalie] = []
        for (_, groupJSON) in players["statistics"] {
            let group = BoxscorePlayerGroup(groupJSON)
            switch group.name {
            case "forwards":
                forwards += group.entries.map(HockeyBoxScore.Skater.init(entry:))
            case "defenses", "defense":
                defense += group.entries.map(HockeyBoxScore.Skater.init(entry:))
            case "goalies":
                goalies += group.entries.map(HockeyBoxScore.Goalie.init(entry:))
            case "skaters":
                // Skaters the feed does not split (empty in every summary
                // captured): defensemen by position, everyone else forward.
                for skater in group.entries.map(HockeyBoxScore.Skater.init(entry:)) {
                    if skater.position == "D" {
                        defense.append(skater)
                    } else {
                        forwards.append(skater)
                    }
                }
            default:
                break
            }
        }
        self.forwards = forwards
        self.defense = defense
        self.goalies = goalies
    }
}

extension HockeyBoxScore.TeamStats {
    /// Reads a `boxscore.teams[].statistics` list, flat and name-keyed.
    fileprivate init(statistics: JSON) {
        func stat(_ name: String) -> JSON {
            boxscoreStatistic(statistics, named: name)["displayValue"]
        }

        self.shots = stat("shotsTotal").intValue
        self.powerPlayGoals = stat("powerPlayGoals").intValue
        self.powerPlayOpportunities = stat("powerPlayOpportunities").intValue
        self.powerPlayPct = stat("powerPlayPct").stringValue
        self.faceoffsWon = stat("faceoffsWon").intValue
        self.faceoffPct = stat("faceoffPercent").stringValue
        self.hits = stat("hits").intValue
        self.penaltyMinutes = stat("penaltyMinutes").intValue
        self.blockedShots = stat("blockedShots").intValue
    }
}

extension HockeyBoxScore.Skater {
    fileprivate init(entry: BoxscorePlayerGroup.Entry) {
        let athlete = entry.athlete
        self.athleteID = athlete["id"].stringValue
        self.name = athlete["displayName"].stringValue
        self.shortName = athlete["shortName"].stringValue
        self.jersey = athlete["jersey"].stringValue
        self.position = athlete["position", "abbreviation"].stringValue
        self.timeOnIce = entry.string("timeOnIce")
        self.goals = entry.int("goals")
        self.assists = entry.int("assists")
        self.plusMinus = entry.int("plusMinus")
        self.shots = entry.int("shotsTotal")
        self.penaltyMinutes = entry.int("penaltyMinutes")
    }
}

extension HockeyBoxScore.Goalie {
    fileprivate init(entry: BoxscorePlayerGroup.Entry) {
        let athlete = entry.athlete
        self.athleteID = athlete["id"].stringValue
        self.name = athlete["displayName"].stringValue
        self.shortName = athlete["shortName"].stringValue
        self.jersey = athlete["jersey"].stringValue
        self.timeOnIce = entry.string("timeOnIce")
        self.shotsAgainst = entry.int("shotsAgainst")
        self.saves = entry.int("saves")
        self.goalsAgainst = entry.int("goalsAgainst")
        self.savePct = entry.string("savePct")
    }
}

extension BoxScore {
    /// A hockey game's comparison strip: shots, the power play, faceoffs,
    /// hits, penalty minutes and blocked shots, home side first.
    init(hockey: HockeyBoxScore) {
        let home = hockey.home.stats
        let away = hockey.away.stats

        func row(_ title: String, _ value: (HockeyBoxScore.TeamStats) -> String) -> Row {
            Row(title: title, home: value(home), away: value(away))
        }

        homeScore = hockey.home.score
        awayScore = hockey.away.score
        rows = [
            row("Shots") { "\($0.shots)" },
            row("Power Play") { "\($0.powerPlayGoals)/\($0.powerPlayOpportunities)" },
            row("Power Play %") { "\($0.powerPlayPct)%" },
            row("Faceoffs Won") { "\($0.faceoffsWon)" },
            row("Faceoff %") { "\($0.faceoffPct)%" },
            row("Hits") { "\($0.hits)" },
            row("Penalty Minutes") { "\($0.penaltyMinutes)" },
            row("Blocked Shots") { "\($0.blockedShots)" },
        ]
    }
}
