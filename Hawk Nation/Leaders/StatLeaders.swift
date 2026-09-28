//
//  StatLeaders.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// MARK: - Feed

/// One player's place on one of the leaders feed's boards.
struct StatLeader: Hashable, Sendable, Identifiable {
    var athleteID: String
    var name: String
    /// `"L. Doncic"`.
    var shortName: String
    /// Empty when the feed has no headshot (none of the soccer feeds do).
    var headshotURL: String
    /// The position's abbreviation: `"G"`, `"RW"`, `"QB"`.
    var position: String
    var teamID: String
    var teamAbbreviation: String
    /// The figure the board ranks by, e.g. `33.484375` points per game.
    var value: Double
    /// The feed's own text for the figure, which is not always the figure.
    /// See `LeaderValueFormat`.
    var displayValue: String

    var id: String { athleteID }
}

/// One of the leaders feed's boards, as the feed names it.
struct LeaderCategory: Hashable, Sendable, Identifiable {
    /// The category's `name`, e.g. `"pointsPerGame"`: the key a
    /// `LeaderCategorySpec` asks for.
    var name: String
    /// `"Points Per Game"`.
    var displayName: String
    /// `"PTS"`.
    var abbreviation: String
    /// Best first, as the feed ranks them.
    var leaders: [StatLeader]

    var id: String { name }
}

/// A league's (or one team's) statistical leaders, read from
/// `LeagueID.leadersURL`.
///
/// The feed is `{requestedSeason, leaders: {categories: [{name,
/// displayName, abbreviation, leaders: [{value, displayValue, athlete,
/// team}]}]}}`. Categories are read by `name` — their order and number
/// differ by league, and between a league's and a team's feeds (the Hawks'
/// lists `defensiveReboundsPerGame`, the NBA's does not).
struct StatLeaders: Hashable, Sendable {
    /// The year ESPN files the season under (see `SeasonNaming`).
    var season: Int?
    /// `"2025-26"`, `"2026-27 English Premier League"`.
    var seasonName: String
    /// `"Regular Season"`.
    var seasonType: String
    /// Only categories with at least one leader: a team's feed lists a
    /// category none of its players leads in with an empty board (the
    /// Ducks' `shutouts`).
    var categories: [LeaderCategory]

    static let empty = StatLeaders(season: nil, seasonName: "", seasonType: "", categories: [])

    var isEmpty: Bool { categories.isEmpty }

    /// The category the feed names `name`, if it lists one with leaders.
    func category(named name: String) -> LeaderCategory? {
        categories.first { $0.name == name }
    }
}

/// Reads a leaders document. See `StatLeaders`.
func parseStatLeaders(from json: JSON) -> StatLeaders {
    let requested = json["requestedSeason"]
    let categories = json["leaders"]["categories"].arrayValue.compactMap { (category: JSON) -> LeaderCategory? in
        let leaders = category["leaders"].arrayValue.map { (leader: JSON) -> StatLeader in
            let athlete = leader["athlete"]
            let team = leader["team"]
            return StatLeader(
                athleteID: athlete["id"].stringValue,
                name: athlete["displayName"].stringValue,
                shortName: athlete["shortName"].stringValue,
                headshotURL: athlete["headshot"]["href"].stringValue,
                position: athlete["position"]["abbreviation"].stringValue,
                teamID: team["id"].stringValue,
                teamAbbreviation: team["abbreviation"].stringValue,
                value: leader["value"].doubleValue,
                displayValue: leader["displayValue"].stringValue
            )
        }
        guard !leaders.isEmpty else { return nil }
        return LeaderCategory(
            name: category["name"].stringValue,
            displayName: category["displayName"].stringValue,
            abbreviation: category["abbreviation"].stringValue,
            leaders: leaders
        )
    }
    return StatLeaders(
        season: requested["year"].int,
        seasonName: requested["displayName"].stringValue,
        seasonType: requested["type"]["name"].stringValue,
        categories: categories
    )
}

// MARK: - Boards

/// One row of a leaderboard as a leaders screen draws it.
struct LeaderBoardRow: Hashable, Sendable, Identifiable {
    /// 1 for the leader. Players level on the figure keep the feed's order
    /// and their own numbers.
    var rank: Int
    var leader: StatLeader
    /// The figure, formatted for the board (`LeaderValueFormat`).
    var value: String
    /// The feed's `displayValue` where it says more than the figure: MLB's
    /// stat line, soccer's matches played.
    var detail: String?

    var id: String { "\(rank):\(leader.athleteID)" }
}

/// One leaderboard as a leaders screen draws it.
struct LeaderBoard: Hashable, Sendable, Identifiable {
    /// The feed's category `name`.
    var name: String
    var title: String
    var label: String
    var rows: [LeaderBoardRow]

    var id: String { name }
}

/// The boards a leaders screen shows for `kind`, each `depth` rows deep.
///
/// The sport's `leaderCategories` pick, order, label and format the boards;
/// a category the feed lacks is skipped. A sport with none (`.other`), or
/// a feed that has none of them, shows every category the feed lists under
/// its own names and figures.
func leaderBoards(from leaders: StatLeaders, kind: SportKind, depth: Int) -> [LeaderBoard] {
    var specs = kind.leaderCategories.filter { leaders.category(named: $0.name) != nil }
    if specs.isEmpty {
        specs = leaders.categories.map {
            LeaderCategorySpec($0.name, $0.displayName, $0.abbreviation, .feed)
        }
    }

    return specs.compactMap { spec -> LeaderBoard? in
        guard let category = leaders.category(named: spec.name) else { return nil }
        let rows = category.leaders.prefix(depth).enumerated().map { index, leader -> LeaderBoardRow in
            let value = spec.format.format(leader.value, displayValue: leader.displayValue)
            let wordy = leader.displayValue.contains { $0.isLetter }
            return LeaderBoardRow(
                rank: index + 1,
                leader: leader,
                value: value,
                detail: wordy && leader.displayValue != value ? leader.displayValue : nil
            )
        }
        return LeaderBoard(name: spec.name, title: spec.title, label: spec.label, rows: rows)
    }
}

// MARK: - Loading

/// Loads a league's stat leaders, or one team's, `depth` players deep.
///
/// A league that names its season (`leadersSeasonType`: soccer) asks for
/// the one in progress by its `SeasonNaming`. Early in a new season that
/// can have no leaders yet, so an empty answer is retried for the season
/// before. Only the first request's failure is reported.
func downloadStatLeaders(
    league: LeagueID,
    teamID: String? = nil,
    depth: Int = 10,
    now: Date = Date()
) async -> Result<StatLeaders, NetworkError> {
    let client = HTTPClient.shared
    let season = league.descriptor.leadersSeason(at: now)

    let first = await client.fetch(league.leadersURL(teamID: teamID, season: season, limit: depth))
        .map(empty: StatLeaders.empty, parseStatLeaders(from:))
    guard case .success(let leaders) = first, leaders.isEmpty, let season else { return first }

    let previous = await client.fetch(league.leadersURL(teamID: teamID, season: season - 1, limit: depth))
        .map(empty: StatLeaders.empty, parseStatLeaders(from:))
    if case .success(let earlier) = previous, !earlier.isEmpty {
        return previous
    }
    return first
}
