//
//  FavoritesScoreboardFollowingTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import SwiftUI
import Testing

@testable import myTeams

// `LeagueScoreboardCenter` following every favorite while the app is in the
// foreground (`startFollowingFavorites()`), whichever page is on screen.

/// Stands in for the pollers' `Task.sleep`: reports every wait, then holds
/// the poller until it is cancelled, so each poller (and the following
/// loop) runs once and tests drive the rest by hand.
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

/// Waits for `count` sleeps: one per poller tick, and one per pass of the
/// following loop. Runs on the caller's actor, so the (non-Sendable)
/// iterator never crosses one.
private func ticks(
    _ count: Int,
    from iterator: inout AsyncStream<Duration>.Iterator,
    isolation: isolated (any Actor)? = #isolation
) async {
    for _ in 0..<count {
        guard await iterator.next(isolation: isolation) != nil else { return }
    }
}

/// Answers each scoreboard URL with the reply routed to it, and anything
/// else with a 404. Routes can change between refreshes.
private final class Boards: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: RecordingTransport.Reply] = [:]

    func route(_ url: String, fixture: String) throws {
        let reply = try RecordingTransport.Reply.fixture(fixture)
        lock.withLock { routes[url] = reply }
    }

    func route(_ url: String, body: String) {
        lock.withLock { routes[url] = RecordingTransport.Reply(body: Data(body.utf8)) }
    }

    func reply(to url: URL) -> RecordingTransport.Reply {
        lock.withLock { routes[url.absoluteString] } ?? .status(404)
    }
}

/// The favorites' seasons, as the center's `loadSchedule` reads them, and
/// how often each was asked for.
private final class Seasons: @unchecked Sendable {
    private let lock = NSLock()
    private var seasons: [TeamRef.ID: [Game]]
    private var counts: [TeamRef.ID: Int] = [:]

    init(_ seasons: [TeamRef.ID: [Game]]) {
        self.seasons = seasons
    }

    func load(_ id: TeamRef.ID) -> [Game]? {
        lock.withLock {
            counts[id, default: 0] += 1
            return seasons[id]
        }
    }

    func loads(of id: TeamRef.ID) -> Int {
        lock.withLock { counts[id, default: 0] }
    }
}

/// The favorites list, observable like `FavoritesStore`'s.
@MainActor
@Observable
private final class Favorites {
    var ids: [TeamRef.ID]

    init(_ teams: [TeamRef]) {
        ids = teams.map(\.id)
    }
}

/// The current instant, set by hand.
@MainActor
private final class ManualClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
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

private func instant(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? .distantPast
}

/// A schedule entry: only the id, start, competition and status matter to
/// the live window.
private func fixture(
    _ gameID: String,
    at start: Date,
    competition: LeagueID? = nil,
    completed: Bool = false
) -> Game {
    Game(
        team: "", opponent: "", score: "", opponentScore: "",
        time: "", date: "", dateAsDate: start, opponentLogo: "", channel: "",
        location: "", gameHome: true, gameID: gameID, pointer: 0,
        gameWin: false, completed: completed, competitionName: "",
        cancelled: false, postponed: false, gameClock: "",
        gamePeriod: "", gameHalftime: false, competition: competition
    )
}

/// Sunday night, 9 p.m. Eastern: the Broncos' game (nfl_scoreboard_20260927,
/// 401872962, kicked off 00:20Z) is under way.
private let sundayNight = instant("2026-09-28T01:00:00Z")
/// The Eastern day every game below is filed under.
private let sunday = "20260927"
private let championsLeague = LeagueID.soccer("uefa.champions")

private let broncos = team(.nfl, "7")
private let royals = team(.mlb, "7")
private let arsenal = team(.premierLeague, "359")
private let leafs = team(.nhl, "21")

/// Broncos' game as the schedule lists it: live now.
private let broncosLive = fixture("401872962", at: instant("2026-09-28T00:20:00Z"))
/// Royals' game an hour from now: fifteen minutes short of the window.
private let royalsLater = fixture("royals-late", at: instant("2026-09-28T02:00:00Z"))
/// Royals' game tomorrow: out of the window.
private let royalsTomorrow = fixture("royals-tomorrow", at: instant("2026-09-29T00:00:00Z"))

/// A board with the Broncos' game over.
private let broncosFinal = """
{"events": [{"id": "401872962", "competitions": [{
  "id": "401872962", "date": "2026-09-28T00:20Z",
  "status": {"type": {"state": "post", "completed": true}},
  "competitors": [
    {"homeAway": "home", "team": {"id": "7"}, "score": "20"},
    {"homeAway": "away", "team": {"id": "14"}, "score": "17"}
  ]
}]}]}
"""

@Suite("League scoreboard center: following the favorites", .timeLimit(.minutes(1)))
struct FavoritesScoreboardFollowingTests {
    @MainActor
    private func makeCenter(
        _ transport: RecordingTransport,
        _ sleeper: HoldingSleeper,
        favorites: Favorites,
        seasons: Seasons,
        clock: ManualClock
    ) -> LeagueScoreboardCenter {
        LeagueScoreboardCenter(
            client: HTTPClient(transport: transport),
            favoriteIDs: { favorites.ids },
            sleep: { try await sleeper.sleep($0) },
            now: { clock.now },
            loadSchedule: { seasons.load($0) }
        )
    }

    private func makeBoards() throws -> Boards {
        let boards = Boards()
        try boards.route(LeagueID.nfl.scoreboardURL(day: sunday), fixture: "nfl_scoreboard_20260927")
        try boards.route(LeagueID.mlb.scoreboardURL(day: sunday), fixture: "mlb_scoreboard_20260927")
        try boards.route(championsLeague.scoreboardURL(day: sunday), fixture: "ucl_scoreboard_20260909")
        return boards
    }

    private func requests(_ transport: RecordingTransport, to league: LeagueID) -> Int {
        let url = league.scoreboardURL(day: sunday)
        return transport.urls.filter { $0.absoluteString == url }.count
    }

    // MARK: Pure decision

    @Test("Live days: the competition's games in the live window, less those a board showed over")
    @MainActor
    func followedDays() {
        let cupTie = fixture("cup", at: instant("2026-09-28T00:30:00Z"), competition: championsLeague)
        let league = fixture("league", at: instant("2026-09-27T23:30:00Z"))
        let played = fixture("played", at: instant("2026-09-27T23:00:00Z"), completed: true)
        let schedule = [cupTie, league, played, royalsTomorrow]

        let leagueDays = LeagueScoreboardCenter.followedDays(
            of: schedule, in: .premierLeague, league: .premierLeague, ended: [], now: sundayNight
        )
        #expect(leagueDays == [sunday])
        let cupDays = LeagueScoreboardCenter.followedDays(
            of: schedule, in: championsLeague, league: .premierLeague, ended: [], now: sundayNight
        )
        #expect(cupDays == [sunday])
        // Another cup the team plays in, with no tie today.
        let otherCup = LeagueScoreboardCenter.followedDays(
            of: schedule, in: .soccer("eng.fa"), league: .premierLeague, ended: [], now: sundayNight
        )
        #expect(otherCup.isEmpty)
        // A board showed the league game over: nothing left in the league.
        let afterFinal = LeagueScoreboardCenter.followedDays(
            of: schedule, in: .premierLeague, league: .premierLeague, ended: ["league"], now: sundayNight
        )
        #expect(afterFinal.isEmpty)
    }

    // MARK: Activation

    @Test("Starting polls each favorite's league with a game in the live window, cups included, and no other")
    @MainActor
    func startPollsLiveLeaguesOnly() async throws {
        let boards = try makeBoards()
        let transport = RecordingTransport { url, _ in boards.reply(to: url) }
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = Favorites([broncos, royals, arsenal, leafs])
        let seasons = Seasons([
            broncos.id: [broncosLive],
            royals.id: [royalsTomorrow],
            // A cup tie under way (not on the fixture board, so never seen
            // over); no league game today.
            arsenal.id: [
                fixture("ucl-live", at: instant("2026-09-28T00:30:00Z"), competition: championsLeague),
                fixture("epl-next", at: instant("2026-10-03T14:00:00Z")),
            ],
            leafs.id: [],
        ])
        let center = makeCenter(transport, sleeper, favorites: favorites, seasons: seasons, clock: ManualClock(sundayNight))
        #expect(center.pollingLeagues.isEmpty)

        center.startFollowingFavorites()
        // The following loop's pass, then one refresh each of NFL and the
        // Champions League.
        await ticks(3, from: &waits)

        #expect(center.isFollowingFavorites)
        #expect(center.pollingLeagues == [.nfl, championsLeague])
        #expect(center.days(wantedIn: .nfl) == [sunday])
        #expect(center.days(wantedIn: championsLeague) == [sunday])
        // One request per live league; the quiet ones cost nothing.
        #expect(transport.requestCount == 2)
        #expect(Set(transport.urls.map(\.absoluteString)) == [
            LeagueID.nfl.scoreboardURL(day: sunday),
            championsLeague.scoreboardURL(day: sunday),
        ])
        #expect(center.days(wantedIn: .mlb).isEmpty)
        #expect(center.days(wantedIn: .premierLeague).isEmpty)
        #expect(center.days(wantedIn: .nhl).isEmpty)
        // The polled board reached `games`, which the alerts and Live
        // Activities read, with no page mounted.
        #expect(center.games[.nfl]?.contains(where: { $0.gameID == "401872962" }) == true)

        // Each season was loaded once.
        #expect(seasons.loads(of: broncos.id) == 1)
        #expect(seasons.loads(of: arsenal.id) == 1)

        center.stopFollowingFavorites()
        #expect(center.pollingLeagues.isEmpty)
    }

    // MARK: Favorites changes

    @Test("Following a team while active subscribes its league; unfollowing withdraws it once no page wants it")
    @MainActor
    func favoritesChanges() async throws {
        let boards = try makeBoards()
        let transport = RecordingTransport { url, _ in boards.reply(to: url) }
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = Favorites([broncos])
        let seasons = Seasons([
            broncos.id: [broncosLive],
            royals.id: [fixture("royals-live", at: instant("2026-09-27T22:00:00Z"))],
        ])
        let center = makeCenter(transport, sleeper, favorites: favorites, seasons: seasons, clock: ManualClock(sundayNight))

        center.startFollowingFavorites()
        await ticks(2, from: &waits)
        #expect(center.pollingLeagues == [.nfl])

        // Followed from the browser: the change is observed, the Royals'
        // season loaded, and MLB polled.
        favorites.ids.append(royals.id)
        await ticks(1, from: &waits)
        #expect(center.pollingLeagues == [.nfl, .mlb])
        #expect(requests(transport, to: .mlb) == 1)
        #expect(seasons.loads(of: royals.id) == 1)

        // The Broncos' page is on screen as they are unfollowed: the page
        // keeps NFL polled…
        let page = center.subscribe(broncos, days: [sunday])
        favorites.ids.removeAll { $0 == broncos.id }
        await center.refreshFollowedFavorites()
        #expect(center.pollingLeagues == [.nfl, .mlb])
        #expect(center.days(wantedIn: .nfl) == [sunday])

        // …until it goes too.
        center.unsubscribe(page)
        #expect(center.pollingLeagues == [.mlb])

        // Unfollowing the Royals leaves nothing polled.
        favorites.ids.removeAll { $0 == royals.id }
        await center.refreshFollowedFavorites()
        #expect(center.pollingLeagues.isEmpty)
        #expect(requests(transport, to: .nfl) == 1)

        center.stopFollowingFavorites()
    }

    // MARK: Economics

    @Test("A league both a page and the favorites want is one poller and one request a refresh")
    @MainActor
    func sharedLeagueOneRequest() async throws {
        let boards = try makeBoards()
        let transport = RecordingTransport { url, _ in boards.reply(to: url) }
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = Favorites([broncos])
        let seasons = Seasons([broncos.id: [broncosLive]])
        let center = makeCenter(transport, sleeper, favorites: favorites, seasons: seasons, clock: ManualClock(sundayNight))

        // The Broncos' page is on screen…
        let page = center.subscribe(broncos, days: [sunday])
        await ticks(1, from: &waits)
        #expect(transport.requestCount == 1)

        // …and the app comes to the foreground: the favorites' subscription
        // joins the page's poller rather than starting another.
        center.startFollowingFavorites()
        await ticks(1, from: &waits)
        #expect(center.pollingLeagues == [.nfl])
        #expect(center.days(wantedIn: .nfl) == [sunday])
        #expect(transport.requestCount == 1)

        // Each refresh — each minute — is still one request.
        await center.refresh(.nfl)
        #expect(transport.requestCount == 2)
        await center.refresh(.nfl)
        #expect(transport.requestCount == 3)
        #expect(requests(transport, to: .nfl) == 3)

        // Either one alone keeps the league polled.
        center.unsubscribe(page)
        #expect(center.pollingLeagues == [.nfl])
        center.stopFollowingFavorites()
        #expect(center.pollingLeagues.isEmpty)
    }

    // MARK: Scene

    @Test("Active starts following, inactive changes nothing, background stops it; coming back resumes")
    @MainActor
    func sceneTransitions() async throws {
        let boards = try makeBoards()
        let transport = RecordingTransport { url, _ in boards.reply(to: url) }
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = Favorites([broncos])
        let seasons = Seasons([broncos.id: [broncosLive]])
        let center = makeCenter(transport, sleeper, favorites: favorites, seasons: seasons, clock: ManualClock(sundayNight))

        // Launched straight into the background (a widget refresh): nothing.
        center.sceneDidChange(to: .background)
        #expect(!center.isFollowingFavorites)
        #expect(center.pollingLeagues.isEmpty)

        center.sceneDidChange(to: .active)
        await ticks(2, from: &waits)
        #expect(center.isFollowingFavorites)
        #expect(center.pollingLeagues == [.nfl])
        #expect(transport.requestCount == 1)

        // Active again, or passing through inactive: no second loop, no
        // second poller.
        center.sceneDidChange(to: .active)
        center.sceneDidChange(to: .inactive)
        #expect(center.isFollowingFavorites)
        #expect(center.pollingLeagues == [.nfl])

        // Backgrounded: every poller stops, and nothing asks for more.
        center.sceneDidChange(to: .background)
        #expect(!center.isFollowingFavorites)
        #expect(center.pollingLeagues.isEmpty)
        #expect(center.days(wantedIn: .nfl).isEmpty)
        await center.refreshFollowedFavorites()
        #expect(center.pollingLeagues.isEmpty)
        #expect(transport.requestCount == 1)

        // Foreground again: polling resumes, the season kept from before.
        center.sceneDidChange(to: .active)
        await ticks(2, from: &waits)
        #expect(center.pollingLeagues == [.nfl])
        #expect(transport.requestCount == 2)
        #expect(seasons.loads(of: broncos.id) == 1)

        center.sceneDidChange(to: .background)
        #expect(center.pollingLeagues.isEmpty)
    }

    // MARK: Live window

    @Test("A game going final stops its league; a game entering the window starts its league")
    @MainActor
    func liveWindowGating() async throws {
        let boards = try makeBoards()
        let transport = RecordingTransport { url, _ in boards.reply(to: url) }
        let sleeper = HoldingSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let clock = ManualClock(sundayNight)
        let favorites = Favorites([broncos, royals])
        let seasons = Seasons([
            broncos.id: [broncosLive],
            royals.id: [royalsLater, royalsTomorrow],
        ])
        let center = makeCenter(transport, sleeper, favorites: favorites, seasons: seasons, clock: clock)

        center.startFollowingFavorites()
        await ticks(2, from: &waits)
        #expect(center.pollingLeagues == [.nfl])

        // The Broncos' game ends. The schedule still calls it unplayed, but
        // the board says it is over: NFL stops at that refresh.
        boards.route(LeagueID.nfl.scoreboardURL(day: sunday), body: broncosFinal)
        await center.refresh(.nfl)
        #expect(center.pollingLeagues.isEmpty)
        #expect(center.days(wantedIn: .nfl).isEmpty)
        let nflRequests = requests(transport, to: .nfl)

        // A minute's recheck with the game still in the schedule's window
        // does not bring NFL back.
        clock.now = sundayNight.addingTimeInterval(60)
        await center.refreshFollowedFavorites()
        #expect(center.pollingLeagues.isEmpty)
        #expect(requests(transport, to: .nfl) == nflRequests)

        // Ten minutes before the Royals' first pitch, the recheck finds the
        // game in the window and MLB starts.
        clock.now = instant("2026-09-28T01:50:00Z")
        await center.refreshFollowedFavorites()
        #expect(center.pollingLeagues == [.mlb])
        #expect(center.days(wantedIn: .mlb) == [sunday])
        await ticks(1, from: &waits)
        #expect(requests(transport, to: .mlb) == 1)
        // Tomorrow's game is not asked for.
        #expect(transport.urls.allSatisfy { !$0.absoluteString.contains("20260928") })

        center.stopFollowingFavorites()
        #expect(center.pollingLeagues.isEmpty)
    }
}
