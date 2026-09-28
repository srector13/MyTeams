//
//  RecordingTransport.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

@testable import myTeams

/// Stands in for `URLSession`: answers each request with whatever `respond`
/// returns for it, and records every URL asked for, so tests can count the
/// requests a loader or poller makes.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    /// One canned response.
    struct Reply: Sendable {
        var status = 200
        var body = Data()
        var headers: [String: String] = [:]

        /// A 200 carrying a fixture's bytes.
        static func fixture(_ name: String, headers: [String: String] = [:]) throws -> Reply {
            Reply(body: try Data(contentsOf: Fixture.url(name)), headers: headers)
        }

        static func status(_ status: Int, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: headers)
        }
    }

    private let lock = NSLock()
    private var recorded: [URL] = []
    private let respond: @Sendable (URL, _ callIndex: Int) -> Reply

    /// - Parameter respond: the reply to a request, given its URL and how
    ///   many requests came before it.
    init(_ respond: @escaping @Sendable (URL, _ callIndex: Int) -> Reply) {
        self.respond = respond
    }

    /// Answers every request with `reply`.
    convenience init(always reply: Reply) {
        self.init { _, _ in reply }
    }

    /// Every URL requested so far, in order.
    var urls: [URL] {
        lock.withLock { recorded }
    }

    var requestCount: Int { urls.count }

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        let index = lock.withLock {
            recorded.append(url)
            return recorded.count - 1
        }
        let reply = respond(url, index)
        guard let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers
        ) else {
            throw URLError(.badServerResponse)
        }
        return (reply.body, response)
    }
}
