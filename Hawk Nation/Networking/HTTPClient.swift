//
//  HTTPClient.swift
//  myTeams
//
//  A dependency-free replacement for the Alamofire package.
//

import Foundation
import OSLog
import Synchronization

private let logger = Logger(subsystem: "com.myTeams", category: "network")

/// Whether a request reads and writes the on-disk `FeedCache` (R-4).
enum FeedCachePolicy: Sendable, Equatable {
    /// The network only, as every request was before the cache.
    case networkOnly
    /// The network first. A good JSON response is stored; a request that
    /// gets no response (`.offline`) is answered with the stored copy.
    case persist
    /// The stored copy when it is at most `maxAge` seconds old, else as
    /// `.persist`. For the widget, whose timeline reloads need not ask ESPN
    /// every time.
    case preferCache(maxAge: TimeInterval)
}

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

/// A `FetchResult` with the response headers a poller paces itself by.
struct FetchResponse: Sendable {
    var result: FetchResult
    /// The server's `Retry-After`, when it sent one.
    var retryAfter: Duration?
    /// The response's `Cache-Control: max-age`: how long it stays fresh.
    var maxAge: Duration?
    /// When the document was fetched, for one served from the `FeedCache`;
    /// `nil` for a response that just came from the network.
    var cachedAt: Date?

    init(result: FetchResult, retryAfter: Duration? = nil, maxAge: Duration? = nil, cachedAt: Date? = nil) {
        self.result = result
        self.retryAfter = retryAfter
        self.maxAge = maxAge
        self.cachedAt = cachedAt
    }

    /// Whether the server is asking the client to slow down: 403 or 429,
    /// which ESPN answers a too-eager client with, or any 5xx.
    var isThrottled: Bool {
        guard case .failure(.httpError(let status)) = result else { return false }
        return status == 403 || status == 429 || (500..<600).contains(status)
    }
}

/// How long a polling loop waits before its next request.
///
/// A good response brings the wait back to `base`, or longer when the
/// response says it stays fresh longer (`max-age`). Each throttled response
/// in a row (403, 429, 5xx — see `FetchResponse.isThrottled`) doubles the
/// wait, up to `cap`; a `Retry-After` longer than that is waited out in full,
/// up to `retryAfterLimit`. Any other failure — offline, a 404, a body that
/// is not JSON — keeps the current wait, neither escalating nor resetting.
///
/// A value type with no clock of its own: the caller sleeps for whatever
/// `delay(after:)` returns, so tests read the schedule directly.
struct PollBackoff: Sendable, Equatable {
    /// The wait after a good response.
    let base: Duration
    /// The longest a throttled loop waits, unless `Retry-After` asks for more.
    let cap: Duration
    /// The longest `Retry-After` honoured, against a header that asks for days.
    static let retryAfterLimit: Duration = .seconds(60 * 60)

    /// The wait the last response called for.
    private(set) var current: Duration

    init(base: Duration, cap: Duration = .seconds(10 * 60)) {
        self.base = base
        self.cap = max(cap, base)
        self.current = base
    }

    /// Records `response` and returns how long to wait before asking again.
    mutating func delay(after response: FetchResponse) -> Duration {
        if response.isThrottled {
            current = min(current * 2, cap)
            guard let retryAfter = response.retryAfter else { return current }
            return max(current, min(retryAfter, Self.retryAfterLimit))
        }
        switch response.result {
        case .success, .empty:
            current = base
            return max(base, min(response.maxAge ?? .zero, cap))
        case .failure:
            return current
        }
    }

    /// Starts the next throttle from `base` again, for a caller that paces
    /// its good responses itself.
    mutating func reset() {
        current = base
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

#if DEBUG
/// Answers requests from the captured ESPN documents in
/// `myTeamsTests/Fixtures` instead of the network, for UI-test launches that
/// set `MYTEAMS_FIXTURES_DIR` (see `HTTPClient.launchTransport`).
///
/// Each route maps an exact request URL to a fixture file; anything else is
/// a 404, so a fixture run never reaches the network and the screens see
/// the same failure a missing feed gives them. The URLs are written out
/// rather than built from `LeagueID`, so this file stays free of app-only
/// helpers for the widget target; `HTTPClientTests` checks the app's URL
/// builders still produce them.
struct FixtureTransport: HTTPTransport {
    /// The launch-environment key naming the fixtures folder.
    static let directoryKey = "MYTEAMS_FIXTURES_DIR"

    /// Request URL → fixture name, without `.json`.
    static let routes: [String: String] = {
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        return [
            // League catalogs (`LeagueID.teamsURL`), each trimmed to 15 teams.
            "\(site)/football/nfl/teams?limit=1000": "nfl_teams",
            "\(site)/basketball/nba/teams?limit=1000": "nba_teams",
            "\(site)/hockey/nhl/teams?limit=1000": "nhl_teams",
            "\(site)/basketball/wnba/teams?limit=1000": "wnba_teams",
            "\(site)/football/college-football/teams?limit=1000&groups=50": "ncaaf_teams",
            "\(site)/basketball/womens-college-basketball/teams?limit=1000&groups=50": "ncaaw_teams",
            "\(site)/soccer/eng.1/teams?limit=1000": "epl_teams",
            "\(site)/soccer/esp.1/teams?limit=1000": "laliga_teams",
            "\(site)/soccer/mex.1/teams?limit=1000": "ligamx_teams",
            "\(site)/soccer/usa.nwsl/teams?limit=1000": "nwsl_teams",
            "\(site)/soccer/ger.1/teams?limit=1000": "bundes_teams",
            "\(site)/soccer/ita.1/teams?limit=1000": "seriea_teams",
            "\(site)/soccer/fra.1/teams?limit=1000": "ligue1_teams",
            "\(site)/soccer/uefa.champions/teams?limit=1000": "uclleague_teams",
            "\(site)/soccer/eng.w.1/teams?limit=1000": "wsl_teams",
            "\(site)/soccer/fra.w.1/teams?limit=1000": "premiere_teams",
            // The seed teams. Kansas's live feed is between seasons and lists
            // no games, so it is served the 2025-26 season.
            "\(site)/basketball/mens-college-basketball/teams/2305/schedule": "jayhawks_schedule_2026",
            "\(site)/basketball/mens-college-basketball/teams/2305/roster": "jayhawks_roster",
            "\(site)/football/nfl/teams/12/schedule": "chiefs_schedule",
            "\(site)/football/nfl/teams/12/roster": "chiefs_roster",
            "\(site)/football/nfl/news?team=12&limit=25": "chiefs_news",
            "\(site)/baseball/mlb/teams/7/schedule": "royals_schedule",
            "\(site)/baseball/mlb/teams/7/roster": "royals_roster",
            "\(site)/soccer/usa.1/teams/186/schedule": "sporting_schedule",
            "\(site)/soccer/usa.1/teams/186/schedule?fixture=true": "sporting_schedule_fixtures",
            "\(site)/soccer/usa.1/teams/186/roster": "sporting_roster",
            // Kansas's league leaders (`LeagueLeadersView`), which list a
            // Jayhawk the roster above has, for the leaders → team page →
            // player sheet path (t_8d15e070).
            "https://site.api.espn.com/apis/site/v3/sports/basketball/mens-college-basketball/leaders?limit=10": "ncaam_leaders",
        ]
    }()

    /// The folder holding the fixtures, `<name>.json` each.
    let directory: URL

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        var status = 404
        var body = Data()
        if let name = Self.routes[url.absoluteString],
           let data = try? Data(contentsOf: directory.appendingPathComponent("\(name).json")) {
            status = 200
            body = data
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:]) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
}
#endif

/// Fetches and decodes the JSON documents the app is built on.
///
/// Every call returns a `FetchResult` rather than throwing, so callers can
/// show an empty state, an error with a retry, or keep what they already
/// have, as suits each screen.
struct HTTPClient: Sendable {
    /// The client every loader uses: the network, unless a Debug build was
    /// launched to serve fixtures (`launchTransport(environment:)`). It keeps
    /// the shared `FeedCache`, except in a fixture launch, which stays
    /// hermetic.
    static let shared = HTTPClient(
        transport: HTTPClient.launchTransport(environment: ProcessInfo.processInfo.environment),
        feedCache: HTTPClient.servesFixtures ? nil : FeedCache.shared
    )

    /// The transport a launch environment asks for: `FixtureTransport` over
    /// the folder named by `MYTEAMS_FIXTURES_DIR`, else `defaultSession`.
    ///
    /// UI tests set the key so the schedule and search assert on captured
    /// documents instead of skipping when ESPN doesn't answer (A-20). Read
    /// only in Debug builds; a Release build always uses the network.
    static func launchTransport(environment: [String: String]) -> any HTTPTransport {
        #if DEBUG
        if let path = environment[FixtureTransport.directoryKey], !path.isEmpty {
            return FixtureTransport(directory: URL(fileURLWithPath: path, isDirectory: true))
        }
        #endif
        return defaultSession
    }

    /// Whether this launch serves fixtures (`launchTransport(environment:)`).
    /// Crests, headshots and the team catalog's disk cache then stay off the
    /// network and out of the live launches' files too, so a fixture launch
    /// is hermetic and settles as fast as its documents load. Always `false`
    /// in Release.
    static let servesFixtures: Bool = {
        #if DEBUG
        return launchTransport(environment: ProcessInfo.processInfo.environment) is FixtureTransport
        #else
        return false
        #endif
    }()

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
    /// Where `.persist` and `.preferCache` requests keep their bodies; `nil`
    /// for a client that never touches the disk, whatever its policy.
    private let feedCache: FeedCache?

    init(transport: any HTTPTransport = HTTPClient.defaultSession, feedCache: FeedCache? = nil) {
        self.transport = transport
        self.feedCache = feedCache
    }

    // MARK: Feed cache scope

    /// The cache policy, and the report of what was served from the cache,
    /// for the requests inside a `withFeedCache` scope.
    struct FeedCacheContext: Sendable {
        let policy: FeedCachePolicy
        let report: FeedCacheReport
    }

    /// Collects when the oldest document served from the cache in a
    /// `withFeedCache` scope was fetched. Requests in the scope may run
    /// concurrently (`async let`, task groups), hence the lock.
    final class FeedCacheReport: Sendable {
        private let oldest = Mutex<Date?>(nil)

        /// The oldest `cachedAt` recorded, or `nil` when every document came
        /// from the network.
        var oldestCachedAt: Date? { oldest.withLock { $0 } }

        func record(_ cachedAt: Date) {
            oldest.withLock { current in
                current = min(current ?? cachedAt, cachedAt)
            }
        }
    }

    /// The scope a request runs in, set by `withFeedCache`. The loaders
    /// (`downloadScheduleData` and the rest) take no cache parameter; their
    /// callers opt their requests in by running them in a scope.
    @TaskLocal static var feedCacheContext: FeedCacheContext?

    /// The policy of the scope the current task runs in: `.networkOnly`
    /// outside any `withFeedCache`. The default of every fetch.
    static var taskCachePolicy: FeedCachePolicy {
        feedCacheContext?.policy ?? .networkOnly
    }

    /// Runs `operation` with its requests under `policy`, returning its value
    /// and, when any document it was given came from the cache, when the
    /// oldest such was fetched. The scope reaches child tasks too.
    static func withFeedCache<Value: Sendable>(
        _ policy: FeedCachePolicy,
        operation: @escaping @Sendable () async -> Value
    ) async -> (value: Value, cachedAt: Date?) {
        let report = FeedCacheReport()
        let value = await $feedCacheContext.withValue(FeedCacheContext(policy: policy, report: report)) {
            await operation()
        }
        return (value, report.oldestCachedAt)
    }

    // MARK: Fetching

    /// Fetches `url` and parses the response body.
    func fetch(_ url: URL, cache policy: FeedCachePolicy = HTTPClient.taskCachePolicy) async -> FetchResult {
        await fetchResponse(url, cache: policy).result
    }

    /// Fetches a URL written as a string. A string that is not a valid URL
    /// fails with `.invalidURL`.
    func fetch(_ urlString: String, cache policy: FeedCachePolicy = HTTPClient.taskCachePolicy) async -> FetchResult {
        await fetchResponse(urlString, cache: policy).result
    }

    /// Fetches `url` and parses the response body, keeping the headers a
    /// poller paces itself by: `Retry-After` and `Cache-Control: max-age`.
    /// See `PollBackoff`.
    ///
    /// Under `.persist` or `.preferCache` a good JSON response is stored in
    /// the `FeedCache`, and a request that gets no response at all is
    /// answered from it, with `cachedAt` set. Any other failure — a 404, a
    /// 429 — passes through: the server answered, and said no.
    ///
    /// - Parameters:
    ///   - now: the instant an HTTP-date `Retry-After` counts from.
    ///   - policy: whether to use the `FeedCache`; by default, the policy of
    ///     the surrounding `withFeedCache` scope.
    func fetchResponse(_ url: URL, now: Date = Date(), cache policy: FeedCachePolicy = HTTPClient.taskCachePolicy) async -> FetchResponse {
        guard let feedCache, policy != .networkOnly else {
            return await networkResponse(url, now: now).response
        }

        if case .preferCache(let maxAge) = policy,
           let cached = await cachedResponse(url, from: feedCache, maxAge: maxAge) {
            return cached
        }

        let (response, body) = await networkResponse(url, now: now)
        if let body {
            await feedCache.write(body, for: url)
            return response
        }
        guard case .failure(.offline) = response.result,
              let cached = await cachedResponse(url, from: feedCache, maxAge: nil)
        else { return response }
        return cached
    }

    /// Fetches a URL written as a string, keeping its pacing headers. A
    /// string that is not a valid URL fails with `.invalidURL`.
    func fetchResponse(_ urlString: String, now: Date = Date(), cache policy: FeedCachePolicy = HTTPClient.taskCachePolicy) async -> FetchResponse {
        guard let url = URL(string: urlString) else {
            // Log the host only, matching the other failure paths above.
            let host = URLComponents(string: urlString)?.host ?? "unknown host"
            logger.error("Malformed URL for host \(host)")
            return FetchResponse(result: .failure(.invalidURL))
        }
        return await fetchResponse(url, now: now, cache: policy)
    }

    /// `url`'s stored document, when the cache has a readable one, recorded
    /// in the surrounding `withFeedCache` scope's report.
    private func cachedResponse(_ url: URL, from feedCache: FeedCache, maxAge: TimeInterval?) async -> FetchResponse? {
        guard let entry = await feedCache.read(url, maxAge: maxAge),
              let raw = try? JSONSerialization.jsonObject(with: entry.body, options: [.fragmentsAllowed])
        else { return nil }
        Self.feedCacheContext?.report.record(entry.fetchedAt)
        return FetchResponse(result: .success(JSON(raw)), cachedAt: entry.fetchedAt)
    }

    /// Asks the network for `url`. The body comes back too when it parsed as
    /// JSON from a 2xx response, the only kind worth storing.
    private func networkResponse(_ url: URL, now: Date) async -> (response: FetchResponse, body: Data?) {
        do {
            let (data, response) = try await transport.load(url)
            let http = response as? HTTPURLResponse
            let retryAfter = Self.retryAfter(http?.value(forHTTPHeaderField: "Retry-After"), now: now)
            let maxAge = Self.maxAge(http?.value(forHTTPHeaderField: "Cache-Control"))
            func respond(_ result: FetchResult, body: Data? = nil) -> (response: FetchResponse, body: Data?) {
                (FetchResponse(result: result, retryAfter: retryAfter, maxAge: maxAge), body)
            }

            if let http, !(200..<300).contains(http.statusCode) {
                logger.error("\(url.host() ?? "request") returned HTTP \(http.statusCode)")
                return respond(.failure(.httpError(status: http.statusCode)))
            }
            if data.isEmpty {
                return respond(.empty)
            }
            guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                logger.error("\(url.host() ?? "request") returned a body that is not JSON")
                return respond(.failure(.decodeError))
            }
            return respond(.success(JSON(raw)), body: data)
        } catch is CancellationError {
            return (FetchResponse(result: .failure(.cancelled)), nil)
        } catch let error as URLError where error.code == .cancelled {
            return (FetchResponse(result: .failure(.cancelled)), nil)
        } catch let error as URLError {
            logger.error("Request to \(url.host() ?? "host") failed: \(error.localizedDescription)")
            return (FetchResponse(result: .failure(.offline(error))), nil)
        } catch {
            // Anything a transport throws that is not a URLError still means
            // no response arrived.
            logger.error("Request to \(url.host() ?? "host") failed: \(error.localizedDescription)")
            return (FetchResponse(result: .failure(.offline(URLError(.unknown)))), nil)
        }
    }

    // MARK: Pacing headers

    /// Reads `Retry-After`: delay-seconds (`"120"`) or an HTTP-date
    /// (`"Wed, 21 Oct 2026 07:28:00 GMT"`) measured from `now`. `nil` when
    /// absent, unreadable, or already past.
    static func retryAfter(_ value: String?, now: Date) -> Duration? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Int(value) {
            return seconds > 0 ? .seconds(seconds) : nil
        }
        guard let date = httpDateParser.date(from: value) else { return nil }
        let seconds = date.timeIntervalSince(now).rounded(.up)
        return seconds > 0 ? .seconds(Int(seconds)) : nil
    }

    /// Reads the `max-age` directive of a `Cache-Control` header, e.g.
    /// `"max-age=60, public"`. `nil` when absent or unreadable.
    static func maxAge(_ value: String?) -> Duration? {
        guard let value else { return nil }
        for directive in value.split(separator: ",") {
            let parts = directive.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "max-age",
                  let seconds = Int(parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            else { continue }
            return seconds >= 0 ? .seconds(seconds) : nil
        }
        return nil
    }

    /// Reads the IMF-fixdate form of an HTTP-date, the only one servers may
    /// send today (RFC 9110 §5.6.7).
    private static let httpDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
