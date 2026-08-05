//
//  DownloadGameData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The four teams the app follows, and everything that differs between them
/// when reading a game summary.
///
/// Each case's raw value is the logo asset name, which is also the identifier
/// the views pass around to say which team they are showing.
enum Sport: String, Sendable, CaseIterable {
    case jayhawk
    case chiefs
    case royals
    case sporting

    /// The ESPN league path this team's summaries live under.
    var summaryPath: String {
        switch self {
        case .jayhawk: "basketball/mens-college-basketball"
        case .chiefs: "football/nfl"
        case .royals: "baseball/mlb"
        case .sporting: "soccer/usa.1"
        }
    }

    /// How the followed team is named in a summary's `boxscore.teams` entries.
    var boxscoreName: String {
        switch self {
        case .jayhawk: "Kansas"
        case .chiefs: "Chiefs"
        case .royals: "Royals"
        case .sporting: "Kansas City"
        }
    }

    /// The city the team plays home games in.
    var homeCity: String {
        switch self {
        case .jayhawk: "Lawrence"
        case .chiefs, .royals, .sporting: "Kansas City"
        }
    }

    /// The team's own colour, used to tint a home game. Away games take the
    /// host team's colour from the feed instead.
    var homeColor: String {
        switch self {
        case .jayhawk: "0051BA"
        case .chiefs: "E31837"
        case .royals: "004687"
        case .sporting: "002A5C"
        }
    }

    func summaryURL(gameID: String) -> String {
        "https://site.api.espn.com/apis/site/v2/sports/\(summaryPath)/summary?event=\(gameID)"
    }
}

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

struct BaseballGameTeamStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var yards: Float
    var passingYards: Float
    var rushingYards: Float
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String

    /// The pair of blank lines a detail view shows before its box score loads.
    static let placeholderPair = [Self](repeating: BaseballGameTeamStats(
        name: "", yards: 0, passingYards: 0, rushingYards: 0, projection: 0,
        score: 0, opponentScore: 0, gameClock: "test"
    ), count: 2)
}

struct SoccerGameTeamStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var yards: Float
    var passingYards: Float
    var rushingYards: Float
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String

    /// The pair of blank lines a detail view shows before its box score loads.
    static let placeholderPair = [Self](repeating: SoccerGameTeamStats(
        name: "", yards: 0, passingYards: 0, rushingYards: 0, projection: 0,
        score: 0, opponentScore: 0, gameClock: "test"
    ), count: 2)
}

/// Loads the venue details shown behind a game's detail sheet.
///
/// The accent colour follows the host: at home the team's own colour is used,
/// and away the colour comes from whichever competitor is not the followed
/// team.
func downloadGameInfo(gameID: String, sport: Sport) async -> GameInfo {
    let json = await HTTPClient.json(from: sport.summaryURL(gameID: gameID))

    let venue = json["gameInfo"]["venue"]
    let city = venue["address"]["city"].stringValue

    let color: String
    if city == sport.homeCity {
        color = sport.homeColor
    } else if json["boxscore", "teams", 0, "team", "shortDisplayName"].stringValue == sport.boxscoreName {
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

/// Loads a game's venue details by team identifier.
///
/// Views carry the team as the logo asset name; an unrecognised name yields an
/// empty summary rather than a failed request.
func downloadGameInfo(gameID: String, type: String) async -> GameInfo {
    guard let sport = Sport(rawValue: type) else { return .empty }
    return await downloadGameInfo(gameID: gameID, sport: sport)
}

/// Loads both teams' box score lines for a basketball game.
///
/// Statistics are addressed by position because the feed lists them in a fixed
/// order without stable identifiers.
func downloadBasketballGameTeamStatsData(gameID: String) async -> [BasketballGameTeamStats] {
    let json = await HTTPClient.json(from: Sport.jayhawk.summaryURL(gameID: gameID))

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
    let json = await HTTPClient.json(from: Sport.chiefs.summaryURL(gameID: gameID))

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

// The baseball and soccer detail views were never finished: they show a fixed
// layout rather than live figures. These loaders return one placeholder entry
// per team so those views lay out as they always have.

/// Returns a placeholder line per team in a baseball game's box score.
func downloadBaseballGameTeamStatsData(gameID: String) async -> [BaseballGameTeamStats] {
    let json = await HTTPClient.json(from: Sport.royals.summaryURL(gameID: gameID))

    return json["boxscore"]["teams"].map { _, _ in
        BaseballGameTeamStats(
            name: "", yards: 0, passingYards: 0, rushingYards: 0,
            projection: 0, score: 0, opponentScore: 0, gameClock: "test"
        )
    }
}

/// Returns a placeholder line per team in a soccer game's box score.
func downloadSoccerGameTeamStatsData(gameID: String) async -> [SoccerGameTeamStats] {
    let json = await HTTPClient.json(from: Sport.sporting.summaryURL(gameID: gameID))

    return json["boxscore"]["teams"].map { _, _ in
        SoccerGameTeamStats(
            name: "", yards: 0, passingYards: 0, rushingYards: 0,
            projection: 0, score: 0, opponentScore: 0, gameClock: "test"
        )
    }
}
