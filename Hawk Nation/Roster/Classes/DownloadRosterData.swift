//
//  DownloadRosterData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/28/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct BasketballPlayer: Identifiable, Hashable, Sendable {
    var id = UUID()
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
    var id = UUID()
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
    var id = UUID()
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
}

struct BaseballPlayer: Identifiable, Hashable, Sendable {
    var id = UUID()
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

/// Loads the Kansas men's basketball roster, sorted by surname.
func downloadBasketballRoster() async -> [BasketballPlayer] {
    let json = await HTTPClient.json(
        from: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/roster"
    )

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

/// Loads the Chiefs roster, sorted by surname.
///
/// The NFL feed groups athletes by unit — offense, defense, special teams —
/// so each group's `items` are flattened into a single roster.
func downloadFootballRoster() async -> [FootBallPlayer] {
    let json = await HTTPClient.json(
        from: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/roster"
    )

    var roster: [FootBallPlayer] = []

    for (_, group): (String, JSON) in json["athletes"] {
        // Shape pin (M6): ESPN sends this `position` as a bare string naming
        // the unit ("offense", "defense", "specialTeam"). Unlike the athlete
        // `position` below, it is not an object. If the feed ever changes it
        // to one, `stringValue` yields "" and every player is filed under ""
        // — ChiefsHome's unit filters would then match nobody and all three
        // roster sections render empty. See JSONTests for the coercion rule.
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

/// Loads the Royals roster, sorted by surname.
///
/// Like the NFL feed, athletes arrive grouped by unit and are flattened.
func downloadBaseballRoster() async -> [BaseballPlayer] {
    let json = await HTTPClient.json(
        from: "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/7/roster"
    )

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

/// Loads the Sporting Kansas City roster, sorted by surname.
///
/// Season totals come embedded in the roster feed, in two categories for
/// outfield players (discipline, then attacking) and a third for keepers.
/// They are addressed by position, as the feed gives them no stable keys.
func downloadSoccerRoster() async -> [SoccerPlayer] {
    let json = await HTTPClient.json(
        from: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/teams/186/roster"
    )

    let roster = json["athletes"].map { _, athlete in
        let categories = athlete["statistics"]["splits"]["categories"]

        func stat(_ category: Int, _ index: Int) -> Int {
            categories[category]["stats"][index]["value"].intValue
        }

        let saves = stat(2, 0)
        let goalsConceded = stat(2, 2)

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
            fouls: stat(0, 0),
            foulsSuffered: stat(0, 1),
            redCards: stat(0, 2),
            yellowCards: stat(0, 3),
            ownGoals: stat(0, 4),
            appearances: stat(0, 5),
            subAppearances: stat(0, 6),
            goalAssists: stat(1, 0),
            offsides: stat(1, 1),
            shotsOnTarget: stat(1, 2),
            totalShots: stat(1, 3),
            totalGoals: stat(1, 4),
            saves: saves,
            shotsFaced: saves + goalsConceded,
            goalsConceded: goalsConceded,
            lastName: athlete["lastName"].stringValue
        )
    }

    return roster.sorted { $0.lastName < $1.lastName }
}
