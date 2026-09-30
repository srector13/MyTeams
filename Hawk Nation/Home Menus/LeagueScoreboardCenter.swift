//
//  LeagueScoreboardCenter.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation

/// Polls one scoreboard per league for the live scores of every favorite in
/// it.
///
/// Each team page used to poll a summary document per game in progress,
/// every minute, and every page stayed mounted — so the cost grew with
/// favorites × games. A league's scoreboard (`LeagueID.scoreboardURL`) lists
/// every game in the league that day, so one request a minute answers for
/// all the favorites in it: the center fans each document out to them by
/// team id (`lines`).
///
/// Pages subscribe while they are on screen, naming the scoreboard days of
/// their games in the live window (`TeamModel`); a league is polled only
/// while some subscription wants a day there, by one poller however many
/// pages or favorites share it. The cost is one request per polled league
/// per minute, and nothing on a quiet day.
///
/// While the app is in the foreground it also follows every favorite
/// itself (`startFollowingFavorites()`), whichever page is showing, so score
/// alerts and Live Activities hear of games in leagues nobody is looking
/// at. It subscribes like a page — one subscription per favorite and
/// competition, for the days of its games in the live window — so a league
/// both it and a page want is still one poller and one request a minute,
/// and a league with no favorite's game under way still costs nothing.
///
/// The favorites the documents fan out to are `FavoritesStore`'s, read at
/// each refresh, never a list of the center's own. A refresh that fails
/// keeps the last scoreboard, so a rate-limited league keeps its last known
/// scores; throttling responses slow the league's poller (`PollBackoff`).
@MainActor
@Observable
final class LeagueScoreboardCenter {
    static let shared = LeagueScoreboardCenter()

    /// A page's standing request for its league's scoreboard. Pass it back to
    /// `update(_:days:)` and `unsubscribe(_:)`.
    struct Subscription: Hashable, Sendable {
        fileprivate let id: Int
        let league: LeagueID
    }

    /// Every favorite's games on the scoreboards polled so far, keyed by
    /// `TeamRef.ID`. See `liveScore(for:team:)`.
    private(set) var lines: [TeamRef.ID: [ScoreboardLine]] = [:]

    /// Every game on each league's kept scoreboards, for readers that follow
    /// whole games rather than a favorite's score (`ScoreAlertEngine`).
    private(set) var games: [LeagueID: [ScoreboardGame]] = [:]

    private let client: HTTPClient
    private let interval: Duration
    private let favoriteIDs: @MainActor () -> [TeamRef.ID]
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @MainActor () -> Date
    private let loadSchedule: @Sendable (TeamRef.ID) async -> [Game]?

    private struct Entry {
        var teamID: TeamRef.ID
        var league: LeagueID
        var days: Set<String>
    }

    @ObservationIgnored private var subscriptions: [Int: Entry] = [:]
    @ObservationIgnored private var lastSubscriptionID = 0
    @ObservationIgnored private var pollers: [LeagueID: Task<Void, Never>] = [:]
    @ObservationIgnored private var backoffs: [LeagueID: PollBackoff] = [:]
    /// The last good scoreboard of each league, by day.
    @ObservationIgnored private var scoreboards: [LeagueID: [String: LeagueScoreboard]] = [:]

    /// A favorite's standing request for one of its competitions, while the
    /// center follows the favorites.
    private struct FollowKey: Hashable {
        var teamID: TeamRef.ID
        var competition: LeagueID
    }

    /// A favorite's season as last loaded: `nil` games when the load failed.
    private struct FollowedSchedule {
        var games: [Game]?
        var loadedAt: Date
    }

    /// Whether the center follows every favorite, not only the pages on
    /// screen. See `startFollowingFavorites()`.
    @ObservationIgnored private(set) var isFollowingFavorites = false
    /// Bumped at each start and stop, so an observation armed by an earlier
    /// run of following does nothing.
    @ObservationIgnored private var followGeneration = 0
    @ObservationIgnored private var followLoop: Task<Void, Never>?
    @ObservationIgnored private var followed: [FollowKey: Subscription] = [:]
    /// Kept across stops, so coming back to the foreground reloads only the
    /// stale ones.
    @ObservationIgnored private var followedSchedules: [TeamRef.ID: FollowedSchedule] = [:]
    @ObservationIgnored private var scheduleLoads: [TeamRef.ID: Task<[Game]?, Never>] = [:]
    /// Games the scoreboards have shown over, for as long as a favorite's
    /// schedule still has them in the live window: a board no subscription
    /// wants any more is dropped, and the game with it.
    @ObservationIgnored private var endedGames: Set<String> = []

    /// How long a favorite's loaded season is trusted before it is fetched
    /// again. The scoreboards say when a game ends; this picks up fixtures
    /// added or moved.
    static let followedScheduleLifetime: TimeInterval = 6 * 60 * 60
    /// How long after a failed load a favorite's season is asked for again.
    static let followedScheduleRetry: TimeInterval = 15 * 60

    /// - Parameters:
    ///   - interval: how often a league is polled while nothing is throttled.
    ///   - favoriteIDs: the registry the scoreboards fan out to, in
    ///     `TeamRef.ID`s. The app's favorites.
    ///   - sleep: waits between refreshes; tests stand in a scripted clock.
    ///   - now: the current instant, for the live window of the favorites
    ///     the center follows.
    ///   - loadSchedule: a favorite's season, by `TeamRef.ID`, or `nil` when
    ///     it cannot be loaded. Read while following the favorites.
    init(
        client: HTTPClient = .shared,
        interval: Duration = .seconds(60),
        favoriteIDs: @escaping @MainActor () -> [TeamRef.ID] = { FavoritesStore.shared.teamIDs },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> Date = { Date() },
        loadSchedule: @escaping @Sendable (TeamRef.ID) async -> [Game]? = { id in
            guard let team = await FavoritesStore.resolve(id, within: .seconds(5)) else { return nil }
            return try? await downloadScheduleData(team: team).get()
        }
    ) {
        self.client = client
        self.interval = interval
        self.favoriteIDs = favoriteIDs
        self.sleep = sleep
        self.now = now
        self.loadSchedule = loadSchedule
    }

    // MARK: Subscribing

    /// Asks for `team`'s league scoreboard on `days` (`scoreboardDay(for:)`),
    /// starting the league's poller if it is not running. With no days, the
    /// subscription polls nothing until `update(_:days:)` adds some.
    ///
    /// - Parameter competition: one of the league's cups
    ///   (`LeagueDescriptor.cupCompetitions`) to poll instead, for the days
    ///   of the team's cup ties: the league's own board does not list them.
    func subscribe(_ team: TeamRef, competition: LeagueID? = nil, days: Set<String>) -> Subscription {
        subscribe(teamID: team.id, league: competition ?? team.league, days: days)
    }

    private func subscribe(teamID: TeamRef.ID, league: LeagueID, days: Set<String>) -> Subscription {
        lastSubscriptionID += 1
        let subscription = Subscription(id: lastSubscriptionID, league: league)
        subscriptions[subscription.id] = Entry(teamID: teamID, league: league, days: days)
        reconcilePoller(for: league)
        return subscription
    }

    /// Replaces the days a subscription asks for, as its games move in and
    /// out of the live window.
    func update(_ subscription: Subscription, days: Set<String>) {
        guard let entry = subscriptions[subscription.id], entry.days != days else { return }
        subscriptions[subscription.id]?.days = days
        reconcilePoller(for: subscription.league)
    }

    /// Withdraws a subscription, stopping its league's poller if no other
    /// subscription wants a day there. The league's last scores are kept for
    /// when a page comes back.
    func unsubscribe(_ subscription: Subscription) {
        guard subscriptions.removeValue(forKey: subscription.id) != nil else { return }
        reconcilePoller(for: subscription.league)
    }

    /// The leagues being polled right now.
    var pollingLeagues: Set<LeagueID> { Set(pollers.keys) }

    /// The days any subscription wants on `league`'s scoreboard.
    func days(wantedIn league: LeagueID) -> Set<String> {
        subscriptions.values
            .filter { $0.league == league }
            .reduce(into: []) { $0.formUnion($1.days) }
    }

    /// Runs one poller for `league` while any subscription wants a day
    /// there, and none otherwise.
    private func reconcilePoller(for league: LeagueID) {
        let wanted = !days(wantedIn: league).isEmpty
        if wanted, pollers[league] == nil {
            // The task holds the center while it polls; unsubscribing
            // cancels it.
            pollers[league] = Task {
                await self.poll(league)
            }
        } else if !wanted, let poller = pollers.removeValue(forKey: league) {
            poller.cancel()
            backoffs[league] = nil
        }
    }

    private func poll(_ league: LeagueID) async {
        while !Task.isCancelled {
            let delay = await refresh(league)
            do {
                try await sleep(delay)
            } catch {
                return
            }
        }
    }

    // MARK: Refreshing

    /// Fetches `league`'s scoreboard for each wanted day — one request per
    /// day, and one day but for a game running past midnight Eastern — fans
    /// the games out to the league's favorites, and returns how long to wait
    /// before the next refresh.
    @discardableResult
    func refresh(_ league: LeagueID) async -> Duration {
        var responses: [FetchResponse] = []
        for day in days(wantedIn: league).sorted() {
            let response = await client.fetchResponse(league.scoreboardURL(day: day))
            if let json = response.result.document {
                scoreboards[league, default: [:]][day] = parseScoreboard(from: json)
            }
            responses.append(response)
        }

        // Days no page wants any more are dropped. With no page subscribed
        // at all, the last scores stay for when one returns.
        let wanted = days(wantedIn: league)
        if !wanted.isEmpty {
            scoreboards[league] = scoreboards[league]?.filter { wanted.contains($0.key) }
        }
        fanOut(league)
        // A favorite's game that just ended no longer keeps its league
        // polled.
        regateFollowedFavorites()

        // A cancelled request is the poller stopping, not the server
        // pushing back.
        guard !Task.isCancelled else { return interval }

        // One throttled day slows the whole league.
        let pacing = responses.first(where: \.isThrottled)
            ?? responses.first(where: { $0.result.document == nil })
            ?? responses.last
        var backoff = backoffs[league] ?? PollBackoff(base: interval)
        let delay = pacing.map { backoff.delay(after: $0) } ?? interval
        backoffs[league] = backoff
        return delay
    }

    /// The teams a league's scoreboards fan out to: the favorites in it (or,
    /// for a cup, in a league that plays it), in favorites order, plus any
    /// subscribed team that is not a favorite (a preview, or a page
    /// mid-removal).
    func registry(for league: LeagueID) -> [TeamRef.ID] {
        var ids = favoriteIDs().filter { id in
            guard let parsed = TeamRef.parse(id: id) else { return false }
            return parsed.league == league || parsed.league.descriptor.cupCompetitions.contains(league)
        }
        for entry in subscriptions.values where entry.league == league && !ids.contains(entry.teamID) {
            ids.append(entry.teamID)
        }
        return ids
    }

    /// Gives every team in `league`'s registry its games from the league's
    /// kept scoreboards — one document read for all of them. A team's lines
    /// are its league's games and its cups' together, so one competition's
    /// refresh never drops another's scores.
    private func fanOut(_ league: LeagueID) {
        let leagueGames = (scoreboards[league] ?? [:])
            .sorted { $0.key < $1.key }
            .flatMap { $0.value.games }
        if games[league] != leagueGames {
            games[league] = leagueGames
        }

        for teamID in registry(for: league) {
            guard let team = TeamRef.parse(id: teamID) else { continue }
            let competitions = [team.league] + team.league.descriptor.cupCompetitions
            let teamLines = competitions.flatMap { competition in
                (scoreboards[competition] ?? [:])
                    .sorted { $0.key < $1.key }
                    .flatMap { $0.value.lines(for: team.espnID) }
            }
            // Only a change is written, so an unchanged minute does not
            // redraw the page.
            if lines[teamID] != teamLines {
                lines[teamID] = teamLines
            }
        }
    }

    // MARK: Following the favorites

    /// Subscribes for every favorite, as its page would, whether or not the
    /// page is on screen: each of its competitions (`[league] +
    /// cupCompetitions`) for the days of its games in the live window
    /// (`followedDays`). Its seasons are loaded here, and re-read once they
    /// are `followedScheduleLifetime` old.
    ///
    /// Rechecked every `interval` as the window moves with the clock, at
    /// every refresh as games end, and whenever the favorites change.
    /// Called when the app comes to the foreground; calling it again does
    /// nothing.
    func startFollowingFavorites() {
        guard !isFollowingFavorites else { return }
        isFollowingFavorites = true
        followGeneration += 1
        observeFavorites(followGeneration)
        followLoop = Task {
            while !Task.isCancelled {
                await self.refreshFollowedFavorites()
                do {
                    try await self.sleep(self.interval)
                } catch {
                    return
                }
            }
        }
    }

    /// Withdraws the favorites' subscriptions, stopping every league no
    /// page still wants. Called when the app goes to the background.
    func stopFollowingFavorites() {
        guard isFollowingFavorites else { return }
        isFollowingFavorites = false
        followGeneration += 1
        followLoop?.cancel()
        followLoop = nil
        let withdrawn = followed.values
        followed = [:]
        for subscription in withdrawn {
            unsubscribe(subscription)
        }
    }

    /// Loads the seasons of favorites that have none or a stale one — each
    /// at most once however many callers ask — then points the favorites'
    /// subscriptions at their live days.
    func refreshFollowedFavorites() async {
        guard isFollowingFavorites else { return }
        let ids = favoriteIDs()
        followedSchedules = followedSchedules.filter { ids.contains($0.key) }

        let current = now()
        for id in ids where scheduleLoads[id] == nil && needsSchedule(id, at: current) {
            let load = loadSchedule
            scheduleLoads[id] = Task {
                await load(id)
            }
        }
        for id in ids {
            guard let load = scheduleLoads[id] else { continue }
            let games = await load.value
            // Whoever was first back stores it.
            if scheduleLoads.removeValue(forKey: id) != nil {
                followedSchedules[id] = FollowedSchedule(games: games, loadedAt: now())
            }
        }
        regateFollowedFavorites()
    }

    private func needsSchedule(_ id: TeamRef.ID, at date: Date) -> Bool {
        guard let schedule = followedSchedules[id] else { return true }
        let lifetime = schedule.games == nil ? Self.followedScheduleRetry : Self.followedScheduleLifetime
        return date.timeIntervalSince(schedule.loadedAt) >= lifetime
    }

    /// Re-reads the favorites on each change, until following stops.
    private func observeFavorites(_ generation: Int) {
        guard followGeneration == generation else { return }
        _ = withObservationTracking {
            favoriteIDs()
        } onChange: {
            // Called before the change lands; read it on the next turn.
            Task { @MainActor in
                guard self.followGeneration == generation else { return }
                self.observeFavorites(generation)
                await self.refreshFollowedFavorites()
            }
        }
    }

    /// Subscribes each favorite's competitions with games in the live
    /// window, updates the ones already subscribed, and withdraws the rest —
    /// a team unfollowed, or its last live game over.
    private func regateFollowedFavorites() {
        guard isFollowingFavorites else { return }
        let current = now()
        for board in games.values {
            for game in board where game.state == "post" {
                endedGames.insert(game.gameID)
            }
        }

        var wanted: [FollowKey: Set<String>] = [:]
        var inWindow: Set<String> = []
        for id in favoriteIDs() {
            guard let team = TeamRef.parse(id: id),
                  let schedule = followedSchedules[id]?.games
            else { continue }
            for game in schedule where shouldPollLiveScore(game: game, now: current) {
                inWindow.insert(game.gameID)
            }
            for competition in [team.league] + team.league.descriptor.cupCompetitions {
                let days = Self.followedDays(
                    of: schedule, in: competition, league: team.league,
                    ended: endedGames, now: current
                )
                if !days.isEmpty {
                    wanted[FollowKey(teamID: id, competition: competition)] = days
                }
            }
        }
        endedGames.formIntersection(inWindow)

        for (key, subscription) in followed where wanted[key] == nil {
            followed[key] = nil
            unsubscribe(subscription)
        }
        for (key, days) in wanted {
            if let subscription = followed[key] {
                update(subscription, days: days)
            } else {
                followed[key] = subscribe(teamID: key.teamID, league: key.competition, days: days)
            }
        }
    }

    /// The scoreboard days (`scoreboardDay(for:)`) of a favorite's games in
    /// `competition` that its page would poll (`shouldPollLiveScore`),
    /// less those a scoreboard has shown over: the schedule is loaded
    /// rarely, the scoreboard every minute.
    ///
    /// - Parameters:
    ///   - league: the team's own league, the competition of games whose
    ///     feed names none.
    ///   - ended: the ids of games a scoreboard listed as `"post"` —
    ///     played out, or called off.
    static func followedDays(
        of schedule: [Game],
        in competition: LeagueID,
        league: LeagueID,
        ended: Set<String>,
        now: Date
    ) -> Set<String> {
        Set(schedule
            .filter { game in
                (game.competition ?? league) == competition
                    && shouldPollLiveScore(game: game, now: now)
                    && !ended.contains(game.gameID)
            }
            .map { scoreboardDay(for: $0.dateAsDate) })
    }

    // MARK: Reading

    /// `game`'s score for `team` on the latest scoreboard: matched by game
    /// id, or else by the opponent's team id when exactly one game on the
    /// board pairs the two (a doubleheader never guesses).
    func liveScore(for game: Game, team: TeamRef) -> LiveGameScore? {
        let teamLines = lines[team.id] ?? []
        if !game.gameID.isEmpty, let line = teamLines.first(where: { $0.gameID == game.gameID }) {
            return line.score
        }
        guard !game.opponentID.isEmpty else { return nil }
        let againstOpponent = teamLines.filter { $0.opponentID == game.opponentID }
        return againstOpponent.count == 1 ? againstOpponent[0].score : nil
    }
}
