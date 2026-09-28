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
    /// Each competitor's `team.shortDisplayName`, by ESPN team id. For score
    /// alerts.
    var teamNames: [String: String] = [:]

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

            var teamNames: [String: String] = [:]
            for (_, competitor) in competition["competitors"] {
                let teamID = competitor["team", "id"].stringValue
                guard !teamID.isEmpty else { continue }
                teamNames[teamID] = competitor["team", "shortDisplayName"].stringValue
            }

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
                teamNames: teamNames
            ))
        }
    }
    return LeagueScoreboard(games: games)
}
