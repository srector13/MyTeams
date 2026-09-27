//
//  HTTPClient.swift
//  myTeams
//
//  A dependency-free replacement for the Alamofire package.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "network")

/// Why a request produced no document.
enum NetworkError: Error, Sendable {
    /// The request never got a response: no connection, a timeout, a host
    /// that could not be found. The underlying error says which.
    case offline(URLError)
    /// The server answered with a status outside 200–299 — a 404 for an
    /// unknown event, a 429 while ESPN rate-limits, a 401 without a news key.
    case httpError(status: Int)
    /// The server answered 2xx with a body that is not JSON.
    case decodeError
    /// The address could not be formed into a URL.
    case invalidURL
    /// The calling task was cancelled, typically because its view went away.
    /// Nothing to report to the reader.
    case cancelled
}

/// The outcome of one request, as the loaders and views need to tell it apart.
///
/// Every failure used to collapse to `JSON.null`, which the parsers read as a
/// document with nothing in it — so a dropped connection, a rate limit and a
/// genuinely empty schedule all looked the same, and screens sat on their
/// loading skeletons forever.
enum FetchResult: Sendable {
    /// A parsed JSON document.
    case success(JSON)
    /// A successful response with no body.
    case empty
    case failure(NetworkError)

    /// The document, or `nil` when the request produced none.
    var document: JSON? {
        if case .success(let json) = self { return json }
        return nil
    }

    /// Parses a successful document with `transform`; an empty response
    /// yields `emptyValue`, and a failure passes through.
    func map<Value>(empty emptyValue: Value, _ transform: (JSON) -> Value) -> Result<Value, NetworkError> {
        switch self {
        case .success(let json): return .success(transform(json))
        case .empty: return .success(emptyValue)
        case .failure(let error): return .failure(error)
        }
    }
}

/// Performs the actual request, so tests can stand in for the network.
protocol HTTPTransport: Sendable {
    func load(_ url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    func load(_ url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url)
    }
}

/// Fetches and decodes the JSON documents the app is built on.
///
/// Every call returns a `FetchResult` rather than throwing, so callers can
/// show an empty state, an error with a retry, or keep what they already
/// have, as suits each screen.
struct HTTPClient: Sendable {
    /// The client every loader uses.
    static let shared = HTTPClient()

    /// A session that keeps responses in the shared URL cache, so the
    /// once-a-minute score refresh is cheap when nothing has changed upstream.
    ///
    /// It no longer waits for connectivity: with the default seven-day
    /// resource timeout that left a request offline hanging, and its screen
    /// loading, indefinitely. A request now gives up after 15 seconds without
    /// data and 60 in total, and the failure is reported as `.offline`.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let transport: any HTTPTransport

    init(transport: any HTTPTransport = HTTPClient.defaultSession) {
        self.transport = transport
    }

    /// Fetches `url` and parses the response body.
    func fetch(_ url: URL) async -> FetchResult {
        do {
            let (data, response) = try await transport.load(url)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                logger.error("\(url.host() ?? "request") returned HTTP \(http.statusCode)")
                return .failure(.httpError(status: http.statusCode))
            }
            if data.isEmpty {
                return .empty
            }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                logger.error("\(url.host() ?? "request") returned a body that is not JSON")
                return .failure(.decodeError)
            }
            return .success(JSON(raw))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch let error as URLError {
            logger.error("Request to \(url.host() ?? "host") failed: \(error.localizedDescription)")
            return .failure(.offline(error))
        } catch {
            // Anything a transport throws that is not a URLError still means
            // no response arrived.
            logger.error("Request to \(url.host() ?? "host") failed: \(error.localizedDescription)")
            return .failure(.offline(URLError(.unknown)))
        }
    }

    /// Fetches a URL written as a string. A string that is not a valid URL
    /// fails with `.invalidURL`.
    func fetch(_ urlString: String) async -> FetchResult {
        guard let url = URL(string: urlString) else {
            // Log the host only, matching the other failure paths above.
            let host = URLComponents(string: urlString)?.host ?? "unknown host"
            logger.error("Malformed URL for host \(host)")
            return .failure(.invalidURL)
        }
        return await fetch(url)
    }
}
