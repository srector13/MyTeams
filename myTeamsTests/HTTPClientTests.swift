//
//  HTTPClientTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Stands in for `URLSession`, answering every request the same way.
private struct StubTransport: HTTPTransport {
    let respond: @Sendable (URL) throws -> (Data, URLResponse)

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        try respond(url)
    }

    /// Answers with `status`, `body` and `headers`.
    static func status(_ status: Int, body: String = "", headers: [String: String]? = nil) -> StubTransport {
        StubTransport { url in
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                throw URLError(.badServerResponse)
            }
            return (Data(body.utf8), response as URLResponse)
        }
    }

    /// Fails the way `URLSession` does, with no response at all.
    static func failing(_ code: URLError.Code) -> StubTransport {
        StubTransport { _ in throw URLError(code) }
    }
}

/// Covers how `HTTPClient` sorts each kind of response into a `FetchResult`,
/// which is what lets the screens tell "nothing scheduled" from "couldn't
/// load".
@Suite("HTTP client")
struct HTTPClientTests {
    private let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule")!

    private func fetch(with transport: StubTransport) async -> FetchResult {
        await HTTPClient(transport: transport).fetch(url)
    }

    @Test("A request with no connection fails as offline, carrying the URL error")
    func offline() async {
        let result = await fetch(with: .failing(.notConnectedToInternet))

        guard case .failure(.offline(let error)) = result else {
            Issue.record("Expected .offline, got \(result)")
            return
        }
        #expect(error.code == .notConnectedToInternet)
        #expect(result.document == nil)
    }

    @Test("A timed-out request fails as offline too")
    func timedOut() async {
        let result = await fetch(with: .failing(.timedOut))

        guard case .failure(.offline(let error)) = result else {
            Issue.record("Expected .offline, got \(result)")
            return
        }
        #expect(error.code == .timedOut)
    }

    @Test("A 404 fails with its status rather than reading as an empty document")
    func notFound() async {
        let result = await fetch(with: .status(404, body: #"{"message": "Not Found"}"#))

        guard case .failure(.httpError(let status)) = result else {
            Issue.record("Expected .httpError, got \(result)")
            return
        }
        #expect(status == 404)
        #expect(result.document == nil)
    }

    @Test("A 429 rate limit fails with its status")
    func rateLimited() async {
        let result = await fetch(with: .status(429))

        guard case .failure(.httpError(let status)) = result else {
            Issue.record("Expected .httpError, got \(result)")
            return
        }
        #expect(status == 429)
    }

    @Test("A 200 with a JSON body succeeds with the parsed document")
    func success() async {
        let result = await fetch(with: .status(200, body: #"{"events": [{"id": "401"}]}"#))

        let document = result.document
        #expect(document?["events", 0, "id"].stringValue == "401")
    }

    @Test("A 200 with no body is empty, not a failure")
    func emptyBody() async {
        let result = await fetch(with: .status(200))

        guard case .empty = result else {
            Issue.record("Expected .empty, got \(result)")
            return
        }
        // Loaders read an empty response as a feed with nothing in it.
        let games = result.map(empty: [String]()) { _ in ["unexpected"] }
        #expect((try? games.get())?.isEmpty == true)
    }

    @Test("A 200 whose body is not JSON is a decode error")
    func notJSON() async {
        let result = await fetch(with: .status(200, body: "<html>Service Unavailable</html>"))

        guard case .failure(.decodeError) = result else {
            Issue.record("Expected .decodeError, got \(result)")
            return
        }
    }

    @Test("A cancelled request is reported as cancelled, not offline")
    func cancelled() async {
        let result = await fetch(with: .failing(.cancelled))

        guard case .failure(.cancelled) = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
    }

    @Test("A string that is not a URL fails without a request")
    func invalidURL() async {
        let client = HTTPClient(transport: StubTransport { _ in
            Issue.record("No request should be made")
            throw URLError(.badURL)
        })
        let result = await client.fetch("")

        guard case .failure(.invalidURL) = result else {
            Issue.record("Expected .invalidURL, got \(result)")
            return
        }
    }

    @Test("A failure passes through map untouched")
    func mapKeepsFailure() async {
        let result = await fetch(with: .status(503))
        let mapped = result.map(empty: 0) { _ in 1 }

        guard case .failure(.httpError(let status)) = mapped else {
            Issue.record("Expected the HTTP error to pass through, got \(mapped)")
            return
        }
        #expect(status == 503)
    }
}

/// Covers the launch switch that serves the UI tests' requests from fixtures
/// (`MYTEAMS_FIXTURES_DIR`, A-20), and the routes it serves.
@Suite("Fixture transport")
struct FixtureTransportTests {
    @Test("With no fixtures key the client uses the network")
    func noKeyUsesNetwork() {
        let transport = HTTPClient.launchTransport(environment: [:])
        #expect((transport as? URLSession) === HTTPClient.defaultSession)
        let empty = HTTPClient.launchTransport(environment: [FixtureTransport.directoryKey: ""])
        #expect((empty as? URLSession) === HTTPClient.defaultSession)
    }

    @Test("With the fixtures key the client serves fixtures from that folder")
    func keyUsesFixtures() {
        let transport = HTTPClient.launchTransport(environment: [FixtureTransport.directoryKey: "/tmp/Fixtures"])
        let fixtures = transport as? FixtureTransport
        #expect(fixtures?.directory == URL(fileURLWithPath: "/tmp/Fixtures", isDirectory: true))
    }

    @Test("A routed URL answers with its fixture")
    func routedURL() async throws {
        let client = HTTPClient(transport: FixtureTransport(directory: try Fixture.directory()))
        let team = TeamCatalog.seeded(league: .nfl, espnID: "12")
        let result = await client.fetch(team.scheduleURL)

        let events = result.document?["events"].arrayValue ?? []
        #expect(!events.isEmpty)
    }

    @Test("An unrouted URL is a 404, never a network request")
    func unroutedURL() async throws {
        let client = HTTPClient(transport: FixtureTransport(directory: try Fixture.directory()))
        let result = await client.fetch(LeagueID.nfl.scoreboardURL(day: "20260927"))

        guard case .failure(.httpError(let status)) = result else {
            Issue.record("Expected a 404, got \(result)")
            return
        }
        #expect(status == 404)
    }

    @Test("Every route names a fixture that exists")
    func routesNameFixtures() {
        for (url, name) in FixtureTransport.routes {
            #expect((try? Fixture.url(name)) != nil, "\(url) routes to missing fixture \(name).json")
        }
    }

    /// The routes are written out, so this catches a URL builder drifting
    /// away from them.
    @Test("The app's URL builders produce the routed URLs")
    func routesMatchURLBuilders() {
        let catalogs: [LeagueID] = [
            .nfl, .nba, .nhl, .wnba, .collegeFootball, .womensCollegeBasketball,
            .premierLeague, .laLiga, .ligaMX, .nwsl,
            .bundesliga, .serieA, .ligue1, .championsLeague,
            .wsl, .premiereLigue,
        ]
        for league in catalogs {
            #expect(FixtureTransport.routes[league.teamsURL] != nil, "No route for \(league.teamsURL)")
        }

        let seeds = [
            TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305"),
            TeamCatalog.seeded(league: .nfl, espnID: "12"),
            TeamCatalog.seeded(league: .mlb, espnID: "7"),
            TeamCatalog.seeded(league: .mls, espnID: "186"),
        ]
        for team in seeds {
            #expect(FixtureTransport.routes[team.scheduleURL] != nil, "No route for \(team.scheduleURL)")
            #expect(FixtureTransport.routes[team.rosterURL] != nil, "No route for \(team.rosterURL)")
        }

        let chiefs = seeds[1]
        let sporting = seeds[3]
        #expect(FixtureTransport.routes[chiefs.newsURL] == "chiefs_news")
        #expect(FixtureTransport.routes[scheduleFixturesURL(sporting.scheduleURL)] == "sporting_schedule_fixtures")
        // Kansas's live feed is between seasons; the routed one has games.
        #expect(FixtureTransport.routes[seeds[0].scheduleURL] == "jayhawks_schedule_2026")
        // The league boards `LeagueLeadersView` loads, for the leaders →
        // team page → player sheet UI test (t_8d15e070).
        #expect(FixtureTransport.routes[LeagueID.mensCollegeBasketball.leadersURL(limit: 10)] == "ncaam_leaders")
        #expect(FixtureTransport.routes.count == catalogs.count + 2 * seeds.count + 3)
    }
}

/// Covers the headers a poller paces itself by, and the schedule
/// `PollBackoff` builds from them.
@Suite("Poll backoff")
struct PollBackoffTests {
    private let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=20260927")!

    private func response(_ status: Int, retryAfter: Duration? = nil, maxAge: Duration? = nil) -> FetchResponse {
        let result: FetchResult = (200..<300).contains(status)
            ? .success(.object([:]))
            : .failure(.httpError(status: status))
        return FetchResponse(result: result, retryAfter: retryAfter, maxAge: maxAge)
    }

    // MARK: Headers

    @Test("Retry-After reads as delay-seconds or an HTTP-date")
    func retryAfterHeader() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21T14:13:20Z
        #expect(HTTPClient.retryAfter("120", now: now) == .seconds(120))
        #expect(HTTPClient.retryAfter(" 30 ", now: now) == .seconds(30))
        #expect(HTTPClient.retryAfter("Mon, 21 Sep 2026 14:15:20 GMT", now: now) == .seconds(120))
        // Absent, unreadable, zero and past values ask for nothing.
        #expect(HTTPClient.retryAfter(nil, now: now) == nil)
        #expect(HTTPClient.retryAfter("soon", now: now) == nil)
        #expect(HTTPClient.retryAfter("0", now: now) == nil)
        #expect(HTTPClient.retryAfter("Mon, 21 Sep 2026 14:00:00 GMT", now: now) == nil)
    }

    @Test("Cache-Control's max-age is read among other directives")
    func maxAgeHeader() {
        // ESPN's scoreboards answer "max-age=4" and the like.
        #expect(HTTPClient.maxAge("max-age=4") == .seconds(4))
        #expect(HTTPClient.maxAge("public, max-age=60, must-revalidate") == .seconds(60))
        #expect(HTTPClient.maxAge("Max-Age=\"90\"") == .seconds(90))
        #expect(HTTPClient.maxAge("no-cache") == nil)
        #expect(HTTPClient.maxAge(nil) == nil)
    }

    @Test("The client passes the pacing headers through with the result")
    func headersPassThrough() async {
        let client = HTTPClient(transport: StubTransport.status(
            429, headers: ["Retry-After": "300", "Cache-Control": "max-age=10"]
        ))
        let response = await client.fetchResponse(url)
        #expect(response.isThrottled)
        #expect(response.retryAfter == .seconds(300))
        #expect(response.maxAge == .seconds(10))
        guard case .failure(.httpError(429)) = response.result else {
            Issue.record("Expected the 429 to pass through, got \(response.result)")
            return
        }
    }

    // MARK: Schedule

    @Test("403, 429 and 5xx throttle; 404 and offline do not")
    func throttleStatuses() {
        #expect(response(403).isThrottled)
        #expect(response(429).isThrottled)
        #expect(response(500).isThrottled)
        #expect(response(503).isThrottled)
        #expect(!response(404).isThrottled)
        #expect(!response(200).isThrottled)
        #expect(!FetchResponse(result: .failure(.offline(URLError(.notConnectedToInternet)))).isThrottled)
    }

    @Test("Each 429 in a row doubles the wait, up to the cap; success resets it")
    func doublesOnThrottle() {
        var backoff = PollBackoff(base: .seconds(60), cap: .seconds(600))
        #expect(backoff.delay(after: response(200)) == .seconds(60))
        #expect(backoff.delay(after: response(429)) == .seconds(120))
        #expect(backoff.delay(after: response(429)) == .seconds(240))
        #expect(backoff.delay(after: response(503)) == .seconds(480))
        #expect(backoff.delay(after: response(429)) == .seconds(600))
        #expect(backoff.delay(after: response(429)) == .seconds(600))
        #expect(backoff.delay(after: response(200)) == .seconds(60))
        #expect(backoff.delay(after: response(429)) == .seconds(120))
    }

    @Test("Retry-After is honoured when it asks for longer than the doubled wait")
    func honoursRetryAfter() {
        var backoff = PollBackoff(base: .seconds(60), cap: .seconds(600))
        #expect(backoff.delay(after: response(429, retryAfter: .seconds(300))) == .seconds(300))
        // Beyond the cap too: the server said when to come back.
        #expect(backoff.delay(after: response(429, retryAfter: .seconds(900))) == .seconds(900))
        // …but not for days.
        #expect(backoff.delay(after: response(429, retryAfter: .seconds(86_400))) == PollBackoff.retryAfterLimit)
        // A shorter Retry-After does not undercut the doubled wait.
        var fresh = PollBackoff(base: .seconds(60))
        #expect(fresh.delay(after: response(429, retryAfter: .seconds(5))) == .seconds(120))
    }

    @Test("A fresh response is not asked for again before its max-age runs out")
    func honoursMaxAge() {
        var backoff = PollBackoff(base: .seconds(60), cap: .seconds(600))
        // ESPN's usual few seconds leave the base interval alone.
        #expect(backoff.delay(after: response(200, maxAge: .seconds(4))) == .seconds(60))
        #expect(backoff.delay(after: response(200, maxAge: .seconds(180))) == .seconds(180))
        // An hour-long max-age is held to the cap, so live scores still move.
        #expect(backoff.delay(after: response(200, maxAge: .seconds(3600))) == .seconds(600))
    }

    @Test("Other failures keep the current wait")
    func otherFailuresHold() {
        var backoff = PollBackoff(base: .seconds(60), cap: .seconds(600))
        let offline = FetchResponse(result: .failure(.offline(URLError(.timedOut))))
        #expect(backoff.delay(after: offline) == .seconds(60))
        #expect(backoff.delay(after: response(429)) == .seconds(120))
        #expect(backoff.delay(after: offline) == .seconds(120))
        #expect(backoff.delay(after: response(404)) == .seconds(120))
        backoff.reset()
        #expect(backoff.current == .seconds(60))
    }
}
