//
//  DownloadGameData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct GameInfo: Hashable, Sendable {
    var venueImage: String
    var city: String
    var state: String
    var capacity: String
    var attendance: String
    var gameColor: String

    /// The value shown before a summary has loaded.
    static let empty = GameInfo(
        venueImage: "", city: "", state: "", capacity: "", attendance: "", gameColor: ""
    )
}

struct BasketballGameTeamStats: Identifiable, Hashable, Sendable {
    var name: String
    var fieldGoals: String
    var fieldGoalPct: Float
    var threePoints: String
    var threePointPct: Float
    var freeThrows: String
    var freeThrowPct: Float
    var offensiveRebounds: Int
    var defensiveRebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var turnOvers: Int
    var fouls: Int
    var largestLead: Int
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String

    /// A team's line is identified by the team, so a refreshed box score
    /// compares equal to the one it replaces when nothing has changed.
    var id: String { name }

    /// The pair of blank lines a detail view shows before its box score loads.
    static let placeholderPair = [Self](repeating: BasketballGameTeamStats(
        name: "", fieldGoals: "0", fieldGoalPct: 0, threePoints: "0",
        threePointPct: 0, freeThrows: "0", freeThrowPct: 0, offensiveRebounds: 0,
        defensiveRebounds: 0, assists: 0, steals: 0, blocks: 0, turnOvers: 0,
        fouls: 0, largestLead: 0, projection: 0, score: 0, opponentScore: 0,
        gameClock: ""
    ), count: 2)
}

struct FootballGameTeamStats: Identifiable, Hashable, Sendable {
    var name: String
    var yards: Int
    var passingYards: Int
    var rushingYards: Int
    var firstDowns: Int
    var drives: Int
    var score: Int
    var interceptions: Int
    var possesionTime: String
    var completionAttempts: Int
    var opponentScore: Int
    var gameClock: String

    /// See `BasketballGameTeamStats.id`.
    var id: String { name }

    /// The pair of blank lines a detail view shows before its box score loads.
    static let placeholderPair = [Self](repeating: FootballGameTeamStats(
        name: "", yards: 0, passingYards: 0, rushingYards: 0, firstDowns: 0,
        drives: 0, score: 0, interceptions: 0, possesionTime: "",
        completionAttempts: 0, opponentScore: 0, gameClock: ""
    ), count: 2)
}

/// One team's line in a baseball game's box score.
///
/// The box score lists teams in no stable order (MLB lists away first, MLS
/// home), so each line carries the `homeAway` side it belongs to and callers
/// pick the side they need rather than indexing by position.
struct BaseballGameTeamStats: Identifiable, Hashable, Sendable {
    var name: String
    /// `"home"` or `"away"`, as the box score labels this line.
    var homeAway: String
    var runs: Int
    var hits: Int
    var errors: Int

    /// A line is identified by its side, falling back to the team name.
    var id: String { homeAway.isEmpty ? name : homeAway }
}

/// One team's line in a soccer game's box score. See
/// `BaseballGameTeamStats` for why lines carry their side.
struct SoccerGameTeamStats: Identifiable, Hashable, Sendable {
    var name: String
    /// `"home"` or `"away"`, as the box score labels this line.
    var homeAway: String
    var goals: Int
    var shots: Int
    var possessionPct: Float
    var corners: Int

    /// See `BaseballGameTeamStats.id`.
    var id: String { homeAway.isEmpty ? name : homeAway }
}

/// The current score of a game, read from its summary document.
///
/// Schedule cards need nothing livelier than the two team totals; the full
/// box-score loaders behind the detail sheets fetch far more than a card
/// renders.
struct LiveGameScore: Sendable, Hashable {
    var score: Int
    var opponentScore: Int
}

/// Reads the current score from a game's summary document.
///
/// `isHome` is the schedule feed's `gameHome` flag for the followed team. The
/// pro summaries carry no `shortDisplayName` on their header competitors, so
/// the home/away side is the reliable key; the box-score name only
/// disambiguates when a header omits `homeAway` (or the fixture moved sides).
///
/// Returns `nil` when the fetch failed or the document cannot be attributed,
/// so a caller can keep its last known figures instead of painting a
/// rate-limited or partial response as a 0–0 game.
func downloadLiveGameScore(gameID: String, team: Team, isHome: Bool) async -> LiveGameScore? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return parseLiveGameScore(from: json, team: team, isHome: isHome)
}

/// Reads a header competitor's score, or `nil` when it has none.
///
/// The summary header publishes `score` as a bare string (`"3"`); the schedule
/// feed wraps it as `{"value": 3.0, "displayValue": "3"}`. Both are accepted.
func competitorScore(_ competitor: JSON) -> Int? {
    let score = competitor["score"]
    return score.dictionary == nil ? score.int : score["displayValue"].int
}

/// Extracts the current score from a game's summary document. See
/// `downloadLiveGameScore`.
func parseLiveGameScore(from json: JSON, team: Team, isHome: Bool) -> LiveGameScore? {
    var score: Int?
    var opponentScore: Int?
    for (_, competitor): (String, JSON) in json["header", "competitions", 0, "competitors"] {
        let followedTeam: Bool
        let side = competitor["homeAway"].stringValue
        if side == "home" || side == "away" {
            followedTeam = side == (isHome ? "home" : "away")
        } else {
            followedTeam = competitor["team"]["shortDisplayName"].stringValue == team.boxscoreName
        }

        if followedTeam {
            score = competitorScore(competitor)
        } else {
            opponentScore = competitorScore(competitor)
        }
    }

    guard let score, let opponentScore else { return nil }
    return LiveGameScore(score: score, opponentScore: opponentScore)
}

/// Where a game stands, as its summary document reports it.
enum GamePhase: Sendable, Hashable {
    /// Not started yet.
    case pre
    /// In progress, including halftime and delays.
    case live
    /// Over — played out, or called off.
    case final
    /// The document carried no status, e.g. because the fetch failed.
    case unknown
}

/// Reads the game's phase from the header of its summary document.
func parseGamePhase(from json: JSON) -> GamePhase {
    let type = json["header", "competitions", 0, "status", "type"]
    if type["completed"].boolValue { return .final }

    switch type["state"].stringValue {
    case "pre": return .pre
    case "in": return .live
    case "post": return .final
    default: return .unknown
    }
}

/// Everything a game's detail sheet shows, read from one summary document.
///
/// The sheets used to fetch the same summary twice per refresh — once for the
/// box score, once for the venue — and never stopped, even for a game long
/// finished. One fetch now fills both, and the phase decides when to ask
/// again (see `refreshInterval`).
///
/// The `download…GameDetail` loaders return `nil` when the fetch produced no
/// document, so a sheet keeps its last good box score through a transient
/// failure instead of flickering to "No game statistics".
struct GameDetail<Stats: Sendable>: Sendable {
    var stats: [Stats]
    var info: GameInfo
    var phase: GamePhase

    init(json: JSON, team: Team, stats: [Stats]) {
        self.stats = stats
        self.info = parseGameInfo(from: json, team: team)
        self.phase = parseGamePhase(from: json)
    }

    /// How long a detail sheet waits before refetching, or `nil` to stop.
    ///
    /// A live game refreshes every ten seconds. One not yet started only needs
    /// to notice kickoff, so it checks once a minute; a finished game will not
    /// change again. A document with no status is retried at the live rate.
    /// How long a detail sheet waits after a fetch that produced no document.
    /// Longer than the live rate, so a rate-limited sheet backs off.
    static var retryInterval: Duration { .seconds(30) }

    var refreshInterval: Duration? {
        switch phase {
        case .live, .unknown: return .seconds(10)
        case .pre: return .seconds(60)
        case .final: return nil
        }
    }
}

/// Reads the venue details shown behind a game's detail sheet.
///
/// The accent colour follows the host: at home the team's own colour is used,
/// and away the colour comes from whichever competitor is not the followed
/// team.
func parseGameInfo(from json: JSON, team: Team) -> GameInfo {
    let venue = json["gameInfo"]["venue"]
    let city = venue["address"]["city"].stringValue

    let color: String
    if city == team.homeCity {
        color = team.brandHex
    } else if json["boxscore", "teams", 0, "team", "shortDisplayName"].stringValue == team.boxscoreName {
        color = json["boxscore", "teams", 1, "team", "color"].stringValue
    } else {
        color = json["boxscore", "teams", 0, "team", "color"].stringValue
    }

    return GameInfo(
        venueImage: venue["images", 0, "href"].stringValue,
        city: city,
        state: venue["address"]["state"].stringValue,
        capacity: venue["capacity"].stringValue,
        attendance: json["gameInfo"]["attendance"].stringValue,
        gameColor: color
    )
}

/// Loads a basketball game's detail sheet: box score, venue and phase.
func downloadBasketballGameDetail(gameID: String, team: Team) async -> GameDetail<BasketballGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseBasketballGameTeamStats(from: json))
}

/// Extracts both teams' box score lines from a basketball game's summary
/// document.
///
/// Statistics are addressed by position because the feed lists them in a fixed
/// order without stable identifiers.
func parseBasketballGameTeamStats(from json: JSON) -> [BasketballGameTeamStats] {
    let competitors = json["header", "competitions", 0, "competitors"]
    let gameClock = json["header", "competitions", 0, "status", "type", "detail"].stringValue

    /// College basketball scores arrive per period — two halves, then one
    /// entry per overtime — so a team's total is the sum of all its line
    /// scores.
    func lineScoreTotal(_ index: Int) -> Int {
        competitors[index]["linescores"].reduce(0) { total, period in
            total + period.1["displayValue"].intValue
        }
    }

    let jayhawksAreFirst = competitors[0]["team"]["name"].stringValue == "Jayhawks"
    let teamScore = lineScoreTotal(jayhawksAreFirst ? 0 : 1)
    let opponentScore = lineScoreTotal(jayhawksAreFirst ? 1 : 0)

    return json["boxscore"]["teams"].enumerated().map { index, element in
        let team = element.1
        let statistics = team["statistics"]

        return BasketballGameTeamStats(
            name: team["team"]["name"].stringValue,
            fieldGoals: statistics[0]["displayValue"].stringValue,
            fieldGoalPct: statistics[1]["displayValue"].floatValue,
            threePoints: statistics[2]["displayValue"].stringValue,
            threePointPct: statistics[3]["displayValue"].floatValue,
            freeThrows: statistics[4]["displayValue"].stringValue,
            freeThrowPct: statistics[5]["displayValue"].floatValue,
            offensiveRebounds: statistics[7]["displayValue"].intValue,
            defensiveRebounds: statistics[8]["displayValue"].intValue,
            assists: statistics[10]["displayValue"].intValue,
            steals: statistics[11]["displayValue"].intValue,
            blocks: statistics[12]["displayValue"].intValue,
            turnOvers: statistics[13]["displayValue"].intValue,
            fouls: statistics[19]["displayValue"].intValue,
            largestLead: statistics[20]["displayValue"].intValue,
            // The box score lists the away team first, matching the
            // predictor's away/home pair.
            projection: index == 0
                ? json["predictor"]["awayTeam"]["gameProjection"].floatValue
                : json["predictor"]["homeTeam"]["gameProjection"].floatValue,
            score: teamScore,
            opponentScore: opponentScore,
            gameClock: gameClock
        )
    }
}

/// Loads a football game's detail sheet: box score, venue and phase.
func downloadFootballGameDetail(gameID: String, team: Team) async -> GameDetail<FootballGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseFootballGameTeamStats(from: json))
}

/// Extracts both teams' box score lines from a football game's summary
/// document.
func parseFootballGameTeamStats(from json: JSON) -> [FootballGameTeamStats] {
    let competitors = json["header", "competitions", 0, "competitors"]
    let gameClock = json["header", "competitions", 0, "status", "type", "detail"].stringValue

    let chiefsAreFirst = competitors[0]["team"]["name"].stringValue == "Chiefs"
    let teamScore = competitors[chiefsAreFirst ? 0 : 1]["score"].intValue
    let opponentScore = competitors[chiefsAreFirst ? 1 : 0]["score"].intValue

    return json["boxscore"]["teams"].map { _, team in
        let statistics = team["statistics"]

        return FootballGameTeamStats(
            name: team["team"]["name"].stringValue,
            yards: statistics[7]["displayValue"].intValue,
            passingYards: statistics[10]["displayValue"].intValue,
            rushingYards: statistics[15]["displayValue"].intValue,
            firstDowns: statistics[0]["displayValue"].intValue,
            drives: statistics[9]["displayValue"].intValue,
            score: teamScore,
            interceptions: statistics[13]["displayValue"].intValue,
            possesionTime: statistics[24]["displayValue"].stringValue,
            completionAttempts: statistics[11]["displayValue"].intValue,
            opponentScore: opponentScore,
            gameClock: gameClock
        )
    }
}
/// Reads one statistic's node from a box-score team's statistics listing.
///
/// MLB nests its team statistics under named groups (`batting`, `pitching`,
/// `fielding`) where the same stat name recurs across groups (`hits` is in all
/// three, counting different things), so a group name can be required. MLS
/// lists its statistics flat, with no groups.
func boxscoreStatistic(_ statistics: JSON, named name: String, in group: String? = nil) -> JSON {
    for (_, section) in statistics {
        if let group {
            guard section["name"].stringValue == group else { continue }
        } else if section["name"].stringValue == name {
            // Flat listing (MLS): the section itself is the stat.
            return section
        }
        for (_, stat) in section["stats"] where stat["name"].stringValue == name {
            return stat
        }
    }
    return .null
}

/// Extracts both teams' box-score lines from a baseball game's summary
/// document. Runs and hits come from the batting group, errors from fielding.
func parseBaseballGameTeamStats(from json: JSON) -> [BaseballGameTeamStats] {
    json["boxscore", "teams"].map { _, team in
        let statistics = team["statistics"]

        return BaseballGameTeamStats(
            name: team["team", "shortDisplayName"].stringValue,
            homeAway: team["homeAway"].stringValue,
            runs: boxscoreStatistic(statistics, named: "runs", in: "batting").intValue,
            hits: boxscoreStatistic(statistics, named: "hits", in: "batting").intValue,
            errors: boxscoreStatistic(statistics, named: "errors", in: "fielding").intValue
        )
    }
}

/// Loads a baseball game's detail sheet: box score, venue and phase.
func downloadBaseballGameDetail(gameID: String, team: Team) async -> GameDetail<BaseballGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseBaseballGameTeamStats(from: json))
}

/// Extracts both teams' box-score lines from a soccer game's summary
/// document.
///
/// The MLS box score publishes match events but not goals: the scoreline
/// lives on the header competitor for the same side, so goals are matched by
/// `homeAway`.
func parseSoccerGameTeamStats(from json: JSON) -> [SoccerGameTeamStats] {
    let competitors = json["header", "competitions", 0, "competitors"]

    func goals(side: String) -> Int {
        for (_, competitor) in competitors where competitor["homeAway"].stringValue == side {
            return competitor["score"].intValue
        }
        return 0
    }

    return json["boxscore", "teams"].map { _, team in
        let statistics = team["statistics"]
        let side = team["homeAway"].stringValue

        return SoccerGameTeamStats(
            name: team["team", "shortDisplayName"].stringValue,
            homeAway: side,
            goals: goals(side: side),
            shots: boxscoreStatistic(statistics, named: "totalShots").intValue,
            possessionPct: boxscoreStatistic(statistics, named: "possessionPct").floatValue,
            corners: boxscoreStatistic(statistics, named: "wonCorners").intValue
        )
    }
}

/// Loads a soccer game's detail sheet: box score, venue and phase.
func downloadSoccerGameDetail(gameID: String, team: Team) async -> GameDetail<SoccerGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseSoccerGameTeamStats(from: json))
}
