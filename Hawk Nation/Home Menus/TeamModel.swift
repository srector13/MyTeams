//
//  TeamModel.swift
//  myTeams
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The roster fields every tab displays, sorts and filters on, whichever sport
/// it shows.
protocol RosterPlayer: Identifiable, Hashable, Sendable {
    var name: String { get }
    var lastName: String { get }
    var number: String { get }
    var numberInt: Int { get }
    var position: String { get }
    var photo: String { get }
    /// The unit a grouped roster feed files the player under (the NFL's
    /// `"offense"`, `"defense"`, `"specialTeam"`), or empty when the feed
    /// has none. `RosterFilter.unit` matches on it.
    var unit: String { get }
}

extension RosterPlayer {
    var unit: String { "" }
}

extension BasketballPlayer: RosterPlayer {}
extension FootBallPlayer: RosterPlayer {
    var unit: String { team }
}
extension BaseballPlayer: RosterPlayer {}
extension SoccerPlayer: RosterPlayer {}
extension HockeyPlayer: RosterPlayer {}

/// How the roster carousel is ordered. The choice also decides which detail —
/// number, or position — each player card shows beneath the name.
enum PlayerSort: String, Sendable {
    case name
    case number
    case position
}

/// Where a section's feed stands, for a section with nothing to show yet.
///
/// A section with content always shows it; this decides what an empty one
/// says instead — skeletons while loading, an empty-state message once the
/// feed has answered with nothing, or an error with a retry when it could
/// not be reached.
enum SectionLoadState: Sendable, Equatable {
    case loading
    case loaded
    case failed
}

/// Everything one team tab displays, and the loading that fills it.
///
/// Team pages differ only in which roster they fetch and which feeds they
/// read, so they share this model rather than each repeating the same state,
/// filtering, sorting and refresh logic.
@MainActor
@Observable
final class TeamModel<Player: RosterPlayer> {
    /// The roster as filtered and sorted for display.
    private(set) var players: [Player] = []

    /// The full roster, kept so that clearing a filter does not need a refetch.
    private(set) var allPlayers: [Player] = []

    private(set) var games: [Game] = []
    private(set) var articles: [News] = []
    /// The league's standings, or `nil` until they load.
    private(set) var standings: Standings?

    private(set) var rosterState: SectionLoadState = .loading
    private(set) var scheduleState: SectionLoadState = .loading
    private(set) var newsState: SectionLoadState = .loading
    private(set) var standingsState: SectionLoadState = .loading

    /// Live scores for the games in the live window, keyed by `Game.gameID`,
    /// as the league's scoreboard reports them (`LeagueScoreboardCenter`).
    /// Schedule cards render from this instead of each card fetching its own
    /// summary document. A game that left the window (finished, postponed,
    /// or too old) drops out; its score comes from the schedule feed itself.
    var liveScores: [String: LiveGameScore] {
        let now = Date()
        var scores: [String: LiveGameScore] = [:]
        for game in games where shouldPollLiveScore(game: game, now: now) {
            if let score = scoreboards.liveScore(for: game, team: team) {
                scores[game.gameID] = score
            }
        }
        return scores
    }

    /// The index in `games` of the next game still to be played. The schedule
    /// carousel opens scrolled to it.
    private(set) var nextGame = 0

    var sort: PlayerSort = .name

    /// The filter currently narrowing the roster, reapplied when the sort
    /// changes so the two do not clobber each other.
    private var activeFilter: (@Sendable (Player) -> Bool)?

    let team: TeamRef
    private let newsURL: String
    private let loadRoster: @Sendable (TeamRef) async -> Result<[Player], NetworkError>
    private let loadStandings: @Sendable (LeagueID) async -> Result<Standings, NetworkError>
    private let scoreboards: LeagueScoreboardCenter

    /// The page's standing requests for its league's scoreboard and each
    /// of its cups', held while the schedule refresh runs (see
    /// `refreshSchedulePeriodically`).
    @ObservationIgnored private var scoreboardSubscriptions: [LeagueScoreboardCenter.Subscription] = []

    /// How the league turns the schedule into a record and a next game: MLS
    /// completion flags are unreliable, so there a past kick-off also counts
    /// as played (`getNextGame`, `seasonRecord(pastDatesCountAsPlayed:)`),
    /// and MLB counts abandoned fixtures as losses.
    private var recordRule: RecordRule { team.league.descriptor.recordRule }

    init(
        team: TeamRef,
        newsURL: String,
        loadRoster: @escaping @Sendable (TeamRef) async -> Result<[Player], NetworkError>,
        loadStandings: @escaping @Sendable (LeagueID) async -> Result<Standings, NetworkError> = { await downloadStandings(league: $0) },
        scoreboards: LeagueScoreboardCenter = .shared
    ) {
        self.team = team
        self.newsURL = newsURL
        self.loadRoster = loadRoster
        self.loadStandings = loadStandings
        self.scoreboards = scoreboards
    }

    /// The team's league record so far this season, in its sport's shape,
    /// counted from the schedule under the league's `RecordRule`. Cup ties
    /// are on the schedule but not in the record. See `scheduleRecord`.
    func displayRecord() -> Record {
        scheduleRecord(games: games, league: team.league)
    }

    // MARK: - Loading

    /// Loads the roster, schedule, news and standings feeds together, then
    /// keeps the schedule fresh for as long as the page is on screen.
    ///
    /// Scores and clocks move during a game, so the schedule is refetched every
    /// minute; rosters, news and standings do not, so they are fetched once.
    /// The model outlives its page (`TeamPages`), so a page coming back
    /// refetches only the schedule, and whichever other feed has not loaded
    /// yet.
    func load() async {
        // A page that failed last time it appeared shows its skeletons again
        // while it retries.
        if rosterState == .failed { rosterState = .loading }
        if scheduleState == .failed { scheduleState = .loading }
        if newsState == .failed { newsState = .loading }
        if standingsState == .failed { standingsState = .loading }

        async let roster = fetchRosterUnlessLoaded()
        async let schedule = fetchSchedule()
        async let news = fetchNewsUnlessLoaded()
        async let leagueStandings = fetchStandingsUnlessLoaded()

        let (loadedRoster, loadedSchedule, loadedNews, loadedStandings) = await (roster, schedule, news, leagueStandings)

        if let loadedRoster { apply(roster: loadedRoster) }
        apply(schedule: loadedSchedule)
        if let loadedNews { apply(news: loadedNews) }
        if let loadedStandings { apply(standings: loadedStandings) }

        await refreshSchedulePeriodically()
    }

    /// Refetches the schedule once a minute until the surrounding task is
    /// cancelled, which SwiftUI does when the page goes away.
    ///
    /// For as long as it runs, the page is subscribed to its league's
    /// scoreboard for the days of its games in the live window, and the
    /// scoreboard supplies `liveScores`. A quiet day wants no days, so a
    /// quiet page makes no score requests; and leaving the page cancels the
    /// loop and withdraws the subscription, stopping the league's poller
    /// unless another page shares it.
    private func refreshSchedulePeriodically() async {
        // The page went away during the first load.
        guard !Task.isCancelled else { return }

        // A cup tie is only on its cup's scoreboard, so each competition
        // the team plays in gets its own subscription; one with no game in
        // the live window polls nothing.
        let subscriptions = ([team.league] + team.league.descriptor.cupCompetitions).map { competition in
            scoreboards.subscribe(team, competition: competition, days: liveScoreboardDays(in: competition))
        }
        scoreboardSubscriptions = subscriptions
        defer {
            for subscription in subscriptions {
                scoreboards.unsubscribe(subscription)
            }
            if scoreboardSubscriptions == subscriptions {
                scoreboardSubscriptions = []
            }
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            apply(schedule: await fetchSchedule())
            // The live window moves with the clock, not only with the feed.
            updateScoreboardSubscription()
        }
    }

    /// The scoreboard days (`scoreboardDay(for:)`) of the games in
    /// `competition` that qualify under `shouldPollLiveScore`: the ones its
    /// scoreboard is polled for.
    private func liveScoreboardDays(in competition: LeagueID, now: Date = Date()) -> Set<String> {
        Set(games
            .filter { ($0.competition ?? team.league) == competition && shouldPollLiveScore(game: $0, now: now) }
            .map { scoreboardDay(for: $0.dateAsDate) })
    }

    private func updateScoreboardSubscription() {
        for subscription in scoreboardSubscriptions {
            scoreboards.update(subscription, days: liveScoreboardDays(in: subscription.league))
        }
    }

    // MARK: - Retrying

    /// Refetches the roster after a failed load.
    func reloadRoster() async {
        rosterState = .loading
        apply(roster: await loadRoster(team))
    }

    /// Refetches the schedule after a failed load, without waiting for the
    /// next scheduled refresh.
    func reloadSchedule() async {
        scheduleState = .loading
        apply(schedule: await fetchSchedule())
        updateScoreboardSubscription()
    }

    /// Refetches the news after a failed load.
    func reloadNews() async {
        newsState = .loading
        apply(news: await downloadNewsData(queryURL: newsURL))
    }

    /// Refetches the standings after a failed load.
    func reloadStandings() async {
        standingsState = .loading
        apply(standings: await loadStandings(team.league))
    }

    // MARK: - Applying results

    private func fetchSchedule() async -> Result<[Game], NetworkError> {
        await downloadScheduleData(team: team)
    }

    /// The roster, or `nil` when it is already on screen.
    private func fetchRosterUnlessLoaded() async -> Result<[Player], NetworkError>? {
        guard rosterState != .loaded else { return nil }
        return await loadRoster(team)
    }

    /// The news, or `nil` when it is already on screen.
    private func fetchNewsUnlessLoaded() async -> Result<[News], NetworkError>? {
        guard newsState != .loaded else { return nil }
        return await downloadNewsData(queryURL: newsURL)
    }

    /// The standings, or `nil` when they are already on screen.
    private func fetchStandingsUnlessLoaded() async -> Result<Standings, NetworkError>? {
        guard standingsState != .loaded else { return nil }
        return await loadStandings(team.league)
    }

    /// Publishes a schedule fetch. A failure keeps what is already on screen
    /// rather than blanking the carousel; it only shows as an error when
    /// there is nothing else to show.
    private func apply(schedule result: Result<[Game], NetworkError>) {
        switch result {
        case .success(let schedule):
            scheduleState = .loaded
            // A feed that suddenly lists nothing mid-season is far likelier a
            // hiccup than a cleared schedule, so games on screen stay put.
            guard !schedule.isEmpty else { return }

            games = schedule
            nextGame = getNextGame(
                schedule: schedule,
                pastDatesCountAsPlayed: recordRule.usesDateForNextGame
            )
        case .failure(let error):
            fail(&scheduleState, with: error, hasContent: !games.isEmpty)
        }
    }

    private func apply(roster result: Result<[Player], NetworkError>) {
        switch result {
        case .success(let roster):
            rosterState = .loaded
            allPlayers = roster
            applyFilterAndSort()
        case .failure(let error):
            fail(&rosterState, with: error, hasContent: !allPlayers.isEmpty)
        }
    }

    private func apply(standings result: Result<Standings, NetworkError>) {
        switch result {
        case .success(let loaded):
            standingsState = .loaded
            standings = loaded
        case .failure(let error):
            fail(&standingsState, with: error, hasContent: standings.map { !$0.isEmpty } ?? false)
        }
    }

    private func apply(news result: Result<[News], NetworkError>) {
        switch result {
        case .success(let loaded):
            newsState = .loaded
            articles = loaded
        case .failure(let error):
            fail(&newsState, with: error, hasContent: !articles.isEmpty)
        }
    }

    /// Marks a section failed, unless it already has content to keep showing
    /// or the fetch was merely cancelled (the view went away mid-load, and
    /// the next appearance loads again).
    private func fail(_ state: inout SectionLoadState, with error: NetworkError, hasContent: Bool) {
        if case .cancelled = error { return }
        if !hasContent {
            state = .failed
        }
    }

    // MARK: - Filtering and sorting

    /// Narrows the roster to the players matching `predicate`, or shows all of
    /// them when it is `nil`.
    func filter(_ predicate: (@Sendable (Player) -> Bool)? = nil) {
        activeFilter = predicate
        applyFilterAndSort()
    }

    func sort(by sort: PlayerSort) {
        self.sort = sort
        applyFilterAndSort()
    }

    private func applyFilterAndSort() {
        let filtered = activeFilter.map { allPlayers.filter($0) } ?? allPlayers

        players = switch sort {
        case .name: filtered.sorted { $0.lastName < $1.lastName }
        case .number: filtered.sorted { $0.numberInt < $1.numberInt }
        case .position: filtered.sorted { $0.position < $1.position }
        }
    }
}

/// Wins, losses and draws from a schedule, counted from each game's own state.
///
/// Deliberately independent of `nextGame`: that carousel pointer clamps to the
/// last slot once the season ends, which silently dropped a finale that is not
/// a win (a loss, or a fixture whose feed never set a winner) from the record.
///
/// A played game that is neither won nor level is a loss; a level one (an MLS
/// draw, an NFL tie — see `Game.isDraw`) counts in the draws column instead.
///
/// - Parameters:
///   - countingAbandonedAsLosses: MLB's rule — cancelled and postponed
///     fixtures count in the losses column. Every other league treats an
///     abandoned fixture as neither win nor loss. See
///     `RecordRule.countsAbandonedGamesAsLosses`.
///   - pastDatesCountAsPlayed: the soccer feed's completion flags are
///     unreliable, so there a past start time stands in for "played". Games
///     are given a four-hour grace window past kickoff so a live match is not
///     yet a loss. `getNextGame` applies the same fallback to the carousel
///     pointer.
func seasonRecord(
    games: [Game],
    countingAbandonedAsLosses: Bool = false,
    pastDatesCountAsPlayed: Bool = false,
    now: Date = Date()
) -> (wins: Int, losses: Int, draws: Int) {
    /// Whether a fixture that was not won has been played out.
    func played(_ game: Game) -> Bool {
        if game.completed { return true }
        return pastDatesCountAsPlayed
            && game.dateAsDate.addingTimeInterval(4 * 3600) < now
    }

    let wins = games.count { $0.gameWin }
    let draws = games.count { game in
        !game.gameWin && !game.cancelled && !game.postponed
            && game.isDraw && played(game)
    }
    let losses = games.count { game in
        if game.gameWin { return false }
        if game.cancelled || game.postponed {
            // MLB's rule: an abandoned fixture goes in the losses column.
            // Everywhere else it is neither win nor loss.
            return countingAbandonedAsLosses
        }
        return !game.isDraw && played(game)
    }
    return (wins, losses, draws)
}

/// Whether a game should show a live score right now, which is also whether
/// its day's league scoreboard is polled for one (`LeagueScoreboardCenter`).
///
/// The old per-card poll asked for every fixture on the carousel, every
/// minute, forever. A season is overwhelmingly games that already finished or
/// start days from now — none of which change while you watch. This confines
/// the polling to the one or two fixtures actually in progress: unplayed or
/// live games whose start is near the current moment.
///
/// The window is deliberately asymmetric. A game starts up to eight hours
/// after its listed date (doubleheaders, delays, a feed that never sets
/// `completed`) and is still worth polling there; fifteen minutes before
/// tip-off covers an early publication of the live scoreboard and nothing
/// earlier, so a tomorrow fixture is never fetched today.
///
/// - Parameters:
///   - game: the fixture to judge. One whose feed gave no game id cannot be
///     matched on a scoreboard or addressed at the summary endpoint, so it
///     never qualifies.
///   - now: the current instant.
func shouldPollLiveScore(game: Game, now: Date = Date()) -> Bool {
    guard !game.gameID.isEmpty else { return false }
    if game.completed || game.cancelled || game.postponed { return false }
    return game.dateAsDate.addingTimeInterval(-15 * 60) <= now
        && now <= game.dateAsDate.addingTimeInterval(8 * 3600)
}
