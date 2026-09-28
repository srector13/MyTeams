//
//  LeagueScoreboardTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Stands in for the pollers' `Task.sleep`: reports every wait it is asked
/// for, returns at once from the first `passes` of them, and after that holds
/// the poller until it is cancelled.
private final class ScriptedSleeper: @unchecked Sendable {
    let waits: AsyncStream<Duration>
    private let continuation: AsyncStream<Duration>.Continuation
    private let passes: Int
    private let lock = NSLock()
    private var calls = 0

    init(passes: Int = 0) {
        (waits, continuation) = AsyncStream.makeStream(of: Duration.self)
        self.passes = passes
    }

    func sleep(_ duration: Duration) async throws {
        let call = lock.withLock {
            calls += 1
            return calls
        }
        continuation.yield(duration)
        if call <= passes { return }
        try await Task.sleep(for: .seconds(24 * 60 * 60))
    }
}

/// The next `count` waits a sleeper reports: one per poller tick. Runs on
/// the caller's actor, so the (non-Sendable) iterator never crosses one.
private func nextWaits(
    _ count: Int,
    from iterator: inout AsyncStream<Duration>.Iterator,
    isolation: isolated (any Actor)? = #isolation
) async -> [Duration] {
    var waits: [Duration] = []
    for _ in 0..<count {
        guard let wait = await iterator.next(isolation: isolation) else { break }
        waits.append(wait)
    }
    return waits
}

/// A team known only by league and id, as a favorite the catalog has not
/// named yet.
private func team(_ league: LeagueID, _ espnID: String) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: espnID, shortName: espnID, abbreviation: "", location: "",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

private let day = "20260927"

/// Answers each league's scoreboard from its fixture, and anything else
/// with a 404 (which a test would see in `urls`).
private func scoreboardTransport() -> RecordingTransport {
    RecordingTransport { url, _ in
        let path = url.path()
        let name = if path.hasSuffix("football/nfl/scoreboard") {
            "nfl_scoreboard_20260927"
        } else if path.hasSuffix("baseball/mlb/scoreboard") {
            "mlb_scoreboard_20260927"
        } else {
            ""
        }
        guard !name.isEmpty else { return .status(404) }
        return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
    }
}

// MARK: - Parsing

/// Golden values from the captured scoreboards (see FIXTURES.md, "League
/// scoreboards"): `nfl_scoreboard_20260927` has Sunday night's game in
/// progress, `mlb_scoreboard_20260927` a cancelled game, and
/// `nfl_scoreboard_20260928` Monday night's game before kickoff.
@Suite("League scoreboard parsing")
struct LeagueScoreboardParsingTests {
    @Test("Scoreboard URLs: one per league and day; college basketball asks for Division I")
    func scoreboardURL() {
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        #expect(LeagueID.nfl.scoreboardURL(day: day) == "\(site)/football/nfl/scoreboard?dates=20260927")
        #expect(LeagueID.mls.scoreboardURL(day: day) == "\(site)/soccer/usa.1/scoreboard?dates=20260927")
        #expect(LeagueID.mensCollegeBasketball.scoreboardURL(day: day)
            == "\(site)/basketball/mens-college-basketball/scoreboard?dates=20260927&groups=50&limit=1000")
        // groups=50 would narrow college football to six games; FBS is its default.
        #expect(LeagueID(sport: "football", league: "college-football").scoreboardURL(day: day)
            == "\(site)/football/college-football/scoreboard?dates=20260927")
    }

    @Test("Games are filed under their start's date in US Eastern time")
    func scoreboardDays() throws {
        // nfl_scoreboard_20260927 id 401872962 .date: Sunday night, 00:20Z Monday.
        #expect(scoreboardDay(for: try #require(parseGameDate("2026-09-28T00:20Z"))) == "20260927")
        #expect(scoreboardDay(for: try #require(parseGameDate("2026-09-27T17:00Z"))) == "20260927")
        #expect(scoreboardDay(for: try #require(parseGameDate("2026-09-28T04:30Z"))) == "20260928")
    }

    @Test("A scoreboard reads every game by id, with scores keyed by team id")
    func nflScoreboard() throws {
        let board = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        #expect(board.games.map(\.gameID) == ["401872962", "401872952", "401872961"])

        // events[0]: Rams (14, away) 26 at Broncos (7, home) 23, 0:48 in the 4th.
        let live = try #require(board.games.first { $0.gameID == "401872962" })
        #expect(live.state == "in")
        #expect(!live.completed)
        #expect(Set(live.competitors) == [
            ScoreboardCompetitor(teamID: "7", homeAway: "home", score: 23),
            ScoreboardCompetitor(teamID: "14", homeAway: "away", score: 26),
        ])
        #expect(live.liveScore(for: "7") == LiveGameScore(score: 23, opponentScore: 26))
        #expect(live.liveScore(for: "14") == LiveGameScore(score: 26, opponentScore: 23))
        #expect(live.liveScore(for: "12") == nil)  // not in this game

        // The Chiefs (12, away) won 24–10 at Miami (15): the same event as
        // chiefs_summary_live_401872952, captured earlier in the game.
        #expect(board.lines(for: "12") == [
            ScoreboardLine(gameID: "401872952", opponentID: "15", score: LiveGameScore(score: 24, opponentScore: 10)),
        ])
        #expect(board.lines(for: "15").first?.score == LiveGameScore(score: 10, opponentScore: 24))
        #expect(board.lines(for: "99").isEmpty)
    }

    @Test("Games not yet started or called off carry no score, though the board says 0–0")
    func noScoreBeforeKickoffOrWhenCancelled() throws {
        // nfl_scoreboard_20260928: Monday night, state "pre", both scores "0".
        let monday = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260928"))
        let pregame = try #require(monday.games.first)
        #expect(pregame.state == "pre")
        #expect(pregame.competitors.map(\.score) == [0, 0])
        #expect(pregame.liveScore(for: "3") == nil)
        #expect(monday.lines(for: "21").isEmpty)

        // mlb_scoreboard_20260927 id 401817103: STATUS_CANCELED, state "post",
        // completed false, 0–0.
        let mlb = parseScoreboard(from: try Fixture.json("mlb_scoreboard_20260927"))
        let cancelled = try #require(mlb.games.first { $0.gameID == "401817103" })
        #expect(cancelled.state == "post" && !cancelled.completed)
        #expect(cancelled.liveScore(for: "10") == nil)
        // …while the Royals' finished game does: Guardians 2 at Royals 3.
        #expect(mlb.lines(for: "7") == [
            ScoreboardLine(gameID: "401817109", opponentID: "5", score: LiveGameScore(score: 3, opponentScore: 2)),
        ])
    }

    @Test("Malformed events, competitions and competitors are skipped, not read as zeros")
    func shapeGuards() {
        let json = JSON(data: Data("""
        {"events": [
          "not an event",
          {"id": "1", "competitions": [
            "not a competition",
            {"id": "", "status": {"type": {"state": "in"}},
             "competitors": [
               {"homeAway": "home", "team": {"id": "7"}, "score": "3"},
               {"homeAway": "away", "team": {}, "score": "9"},
               {"homeAway": "away", "team": {"id": "5"}, "score": {"displayValue": "2"}}
             ]}
          ]},
          {"competitions": [{"competitors": []}]}
        ]}
        """.utf8))
        let board = parseScoreboard(from: json)
        // The competition had no id, so it takes the event's; the event with
        // neither is dropped.
        #expect(board.games.count == 1)
        let game = board.games[0]
        #expect(game.gameID == "1")
        #expect(game.competitors.map(\.teamID) == ["7", "5"])
        #expect(game.liveScore(for: "7") == LiveGameScore(score: 3, opponentScore: 2))

        #expect(parseScoreboard(from: JSON(data: Data())).games.isEmpty)
        #expect(parseScoreboard(from: JSON(data: Data(#"{"events": {"id": "1"}}"#.utf8))).games.isEmpty)
    }
}

// MARK: - Batching

@Suite("League scoreboard batching", .timeLimit(.minutes(1)))
struct LeagueScoreboardCenterTests {
    private let nflFavorites = ["12", "15", "7", "14", "13"].map { team(.nfl, $0) }
    private let mlbFavorites = ["7", "5", "20", "21", "10"].map { team(.mlb, $0) }

    @MainActor
    private func makeCenter(
        _ transport: RecordingTransport,
        _ sleeper: ScriptedSleeper,
        favorites: [TeamRef]
    ) -> LeagueScoreboardCenter {
        let ids = favorites.map(\.id)
        return LeagueScoreboardCenter(
            client: HTTPClient(transport: transport),
            favoriteIDs: { ids },
            sleep: { try await sleeper.sleep($0) }
        )
    }

    @Test("Ten favorites across two leagues cost two requests a tick, not one per game")
    @MainActor
    func twoLeaguesTwoRequests() async {
        let transport = scoreboardTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = nflFavorites + mlbFavorites
        let center = makeCenter(transport, sleeper, favorites: favorites)

        // The worst case: every favorite's page subscribed at once, each
        // with a game in today's live window.
        let subscriptions = favorites.map { center.subscribe($0, days: [day]) }
        #expect(center.pollingLeagues == [.nfl, .mlb])

        // One tick of each league's poller.
        let ticks = await nextWaits(2, from: &waits)
        #expect(ticks == [.seconds(60), .seconds(60)])

        #expect(transport.requestCount == 2)
        #expect(Set(transport.urls.map(\.absoluteString)) == [
            LeagueID.nfl.scoreboardURL(day: day),
            LeagueID.mlb.scoreboardURL(day: day),
        ])

        // Both documents fanned out to every favorite in their league.
        #expect(center.lines[team(.nfl, "12").id]?.first?.score == LiveGameScore(score: 24, opponentScore: 10))
        #expect(center.lines[team(.nfl, "15").id]?.first?.score == LiveGameScore(score: 10, opponentScore: 24))
        #expect(center.lines[team(.nfl, "7").id]?.first?.score == LiveGameScore(score: 23, opponentScore: 26))
        #expect(center.lines[team(.nfl, "14").id]?.first?.score == LiveGameScore(score: 26, opponentScore: 23))
        #expect(center.lines[team(.nfl, "13").id]?.first?.score == LiveGameScore(score: 35, opponentScore: 27))
        #expect(center.lines[team(.mlb, "7").id]?.first?.score == LiveGameScore(score: 3, opponentScore: 2))
        #expect(center.lines[team(.mlb, "5").id]?.first?.score == LiveGameScore(score: 2, opponentScore: 3))
        #expect(center.lines[team(.mlb, "20").id]?.first?.score == LiveGameScore(score: 6, opponentScore: 4))
        #expect(center.lines[team(.mlb, "21").id]?.first?.score == LiveGameScore(score: 4, opponentScore: 6))
        #expect(center.lines[team(.mlb, "10").id] == [])  // cancelled
        // Teams on the boards that nobody follows are not fanned out to.
        #expect(center.lines[team(.nfl, "18").id] == nil)

        for subscription in subscriptions {
            center.unsubscribe(subscription)
        }
        #expect(center.pollingLeagues.isEmpty)
    }

    @Test("One visible page's request serves every favorite in its league; other leagues poll nothing")
    @MainActor
    func visiblePageOnly() async {
        let transport = scoreboardTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let center = makeCenter(transport, sleeper, favorites: nflFavorites + mlbFavorites)

        // Only the selected (Chiefs) page is mounted.
        let chiefs = center.subscribe(nflFavorites[0], days: [day])
        _ = await nextWaits(1, from: &waits)

        #expect(transport.requestCount == 1)
        #expect(center.pollingLeagues == [.nfl])
        // The other NFL favorites were filled from the same document…
        for favorite in nflFavorites {
            #expect(center.lines[favorite.id]?.count == 1)
        }
        // …and the MLB favorites, whose pages are not mounted, cost nothing.
        for favorite in mlbFavorites {
            #expect(center.lines[favorite.id] == nil)
        }
        center.unsubscribe(chiefs)
    }

    @Test("Mounting and unmounting pages starts and stops exactly one poller per league")
    @MainActor
    func pollerLifecycle() async {
        let transport = scoreboardTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let center = makeCenter(transport, sleeper, favorites: nflFavorites + mlbFavorites)
        #expect(center.pollingLeagues.isEmpty)

        // A page with nothing in the live window polls nothing.
        let royals = center.subscribe(mlbFavorites[0], days: [])
        #expect(center.pollingLeagues.isEmpty)

        // Mounting the Chiefs page starts the NFL poller; a second NFL page
        // joins it rather than starting another.
        let chiefs = center.subscribe(nflFavorites[0], days: [day])
        #expect(center.pollingLeagues == [.nfl])
        let broncos = center.subscribe(nflFavorites[2], days: [day])
        #expect(center.pollingLeagues == [.nfl])

        _ = await nextWaits(1, from: &waits)
        #expect(transport.requestCount == 1)

        // Unmounting one leaves the poller to the other; unmounting both
        // stops it.
        center.unsubscribe(chiefs)
        #expect(center.pollingLeagues == [.nfl])
        center.unsubscribe(broncos)
        #expect(center.pollingLeagues.isEmpty)
        // Unsubscribing twice changes nothing.
        center.unsubscribe(broncos)
        #expect(center.pollingLeagues.isEmpty)

        // The Royals' game enters the live window: now MLB is polled.
        center.update(royals, days: [day])
        #expect(center.pollingLeagues == [.mlb])
        _ = await nextWaits(1, from: &waits)
        #expect(transport.requestCount == 2)
        #expect(transport.urls.last?.absoluteString == LeagueID.mlb.scoreboardURL(day: day))

        center.unsubscribe(royals)
        #expect(center.pollingLeagues.isEmpty)
        // The last scores stay for when a page comes back.
        #expect(center.lines[mlbFavorites[0].id]?.isEmpty == false)
    }

    @Test("A 429 doubles the next wait, Retry-After is honoured, and last-known scores survive")
    @MainActor
    func backoff() async {
        let transport = RecordingTransport { _, call in
            switch call {
            case 0: .status(429)
            case 1: .status(429, headers: ["Retry-After": "300"])
            case 2: (try? RecordingTransport.Reply.fixture("nfl_scoreboard_20260927", headers: ["Cache-Control": "max-age=4"])) ?? .status(404)
            default: .status(503)
            }
        }
        let sleeper = ScriptedSleeper(passes: 3)
        var waits = sleeper.waits.makeAsyncIterator()
        let center = makeCenter(transport, sleeper, favorites: nflFavorites)
        let chiefs = center.subscribe(nflFavorites[0], days: [day])

        let delays = await nextWaits(4, from: &waits)
        #expect(delays == [
            .seconds(120),  // 429: the 60-second interval, doubled
            .seconds(300),  // 429 again: doubled to 240, but Retry-After says 300
            .seconds(60),   // 200: back to the interval (max-age=4 is shorter)
            .seconds(120),  // 503: doubled again
        ])
        #expect(transport.requestCount == 4)

        // The 503 kept the scores the 200 brought.
        #expect(center.lines[nflFavorites[0].id]?.first?.score == LiveGameScore(score: 24, opponentScore: 10))
        center.unsubscribe(chiefs)
    }

    @Test("A schedule game finds its score by id, or by opponent when the ids differ")
    @MainActor
    func matchingGames() async throws {
        let transport = scoreboardTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let center = makeCenter(transport, sleeper, favorites: [.chiefs])
        let subscription = center.subscribe(.chiefs, days: [day])
        _ = await nextWaits(1, from: &waits)
        center.unsubscribe(subscription)

        // chiefs_schedule.json id 401872952: at Miami (15).
        let (event, pointer) = try Fixture.event("401872952", in: Fixture.json("chiefs_schedule"))
        var game = parseGame(from: event, team: .chiefs, pointer: pointer)
        #expect(game.gameID == "401872952")
        #expect(game.opponentID == "15")
        #expect(center.liveScore(for: game, team: .chiefs) == LiveGameScore(score: 24, opponentScore: 10))

        game.gameID = "0"
        #expect(center.liveScore(for: game, team: .chiefs) == LiveGameScore(score: 24, opponentScore: 10))

        game.opponentID = "99"
        #expect(center.liveScore(for: game, team: .chiefs) == nil)
    }

    @Test("The registry is the favorites in the league, in favorites order")
    @MainActor
    func registryFollowsFavorites() {
        var favoriteIDs = (nflFavorites + mlbFavorites).map(\.id)
        let center = LeagueScoreboardCenter(
            client: HTTPClient(transport: RecordingTransport(always: .status(404))),
            favoriteIDs: { favoriteIDs },
            sleep: { _ in }
        )
        #expect(center.registry(for: .nfl) == nflFavorites.map(\.id))
        #expect(center.registry(for: .mls).isEmpty)

        // Read afresh each time: an unfollowed team drops out at once.
        favoriteIDs.removeFirst()
        #expect(center.registry(for: .nfl) == nflFavorites.dropFirst().map(\.id))
    }
}

// MARK: - The new leagues

/// The P3 scoreboards by the exact URL the registry builds for each, so a
/// request the registry did not build is a 404 the test sees. See
/// FIXTURES.md, "New leagues (P3-a)" and "Cross-league acceptance (P3-e)".
private let newLeagueBoards: [String: String] = [
    LeagueID.nba.scoreboardURL(day: "20261003"): "nba_scoreboard_20261003",
    LeagueID.nhl.scoreboardURL(day: "20260919"): "nhl_scoreboard_20260919",
    LeagueID.premierLeague.scoreboardURL(day: "20260821"): "epl_scoreboard_20260821",
    LeagueID.premierLeague.scoreboardURL(day: "20260909"): "epl_scoreboard_20260909",
    LeagueID.soccer("uefa.champions").scoreboardURL(day: "20260909"): "ucl_scoreboard_20260909",
    LeagueID.collegeFootball.scoreboardURL(day: "20260829"): "ncaaf_scoreboard_20260829",
]

private func newLeagueTransport() -> RecordingTransport {
    RecordingTransport { url, _ in
        guard let name = newLeagueBoards[url.absoluteString] else { return .status(404) }
        return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
    }
}

@Suite("League scoreboards: favorites in the new leagues", .timeLimit(.minutes(1)))
struct NewLeagueScoreboardCenterTests {
    private let heat = team(.nba, "14")
    private let raptors = team(.nba, "28")
    private let leafs = team(.nhl, "21")
    private let canadiens = team(.nhl, "10")
    private let arsenal = team(.premierLeague, "359")
    private let coventry = team(.premierLeague, "388")
    private let usc = team(.collegeFootball, "30")
    private let sanJose = team(.collegeFootball, "23")
    /// Plays the Champions League too (`LeagueDescriptor.laLiga.cupCompetitions`).
    private let barcelona = team(.laLiga, "83")
    private let championsLeague = LeagueID.soccer("uefa.champions")

    @MainActor
    private func makeCenter(
        _ transport: RecordingTransport,
        _ sleeper: ScriptedSleeper,
        favorites: [TeamRef]
    ) -> LeagueScoreboardCenter {
        let ids = favorites.map(\.id)
        return LeagueScoreboardCenter(
            client: HTTPClient(transport: transport),
            favoriteIDs: { ids },
            sleep: { try await sleeper.sleep($0) }
        )
    }

    @Test("NBA, NHL, EPL and NCAAF favorites poll one scoreboard each, by the registry's URL")
    @MainActor
    func fourLeagues() async {
        let transport = newLeagueTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let favorites = [heat, raptors, leafs, canadiens, arsenal, coventry, usc, sanJose]
        let center = makeCenter(transport, sleeper, favorites: favorites)

        // One page per league on screen, each on its game's day.
        let subscriptions = [
            center.subscribe(heat, days: ["20261003"]),
            center.subscribe(leafs, days: ["20260919"]),
            center.subscribe(arsenal, days: ["20260821"]),
            center.subscribe(usc, days: ["20260829"]),
        ]
        #expect(center.pollingLeagues == [.nba, .nhl, .premierLeague, .collegeFootball])

        _ = await nextWaits(4, from: &waits)
        #expect(transport.requestCount == 4)
        #expect(Set(transport.urls.map(\.absoluteString)) == [
            "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=20261003",
            "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=20260919",
            "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20260821",
            "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard?dates=20260829",
        ])

        // nba_scoreboard_20261003: Heat at Raptors before tip-off, "0"–"0"
        // on the board, so no score for either.
        #expect(center.lines[heat.id] == [])
        #expect(center.lines[raptors.id] == [])

        // nhl_scoreboard_20260919: split squads, two games each on one board.
        #expect(center.lines[leafs.id] == [
            ScoreboardLine(gameID: "401881922", opponentID: "10", score: LiveGameScore(score: 1, opponentScore: 4)),
            ScoreboardLine(gameID: "401881923", opponentID: "10", score: LiveGameScore(score: 3, opponentScore: 4)),
        ])
        #expect(center.lines[canadiens.id]?.map(\.score) == [
            LiveGameScore(score: 4, opponentScore: 1),
            LiveGameScore(score: 4, opponentScore: 3),
        ])

        // epl_scoreboard_20260821: Arsenal 3–0 Coventry, "FT".
        #expect(center.lines[arsenal.id] == [
            ScoreboardLine(gameID: "401879301", opponentID: "388", score: LiveGameScore(score: 3, opponentScore: 0)),
        ])
        #expect(center.lines[coventry.id]?.first?.score == LiveGameScore(score: 0, opponentScore: 3))

        // ncaaf_scoreboard_20260829: USC 42–26 San José State.
        #expect(center.lines[usc.id]?.first?.score == LiveGameScore(score: 42, opponentScore: 26))
        #expect(center.lines[sanJose.id]?.first?.score == LiveGameScore(score: 26, opponentScore: 42))

        for subscription in subscriptions {
            center.unsubscribe(subscription)
        }
        #expect(center.pollingLeagues.isEmpty)
    }

    @Test("Live cards name the period by sport; soccer shows its match status")
    func liveCardLabels() throws {
        // The NHL board's overtime game (401881923): status.period 4.
        let board = try Fixture.json("nhl_scoreboard_20260919")
        let overtime = board["events", 1, "competitions", 0, "status", "period"].stringValue
        #expect(overtime == "4")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel(overtime) == "OT")
        #expect(LeagueDescriptor.nhl.liveCardPeriodLabel("2") == "2nd Period")
        #expect(LeagueDescriptor.nba.liveCardPeriodLabel("4") == "4th Quarter")
        #expect(LeagueDescriptor.collegeFootball.liveCardPeriodLabel("5") == "OT")

        // Soccer: epl_schedule's Coventry match (401879301) rewound to the
        // interval and then the 67th minute. At the break the card shows
        // the status ("Halftime"), not a period; in play, the half and the
        // match clock.
        let schedule = try Fixture.json("epl_schedule")
        let (event, pointer) = try Fixture.event("401879301", in: schedule)
        let status: [JSON.Index] = ["competitions", 0, "status"]
        let inPlay = event
            .setting(status + ["type", "completed"], to: .bool(false))
            .setting(status + ["type", "state"], to: .string("in"))

        let interval = parseGame(
            from: inPlay
                .setting(status + ["period"], to: .number(1))
                .setting(status + ["type", "description"], to: .string("Halftime")),
            team: arsenal, pointer: pointer
        )
        #expect(interval.gameHalftime)
        #expect(!interval.completed)

        let secondHalf = parseGame(
            from: inPlay
                .setting(status + ["period"], to: .number(2))
                .setting(status + ["displayClock"], to: .string("67'"))
                .setting(status + ["type", "description"], to: .string("Second Half")),
            team: arsenal, pointer: pointer
        )
        #expect(!secondHalf.gameHalftime)
        #expect(secondHalf.gameClock == "67'")
        #expect(LeagueDescriptor.premierLeague.liveCardPeriodLabel(secondHalf.gamePeriod) == "2nd Half")
    }

    @Test("Bug: soccer extra time read as OT, 2OT and penalties as 3OT")
    func soccerExtraTime() {
        // A cup tie level after 90 minutes plays periods 3 and 4 (extra
        // time), then a shoot-out.
        for league in [LeagueDescriptor.premierLeague, .laLiga, .ligaMX, .nwsl, .mls] {
            #expect(league.liveCardPeriodLabel("2") == "2nd Half")
            #expect(league.liveCardPeriodLabel("3") == "Extra Time")
            #expect(league.liveCardPeriodLabel("4") == "Extra Time")
            #expect(league.liveCardPeriodLabel("5") == "Penalties")
        }
        // Halves elsewhere still go to overtime.
        #expect(LeagueDescriptor.mensCollegeBasketball.liveCardPeriodLabel("3") == "OT")
        #expect(LeagueDescriptor.mensCollegeBasketball.liveCardPeriodLabel("4") == "2OT")
    }

    @Test("Bug: cup ties got no live score — the poller watched the league's scoreboard only")
    @MainActor
    func cupTies() async throws {
        let transport = newLeagueTransport()
        let sleeper = ScriptedSleeper()
        var waits = sleeper.waits.makeAsyncIterator()
        let center = makeCenter(transport, sleeper, favorites: [arsenal, barcelona, heat])

        // Arsenal won 1–0 at Napoli (114) in the Champions League on
        // September 9 (ucl_schedule_359, ucl_scoreboard_20260909). The
        // Premier League's board that day is empty (epl_scoreboard_20260909):
        // the league poller alone finds nothing.
        let league = center.subscribe(arsenal, days: ["20260909"])
        _ = await nextWaits(1, from: &waits)
        #expect(transport.urls.last?.absoluteString
            == "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20260909")
        #expect(center.lines[arsenal.id] == [])

        // The page subscribes the cup's days under the cup.
        let cup = center.subscribe(arsenal, competition: championsLeague, days: ["20260909"])
        #expect(cup.league == championsLeague)
        #expect(center.pollingLeagues == [.premierLeague, championsLeague])
        _ = await nextWaits(1, from: &waits)
        #expect(transport.requestCount == 2)
        #expect(transport.urls.last?.absoluteString
            == "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/scoreboard?dates=20260909")

        let napoli = ScoreboardLine(gameID: "401915423", opponentID: "114", score: LiveGameScore(score: 1, opponentScore: 0))
        #expect(center.lines[arsenal.id] == [napoli])

        // The cup's registry is every favorite whose league plays it:
        // Barcelona's 5–1 over Feyenoord (142) came in the same document.
        #expect(center.registry(for: championsLeague) == [arsenal.id, barcelona.id])
        #expect(center.lines[barcelona.id] == [
            ScoreboardLine(gameID: "401915424", opponentID: "142", score: LiveGameScore(score: 5, opponentScore: 1)),
        ])
        #expect(center.lines[heat.id] == nil)

        // A later league refresh keeps the cup's line.
        await center.refresh(.premierLeague)
        #expect(center.lines[arsenal.id] == [napoli])

        // The schedule card finds it: the merged schedule files the tie
        // under the cup, by the event's league.slug.
        let leagueSchedule = try Fixture.json("epl_schedule")
        let cupSchedule = try Fixture.json("ucl_schedule_359")
        let games = mergeSchedules(
            league: leagueSchedule, cups: [(competition: championsLeague, json: cupSchedule)], team: arsenal
        )
        let tie = try #require(games.first { $0.gameID == "401915423" })
        #expect(tie.competition == championsLeague)
        #expect(center.liveScore(for: tie, team: arsenal) == LiveGameScore(score: 1, opponentScore: 0))

        center.unsubscribe(league)
        center.unsubscribe(cup)
        #expect(center.pollingLeagues.isEmpty)
    }
}
