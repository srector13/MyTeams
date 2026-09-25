//
//  DownloadGameData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct GameInfo: Identifiable, Hashable, Sendable {
    var id = UUID()
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
    var id = UUID()
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
    var id = UUID()
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
    var id = UUID()
    var name: String
    /// `"home"` or `"away"`, as the box score labels this line.
    var homeAway: String
    var runs: Int
    var hits: Int
    var errors: Int
}

/// One team's line in a soccer game's box score. See
/// `BaseballGameTeamStats` for why lines carry their side.
struct SoccerGameTeamStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// `"home"` or `"away"`, as the box score labels this line.
    var homeAway: String
    var goals: Int
    var shots: Int
    var possessionPct: Float
    var corners: Int
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
    let json = await HTTPClient.json(from: team.summaryURL(gameID: gameID))

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
            score = competitor["score"]["displayValue"].intValue
        } else {
            opponentScore = competitor["score"]["displayValue"].intValue
        }
    }

    guard let score, let opponentScore else { return nil }
    return LiveGameScore(score: score, opponentScore: opponentScore)
}

/// Loads the venue details shown behind a game's detail sheet.
///
/// The accent colour follows the host: at home the team's own colour is used,
/// and away the colour comes from whichever competitor is not the followed
/// team.
func downloadGameInfo(gameID: String, team: Team) async -> GameInfo {
    let json = await HTTPClient.json(from: team.summaryURL(gameID: gameID))

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

/// Loads both teams' box score lines for a basketball game.
///
/// Statistics are addressed by position because the feed lists them in a fixed
/// order without stable identifiers.
func downloadBasketballGameTeamStatsData(gameID: String) async -> [BasketballGameTeamStats] {
    let json = await HTTPClient.json(from: Team.jayhawks.summaryURL(gameID: gameID))

    let competitors = json["header", "competitions", 0, "competitors"]
    let gameClock = json["header", "competitions", 0, "status", "type", "detail"].stringValue

    /// College basketball scores arrive per half, so a team's total is the sum
    /// of its line scores.
    func halfTotal(_ index: Int) -> Int {
        competitors[index]["linescores", 0, "displayValue"].intValue
            + competitors[index]["linescores", 1, "displayValue"].intValue
    }

    let jayhawksAreFirst = competitors[0]["team"]["name"].stringValue == "Jayhawks"
    let teamScore = halfTotal(jayhawksAreFirst ? 0 : 1)
    let opponentScore = halfTotal(jayhawksAreFirst ? 1 : 0)

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

/// Loads both teams' box score lines for a football game.
func downloadFootballGameTeamStatsData(gameID: String) async -> [FootballGameTeamStats] {
    let json = await HTTPClient.json(from: Team.chiefs.summaryURL(gameID: gameID))

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

/// Loads both teams' box score lines for a baseball game.
func downloadBaseballGameTeamStatsData(gameID: String) async -> [BaseballGameTeamStats] {
    let json = await HTTPClient.json(from: Team.royals.summaryURL(gameID: gameID))
    return parseBaseballGameTeamStats(from: json)
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

/// Loads both teams' box score lines for a soccer game.
func downloadSoccerGameTeamStatsData(gameID: String) async -> [SoccerGameTeamStats] {
    let json = await HTTPClient.json(from: Team.sporting.summaryURL(gameID: gameID))
    return parseSoccerGameTeamStats(from: json)
}
