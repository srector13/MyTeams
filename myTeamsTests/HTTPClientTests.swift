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

    /// Answers with `status` and `body`.
    static func status(_ status: Int, body: String = "") -> StubTransport {
        StubTransport { url in
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
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
