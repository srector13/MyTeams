//
//  DownloadAthleteData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct BasketballPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var gamesPlayed: Int
    var avgMinutes: Float
    var fieldGoalPct: Float
    var threePointFieldGoalPct: Float
    var freeThrowPct: Float
    var avgOffensiveRebounds: Float
    var avgDefensiveRebounds: Float
    var avgRebounds: Float
    var avgAssists: Float
    var avgBlocks: Float
    var avgSteals: Float
    var avgFouls: Float
    var avgTurnovers: Float
    var avgPoints: Float

    /// The value shown before a player's splits have loaded.
    static let empty = BasketballPlayerStats(
        gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0,
        freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0,
        avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0,
        avgTurnovers: 0, avgPoints: 0
    )
}

/// One statistic in an NFL player's season splits.
struct FootballStat: Identifiable, Hashable, Sendable {
    var id = UUID()
    var label: String
    var display: String

    /// Whether every number in the value is zero ("0", "0.0", "0/0"). A player
    /// with only zeros for a group did not take part in that facet of the
    /// game, so the group is not rendered.
    var isZero: Bool {
        let numbers = display
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .compactMap { Double($0) }
        return !numbers.isEmpty && numbers.allSatisfy { $0 == 0 }
    }
}

/// A position-appropriate block of stats — Passing, Rushing, Defense — under
/// one header.
struct FootballStatGroup: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var stats: [FootballStat]

    /// The stats in the three-column rows the detail view renders, matching
    /// the basketball layout.
    var rows: [[FootballStat]] {
        stride(from: 0, to: stats.count, by: 3).map {
            Array(stats[$0 ..< min($0 + 3, stats.count)])
        }
    }
}

struct FootballPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var groups: [FootballStatGroup]

    /// Whether the splits fetch has finished; lets the view tell "loading"
    /// from "nothing to show".
    var loaded: Bool

    static let empty = FootballPlayerStats(groups: [], loaded: false)
}

/// One catalogued group of NFL split stats.
private struct FootballStatSpec {
    var title: String

    /// The group is rendered only when the feed reports one of these stats,
    /// which keeps e.g. the passing line off a linebacker's card.
    var anchors: [String]
    var entries: [(name: String, label: String)]

    init(_ title: String, anchors: [String], entries: [(name: String, label: String)]) {
        self.title = title
        self.anchors = anchors
        self.entries = entries
    }
}

/// The stat names the NFL athlete-splits feed publishes, in display order.
///
/// Shared names (sacks, interceptions) sit in both the passing and the
/// defensive spec; the passing spec runs first, so a quarterback's "sacks"
/// reads as times sacked and a defender's as sacks made.
private let footballStatSpecs: [FootballStatSpec] = [
    .init("Passing", anchors: ["passingAttempts", "passingYards"], entries: [
        ("completions", "Completions"),
        ("passingAttempts", "Attempts"),
        ("completionPct", "Completion %"),
        ("passingYards", "Yards"),
        ("yardsPerPassAttempt", "Avg / Pass"),
        ("longPassing", "Long"),
        ("passingTouchdowns", "Touchdowns"),
        ("interceptions", "Interceptions"),
        ("sacks", "Sacked"),
        ("sackYards", "Sack Yards"),
        ("QBRating", "Rating"),
    ]),
    .init("Rushing", anchors: ["rushingAttempts", "rushingYards"], entries: [
        ("rushingAttempts", "Carries"),
        ("rushingYards", "Yards"),
        ("yardsPerRushAttempt", "Avg / Carry"),
        ("longRushing", "Long"),
        ("rushingTouchdowns", "Touchdowns"),
    ]),
    .init("Receiving", anchors: ["receptions", "receivingYards"], entries: [
        ("targets", "Targets"),
        ("receptions", "Receptions"),
        ("receivingYards", "Yards"),
        ("yardsPerReception", "Avg / Catch"),
        ("longReception", "Long"),
        ("receivingTouchdowns", "Touchdowns"),
    ]),
    .init("Ball Security", anchors: ["fumbles", "fumblesLost"], entries: [
        ("fumbles", "Fumbles"),
        ("fumblesLost", "Fumbles Lost"),
    ]),
    .init("Defense", anchors: ["totalTackles"], entries: [
        ("totalTackles", "Tackles"),
        ("soloTackles", "Solo"),
        ("assistTackles", "Assists"),
        ("sacks", "Sacks"),
        ("stuffs", "Tackles For Loss"),
        ("stuffYards", "TFL Yards"),
        ("fumblesForced", "Forced Fumbles"),
        ("fumblesRecovered", "Fumbles Recovered"),
        ("kicksBlocked", "Blocked Kicks"),
        ("interceptions", "Interceptions"),
        ("interceptionYards", "INT Yards"),
        ("avgInterceptionYards", "INT Avg"),
        ("interceptionTouchdowns", "INT Touchdowns"),
        ("longInterception", "INT Long"),
        ("passesDefended", "Passes Defended"),
    ]),
    .init("Kicking", anchors: ["totalKickingPoints", "fieldGoalPct"], entries: [
        ("fieldGoalsMade-fieldGoalAttempts", "Field Goals"),
        ("fieldGoalsMade1_19-fieldGoalAttempts1_19", "FG 1-19"),
        ("fieldGoalsMade20_29-fieldGoalAttempts20_29", "FG 20-29"),
        ("fieldGoalsMade30_39-fieldGoalAttempts30_39", "FG 30-39"),
        ("fieldGoalsMade40_49-fieldGoalAttempts40_49", "FG 40-49"),
        ("fieldGoalsMade50-fieldGoalAttempts50", "FG 50+"),
        ("fieldGoalPct", "Field Goal %"),
        ("longFieldGoalMade", "Long Field Goal"),
        ("extraPointsMade-extraPointAttempts", "Extra Points"),
        ("totalKickingPoints", "Points"),
    ]),
    .init("Punting", anchors: ["punts", "puntYards"], entries: [
        ("punts", "Punts"),
        ("puntYards", "Yards"),
        ("grossAvgPuntYards", "Gross Avg"),
        ("netAvgPuntYards", "Net Avg"),
        ("longPunt", "Long"),
        ("touchbacks", "Touchbacks"),
        ("touchbackPct", "Touchback %"),
        ("puntsInside20", "Inside 20"),
        ("puntsInside20Pct", "Inside 20 %"),
        ("puntReturns", "Returns"),
        ("puntReturnYards", "Return Yards"),
        ("avgPuntReturnYards", "Return Avg"),
    ]),
]

/// Formats one raw feed value. Made-attempted stats ("5-6") arrive joined by
/// a hyphen under a hyphenated name and are shown as "5/6".
private func footballStatDisplay(name: String, raw: String) -> String {
    guard name.contains("-") else { return raw }
    let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
    if parts.count == 2,
       parts[0].allSatisfy({ $0.isNumber }), parts[1].allSatisfy({ $0.isNumber }) {
        return "\(parts[0])/\(parts[1])"
    }
    return raw
}

/// Turns an uncatalogued feed name such as "yardsAfterCatch" into the row
/// label "Yards After Catch".
private func humaniseStatName(_ name: String) -> String {
    var words: [String] = []
    var current = ""
    for character in name {
        if character.isUppercase || character == "_" || character == "-" {
            if !current.isEmpty { words.append(current) }
            current = character == "_" ? "" : String(character).lowercased()
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { words.append(current) }
    return words
        .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        .joined(separator: " ")
}

/// Loads a Chiefs player's season splits.
///
/// Unlike the basketball feed, which repeats a keyed stats object per split,
/// the NFL splits document carries one "All Splits" row whose values align
/// positionally with a top-level `names` array. The stats that belong in each
/// group, and whether the group appears at all, come from
/// `footballStatSpecs`; the feed only carries the lines a given position
/// actually plays, and groups whose numbers are all zero are dropped.
func downloadFootballPlayerStats(playerID: String) async -> FootballPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/football/nfl/athletes/\(playerID)/splits"
    )

    let names = json["names"].arrayValue.map { $0.stringValue }
    let values = json["splitCategories"][0]["splits"][0]["stats"].arrayValue.map { $0.stringValue }
    guard !names.isEmpty, names.count == values.count else {
        return FootballPlayerStats(groups: [], loaded: true)
    }

    var feed: [String: String] = [:]
    for (name, value) in zip(names, values) { feed[name] = value }

    var claimed: Set<String> = []
    var groups: [FootballStatGroup] = []

    for spec in footballStatSpecs where spec.anchors.contains(where: { feed[$0] != nil }) {
        var stats: [FootballStat] = []
        for entry in spec.entries {
            guard let raw = feed[entry.name], !claimed.contains(entry.name) else { continue }
            claimed.insert(entry.name)
            stats.append(FootballStat(label: entry.label, display: footballStatDisplay(name: entry.name, raw: raw)))
        }
        if stats.contains(where: { !$0.isZero }) {
            groups.append(FootballStatGroup(title: spec.title, stats: stats))
        }
    }

    // Stats ESPN reports that the catalogue does not know yet still show,
    // under a generated label, rather than silently disappearing.
    let unknown = names.filter { !claimed.contains($0) }
    if !unknown.isEmpty {
        let stats = unknown.map {
            FootballStat(label: humaniseStatName($0), display: footballStatDisplay(name: $0, raw: feed[$0] ?? ""))
        }
        if stats.contains(where: { !$0.isZero }) {
            groups.append(FootballStatGroup(title: "Statistics", stats: stats))
        }
    }

    return FootballPlayerStats(groups: groups, loaded: true)
}

struct SoccerPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var starts: String
    var saves: String
    var cleanSheets: String
    var goalsConceded: String

    static let empty = SoccerPlayerStats(
        starts: "", saves: "", cleanSheets: "", goalsConceded: ""
    )
}

struct BaseballPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()

    // Pitching
    var EarnedRunAverage: Int
    var wins: Int
    var losses: Int
    var saves: Int
    var saveOpportunities: Int
    var gamesPlayed: Int
    var gamesStarted: Int
    var completeGames: Int
    var innings: Float
    var hits: Int
    var runs: Int
    var earnedRuns: Int
    var homeRuns: Int
    var walks: Int
    var strikeouts: Int
    var opponentAvg: Float

    // Batting
    var AtBats: Int
    var Runs: Int
    var Hits: Int
    var Doubles: Int
    var Triples: Int
    var HomeRuns: Int
    var RBIs: Float
    var Walks: Int
    var HitByPitch: Int
    var Strikeouts: Int
    var StolenBases: Int
    var CaughtStealing: Int
    var Avg: Float
    var OnBasePct: Float
    var SlugAvg: Float
    var OPS: Float

    /// The value shown before a player's splits have loaded, and the base the
    /// loader fills in either the pitching or the batting half of.
    static let empty = BaseballPlayerStats(
        EarnedRunAverage: 0, wins: 0, losses: 0, saves: 0, saveOpportunities: 0,
        gamesPlayed: 0, gamesStarted: 0, completeGames: 0, innings: 0, hits: 0,
        runs: 0, earnedRuns: 0, homeRuns: 0, walks: 0, strikeouts: 0, opponentAvg: 0,
        AtBats: 0, Runs: 0, Hits: 0, Doubles: 0, Triples: 0, HomeRuns: 0, RBIs: 0,
        Walks: 0, HitByPitch: 0, Strikeouts: 0, StolenBases: 0, CaughtStealing: 0,
        Avg: 0, OnBasePct: 0, SlugAvg: 0, OPS: 0
    )
}

/// Loads a Kansas player's season averages.
///
/// The splits feed reports home and away separately, so a rate stat is the
/// mean of the two and games played is their sum. Values are addressed by
/// position because the feed lists them in a fixed order with no keys.
func downloadBasketballPlayerStats(playerID: String) async -> BasketballPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/basketball/mens-college-basketball/athletes/\(playerID)/splits"
    )

    let splits = json["splitCategories"][0]["splits"]

    /// The mean of the home and away values at `index`.
    func average(_ index: Int) -> Float {
        (splits[0]["stats"][index].floatValue + splits[1]["stats"][index].floatValue) / 2
    }

    return BasketballPlayerStats(
        gamesPlayed: splits[0]["stats"][0].intValue + splits[1]["stats"][0].intValue,
        avgMinutes: average(1),
        fieldGoalPct: average(3),
        threePointFieldGoalPct: average(5),
        freeThrowPct: average(7),
        avgOffensiveRebounds: average(8),
        avgDefensiveRebounds: average(9),
        avgRebounds: average(10),
        avgAssists: average(11),
        avgBlocks: average(12),
        avgSteals: average(13),
        avgFouls: average(14),
        avgTurnovers: average(15),
        avgPoints: average(16)
    )
}

/// Loads a Royals player's season totals.
///
/// Pitchers and position players get different stat lines from the feed, in
/// the same positions, so the player's position decides which half of
/// `BaseballPlayerStats` is filled in.
func downloadBaseballPlayerStats(
    playerID: String,
    playerPosition: String
) async -> BaseballPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/baseball/mlb/athletes/\(playerID)/splits"
    )

    let stats = json["splitCategories"][0]["splits"][0]["stats"]
    var result = BaseballPlayerStats.empty

    if playerPosition.contains("Pitcher") {
        result.EarnedRunAverage = stats[0].intValue
        result.wins = stats[1].intValue
        result.losses = stats[2].intValue
        result.saves = stats[3].intValue
        result.saveOpportunities = stats[4].intValue
        result.gamesPlayed = stats[5].intValue
        result.gamesStarted = stats[6].intValue
        result.completeGames = stats[7].intValue
        result.innings = stats[8].floatValue
        result.hits = stats[9].intValue
        result.runs = stats[10].intValue
        result.earnedRuns = stats[11].intValue
        result.homeRuns = stats[12].intValue
        result.walks = stats[13].intValue
        result.strikeouts = stats[14].intValue
        result.opponentAvg = stats[15].floatValue
    } else {
        result.AtBats = stats[0].intValue
        result.Runs = stats[1].intValue
        result.Hits = stats[2].intValue
        result.Doubles = stats[3].intValue
        result.Triples = stats[4].intValue
        result.HomeRuns = stats[5].intValue
        result.RBIs = stats[6].floatValue
        result.Walks = stats[7].intValue
        result.HitByPitch = stats[8].intValue
        result.Strikeouts = stats[9].intValue
        result.StolenBases = stats[10].intValue
        result.CaughtStealing = stats[11].intValue
        result.Avg = stats[12].floatValue
        result.OnBasePct = stats[13].floatValue
        result.SlugAvg = stats[14].floatValue
        result.OPS = stats[15].floatValue
    }

    return result
}

/// Loads a Sporting Kansas City player's headline statistics.
///
/// Only the keeper line is filled in; outfield players show "N/A", as they
/// always have.
func downloadSoccerPlayerStats(
    playerID: String,
    playerPosition: String
) async -> SoccerPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/soccer/usa.1/athletes/\(playerID)"
    )

    guard playerPosition.contains("Goalkeeper") else {
        return SoccerPlayerStats(
            starts: "N/A", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A"
        )
    }

    let summary = json["athlete"]["statsSummary"]["statistics"]

    return SoccerPlayerStats(
        starts: summary[0]["value"].stringValue,
        saves: summary[1]["value"].stringValue,
        cleanSheets: summary[2]["value"].stringValue,
        goalsConceded: summary[3]["value"].stringValue
    )
}
