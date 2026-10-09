//
//  DownloadAthleteData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct BasketballPlayerStats: Hashable, Sendable {
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
    /// The seasons the splits document offers. See `AthleteSeasons`.
    var seasons: AthleteSeasons = .empty

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
    /// The feed's name for the stat, e.g. "passingYards" — unique within a
    /// player's splits, so it identifies the stat across refetches.
    var id: String
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
    var title: String
    var stats: [FootballStat]

    /// Group titles are distinct, so the title identifies the group.
    var id: String { title }

    /// The stats in the three-column rows the detail view renders, matching
    /// the basketball layout.
    var rows: [[FootballStat]] {
        stride(from: 0, to: stats.count, by: 3).map {
            Array(stats[$0 ..< min($0 + 3, stats.count)])
        }
    }
}

struct FootballPlayerStats: Hashable, Sendable {
    var groups: [FootballStatGroup]

    /// Whether the splits fetch has finished; lets the view tell "loading"
    /// from "nothing to show".
    var loaded: Bool
    /// The seasons the splits document offers. See `AthleteSeasons`.
    var seasons: AthleteSeasons = .empty

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

/// Loads a football player's season splits in `league`.
///
/// Unlike the basketball feed, which repeats a keyed stats object per split,
/// the NFL splits document carries one "All Splits" row whose values align
/// positionally with a top-level `names` array. The stats that belong in each
/// group, and whether the group appears at all, come from
/// `footballStatSpecs`; the feed only carries the lines a given position
/// actually plays, and groups whose numbers are all zero are dropped.
///
/// `season` is a `season` filter value (`AthleteSeason.value`); `nil` asks
/// for the feed's current season, as do the other splits loaders.
func downloadFootballPlayerStats(
    playerID: String,
    league: LeagueID,
    season: String? = nil
) async -> FootballPlayerStats {
    // The player sheets have no error state of their own: a failed fetch
    // reads as an empty document, which each parser renders as no stats.
    let json = await HTTPClient.shared.fetch(
        athleteSplitsURL(league: league, athleteID: playerID, season: season)
    ).document ?? .null
    return parseFootballPlayerStats(from: json)
}

/// Builds a football player's stat groups from a splits document. See
/// `downloadFootballPlayerStats`.
func parseFootballPlayerStats(from json: JSON) -> FootballPlayerStats {
    let names = json["names"].arrayValue.map { $0.stringValue }
    let values = json["splitCategories"][0]["splits"][0]["stats"].arrayValue.map { $0.stringValue }
    let seasons = parseAthleteSeasons(from: json)
    guard !names.isEmpty, names.count == values.count else {
        return FootballPlayerStats(groups: [], loaded: true, seasons: seasons)
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
            stats.append(FootballStat(id: entry.name, label: entry.label, display: footballStatDisplay(name: entry.name, raw: raw)))
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
            FootballStat(id: $0, label: humaniseStatName($0), display: footballStatDisplay(name: $0, raw: feed[$0] ?? ""))
        }
        if stats.contains(where: { !$0.isZero }) {
            groups.append(FootballStatGroup(title: "Statistics", stats: stats))
        }
    }

    return FootballPlayerStats(groups: groups, loaded: true, seasons: seasons)
}

/// A soccer player's headline season statistics, from the athlete
/// document's `statsSummary`. A figure the summary does not list reads
/// "N/A": keepers get the goalkeeping line, everyone else the outfield one.
struct SoccerPlayerStats: Hashable, Sendable {
    var starts: String
    var saves: String
    var cleanSheets: String
    var goalsConceded: String
    /// Appearances off the bench: the bracketed half of `starts-subIns`
    /// (`"15 (4)"`).
    var substituteAppearances = "N/A"
    var goals = "N/A"
    var assists = "N/A"
    var shots = "N/A"

    static let empty = SoccerPlayerStats(
        starts: "", saves: "", cleanSheets: "", goalsConceded: "",
        substituteAppearances: "", goals: "", assists: "", shots: ""
    )

    /// Whether the summary gave anything but "N/A".
    var hasFigures: Bool {
        [starts, saves, cleanSheets, goalsConceded, substituteAppearances, goals, assists, shots]
            .contains { $0 != "N/A" && !$0.isEmpty }
    }
}

struct BaseballPlayerStats: Hashable, Sendable {
    // Pitching
    var EarnedRunAverage: Float
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

    /// The seasons the splits document offers. See `AthleteSeasons`.
    var seasons: AthleteSeasons = .empty

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

/// Loads a basketball player's season averages in `league`.
///
/// The college splits feeds report only home and away, so there a rate stat
/// is the mean of the two weighted by games played, and games played is
/// their sum. The NBA and WNBA feeds lead with an "All Splits" row, which
/// is read alone. See `parseBasketballPlayerStats`.
func downloadBasketballPlayerStats(
    playerID: String,
    league: LeagueID,
    season: String? = nil
) async -> BasketballPlayerStats {
    let json = await HTTPClient.shared.fetch(
        athleteSplitsURL(league: league, athleteID: playerID, season: season)
    ).document ?? .null
    return parseBasketballPlayerStats(from: json)
}

/// The splits row that is a player's whole season, by the name each feed
/// gives it: basketball's and hockey's `"All Splits"`, college football's
/// `"Season"`.
private let seasonSplitNames: Set<String> = ["All Splits", "Season"]

/// Extracts a basketball player's season averages from a splits document.
/// See `downloadBasketballPlayerStats`.
///
/// Values are found by the document's `names` (`"avgPoints"`); a document
/// without them is read at the positions every captured feed lists them in.
///
/// Every row used to be read as `[0]` home and `[1]` away. The NBA's rows
/// are All Splits, Home, Road, …, which made a 76-game NBA season 113 games
/// and blended its averages with the home split's.
func parseBasketballPlayerStats(from json: JSON) -> BasketballPlayerStats {
    let names = json["names"].arrayValue.map(\.stringValue)
    let rows = json["splitCategories"][0]["splits"].arrayValue
    let parts: [JSON] = rows.first { seasonSplitNames.contains($0["displayName"].stringValue) }
        .map { [$0] } ?? Array(rows.prefix(2))

    func value(_ row: JSON, _ name: String, _ position: Int) -> JSON {
        row["stats"][names.firstIndex(of: name) ?? position]
    }

    let games = parts.map { value($0, "gamesPlayed", 0).floatValue }
    let totalGames = games.reduce(0, +)

    /// The parts' values for `name`, weighted by the games each covers. A
    /// player with no games falls back to the plain mean rather than
    /// dividing by zero.
    func average(_ name: String, _ position: Int) -> Float {
        let values = parts.map { value($0, name, position).floatValue }
        guard !values.isEmpty else { return 0 }
        guard totalGames > 0 else { return values.reduce(0, +) / Float(values.count) }
        return zip(values, games).reduce(Float(0)) { $0 + $1.0 * $1.1 } / totalGames
    }

    return BasketballPlayerStats(
        gamesPlayed: parts.reduce(0) { $0 + value($1, "gamesPlayed", 0).intValue },
        avgMinutes: average("avgMinutes", 1),
        fieldGoalPct: average("fieldGoalPct", 3),
        threePointFieldGoalPct: average("threePointFieldGoalPct", 5),
        freeThrowPct: average("freeThrowPct", 7),
        avgOffensiveRebounds: average("avgOffensiveRebounds", 8),
        avgDefensiveRebounds: average("avgDefensiveRebounds", 9),
        avgRebounds: average("avgRebounds", 10),
        avgAssists: average("avgAssists", 11),
        avgBlocks: average("avgBlocks", 12),
        avgSteals: average("avgSteals", 13),
        avgFouls: average("avgFouls", 14),
        avgTurnovers: average("avgTurnovers", 15),
        avgPoints: average("avgPoints", 16),
        seasons: parseAthleteSeasons(from: json)
    )
}

// MARK: - Season lines by name

/// One statistic in a player's season line.
struct PlayerSeasonStat: Identifiable, Hashable, Sendable {
    /// The feed's name for it, e.g. `"goals"`.
    var id: String
    /// The feed's display name, e.g. `"Goals"`.
    var label: String
    /// The feed's abbreviation, e.g. `"G"`.
    var abbreviation: String
    /// As the feed shows it: `"41"`, `".888"`, `"17:15"`.
    var display: String
}

/// A player's whole-season row from a splits document, each figure keyed
/// by the document's `names`.
///
/// The splits documents carry parallel `names`, `labels` and
/// `displayNames`, and each row a bare `stats` array in the same order.
/// They are zipped here, as `BoxscorePlayerGroup` does for box scores, so
/// a reader asks for `"savePct"` rather than a position that differs
/// between a skater's line and a goalie's.
struct SplitsSeasonLine: Hashable, Sendable {
    /// The document's `displayName`, e.g. `"2025-26 Splits"`.
    var title: String
    /// Feed order.
    var stats: [PlayerSeasonStat]
    /// Whether the fetch has finished; lets a view tell "loading" from
    /// "nothing to show".
    var loaded: Bool
    /// The seasons the document offers. See `AthleteSeasons`.
    var seasons: AthleteSeasons = .empty

    static let empty = SplitsSeasonLine(title: "", stats: [], loaded: false)

    /// The stat the feed names `name`, if the line has it.
    func stat(_ name: String) -> PlayerSeasonStat? {
        stats.first { $0.id == name }
    }
}

/// Reads the season row of a splits document: the row named "All Splits"
/// or "Season", or a lone row. A document with neither (college
/// basketball's Home and Away only) reads as loaded and empty, as does a
/// failed fetch.
func parseSplitsSeasonLine(from json: JSON) -> SplitsSeasonLine {
    let names = json["names"].arrayValue.map(\.stringValue)
    let labels = json["displayNames"].arrayValue.map(\.stringValue)
    let abbreviations = json["labels"].arrayValue.map(\.stringValue)
    let rows = json["splitCategories"][0]["splits"].arrayValue
    let season = rows.first { seasonSplitNames.contains($0["displayName"].stringValue) }
        ?? (rows.count == 1 ? rows.first : nil)
    let values = season?["stats"].arrayValue.map(\.stringValue) ?? []
    let seasons = parseAthleteSeasons(from: json)

    guard !names.isEmpty, names.count == values.count else {
        return SplitsSeasonLine(title: json["displayName"].stringValue, stats: [], loaded: true, seasons: seasons)
    }

    var seen: Set<String> = []
    var stats: [PlayerSeasonStat] = []
    for (index, name) in names.enumerated() where seen.insert(name).inserted {
        stats.append(PlayerSeasonStat(
            id: name,
            label: index < labels.count ? labels[index] : name,
            abbreviation: index < abbreviations.count ? abbreviations[index] : "",
            display: values[index]
        ))
    }
    return SplitsSeasonLine(title: json["displayName"].stringValue, stats: stats, loaded: true, seasons: seasons)
}

// MARK: - Hockey

/// The skater stats a hockey player sheet shows, in order, by the NHL
/// splits feed's names.
let hockeySkaterStatNames = [
    "games", "goals", "assists", "points", "plusMinus", "penaltyMinutes",
    "shotsTotal", "powerPlayGoals", "powerPlayAssists", "shortHandedGoals",
    "gameWinningGoals", "faceoffPercent", "timeOnIcePerGame",
]

/// The goaltender stats a hockey player sheet shows, in order.
let hockeyGoalieStatNames = [
    "gameStarted", "wins", "losses", "overtimeLosses", "goalsAgainst",
    "avgGoalsAgainst", "shotsAgainst", "saves", "savePct", "shutouts",
    "timeOnIcePerGame",
]

/// Loads a hockey player's season line in `league`, from the athlete
/// splits. See `hockeySheetStats(from:)`.
func downloadHockeyPlayerStats(
    playerID: String,
    league: LeagueID,
    season: String? = nil
) async -> SplitsSeasonLine {
    let json = await HTTPClient.shared.fetch(
        athleteSplitsURL(league: league, athleteID: playerID, season: season)
    ).document ?? .null
    return parseSplitsSeasonLine(from: json)
}

/// The stats a hockey player sheet shows from `line`: a goalie's line (one
/// with a `savePct`) in `hockeyGoalieStatNames` order, a skater's in
/// `hockeySkaterStatNames` order. A line with none of those names shows
/// every stat it has, so a new feed shape still renders.
func hockeySheetStats(from line: SplitsSeasonLine) -> [PlayerSeasonStat] {
    let order = line.stat("savePct") != nil ? hockeyGoalieStatNames : hockeySkaterStatNames
    let picked = order.compactMap(line.stat)
    return picked.isEmpty ? line.stats : picked
}

/// Loads a baseball player's season totals in `league`.
///
/// Pitchers and position players get different stat lines from the feed, in
/// the same positions, so the player's position decides which half of
/// `BaseballPlayerStats` is filled in.
func downloadBaseballPlayerStats(
    playerID: String,
    playerPosition: String,
    league: LeagueID,
    season: String? = nil
) async -> BaseballPlayerStats {
    let json = await HTTPClient.shared.fetch(
        athleteSplitsURL(league: league, athleteID: playerID, season: season)
    ).document ?? .null
    return parseBaseballPlayerStats(from: json, playerPosition: playerPosition)
}

/// Extracts a baseball player's season totals from a splits document. See
/// `downloadBaseballPlayerStats`.
///
/// Each figure is looked up by its name in the document's `names` array
/// (`ERA`, `wins`, … for a pitcher; `atBats`, `runs`, … for a batter), as
/// `parseFootballPlayerStats` does, so a column ESPN inserts or reorders
/// cannot shift every figure along by one; a name the feed drops reads as
/// zero. A document without `names` matching its values one-for-one is read
/// by position in the order those names are listed here.
func parseBaseballPlayerStats(from json: JSON, playerPosition: String) -> BaseballPlayerStats {
    let values = json["splitCategories"][0]["splits"][0]["stats"].arrayValue
    let names = json["names"].arrayValue.map(\.stringValue)
    let byName = !names.isEmpty && names.count == values.count
    var result = BaseballPlayerStats.empty
    result.seasons = parseAthleteSeasons(from: json)

    let isPitcher = playerPosition.contains("Pitcher")
    let order = isPitcher ? baseballPitchingStatNames : baseballBattingStatNames
    var feed: [String: JSON] = [:]
    if byName {
        for (name, value) in zip(names, values) where feed[name] == nil { feed[name] = value }
    } else {
        for (name, value) in zip(order, values) { feed[name] = value }
    }
    func stat(_ name: String) -> JSON { feed[name] ?? .null }

    if isPitcher {
        result.EarnedRunAverage = stat("ERA").floatValue
        result.wins = stat("wins").intValue
        result.losses = stat("losses").intValue
        result.saves = stat("saves").intValue
        result.saveOpportunities = stat("saveOpportunities").intValue
        result.gamesPlayed = stat("gamesPlayed").intValue
        result.gamesStarted = stat("gamesStarted").intValue
        result.completeGames = stat("completeGames").intValue
        result.innings = stat("innings").floatValue
        result.hits = stat("hits").intValue
        result.runs = stat("runs").intValue
        result.earnedRuns = stat("earnedRuns").intValue
        result.homeRuns = stat("homeRuns").intValue
        result.walks = stat("walks").intValue
        result.strikeouts = stat("strikeouts").intValue
        result.opponentAvg = stat("opponentAvg").floatValue
    } else {
        result.AtBats = stat("atBats").intValue
        result.Runs = stat("runs").intValue
        result.Hits = stat("hits").intValue
        result.Doubles = stat("doubles").intValue
        result.Triples = stat("triples").intValue
        result.HomeRuns = stat("homeRuns").intValue
        result.RBIs = stat("RBIs").floatValue
        result.Walks = stat("walks").intValue
        result.HitByPitch = stat("hitByPitch").intValue
        result.Strikeouts = stat("strikeouts").intValue
        result.StolenBases = stat("stolenBases").intValue
        result.CaughtStealing = stat("caughtStealing").intValue
        result.Avg = stat("avg").floatValue
        result.OnBasePct = stat("onBasePct").floatValue
        result.SlugAvg = stat("slugAvg").floatValue
        result.OPS = stat("OPS").floatValue
    }

    return result
}

/// A pitcher's splits `names`, in the order the feed lists them
/// (royals_splits_5136077.json).
private let baseballPitchingStatNames = [
    "ERA", "wins", "losses", "saves", "saveOpportunities", "gamesPlayed",
    "gamesStarted", "completeGames", "innings", "hits", "runs", "earnedRuns",
    "homeRuns", "walks", "strikeouts", "opponentAvg",
]

/// A batter's splits `names`, in the order the feed lists them (the same
/// fixture's `extraPlayerPageAthleteSplits.batting.names`).
private let baseballBattingStatNames = [
    "atBats", "runs", "hits", "doubles", "triples", "homeRuns", "RBIs",
    "walks", "hitByPitch", "strikeouts", "stolenBases", "caughtStealing",
    "avg", "onBasePct", "slugAvg", "OPS",
]

/// Loads a soccer player's headline statistics in `league`.
///
/// The roster feed carries fuller season totals (`parseSoccerRoster`); the
/// player sheet reads these only for a player the roster listed without
/// any. See `parseSoccerPlayerStats`.
func downloadSoccerPlayerStats(
    playerID: String,
    playerPosition: String,
    league: LeagueID
) async -> SoccerPlayerStats {
    let json = await HTTPClient.shared.fetch(
        league.athleteURL(athleteID: playerID)
    ).document ?? .null
    return parseSoccerPlayerStats(from: json, playerPosition: playerPosition)
}

/// Extracts a soccer player's headline statistics from an athlete document.
/// See `downloadSoccerPlayerStats`.
///
/// The summary's statistics are read by `name`. A keeper's are
/// `starts-subIns`, `saves`, `cleanSheet`, `goalsConceded`; an outfield
/// player's `starts-subIns`, `totalGoals`, `goalAssists`, `totalShots` —
/// the same four in every soccer league captured. No soccer feed carries
/// minutes played. Outfield players used to read "N/A" throughout.
func parseSoccerPlayerStats(from json: JSON, playerPosition: String) -> SoccerPlayerStats {
    var summary: [String: JSON] = [:]
    for stat in json["athlete"]["statsSummary"]["statistics"].arrayValue {
        let name = stat["name"].stringValue
        if summary[name] == nil { summary[name] = stat }
    }

    func value(_ name: String) -> String {
        summary[name].map { $0["value"].stringValue } ?? "N/A"
    }

    let starts = value("starts-subIns")

    guard !playerPosition.contains("Goalkeeper") else {
        return SoccerPlayerStats(
            starts: starts,
            saves: value("saves"),
            cleanSheets: value("cleanSheet"),
            goalsConceded: value("goalsConceded")
        )
    }

    // `value` is the starts alone; the substitute appearances are only in
    // the `displayValue`, bracketed: "15 (4)".
    let appearances = summary["starts-subIns"]?["displayValue"].stringValue ?? ""
    var substitutes = "N/A"
    if let open = appearances.firstIndex(of: "("),
       let close = appearances.lastIndex(of: ")"),
       open < close {
        substitutes = appearances[appearances.index(after: open) ..< close]
            .trimmingCharacters(in: .whitespaces)
    }

    return SoccerPlayerStats(
        starts: starts,
        saves: "N/A",
        cleanSheets: "N/A",
        goalsConceded: "N/A",
        substituteAppearances: substitutes,
        goals: value("totalGoals"),
        assists: value("goalAssists"),
        shots: value("totalShots")
    )
}

// MARK: - Seasons

/// One season an athlete document's `season` filter offers.
struct AthleteSeason: Identifiable, Hashable, Sendable {
    /// What the feed takes as `?season=`: the year the season ends,
    /// `"2026"` for 2025-26.
    var value: String
    /// As the feed shows it: `"2025-26"`, or `"2026"` for a one-year season.
    var label: String

    var id: String { value }
}

/// The seasons a splits or game-log document's `filters` list, newest first
/// as the feed orders them, and the one the document is for.
///
/// A document fetched for a past season lists only that season, so a sheet
/// keeps the list from its first, current-season fetch.
struct AthleteSeasons: Hashable, Sendable {
    var options: [AthleteSeason]
    /// The `value` of the season the document covers, if it says.
    var selected: String?

    static let empty = AthleteSeasons(options: [], selected: nil)
}

/// Reads the `season` entry of a document's `filters`. A document without
/// one, or a failed fetch, offers no seasons.
func parseAthleteSeasons(from json: JSON) -> AthleteSeasons {
    let filter = json["filters"].arrayValue.first { $0["name"].stringValue == "season" } ?? .null
    var seen: Set<String> = []
    let options = filter["options"].arrayValue.compactMap { option -> AthleteSeason? in
        let value = option["value"].stringValue
        guard !value.isEmpty, seen.insert(value).inserted else { return nil }
        let label = option["displayValue"].stringValue
        return AthleteSeason(value: value, label: label.isEmpty ? value : label)
    }
    let selected = filter["value"].stringValue
    return AthleteSeasons(options: options, selected: selected.isEmpty ? nil : selected)
}

/// `url` for `season`, or as it is for `nil`: the feed's current season.
private func seasonURL(_ url: String, season: String?) -> String {
    guard let season, !season.isEmpty else { return url }
    return "\(url)?season=\(season.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? season)"
}

/// An athlete's splits in `season`. See `seasonURL(_:season:)`.
private func athleteSplitsURL(league: LeagueID, athleteID: String, season: String?) -> String {
    seasonURL(league.athleteSplitsURL(athleteID: athleteID), season: season)
}

// MARK: - Game logs

/// One stat column of a game log: the feed's `names`, `labels` and
/// `displayNames` at one position.
struct GameLogColumn: Identifiable, Hashable, Sendable {
    /// The feed's name for it, e.g. `"passingYards"`.
    var id: String
    /// The column header, e.g. `"YDS"`.
    var label: String
    /// The full name VoiceOver reads, e.g. `"Passing Yards"`.
    var displayName: String
}

/// One game in an athlete's game log.
struct GameLogRow: Identifiable, Hashable, Sendable {
    /// ESPN's event id.
    var id: String
    /// When the game started; `nil` if the feed's `gameDate` did not parse.
    var date: Date?
    var opponentID: String
    /// `"Las Vegas Raiders"`.
    var opponentName: String
    /// `"LV"`.
    var opponentAbbreviation: String
    /// The feed's `atVs`: `"vs"` at home, `"@"` away.
    var isHome: Bool
    /// The feed's `gameResult` for the athlete's team: `"W"`, `"L"`, a
    /// draw's letter, or empty for a game without one.
    var result: String
    /// Winner's score first, as the feed gives it: `"30-27"`, `"33-30 OT"`.
    var score: String
    /// A postseason game's `eventNote`, e.g. `"East 1st Round - Game 6"`.
    var note: String
    /// The season type the game is filed under, e.g. `"2025-26 Postseason"`.
    var seasonType: String
    /// The athlete's line in the game, by the document's `names`, as the
    /// feed displays it: `["passingYards": "225", "completionPct": "50.0"]`.
    var stats: [String: String]

    /// `"W 30-27"`, or whichever half the feed gave.
    var resultSummary: String {
        [result, score].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `"@ LV"` or `"vs LV"`, the full name standing in for a missing
    /// abbreviation.
    var opponentSummary: String {
        let opponent = opponentAbbreviation.isEmpty ? opponentName : opponentAbbreviation
        return "\(isHome ? "vs" : "@") \(opponent)"
    }
}

/// An athlete's game log in one season: every game the feed lists, newest
/// first.
struct AthleteGameLog: Hashable, Sendable {
    /// Feed order.
    var columns: [GameLogColumn]
    /// Newest first.
    var rows: [GameLogRow]
    /// The seasons the document offers. See `AthleteSeasons`.
    var seasons: AthleteSeasons
    /// Whether the fetch has finished; lets a view tell "loading" from
    /// "nothing to show".
    var loaded: Bool

    static let empty = AthleteGameLog(columns: [], rows: [], seasons: .empty, loaded: false)

    /// The three or four columns a compact row shows, under the spec's own
    /// headers (the NFL's `labels` call both passing and rushing yards
    /// "YDS"): the `gameLogHeadlineSpecs` entry this log has the most
    /// columns of. A tie goes to the spec whose first column comes first in
    /// the log, as the feed leads with a player's main line: a tight end's
    /// receiving before his rushing. A log matching no spec in at least two
    /// columns shows its first four.
    var headlineColumns: [GameLogColumn] {
        var positions: [String: Int] = [:]
        for (index, column) in columns.enumerated() where positions[column.id] == nil {
            positions[column.id] = index
        }

        var best: [GameLogColumn] = []
        var bestLead = Int.max
        for spec in gameLogHeadlineSpecs {
            let picked = spec.compactMap { entry -> GameLogColumn? in
                guard let index = positions[entry.name] else { return nil }
                return GameLogColumn(id: entry.name, label: entry.label, displayName: columns[index].displayName)
            }
            let lead = picked.first.flatMap { positions[$0.id] } ?? Int.max
            if picked.count > best.count || (picked.count == best.count && lead < bestLead) {
                best = picked
                bestLead = lead
            }
        }
        return best.count >= 2 ? best : Array(columns.prefix(4))
    }
}

/// The compact columns per kind of player, by the game-log `names` each
/// sport's feed publishes (`{key}_gamelog_{id}.json`).
private let gameLogHeadlineSpecs: [[(name: String, label: String)]] = [
    // Football: passer, runner, receiver, defender, kicker.
    [("passingYards", "YDS"), ("passingTouchdowns", "TD"), ("interceptions", "INT"), ("QBRating", "RTG")],
    [("rushingAttempts", "CAR"), ("rushingYards", "YDS"), ("rushingTouchdowns", "TD"), ("receptions", "REC")],
    [("receptions", "REC"), ("receivingYards", "YDS"), ("receivingTouchdowns", "TD"), ("receivingTargets", "TGT")],
    [("totalTackles", "TOT"), ("sacks", "SACK"), ("interceptions", "INT"), ("passesDefended", "PD")],
    [("fieldGoalsMade-fieldGoalAttempts", "FG"), ("longFieldGoalMade", "LNG"),
     ("extraPointsMade-extraPointAttempts", "XP"), ("totalKickingPoints", "PTS")],
    // Basketball.
    [("points", "PTS"), ("totalRebounds", "REB"), ("assists", "AST"), ("minutes", "MIN")],
    // Baseball: batter, pitcher.
    [("atBats", "AB"), ("hits", "H"), ("homeRuns", "HR"), ("RBIs", "RBI")],
    [("innings", "IP"), ("hits", "H"), ("earnedRuns", "ER"), ("strikeouts", "K")],
    // Hockey: goaltender, skater.
    [("saves", "SV"), ("goalsAgainst", "GA"), ("savePct", "SV%")],
    [("goals", "G"), ("assists", "A"), ("points", "PTS"), ("plusMinus", "+/-")],
    // Soccer.
    [("totalGoals", "G"), ("goalAssists", "A"), ("totalShots", "SH"), ("shotsOnTarget", "SOT")],
]

/// Loads an athlete's game log in `league`: `season`'s, or the feed's
/// current season's for `nil`. A failed fetch reads as a loaded, empty log.
func downloadGameLog(athlete: String, league: LeagueID, season: String? = nil) async -> AthleteGameLog {
    let json = await HTTPClient.shared.fetch(
        seasonURL("\(league.athleteURL(athleteID: athlete))/gamelog", season: season)
    ).document ?? .null
    return parseGameLog(from: json)
}

/// Builds an athlete's game log from a game-log document. See
/// `downloadGameLog`.
///
/// Every sport's document has the same shape. Top-level `names`, `labels`
/// and `displayNames` name the stat columns; `seasonTypes[].categories[]`
/// (a month, a playoff round, a whole season) list `events[]` of
/// `{eventId, stats}`, the stats in `names` order; and the top-level
/// `events` object keys each game's date, opponent and result by event id.
/// The season types and their categories run newest first, and so do the
/// rows here: the `events` object is unordered. A category of type
/// `"total"` lists no events. A row whose game is missing from `events` is
/// dropped, as is a game listed twice.
func parseGameLog(from json: JSON) -> AthleteGameLog {
    let names = json["names"].arrayValue.map(\.stringValue)
    let labels = json["labels"].arrayValue.map(\.stringValue)
    let displayNames = json["displayNames"].arrayValue.map(\.stringValue)

    var columns: [GameLogColumn] = []
    var seenColumns: Set<String> = []
    for (index, name) in names.enumerated() where seenColumns.insert(name).inserted {
        columns.append(GameLogColumn(
            id: name,
            label: index < labels.count ? labels[index] : name,
            displayName: index < displayNames.count ? displayNames[index] : name
        ))
    }

    let events = json["events"]
    var seenEvents: Set<String> = []
    var rows: [GameLogRow] = []
    for seasonType in json["seasonTypes"].arrayValue {
        let seasonName = seasonType["displayName"].stringValue
        for category in seasonType["categories"].arrayValue {
            for entry in category["events"].arrayValue {
                let id = entry["eventId"].stringValue
                let event = events[id]
                guard !id.isEmpty, event.exists, seenEvents.insert(id).inserted else { continue }

                var stats: [String: String] = [:]
                for (name, value) in zip(names, entry["stats"].arrayValue) where stats[name] == nil {
                    stats[name] = value.stringValue
                }

                let opponent = event["opponent"]
                let atVs = event["atVs"].stringValue
                rows.append(GameLogRow(
                    id: id,
                    date: parseGameLogDate(event["gameDate"].stringValue),
                    opponentID: opponent["id"].stringValue,
                    opponentName: opponent["displayName"].stringValue,
                    opponentAbbreviation: opponent["abbreviation"].stringValue,
                    // A game without `atVs` is placed by the home team's id.
                    isHome: atVs.isEmpty
                        ? event["homeTeamId"].stringValue == event["team"]["id"].stringValue
                        : atVs != "@",
                    result: event["gameResult"].stringValue,
                    score: event["score"].stringValue,
                    note: event["eventNote"].stringValue,
                    seasonType: seasonName,
                    stats: stats
                ))
            }
        }
    }

    return AthleteGameLog(columns: columns, rows: rows, seasons: parseAthleteSeasons(from: json), loaded: true)
}

/// Readers for a game log's `gameDate`, `2026-10-04T20:25:00.000+00:00`,
/// and the same without fractional seconds or seconds. Pinned to
/// `en_US_POSIX` and the Gregorian calendar, as `makeEventDateParser` is.
private let gameLogDateParsers: [DateFormatter] = [
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
    "yyyy-MM-dd'T'HH:mm:ssXXXXX",
    "yyyy-MM-dd'T'HH:mmXXXXX",
].map { format in
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
}

/// The instant a game log's `gameDate` names, or `nil`.
func parseGameLogDate(_ string: String) -> Date? {
    guard !string.isEmpty else { return nil }
    for parser in gameLogDateParsers {
        if let date = parser.date(from: string) { return date }
    }
    return nil
}
