//
//  WidgetScheduleLoader.swift
//  myTeams
//
//  Created by Stephen Rector on 12/1/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation

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
        for team: Team,
        teamName: String = "Opponent",
        detail: String? = nil
    ) -> WidgetGame {
        WidgetGame(
            backgroundLogo: team.logo,
            teamName: teamName,
            gameDate: detail ?? "Date",
            gameTime: detail ?? "Time",
            gameChannel: detail ?? "Channel",
            teamLogo: nil,
            teamColor: team.color
        )
    }
}

// The teams the widgets cover are the canonical `Team` cases, defined in
// Networking/Sport.swift (shared with the app target). WidgetTeam used to be
// a fourth-hand copy of that list and had no Sporting case — which is why
// Sporting KC has never had a widget.

/// Shows the day of the week alongside the date, e.g. "Mon Jan 18, 2021".
private let widgetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E MMM d, y"
    // Same presentation zone as the app's schedule formatters (see
    // `scheduleDisplayZone` in DownloadScheduleData.swift): game dates read
    // in US Central regardless of where the phone is.
    formatter.timeZone = TimeZone(identifier: "America/Chicago")
    return formatter
}()

enum WidgetScheduleLoader {
    /// Loads a team's next fixture, or `nil` when the season has no games left
    /// to play.
    ///
    /// Shares the app's schedule parsing rather than repeating it, which is
    /// what the per-team loaders here used to do with a thousand lines of
    /// hand-written models apiece.
    static func nextGame(for team: Team) async -> WidgetGame? {
        let schedule = await downloadScheduleData(
            queryURL: team.scheduleURL,
            teamName: team.scheduleTeamName,
            teamNameField: team.scheduleNameField
        )

        // The widget wants the earliest fixture that has not kicked off yet.
        // The app locates the next game by walking completion flags
        // (`getNextGame`); with dates parsed as true instants the two agree on
        // every well-flagged schedule, and the widget keeps its date form
        // because it renders `nil` — not a clamped last game — after a season
        // ends, which the flag walk cannot express.
        guard let game = schedule
            .filter({ $0.dateAsDate >= Date() && !$0.cancelled })
            .min(by: { $0.dateAsDate < $1.dateAsDate })
        else { return nil }

        return WidgetGame(
            backgroundLogo: team.logo,
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
