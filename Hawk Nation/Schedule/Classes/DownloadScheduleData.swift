//
//  DownloadScheduleData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct Game: Identifiable, Hashable, Sendable {
    /// ESPN's id for the event, or — for a feed entry that carries none — a
    /// key built from its raw date, opponent and feed position. See `id`.
    var eventID = ""
    /// The followed team's name as the feed gives it (see `TeamNameField`),
    /// or empty when the event does not list the team.
    var team: String
    var opponent: String
    /// The opponent's ESPN team id, or empty when the feed names none.
    var opponentID = ""
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
    /// The competition the game is played in: the team's league, or one of
    /// its cups (`LeagueDescriptor.cupCompetitions`). Read from the event's
    /// `league.slug`, which the soccer feeds carry; `nil` for feeds that name
    /// none, which are always the league's own games.
    var competition: LeagueID? = nil
    /// ESPN's season type for the event (`seasonType.type`): 1 preseason,
    /// 2 regular season, 3 postseason, 4 all-star. The soccer feeds use
    /// their own season ids (13846, 14308, …) here instead. `nil` when the
    /// event carries none.
    var seasonType: Int? = nil

    /// Whether the game is one of the team's league games rather than a cup
    /// tie. See `competition`.
    func isLeagueGame(of league: LeagueID) -> Bool {
        competition == nil || competition == league
    }

    /// Whether the game counts toward the header's record: everything but
    /// exhibitions — preseason (1) and all-star (4) games, which the
    /// standings leave out too. Postseason games count, so an NCAA
    /// tournament run stays in the record; an event with no season type, or
    /// a soccer season id, counts as a regular-season game.
    var countsTowardRecord: Bool {
        seasonType != 1 && seasonType != 4
    }

    /// The game's identity, stable across the once-a-minute schedule refresh.
    ///
    /// A fresh `UUID()` per parse made every refresh look like a brand-new set
    /// of games to `ForEach`, tearing down each card and restarting its logo
    /// load. The event id (or, for a game built without one, the competition
    /// id, then the start and opponent) names the same fixture every time.
    var id: String {
        if !eventID.isEmpty { return eventID }
        if !gameID.isEmpty { return gameID }
        return "\(dateAsDate.timeIntervalSince1970)|\(opponent)"
    }

    /// Whether the game stands level — an MLS draw or an NFL tie once played.
    ///
    /// Neither competitor's `winner` flag is set on a level game, so a caller
    /// that reads "played and not won" as a loss must check this first. A game
    /// with no scores published yet is never a draw.
    var isDraw: Bool {
        guard !gameWin, let score = Int(score), let opponentScore = Int(opponentScore) else {
            return false
        }
        return score == opponentScore
    }
}

/// Which field of an ESPN `team` object a schedule card names a team by.
///
/// The feeds disagree on which reads best: the basketball and football feeds
/// carry the short name in `nickname` ("Kansas", "Broncos"), while the
/// baseball and soccer feeds' `nickname` is absent or a mascot, and their
/// `shortDisplayName` is the familiar name. Each league's field is declared
/// on its `LeagueDescriptor` (`competitorNameField`). Names are display only;
/// teams are matched by id.
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

/// The zone game times are presented in: the device's own, following it if
/// it changes while the app runs. The feed's timestamps are UTC instants
/// (`eventDateParser`), so only display depends on this; `dateAsDate` and
/// clock comparisons (`dateAsDate < Date()`) are zone-free. Display used to
/// be pinned to US Central, the home zone of the four seed teams, which read
/// wrong for anyone following a team from elsewhere.
private let scheduleDisplayZone = TimeZone.autoupdatingCurrent

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
/// `Date()` anywhere. Presentation in the device's time zone happens in the
/// display formatters above, not by shifting the instant itself.
func parseGameDate(_ raw: String) -> Date? {
    let cleaned = raw
        .replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")

    return eventDateParser.date(from: cleaned)
}

/// Builds one `Game` from an ESPN event object.
///
/// The followed team is the competitor whose `team.id` is `team.espnID`; any
/// other competitor is the opponent. Both are named by the league's
/// `competitorNameField`.
///
/// An event normally holds one competition. Should it hold several, the game
/// is read from the one the followed team plays in (the first, if none
/// names it), rather than letting the last one silently overwrite the rest.
///
/// - Parameter competition: the league whose feed the event came from, for
///   an event that does not name its own (`league.slug`). `nil`, the
///   default, leaves such an event's `competition` unnamed, which counts as
///   the team's league.
///
/// Internal rather than private so the golden fixture tests can drive it
/// with real ESPN events; `parseSchedule` remains the production entry point.
func parseGame(
    from event: JSON,
    team: TeamRef,
    pointer: Int,
    competition feedCompetition: LeagueID? = nil
) -> Game {
    let nameField = team.league.descriptor.competitorNameField
    var teamName = ""
    var opponent = ""
    var opponentID = ""
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

    // Shape pin (M6): ESPN's schedule endpoints carry exactly one
    // competition per event today. Reading only the followed team's keeps a
    // multi-competition event (a doubleheader feed, say) from mixing one
    // competition's venue with another's score.
    let competitions = event["competitions"].arrayValue
    let played = competitions.first { competition in
        competition["competitors"].arrayValue.contains { $0["team"]["id"].stringValue == team.espnID }
    } ?? competitions.first

    if let competition = played {
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
            if competitor["team"]["id"].stringValue == team.espnID {
                teamName = competitor["team"][nameField.rawValue].stringValue
                gameHome = competitor["homeAway"].stringValue == "home"
                gameWin = competitor["winner"].boolValue
                score = competitor["score"]["displayValue"].stringValue
            } else {
                opponent = competitor["team"][nameField.rawValue].stringValue
                opponentID = competitor["team"]["id"].stringValue
                opponentScore = competitor["score"]["displayValue"].stringValue

                // Feeds ship a light and a dark variant of every logo, among
                // a dozen brand-service ones. Take the default crest, chosen
                // by its `rel` tokens, which reads on the team-coloured cards.
                opponentLogo = ESPNLogos.select(competitor["team"]["logos"]).default?.absoluteString ?? ""
            }
        }
    }

    // Prefer the event's own id; the competition id is the same number on
    // every feed seen so far. The last resort uses the raw date string, not
    // `dateAsDate`, which falls back to "now" when the date is unreadable,
    // plus the feed position so an id-less doubleheader stays two games.
    var eventID = event["id"].stringValue
    if eventID.isEmpty { eventID = gameID }
    if eventID.isEmpty { eventID = "\(event["date"].stringValue)|\(opponent)|\(pointer)" }

    // Soccer events name their competition; every other feed leaves it to
    // the league the schedule was fetched for.
    let slug = event["league"]["slug"].stringValue
    let competition = slug.isEmpty
        ? feedCompetition
        : LeagueID(sport: team.league.sport, league: slug)

    return Game(
        eventID: eventID,
        team: teamName,
        opponent: opponent,
        opponentID: opponentID,
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
        gameHalftime: halftime,
        competition: competition,
        seasonType: event["seasonType"]["type"].int
    )
}

/// Loads a team's season schedule.
///
/// Games keep the order the feed lists them in, and each carries its position
/// as `pointer` — the schedule carousels scroll to the next unplayed game by
/// that index.
///
/// A feed that answers with no events is a season with nothing scheduled
/// (`.success([])`), which is distinct from a feed that could not be reached.
///
/// A soccer team plays in more than its league. The league's feed lists
/// only league fixtures, so each of the league's `cupCompetitions` is
/// fetched alongside it, from the same team schedule endpoint under the
/// cup's path, and the fixtures are merged (`mergeSchedules`). The league is
/// primary: its feed failing fails the schedule, while a cup feed that fails,
/// or that the team has no fixtures in, simply adds nothing.
func downloadScheduleData(team: TeamRef) async -> Result<[Game], NetworkError> {
    let cups = team.league.descriptor.cupCompetitions
    guard !cups.isEmpty else {
        return await HTTPClient.shared.fetch(team.scheduleURL).map(empty: []) { json in
            parseSchedule(from: json, team: team)
        }
    }

    async let league = HTTPClient.shared.fetch(team.scheduleURL)
    let cupDocuments = await withTaskGroup(of: (Int, JSON?).self) { group in
        for (index, cup) in cups.enumerated() {
            group.addTask {
                let result = await HTTPClient.shared.fetch(cup.scheduleURL(teamID: team.espnID))
                guard case .success(let json) = result else { return (index, nil) }
                return (index, json)
            }
        }
        var documents = [JSON?](repeating: nil, count: cups.count)
        for await (index, json) in group {
            documents[index] = json
        }
        return documents
    }

    return await league.map(empty: []) { json in
        let cupSchedules = zip(cups, cupDocuments).compactMap { cup, document in
            document.map { (competition: cup, json: $0) }
        }
        return mergeSchedules(league: json, cups: cupSchedules, team: team)
    }
}

/// Builds the season's games from a schedule document. See
/// `downloadScheduleData`.
///
/// - Parameter competition: the league the document was fetched for, for
///   events that do not name their own; see `parseGame`.
func parseSchedule(from json: JSON, team: TeamRef, competition: LeagueID? = nil) -> [Game] {
    json["events"].enumerated().map { pointer, element in
        parseGame(from: element.1, team: team, pointer: pointer, competition: competition)
    }
}

/// One schedule of a team's league games and cup ties, in kick-off order.
///
/// The league document comes first; each cup document adds the fixtures the
/// league's did not already list (matched by `Game.id`). A cup feed with no
/// current fixtures answers with its previous edition — the FA Cup's 2025-26
/// run in September 2026 — so a cup event counts only when it is filed under
/// the league document's season (`season.year` on each event). Every game is
/// then ordered by kick-off, which is also what `getNextGame` expects, and
/// `pointer` renumbered to match.
func mergeSchedules(
    league: JSON,
    cups: [(competition: LeagueID, json: JSON)],
    team: TeamRef
) -> [Game] {
    var games = parseSchedule(from: league, team: team, competition: team.league)
    var seen = Set(games.map(\.id))
    let season = league["season"]["year"].int

    for cup in cups {
        for (_, event) in cup.json["events"] {
            if let season, let eventSeason = event["season"]["year"].int, eventSeason != season {
                continue
            }
            let game = parseGame(from: event, team: team, pointer: 0, competition: cup.competition)
            if seen.insert(game.id).inserted {
                games.append(game)
            }
        }
    }

    // Stable, so fixtures sharing a kick-off keep their feed order.
    let ordered = games.enumerated()
        .sorted { ($0.element.dateAsDate, $0.offset) < ($1.element.dateAsDate, $1.offset) }
        .map(\.element)
    return ordered.enumerated().map { pointer, game in
        var game = game
        game.pointer = pointer
        return game
    }
}
