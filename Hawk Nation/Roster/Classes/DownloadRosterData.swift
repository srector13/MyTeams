//
//  DownloadRosterData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/28/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct BasketballPlayer: Identifiable, Hashable, Sendable {
    var playerID: String
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var grade: String
    var hometown: String
    var photo: String
    var status: String
    var lastName: String
}

struct FootBallPlayer: Identifiable, Hashable, Sendable {
    var playerID: String
    var name: String
    var numberInt: Int
    var number: String
    var height: String
    var weight: String
    var position: String
    var hometown: String
    var photo: String
    var debutYear: String
    var college: String
    var age: String
    var lastName: String
    var team: String
}

struct SoccerPlayer: Identifiable, Hashable, Sendable {
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var photo: String
    var age: String
    var playerID: String
    var birthPlace: String
    var citizenshipCountry: String
    var fouls: Int
    var foulsSuffered: Int
    var redCards: Int
    var yellowCards: Int
    var ownGoals: Int
    var appearances: Int
    var subAppearances: Int
    var goalAssists: Int
    var offsides: Int
    var shotsOnTarget: Int
    var totalShots: Int
    var totalGoals: Int
    var saves: Int
    var shotsFaced: Int
    var goalsConceded: Int
    var lastName: String
    /// Whether the roster feed listed season totals for the player. Some it
    /// lists with none (5 of Arsenal's 27 on 2026-09-28); their sheet reads
    /// the athlete document instead (`downloadSoccerPlayerStats`).
    var hasSeasonStats = true
}

struct BaseballPlayer: Identifiable, Hashable, Sendable {
    var playerID: String
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var hometown: String
    var photo: String
    var debutYear: String
    var college: String
    var batHand: String
    var throwHand: String
    var age: String
    var lastName: String
}

struct HockeyPlayer: Identifiable, Hashable, Sendable {
    var playerID: String
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var hometown: String
    var photo: String
    var age: String
    /// The hand the player shoots (or, for a goalie, catches) with.
    var shoots: String
    var lastName: String
}

// Roster players are identified by their ESPN athlete id, so a refetched
// roster matches the cards already on screen instead of replacing them all.
// A player the feed gives no id falls back to name and number.

extension BasketballPlayer {
    var id: String { playerID.isEmpty ? "\(name)#\(number)" : playerID }
}

extension FootBallPlayer {
    var id: String { playerID.isEmpty ? "\(name)#\(number)" : playerID }
}

extension SoccerPlayer {
    var id: String { playerID.isEmpty ? "\(name)#\(number)" : playerID }
}

extension BaseballPlayer {
    var id: String { playerID.isEmpty ? "\(name)#\(number)" : playerID }
}

extension HockeyPlayer {
    var id: String { playerID.isEmpty ? "\(name)#\(number)" : playerID }
}

/// Shown in place of a headshot the feed has no image for.
private let missingHeadshot = "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png"

/// The jersey number sorted players without one to the end of the roster.
private let noJerseyNumber = 1000

private extension JSON {
    /// An athlete's headshot, falling back to the generic silhouette.
    var headshotURL: String {
        let href = self["headshot"]["href"].stringValue
        return href.isEmpty ? missingHeadshot : href
    }

    /// An athlete's jersey number as an integer, or `noJerseyNumber` when it
    /// is absent or not numeric.
    var jerseyNumber: Int {
        Int(self["jersey"].stringValue) ?? noJerseyNumber
    }
}

/// Loads a basketball team's roster, sorted by surname.
func downloadBasketballRoster(team: TeamRef) async -> Result<[BasketballPlayer], NetworkError> {
    await HTTPClient.shared.fetch(team.rosterURL).map(empty: [], parseBasketballRoster(from:))
}

/// Builds the roster from the feed's document. See `downloadBasketballRoster`.
func parseBasketballRoster(from json: JSON) -> [BasketballPlayer] {

    let roster = json["athletes"].map { _, athlete in
        // College athletes list a state; international ones list a country
        // instead.
        let city = athlete["birthPlace"]["city"].stringValue
        let region = athlete["birthPlace"]["state"].stringValue.isEmpty
            ? athlete["birthPlace"]["country"].stringValue
            : athlete["birthPlace"]["state"].stringValue

        return BasketballPlayer(
            playerID: athlete["id"].stringValue,
            name: athlete["fullName"].stringValue,
            number: athlete["jersey"].stringValue,
            numberInt: athlete.jerseyNumber,
            height: athlete["displayHeight"].stringValue,
            weight: athlete["displayWeight"].stringValue,
            position: athlete["position"]["displayName"].stringValue,
            grade: athlete["experience"]["displayValue"].stringValue,
            hometown: "\(city), \(region)",
            photo: athlete.headshotURL,
            status: athlete["status"]["name"].stringValue,
            lastName: athlete["lastName"].stringValue
        )
    }

    return roster.sorted { $0.lastName < $1.lastName }
}

/// Loads a football team's roster, sorted by surname.
///
/// The NFL feed groups athletes by unit — offense, defense, special teams —
/// so each group's `items` are flattened into a single roster.
func downloadFootballRoster(team: TeamRef) async -> Result<[FootBallPlayer], NetworkError> {
    await HTTPClient.shared.fetch(team.rosterURL).map(empty: [], parseFootballRoster(from:))
}

/// Builds the roster from the feed's document. See `downloadFootballRoster`.
func parseFootballRoster(from json: JSON) -> [FootBallPlayer] {

    var roster: [FootBallPlayer] = []

    for (_, group): (String, JSON) in json["athletes"] {
        // Shape pin (M6): ESPN sends this `position` as a bare string naming
        // the unit ("offense", "defense", "specialTeam"). Unlike the athlete
        // `position` below, it is not an object. If the feed ever changes it
        // to one, `stringValue` yields "" and every player is filed under ""
        // — the NFL unit filters (`LeagueDescriptor.rosterFilters`) would
        // then match nobody and all three render empty. See JSONTests for the coercion rule.
        let unit = group["position"].stringValue

        for (_, athlete): (String, JSON) in group["items"] {
            let city = athlete["birthPlace"]["city"].stringValue
            let state = athlete["birthPlace"]["state"].stringValue

            roster.append(
                FootBallPlayer(
                    playerID: athlete["id"].stringValue,
                    name: athlete["fullName"].stringValue,
                    numberInt: athlete.jerseyNumber,
                    number: athlete["jersey"].stringValue,
                    height: athlete["displayHeight"].stringValue,
                    weight: athlete["displayWeight"].stringValue,
                    position: athlete["position"]["displayName"].stringValue,
                    hometown: city.isEmpty ? "N/A" : "\(city), \(state)",
                    photo: athlete.headshotURL,
                    debutYear: athlete["debutYear"].stringValue,
                    college: athlete["college"]["name"].stringValue,
                    age: athlete["age"].stringValue,
                    lastName: athlete["lastName"].stringValue,
                    team: unit
                )
            )
        }
    }

    return roster.sorted { $0.lastName < $1.lastName }
}

/// Loads a baseball team's roster, sorted by surname.
///
/// Like the NFL feed, athletes arrive grouped by unit and are flattened.
func downloadBaseballRoster(team: TeamRef) async -> Result<[BaseballPlayer], NetworkError> {
    await HTTPClient.shared.fetch(team.rosterURL).map(empty: [], parseBaseballRoster(from:))
}

/// Builds the roster from the feed's document. See `downloadBaseballRoster`.
func parseBaseballRoster(from json: JSON) -> [BaseballPlayer] {

    var roster: [BaseballPlayer] = []

    for (_, group): (String, JSON) in json["athletes"] {
        for (_, athlete): (String, JSON) in group["items"] {
            let city = athlete["birthPlace"]["city"].stringValue
            let state = athlete["birthPlace"]["state"].stringValue

            roster.append(
                BaseballPlayer(
                    playerID: athlete["id"].stringValue,
                    name: athlete["fullName"].stringValue,
                    number: athlete["jersey"].stringValue,
                    numberInt: athlete.jerseyNumber,
                    height: athlete["displayHeight"].stringValue,
                    weight: athlete["displayWeight"].stringValue,
                    position: athlete["position"]["displayName"].stringValue,
                    hometown: "\(city), \(state)",
                    photo: athlete.headshotURL,
                    debutYear: athlete["debutYear"].stringValue,
                    college: athlete["college"]["name"].stringValue,
                    batHand: athlete["bats"]["displayValue"].stringValue,
                    throwHand: athlete["throws"]["displayValue"].stringValue,
                    age: athlete["age"].stringValue,
                    lastName: athlete["lastName"].stringValue
                )
            )
        }
    }

    return roster.sorted { $0.lastName < $1.lastName }
}

/// Loads a soccer team's roster, sorted by surname.
///
/// Season totals come embedded in the roster feed, in three categories —
/// `general` (discipline and appearances), `offensive` and `goalKeeping`,
/// the last for outfield players too. Each stat is read by its `name`,
/// which is unique across the three. See `parseSoccerRoster`.
func downloadSoccerRoster(team: TeamRef) async -> Result<[SoccerPlayer], NetworkError> {
    await HTTPClient.shared.fetch(team.rosterURL).map(empty: [], parseSoccerRoster(from:))
}

/// Builds the roster from the feed's document. See `downloadSoccerRoster`.
///
/// `appearances` is every appearance, off the bench included: Sporting's
/// Calvin Harris has 25 with 2 `subIns`, and his athlete document says
/// 23 starts (2 as a substitute). Every soccer roster captured (MLS,
/// Premier League, LALIGA, Liga MX, NWSL) names the same 15 stats.
func parseSoccerRoster(from json: JSON) -> [SoccerPlayer] {

    let roster = json["athletes"].map { _, athlete in
        let categories = athlete["statistics"]["splits"]["categories"].arrayValue

        var values: [String: Int] = [:]
        for category in categories {
            for stat in category["stats"].arrayValue {
                let name = stat["name"].stringValue
                if values[name] == nil { values[name] = stat["value"].intValue }
            }
        }

        func stat(_ name: String) -> Int { values[name] ?? 0 }

        let saves = stat("saves")
        let goalsConceded = stat("goalsConceded")

        let country = athlete["birthPlace"]["country"].stringValue
        // Shape pin (M6): the soccer feed has shipped `citizenship` both as a
        // string and as an array of country objects. `stringValue` returns ""
        // for an array, so one shape change makes every player read "N/A"
        // here — if that column goes blank across the roster, iterate the
        // array and take each element's `name` instead.
        let citizenship = athlete["citizenship"].stringValue

        return SoccerPlayer(
            name: athlete["fullName"].stringValue,
            number: athlete["jersey"].stringValue,
            numberInt: athlete.jerseyNumber,
            height: athlete["displayHeight"].stringValue,
            weight: athlete["displayWeight"].stringValue,
            position: athlete["position"]["displayName"].stringValue,
            photo: athlete.headshotURL,
            age: athlete["age"].stringValue,
            playerID: athlete["id"].stringValue,
            birthPlace: country.isEmpty ? "N/A" : country,
            citizenshipCountry: citizenship.isEmpty ? "N/A" : citizenship,
            fouls: stat("foulsCommitted"),
            foulsSuffered: stat("foulsSuffered"),
            redCards: stat("redCards"),
            yellowCards: stat("yellowCards"),
            ownGoals: stat("ownGoals"),
            appearances: stat("appearances"),
            subAppearances: stat("subIns"),
            goalAssists: stat("goalAssists"),
            offsides: stat("offsides"),
            shotsOnTarget: stat("shotsOnTarget"),
            totalShots: stat("totalShots"),
            totalGoals: stat("totalGoals"),
            saves: saves,
            // The feed's own `shotsFaced` is 0 for every keeper captured.
            shotsFaced: saves + goalsConceded,
            goalsConceded: goalsConceded,
            lastName: athlete["lastName"].stringValue,
            hasSeasonStats: !values.isEmpty
        )
    }

    return roster.sorted { $0.lastName < $1.lastName }
}

/// Loads a hockey team's roster, sorted by surname.
///
/// The NHL feed groups athletes by position ("Centers", "Defense",
/// "Goalies" …); each group's `items` are flattened into a single roster.
func downloadHockeyRoster(team: TeamRef) async -> Result<[HockeyPlayer], NetworkError> {
    await HTTPClient.shared.fetch(team.rosterURL).map(empty: [], parseHockeyRoster(from:))
}

/// Builds the roster from the feed's document. See `downloadHockeyRoster`.
func parseHockeyRoster(from json: JSON) -> [HockeyPlayer] {
    // A hockey league outside the registry is assumed flat
    // (`LeagueDescriptor.descriptor(for:)`), so an entry with no `items`
    // is read as an athlete itself.
    let athletes = json["athletes"].arrayValue.flatMap { (entry: JSON) -> [JSON] in
        entry["items"].array ?? [entry]
    }

    let roster = athletes.map { (athlete: JSON) -> HockeyPlayer in
        // North American players list a state or province; others only a
        // country.
        let city = athlete["birthPlace"]["city"].stringValue
        let region = athlete["birthPlace"]["state"].stringValue.isEmpty
            ? athlete["birthPlace"]["country"].stringValue
            : athlete["birthPlace"]["state"].stringValue

        return HockeyPlayer(
            playerID: athlete["id"].stringValue,
            name: athlete["fullName"].stringValue,
            number: athlete["jersey"].stringValue,
            numberInt: athlete.jerseyNumber,
            height: athlete["displayHeight"].stringValue,
            weight: athlete["displayWeight"].stringValue,
            position: athlete["position"]["displayName"].stringValue,
            hometown: city.isEmpty ? "N/A" : "\(city), \(region)",
            photo: athlete.headshotURL,
            age: athlete["age"].stringValue,
            shoots: athlete["hand"]["displayValue"].stringValue,
            lastName: athlete["lastName"].stringValue
        )
    }

    return roster.sorted { $0.lastName < $1.lastName }
}
