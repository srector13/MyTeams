//
//  DownloadScheduleData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct Game: Identifiable, Hashable, Sendable {
    var id = UUID()
    var team: String
    var opponent: String
    var score: String
    var opponentScore: String
    var time: String
    var date: String
    var dateAsDate: Date
    var opponentLogo: String
    var channel: String
    var location: String
    var gameHome: Bool
    var gameID: String
    var pointer: Int
    var gameWin: Bool
    var completed: Bool
    var competitionName: String
    var cancelled: Bool
    var postponed: Bool
    var gameClock: String
    var gamePeriod: String
    var gameHalftime: Bool
}

/// Which field of an ESPN `team` object names the team a schedule belongs to.
///
/// The feeds disagree: basketball, football and baseball carry a `nickname`
/// ("Jayhawks", "Chiefs"), while the soccer feed only carries a
/// `shortDisplayName`.
enum TeamNameField: String, Sendable {
    case nickname
    case shortDisplayName
}

// These formatters keep the device's locale, so month names and the choice of
// a 12- or 24-hour clock follow the reader's region settings.
//
// They are shared rather than rebuilt for each of the several hundred games
// parsed per refresh; `DateFormatter` is `Sendable`, and none of these are
// mutated after creation.

/// The zone every game time is presented in: US Central, the home zone of all
/// four teams. Display is pinned to this zone while the underlying `Date`
/// stays the true instant, so schedule text reads identically on any device
/// and clock comparisons (`dateAsDate < Date()`) remain correct. The zone is
/// DST-aware, unlike the fixed six-hour shift this replaced.
private let scheduleDisplayZone = TimeZone(identifier: "America/Chicago")

/// Formats a game's calendar date for display, e.g. "Jan 18, 2021".
private let gameDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM dd, yyyy"
    formatter.timeZone = scheduleDisplayZone
    return formatter
}()

/// Formats a game's start time for display, e.g. "7:00 PM".
private let gameTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.timeZone = scheduleDisplayZone
    return formatter
}()

/// Reads the UTC timestamps ESPN puts on events.
private let eventDateParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    // ESPN's `Z` suffix means UTC; parse in UTC explicitly so the result is
    // the same instant on every device instead of the wall-clock reading of
    // whatever timezone the device happens to be set to.
    formatter.timeZone = .utc
    return formatter
}()

/// Reads an ESPN event timestamp, which is UTC in the form
/// `2021-01-18T23:00Z`, as the exact instant it names.
///
/// The returned `Date` is timezone-neutral — correct for comparisons against
/// `Date()` anywhere. Presentation in US Central time happens in the display
/// formatters above, not by shifting the instant itself.
func parseGameDate(_ raw: String) -> Date? {
    let cleaned = raw
        .replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")

    return eventDateParser.date(from: cleaned)
}

/// Builds one `Game` from an ESPN event object.
///
/// `teamNameField` selects the name the feed uses to identify the followed
/// team; the competitor that does not match it is the opponent.
private func parseGame(
    from event: JSON,
    teamName: String,
    teamNameField: TeamNameField,
    pointer: Int
) -> Game {
    var opponent = ""
    var score = ""
    var opponentScore = ""
    var time = ""
    var date = ""
    var dateAsDate = Date()
    var opponentLogo = ""
    var channel = ""
    var location = ""
    var gameHome = false
    var gameID = ""
    var gameWin = false
    var completed = false
    var cancelled = false
    var postponed = false
    var gameClock = ""
    var gamePeriod = ""
    var halftime = false

    for (_, competition): (String, JSON) in event["competitions"] {
        // Shape pin (M6): every assignment below overwrites the previous
        // iteration's value, so with more than one competition in an event —
        // a doubleheader feed, say — the last one silently wins. ESPN's
        // summary and schedule endpoints carry exactly one competition per
        // event today; revisit this loop (or assert a count of one) if a
        // fixture ever shows the wrong venue, time, or score.
        location = competition["venue"]["fullName"].stringValue
        gameID = competition["id"].stringValue

        if let parsed = parseGameDate(event["date"].stringValue) {
            dateAsDate = parsed
            date = gameDateFormatter.string(from: parsed)
            time = gameTimeFormatter.string(from: parsed)
        }

        let status = competition["status"]
        completed = status["type"]["completed"].boolValue
        halftime = status["type"]["description"].stringValue == "Halftime"
        gameClock = status["displayClock"].stringValue
        gamePeriod = status["period"].stringValue

        let detail = status["type"]["detail"].stringValue
        postponed = detail == "Postponed"
        cancelled = detail == "Canceled"

        channel = competition["broadcasts", 0, "media", "shortName"].stringValue
        if channel.isEmpty {
            channel = "TBD"
        }

        for (_, competitor): (String, JSON) in competition["competitors"] {
            if competitor["team"][teamNameField.rawValue].stringValue == teamName {
                gameHome = competitor["homeAway"].stringValue == "home"
                gameWin = competitor["winner"].boolValue
                score = competitor["score"]["displayValue"].stringValue
            } else {
                opponent = competitor["team"][teamNameField.rawValue].stringValue
                opponentScore = competitor["score"]["displayValue"].stringValue

                // Feeds ship a light and a dark variant of every logo. Take
                // the light one, which reads on the team-coloured cards.
                for (_, logo): (String, JSON) in competitor["team"]["logos"] {
                    let link = logo["href"].stringValue
                    if !link.contains("dark") {
                        opponentLogo = link
                    }
                }
            }
        }
    }

    return Game(
        team: teamName,
        opponent: opponent,
        score: score,
        opponentScore: opponentScore,
        time: time,
        date: date,
        dateAsDate: dateAsDate,
        opponentLogo: opponentLogo,
        channel: channel,
        location: location,
        gameHome: gameHome,
        gameID: gameID,
        pointer: pointer,
        gameWin: gameWin,
        completed: completed,
        competitionName: event["name"].stringValue,
        cancelled: cancelled,
        postponed: postponed,
        gameClock: gameClock,
        gamePeriod: gamePeriod,
        gameHalftime: halftime
    )
}

/// Loads a team's season schedule.
///
/// Games keep the order the feed lists them in, and each carries its position
/// as `pointer` — the schedule carousels scroll to the next unplayed game by
/// that index.
func downloadScheduleData(
    queryURL: String,
    teamName: String,
    teamNameField: TeamNameField = .nickname
) async -> [Game] {
    let json = await HTTPClient.json(from: queryURL)

    return json["events"].enumerated().map { pointer, element in
        parseGame(
            from: element.1,
            teamName: teamName,
            teamNameField: teamNameField,
            pointer: pointer
        )
    }
}
