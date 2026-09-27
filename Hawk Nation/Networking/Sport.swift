//
//  Sport.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The sport a league plays, which decides the roster, box score and player
/// statistics a team page reads.
enum SportKind: String, Codable, Sendable {
    case football
    case basketball
    case baseball
    case soccer
    /// Hockey leagues are catalogued and badged, but have no dedicated views
    /// yet; they render as `other` does.
    case hockey
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

/// How a schedule card draws a game in progress.
enum LiveCardStyle: Sendable {
    /// The period and clock (or "Halftime"), with the live score beneath.
    case periodFirst
    /// The live score, with an arrow for whether the followed team leads or
    /// trails, above the period and clock.
    case scoreFirst
}

/// One button in a roster's filter menu: the players it keeps.
struct RosterFilter: Sendable, Hashable {
    var label: String
    /// The unit the roster feed files the player under (the NFL's
    /// `"offense"`, `"defense"`, `"specialTeam"`), or `nil` for any.
    var unit: String?
    /// The player's position as the feed names it, or `nil` for any.
    var position: String?

    init(label: String, unit: String? = nil, position: String? = nil) {
        self.label = label
        self.unit = unit
        self.position = position
    }

    /// A filter for each position, labelled as the feed names it unless
    /// `labels` renames it.
    static func positions(_ positions: [String], labels: [String: String] = [:]) -> [RosterFilter] {
        positions.map { RosterFilter(label: labels[$0] ?? $0, position: $0) }
    }

    /// A unit's filters: every player in it, then each position within it.
    static func unit(
        _ unit: String,
        positions: [String],
        labels: [String: String] = [:]
    ) -> [RosterFilter] {
        [RosterFilter(label: "All", unit: unit)]
            + positions.map { RosterFilter(label: labels[$0] ?? $0, unit: unit, position: $0) }
    }
}

/// An entry in a roster's filter menu, after its leading "All".
enum RosterFilterEntry: Sendable, Hashable {
    case filter(RosterFilter)
    /// A submenu, such as one NFL unit and its positions.
    case menu(title: String, filters: [RosterFilter])
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

    /// What a schedule card calls a finished game that stands level.
    var drawLabel = "Draw"

    /// How a schedule card draws a game in progress.
    var liveCardStyle = LiveCardStyle.periodFirst

    /// The roster filter menu, after its leading "All". The positions worth
    /// filtering by, and how the feed groups them, differ by league.
    var rosterFilters: [RosterFilterEntry] = []

    /// A bundled image the game sheet draws in place of the venue's photo,
    /// for leagues whose summaries carry none. Such a sheet names the venue
    /// alone rather than appending the city and state: the MLS summaries
    /// fold the state into the city.
    var venueBackdropAsset: String?

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
        periodStyle: .halves,
        rosterFilters: [
            .filter(RosterFilter(label: "Forwards", position: "Forward")),
            .filter(RosterFilter(label: "Guards", position: "Guard")),
        ]
    )

    static let nfl = LeagueDescriptor(
        id: .nfl,
        kind: .football,
        displayName: "NFL",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .quarters,
        drawLabel: "Tie",
        liveCardStyle: .scoreFirst,
        // The grouped roster feed files each player under a unit.
        rosterFilters: [
            .menu(title: "Defense", filters: RosterFilter.unit(
                "defense",
                positions: [
                    "Cornerback", "Defensive End", "Defensive Tackle",
                    "Linebacker", "Safety",
                ]
            )),
            .menu(title: "Offense", filters: RosterFilter.unit(
                "offense",
                positions: [
                    "Center", "Fullback", "Guard", "Quarterback",
                    "Running Back", "Offensive Tackle", "Tight End",
                    "Wide Receiver",
                ],
                // The menu shortens this one; the feed does not.
                labels: ["Offensive Tackle": "Tackle"]
            )),
            .menu(title: "Special Teams", filters: RosterFilter.unit(
                "specialTeam",
                positions: ["Long Snapper", "Place Kicker", "Punter"]
            )),
        ]
    )

    static let mlb = LeagueDescriptor(
        id: .mlb,
        kind: .baseball,
        displayName: "MLB",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(countsAbandonedGamesAsLosses: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .unnamed,
        rosterFilters: RosterFilter.positions([
            "Catcher", "Center Fielder", "First Baseman", "Relief Pitcher",
            "Second Baseman", "Shortstop", "Starting Pitcher", "Third Baseman",
        ]).map(RosterFilterEntry.filter)
    )

    static let mls = LeagueDescriptor(
        id: .mls,
        kind: .soccer,
        displayName: "MLS",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(usesDateForNextGame: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        // The menu's own names for the playing positions.
        rosterFilters: RosterFilter.positions(
            ["Goalkeeper", "Defender", "Midfielder", "Forward"],
            labels: ["Defender": "Defense", "Midfielder": "Midfield", "Forward": "Attacker"]
        ).map(RosterFilterEntry.filter),
        venueBackdropAsset: "soccerField"
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
