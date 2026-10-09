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
    /// The completions: the leading figure of the feed's `"18/29"`.
    var completionAttempts: Int
    var opponentScore: Int
    var gameClock: String
    /// Completions and attempts as the feed writes them, `"18/29"`.
    var completionAttemptsDisplay = ""

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

/// The current score of a game, as its league's scoreboard (see
/// `LeagueScoreboardCenter`) or its summary document reports it.
///
/// Schedule cards need nothing livelier than the two team totals; the full
/// box-score loaders behind the detail sheets fetch far more than a card
/// renders.
struct LiveGameScore: Sendable, Hashable {
    var score: Int
    var opponentScore: Int
}

/// Reads a competitor's score, or `nil` when it has none.
///
/// The summary header and the league scoreboards publish `score` as a bare
/// string (`"3"`); the schedule feed wraps it as
/// `{"value": 3.0, "displayValue": "3"}`. Both are accepted.
func competitorScore(_ competitor: JSON) -> Int? {
    let score = competitor["score"]
    return score.dictionary == nil ? score.int : score["displayValue"].int
}

/// Extracts the current score from a game's summary document.
///
/// `isHome` is the schedule feed's `gameHome` flag for the followed team, and
/// the home/away side is the primary key; the competitor's `team.id` only
/// decides when a header omits `homeAway`.
///
/// Returns `nil` when the document cannot be attributed, so a caller can keep
/// its last known figures instead of painting a partial response as a 0–0
/// game. Schedule cards now read their scores from the league scoreboard
/// (`parseScoreboard`); this reads the same figures from a summary.
///
/// Test support only: no production code calls it. The parser tests use it
/// to pin the summary's score shape (`GoldenParserTests`,
/// `BoxScoreParsingTests`).
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
    /// In progress, the clock running.
    case live
    /// In progress but stopped: halftime, a weather delay, a suspension.
    case paused
    /// Over — played out, or called off.
    case final
    /// The document carried no status, e.g. a partial response.
    case unknown
}

/// The in-progress statuses (`status.type.name`) whose clock is stopped for
/// minutes at a time, so a sheet has nothing to refresh every ten seconds.
private let pausedStatusNames: Set<String> = [
    "STATUS_HALFTIME", "STATUS_DELAYED", "STATUS_RAIN_DELAY", "STATUS_SUSPENDED",
]

/// Reads the game's phase from the header of its summary document.
func parseGamePhase(from json: JSON) -> GamePhase {
    let type = json["header", "competitions", 0, "status", "type"]
    if type["completed"].boolValue { return .final }

    switch type["state"].stringValue {
    case "pre": return .pre
    case "in": return pausedStatusNames.contains(type["name"].stringValue) ? .paused : .live
    case "post": return .final
    default: return .unknown
    }
}

/// The status beneath a game sheet's scoreline: "Final", "Halftime", or
/// the period and clock.
///
/// The sheet reads it from each refreshed summary rather than from the
/// `Game` it was opened with, whose period and clock froze at the tap and
/// which never turned "Final" (A-2).
struct GameStatus: Hashable, Sendable {
    var completed: Bool
    var halftime: Bool
    /// The period as the feed numbers it (`"2"`); see
    /// `LeagueDescriptor.liveCardPeriodLabel(_:)`.
    var period: String
    /// The game clock as the feed writes it (`"4:12"`, `"67'"`).
    var clock: String
    /// The feed's own one-line status (`"Final/OT"`, `"2nd - 4:12"`); empty
    /// for a status taken from a `Game`.
    var detail: String = ""
}

extension GameStatus {
    /// The status the schedule feed gave `game` when it was tapped.
    init(game: Game) {
        self.init(
            completed: game.completed,
            halftime: game.gameHalftime,
            period: game.gamePeriod,
            clock: game.gameClock
        )
    }

    /// The status a sheet shows: the last one a summary gave, or the
    /// tapped `game`'s while none has loaded.
    static func shown(refreshed: GameStatus?, tapped game: Game) -> GameStatus {
        refreshed ?? GameStatus(game: game)
    }
}

/// Reads the game's status from the header of its summary document, or
/// `nil` when the document carries none (a partial response), so a sheet
/// keeps the status it already shows.
func parseGameStatus(from json: JSON) -> GameStatus? {
    let status = json["header", "competitions", 0, "status"]
    let type = status["type"]
    guard type.dictionary != nil else { return nil }

    return GameStatus(
        completed: type["completed"].boolValue,
        // The schedule feed's test, and the paused status's name.
        halftime: type["description"].stringValue == "Halftime"
            || type["name"].stringValue == "STATUS_HALFTIME",
        period: status["period"].stringValue,
        clock: status["displayClock"].stringValue,
        detail: type["detail"].stringValue
    )
}

/// Everything a game's detail sheet shows, read from one summary document.
///
/// The sheets used to fetch the same summary twice per refresh — once for the
/// box score, once for the venue — and never stopped, even for a game long
/// finished. One fetch now fills both (`LeagueDescriptor.gameSheet`), and the
/// phase decides when to ask again (see `refreshInterval`).
struct GameDetail<Stats: Sendable>: Sendable {
    var stats: [Stats]
    var info: GameInfo
    var phase: GamePhase
    /// `nil` when the document carries no status. See `parseGameStatus`.
    var status: GameStatus?

    init(json: JSON, team: TeamRef, stats: [Stats]) {
        self.stats = stats
        self.info = parseGameInfo(from: json, team: team)
        self.phase = parseGamePhase(from: json)
        self.status = parseGameStatus(from: json)
    }

    /// How long a detail sheet waits after a fetch that produced no document.
    /// Longer than the live rate; a throttled sheet doubles it from here (see
    /// `PollBackoff`).
    static var retryInterval: Duration { .seconds(30) }

    /// How long a detail sheet waits before refetching, or `nil` to stop.
    ///
    /// Only a game in progress with its clock running (`state` `"in"`)
    /// refreshes every ten seconds. One not yet started only needs to notice
    /// kickoff, and one at halftime or in a delay to notice the restart, so
    /// those check once a minute, as does a document with no status. A
    /// finished game will not change again.
    var refreshInterval: Duration? {
        switch phase {
        case .live: return .seconds(10)
        case .pre, .paused, .unknown: return .seconds(60)
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

/// Extracts both teams' box score lines from a basketball game's summary
/// document. Every line carries `team`'s score first.
///
/// Statistics are read by `name` (`boxscoreStatistic`). They used to be read
/// by position, and the feed's list had shifted under that reading: from
/// assists on, every figure was its neighbour's. College, NBA and WNBA
/// summaries all name the same statistics.
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

        func stat(_ name: String) -> JSON {
            boxscoreStatistic(statistics, named: name)["displayValue"]
        }

        return BasketballGameTeamStats(
            name: team["team"]["name"].stringValue,
            fieldGoals: stat("fieldGoalsMade-fieldGoalsAttempted").stringValue,
            fieldGoalPct: stat("fieldGoalPct").floatValue,
            threePoints: stat("threePointFieldGoalsMade-threePointFieldGoalsAttempted").stringValue,
            threePointPct: stat("threePointFieldGoalPct").floatValue,
            freeThrows: stat("freeThrowsMade-freeThrowsAttempted").stringValue,
            freeThrowPct: stat("freeThrowPct").floatValue,
            offensiveRebounds: stat("offensiveRebounds").intValue,
            defensiveRebounds: stat("defensiveRebounds").intValue,
            assists: stat("assists").intValue,
            steals: stat("steals").intValue,
            blocks: stat("blocks").intValue,
            turnOvers: stat("turnovers").intValue,
            fouls: stat("fouls").intValue,
            largestLead: stat("largestLead").intValue,
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

/// Extracts both teams' box score lines from a football game's summary
/// document. Every line carries `team`'s score first.
///
/// Statistics are read by `name`: the NFL lists 25, college football 15 in
/// another order, so no one position fits both. A statistic a feed does not
/// carry (college football has no `totalDrives`; a pre-game summary lists
/// only season averages) reads as zero. `interceptions` appears twice in the
/// NFL list, with the same value; the first is read.
func parseFootballGameTeamStats(from json: JSON, team followed: TeamRef) -> [FootballGameTeamStats] {
    let competitors = json["header", "competitions", 0, "competitors"]
    let gameClock = json["header", "competitions", 0, "status", "type", "detail"].stringValue

    let followedIsFirst = competitors[0]["team"]["id"].stringValue == followed.espnID
    let teamScore = competitors[followedIsFirst ? 0 : 1]["score"].intValue
    let opponentScore = competitors[followedIsFirst ? 1 : 0]["score"].intValue

    return json["boxscore"]["teams"].map { _, team in
        let statistics = team["statistics"]

        func stat(_ name: String) -> JSON {
            boxscoreStatistic(statistics, named: name)["displayValue"]
        }

        return FootballGameTeamStats(
            name: team["team"]["name"].stringValue,
            yards: stat("totalYards").intValue,
            passingYards: stat("netPassingYards").intValue,
            rushingYards: stat("rushingYards").intValue,
            firstDowns: stat("firstDowns").intValue,
            drives: stat("totalDrives").intValue,
            score: teamScore,
            interceptions: stat("interceptions").intValue,
            possesionTime: stat("possessionTime").stringValue,
            completionAttempts: stat("completionAttempts").intValue,
            opponentScore: opponentScore,
            gameClock: gameClock,
            completionAttemptsDisplay: stat("completionAttempts").stringValue
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
            row("Completion Attempts") { $0.completionAttemptsDisplay.isEmpty ? "\($0.completionAttempts)" : $0.completionAttemptsDisplay },
        ]
        // College feeds carry no `totalDrives`: a row of zeros is no row.
        if home.drives == 0 && away.drives == 0 {
            rows.removeAll { $0.title == "Drives" }
        }
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
    /// The period-by-period score, sized from the summary's own format.
    /// `nil` when the header does not list both sides.
    var linescore: Linescore?
    /// A hockey game's skater and goalie tables; `nil` for other sports.
    var hockey: HockeyBoxScore?
    /// A soccer game's lineups; `nil` for other sports, or a summary with
    /// no rosters yet.
    var soccerLineups: SoccerLineups?
    /// The timeline, win probability and injuries (R-2); empty parts for a
    /// summary that carries none.
    var story: GameStory = .empty
    var info: GameInfo
    var phase: GamePhase
    /// The status line beneath the scoreline; `nil` when the summary
    /// carries no status.
    var status: GameStatus?
    /// How long to wait before refetching, or `nil` to stop.
    var refreshInterval: Duration?

    init<Stats: Sendable>(_ detail: GameDetail<Stats>, boxScore: ([Stats]) -> BoxScore?) {
        self.boxScore = boxScore(detail.stats)
        self.info = detail.info
        self.phase = detail.phase
        self.status = detail.status
        self.refreshInterval = detail.refreshInterval
    }

    /// How long a sheet waits after a fetch that produced no document.
    static var retryInterval: Duration { GameDetail<BoxScore>.retryInterval }
}

/// One refresh of a detail sheet: the sheet, or `nil` when the fetch
/// produced no document, and the response it came from, which paces the
/// next refresh.
struct GameSheetLoad: Sendable {
    var sheet: GameSheet?
    var response: FetchResponse
}

extension LeagueDescriptor {
    /// Reads a game's detail sheet from its summary document with the
    /// league's sport's parser: the box score, the venue and the phase all
    /// come from this one document.
    ///
    /// - Parameter followedIsHome: the schedule's `gameHome` for the game;
    ///   basketball and football lines carry the followed team's score first.
    func gameSheet(from json: JSON, team: TeamRef, followedIsHome: Bool) -> GameSheet {
        var sheet: GameSheet
        switch kind {
        case .basketball:
            let detail = GameDetail(json: json, team: team, stats: parseBasketballGameTeamStats(from: json, team: team))
            sheet = GameSheet(detail) { BoxScore(basketball: $0, followedIsHome: followedIsHome) }
        case .football:
            let detail = GameDetail(json: json, team: team, stats: parseFootballGameTeamStats(from: json, team: team))
            sheet = GameSheet(detail) { BoxScore(football: $0, followedIsHome: followedIsHome) }
        case .baseball:
            let detail = GameDetail(json: json, team: team, stats: parseBaseballGameTeamStats(from: json))
            sheet = GameSheet(detail) { BoxScore(baseball: $0) }
        case .soccer:
            let detail = GameDetail(json: json, team: team, stats: parseSoccerGameTeamStats(from: json))
            sheet = GameSheet(detail) { BoxScore(soccer: $0) }
            sheet.soccerLineups = SoccerLineups(summary: json)
        case .hockey:
            // The comparison strip is the box score's rows; the skater and
            // goalie tables ride alongside.
            let hockey = HockeyBoxScore(summary: json)
            let detail = GameDetail(json: json, team: team, stats: hockey.map { [$0] } ?? [])
            sheet = GameSheet(detail) { lines in lines.first.map(BoxScore.init(hockey:)) }
            sheet.hockey = hockey
        case .other:
            // No box-score parser for this sport: the venue and phase only.
            sheet = GameSheet(GameDetail<BoxScore>(json: json, team: team, stats: [])) { _ in nil }
        }
        // Every sport's periods come from the same reader, sized by the
        // summary's `format`.
        sheet.linescore = Linescore(summary: json, league: self)
        // As is the story, from whichever lists the sport's summary carries.
        sheet.story = GameStory(summary: json)
        return sheet
    }

    /// Loads a game's detail sheet in this league: one summary request per
    /// call, whatever the sport. See `gameSheet(from:team:followedIsHome:)`.
    ///
    /// - Parameter competition: the competition the game belongs to
    ///   (`Game.competition`). A cup tie's summary is asked for under the
    ///   cup's path; `nil` means the team's league.
    func downloadGameSheet(
        gameID: String,
        team: TeamRef,
        followedIsHome: Bool,
        competition: LeagueID? = nil,
        client: HTTPClient = .shared
    ) async -> GameSheetLoad {
        let summaryURL = (competition ?? team.league).summaryURL(gameID: gameID)
        let response = await client.fetchResponse(summaryURL)
        let sheet = response.result.document.map {
            gameSheet(from: $0, team: team, followedIsHome: followedIsHome)
        }
        return GameSheetLoad(sheet: sheet, response: response)
    }
}
