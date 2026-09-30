//
//  LeagueScoreboardCenterFanoutTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import Testing

@testable import myTeams

// `LeagueScoreboardCenter.games`, the whole-game view `ScoreAlertEngine`
// reads, against the per-favorite `lines` fanned out from the same kept
// scoreboards.

/// Stands in for the pollers' `Task.sleep`: reports every wait, then holds
/// the poller until it is cancelled, so each poller refreshes once and
/// tests drive the rest by hand.
private final class HoldingSleeper: @unchecked Sendable {
    let waits: AsyncStream<Duration>
    private let continuation: AsyncStream<Duration>.Continuation

    init() {
        (waits, continuation) = AsyncStream.makeStream(of: Duration.self)
    }

    func sleep(_ duration: Duration) async throws {
        continuation.yield(duration)
        try await Task.sleep(for: .seconds(24 * 60 * 60))
    }
}

/// Waits for `count` poller ticks. Runs on the caller's actor, so the
/// (non-Sendable) iterator never crosses one.
private func ticks(
    _ count: Int,
    from iterator: inout AsyncStream<Duration>.Iterator,
    isolation: isolated (any Actor)? = #isolation
) async {
    for _ in 0..<count {
        guard await iterator.next(isolation: isolation) != nil else { return }
    }
}

/// Records whether an observed property changed.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    var hasFired: Bool { lock.withLock { fired } }

    func fire() {
        lock.withLock { fired = true }
    }
}

private func team(_ league: LeagueID, _ espnID: String) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: espnID, shortName: espnID, abbreviation: "", location: "",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

private let sunday = "20260927"
private let monday = "20260928"
private let championsLeague = LeagueID.soccer("uefa.champions")

/// Answers each URL from the fixture named for it, and anything else with a
/// 404. The names can change between refreshes.
private final class FixtureRoutes: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: String]

    init(_ routes: [String: String]) {
        self.routes = routes
    }

    func route(_ url: String, to fixture: String?) {
        lock.withLock { routes[url] = fixture }
    }

    func reply(to url: URL) -> RecordingTransport.Reply {
        guard let name = lock.withLock({ routes[url.absoluteString] }) else { return .status(404) }
        return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
    }
}

@Suite("League scoreboard center: games fan-out", .timeLimit(.minutes(1)))
struct LeagueScoreboardCenterFanoutTests {
    @MainActor
    private func makeCenter(
        _ routes: FixtureRoutes,
        _ sleeper: HoldingSleeper,
        favorites: [TeamRef]
    ) -> LeagueScoreboardCenter {
        let ids = favorites.map(\.id)
        return LeagueScoreboardCenter(
            client: HTTPClient(transport: RecordingTransport { url, _ in routes.reply(to: url) }),
            favoriteIDs: { ids },
            sleep: { try await sleeper.sleep($0) }
        )
    }

    private func board(_ fixture: String) throws -> LeagueScoreboard {
        parseScoreboard(from: try Fixture.json(fixture))
    }

    @Test("games is the whole board in document order, followed or not; each favorite's lines are its slice of it")
    @MainActor
    func gamesMatchLines() async throws {
        let routes = FixtureRoutes([LeagueID.nfl.scoreboardURL(day: sunday): "nfl_scoreboard_20260927"])
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = [team(.nfl, "12"), team(.nfl, "7"), team(.mlb, "7")]
        let center = makeCenter(routes, sleeper, favorites: favorites)

        let subscription = center.subscribe(favorites[0], days: [sunday])
        await ticks(1, from: &waits)

        // Every game on the board, the Raiders–Saints game nobody follows
        // included, as parsed and in the document's order.
        let expected = try board("nfl_scoreboard_20260927")
        let nflGames = try #require(center.games[.nfl])
        #expect(nflGames == expected.games)
        #expect(nflGames.map(\.gameID) == ["401872962", "401872952", "401872961"])
        // Only the league polled has an entry.
        let leagues = Set(center.games.keys)
        #expect(leagues == [.nfl])

        // Each NFL favorite's lines are what the same games give it.
        let fromGames = LeagueScoreboard(games: nflGames)
        for favorite in favorites where favorite.league == .nfl {
            let lines = center.lines[favorite.id]
            #expect(lines == fromGames.lines(for: favorite.espnID))
            #expect(lines?.isEmpty == false)
        }
        // The Royals share the Broncos' ESPN id but not their league.
        #expect(center.lines[favorites[2].id] == nil)

        center.unsubscribe(subscription)
    }

    @Test("Days are flattened earliest first, whatever order they were added in; a day no longer wanted drops out")
    @MainActor
    func daysInOrder() async throws {
        let routes = FixtureRoutes([
            LeagueID.nfl.scoreboardURL(day: sunday): "nfl_scoreboard_20260927",
            LeagueID.nfl.scoreboardURL(day: monday): "nfl_scoreboard_20260928",
        ])
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let eagles = team(.nfl, "21")
        let center = makeCenter(routes, sleeper, favorites: [eagles])
        let sundayIDs = try board("nfl_scoreboard_20260927").games.map(\.gameID)
        let mondayIDs = try board("nfl_scoreboard_20260928").games.map(\.gameID)

        // Monday first…
        let subscription = center.subscribe(eagles, days: [monday])
        await ticks(1, from: &waits)
        let mondayOnly = center.games[.nfl]?.map(\.gameID)
        #expect(mondayOnly == mondayIDs)

        // …then Sunday joins, and goes ahead of it.
        center.update(subscription, days: [sunday, monday])
        await center.refresh(.nfl)
        let both = center.games[.nfl]?.map(\.gameID)
        #expect(both == sundayIDs + mondayIDs)
        let daysDisjoint = Set(sundayIDs).isDisjoint(with: mondayIDs)
        #expect(daysDisjoint)

        // Monday leaves the window: its games leave `games`.
        center.update(subscription, days: [sunday])
        await center.refresh(.nfl)
        let sundayOnly = center.games[.nfl]?.map(\.gameID)
        #expect(sundayOnly == sundayIDs)

        // Unmounted, the last games stay for when a page comes back.
        center.unsubscribe(subscription)
        let kept = center.games[.nfl]?.map(\.gameID)
        #expect(kept == sundayIDs)
    }

    @Test("A game on two days' boards is listed once per board: games is not deduplicated")
    @MainActor
    func sameBoardTwoDays() async throws {
        // Pins current behavior: both days answer with Sunday's document.
        let routes = FixtureRoutes([
            LeagueID.nfl.scoreboardURL(day: sunday): "nfl_scoreboard_20260927",
            LeagueID.nfl.scoreboardURL(day: monday): "nfl_scoreboard_20260927",
        ])
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let chiefs = team(.nfl, "12")
        let center = makeCenter(routes, sleeper, favorites: [chiefs])

        let subscription = center.subscribe(chiefs, days: [sunday, monday])
        await ticks(1, from: &waits)

        let sundayGames = try board("nfl_scoreboard_20260927").games
        let games = center.games[.nfl]
        #expect(games == sundayGames + sundayGames)
        // The favorite's lines double with it, and still agree with games.
        let lines = center.lines[chiefs.id]
        #expect(lines?.count == 2)
        #expect(lines == LeagueScoreboard(games: games ?? []).lines(for: chiefs.espnID))

        center.unsubscribe(subscription)
    }

    @Test("Per league: a cup's games sit under the cup, a pair meeting twice is two games, and a team's lines join league and cup")
    @MainActor
    func perLeagueMultiplicity() async throws {
        let routes = FixtureRoutes([
            LeagueID.premierLeague.scoreboardURL(day: "20260821"): "epl_scoreboard_20260821",
            championsLeague.scoreboardURL(day: "20260909"): "ucl_scoreboard_20260909",
            LeagueID.nhl.scoreboardURL(day: "20260919"): "nhl_scoreboard_20260919",
        ])
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let arsenal = team(.premierLeague, "359")
        let leafs = team(.nhl, "21")
        let center = makeCenter(routes, sleeper, favorites: [arsenal, leafs])

        let subscriptions = [
            center.subscribe(arsenal, days: ["20260821"]),
            center.subscribe(arsenal, competition: championsLeague, days: ["20260909"]),
            center.subscribe(leafs, days: ["20260919"]),
        ]
        await ticks(3, from: &waits)

        let league = try #require(center.games[.premierLeague])
        let cup = try #require(center.games[championsLeague])
        let leagueBoard = try board("epl_scoreboard_20260821")
        let cupBoard = try board("ucl_scoreboard_20260909")
        #expect(league == leagueBoard.games)
        #expect(cup == cupBoard.games)
        // Filed apart: nothing on both.
        let filedApart = Set(league.map(\.gameID)).isDisjoint(with: cup.map(\.gameID))
        #expect(filedApart)

        // Arsenal's lines are the league's games then the cup's, each read
        // from the entry `games` holds for it.
        let arsenalLines = center.lines[arsenal.id]
        let expectedArsenal = LeagueScoreboard(games: league).lines(for: "359")
            + LeagueScoreboard(games: cup).lines(for: "359")
        #expect(arsenalLines == expectedArsenal)
        #expect(arsenalLines?.map(\.gameID) == ["401879301", "401915423"])

        // nhl_scoreboard_20260919: Canadiens and Maple Leafs twice on one
        // board — two games, not one, and a line for each.
        let nhl = try #require(center.games[.nhl])
        let pair: Set<String> = ["10", "21"]
        let meetings = nhl.filter { Set($0.competitors.map(\.teamID)) == pair }
        #expect(meetings.map(\.gameID) == ["401881922", "401881923"])
        let leafsLines = center.lines[leafs.id]
        #expect(leafsLines?.map(\.gameID) == meetings.map(\.gameID))

        for subscription in subscriptions {
            center.unsubscribe(subscription)
        }
    }

    @Test("games is written only when it changes, and a failed refresh keeps the last board")
    @MainActor
    func writesOnlyOnChange() async throws {
        let url = LeagueID.nfl.scoreboardURL(day: sunday)
        let routes = FixtureRoutes([url: "nfl_scoreboard_20260927"])
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let chiefs = team(.nfl, "12")
        let center = makeCenter(routes, sleeper, favorites: [chiefs])
        let subscription = center.subscribe(chiefs, days: [sunday])
        await ticks(1, from: &waits)
        let first = center.games[.nfl]

        // The same document again: no write, so no observer is woken.
        let unchanged = ChangeFlag()
        withObservationTracking {
            _ = center.games
        } onChange: {
            unchanged.fire()
        }
        await center.refresh(.nfl)
        #expect(!unchanged.hasFired)
        #expect(center.games[.nfl] == first)

        // A 404: the last board is kept, still without a write.
        routes.route(url, to: nil)
        await center.refresh(.nfl)
        #expect(!unchanged.hasFired)
        #expect(center.games[.nfl] == first)

        // A different board: written, and observed.
        routes.route(url, to: "nfl_scoreboard_20260928")
        await center.refresh(.nfl)
        #expect(unchanged.hasFired)
        let replaced = center.games[.nfl]
        let mondayBoard = try board("nfl_scoreboard_20260928")
        #expect(replaced == mondayBoard.games)

        center.unsubscribe(subscription)
    }
}
