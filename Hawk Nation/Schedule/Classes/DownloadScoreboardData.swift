//
//  DownloadScoreboardData.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// The day ESPN files a game under on its scoreboards: the calendar date of
/// its start in US Eastern time. A Sunday-night kickoff at 00:20Z Monday is
/// on Sunday's board.
private let scoreboardDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "yyyyMMdd"
    return formatter
}()

/// The `dates` value of the scoreboard listing a game that starts at `date`,
/// e.g. `"20260927"`. See `LeagueID.scoreboardURL(day:)`.
func scoreboardDay(for date: Date) -> String {
    scoreboardDayFormatter.string(from: date)
}

/// One side of a game on a league scoreboard.
struct ScoreboardCompetitor: Sendable, Hashable {
    /// The competitor's ESPN team id.
    var teamID: String
    /// `"home"` or `"away"`, as the scoreboard labels it.
    var homeAway: String
    /// `nil` when the scoreboard gives no readable score.
    var score: Int?
}

/// One side of a game as a league scoreboard names and ranks it, for Home's
/// Around Your Leagues rows (`HomeLeagueGame`), which list games between
/// teams the reader doesn't follow and so can't look them up anywhere else.
/// Kept apart from `ScoreboardCompetitor`, whose identity the score fan-out
/// compares, so a renamed crest never reads as a changed score.
struct ScoreboardTeam: Sendable, Hashable {
    /// `team.abbreviation`, `"KC"`; empty when the board gives none.
    var abbreviation: String = ""
    /// `team.shortDisplayName`, `"Chiefs"`, `"San José St"`.
    var shortName: String = ""
    /// `team.displayName`, `"Kansas City Chiefs"`.
    var displayName: String = ""
    /// `team.location`, `"Kansas City"`.
    var location: String = ""
    /// `team.logo`, the scoreboard's crest.
    var logoURL: URL? = nil
    /// `team.color` and `team.alternateColor`, six hex digits, or empty.
    var colorHex: String = ""
    var alternateColorHex: String = ""
    /// The competitor's `curatedRank.current` in a college poll, 1 to 25;
    /// `nil` when unranked, which the board writes as 99, or not given.
    var rank: Int? = nil
    /// The competitor's `winner` flag, set once a game is decided.
    var winner: Bool = false

    /// The name a compact row shows: the short name, else the abbreviation.
    var rowName: String {
        if !shortName.isEmpty { return shortName }
        if !abbreviation.isEmpty { return abbreviation }
        return displayName
    }

    /// The poll's unranked marker and anything outside a top 25 read as
    /// unranked.
    static func pollRank(_ value: Int?) -> Int? {
        guard let value, (1...25).contains(value) else { return nil }
        return value
    }
}

/// One game on a league scoreboard, reduced to what the schedule cards need.
struct ScoreboardGame: Sendable, Hashable {
    /// The competition id, which is the schedule's `Game.gameID`.
    var gameID: String
    /// `status.type.state`: `"pre"`, `"in"` or `"post"`.
    var state: String
    /// `status.type.completed`: a `"post"` game that was played out, not
    /// called off.
    var completed: Bool
    var competitors: [ScoreboardCompetitor]
    /// `status.period`: the quarter, half, period or inning; 0 before the
    /// start. For score alerts (`ScoreAlertEngine`).
    var period: Int = 0
    /// Each competitor's `team.shortDisplayName`, by ESPN team id; a team
    /// the board gives no name for has no entry. For score alerts.
    var teamNames: [String: String] = [:]
    /// `status.displayClock`: `"12:34"`, `"67'"`, `"90'+5'"`; `"0:00"` where
    /// the sport keeps no clock. For Live Activities (`LiveActivityManager`).
    var clock: String = ""
    /// The competition's `date`, its scheduled start. For Live Activities.
    var startDate: Date? = nil
    /// Each competitor's names, crest, colours, poll rank and `winner` flag,
    /// by ESPN team id. For Home's Around Your Leagues rows.
    var teams: [String: ScoreboardTeam] = [:]
    /// `status.type.shortDetail`: `"0:48 - 4th"`, `"Final/OT"`, `"FT"`,
    /// `"9/28 - 8:15 PM EDT"`, `"Canceled"`.
    var statusDetail: String = ""
    /// `status.type.description == "Halftime"`.
    var halftime: Bool = false
    /// Called off, as `gameCalledOff` reads the status: cancelled for good,
    /// or postponed to another day.
    var cancelled: Bool = false
    var postponed: Bool = false
    /// The national broadcast, `competition.broadcast` (`"CBS"`), else the
    /// first of `broadcasts[].names`; empty when the board names none.
    var broadcast: String = ""
    /// `competition.venue.fullName`.
    var venue: String = ""
    /// `competition.neutralSite`: a bowl, a tournament site.
    var neutralSite: Bool = false
    /// The event's `name`, `"Los Angeles Rams at Denver Broncos"`.
    var name: String = ""

    /// The away side of a two-team game, then the home side; `nil` for a
    /// game the board doesn't list as one team at the other.
    var awayAndHome: (away: ScoreboardCompetitor, home: ScoreboardCompetitor)? {
        guard competitors.count == 2,
              let home = competitors.first(where: { $0.homeAway == "home" }),
              let away = competitors.first(where: { $0.homeAway == "away" })
        else { return nil }
        return (away, home)
    }

    /// The score as `teamID` sees it, or `nil` when the game does not list
    /// that team against one opponent, or has no score worth showing yet.
    ///
    /// A game not yet started reads 0–0 on the scoreboard, and a cancelled
    /// or postponed one (`"post"` without `completed`) keeps that 0–0, so
    /// only games under way or played out carry a score.
    func liveScore(for teamID: String) -> LiveGameScore? {
        guard state == "in" || (state == "post" && completed),
              let followed = competitors.first(where: { $0.teamID == teamID }),
              let opponent = self.opponent(of: teamID),
              let score = followed.score,
              let opponentScore = opponent.score
        else { return nil }
        return LiveGameScore(score: score, opponentScore: opponentScore)
    }

    /// The other side of a two-team game `teamID` plays in.
    func opponent(of teamID: String) -> ScoreboardCompetitor? {
        guard competitors.count == 2, competitors.contains(where: { $0.teamID == teamID }) else { return nil }
        return competitors.first { $0.teamID != teamID }
    }
}

/// One team's game on a league scoreboard, as `LeagueScoreboardCenter` fans
/// it out to each favorite.
struct ScoreboardLine: Sendable, Hashable {
    var gameID: String
    /// The opponent's ESPN team id, for matching a game whose id the
    /// schedule does not share (see `LeagueScoreboardCenter.liveScore`).
    var opponentID: String
    var score: LiveGameScore
}

/// Every game on one league's scoreboard for one day.
struct LeagueScoreboard: Sendable, Hashable {
    var games: [ScoreboardGame]

    /// The games `teamID` has a score in, read from this one document.
    func lines(for teamID: String) -> [ScoreboardLine] {
        games.compactMap { game in
            guard let score = game.liveScore(for: teamID),
                  let opponent = game.opponent(of: teamID)
            else { return nil }
            return ScoreboardLine(gameID: game.gameID, opponentID: opponent.teamID, score: score)
        }
    }
}

/// Reads a league scoreboard document.
///
/// Every value is found by name — the competition's `id`, its
/// `status.type`, each competitor's `team.id` and `homeAway` — never by
/// position. Events or competitions that are not objects, games with no id,
/// and competitors with no team id are skipped rather than read as zeros.
/// Scores come as bare strings (`"23"`); the schedule feed's wrapped form
/// (`{"displayValue": "23"}`) is read too (`competitorScore`).
func parseScoreboard(from json: JSON) -> LeagueScoreboard {
    var games: [ScoreboardGame] = []
    for (_, event) in json["events"] where event.dictionary != nil {
        for (_, competition) in event["competitions"] where competition.dictionary != nil {
            var gameID = competition["id"].stringValue
            if gameID.isEmpty { gameID = event["id"].stringValue }
            guard !gameID.isEmpty else { continue }

            // The competition carries its own status; the event's is the
            // same object on every board seen so far.
            var status = competition["status", "type"]
            if status.dictionary == nil { status = event["status", "type"] }
            var period = competition["status", "period"]
            if period.int == nil { period = event["status", "period"] }
            var clock = competition["status", "displayClock"]
            if clock.string == nil { clock = event["status", "displayClock"] }
            var date = competition["date"]
            if date.string == nil { date = event["date"] }

            var teamNames: [String: String] = [:]
            var teams: [String: ScoreboardTeam] = [:]
            for (_, competitor) in competition["competitors"] {
                let teamID = competitor["team", "id"].stringValue
                guard !teamID.isEmpty else { continue }
                teams[teamID] = scoreboardTeam(competitor)
                // No name rather than an empty one, so readers fall back
                // ("Home", "Away") instead of showing a blank.
                let name = competitor["team", "shortDisplayName"].stringValue
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                teamNames[teamID] = name
            }

            var broadcast = competition["broadcast"].stringValue
                .trimmingCharacters(in: .whitespaces)
            if broadcast.isEmpty {
                broadcast = competition["broadcasts", 0, "names", 0].stringValue
                    .trimmingCharacters(in: .whitespaces)
            }
            let calledOff = gameCalledOff(status)
            var name = event["name"].stringValue
            if name.isEmpty { name = event["shortName"].stringValue }

            let competitors: [ScoreboardCompetitor] = competition["competitors"].compactMap { _, competitor in
                let teamID = competitor["team", "id"].stringValue
                guard !teamID.isEmpty else { return nil }
                return ScoreboardCompetitor(
                    teamID: teamID,
                    homeAway: competitor["homeAway"].stringValue,
                    score: competitorScore(competitor)
                )
            }

            games.append(ScoreboardGame(
                gameID: gameID,
                state: status["state"].stringValue,
                completed: status["completed"].boolValue,
                competitors: competitors,
                period: period.intValue,
                teamNames: teamNames,
                clock: clock.stringValue,
                startDate: parseGameDate(date.stringValue),
                teams: teams,
                statusDetail: status["shortDetail"].stringValue,
                halftime: status["description"].stringValue == "Halftime",
                cancelled: calledOff.cancelled,
                postponed: calledOff.postponed,
                broadcast: broadcast,
                venue: competition["venue", "fullName"].stringValue,
                neutralSite: competition["neutralSite"].boolValue,
                name: name
            ))
        }
    }
    return LeagueScoreboard(games: games)
}

/// A scoreboard competitor's names, crest, colours, poll rank and result,
/// each read by name; whatever the board leaves out stays empty.
private func scoreboardTeam(_ competitor: JSON) -> ScoreboardTeam {
    let team = competitor["team"]
    func text(_ key: String) -> String {
        team[key].stringValue.trimmingCharacters(in: .whitespaces)
    }
    let logo = text("logo")
    return ScoreboardTeam(
        abbreviation: text("abbreviation"),
        shortName: text("shortDisplayName"),
        displayName: text("displayName"),
        location: text("location"),
        logoURL: logo.isEmpty ? nil : URL(string: logo),
        colorHex: text("color"),
        alternateColorHex: text("alternateColor"),
        rank: ScoreboardTeam.pollRank(competitor["curatedRank", "current"].int),
        winner: competitor["winner"].boolValue
    )
}

// MARK: - Around Your Leagues

extension LeagueID {
    /// The league's scoreboard for one day (`"20261025"`) of Home's Around
    /// Your Leagues (`HomeViewModel`).
    ///
    /// A college board is big: with `rankedOnly` it asks for the default
    /// board (college basketball's featured games, college football's FBS)
    /// and the rows keep the ranked teams' games; without, basketball names
    /// all of Division I (`groups=50&limit=1000`), as `scoreboardURL(day:)`
    /// does. College football's default board is already its FBS slate, and
    /// `limit=1000` there answers a shorter one (25 games of 44 on a
    /// Saturday), so it asks for no more.
    func roundupScoreboardURL(dates: String, rankedOnly: Bool) -> String {
        var url = "https://site.api.espn.com/apis/site/v2/sports/\(path)/scoreboard?dates=\(dates)"
        if isCollege && !rankedOnly && sport == "basketball" {
            url += "&groups=50&limit=1000"
        }
        return url
    }
}
