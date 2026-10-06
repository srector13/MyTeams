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

/// A day of favorites' games: today's, or tomorrow's on a day without any.
struct HomeDay: Equatable, Sendable {
    /// The day's start.
    let date: Date
    let isToday: Bool
    /// In start order.
    let games: [HomeGame]
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
    /// How far back Results reaches.
    static let resultsWindow: TimeInterval = 48 * 60 * 60

    /// The most headlines Home shows.
    static let headlineCount = 5

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

    /// The favorites' games today in start order, or tomorrow's when there
    /// are none today; `nil` when there are none either day. Games without
    /// a date are left out.
    static func upcomingDay(_ games: [HomeGame], now: Date, calendar: Calendar = .autoupdatingCurrent) -> HomeDay? {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        for (day, isToday) in [(today, true), (tomorrow, false)] {
            let onDay = games
                .filter { !$0.game.date.isEmpty && calendar.isDate($0.game.dateAsDate, inSameDayAs: day) }
                .sorted { $0.game.dateAsDate < $1.game.dateAsDate }
            if !onDay.isEmpty {
                return HomeDay(date: day, isToday: isToday, games: onDay)
            }
        }
        return nil
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

    /// The newest `headlineCount` stories across the favorites' feeds, each
    /// story once (a story tagged with two favorites is in both feeds), as
    /// the first favorite in `teams` to list it.
    static func headlines(teams: [TeamRef], articles: [TeamRef.ID: [News]]) -> [HomeHeadline] {
        var seen: Set<String> = []
        var merged: [HomeHeadline] = []
        for team in teams {
            for article in articles[team.id] ?? [] where seen.insert(article.id).inserted {
                merged.append(HomeHeadline(team: team, article: article))
            }
        }
        return Array(merged.sorted { $0.article.publishedAt > $1.article.publishedAt }.prefix(headlineCount))
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
/// - Today and Results read the favorites' seasons the center loaded to
///   know which boards to poll (`followedSeason(of:)`).
/// - Headlines merges each favorite's ESPN news feed
///   (`downloadNewsData`), fetched again once `TeamFeed.news.timeToLive`
///   has run out, as a team page's is.
///
/// One cadence (`refreshInterval`, the center's): the clock moves on for
/// Today and Results, and any news feed past its time-to-live is fetched.
/// The scoreboards redraw Home whenever the center's polls change them.
@MainActor
@Observable
final class HomeViewModel {
    /// How often Home looks again at the clock and its news feeds: the
    /// scoreboards' own once a minute.
    static let refreshInterval: Duration = .seconds(60)

    /// The favorites, in favorites order.
    private(set) var teams: [TeamRef] = []

    /// The moment Today and Results are worked out against, moved on each
    /// `refreshInterval`.
    private(set) var now: Date

    private var articles: [TeamRef.ID: [News]] = [:]
    private var newsStates: [TeamRef.ID: SectionLoadState] = [:]
    @ObservationIgnored private var newsLoadedAt: [TeamRef.ID: Date] = [:]

    private let scoreboards: LeagueScoreboardCenter
    private let loadNews: @Sendable (String) async -> Result<[News], NetworkError>
    private let clock: @MainActor () -> Date

    init(
        scoreboards: LeagueScoreboardCenter = .shared,
        loadNews: @escaping @Sendable (String) async -> Result<[News], NetworkError> = { await downloadNewsData(queryURL: $0) },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.scoreboards = scoreboards
        self.loadNews = loadNews
        self.clock = now
        self.now = now()
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

    /// Where the favorites' seasons stand, for Today and Results.
    var scheduleState: SectionLoadState {
        HomeFeed.combinedState(teams.map { Self.loadState(of: scoreboards.followedSeason(of: $0.id)) })
    }

    private static func loadState(of season: LeagueScoreboardCenter.FollowedSeason) -> SectionLoadState {
        switch season {
        case .loading: return .loading
        case .loaded: return .loaded
        case .failed: return .failed
        }
    }

    var liveGames: [HomeLiveGame] {
        HomeFeed.liveGames(teams: teams, boards: scoreboards.games, seasons: seasons)
    }

    /// The boards are only polled for the days of games the seasons list,
    /// so Live Now stands where the seasons do.
    var liveState: SectionLoadState { scheduleState }

    var today: HomeDay? {
        HomeFeed.upcomingDay(HomeFeed.games(teams: teams, seasons: seasons), now: now)
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

    /// `game`'s live score for `team` on the scoreboard, for a game under
    /// way in Today.
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

    /// Asks the center again for the seasons that failed.
    func reloadSchedules() async {
        await scoreboards.retryFailedSchedules()
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
            of: (TeamRef.ID, Result<[News], NetworkError>).self,
            returning: [(TeamRef.ID, Result<[News], NetworkError>)].self
        ) { group in
            for team in due {
                let id = team.id
                let url = team.newsURL
                group.addTask {
                    (id, await load(url))
                }
            }
            var answers: [(TeamRef.ID, Result<[News], NetworkError>)] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }

        for (id, result) in answers {
            apply(news: result, for: id)
        }
    }

    /// Publishes a news fetch. A failure keeps what is already on screen,
    /// and a cancelled fetch (Home went away mid-load) changes nothing, as
    /// on a team page (`TeamModel`).
    private func apply(news result: Result<[News], NetworkError>, for id: TeamRef.ID) {
        switch result {
        case .success(let loaded):
            newsStates[id] = .loaded
            newsLoadedAt[id] = clock()
            articles[id] = loaded
        case .failure(let error):
            if case .cancelled = error { return }
            if (articles[id] ?? []).isEmpty {
                newsStates[id] = .failed
            }
        }
    }
}
