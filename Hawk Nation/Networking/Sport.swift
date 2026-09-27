//
//  Sport.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The sport a league plays, which decides the cards, box scores and player
/// sheets a team page uses.
enum SportKind: String, Codable, Sendable {
    case football
    case basketball
    case baseball
    case soccer
    /// A sport the app has no dedicated views for.
    case other
}

/// How a league's roster feed lists its athletes.
enum RosterShape: Sendable {
    /// `athletes` is a list of groups, each with its own `items` (NFL units,
    /// MLB position groups).
    case grouped
    /// `athletes` is one flat list (college basketball, MLS).
    case flat
}

/// How a league's schedule turns into a record and a next game.
struct RecordRule: Sendable, Hashable {
    /// Cancelled and postponed fixtures count in the losses column. MLB has
    /// always been shown this way; every other league treats an abandoned
    /// fixture as neither win nor loss. See `seasonRecord`.
    var countsAbandonedGamesAsLosses = false

    /// A past kick-off also counts as played, both for the record and for
    /// locating the next game. MLS completion flags lag or never arrive. See
    /// `getNextGame` and `seasonRecord(pastDatesCountAsPlayed:)`.
    var usesDateForNextGame = false
}

/// Everything that differs by league rather than by team.
///
/// The retired `Team` enum carried these as per-team switches, and the views
/// carried the rest as per-team flags and name matching. They live here now,
/// keyed on the league, so any team in a known league gets them.
struct LeagueDescriptor: Sendable, Identifiable {
    /// How a league names its game periods.
    enum PeriodStyle: Sendable {
        case halves
        case quarters
        /// No period label (baseball innings are not named).
        case unnamed
    }

    let id: LeagueID
    let kind: SportKind
    let displayName: String
    let isCollege: Bool
    let rosterShape: RosterShape
    let recordRule: RecordRule

    /// The field of an ESPN competitor's `team` object that names it on the
    /// schedule cards. Display only — the followed team is found by id.
    let competitorNameField: TeamNameField

    let periodStyle: PeriodStyle

    /// The label for a game period as the feeds number it (`status.period`).
    ///
    /// Only regulation periods are named; overtime and innings read as blank.
    func periodName(_ period: String) -> String {
        let names: [String: String] = switch periodStyle {
        case .halves: ["1": "1st Half", "2": "2nd Half"]
        case .quarters: ["1": "1st Quarter", "2": "2nd Quarter", "3": "3rd Quarter", "4": "4th Quarter"]
        case .unnamed: [:]
        }
        return names[period] ?? ""
    }

    // MARK: - Known leagues

    static let mensCollegeBasketball = LeagueDescriptor(
        id: .mensCollegeBasketball,
        kind: .basketball,
        displayName: "NCAA Men's Basketball",
        isCollege: true,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .halves
    )

    static let nfl = LeagueDescriptor(
        id: .nfl,
        kind: .football,
        displayName: "NFL",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .quarters
    )

    static let mlb = LeagueDescriptor(
        id: .mlb,
        kind: .baseball,
        displayName: "MLB",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(countsAbandonedGamesAsLosses: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .unnamed
    )

    static let mls = LeagueDescriptor(
        id: .mls,
        kind: .soccer,
        displayName: "MLS",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(usesDateForNextGame: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves
    )

    static let known: [LeagueID: LeagueDescriptor] = Dictionary(
        uniqueKeysWithValues: [mensCollegeBasketball, nfl, mlb, mls].map { ($0.id, $0) }
    )

    /// The descriptor for `id`: a known league's own, or a plain one derived
    /// from the sport path component.
    static func descriptor(for id: LeagueID) -> LeagueDescriptor {
        if let known = known[id] { return known }
        return LeagueDescriptor(
            id: id,
            kind: SportKind(rawValue: id.sport) ?? .other,
            displayName: id.path,
            isCollege: false,
            rosterShape: .flat,
            recordRule: RecordRule(),
            competitorNameField: .shortDisplayName,
            periodStyle: .unnamed
        )
    }
}
