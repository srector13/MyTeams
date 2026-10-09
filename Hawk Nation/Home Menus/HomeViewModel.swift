//
//  HomeViewModel.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation

/// A favorite's game on Home: the game as its schedule lists it, and the
/// favorite whose schedule that is.
struct HomeGame: Identifiable, Hashable, Sendable {
    let team: TeamRef
    let game: Game

    /// The game's id, so two favorites playing each other are one game.
    var id: String { game.gameID.isEmpty ? "\(team.id)|\(game.id)" : game.gameID }
}

/// A favorite's game under way, as the league's scoreboard has it now: the
/// same reading of the board a Live Activity takes
/// (`LiveActivityStateMapper`), so Home and the Lock Screen agree.
struct HomeLiveGame: Identifiable, Hashable, Sendable {
    let team: TeamRef
    /// The matchup: each side's name, home and away.
    let info: GameActivityInfo
    /// The scores and the stage, "4th Quarter · 0:48".
    let state: GameActivityState
    /// Whether the favorite is the home side.
    let favoriteIsHome: Bool
    /// The game as the favorite's schedule lists it, for its sheet and the
    /// opponent's crest; `nil` while the schedule has not loaded.
    let game: Game?

    var id: String { info.gameID }
}

/// A day of the favorites' upcoming games, under its date header.
struct HomeDay: Identifiable, Equatable, Sendable {
    /// The day's start.
    let date: Date
    /// In start order.
    let games: [HomeGame]

    var id: Date { date }
}

/// A story from a favorite's news feed, with the favorite it came from.
struct HomeHeadline: Identifiable, Hashable, Sendable {
    let team: TeamRef
    let article: News

    var id: String { article.id }
}

/// What Home shows, worked out from the favorites' seasons, the league
/// scoreboards and the news feeds as plain values, so the tests can drive
/// it.
enum HomeFeed {
    /// How far ahead Upcoming reaches.
    static let upcomingWindow: TimeInterval = 7 * 24 * 60 * 60

    /// How far back Recent Results reaches.
    static let resultsWindow: TimeInterval = 7 * 24 * 60 * 60

    /// The favorites' games under way on `boards`, in favorites order, each
    /// game once however many favorites play in it. A favorite's games are
    /// read from its league's board and its cups'.
    ///
    /// - Parameter seasons: each favorite's season by `TeamRef.ID`, for the
    ///   scheduled game a tile opens.
    static func liveGames(
        teams: [TeamRef],
        boards: [LeagueID: [ScoreboardGame]],
        seasons: [TeamRef.ID: [Game]]
    ) -> [HomeLiveGame] {
        var seen: Set<String> = []
        var result: [HomeLiveGame] = []
        for team in teams {
            for competition in [team.league] + team.league.descriptor.cupCompetitions {
                for board in boards[competition] ?? [] where board.state == "in" {
                    guard !seen.contains(board.gameID),
                          let side = board.competitors.first(where: { $0.teamID == team.espnID }),
                          let candidate = LiveActivityStateMapper.candidate(
                            for: board, teamID: team.espnID, homeLeague: team.league, league: competition
                          )
                    else { continue }
                    seen.insert(board.gameID)
                    result.append(HomeLiveGame(
                        team: team,
                        info: candidate.info,
                        state: candidate.state,
                        favoriteIsHome: side.homeAway == "home",
                        game: seasons[team.id]?.first { $0.gameID == board.gameID }
                    ))
                }
            }
        }
        return result
    }

    /// Every favorite's games, in favorites order, each game once.
    static func games(teams: [TeamRef], seasons: [TeamRef.ID: [Game]]) -> [HomeGame] {
        var seen: Set<String> = []
        var result: [HomeGame] = []
        for team in teams {
            for game in seasons[team.id] ?? [] {
                let entry = HomeGame(team: team, game: game)
                if seen.insert(entry.id).inserted {
                    result.append(entry)
                }
            }
        }
        return result
    }

    /// The favorites' games still to start within the next
    /// `upcomingWindow`, by day, soonest first; none when there are none.
    /// Games without a date are left out, and a game under way is Live
    /// Now's.
    static func upcomingDays(_ games: [HomeGame], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [HomeDay] {
        let latest = now.addingTimeInterval(upcomingWindow)
        let upcoming = games
            .filter { entry in
                let game = entry.game
                return !game.completed && !game.date.isEmpty
                    && game.dateAsDate >= now && game.dateAsDate <= latest
            }
            .sorted { $0.game.dateAsDate < $1.game.dateAsDate }

        var days: [HomeDay] = []
        for entry in upcoming {
            let day = calendar.startOfDay(for: entry.game.dateAsDate)
            if let last = days.last, last.date == day {
                days[days.count - 1] = HomeDay(date: day, games: last.games + [entry])
            } else {
                days.append(HomeDay(date: day, games: [entry]))
            }
        }
        return days
    }

    /// The favorites' games played out in the last `resultsWindow`, newest
    /// first. A game called off is not a result.
    static func results(_ games: [HomeGame], now: Date) -> [HomeGame] {
        let earliest = now.addingTimeInterval(-resultsWindow)
        return games
            .filter { entry in
                let game = entry.game
                return game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty
                    && game.dateAsDate >= earliest && game.dateAsDate <= now
            }
            .sorted { $0.game.dateAsDate > $1.game.dateAsDate }
    }

    /// Every story across the favorites' feeds, newest first, each story
    /// once (a story tagged with two favorites is in both feeds), as the
    /// first favorite in `teams` to list it. No cap: Home's news feed is
    /// the page's bottom layer and draws its rows lazily.
    static func headlines(teams: [TeamRef], articles: [TeamRef.ID: [News]]) -> [HomeHeadline] {
        var seen: Set<String> = []
        var merged: [HomeHeadline] = []
        for team in teams {
            for article in articles[team.id] ?? [] where seen.insert(article.id).inserted {
                merged.append(HomeHeadline(team: team, article: article))
            }
        }
        return merged.sorted { $0.article.publishedAt > $1.article.publishedAt }
    }

    /// One state for a section fed by every favorite's feed (P1's
    /// `SectionLoadState`): loaded once any feed has answered, failed only
    /// when every one failed, loading otherwise. Nothing to load is loaded.
    static func combinedState(_ states: [SectionLoadState]) -> SectionLoadState {
        if states.isEmpty || states.contains(.loaded) { return .loaded }
        if states.allSatisfy({ $0 == .failed }) { return .failed }
        return .loading
    }
}

/// Everything Home shows, gathered from what the app already loads: no
/// request of its own but the favorites' news feeds, which the team pages
/// read too.
///
/// - Live Now reads the league scoreboards `LeagueScoreboardCenter`
///   polls for every favorite while the app is in the foreground — the
///   same app-owned feed score alerts and Live Activities read.
/// - Upcoming and Recent Results read the favorites' seasons the center
///   loaded to know which boards to poll (`followedSeason(of:)`).
/// - The news feed merges each favorite's ESPN news feed
///   (`downloadNewsData`, up to the 25 stories `TeamRef.newsURL` asks
///   for), fetched again once `TeamFeed.news.timeToLive` has run out, as a
///   team page's is.
///
/// One cadence (`refreshInterval`, the center's): the clock moves on for
/// Upcoming and Recent Results, and any news feed past its time-to-live is
/// fetched.
/// The scoreboards redraw Home whenever the center's polls change them.
@MainActor
@Observable
final class HomeViewModel {
    /// How often Home looks again at the clock and its news feeds: the
    /// scoreboards' own once a minute.
    static let refreshInterval: Duration = .seconds(60)

    /// The favorites, in favorites order.
    private(set) var teams: [TeamRef] = []

    /// The moment Upcoming and Recent Results are worked out against, moved
    /// on each `refreshInterval`.
    private(set) var now: Date

    private var articles: [TeamRef.ID: [News]] = [:]
    private var newsStates: [TeamRef.ID: SectionLoadState] = [:]
    @ObservationIgnored private var newsLoadedAt: [TeamRef.ID: Date] = [:]
    /// When each favorite's news on screen was fetched, for the feeds served
    /// from the `FeedCache` (R-4).
    private var newsCachedAt: [TeamRef.ID: Date] = [:]

    private let scoreboards: LeagueScoreboardCenter
    private let loadNews: @Sendable (String) async -> Result<[News], NetworkError>
    private let clock: @MainActor () -> Date

    init(
        scoreboards: LeagueScoreboardCenter = .shared,
        loadNews: @escaping @Sendable (String) async -> Result<[News], NetworkError> = { await downloadNewsData(queryURL: $0) },
        now: @escaping @MainActor () -> Date = { HomeViewModel.launchNow() }
    ) {
        self.scoreboards = scoreboards
        self.loadNews = loadNews
        self.clock = now
        self.now = now()
    }

    /// The launch-environment key a UI test pins Home's clock with, in
    /// seconds since 1970, so the ±7-day windows read the same against the
    /// fixtures (`MYTEAMS_FIXTURES_DIR`) whenever the tests run. Read by
    /// Debug builds only.
    static let launchNowKey = "MYTEAMS_HOME_NOW"

    /// The time, or in a Debug build the moment `launchNowKey` pins.
    static func launchNow() -> Date {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[launchNowKey], let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        #endif
        return Date()
    }

    // MARK: Sections

    /// Each favorite's season, where the center has loaded it.
    private var seasons: [TeamRef.ID: [Game]] {
        var seasons: [TeamRef.ID: [Game]] = [:]
        for team in teams {
            if case .loaded(let games) = scoreboards.followedSeason(of: team.id) {
                seasons[team.id] = games
            }
        }
        return seasons
    }

    // The game sections show only when they have games (t_191edd79):
    // nothing to say while the seasons load or when one failed, which pull
    // to refresh asks for again.

    var liveGames: [HomeLiveGame] {
        HomeFeed.liveGames(teams: teams, boards: scoreboards.games, seasons: seasons)
    }

    var upcoming: [HomeDay] {
        HomeFeed.upcomingDays(HomeFeed.games(teams: teams, seasons: seasons), now: now)
    }

    var results: [HomeGame] {
        HomeFeed.results(HomeFeed.games(teams: teams, seasons: seasons), now: now)
    }

    var headlines: [HomeHeadline] {
        HomeFeed.headlines(teams: teams, articles: articles)
    }

    var headlinesState: SectionLoadState {
        HomeFeed.combinedState(teams.map { newsStates[$0.id] ?? .loading })
    }

    /// When the oldest news feed on screen was fetched, when any came from
    /// the `FeedCache` because the network could not be reached; `nil` when
    /// every one is the network's own. For an `UpdatedCaption`.
    var headlinesCachedAt: Date? {
        teams.compactMap { newsCachedAt[$0.id] }.min()
    }

    /// `game`'s live score for `team` on the scoreboard, for a game in
    /// Upcoming that has got under way since the last `refreshInterval`.
    func liveScore(for game: Game, team: TeamRef) -> LiveGameScore? {
        shouldPollLiveScore(game: game, now: now) ? scoreboards.liveScore(for: game, team: team) : nil
    }

    // MARK: Loading

    /// Shows `teams`, then keeps Home current for as long as it is on
    /// screen: SwiftUI cancels the task when it goes.
    func run(teams: [TeamRef]) async {
        self.teams = teams
        let ids = Set(teams.map(\.id))
        articles = articles.filter { ids.contains($0.key) }
        newsStates = newsStates.filter { ids.contains($0.key) }
        newsLoadedAt = newsLoadedAt.filter { ids.contains($0.key) }
        newsCachedAt = newsCachedAt.filter { ids.contains($0.key) }

        while !Task.isCancelled {
            now = clock()
            await refreshNews(force: false)
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                return
            }
        }
    }

    /// Pull to refresh: every favorite's news again, whatever its age, and
    /// any season that failed. What is on screen stays until each answer
    /// arrives. The scoreboards keep their own minute.
    func refreshAll() async {
        now = clock()
        async let news: Void = refreshNews(force: true)
        async let schedules: Void = scoreboards.retryFailedSchedules()
        _ = await (news, schedules)
    }

    /// Retries the news feeds that failed.
    func reloadNews() async {
        await refreshNews(force: false)
    }

    /// Fetches the favorites' news feeds that are due (`feedNeedsRefresh`):
    /// not loaded, failed, or past `TeamFeed.news.timeToLive`; all of them
    /// when `force`d.
    private func refreshNews(force: Bool) async {
        let current = clock()
        let due = teams.filter { team in
            force || feedNeedsRefresh(
                state: newsStates[team.id] ?? .loading,
                loadedAt: newsLoadedAt[team.id],
                timeToLive: TeamFeed.news.timeToLive,
                now: current
            )
        }
        guard !due.isEmpty else { return }

        // A feed that failed shows its placeholder again while it retries.
        for team in due where newsStates[team.id] == .failed {
            newsStates[team.id] = .loading
        }

        let load = loadNews
        let answers = await withTaskGroup(
            of: (TeamRef.ID, Result<[News], NetworkError>, Date?).self,
            returning: [(TeamRef.ID, Result<[News], NetworkError>, Date?)].self
        ) { group in
            for team in due {
                let id = team.id
                let url = team.newsURL
                group.addTask {
                    // Stored as it loads, and read back offline (R-4).
                    let (result, cachedAt) = await HTTPClient.withFeedCache(.persist) { await load(url) }
                    return (id, result, cachedAt)
                }
            }
            var answers: [(TeamRef.ID, Result<[News], NetworkError>, Date?)] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }

        for (id, result, cachedAt) in answers {
            apply(news: result, cachedAt: cachedAt, for: id)
        }
    }

    /// Publishes a news fetch. A failure keeps what is already on screen,
    /// and a cancelled fetch (Home went away mid-load) changes nothing, as
    /// on a team page (`TeamModel`). News served from the cache is shown but
    /// not counted as loaded, so the next `refreshInterval` asks again.
    private func apply(news result: Result<[News], NetworkError>, cachedAt: Date?, for id: TeamRef.ID) {
        switch result {
        case .success(let loaded):
            newsStates[id] = .loaded
            newsLoadedAt[id] = cachedAt == nil ? clock() : nil
            newsCachedAt[id] = cachedAt
            articles[id] = loaded
        case .failure(let error):
            if case .cancelled = error { return }
            if (articles[id] ?? []).isEmpty {
                newsStates[id] = .failed
            }
        }
    }
}
