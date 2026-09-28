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
    /// The followed team's crest, drawn faintly behind the fixture. Read from
    /// `LogoStore`; the widget no longer bundles crests.
    var backgroundLogo: Data?
    var teamName: String
    var gameDate: String
    var gameTime: String
    var gameChannel: String

    /// The opponent's crest, read from `LogoStore` (or fetched into it)
    /// alongside the schedule.
    ///
    /// Widgets get one short window to build a timeline and cannot load
    /// anything while rendering, so the image travels with the entry rather
    /// than being fetched from the view.
    var teamLogo: Data?

    var teamColor: Color

    /// The entry shown in the widget gallery, and whenever a load fails.
    static func placeholder(
        for team: TeamRef,
        teamName: String = "Opponent",
        detail: String? = nil
    ) -> WidgetGame {
        WidgetGame(
            backgroundLogo: WidgetScheduleLoader.storedCrest(for: team),
            teamName: teamName,
            gameDate: detail ?? "Date",
            gameTime: detail ?? "Time",
            gameChannel: detail ?? "Channel",
            teamLogo: nil,
            teamColor: team.color
        )
    }
}

// The teams the widgets cover come from the bundled catalog
// (`TeamCatalog`, Networking/TeamRef.swift, shared with the app target; the
// widget bundles its own copy of teams.json). WidgetTeam used to be a
// fourth-hand copy of the team list and had no Sporting case — the reason
// Sporting KC lacked a widget until the bundle grew its fourth entry.

/// Shows the day of the week alongside the date, e.g. "Mon Jan 18, 2021".
private let widgetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E MMM d, y"
    // Same presentation zone as the app's schedule formatters (see
    // `scheduleDisplayZone` in DownloadScheduleData.swift): the device's own.
    formatter.timeZone = .autoupdatingCurrent
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
    static func nextGame(for team: TeamRef) async -> WidgetLoadResult {
        let result = await downloadScheduleData(team: team)
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

        async let background = crest(for: team, favorite: true)
        async let opponentLogo = opponentCrest(for: game, following: team)
        let widgetGame = WidgetGame(
            backgroundLogo: await background,
            teamName: game.opponent,
            gameDate: widgetDateFormatter.string(from: game.dateAsDate),
            gameTime: game.time,
            gameChannel: game.channel,
            teamLogo: await opponentLogo,
            teamColor: team.color
        )
        return .game(widgetGame, kickoff: game.dateAsDate)
    }

    /// Loads a team's next fixture, giving up as `.failed` after `deadline`.
    ///
    /// The widget gallery wants its snapshot back within moments; a slow
    /// network should fall back to sample data rather than hold it up.
    static func nextGame(for team: TeamRef, within deadline: Duration) async -> WidgetLoadResult {
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

    /// A crest already in `LogoStore`, read synchronously.
    static func storedCrest(for team: TeamRef) -> Data? {
        LogoStore.url(for: team, variant: .default).flatMap { try? Data(contentsOf: $0) }
    }

    /// A team's crest from `LogoStore`, downloading it into the store first
    /// if it is not there. Stored crests are reused across timelines, so the
    /// hourly reload no longer downloads them again.
    private static func crest(for team: TeamRef, favorite: Bool) async -> Data? {
        if let stored = storedCrest(for: team) {
            return stored
        }
        await LogoStore.prefetched(team, variant: .default, favorite: favorite)
        return storedCrest(for: team)
    }

    /// The opponent's crest, stored under its ESPN id.
    ///
    /// Schedule competitors carry `team.id` but not always a league, so the
    /// opponent is filed under the followed team's league; pro opponents are
    /// always same-league. An opponent without an id is downloaded but not
    /// stored. Uses the app's session, whose timeouts keep a stalled image
    /// from eating the widget's short refresh window.
    private static func opponentCrest(for game: Game, following team: TeamRef) async -> Data? {
        guard let url = URL(string: game.opponentLogo) else { return nil }
        guard !game.opponentID.isEmpty else {
            guard let data = try? await HTTPClient.defaultSession.data(from: url).0 else { return nil }
            return LogoStore.downscaledPNG(data)
        }
        let opponent = TeamRef(
            league: team.league,
            espnID: game.opponentID,
            displayName: game.opponent,
            shortName: game.opponent,
            abbreviation: "",
            location: "",
            colorHex: "",
            alternateColorHex: "",
            logoURL: url,
            logoDarkURL: nil,
            logoAsset: nil
        )
        return await crest(for: opponent, favorite: false)
    }

    /// Refreshes the followed team's league catalog, at most daily. The
    /// catalog itself is cached for a week, so most calls do nothing.
    static func refreshCatalog(for team: TeamRef) async {
        await RemoteTeamCatalog.shared.refreshIfDue(team.league, minimumInterval: 24 * 60 * 60)
    }
}
