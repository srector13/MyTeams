//
//  LeagueScoreboardCenter.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

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
/// pages or favorites share it. The cost is one request per visible league
/// per minute, and nothing on a quiet day.
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

    private let client: HTTPClient
    private let interval: Duration
    private let favoriteIDs: @MainActor () -> [TeamRef.ID]
    private let sleep: @Sendable (Duration) async throws -> Void

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

    /// - Parameters:
    ///   - interval: how often a league is polled while nothing is throttled.
    ///   - favoriteIDs: the registry the scoreboards fan out to, in
    ///     `TeamRef.ID`s. The app's favorites.
    ///   - sleep: waits between refreshes; tests stand in a scripted clock.
    init(
        client: HTTPClient = .shared,
        interval: Duration = .seconds(60),
        favoriteIDs: @escaping @MainActor () -> [TeamRef.ID] = { FavoritesStore.shared.teamIDs },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.interval = interval
        self.favoriteIDs = favoriteIDs
        self.sleep = sleep
    }

    // MARK: Subscribing

    /// Asks for `team`'s league scoreboard on `days` (`scoreboardDay(for:)`),
    /// starting the league's poller if it is not running. With no days, the
    /// subscription polls nothing until `update(_:days:)` adds some.
    func subscribe(_ team: TeamRef, days: Set<String>) -> Subscription {
        lastSubscriptionID += 1
        let subscription = Subscription(id: lastSubscriptionID, league: team.league)
        subscriptions[subscription.id] = Entry(teamID: team.id, league: team.league, days: days)
        reconcilePoller(for: team.league)
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

    /// The teams a league's scoreboards fan out to: the favorites in it, in
    /// favorites order, plus any subscribed team that is not a favorite (a
    /// preview, or a page mid-removal).
    func registry(for league: LeagueID) -> [TeamRef.ID] {
        var ids = favoriteIDs().filter { TeamRef.parse(id: $0)?.league == league }
        for entry in subscriptions.values where entry.league == league && !ids.contains(entry.teamID) {
            ids.append(entry.teamID)
        }
        return ids
    }

    /// Gives every team in `league`'s registry its games from the league's
    /// kept scoreboards — one document read for all of them.
    private func fanOut(_ league: LeagueID) {
        let boards = (scoreboards[league] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
        for teamID in registry(for: league) {
            guard let espnID = TeamRef.parse(id: teamID)?.espnID else { continue }
            let teamLines = boards.flatMap { $0.lines(for: espnID) }
            // Only a change is written, so an unchanged minute does not
            // redraw the page.
            if lines[teamID] != teamLines {
                lines[teamID] = teamLines
            }
        }
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
