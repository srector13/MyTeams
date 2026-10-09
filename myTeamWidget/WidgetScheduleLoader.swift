//
//  WidgetScheduleLoader.swift
//  myTeams
//
//  Created by Stephen Rector on 12/1/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation

/// The featured game, as the widget renders it: the next fixture, or a game
/// under way or just finished (C-5).
struct WidgetGame: Sendable {
    /// The followed team's crest, drawn faintly behind the fixture. Read from
    /// `LogoStore`; the widget no longer bundles crests.
    var backgroundLogo: Data?
    /// The opponent.
    var teamName: String
    /// The date of a fixture; for a game under way or finished, its status
    /// ("Live · 67'", "Final").
    var gameDate: String
    /// The start time of a fixture; for a game under way or finished, the
    /// score, the followed team's first.
    var gameTime: String
    /// The channel, or `nil` where the feed named none (the parser's "TBD")
    /// or the game is no longer to be watched.
    var gameChannel: String?

    /// The opponent's crest, read from `LogoStore` (or fetched into it)
    /// alongside the schedule.
    ///
    /// Widgets get one short window to build a timeline and cannot load
    /// anything while rendering, so the image travels with the entry rather
    /// than being fetched from the view.
    var teamLogo: Data?

    /// The followed team, whose colour and crest the widget is drawn in.
    var team: TeamRef

    /// When set, there is no game to show: the tile draws this one line with
    /// the followed team's crest instead of a fixture (B-16).
    var message: String? = nil

    /// The game on one line, for the Lock Screen's `.accessoryInline`
    /// (R-9): "KC 21–17 Q3", "KC vs BUF 7:20 PM" (`WidgetDayBuilder`).
    var inline: String = ""

    /// The followed team's colour, or a stable fallback when the feed gives
    /// none: the fill `teamInk(on:)` picks its ink against.
    var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    /// The entry shown in the widget gallery.
    static func placeholder(for team: TeamRef) -> WidgetGame {
        WidgetGame(
            backgroundLogo: WidgetScheduleLoader.storedCrest(for: team),
            teamName: "Opponent",
            gameDate: "Date",
            gameTime: "Time",
            gameChannel: "Channel",
            teamLogo: nil,
            team: team,
            inline: "\(WidgetDayBuilder.label(of: team)) vs Opponent"
        )
    }

    /// The followed team's crest and one honest line, for a season that is
    /// over ("No upcoming games") or a load that failed ("Couldn't update").
    static func notice(_ message: String, for team: TeamRef) -> WidgetGame {
        WidgetGame(
            backgroundLogo: WidgetScheduleLoader.storedCrest(for: team),
            teamName: team.shortName,
            gameDate: "",
            gameTime: "",
            gameChannel: nil,
            teamLogo: nil,
            team: team,
            message: message,
            inline: WidgetDayBuilder.inlineNotice(team: team, message: message)
        )
    }

    /// The channel as the schedule cards show it: hidden when the feed named
    /// none (`GameCardContent.broadcast(of:)`).
    static func broadcast(_ channel: String) -> String? {
        WidgetDayBuilder.broadcast(channel)
    }
}

// The team a widget covers comes from its configuration (`SelectTeamIntent`)
// or the reader's favorites, resolved by `WidgetTeams` (TeamEntity.swift).

/// The date with its day of the week, in the reader's own order (A-13), e.g.
/// "Mon, Jan 18, 2021" or "Mon 18 Jan 2021".
private let widgetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("EEEyMMMd")
    // Same presentation zone as the app's schedule formatters (see
    // `scheduleDisplayZone` in DownloadScheduleData.swift): the device's own.
    formatter.timeZone = .autoupdatingCurrent
    return formatter
}()

/// The start time on the reader's own 12- or 24-hour clock (A-13), e.g.
/// "7:30 PM" or "19:30".
private let widgetTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("jmm")
    formatter.timeZone = .autoupdatingCurrent
    return formatter
}()

/// What the widget found when it looked for a game to feature.
enum WidgetLoadResult: Sendable {
    /// The game to show, and when the widget should look again: a fixture's
    /// kickoff, soon for a game under way, tomorrow for a result.
    case game(WidgetGame, refresh: Date)
    /// The schedule loaded but has no games left to play.
    case seasonOver
    /// The schedule could not be loaded (or, for a gallery preview, not in
    /// time).
    case failed
}

enum WidgetScheduleLoader {
    /// How soon a widget showing a game under way looks again.
    static let liveRefreshInterval: TimeInterval = 5 * 60

    /// How old a stored schedule (`FeedCache`, R-4) may be and still be used
    /// without asking ESPN: a timeline reload within it reads the disk. Older,
    /// the network is asked, and the stored copy answers when it can't be
    /// reached.
    static let scheduleCacheMaxAge: TimeInterval = 5 * 60

    /// Loads the game a team's widget features: the one under way, else
    /// today's result, else the next fixture (`WidgetFeaturedGame.pick`).
    ///
    /// Games under way come from the scoreboard snapshot the app writes to
    /// the App Group (`WidgetScoreboardCodec`); without a fresh one, the
    /// schedule alone decides. Shares the app's schedule parsing rather than
    /// repeating it, which is what the per-team loaders here used to do with
    /// a thousand lines of hand-written models apiece.
    static func featuredGame(for team: TeamRef, now: Date = Date()) async -> WidgetLoadResult {
        let schedule = await self.schedule(for: team)

        let featured = WidgetFeaturedGame.pick(
            teamID: team.id,
            snapshots: WidgetScoreboardCodec.read(),
            schedule: schedule ?? [],
            now: now
        )

        async let background = crest(for: team, favorite: true)
        switch featured {
        case .live(let snapshot), .result(let snapshot):
            // The schedule's own entry for the game, when it loaded, names
            // the opponent as the rest of the app does and carries its crest.
            let scheduled = schedule?.first { !$0.gameID.isEmpty && $0.gameID == snapshot.gameID }
            async let opponentLogo = opponentCrest(of: snapshot, scheduled: scheduled, following: team)
            let widgetGame = WidgetGame(
                backgroundLogo: await background,
                teamName: scheduled?.opponent ?? snapshot.opponentName(of: team.espnID),
                gameDate: snapshot.statusText,
                gameTime: snapshot.score(for: team.espnID),
                gameChannel: snapshot.state == .inProgress ? scheduled.flatMap { WidgetGame.broadcast($0.channel) } : nil,
                teamLogo: await opponentLogo,
                team: team,
                inline: snapshot.state == .inProgress
                    ? WidgetDayBuilder.inlineLive(team: team, snapshot: snapshot)
                    : WidgetDayBuilder.inlineFinal(team: team, score: snapshot.score(for: team.espnID))
            )
            let refresh = snapshot.state == .inProgress ? now + liveRefreshInterval : startOfTomorrow(after: now)
            return .game(widgetGame, refresh: refresh)
        case .scheduleResult(let game):
            async let opponentLogo = opponentCrest(for: game, following: team)
            let widgetGame = WidgetGame(
                backgroundLogo: await background,
                teamName: game.opponent,
                gameDate: "Final",
                gameTime: "\(game.score)–\(game.opponentScore)",
                gameChannel: nil,
                teamLogo: await opponentLogo,
                team: team,
                inline: WidgetDayBuilder.inlineFinal(team: team, score: "\(game.score)–\(game.opponentScore)")
            )
            return .game(widgetGame, refresh: startOfTomorrow(after: now))
        case .next(let game):
            async let opponentLogo = opponentCrest(for: game, following: team)
            let day = WidgetDayBuilder()
            let opponent = day.opponentAbbreviation(
                league: game.competition ?? team.league, espnID: game.opponentID, name: game.opponent
            )
            let widgetGame = WidgetGame(
                backgroundLogo: await background,
                teamName: game.opponent,
                gameDate: widgetDateFormatter.string(from: game.dateAsDate),
                gameTime: widgetTimeFormatter.string(from: game.dateAsDate),
                gameChannel: WidgetGame.broadcast(game.channel),
                teamLogo: await opponentLogo,
                team: team,
                inline: day.inlineUpcoming(team: team, opponent: opponent, start: game.dateAsDate, now: now)
            )
            // Once the game starts it is no longer the next one; look again
            // then, for its live score or the following fixture.
            return .game(widgetGame, refresh: game.dateAsDate)
        case .none:
            return schedule == nil ? .failed : .seasonOver
        }
    }

    /// A team's season: the stored copy while it is fresh (R-4), else the
    /// network's, else the stored copy whatever its age; `nil` when none
    /// could be had.
    static func schedule(for team: TeamRef) async -> [Game]? {
        let result = await HTTPClient.withFeedCache(.preferCache(maxAge: scheduleCacheMaxAge)) {
            await downloadScheduleData(team: team)
        }.value
        if case .success(let games) = result {
            return games
        }
        return nil
    }

    /// The favorites' seasons, loaded side by side, for "My Day" (R-9). A
    /// season that could not be had is left out.
    static func seasons(for teams: [TeamRef]) async -> [TeamRef.ID: [Game]] {
        await withTaskGroup(of: (TeamRef.ID, [Game]?).self, returning: [TeamRef.ID: [Game]].self) { group in
            for team in teams {
                group.addTask {
                    (team.id, await WidgetScheduleLoader.schedule(for: team))
                }
            }
            var seasons: [TeamRef.ID: [Game]] = [:]
            for await (id, games) in group {
                if let games {
                    seasons[id] = games
                }
            }
            return seasons
        }
    }

    /// The pixel size "My Day" reads crests at: its rows draw them at 28 pt,
    /// and a large timeline holds up to twelve, so the stored 256 px
    /// (`LogoStore.maxPixelSize`) would spend the widget's memory budget for
    /// nothing.
    static let dayCrestPixelSize = 84

    /// A "My Day" row with its crests: the favorite's and the opponent's, as
    /// `LogoStore` already holds them, downscaled. Nothing is downloaded;
    /// the favorites' crests are kept current by the app.
    static func dayRow(_ row: WidgetDayRow) -> DayEntry.Row {
        var opponent: Data?
        if !row.opponentID.isEmpty {
            opponent = storedCrest(for: opponentRef(league: row.league, espnID: row.opponentID, name: row.opponentName, logoURL: nil))
                ?? storedCrest(for: opponentRef(league: row.team.league, espnID: row.opponentID, name: row.opponentName, logoURL: nil))
        }
        return DayEntry.Row(
            row: row,
            teamCrest: storedCrest(for: row.team).flatMap(dayCrest),
            opponentCrest: opponent.flatMap(dayCrest)
        )
    }

    private static func dayCrest(_ data: Data) -> Data? {
        LogoStore.downscaledPNG(data, maxPixelSize: dayCrestPixelSize)
    }

    /// Midnight after `date`: when today's result gives way to the next
    /// fixture.
    private static func startOfTomorrow(after date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date + 24 * 60 * 60
    }

    /// Loads a team's featured game, giving up as `.failed` after
    /// `deadline`.
    ///
    /// The widget gallery wants its snapshot back within moments; a slow
    /// network should fall back to sample data rather than hold it up.
    static func featuredGame(for team: TeamRef, within deadline: Duration) async -> WidgetLoadResult {
        await withTaskGroup(of: WidgetLoadResult.self) { group in
            group.addTask {
                await WidgetScheduleLoader.featuredGame(for: team)
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
        let opponent = opponentRef(league: team.league, espnID: game.opponentID, name: game.opponent, logoURL: url)
        return await crest(for: opponent, favorite: false)
    }

    /// The opponent's crest in a snapshot's game: the schedule entry's, when
    /// the schedule has the game, else whatever `LogoStore` already holds
    /// under the board's league (a snapshot carries no logo URL).
    private static func opponentCrest(
        of snapshot: WidgetScoreboardSnapshot,
        scheduled: Game?,
        following team: TeamRef
    ) async -> Data? {
        if let scheduled {
            return await opponentCrest(for: scheduled, following: team)
        }
        let opponentID = snapshot.opponentID(of: team.espnID)
        guard !opponentID.isEmpty else { return nil }
        let league = LeagueID(path: snapshot.league) ?? team.league
        let name = snapshot.opponentName(of: team.espnID)
        return storedCrest(for: opponentRef(league: league, espnID: opponentID, name: name, logoURL: nil))
            ?? storedCrest(for: opponentRef(league: team.league, espnID: opponentID, name: name, logoURL: nil))
    }

    /// A stand-in `TeamRef` for an opponent, enough to file its crest under.
    private static func opponentRef(league: LeagueID, espnID: String, name: String, logoURL: URL?) -> TeamRef {
        TeamRef(
            league: league,
            espnID: espnID,
            displayName: name,
            shortName: name,
            abbreviation: "",
            location: "",
            colorHex: "",
            alternateColorHex: "",
            logoURL: logoURL,
            logoDarkURL: nil,
            logoAsset: nil
        )
    }

    /// Refreshes the followed team's league catalog, at most daily. The
    /// catalog itself is cached for a week, so most calls do nothing.
    static func refreshCatalog(for team: TeamRef) async {
        await RemoteTeamCatalog.shared.refreshIfDue(team.league, minimumInterval: 24 * 60 * 60)
    }
}
