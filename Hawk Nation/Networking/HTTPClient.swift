//
//  HTTPClient.swift
//  myTeams
//
//  A dependency-free replacement for the Alamofire package.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "network")

/// Fetches and decodes the JSON documents the app is built on.
///
/// Every call returns a `JSON` node rather than throwing. A request that fails
/// yields `JSON.null`, which the parsers read as a document with no events, no
/// athletes and no statistics — so a dropped connection leaves a screen in its
/// loading state instead of tearing down the view.
enum HTTPClient {
    /// A session that keeps responses in the shared URL cache, so the
    /// once-a-minute score refresh is cheap when nothing has changed upstream.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    /// Fetches `url` and parses the response body.
    static func json(from url: URL) async -> JSON {
        do {
            let (data, response) = try await session.data(from: url)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                logger.error("\(url.host() ?? "request") returned HTTP \(http.statusCode)")
                return .null
            }
            return JSON(data: data)
        } catch is CancellationError {
            return .null
        } catch let error as URLError where error.code == .cancelled {
            return .null
        } catch {
            logger.error("Request to \(url.host() ?? "host") failed: \(error.localizedDescription)")
            return .null
        }
    }

    /// Fetches a URL written as a string. A string that is not a valid URL
    /// yields `JSON.null`, the same as a failed request.
    static func json(from urlString: String) async -> JSON {
        guard let url = URL(string: urlString) else {
            // The string can still carry a query with the NewsAPI key, so
            // log the host only — matching the other failure paths above.
            let host = URLComponents(string: urlString)?.host ?? "unknown host"
            logger.error("Malformed URL for host \(host)")
            return .null
        }
        return await json(from: url)
    }
}
