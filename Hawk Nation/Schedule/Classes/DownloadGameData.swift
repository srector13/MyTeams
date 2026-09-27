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
/// `isHome` is the schedule feed's `gameHome` flag for the followed team, and
/// the home/away side is the primary key; the competitor's `team.id` only
/// decides when a header omits `homeAway`.
///
/// Returns `nil` when the fetch failed or the document cannot be attributed,
/// so a caller can keep its last known figures instead of painting a
/// rate-limited or partial response as a 0–0 game.
func downloadLiveGameScore(gameID: String, team: TeamRef, isHome: Bool) async -> LiveGameScore? {
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
func parseLiveGameScore(from json: JSON, team: TeamRef, isHome: Bool) -> LiveGameScore? {
    var score: Int?
    var opponentScore: Int?
    for (_, competitor): (String, JSON) in json["header", "competitions", 0, "competitors"] {
        let followedTeam: Bool
        let side = competitor["homeAway"].stringValue
        if side == "home" || side == "away" {
            followedTeam = side == (isHome ? "home" : "away")
        } else {
            followedTeam = competitor["team"]["id"].stringValue == team.espnID
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
    /// The document carried no status, e.g. a partial response.
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

    init(json: JSON, team: TeamRef, stats: [Stats]) {
        self.stats = stats
        self.info = parseGameInfo(from: json, team: team)
        self.phase = parseGamePhase(from: json)
    }

    /// How long a detail sheet waits after a fetch that produced no document.
    /// Longer than the live rate, so a rate-limited sheet backs off.
    static var retryInterval: Duration { .seconds(30) }

    /// How long a detail sheet waits before refetching, or `nil` to stop.
    ///
    /// A live game refreshes every ten seconds. One not yet started only needs
    /// to notice kickoff, so it checks once a minute; a finished game will not
    /// change again. A document with no status is retried at the live rate.
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
/// The accent colour follows the host: when the box score lists the followed
/// team (by `team.id`) as home, the team's own colour is used; otherwise the
/// colour comes from whichever box-score team is not the followed one.
func parseGameInfo(from json: JSON, team: TeamRef) -> GameInfo {
    let venue = json["gameInfo"]["venue"]
    let city = venue["address"]["city"].stringValue

    let boxscoreTeams = json["boxscore", "teams"].map { $0.1 }
    let followed = boxscoreTeams.first { $0["team", "id"].stringValue == team.espnID }
    let color: String
    if followed?["homeAway"].stringValue == "home" {
        color = team.colorHex
    } else {
        let host = boxscoreTeams.first { $0["team", "id"].stringValue != team.espnID }
        color = host?["team", "color"].stringValue ?? ""
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
func downloadBasketballGameDetail(gameID: String, team: TeamRef) async -> GameDetail<BasketballGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseBasketballGameTeamStats(from: json, team: team))
}

/// Extracts both teams' box score lines from a basketball game's summary
/// document. Every line carries `team`'s score first.
///
/// Statistics are addressed by position because the feed lists them in a fixed
/// order without stable identifiers.
func parseBasketballGameTeamStats(from json: JSON, team followed: TeamRef) -> [BasketballGameTeamStats] {
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

    let followedIsFirst = competitors[0]["team"]["id"].stringValue == followed.espnID
    let teamScore = lineScoreTotal(followedIsFirst ? 0 : 1)
    let opponentScore = lineScoreTotal(followedIsFirst ? 1 : 0)

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
func downloadFootballGameDetail(gameID: String, team: TeamRef) async -> GameDetail<FootballGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseFootballGameTeamStats(from: json, team: team))
}

/// Extracts both teams' box score lines from a football game's summary
/// document. Every line carries `team`'s score first.
func parseFootballGameTeamStats(from json: JSON, team followed: TeamRef) -> [FootballGameTeamStats] {
    let competitors = json["header", "competitions", 0, "competitors"]
    let gameClock = json["header", "competitions", 0, "status", "type", "detail"].stringValue

    let followedIsFirst = competitors[0]["team"]["id"].stringValue == followed.espnID
    let teamScore = competitors[followedIsFirst ? 0 : 1]["score"].intValue
    let opponentScore = competitors[followedIsFirst ? 1 : 0]["score"].intValue

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
            runs: boxscoreStatistic(statistics, named: "runs", in: "batting")["displayValue"].intValue,
            hits: boxscoreStatistic(statistics, named: "hits", in: "batting")["displayValue"].intValue,
            errors: boxscoreStatistic(statistics, named: "errors", in: "fielding")["displayValue"].intValue
        )
    }
}

/// Loads a baseball game's detail sheet: box score, venue and phase.
func downloadBaseballGameDetail(gameID: String, team: TeamRef) async -> GameDetail<BaseballGameTeamStats>? {
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
            shots: boxscoreStatistic(statistics, named: "totalShots")["displayValue"].intValue,
            possessionPct: boxscoreStatistic(statistics, named: "possessionPct")["displayValue"].floatValue,
            corners: boxscoreStatistic(statistics, named: "wonCorners")["displayValue"].intValue
        )
    }
}

/// Loads a soccer game's detail sheet: box score, venue and phase.
func downloadSoccerGameDetail(gameID: String, team: TeamRef) async -> GameDetail<SoccerGameTeamStats>? {
    guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
        return nil
    }
    return GameDetail(json: json, team: team, stats: parseSoccerGameTeamStats(from: json))
}

// MARK: - The detail sheet's box score

/// A game's box score as the detail sheet draws it, whatever the sport: the
/// scoreline, then one row per statistic, home side on the left.
struct BoxScore: Hashable, Sendable {
    struct Row: Hashable, Sendable, Identifiable {
        var title: String
        var home: String
        var away: String

        /// Titles are distinct within a sport's box score.
        var id: String { title }
    }

    var homeScore: Int
    var awayScore: Int
    var rows: [Row]

    /// Reads a basketball box score. The lines come away first, home second,
    /// and each carries the followed team's score first.
    init?(basketball lines: [BasketballGameTeamStats], followedIsHome: Bool) {
        guard lines.count >= 2 else { return nil }
        let away = lines[0]
        let home = lines[1]

        func row(_ title: String, _ value: (BasketballGameTeamStats) -> String) -> Row {
            Row(title: title, home: value(home), away: value(away))
        }

        homeScore = followedIsHome ? away.score : away.opponentScore
        awayScore = followedIsHome ? away.opponentScore : away.score
        rows = [
            row("Field Goals") { $0.fieldGoals.replacingOccurrences(of: "-", with: "/") },
            row("Field Goal %") { "\(Int($0.fieldGoalPct))%" },
            row("Three Points") { $0.threePoints.replacingOccurrences(of: "-", with: "/") },
            row("Three Point %") { "\(Int($0.threePointPct))%" },
            row("Free Throws") { $0.freeThrows.replacingOccurrences(of: "-", with: "/") },
            row("Free Throw %") { "\(Int($0.freeThrowPct))%" },
            row("Offensive Rebounds") { "\($0.offensiveRebounds)" },
            row("Defensive Rebounds") { "\($0.defensiveRebounds)" },
            row("Assists") { "\($0.assists)" },
            row("Blocks") { "\($0.blocks)" },
            row("Steals") { "\($0.steals)" },
            row("Turnovers") { "\($0.turnOvers)" },
            row("Fouls") { "\($0.fouls)" },
        ]
    }

    /// Reads a football box score, laid out as `init(basketball:)` describes.
    init?(football lines: [FootballGameTeamStats], followedIsHome: Bool) {
        guard lines.count >= 2 else { return nil }
        let away = lines[0]
        let home = lines[1]

        func row(_ title: String, _ value: (FootballGameTeamStats) -> String) -> Row {
            Row(title: title, home: value(home), away: value(away))
        }

        homeScore = followedIsHome ? away.score : away.opponentScore
        awayScore = followedIsHome ? away.opponentScore : away.score
        rows = [
            row("Total Yards") { "\($0.yards)" },
            row("Passing Yards") { "\($0.passingYards)" },
            row("Rushing Yards") { "\($0.rushingYards)" },
            row("First Downs") { "\($0.firstDowns)" },
            row("Drives") { "\($0.drives)" },
            row("Interceptions") { "\($0.interceptions)" },
            row("Possession Time") { "\($0.possesionTime)" },
            row("Completion Attempts") { "\($0.completionAttempts)" },
        ]
    }

    /// Reads a baseball box score, whose lines carry their own side.
    init?(baseball lines: [BaseballGameTeamStats]) {
        guard let home = lines.first(where: { $0.homeAway == "home" }),
              let away = lines.first(where: { $0.homeAway == "away" })
        else { return nil }

        func row(_ title: String, _ value: (BaseballGameTeamStats) -> String) -> Row {
            Row(title: title, home: value(home), away: value(away))
        }

        homeScore = home.runs
        awayScore = away.runs
        rows = [
            row("Runs") { "\($0.runs)" },
            row("Hits") { "\($0.hits)" },
            row("Errors") { "\($0.errors)" },
        ]
    }

    /// Reads a soccer box score, whose lines carry their own side.
    init?(soccer lines: [SoccerGameTeamStats]) {
        guard let home = lines.first(where: { $0.homeAway == "home" }),
              let away = lines.first(where: { $0.homeAway == "away" })
        else { return nil }

        func row(_ title: String, _ value: (SoccerGameTeamStats) -> String) -> Row {
            Row(title: title, home: value(home), away: value(away))
        }

        homeScore = home.goals
        awayScore = away.goals
        rows = [
            row("Goals") { "\($0.goals)" },
            row("Shots") { "\($0.shots)" },
            row("Possession") { "\(Int($0.possessionPct.rounded()))%" },
            row("Corner Kicks") { "\($0.corners)" },
        ]
    }
}

/// Everything a game's detail sheet draws from one summary fetch, whatever
/// the sport. See `GameDetail`.
struct GameSheet: Sendable {
    /// `nil` when the summary carries no box score for both sides yet.
    var boxScore: BoxScore?
    var info: GameInfo
    /// How long to wait before refetching, or `nil` to stop.
    var refreshInterval: Duration?

    init<Stats: Sendable>(_ detail: GameDetail<Stats>, boxScore: ([Stats]) -> BoxScore?) {
        self.boxScore = boxScore(detail.stats)
        self.info = detail.info
        self.refreshInterval = detail.refreshInterval
    }

    /// How long a sheet waits after a fetch that produced no document.
    static var retryInterval: Duration { GameDetail<BoxScore>.retryInterval }
}

extension LeagueDescriptor {
    /// Loads a game's detail sheet in this league, reading the box score with
    /// the league's sport's parser. `nil` when the fetch produced no document.
    ///
    /// - Parameter followedIsHome: the schedule's `gameHome` for the game;
    ///   basketball and football lines carry the followed team's score first.
    func downloadGameSheet(gameID: String, team: TeamRef, followedIsHome: Bool) async -> GameSheet? {
        switch kind {
        case .basketball:
            guard let detail = await downloadBasketballGameDetail(gameID: gameID, team: team) else { return nil }
            return GameSheet(detail) { BoxScore(basketball: $0, followedIsHome: followedIsHome) }
        case .football:
            guard let detail = await downloadFootballGameDetail(gameID: gameID, team: team) else { return nil }
            return GameSheet(detail) { BoxScore(football: $0, followedIsHome: followedIsHome) }
        case .baseball:
            guard let detail = await downloadBaseballGameDetail(gameID: gameID, team: team) else { return nil }
            return GameSheet(detail) { BoxScore(baseball: $0) }
        case .soccer:
            guard let detail = await downloadSoccerGameDetail(gameID: gameID, team: team) else { return nil }
            return GameSheet(detail) { BoxScore(soccer: $0) }
        case .hockey, .other:
            // No box-score parser for this sport: the venue and phase only.
            guard let json = await HTTPClient.shared.fetch(team.summaryURL(gameID: gameID)).document else {
                return nil
            }
            return GameSheet(GameDetail<BoxScore>(json: json, team: team, stats: [])) { _ in nil }
        }
    }
}
