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
func downloadFootballPlayerStats(playerID: String, league: LeagueID) async -> FootballPlayerStats {
    // The player sheets have no error state of their own: a failed fetch
    // reads as an empty document, which each parser renders as no stats.
    let json = await HTTPClient.shared.fetch(
        league.athleteSplitsURL(athleteID: playerID)
    ).document ?? .null
    return parseFootballPlayerStats(from: json)
}

/// Builds a football player's stat groups from a splits document. See
/// `downloadFootballPlayerStats`.
func parseFootballPlayerStats(from json: JSON) -> FootballPlayerStats {
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

    return FootballPlayerStats(groups: groups, loaded: true)
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
func downloadBasketballPlayerStats(playerID: String, league: LeagueID) async -> BasketballPlayerStats {
    let json = await HTTPClient.shared.fetch(
        league.athleteSplitsURL(athleteID: playerID)
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
        avgPoints: average("avgPoints", 16)
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

    guard !names.isEmpty, names.count == values.count else {
        return SplitsSeasonLine(title: json["displayName"].stringValue, stats: [], loaded: true)
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
    return SplitsSeasonLine(title: json["displayName"].stringValue, stats: stats, loaded: true)
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
func downloadHockeyPlayerStats(playerID: String, league: LeagueID) async -> SplitsSeasonLine {
    let json = await HTTPClient.shared.fetch(
        league.athleteSplitsURL(athleteID: playerID)
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
    league: LeagueID
) async -> BaseballPlayerStats {
    let json = await HTTPClient.shared.fetch(
        league.athleteSplitsURL(athleteID: playerID)
    ).document ?? .null
    return parseBaseballPlayerStats(from: json, playerPosition: playerPosition)
}

/// Extracts a baseball player's season totals from a splits document. See
/// `downloadBaseballPlayerStats`.
func parseBaseballPlayerStats(from json: JSON, playerPosition: String) -> BaseballPlayerStats {
    let stats = json["splitCategories"][0]["splits"][0]["stats"]
    var result = BaseballPlayerStats.empty

    if playerPosition.contains("Pitcher") {
        result.EarnedRunAverage = stats[0].floatValue
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
