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
// a fourth-hand copy of that list and had no Sporting case — the reason
// Sporting KC lacked a widget until the bundle grew its fourth entry.

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

/// What the widget found when it looked for the next fixture.
enum WidgetLoadResult: Sendable {
    /// The next fixture, and when it starts.
    case game(WidgetGame, kickoff: Date)
    /// The schedule loaded but has no games left to play.
    case seasonOver
    /// The schedule could not be loaded (or, for a gallery preview, not in
    /// time).
    case failed
}

enum WidgetScheduleLoader {
    /// Loads a team's next fixture.
    ///
    /// Shares the app's schedule parsing rather than repeating it, which is
    /// what the per-team loaders here used to do with a thousand lines of
    /// hand-written models apiece.
    static func nextGame(for team: Team) async -> WidgetLoadResult {
        let result = await downloadScheduleData(
            queryURL: team.scheduleURL,
            teamName: team.scheduleTeamName,
            teamNameField: team.scheduleNameField
        )
        guard case .success(let schedule) = result else { return .failed }

        // The widget wants the earliest fixture that has not kicked off yet.
        // The app locates the next game by walking completion flags
        // (`getNextGame`); with dates parsed as true instants the two agree on
        // every well-flagged schedule, and the widget keeps its date form
        // because it renders `nil` — not a clamped last game — after a season
        // ends, which the flag walk cannot express. Status flags the app does
        // honour are honoured here too: a fixture the app counts as played
        // (cancelled or postponed) is never offered as the widget's next game.
        guard let game = schedule
            .filter({ $0.dateAsDate >= Date() && !$0.cancelled && !$0.postponed })
            .min(by: { $0.dateAsDate < $1.dateAsDate })
        else { return .seasonOver }

        let widgetGame = WidgetGame(
            backgroundLogo: team.logo,
            teamName: game.opponent,
            gameDate: widgetDateFormatter.string(from: game.dateAsDate),
            gameTime: game.time,
            gameChannel: game.channel,
            teamLogo: await logoData(game.opponentLogo),
            teamColor: team.color
        )
        return .game(widgetGame, kickoff: game.dateAsDate)
    }

    /// Loads a team's next fixture, giving up as `.failed` after `deadline`.
    ///
    /// The widget gallery wants its snapshot back within moments; a slow
    /// network should fall back to sample data rather than hold it up.
    static func nextGame(for team: Team, within deadline: Duration) async -> WidgetLoadResult {
        await withTaskGroup(of: WidgetLoadResult.self) { group in
            group.addTask {
                await WidgetScheduleLoader.nextGame(for: team)
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return .failed
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }
    }

    /// Fetches the opponent's crest. Uses the app's session, whose timeouts
    /// keep a stalled image from eating the widget's short refresh window.
    private static func logoData(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await HTTPClient.defaultSession.data(from: url).0
    }
}
