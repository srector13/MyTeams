//
//  TheSportsDBHeadshotStore.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "headshots")

// MARK: - Model

/// One row of TheSportsDB's `searchplayers.php` answer. Every field may be
/// missing or `null`; a missing string is empty.
struct TheSportsDBPlayer: Hashable, Sendable {
    /// TheSportsDB's player id (`idPlayer`).
    var id: String
    /// `strPlayer`, e.g. `Dejan Joveljić`.
    var name: String
    /// `strTeam`: the club, or `_Retired-Soccer` and the like.
    var team: String
    /// `strSport`, e.g. `Soccer`.
    var sport: String
    /// `strGender`: `Male`, `Female` or empty.
    var gender: String
    /// `strNumber`, when it is a number.
    var number: Int?
    /// `strCutout`, `strThumb` and `strRender`, as given.
    var cutout: String?
    var thumb: String?
    var render: String?

    /// The photo to draw: the cutout, else the thumbnail, else the render —
    /// the first that is an HTTPS URL.
    var imageURL: URL? {
        for candidate in [cutout, thumb, render] {
            guard let candidate, let url = URL(string: candidate),
                  url.scheme == "https", url.host() != nil
            else { continue }
            return url
        }
        return nil
    }
}

/// A TheSportsDB photo matched to an ESPN athlete by name and club.
struct TheSportsDBPhoto: Codable, Hashable, Sendable {
    var playerID: String
    /// TheSportsDB's name for the player, for the credits list.
    var name: String
    var imageURL: URL
}

/// What the store knows of one player: a photo, or that TheSportsDB has
/// none it can match. Asked again once `TheSportsDB.photoInterval` (a
/// photo) or `noMatchInterval` (none) old.
struct TheSportsDBRecord: Codable, Hashable, Sendable {
    var photo: TheSportsDBPhoto?
    /// When TheSportsDB answered.
    var checked: Date
}

// MARK: - Requests and parsing

/// TheSportsDB's free v1 API behind the soccer photo tier, and the parser
/// and join over its answers. Pure functions: `TheSportsDBHeadshotStore`
/// decides when to call them.
///
/// The free key is `3`, public by design. Players are searched by name
/// (`searchplayers.php?p=`); a row counts only if it is soccer, of the
/// roster's sex, at ESPN's club, and is the roster player by name — so a
/// namesake who has retired (`_Retired-Soccer`) or a row whose club is out
/// of date never lends a face.
enum TheSportsDB {
    static let apiHost = "www.thesportsdb.com"
    /// The free, public test key.
    static let freeKey = "3"

    /// The fewest seconds between two requests: the free key allows about
    /// 30 a minute.
    static let requestSpacing: Duration = .milliseconds(2500)
    /// How long a matched photo stands before the player is asked about again.
    static let photoInterval: TimeInterval = 7 * 24 * 60 * 60
    /// How long "no match" stands.
    static let noMatchInterval: TimeInterval = 3 * 24 * 60 * 60

    /// The credit every TheSportsDB photo carries.
    static let creditLine = "Photo via TheSportsDB"

    /// RFC 3986's unreserved characters: all a query value keeps unencoded,
    /// so a space is `%20` and `&` cannot end the name early.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// `GET https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=Dejan%20Joveljic`.
    static func searchURL(name: String) -> URL? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let encoded = name.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        return URL(string: "https://\(apiHost)/api/v1/json/\(freeKey)/searchplayers.php?p=\(encoded)")
    }

    /// Whether `host` serves TheSportsDB's images (`r2.thesportsdb.com`,
    /// `www.thesportsdb.com`).
    static func isImageHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "thesportsdb.com" || host.hasSuffix(".thesportsdb.com")
    }

    /// Whether `json` is a search answer: an object with a `player` key,
    /// `null` or a list. Anything else (an error object) is no answer.
    static func isPlayerAnswer(_ json: JSON) -> Bool {
        guard let object = json.dictionary, let player = object["player"] else { return false }
        return player.isNull || player.array != nil
    }

    /// The rows of a search answer; none for `"player": null`.
    static func parsePlayers(_ json: JSON) -> [TheSportsDBPlayer] {
        json["player"].arrayValue.compactMap { row -> TheSportsDBPlayer? in
            let name = row["strPlayer"].stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            func text(_ key: String) -> String? {
                let value = row[key].stringValue.trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            return TheSportsDBPlayer(
                id: row["idPlayer"].stringValue,
                name: name,
                team: row["strTeam"].stringValue,
                sport: row["strSport"].stringValue,
                gender: row["strGender"].stringValue,
                number: text("strNumber").flatMap { Int($0) },
                cutout: text("strCutout"),
                thumb: text("strThumb"),
                render: text("strRender")
            )
        }
    }

    /// The row that is `query`'s player: soccer, of the roster's sex, at
    /// ESPN's club (`HeadshotNameMatching.teamMatches`), and by name
    /// (`HeadshotNameMatching.pick`). `nil` when none is, or several are.
    static func match(_ query: SoccerHeadshotQuery, in players: [TheSportsDBPlayer]) -> TheSportsDBPlayer? {
        let womens = HeadshotNameMatching.isWomens(query.team.league)
        let candidates = players.filter { player in
            player.sport.caseInsensitiveCompare("Soccer") == .orderedSame
                && HeadshotNameMatching.genderFits(player.gender, womens: womens)
                && HeadshotNameMatching.teamMatches(query.team, player.team)
        }
        return HeadshotNameMatching.pick(
            name: query.name,
            number: query.number,
            among: candidates,
            nameOf: { $0.name },
            numberOf: { $0.number }
        )
    }

    /// The photo `query`'s player has, if their row matches and has one.
    static func photo(for query: SoccerHeadshotQuery, in players: [TheSportsDBPlayer]) -> TheSportsDBPhoto? {
        guard let player = match(query, in: players), let url = player.imageURL else { return nil }
        return TheSportsDBPhoto(playerID: player.id, name: player.name, imageURL: url)
    }
}

// MARK: - Store

/// The TheSportsDB tier of the soccer headshot fallback: on by default
/// (Settings → Advanced → Soccer Photos), for players ESPN has no headshot
/// of.
///
/// Asked only on demand: a headshot view whose earlier tiers have no photo
/// calls `request(_:)` while it is on screen, and `withdraw(_:)` as it
/// goes, so a row scrolled past costs nothing. Requests wait in one queue
/// and go out one at a time, `TheSportsDB.requestSpacing` apart. Every
/// answer — a photo or "no match" — is kept in memory and on disk, in
/// Caches/TheSportsDB, for `TheSportsDB.photoInterval` (a photo) or
/// `noMatchInterval` (none). Nothing is asked while the setting is off.
///
/// A failed request — a timeout, a 503, an HTML error page — is not
/// cached. The player counts as having no photo here for `failureRetry`,
/// so later tiers draw; three failures in a row, a 403 or 429, or no
/// connection quiet the whole queue for `failureBackoff` (or the server's
/// `Retry-After`).
@MainActor
@Observable
final class TheSportsDBHeadshotStore {
    static let shared = TheSportsDBHeadshotStore()

    /// What is known, by `SoccerHeadshotQuery.key`.
    private(set) var records: [String: TheSportsDBRecord] = [:]

    /// Players whose last request failed, and when: no photo here until
    /// `failureRetry` has passed.
    private(set) var failures: [String: Date] = [:]

    /// The photos drawn this session, in the order first shown, for
    /// Settings → Photo Credits.
    private(set) var shownThisSession: [TheSportsDBPhoto] = []

    @ObservationIgnored private let client: HTTPClient
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let spacing: Duration
    /// Now, for an answer's age.
    @ObservationIgnored private let now: () -> Date
    /// `false` keeps the store off the network: fixture launches.
    @ObservationIgnored private let enabled: Bool
    /// The reader's setting, read at each request.
    @ObservationIgnored private let isOn: @MainActor () -> Bool

    /// Players waiting for a request, in the order asked.
    @ObservationIgnored private var queue: [SoccerHeadshotQuery] = []
    /// The player being asked about now.
    @ObservationIgnored private var inFlight: String?
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    /// When the last request went out.
    @ObservationIgnored private var lastSent: ContinuousClock.Instant?
    /// After a throttling answer or repeated failures, no request before this.
    @ObservationIgnored private var retryNotBefore: ContinuousClock.Instant?
    @ObservationIgnored private var consecutiveFailures = 0

    /// How long one player's failed request keeps them photo-less here.
    static let failureRetry: TimeInterval = 10 * 60
    /// How long the queue keeps quiet after it is throttled.
    static let failureBackoff: Duration = .seconds(5 * 60)

    /// Caches/TheSportsDB, beside Wikidata's Caches/Headshots.
    static var defaultDirectory: URL {
        SharedPaths.caches.appending(path: "TheSportsDB", directoryHint: .isDirectory)
    }

    /// A session that names the app (`WikidataHeadshots.userAgent`) and
    /// gives up after ten seconds; the answers are kept in the store's file.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": WikidataHeadshots.userAgent,
            "Accept": "application/json",
        ]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(
        client: HTTPClient = HTTPClient(transport: TheSportsDBHeadshotStore.session),
        directory: URL = TheSportsDBHeadshotStore.defaultDirectory,
        spacing: Duration = TheSportsDB.requestSpacing,
        now: @escaping () -> Date = { Date() },
        enabled: Bool = !HTTPClient.servesFixtures,
        isOn: @escaping @MainActor () -> Bool = { SoccerPhotoSettings.theSportsDBEnabled() }
    ) {
        self.client = client
        self.directory = directory
        self.spacing = spacing
        self.now = now
        self.enabled = enabled
        self.isOn = isOn
        records = Self.load(from: directory)
    }

    // MARK: Reading

    /// What TheSportsDB has said of the player: `.off` while the setting
    /// is, `.photo` or `.noPhoto` once answered, `.pending` until then. A
    /// player whose request failed lately, or a queue keeping quiet, is
    /// `.noPhoto`, so the next tier draws; so is a "no match" answer until it
    /// is stale, when it is `.pending` again to be asked again. A stale
    /// photo is still drawn while it is asked again.
    func state(for query: SoccerHeadshotQuery) -> HeadshotTierState {
        guard enabled, isOn(), query.isSoccer else { return .off }
        if let record = records[query.key] {
            if let known = record.photo { return .photo(known.imageURL) }
            if !isStale(record) { return .noPhoto }
        }
        if let failed = failures[query.key], now().timeIntervalSince(failed) < Self.failureRetry {
            return .noPhoto
        }
        return isBackingOff ? .noPhoto : .pending
    }

    /// The player's photo, once matched.
    func photo(for query: SoccerHeadshotQuery) -> TheSportsDBPhoto? {
        records[query.key]?.photo
    }

    /// Records that the player's photo was drawn, for the credits list:
    /// once per player.
    func noteShown(_ query: SoccerHeadshotQuery) {
        guard let shown = records[query.key]?.photo,
              !shownThisSession.contains(where: { $0.playerID == shown.playerID })
        else { return }
        shownThisSession.append(shown)
    }

    // MARK: Requesting

    /// Queues a search for the player, unless the setting is off, the
    /// answer is cached and fresh, or they are already queued or asked
    /// about.
    func request(_ query: SoccerHeadshotQuery) {
        guard enabled, isOn(), query.isSoccer, TheSportsDB.searchURL(name: query.name) != nil else { return }
        if let record = records[query.key], !isStale(record) { return }
        if let failed = failures[query.key], now().timeIntervalSince(failed) < Self.failureRetry { return }
        guard inFlight != query.key, !queue.contains(where: { $0.key == query.key }) else { return }
        queue.append(query)
        startQueue()
    }

    /// Drops the player from the queue, unless they are being asked about
    /// now: their view has gone.
    func withdraw(_ query: SoccerHeadshotQuery) {
        queue.removeAll { $0.key == query.key }
    }

    /// Waits for the queue to empty. For tests.
    func settle() async {
        await queueTask?.value
    }

    /// Whether a throttling answer, or repeated failures, have the queue
    /// keeping quiet.
    var isBackingOff: Bool {
        retryNotBefore.map { ContinuousClock.now < $0 } ?? false
    }

    private func isStale(_ record: TheSportsDBRecord) -> Bool {
        let interval = record.photo == nil ? TheSportsDB.noMatchInterval : TheSportsDB.photoInterval
        return now().timeIntervalSince(record.checked) >= interval
    }

    private func startQueue() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            await self?.runQueue()
            self?.queueTask = nil
        }
    }

    /// Sends the queue's searches one at a time, `spacing` apart, until it
    /// is empty, the setting goes off, or the store backs off.
    private func runQueue() async {
        while !queue.isEmpty {
            guard isOn(), !isBackingOff else {
                // Views still on screen ask again when they are drawn.
                queue = []
                return
            }
            if let lastSent, ContinuousClock.now < lastSent + spacing {
                do {
                    try await Task.sleep(until: lastSent + spacing, clock: .continuous)
                } catch {
                    return
                }
                // The queue may have changed during the wait.
                continue
            }
            let query = queue.removeFirst()
            if let record = records[query.key], !isStale(record) { continue }
            inFlight = query.key
            lastSent = ContinuousClock.now
            await lookUp(query)
            inFlight = nil
        }
    }

    /// One search: caches the photo found, or "no match"; on failure,
    /// nothing.
    private func lookUp(_ query: SoccerHeadshotQuery) async {
        guard let url = TheSportsDB.searchURL(name: query.name) else { return }
        let response = await client.fetchResponse(url)
        if case .failure(.cancelled) = response.result { return }
        // An HTML error page is `.decodeError`; an empty 200 is no answer
        // either.
        guard let json = response.result.document, TheSportsDB.isPlayerAnswer(json) else {
            fail(query, response: response)
            return
        }
        consecutiveFailures = 0
        failures[query.key] = nil
        let found = TheSportsDB.photo(for: query, in: TheSportsDB.parsePlayers(json))
        records[query.key] = TheSportsDBRecord(photo: found, checked: now())
        save()
        let outcome = found == nil ? "no match" : "a photo"
        logger.debug("TheSportsDB: \(outcome, privacy: .public) for a \(query.team.league.description, privacy: .public) player")
    }

    private func fail(_ query: SoccerHeadshotQuery, response: FetchResponse) {
        failures[query.key] = now()
        consecutiveFailures += 1
        // A 503 can be one name's alone (`Andre Luiz` on 2026-10-16, when
        // others answered): only a refusal, or no connection, quiets the
        // whole queue at once.
        var throttled = false
        switch response.result {
        case .failure(.httpError(let status)):
            throttled = status == 403 || status == 429
        case .failure(.offline):
            throttled = true
        default:
            break
        }
        if throttled || consecutiveFailures >= 3 {
            retryNotBefore = ContinuousClock.now + max(Self.failureBackoff, response.retryAfter ?? .zero)
            consecutiveFailures = 0
            logger.debug("TheSportsDB lookups failing; backing off")
        }
    }

    // MARK: Disk

    var fileURL: URL {
        directory.appending(path: "players.json", directoryHint: .notDirectory)
    }

    private static func load(from directory: URL) -> [String: TheSportsDBRecord] {
        let file = directory.appending(path: "players.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode([String: TheSportsDBRecord].self, from: data)
        else { return [:] }
        return stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write \(self.fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
