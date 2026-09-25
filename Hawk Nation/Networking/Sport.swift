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
