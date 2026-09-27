//
//  Sport.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI

/// The canonical identity of the four teams the app follows.
///
/// This enum used to exist three times over — as `Sport` (ESPN paths and
/// network identity, here), as `Team` (display names, logos and colours, in
/// TabBar.swift) and as `WidgetTeam` (the widget's own partial copy). The
/// copies drifted: the widget list lacked Sporting KC, and colours were
/// spelled out twice by hand. Everything a team needs now lives in this one
/// switch, and the app, the widget, and the team pages all read from it.
///
/// The raw value is the logo asset name, which doubles as the stable
/// identifier for any serialization.
enum Team: String, Sendable, CaseIterable, Identifiable {
    case jayhawks = "jayhawk"
    case chiefs
    case royals
    case sporting

    var id: Self { self }

    // MARK: - Display

    /// The full name shown in the header and the sticky title bar.
    var displayName: String {
        switch self {
        case .jayhawks: "Kansas Jayhawks"
        case .chiefs: "Kansas City Chiefs"
        case .royals: "Kansas City Royals"
        case .sporting: "Sporting Kansas City"
        }
    }

    /// The short name shown beside the crest on the selected tab.
    var shortName: String {
        switch self {
        case .jayhawks: "Jayhawks"
        case .chiefs: "Chiefs"
        case .royals: "Royals"
        case .sporting: "Sporting"
        }
    }

    /// The asset name of the team crest. Equal to the raw value.
    var logo: String { rawValue }

    /// The team crest, for views that used to hardcode `Image("jayhawk")`.
    var logoImage: Image { Image(logo) }

    // MARK: - Colour

    /// The brand colour as RGB bytes — the single source for both
    /// representations below.
    private var brandRGB: (red: Int, green: Int, blue: Int) {
        switch self {
        case .jayhawks: (0, 81, 186)
        case .chiefs: (227, 24, 55)
        case .royals: (0, 70, 135)
        case .sporting: (0, 42, 92)
        }
    }

    /// The team's colour for SwiftUI views.
    var color: Color {
        Color(
            red: Double(brandRGB.red) / 255,
            green: Double(brandRGB.green) / 255,
            blue: Double(brandRGB.blue) / 255
        )
    }

    /// The same colour as the six-digit hex string ESPN uses in its feeds,
    /// used to tint a home game (away games take the host's colour from the
    /// feed instead).
    var brandHex: String {
        String(
            format: "%02X%02X%02X",
            brandRGB.red, brandRGB.green, brandRGB.blue
        )
    }

    // MARK: - ESPN network identity

    /// The ESPN league path this team's data lives under.
    var leaguePath: String {
        switch self {
        case .jayhawks: "basketball/mens-college-basketball"
        case .chiefs: "football/nfl"
        case .royals: "baseball/mlb"
        case .sporting: "soccer/usa.1"
        }
    }

    /// The team's id in ESPN's site API.
    var espnTeamId: Int {
        switch self {
        case .jayhawks: 2305
        case .chiefs: 12
        case .royals: 7
        case .sporting: 186
        }
    }

    /// The city the team plays home games in.
    var homeCity: String {
        switch self {
        case .jayhawks: "Lawrence"
        case .chiefs, .royals, .sporting: "Kansas City"
        }
    }

    /// How the team is named in a summary's `boxscore.teams` / header
    /// competitor entries (`shortDisplayName`).
    var boxscoreName: String {
        switch self {
        case .jayhawks: "Kansas"
        case .chiefs: "Chiefs"
        case .royals: "Royals"
        case .sporting: "Kansas City"
        }
    }

    /// The name this team goes by in its own schedule feed, and the field
    /// that carries it. The feeds disagree: the Chiefs' `nickname` is "KC"
    /// while the summary's `shortDisplayName` is "Chiefs", and the soccer
    /// feed only names itself in `shortDisplayName`.
    var scheduleTeamName: String {
        switch self {
        case .jayhawks: "Kansas"
        case .chiefs: "KC"
        case .royals: "Royals"
        case .sporting: "Kansas City"
        }
    }

    var scheduleNameField: TeamNameField {
        switch self {
        case .jayhawks, .chiefs: .nickname
        case .royals, .sporting: .shortDisplayName
        }
    }

    // MARK: - URLs

    var scheduleURL: String {
        "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/teams/\(espnTeamId)/schedule"
    }

    func summaryURL(gameID: String) -> String {
        "https://site.api.espn.com/apis/site/v2/sports/\(leaguePath)/summary?event=\(gameID)"
    }
}

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
