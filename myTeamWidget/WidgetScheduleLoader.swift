//
//  WidgetScheduleLoader.swift
//  myTeams
//
//  Created by Stephen Rector on 12/1/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The next fixture, as the widget renders it.
struct WidgetGame: Sendable {
    var backgroundLogo: String
    var teamName: String
    var gameDate: String
    var gameTime: String
    var gameChannel: String

    /// The opponent's crest, fetched alongside the schedule.
    ///
    /// Widgets get one short window to build a timeline and cannot load
    /// anything while rendering, so the image travels with the entry rather
    /// than being fetched from the view.
    var teamLogo: Data?

    var teamColor: Color

    /// The entry shown in the widget gallery, and whenever a load fails.
    static func placeholder(
        for team: WidgetTeam,
        teamName: String = "Opponent",
        detail: String? = nil
    ) -> WidgetGame {
        WidgetGame(
            backgroundLogo: team.sport.rawValue,
            teamName: teamName,
            gameDate: detail ?? "Date",
            gameTime: detail ?? "Time",
            gameChannel: detail ?? "Channel",
            teamLogo: nil,
            teamColor: team.color
        )
    }
}

/// The teams that have a widget. Sporting Kansas City has never had one.
enum WidgetTeam: Sendable {
    case jayhawks
    case chiefs
    case royals

    var sport: Sport {
        switch self {
        case .jayhawks: .jayhawk
        case .chiefs: .chiefs
        case .royals: .royals
        }
    }

    var color: Color {
        switch self {
        case .jayhawks: Color(red: 0 / 255, green: 81 / 255, blue: 186 / 255)
        case .chiefs: Color(red: 227 / 255, green: 24 / 255, blue: 55 / 255)
        case .royals: Color(red: 0 / 255, green: 70 / 255, blue: 135 / 255)
        }
    }

    /// The name this team goes by in its own schedule feed.
    var teamName: String {
        switch self {
        case .jayhawks: "Kansas"
        case .chiefs: "KC"
        case .royals: "Royals"
        }
    }

    var teamNameField: TeamNameField {
        switch self {
        case .jayhawks, .chiefs: .nickname
        case .royals: .shortDisplayName
        }
    }

    var scheduleURL: String {
        switch self {
        case .jayhawks:
            "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/schedule"
        case .chiefs:
            "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule"
        case .royals:
            "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/7/schedule"
        }
    }
}

/// Shows the day of the week alongside the date, e.g. "Mon Jan 18, 2021".
private let widgetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E MMM d, y"
    return formatter
}()

enum WidgetScheduleLoader {
    /// Loads a team's next fixture, or `nil` when the season has no games left
    /// to play.
    ///
    /// Shares the app's schedule parsing rather than repeating it, which is
    /// what the per-team loaders here used to do with a thousand lines of
    /// hand-written models apiece.
    static func nextGame(for team: WidgetTeam) async -> WidgetGame? {
        let schedule = await downloadScheduleData(
            queryURL: team.scheduleURL,
            teamName: team.teamName,
            teamNameField: team.teamNameField
        )

        guard let game = schedule
            .filter({ $0.dateAsDate >= Date() && !$0.cancelled })
            .min(by: { $0.dateAsDate < $1.dateAsDate })
        else { return nil }

        return WidgetGame(
            backgroundLogo: team.sport.rawValue,
            teamName: game.opponent,
            gameDate: widgetDateFormatter.string(from: game.dateAsDate),
            gameTime: game.time,
            gameChannel: game.channel,
            teamLogo: await logoData(game.opponentLogo),
            teamColor: team.color
        )
    }

    private static func logoData(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}
