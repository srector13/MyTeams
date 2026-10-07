//
//  ApiFootballHeadshotStore.swift
//  myTeams
//
//  Created by Stephen Rector on 10/7/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import CryptoKit
import Foundation
import Observation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "headshots")

// MARK: - Model

/// One row of API-Football's `/players` answer: who the player is in
/// API-Sports' own id space, and the teams they played for in the league.
struct ApiFootballPlayer: Codable, Hashable, Sendable {
    /// API-Sports' player id. Never an ESPN id: the two do not align
    /// (docs/HEADSHOT_SOURCE_APIFOOTBALL.md, "ID-alignment story").
    var id: Int
    /// The short name, e.g. `D. Raya`.
    var name: String
    var firstname: String
    var lastname: String
    /// The photo URL the row gave, if any.
    var photo: String?
    /// The row's team names, e.g. `["Arsenal"]`; empty when it gave none.
    var teams: [String]
    /// The API-Football league the row was swept from.
    var league: Int
}

/// One page of `/players`.
struct ApiFootballPage: Sendable {
    var players: [ApiFootballPlayer]
    /// The page this is, and how many there are (`paging`).
    var current: Int
    var total: Int
    /// The answer's `errors`, by key (`token`, `plan`, `requests`, …).
    var errors: [String: String]
}

/// An ESPN roster player, as the join needs them.
struct ApiFootballRosterEntry: Hashable, Sendable {
    var espnID: String
    var name: String
}

/// A player's API-Football photo, matched to an ESPN athlete by name and team.
struct ApiFootballPhoto: Codable, Hashable, Sendable {
    var playerID: Int
    /// API-Football's name for the player, for the credits list.
    var name: String
    /// The row's own photo URL, when it gave one on the media CDN.
    var photo: String?

    init(_ player: ApiFootballPlayer) {
        playerID = player.id
        name = player.name
        photo = player.photo
    }

    /// The keyless CDN image: the row's own URL when it is on the CDN,
    /// else the one built from the matched id — never from an ESPN id.
    var imageURL: URL? {
        if let photo, let url = URL(string: photo), url.host() == ApiFootball.mediaHost {
            return url
        }
        return ApiFootball.photoURL(playerID: playerID)
    }

    /// The credit every API-Football photo carries.
    static let creditLine = "Photo via API-Football / API-Sports"
}

/// Where a league's weekly sweep of `/players` has got to, and what it found.
struct ApiFootballSweep: Codable, Hashable, Sendable {
    var season: Int
    /// The page to ask for next.
    var nextPage: Int
    /// When the last full sweep finished; `nil` while one is under way.
    var completed: Date?
    /// Every player found, by sweeps past and present.
    var players: [ApiFootballPlayer]
}

// MARK: - Requests and parsing

/// The API-Football (API-Sports) requests behind the tier-3 headshot
/// fallback, and the parsers and name join over their answers. Pure
/// functions: `ApiFootballHeadshotStore` decides when to call them.
///
/// See docs/HEADSHOT_SOURCE_APIFOOTBALL.md: the keyed JSON API resolves
/// players by name and team; their photos come from a keyless CDN.
enum ApiFootball {
    /// The keyed JSON API: the only host that ever sees the reader's key.
    static let apiHost = "v3.football.api-sports.io"
    /// The keyless photo CDN.
    static let mediaHost = "media.api-sports.io"
    /// Where a reader signs up for a free key.
    static let dashboardURL = URL(string: "https://www.dashboard.api-football.com/")
    /// The header the key travels in.
    static let keyHeader = "x-apisports-key"

    /// API-Football's league id for each soccer league the app follows.
    /// Each was checked on 2026-10-07 against the league's crest on the
    /// keyless CDN (`media.api-sports.io/football/leagues/<id>.png`); the
    /// vendor's docs are bot-gated. A league missing here gets no tier 3.
    static let leagueIDs: [LeagueID: Int] = [
        .premierLeague: 39,
        .laLiga: 140,
        .serieA: 135,
        .bundesliga: 78,
        .ligue1: 61,
        .mls: 253,
        .ligaMX: 262,
        .wsl: 44,
        .nwsl: 254,
        .premiereLigue: 64,
    ]

    /// The most API-Football requests the app makes in one UTC day: the
    /// free plan allows 100, and the reader may use their key elsewhere.
    static let dailyRequestCap = 40

    /// How long a finished sweep stays fresh.
    static let sweepInterval: TimeInterval = 7 * 24 * 60 * 60

    /// The free plan allows 10 requests a minute: one every 6.5 seconds
    /// stays under it.
    static let requestSpacing: Duration = .milliseconds(6500)

    /// SHA-256 of the CDN's two "no photo" images, by byte count: the grey
    /// bust (5,192 B) and "NO PHOTO YET" (8,624 B). Rehashed 2026-10-07.
    static let placeholderHashes: [Int: String] = [
        5192: "2ff7d52a628fce5d954c58480dde4e47396db4bb405b7b7d6a6567134bf86422",
        8624: "575e4487e3942dd820fe682e8b81f9c59b0b0d60265433ce5bd1884db4004035",
    ]

    static func leagueID(for league: LeagueID) -> Int? {
        leagueIDs[league]
    }

    /// The `season=` for `league` at `date`: API-Football files a season
    /// under the year it starts (2026 for 2026-27) and MLS and the NWSL
    /// under their calendar year, as the app's `SeasonNaming` already does.
    static func season(for league: LeagueID, at date: Date) -> Int? {
        league.descriptor.seasonNaming?.season(at: date)
    }

    static var statusURL: URL? {
        URL(string: "https://\(apiHost)/status")
    }

    /// `GET https://v3.football.api-sports.io/players?league=39&season=2026&page=1`.
    static func playersURL(league: Int, season: Int, page: Int) -> URL? {
        URL(string: "https://\(apiHost)/players?league=\(league)&season=\(season)&page=\(page)")
    }

    /// `https://media.api-sports.io/football/players/<id>.png`. `playerID`
    /// must be API-Sports' own, from keyed JSON: an ESPN id here is another
    /// person's photo or a placeholder.
    static func photoURL(playerID: Int) -> URL? {
        URL(string: "https://\(mediaHost)/football/players/\(playerID).png")
    }

    /// `url` with the key header — only when it is the keyed API over
    /// HTTPS. Every other URL gets `nil`, so the key cannot reach the CDN
    /// or anywhere else.
    static func keyedRequest(_ url: URL, key: String) -> URLRequest? {
        guard url.scheme == "https", url.host() == apiHost else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: keyHeader)
        return request
    }

    /// The answer's `errors`: `[]` when there are none, else an object of
    /// messages (`{"token": "Error/Missing application key…"}`).
    static func errorMessages(_ json: JSON) -> [String: String] {
        if let object = json["errors"].dictionary {
            return object.mapValues(\.stringValue).filter { !$0.value.isEmpty }
        }
        var messages: [String: String] = [:]
        for (index, error) in json["errors"].arrayValue.enumerated() where !error.stringValue.isEmpty {
            messages[String(index)] = error.stringValue
        }
        return messages
    }

    /// What a `/status` answer says of the key. Errors mean a bad key.
    static func parseStatus(_ json: JSON, status: Int) -> ApiFootballProbe {
        if let message = errorMessages(json).sorted(by: { $0.key < $1.key }).first?.value {
            return .failed(message: "API-Football didn't accept the key: \(message)")
        }
        guard (200..<300).contains(status) else {
            return .failed(message: "API-Football didn't accept the key (HTTP \(status)).")
        }
        let response = json["response"]
        guard response.dictionary != nil else {
            return .failed(message: "API-Football's answer could not be read.")
        }
        let plan = response["subscription"]["plan"].stringValue
        var parts = [plan.isEmpty ? "Key accepted" : "\(plan) plan"]
        if let used = response["requests"]["current"].int, let limit = response["requests"]["limit_day"].int {
            parts.append("\(used) of \(limit) requests used today")
        }
        return .accepted(summary: parts.joined(separator: ", "))
    }

    /// One `/players` page. The team is `player.team` where a row has one,
    /// else each `statistics[].team`.
    static func parsePlayers(_ json: JSON, league: Int) -> ApiFootballPage {
        let players = json["response"].arrayValue.compactMap { row -> ApiFootballPlayer? in
            let player = row["player"]
            guard let id = player["id"].int, id > 0 else { return nil }
            var teams: [String] = []
            let names = [player["team"]["name"].stringValue]
                + row["statistics"].arrayValue.map { $0["team"]["name"].stringValue }
            for name in names where !name.isEmpty && !teams.contains(name) {
                teams.append(name)
            }
            let photo = player["photo"].stringValue
            return ApiFootballPlayer(
                id: id,
                name: player["name"].stringValue,
                firstname: player["firstname"].stringValue,
                lastname: player["lastname"].stringValue,
                photo: photo.isEmpty ? nil : photo,
                teams: teams,
                league: league
            )
        }
        let current = json["paging"]["current"].int ?? 1
        let total = json["paging"]["total"].int ?? json["paging"]["lastPage"].int ?? current
        return ApiFootballPage(players: players, current: current, total: total, errors: errorMessages(json))
    }

    /// The newest season a free-plan `plan` error offers ("try from 2022 to
    /// 2024" → 2024), or `nil` for any other error.
    static func fallbackSeason(from errors: [String: String]) -> Int? {
        guard let message = errors["plan"] else { return nil }
        return message.matches(of: /\b(?:19|20)\d{2}\b/).compactMap { Int(String($0.output)) }.max()
    }

    /// Whether `data` is one of the CDN's "no photo" images.
    static func isPlaceholder(_ data: Data) -> Bool {
        guard let expected = placeholderHashes[data.count] else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == expected
    }

    // MARK: Name and team join

    /// A name as comparable words: lowercased, accents and ligatures folded,
    /// apostrophes dropped, split at hyphens, dots and spaces.
    /// `"Martin Ødegaard"` → `["martin", "odegaard"]`, `"J. O'Neil"` → `["j", "oneil"]`.
    static func tokens(_ text: String) -> [String] {
        var folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        for (from, to) in [
            ("ø", "o"), ("æ", "ae"), ("œ", "oe"), ("ß", "ss"), ("ł", "l"),
            ("đ", "d"), ("ð", "d"), ("þ", "th"), ("ı", "i"),
            ("'", ""), ("’", ""), ("`", ""),
        ] {
            folded = folded.replacingOccurrences(of: from, with: to)
        }
        return folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Words a club's name carries that say nothing of which club it is,
    /// including the women's-side markers (`Chelsea W`).
    private static let teamNoise: Set<String> = [
        "fc", "cf", "afc", "sc", "ac", "ssc", "cd", "ud", "rc", "rcd", "sd", "club", "de", "the",
        "w", "wfc", "women", "womens", "ladies", "femenino", "feminin", "feminine", "feminines",
    ]

    /// Whether ESPN's team name and API-Football's name the same club: the
    /// shorter's words all in the longer, a word matching another it
    /// begins (`inter` ↔ `internazionale`) when both are 4+ letters.
    static func teamsMatch(_ espn: String, _ api: String) -> Bool {
        let a = Set(tokens(espn)).subtracting(teamNoise)
        let b = Set(tokens(api)).subtracting(teamNoise)
        guard !a.isEmpty, !b.isEmpty else { return false }
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        return small.allSatisfy { word in
            large.contains { other in
                other == word || (min(word.count, other.count) >= 4 && (other.hasPrefix(word) || word.hasPrefix(other)))
            }
        }
    }

    /// Whether ESPN's `name` is `player`: every word the same as their full
    /// or short name; or, unless `strict`, the first name and a surname word
    /// (`Kepa Arrizabalaga` ↔ Kepa / Arrizabalaga Revuelta), or the short
    /// name's initial and surname (`Ben White` ↔ `B. White`).
    static func namesMatch(_ name: String, _ player: ApiFootballPlayer, strict: Bool) -> Bool {
        let espn = tokens(name)
        guard !espn.isEmpty else { return false }
        let short = tokens(player.name)
        if espn == tokens("\(player.firstname) \(player.lastname)") || espn == short { return true }
        guard !strict, espn.count >= 2, let first = espn.first, let last = espn.last else { return false }
        if tokens(player.firstname).first == first, tokens(player.lastname).contains(last) { return true }
        let surname = Array(short.dropFirst())
        if let initial = short.first, initial.count == 1, initial.first == first.first,
           !surname.isEmpty, surname.count < espn.count, Array(espn.suffix(surname.count)) == surname {
            return true
        }
        return false
    }

    /// ESPN ids → API-Football players, for `roster` of `team` in `league`.
    ///
    /// Only rows swept from `league`'s own API-Football league are
    /// considered, so a women's roster never meets a men's row (and the
    /// reverse) however alike the names and clubs. A row naming teams must
    /// name `team`; a row naming none must match the whole name. A whole-name
    /// match outranks a looser one; a player still left with two candidate
    /// rows is left out rather than guessed.
    static func join(
        roster: [ApiFootballRosterEntry],
        team: String,
        league: LeagueID,
        players: [ApiFootballPlayer]
    ) -> [String: ApiFootballPlayer] {
        guard let apiLeague = leagueID(for: league) else { return [:] }
        let candidates = players.filter { player in
            player.league == apiLeague
                && (player.teams.isEmpty || player.teams.contains { teamsMatch(team, $0) })
        }
        var matches: [String: ApiFootballPlayer] = [:]
        for entry in roster {
            let exact = candidates.filter { namesMatch(entry.name, $0, strict: true) }
            let found = exact.isEmpty
                ? candidates.filter { namesMatch(entry.name, $0, strict: $0.teams.isEmpty) }
                : exact
            if Set(found.map(\.id)).count == 1, let player = found.first {
                matches[entry.espnID] = player
            }
        }
        return matches
    }

    // MARK: Network

    /// Asks `/status` whether `key` works: one request, which API-Football
    /// does not count against the day's quota. The key is never in the
    /// message.
    static func probe(key: String, transport: any KeyedHTTPTransport) async -> ApiFootballProbe {
        guard let url = statusURL, let request = keyedRequest(url, key: key) else {
            return .failed(message: "The key could not be checked.")
        }
        do {
            let (data, response) = try await transport.send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let outcome = parseStatus(JSON(data: data), status: status)
            if case .failed(let message) = outcome {
                return .failed(message: message.replacingOccurrences(of: key, with: "…"))
            }
            return outcome
        } catch {
            return .failed(message: "Couldn't reach API-Football. Check your connection and try again.")
        }
    }

    /// The keyed API's session: no shared cache (answers are kept in the
    /// store's files), and a short timeout.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

/// Sends a request built by `ApiFootball.keyedRequest`, header and all, so
/// tests can stand in for the network.
protocol KeyedHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: KeyedHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

// MARK: - Budget

/// Counts API-Football requests per UTC day in `UserDefaults` (a count, not
/// a secret) and refuses any past `cap`; the count starts again each day.
struct ApiFootballBudget {
    static let defaultsKey = "apiFootball.budget"

    let defaults: UserDefaults
    let cap: Int
    let now: () -> Date

    init(defaults: UserDefaults = .standard, cap: Int = ApiFootball.dailyRequestCap, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.cap = cap
        self.now = now
    }

    /// `2026-10-07`: the UTC day of `date`.
    static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Requests made today.
    var used: Int {
        let stored = defaults.dictionary(forKey: Self.defaultsKey)
        guard stored?["day"] as? String == Self.day(now()) else { return 0 }
        return stored?["count"] as? Int ?? 0
    }

    var canSpend: Bool { used < cap }

    /// Counts one request. `false`, counting nothing, once today's cap is reached.
    @discardableResult
    func spend() -> Bool {
        let used = used
        guard used < cap else { return false }
        let entry: [String: Any] = ["day": Self.day(now()), "count": used + 1]
        defaults.set(entry, forKey: Self.defaultsKey)
        return true
    }
}

// MARK: - Store

/// Tier 3 of the soccer headshot fallback: photos from API-Football, with
/// the reader's own key, for athletes ESPN and Wikidata have none of.
///
/// A team page hands the store its roster as it loads (`prefetch(roster:team:league:)`).
/// If that league's last sweep is a week old, or never ran, the store pages
/// through `/players?league=&season=` — one request every few seconds,
/// never more than `ApiFootball.dailyRequestCap` a UTC day (`ApiFootballBudget`);
/// a sweep cut short by the cap resumes on a later day where it stopped.
/// Rows are joined to ESPN's roster by name and team, never by id.
///
/// Every page is cached on disk, one file per league under
/// Caches/ApiFootball, so photos survive without spending quota. Nothing
/// is asked, and no photo is given, without `credentials()`: the toggle on
/// and a key saved. Failure is silent and pauses the sweep for an hour.
@MainActor
@Observable
final class ApiFootballHeadshotStore {
    static let shared = ApiFootballHeadshotStore()

    /// Matched photos, by league and then ESPN id.
    private(set) var matches: [LeagueID: [String: ApiFootballPhoto]] = [:]

    /// The photos drawn this session, in the order first shown, for
    /// Settings → Photo Credits.
    private(set) var shownThisSession: [ApiFootballPhoto] = []

    @ObservationIgnored private let transport: any KeyedHTTPTransport
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let credentials: @MainActor () -> String?
    @ObservationIgnored private let budget: ApiFootballBudget
    @ObservationIgnored private let spacing: Duration
    /// Today, for the season asked for and a sweep's age.
    @ObservationIgnored private let now: () -> Date
    /// `false` keeps the store off the network: fixture launches.
    @ObservationIgnored private let enabled: Bool

    /// Sweeps by API-Football league.
    @ObservationIgnored private var sweeps: [Int: ApiFootballSweep]
    /// The rosters seen, by league and team name, to join each new page to.
    @ObservationIgnored private var rosters: [LeagueID: [String: [ApiFootballRosterEntry]]] = [:]
    @ObservationIgnored private var sweepTasks: [Int: Task<Void, Never>] = [:]
    /// After a failure, no request before this.
    @ObservationIgnored private var pausedUntil: Date?

    /// How long the store keeps quiet after a failed request.
    static let failurePause: TimeInterval = 60 * 60

    /// Caches/ApiFootball, beside Wikidata's Caches/Headshots.
    static var defaultDirectory: URL {
        SharedPaths.caches.appending(path: "ApiFootball", directoryHint: .isDirectory)
    }

    init(
        transport: any KeyedHTTPTransport = ApiFootball.session,
        directory: URL = ApiFootballHeadshotStore.defaultDirectory,
        credentials: @escaping @MainActor () -> String? = { ApiFootballSettings.shared.activeKey() },
        budget: ApiFootballBudget = ApiFootballBudget(),
        spacing: Duration = ApiFootball.requestSpacing,
        now: @escaping () -> Date = { Date() },
        enabled: Bool = !HTTPClient.servesFixtures
    ) {
        self.transport = transport
        self.directory = directory
        self.credentials = credentials
        self.budget = budget
        self.spacing = spacing
        self.now = now
        self.enabled = enabled
        sweeps = Self.load(from: directory)
    }

    // MARK: Reading

    /// The athlete's API-Football photo, once matched — and only while the
    /// reader's key is in use.
    func photo(espnID: String, league: LeagueID) -> ApiFootballPhoto? {
        guard credentials() != nil else { return nil }
        return matches[league]?[espnID]
    }

    /// Records that `photo` was drawn, for the credits list: once per player.
    func noteShown(_ photo: ApiFootballPhoto) {
        guard !shownThisSession.contains(where: { $0.playerID == photo.playerID }) else { return }
        shownThisSession.append(photo)
    }

    // MARK: Requesting

    /// Joins a roster that has just loaded to the cached rows, and starts
    /// the league's sweep if it is due and today's budget allows. Without a
    /// key the roster is only remembered, for `resume()`; nothing is asked.
    /// Does nothing for a league with no API-Football id.
    func prefetch(roster: [ApiFootballRosterEntry], team: String, league: LeagueID) {
        guard enabled, !roster.isEmpty, ApiFootball.leagueID(for: league) != nil else { return }
        rosters[league, default: [:]][team] = roster
        resume(league)
    }

    /// Joins and sweeps every roster seen this session, as `prefetch` would:
    /// for when the key or toggle has just turned on, since a page already
    /// on screen loads no roster to say so. Nothing without a key.
    func resume() {
        for league in rosters.keys {
            resume(league)
        }
    }

    private func resume(_ league: LeagueID) {
        guard enabled, credentials() != nil, let apiLeague = ApiFootball.leagueID(for: league) else { return }
        rejoin(league, apiLeague: apiLeague)
        startSweepIfDue(league, apiLeague: apiLeague)
    }

    /// Waits for every sweep in progress. For tests.
    func settle() async {
        while let task = sweepTasks.values.first {
            await task.value
        }
    }

    private func startSweepIfDue(_ league: LeagueID, apiLeague: Int) {
        guard sweepTasks[apiLeague] == nil, !isPaused, budget.canSpend else { return }
        if let completed = sweeps[apiLeague]?.completed,
           now().timeIntervalSince(completed) < ApiFootball.sweepInterval {
            return
        }
        sweepTasks[apiLeague] = Task { [weak self] in
            await self?.sweep(league, apiLeague: apiLeague)
            self?.sweepTasks[apiLeague] = nil
        }
    }

    /// Pages through the league until the sweep is done, the day's budget
    /// is spent, the key is withdrawn, or a request fails.
    private func sweep(_ league: LeagueID, apiLeague: Int) async {
        var sweep = sweeps[apiLeague] ?? ApiFootballSweep(season: 0, nextPage: 1, completed: nil, players: [])
        if sweep.completed != nil || sweep.season == 0 {
            // A new sweep, of the season under way; the old rows stay
            // drawable until the new pages replace them.
            guard let season = ApiFootball.season(for: league, at: now()) else { return }
            sweep.season = season
            sweep.nextPage = 1
            sweep.completed = nil
        }
        var triedOlderSeason = false
        var first = true

        while sweep.completed == nil {
            if !first {
                do { try await Task.sleep(for: spacing) } catch { return }
            }
            first = false
            guard let key = credentials(), budget.canSpend,
                  let url = ApiFootball.playersURL(league: apiLeague, season: sweep.season, page: sweep.nextPage),
                  let request = ApiFootball.keyedRequest(url, key: key)
            else { return }
            budget.spend()

            guard let answer = await load(request) else {
                pause()
                return
            }
            let (status, json) = answer
            let page = ApiFootball.parsePlayers(json, league: apiLeague)
            if !page.errors.isEmpty {
                // The free plan covers only some seasons: sweep the newest
                // it offers. Clubs may have changed since, so some players
                // will miss; none will be mismatched.
                if !triedOlderSeason, let older = ApiFootball.fallbackSeason(from: page.errors), older < sweep.season {
                    triedOlderSeason = true
                    sweep.season = older
                    sweep.nextPage = 1
                    continue
                }
                let refused = sweep.nextPage
                logger.debug("API-Football refused page \(refused) of league \(apiLeague)")
                pause()
                return
            }
            guard (200..<300).contains(status) else {
                pause()
                return
            }

            var byID = Dictionary(sweep.players.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for player in page.players { byID[player.id] = player }
            sweep.players = byID.values.sorted { $0.id < $1.id }
            if page.current >= page.total || page.players.isEmpty {
                sweep.completed = now()
                sweep.nextPage = 1
            } else {
                sweep.nextPage = page.current + 1
            }
            sweeps[apiLeague] = sweep
            save(apiLeague)
            rejoin(league, apiLeague: apiLeague)
        }
        let count = sweep.players.count
        logger.debug("Swept league \(apiLeague): \(count) players")
    }

    /// Sends `request`: its status and body, or `nil` when no answer came.
    private func load(_ request: URLRequest) async -> (Int, JSON)? {
        do {
            let (data, response) = try await transport.send(request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, JSON(data: data))
        } catch {
            return nil
        }
    }

    /// Joins every roster seen in `league` to its rows.
    private func rejoin(_ league: LeagueID, apiLeague: Int) {
        let players = sweeps[apiLeague]?.players ?? []
        guard !players.isEmpty else { return }
        var joined = matches[league] ?? [:]
        for (team, roster) in rosters[league] ?? [:] {
            let found = ApiFootball.join(roster: roster, team: team, league: league, players: players)
            for entry in roster {
                joined[entry.espnID] = found[entry.espnID].map { ApiFootballPhoto($0) }
            }
        }
        if joined != matches[league] ?? [:] {
            matches[league] = joined
        }
    }

    private var isPaused: Bool {
        pausedUntil.map { Date() < $0 } ?? false
    }

    private func pause() {
        pausedUntil = Date().addingTimeInterval(Self.failurePause)
    }

    // MARK: Disk

    func fileURL(for apiLeague: Int) -> URL {
        directory.appending(path: "league-\(apiLeague).json", directoryHint: .notDirectory)
    }

    /// Every `league-<id>.json` in `directory`, by league id.
    private static func load(from directory: URL) -> [Int: ApiFootballSweep] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var sweeps: [Int: ApiFootballSweep] = [:]
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("league-"), let id = Int(name.dropFirst("league-".count)),
                  let data = try? Data(contentsOf: file),
                  let sweep = try? JSONDecoder().decode(ApiFootballSweep.self, from: data)
            else { continue }
            sweeps[id] = sweep
        }
        return sweeps
    }

    private func save(_ apiLeague: Int) {
        guard let sweep = sweeps[apiLeague], let data = try? JSONEncoder().encode(sweep) else { return }
        let file = fileURL(for: apiLeague)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Could not write \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

// MARK: - Images

/// Loads API-Football photos from the keyless CDN — no key, no header —
/// keeping them in memory, and the CDN's bytes in a URL cache. Only
/// `ApiFootball.mediaHost` is fetched. The CDN's two placeholder images
/// count as no photo (`ApiFootball.isPlaceholder`), so the view keeps its
/// own. Every failure is `nil`.
actor ApiFootballImageLoader {
    static let shared = ApiFootballImageLoader()

    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    /// A plain session with a disk cache: the CDN allows 48 hours.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let transport: any HTTPTransport
    /// `false` keeps the loader off the network: fixture launches.
    private let enabled: Bool

    /// Downloads in progress, by URL, shared by every caller of that URL.
    private var loads: [URL: Task<UIImage?, Never>] = [:]

    init(
        transport: any HTTPTransport = ApiFootballImageLoader.session,
        enabled: Bool = !HTTPClient.servesFixtures
    ) {
        self.transport = transport
        self.enabled = enabled
    }

    func image(for url: URL) async -> UIImage? {
        guard enabled, url.scheme == "https", url.host() == ApiFootball.mediaHost else { return nil }
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let existing = loads[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [transport] in
            do {
                let (data, response) = try await transport.load(url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                guard !ApiFootball.isPlaceholder(data) else { return nil }
                return UIImage(data: data)
            } catch {
                logger.debug("API-Football image failed: \(error.localizedDescription)")
                return nil
            }
        }
        loads[url] = task
        let image = await task.value
        if let image { memory.setObject(image, forKey: url as NSURL) }
        loads[url] = nil
        return image
    }
}
