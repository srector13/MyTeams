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
    /// ESPN's athlete id, or empty when the feed gave none. The headshot
    /// fallback looks the athlete up on Wikidata by it.
    var playerID: String { get }
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

/// The team page's feeds that refresh on a time-to-live (A-3). The schedule
/// is not one of them: it has its own once-a-minute refresh while the page
/// is on screen.
enum TeamFeed: CaseIterable, Hashable, Sendable {
    case roster
    case news
    case standings
    case leaders

    /// How long a loaded feed is shown before the page's next appearance
    /// fetches it again. News and standings move on a match day; the roster
    /// and leaders rarely do, but nothing is lost asking on the same clock.
    var timeToLive: TimeInterval { 15 * 60 }

    /// The feeds a followed game going final changes: the match report, the
    /// table and the season's stat lines. They are refetched at once rather
    /// than when their time-to-live runs out.
    static let changedByFinalWhistle: Set<TeamFeed> = [.news, .standings, .leaders]
}

/// Whether a feed should be fetched (again): it has not loaded, it failed,
/// it was marked stale (`loadedAt` cleared), or it is `timeToLive` old.
func feedNeedsRefresh(
    state: SectionLoadState,
    loadedAt: Date?,
    timeToLive: TimeInterval,
    now: Date
) -> Bool {
    guard state == .loaded, let loadedAt else { return true }
    return now.timeIntervalSince(loadedAt) >= timeToLive
}

/// Whether a game `old` listed as unfinished is finished in `new`: the
/// moment the news, standings and leaders feeds change (A-3).
func gameWentFinal(from old: [Game], to new: [Game]) -> Bool {
    let unfinished = Set(old.filter { !$0.completed }.map(\.id))
    return new.contains { $0.completed && unfinished.contains($0.id) }
}

/// The roster's name order (A-15): by last name as Finder sorts names —
/// case- and diacritic-aware, so "de Jong", "Ødegaard" and "van Dijk" file
/// among the other names rather than after "Z" — then by full name, then by
/// shirt number.
func rosterNameOrder<Player: RosterPlayer>(_ lhs: Player, _ rhs: Player) -> Bool {
    let byLastName = lhs.lastName.localizedStandardCompare(rhs.lastName)
    if byLastName != .orderedSame { return byLastName == .orderedAscending }
    let byName = lhs.name.localizedStandardCompare(rhs.name)
    if byName != .orderedSame { return byName == .orderedAscending }
    return lhs.numberInt < rhs.numberInt
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
    /// The team's leader on each of its sport's boards (`leaderBoards`,
    /// one deep), for the Leaders section.
    private(set) var leaders: [LeaderBoard] = []

    private(set) var rosterState: SectionLoadState = .loading
    private(set) var scheduleState: SectionLoadState = .loading
    private(set) var newsState: SectionLoadState = .loading
    private(set) var standingsState: SectionLoadState = .loading
    private(set) var leadersState: SectionLoadState = .loading

    /// When each feed last loaded, or nothing when it has not, or a game
    /// going final made it stale (A-3). See `needsRefresh(_:)`.
    @ObservationIgnored private var loadedAt: [TeamFeed: Date] = [:]

    /// When the schedule on screen was fetched, when it came from the
    /// `FeedCache` because the network could not be reached (R-4); `nil`
    /// when it is the network's own. Cached scores are not live, so no live
    /// score is polled while it is set.
    private(set) var scheduleCachedAt: Date?

    /// When the schedule on screen was fetched — just now from the network,
    /// or `scheduleCachedAt` — for an "Updated … ago" caption
    /// (`UpdatedCaption`). `nil` until a schedule has loaded.
    private(set) var scheduleUpdatedAt: Date?

    /// When each of the other feeds on screen was fetched, for the feeds
    /// served from the `FeedCache`; a feed absent here is the network's own.
    private(set) var feedCachedAt: [TeamFeed: Date] = [:]

    /// Live scores for the games in the live window, keyed by `Game.gameID`,
    /// as the league's scoreboard reports them (`LeagueScoreboardCenter`).
    /// Schedule cards render from this instead of each card fetching its own
    /// summary document. A game that left the window (finished, postponed,
    /// or too old) drops out; its score comes from the schedule feed itself.
    var liveScores: [String: LiveGameScore] {
        let now = Date()
        let networkFresh = scheduleCachedAt == nil
        var scores: [String: LiveGameScore] = [:]
        for game in games where shouldPollLiveScore(game: game, now: now, networkFresh: networkFresh) {
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
    private let loadLeaders: @Sendable (TeamRef) async -> Result<StatLeaders, NetworkError>
    private let loadNews: @Sendable (String) async -> Result<[News], NetworkError>
    private let loadSchedule: @Sendable (TeamRef) async -> Result<[Game], NetworkError>
    private let scoreboards: LeagueScoreboardCenter
    /// The clock the feeds' time-to-live is read against; a test's own.
    private let now: @MainActor () -> Date

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
        loadLeaders: @escaping @Sendable (TeamRef) async -> Result<StatLeaders, NetworkError> = {
            await downloadStatLeaders(league: $0.league, teamID: $0.espnID, depth: 1)
        },
        loadNews: @escaping @Sendable (String) async -> Result<[News], NetworkError> = { await downloadNewsData(queryURL: $0) },
        loadSchedule: @escaping @Sendable (TeamRef) async -> Result<[Game], NetworkError> = { await downloadScheduleData(team: $0) },
        scoreboards: LeagueScoreboardCenter = .shared,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.team = team
        self.newsURL = newsURL
        self.loadRoster = loadRoster
        self.loadStandings = loadStandings
        self.loadLeaders = loadLeaders
        self.loadNews = loadNews
        self.loadSchedule = loadSchedule
        self.scoreboards = scoreboards
        self.now = now
    }

    /// The team's league record so far this season, in its sport's shape,
    /// counted from the schedule under the league's `RecordRule`. Cup ties
    /// are on the schedule but not in the record. See `scheduleRecord`.
    func displayRecord() -> Record {
        scheduleRecord(games: games, league: team.league)
    }

    // MARK: - Loading

    /// Loads the roster, schedule, news, standings and leaders feeds
    /// together, then keeps the schedule fresh for as long as the page is on
    /// screen.
    ///
    /// Scores and clocks move during a game, so the schedule is refetched every
    /// minute; rosters, news, standings and leaders move more slowly, so they
    /// are fetched when the page appears and their time-to-live has run out
    /// (`TeamFeed.timeToLive`), or as soon as a followed game goes final
    /// (A-3).
    /// The model outlives its page (`TeamPages`), so a page coming back
    /// refetches the schedule, and whichever other feed has not loaded yet or
    /// has gone stale.
    func load() async {
        // A page that failed last time it appeared shows its skeletons again
        // while it retries; `refreshExpiredFeeds` does the same for the rest.
        if scheduleState == .failed { scheduleState = .loading }

        async let schedule = fetchSchedule()
        async let feeds: Void = refreshExpiredFeeds()

        let loadedSchedule = await schedule
        await feeds

        await publish(schedule: loadedSchedule)
        await refreshSchedulePeriodically()
    }

    /// Refetches every feed — roster, schedule, news, standings and leaders —
    /// whatever its age: pull-to-refresh (C-1). What is on screen stays there
    /// until each answer arrives, and a failed refresh keeps it.
    func refreshAll() async {
        if rosterState == .failed { rosterState = .loading }
        if scheduleState == .failed { scheduleState = .loading }
        if newsState == .failed { newsState = .loading }
        if standingsState == .failed { standingsState = .loading }
        if leadersState == .failed { leadersState = .loading }

        async let roster = fetchRoster(if: true)
        async let schedule = fetchSchedule()
        async let news = fetchNews(if: true)
        async let leagueStandings = fetchStandings(if: true)
        async let teamLeaders = fetchLeaders(if: true)

        let (loadedRoster, loadedSchedule, loadedNews, loadedStandings, loadedLeaders) =
            await (roster, schedule, news, leagueStandings, teamLeaders)

        // The schedule first: a game it shows going final marks the other
        // feeds stale, and their answers here are the fresh ones.
        apply(schedule: loadedSchedule.result, cachedAt: loadedSchedule.cachedAt)
        updateScoreboardSubscription()
        if let loadedRoster { apply(roster: loadedRoster) }
        if let loadedNews { apply(news: loadedNews) }
        if let loadedStandings { apply(standings: loadedStandings) }
        if let loadedLeaders { apply(leaders: loadedLeaders) }
    }

    /// Refetches whichever of the roster, news, standings and leaders is due
    /// (`needsRefresh(_:)`): not loaded yet, failed, past its time-to-live,
    /// or made stale by a game going final (A-3). The rest stay as they are.
    func refreshExpiredFeeds() async {
        let current = now()
        let due = Set(TeamFeed.allCases.filter { needsRefresh($0, now: current) })
        guard !due.isEmpty else { return }

        // A feed that failed last time shows its skeletons again while it
        // retries.
        if rosterState == .failed { rosterState = .loading }
        if newsState == .failed { newsState = .loading }
        if standingsState == .failed { standingsState = .loading }
        if leadersState == .failed { leadersState = .loading }

        async let roster = fetchRoster(if: due.contains(.roster))
        async let news = fetchNews(if: due.contains(.news))
        async let leagueStandings = fetchStandings(if: due.contains(.standings))
        async let teamLeaders = fetchLeaders(if: due.contains(.leaders))

        let (loadedRoster, loadedNews, loadedStandings, loadedLeaders) =
            await (roster, news, leagueStandings, teamLeaders)

        if let loadedRoster { apply(roster: loadedRoster) }
        if let loadedNews { apply(news: loadedNews) }
        if let loadedStandings { apply(standings: loadedStandings) }
        if let loadedLeaders { apply(leaders: loadedLeaders) }
    }

    /// Whether `feed` is due a fetch on the page's next appearance: see
    /// `feedNeedsRefresh`.
    func needsRefresh(_ feed: TeamFeed) -> Bool {
        needsRefresh(feed, now: now())
    }

    private func needsRefresh(_ feed: TeamFeed, now: Date) -> Bool {
        feedNeedsRefresh(
            state: state(of: feed),
            loadedAt: loadedAt[feed],
            timeToLive: feed.timeToLive,
            now: now
        )
    }

    private func state(of feed: TeamFeed) -> SectionLoadState {
        switch feed {
        case .roster: rosterState
        case .news: newsState
        case .standings: standingsState
        case .leaders: leadersState
        }
    }

    /// Publishes a schedule fetch, and when it shows a followed game gone
    /// final, refetches the feeds that changed with it straight away (A-3).
    private func publish(schedule fetched: Fetched<[Game]>) async {
        if apply(schedule: fetched.result, cachedAt: fetched.cachedAt) {
            await refreshExpiredFeeds()
        }
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
            await publish(schedule: await fetchSchedule())
            // The live window moves with the clock, not only with the feed.
            updateScoreboardSubscription()
        }
    }

    /// The scoreboard days (`scoreboardDay(for:)`) of the games in
    /// `competition` that qualify under `shouldPollLiveScore`: the ones its
    /// scoreboard is polled for.
    private func liveScoreboardDays(in competition: LeagueID, now: Date = Date()) -> Set<String> {
        let networkFresh = scheduleCachedAt == nil
        return Set(games
            .filter {
                ($0.competition ?? team.league) == competition
                    && shouldPollLiveScore(game: $0, now: now, networkFresh: networkFresh)
            }
            .map { scoreboardDay(for: $0.dateAsDate) })
    }

    private func updateScoreboardSubscription() {
        for subscription in scoreboardSubscriptions {
            scoreboards.update(subscription, days: liveScoreboardDays(in: subscription.league))
        }
    }

    /// Loads the team's leaders unless they are already on screen and
    /// fresh, so a page coming back does not ask the leaders feed again
    /// within its time-to-live. One that failed last time retries;
    /// `reloadLeaders` refetches regardless.
    func loadLeadersIfNeeded() async {
        guard needsRefresh(.leaders) else { return }
        if leadersState == .failed { leadersState = .loading }
        if let loaded = await fetchLeaders(if: true) {
            apply(leaders: loaded)
        }
    }

    // MARK: - Retrying

    /// Refetches the roster after a failed load.
    func reloadRoster() async {
        rosterState = .loading
        if let loaded = await fetchRoster(if: true) { apply(roster: loaded) }
    }

    /// Refetches the schedule after a failed load, without waiting for the
    /// next scheduled refresh.
    func reloadSchedule() async {
        scheduleState = .loading
        await publish(schedule: await fetchSchedule())
        updateScoreboardSubscription()
    }

    /// Refetches the news after a failed load.
    func reloadNews() async {
        newsState = .loading
        if let loaded = await fetchNews(if: true) { apply(news: loaded) }
    }

    /// Refetches the standings after a failed load.
    func reloadStandings() async {
        standingsState = .loading
        if let loaded = await fetchStandings(if: true) { apply(standings: loaded) }
    }

    /// Refetches the leaders, after a failed load or on request.
    func reloadLeaders() async {
        leadersState = .loading
        if let loaded = await fetchLeaders(if: true) { apply(leaders: loaded) }
    }

    // MARK: - Applying results

    /// A feed's answer, and when it was fetched when it came from the
    /// `FeedCache` rather than the network (R-4).
    typealias Fetched<Value> = (result: Result<Value, NetworkError>, cachedAt: Date?)

    /// Runs `load` with its requests under `.persist`: a good answer is
    /// stored, and one that cannot reach the network is answered from the
    /// last stored one.
    private func persisting<Value: Sendable>(
        _ load: @escaping @Sendable () async -> Result<Value, NetworkError>
    ) async -> Fetched<Value> {
        let (result, cachedAt) = await HTTPClient.withFeedCache(.persist, operation: load)
        return (result, cachedAt)
    }

    private func fetchSchedule() async -> Fetched<[Game]> {
        await persisting { [load = self.loadSchedule, team = self.team] in await load(team) }
    }

    /// The roster, or `nil` when it is not `due`.
    private func fetchRoster(if due: Bool) async -> Fetched<[Player]>? {
        guard due else { return nil }
        return await persisting { [load = self.loadRoster, team = self.team] in await load(team) }
    }

    /// The news, or `nil` when it is not `due`.
    private func fetchNews(if due: Bool) async -> Fetched<[News]>? {
        guard due else { return nil }
        return await persisting { [load = self.loadNews, url = self.newsURL] in await load(url) }
    }

    /// The standings, or `nil` when they are not `due`.
    private func fetchStandings(if due: Bool) async -> Fetched<Standings>? {
        guard due else { return nil }
        return await persisting { [load = self.loadStandings, league = self.team.league] in await load(league) }
    }

    /// The leaders, or `nil` when they are not `due`.
    private func fetchLeaders(if due: Bool) async -> Fetched<StatLeaders>? {
        guard due else { return nil }
        return await persisting { [load = self.loadLeaders, team = self.team] in await load(team) }
    }

    /// Records when `feed` loaded. One served from the cache is shown but
    /// not counted as loaded, so the page's next appearance asks the
    /// network again (`needsRefresh(_:)`).
    private func markLoaded(_ feed: TeamFeed, cachedAt: Date?) {
        loadedAt[feed] = cachedAt == nil ? now() : nil
        feedCachedAt[feed] = cachedAt
    }

    /// Publishes a schedule fetch. A failure keeps what is already on screen
    /// rather than blanking the carousel; it only shows as an error when
    /// there is nothing else to show.
    ///
    /// - Parameter cachedAt: when the schedule was fetched, for one served
    ///   from the `FeedCache`.
    /// - Returns: whether a game on screen went final with this fetch, which
    ///   marks the feeds it changes stale (A-3).
    @discardableResult
    private func apply(schedule result: Result<[Game], NetworkError>, cachedAt: Date?) -> Bool {
        switch result {
        case .success(let schedule):
            scheduleState = .loaded
            // A feed that suddenly lists nothing mid-season is far likelier a
            // hiccup than a cleared schedule, so games on screen stay put.
            guard !schedule.isEmpty else { return false }

            scheduleCachedAt = cachedAt
            scheduleUpdatedAt = cachedAt ?? now()
            let wentFinal = gameWentFinal(from: games, to: schedule)
            games = schedule
            nextGame = getNextGame(
                schedule: schedule,
                pastDatesCountAsPlayed: recordRule.usesDateForNextGame
            )
            if wentFinal {
                for feed in TeamFeed.changedByFinalWhistle {
                    loadedAt[feed] = nil
                }
            }
            return wentFinal
        case .failure(let error):
            fail(&scheduleState, with: error, hasContent: !games.isEmpty)
            return false
        }
    }

    private func apply(roster fetched: Fetched<[Player]>) {
        switch fetched.result {
        case .success(let roster):
            rosterState = .loaded
            markLoaded(.roster, cachedAt: fetched.cachedAt)
            allPlayers = roster
            applyFilterAndSort()
        case .failure(let error):
            fail(&rosterState, with: error, hasContent: !allPlayers.isEmpty)
        }
    }

    private func apply(standings fetched: Fetched<Standings>) {
        switch fetched.result {
        case .success(let loaded):
            standingsState = .loaded
            markLoaded(.standings, cachedAt: fetched.cachedAt)
            standings = loaded
        case .failure(let error):
            fail(&standingsState, with: error, hasContent: standings.map { !$0.isEmpty } ?? false)
        }
    }

    private func apply(leaders fetched: Fetched<StatLeaders>) {
        switch fetched.result {
        case .success(let loaded):
            leadersState = .loaded
            markLoaded(.leaders, cachedAt: fetched.cachedAt)
            leaders = leaderBoards(from: loaded, kind: team.league.descriptor.kind, depth: 1)
        case .failure(let error):
            fail(&leadersState, with: error, hasContent: !leaders.isEmpty)
        }
    }

    private func apply(news fetched: Fetched<[News]>) {
        switch fetched.result {
        case .success(let loaded):
            newsState = .loaded
            markLoaded(.news, cachedAt: fetched.cachedAt)
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
        // Not a raw `<`, which put "de Jong" and "Ødegaard" after "Z" (A-15).
        case .name: filtered.sorted(by: rosterNameOrder)
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
///   - networkFresh: whether the schedule `game` came from was just fetched
///     from the network. One served from the `FeedCache` (R-4) means the network
///     is out of reach, so there is no live score to poll for, and the
///     cached game's state may be days old.
func shouldPollLiveScore(game: Game, now: Date = Date(), networkFresh: Bool = true) -> Bool {
    guard networkFresh else { return false }
    guard !game.gameID.isEmpty else { return false }
    if game.completed || game.cancelled || game.postponed { return false }
    return game.dateAsDate.addingTimeInterval(-15 * 60) <= now
        && now <= game.dateAsDate.addingTimeInterval(8 * 3600)
}

// MARK: - Last updated

/// How long ago `updatedAt` was, as a caption under a section shown from
/// the `FeedCache` (R-4): "Updated just now", "Updated 5 min. ago",
/// "Updated 2 days ago".
func updatedAgoText(since updatedAt: Date, now: Date) -> String {
    guard now.timeIntervalSince(updatedAt) >= 60 else { return "Updated just now" }
    // "5 min. ago", in the reader's language. Built per call: a shared
    // `RelativeDateTimeFormatter` isn't `Sendable`, and this runs at most
    // once a minute per caption.
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.dateTimeStyle = .numeric
    return "Updated \(formatter.localizedString(for: updatedAt, relativeTo: now))"
}

/// The "Updated … ago" line for a section whose content may be old: see
/// `TeamModel.scheduleUpdatedAt` and `HomeViewModel.headlinesCachedAt`.
/// Moves on with the clock once a minute.
struct UpdatedCaption: View {
    let updatedAt: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(updatedAgoText(since: updatedAt, now: context.date))
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
