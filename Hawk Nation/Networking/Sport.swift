//
//  Sport.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The four teams the app follows, and everything that differs between them
/// when reading a game summary.
///
/// Each case's raw value is the logo asset name, which is also the identifier
/// the views pass around to say which team they are showing.
enum Sport: String, Sendable, CaseIterable {
    case jayhawk
    case chiefs
    case royals
    case sporting

    /// The ESPN league path this team's summaries live under.
    var summaryPath: String {
        switch self {
        case .jayhawk: "basketball/mens-college-basketball"
        case .chiefs: "football/nfl"
        case .royals: "baseball/mlb"
        case .sporting: "soccer/usa.1"
        }
    }

    /// How the followed team is named in a summary's `boxscore.teams` entries.
    var boxscoreName: String {
        switch self {
        case .jayhawk: "Kansas"
        case .chiefs: "Chiefs"
        case .royals: "Royals"
        case .sporting: "Kansas City"
        }
    }

    /// The city the team plays home games in.
    var homeCity: String {
        switch self {
        case .jayhawk: "Lawrence"
        case .chiefs, .royals, .sporting: "Kansas City"
        }
    }

    /// The team's own colour, used to tint a home game. Away games take the
    /// host team's colour from the feed instead.
    var homeColor: String {
        switch self {
        case .jayhawk: "0051BA"
        case .chiefs: "E31837"
        case .royals: "004687"
        case .sporting: "002A5C"
        }
    }

    func summaryURL(gameID: String) -> String {
        "https://site.api.espn.com/apis/site/v2/sports/\(summaryPath)/summary?event=\(gameID)"
    }
}
