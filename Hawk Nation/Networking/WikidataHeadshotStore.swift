//
//  WikidataHeadshotStore.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "headshots")

// MARK: - Model

/// An athlete's photo on Wikimedia Commons, with what its licence asks the
/// app to show beside it once that is known.
///
/// Wikidata gives the item and the file; that alone is enough to draw the
/// photo. The licence and author come later from Commons, and only for a
/// photo whose credit is looked at (`WikidataHeadshotStore.requestLicenses(for:)`).
///
/// Only the photo comes from Wikidata. The athlete's name, birthday, height
/// and every other roster fact stay ESPN's.
struct CommonsPhoto: Codable, Hashable, Sendable {
    /// The athlete's Wikidata item, e.g. `Q19665907`.
    var qid: String
    /// The file's title as Wikidata's P18 gives it: already percent-encoded
    /// and without `File:`, e.g. `Shaquille%20O%27Neal%20October%202017%20%28cropped%29.jpg`.
    /// Never encode it again: a double-encoded title is a 404.
    var fileTitle: String
    /// The licence's short name, e.g. `CC BY-SA 4.0`. Empty when Commons
    /// gave none; `nil` until Commons has been asked.
    var licenseShortName: String?
    /// The photographer or rights holder, as plain text. Empty when Commons
    /// gave none; `nil` until Commons has been asked.
    var artist: String?
    /// The file's description page on Commons, where its full licence is.
    var descriptionPage: String

    /// The title as a reader sees it: `Shaquille O'Neal October 2017 (cropped).jpg`.
    var displayTitle: String { fileTitle.removingPercentEncoding ?? fileTitle }

    /// The 250 px thumbnail (`WikidataHeadshots.imageURL(fileTitle:)`).
    var imageURL: URL? { WikidataHeadshots.imageURL(fileTitle: fileTitle) }

    var descriptionPageURL: URL? { URL(string: descriptionPage) }

    /// Whether Commons has answered for the licence. The photo is drawn
    /// either way.
    var hasLicense: Bool { licenseShortName != nil }

    /// Fills in the licence Commons gave.
    mutating func apply(_ license: CommonsLicense) {
        licenseShortName = license.shortName
        artist = license.artist
    }

    /// "Photo: Bryan Berlin, CC BY-SA 4.0, via Wikimedia Commons", leaving
    /// out what Commons left out or has not yet given.
    var creditLine: String {
        let parts = [artist, licenseShortName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty
            ? "Photo via Wikimedia Commons"
            : "Photo: \(parts.joined(separator: ", ")), via Wikimedia Commons"
    }
}

/// What the store knows of one athlete: a photo, or that Wikidata has none
/// for them. A photo is never looked up again; "none" is, once it is
/// `WikidataHeadshotStore.recheckInterval` old.
struct HeadshotRecord: Codable, Hashable, Sendable {
    var photo: CommonsPhoto?
    /// When Wikidata answered.
    var checked: Date
}

/// One SPARQL result row: the athlete's item and, when it has one, its P18.
struct WikidataMatch: Hashable, Sendable {
    var qid: String
    /// Percent-encoded, as Wikidata sends it. See `CommonsPhoto.fileTitle`.
    var fileTitle: String?
}

/// A Commons file's licence details (`extmetadata`).
struct CommonsLicense: Hashable, Sendable {
    var shortName: String
    var artist: String
}

// MARK: - Queries and parsing

/// The Wikidata and Commons requests behind the headshot fallback, and the
/// parsers for their answers. Pure functions: `WikidataHeadshotStore`
/// decides when to call them.
enum WikidataHeadshots {
    /// The most ESPN ids one SPARQL query carries.
    static let batchLimit = 200

    /// The most titles one Commons `imageinfo` request carries.
    static let commonsTitleLimit = 50

    /// The thumbnail width asked of `Special:FilePath`.
    static let thumbnailWidth = 250

    /// Wikimedia asks every client to name itself and a way to reach its
    /// author (https://meta.wikimedia.org/wiki/User-Agent_policy).
    static let userAgent = "MyTeams/1.0 (iOS app; https://github.com/srector13/MyTeams)"

    static let sparqlEndpoint = "https://query.wikidata.org/sparql"
    static let commonsAPI = "https://commons.wikimedia.org/w/api.php"
    static let commonsWiki = "https://commons.wikimedia.org/wiki/"

    /// The Wikidata property holding ESPN's athlete id in `league`'s sport,
    /// or `nil` where there is none and the monogram stays.
    ///
    /// Each was checked against current ESPN rosters on 2026-10-06 (e.g.
    /// MLB 39878 Corbin Burnes → Q50345079, soccer 196176 David Raya →
    /// Q19665907). P7262 (college football) holds ESPN's legacy ids, which
    /// matched none of 200 current roster ids: it is wired, but expect
    /// almost no hits. No property covers the WNBA or college basketball.
    static func property(for league: LeagueID) -> String? {
        if league.sport == "soccer" { return "P3681" }  // ESPN FC player ID
        switch (league.sport, league.league) {
        case ("baseball", "mlb"): return "P3571"
        case ("football", "nfl"): return "P3686"
        case ("football", "college-football"): return "P7262"
        case ("basketball", "nba"): return "P3685"
        case ("hockey", "nhl"): return "P3687"
        default: return nil
        }
    }

    /// Whether `id` can be an ESPN athlete id: digits only. Roster players
    /// without one are identified by name and number (`"Name#23"`).
    static func isESPNAthleteID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isASCII) && id.allSatisfy(\.isNumber)
    }

    /// The SPARQL query matching `ids` under `property`, with each item's
    /// image (P18) where it has one.
    static func sparqlQuery(ids: [String], property: String) -> String {
        let values = ids.map { "\"\($0)\"" }.joined(separator: " ")
        return "SELECT ?espnId ?item ?image WHERE { VALUES ?espnId { \(values) } "
            + "?item wdt:\(property) ?espnId . OPTIONAL { ?item wdt:P18 ?image . } }"
    }

    /// `GET https://query.wikidata.org/sparql?query=…&format=json&maxlag=5`.
    static func sparqlURL(ids: [String], property: String) -> URL? {
        url(sparqlEndpoint, [
            ("query", sparqlQuery(ids: ids, property: property)),
            ("format", "json"),
            ("maxlag", "5"),
        ])
    }

    /// The Commons API request for `fileTitles`' licences. The titles are
    /// P18's percent-encoded ones; the API takes them decoded, as `File:…`.
    static func commonsInfoURL(fileTitles: [String]) -> URL? {
        let titles = fileTitles.map { "File:" + ($0.removingPercentEncoding ?? $0) }
        return url(commonsAPI, [
            ("action", "query"),
            ("prop", "imageinfo"),
            ("iiprop", "extmetadata"),
            ("iiextmetadatafilter", "LicenseShortName|Artist|LicenseUrl"),
            ("titles", titles.joined(separator: "|")),
            ("format", "json"),
            ("formatversion", "2"),
            ("maxlag", "5"),
        ])
    }

    /// `https://commons.wikimedia.org/wiki/Special:FilePath/<title>?width=250`,
    /// which redirects to the thumbnail on Wikimedia's CDN. `fileTitle` goes
    /// in exactly as P18 gave it, already encoded.
    static func imageURL(fileTitle: String, width: Int = thumbnailWidth) -> URL? {
        URL(string: "\(commonsWiki)Special:FilePath/\(fileTitle)?width=\(width)")
    }

    /// `https://commons.wikimedia.org/wiki/File:<title>`, `fileTitle` again
    /// as P18 gave it.
    static func descriptionPage(fileTitle: String) -> String {
        "\(commonsWiki)File:\(fileTitle)"
    }

    /// The file title in a P18 value,
    /// `http://commons.wikimedia.org/wiki/Special:FilePath/David%20Raya.jpg`
    /// → `David%20Raya.jpg`, left encoded.
    static func fileTitle(fromP18 value: String) -> String? {
        guard let range = value.range(of: "Special:FilePath/") else { return nil }
        let title = String(value[range.upperBound...])
        return title.isEmpty ? nil : title
    }

    /// The SPARQL results by ESPN id. An id with several rows (two images,
    /// say) keeps the first with an image. Ids Wikidata does not know are
    /// absent.
    static func parseMatches(_ json: JSON) -> [String: WikidataMatch] {
        var matches: [String: WikidataMatch] = [:]
        for binding in json["results"]["bindings"].arrayValue {
            let id = binding["espnId"]["value"].stringValue
            let item = binding["item"]["value"].stringValue
            guard !id.isEmpty, let qid = item.split(separator: "/").last.map({ String($0) }) else { continue }
            let title = fileTitle(fromP18: binding["image"]["value"].stringValue)
            if let existing = matches[id], existing.fileTitle != nil || title == nil { continue }
            matches[id] = WikidataMatch(qid: qid, fileTitle: title)
        }
        return matches
    }

    /// The licences in a Commons `imageinfo` answer, by the percent-encoded
    /// titles they were asked for. A title the answer lacks, or marks
    /// missing, is absent.
    static func parseLicenses(_ json: JSON, requested fileTitles: [String]) -> [String: CommonsLicense] {
        // The API may rewrite a title (underscores to spaces, a first
        // letter capitalised) and says so in `normalized`.
        var normalized: [String: String] = [:]
        for entry in json["query"]["normalized"].arrayValue {
            normalized[entry["from"].stringValue] = entry["to"].stringValue
        }
        var pages: [String: JSON] = [:]
        for page in json["query"]["pages"].arrayValue where !page["missing"].boolValue {
            pages[page["title"].stringValue] = page
        }

        var licenses: [String: CommonsLicense] = [:]
        for fileTitle in fileTitles {
            let asked = "File:" + (fileTitle.removingPercentEncoding ?? fileTitle)
            guard let page = pages[normalized[asked] ?? asked] else { continue }
            let metadata = page["imageinfo"][0]["extmetadata"]
            licenses[fileTitle] = CommonsLicense(
                shortName: plainText(metadata["LicenseShortName"]["value"].stringValue),
                artist: plainText(metadata["Artist"]["value"].stringValue)
            )
        }
        return licenses
    }

    /// Commons's `Artist` is HTML (`<a href="…">Bryan Berlin</a>`): its text,
    /// entities decoded and whitespace collapsed, cut to a credit line's
    /// length.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(119)) + "…" : collapsed
    }

    /// RFC 3986's unreserved characters: all a query value keeps unencoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// `base` with `items` as its query, every character but the unreserved
    /// ones percent-encoded. `URLComponents` would leave `+`, `?` and `|`
    /// as they are, and a file title may hold `&` or `+`.
    private static func url(_ base: String, _ items: [(String, String)]) -> URL? {
        let allowed = unreserved
        let query = items.compactMap { name, value -> String? in
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return "\(name)=\(encoded)"
        }
        guard query.count == items.count else { return nil }
        return URL(string: "\(base)?\(query.joined(separator: "&"))")
    }
}

// MARK: - Store

/// Finds Commons photos for athletes whose ESPN headshot is missing, and
/// remembers the answer for good.
///
/// A team page hands the store its whole roster as soon as the feed lands
/// (`prefetch(espnIDs:league:)`), and the uncached ids go out at once as
/// one SPARQL query per sport — up to `WikidataHeadshots.batchLimit` ids —
/// with no debounce. Screens without a roster feed (game sheets, news) fall
/// back on `request(espnID:league:)`, which a headshot view calls once its
/// ESPN image has failed (or the feed had none) and the row is on screen;
/// requests made within `debounce` of each other share a query.
///
/// The query gives each athlete's item and file title, which is all a
/// photo needs to be drawn. Its licence and author are fetched from Commons
/// only when someone looks at its credit — a long-press, or Settings →
/// Photo Credits (`requestLicenses(for:)`) — one request per 50 photos, and
/// merged into the cached entry.
///
/// Every answer is cached on disk by ESPN athlete id, one file per
/// Wikidata property under Caches/Headshots: a photo, with its attribution
/// once known, or "no photo". A cached photo is never asked about again; a
/// "no photo" 30 days old is, in the same batches, since Commons may have
/// one by then. Any failure is silent: nothing is cached, the view keeps its monogram
/// (or a photo its generic credit), and the store waits a minute (or the
/// server's `Retry-After`) before asking again.
@MainActor
@Observable
final class WikidataHeadshotStore {
    static let shared = WikidataHeadshotStore()

    /// What has been resolved, by property and then ESPN id.
    private(set) var records: [String: [String: HeadshotRecord]] = [:]

    /// The Commons photos drawn this session, in the order first shown,
    /// for Settings → Photo Credits.
    private(set) var shownThisSession: [CommonsPhoto] = []

    @ObservationIgnored private let client: HTTPClient
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let debounce: Duration
    /// Now, for a "no photo" answer's age.
    @ObservationIgnored private let now: () -> Date
    /// `false` keeps the store off the network: fixture launches.
    @ObservationIgnored private let enabled: Bool

    /// Ids waiting for the next batch, by property, in request order.
    @ObservationIgnored private var pending: [String: [String]] = [:]
    /// Ids in a query now.
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    /// Whether a roster prefetch is pending: the next batch goes out at
    /// once, without waiting out the debounce.
    @ObservationIgnored private var sendsNow = false
    /// The licences fetched this launch, by percent-encoded file title, so a
    /// photo resolved after its licence still gets it.
    @ObservationIgnored private var licenses: [String: CommonsLicense] = [:]
    /// Titles whose licence is being fetched.
    @ObservationIgnored private var licensesInFlight: Set<String> = []
    /// The latest licence fetch, which waits on the one before it.
    @ObservationIgnored private var licenseTask: Task<Void, Never>?
    /// When the debounce ends: pushed back by each new request.
    @ObservationIgnored private var deadline = ContinuousClock.now
    /// When the oldest pending request was made: a batch goes out at most
    /// `maxWait` after it, however steadily the reader scrolls.
    @ObservationIgnored private var oldestPending: ContinuousClock.Instant?
    /// After a failure, no query before this.
    @ObservationIgnored private var retryNotBefore: ContinuousClock.Instant?

    /// How long a render-time request waits for others to share its query.
    nonisolated static let defaultDebounce: Duration = .milliseconds(300)
    /// The longest a request waits on a reader who keeps scrolling.
    static let maxWait: Duration = .seconds(2)
    /// How long the store keeps quiet after a failed query.
    static let failureBackoff: Duration = .seconds(60)
    /// How long a "no photo" answer stands before the athlete is asked
    /// about again.
    static let recheckInterval: TimeInterval = 30 * 24 * 60 * 60

    /// The store's own directory: Caches/Headshots, beside LogoStore's crests.
    static var defaultDirectory: URL {
        SharedPaths.caches.appending(path: "Headshots", directoryHint: .isDirectory)
    }

    /// A session that names the app to Wikimedia (`WikidataHeadshots.userAgent`)
    /// and gives up after five seconds: a fallback photo is never worth a wait.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": WikidataHeadshots.userAgent,
            "Api-User-Agent": WikidataHeadshots.userAgent,
            "Accept": "application/sparql-results+json, application/json",
        ]
        // The answers are cached in the store's own files.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(
        client: HTTPClient = HTTPClient(transport: WikidataHeadshotStore.session),
        directory: URL = WikidataHeadshotStore.defaultDirectory,
        debounce: Duration = WikidataHeadshotStore.defaultDebounce,
        now: @escaping () -> Date = { Date() },
        enabled: Bool = !HTTPClient.servesFixtures
    ) {
        self.client = client
        self.directory = directory
        self.debounce = debounce
        self.now = now
        self.enabled = enabled
        // Read every cached answer now, so no view's body reads the disk or
        // changes `records` while SwiftUI is drawing.
        records = Self.load(from: directory)
    }

    // MARK: Reading

    /// What is known of the athlete: `nil` until Wikidata has answered for
    /// them, then a record with or without a photo.
    func record(espnID: String, league: LeagueID) -> HeadshotRecord? {
        guard let property = WikidataHeadshots.property(for: league) else { return nil }
        return records[property]?[espnID]
    }

    /// The athlete's Commons photo, once one is known.
    func photo(espnID: String, league: LeagueID) -> CommonsPhoto? {
        record(espnID: espnID, league: league)?.photo
    }

    /// Whether a later tier may stand in for Wikidata on the athlete: it has
    /// answered with no photo, or it is not answering — backing off after a
    /// failure, or still silent once the view has `waited` (`maxWait`).
    func lacksPhoto(espnID: String, league: LeagueID, waited: Bool) -> Bool {
        if let record = record(espnID: espnID, league: league) { return record.photo == nil }
        return waited || isBackingOff
    }

    // MARK: Requesting

    /// Asks for the athlete's photo in the next batch, after the debounce,
    /// unless the answer is cached (and not a stale "no photo"), already asked for, or the sport has no
    /// Wikidata property. For a headshot drawn without its roster.
    func request(espnID: String, league: LeagueID) {
        guard enqueue(espnID, league: league) else { return }
        deadline = ContinuousClock.now + debounce
        startBatches()
    }

    /// Asks at once, in one query, about every athlete on a roster that has
    /// just loaded, so their photos are known before their cards are drawn.
    /// Cached and unusable ids are skipped; a roster wholly cached asks
    /// nothing.
    func prefetch(espnIDs: [String], league: LeagueID) {
        var added = false
        for id in espnIDs where enqueue(id, league: league) {
            added = true
        }
        guard added else { return }
        sendsNow = true
        startBatches()
    }

    /// Adds `espnID` to the pending batch. `false` when it is not to be
    /// asked about.
    private func enqueue(_ espnID: String, league: LeagueID) -> Bool {
        guard enabled,
              WikidataHeadshots.isESPNAthleteID(espnID),
              let property = WikidataHeadshots.property(for: league)
        else { return false }
        let key = Self.key(property, espnID)
        guard records[property]?[espnID].map(isStale) ?? true,
              !inFlight.contains(key),
              !(pending[property]?.contains(espnID) ?? false)
        else { return false }

        pending[property, default: []].append(espnID)
        if oldestPending == nil { oldestPending = ContinuousClock.now }
        return true
    }

    /// Whether `record` is a "no photo" old enough to ask about again. A
    /// photo never is.
    private func isStale(_ record: HeadshotRecord) -> Bool {
        record.photo == nil && now().timeIntervalSince(record.checked) >= Self.recheckInterval
    }

    private func startBatches() {
        guard batchTask == nil else { return }
        batchTask = Task { [weak self] in
            await self?.runBatches()
            self?.batchTask = nil
        }
    }

    /// Waits for the batch and licence fetch in progress, if any. For tests.
    func settle() async {
        await batchTask?.value
        await licenseTask?.value
    }

    /// Records that `photo` was drawn, for the credits list: once per file,
    /// with its licence when it is known.
    func noteShown(_ photo: CommonsPhoto) {
        guard !shownThisSession.contains(where: { $0.fileTitle == photo.fileTitle }) else { return }
        var photo = photo
        if !photo.hasLicense, let license = licenses[photo.fileTitle] {
            photo.apply(license)
        }
        shownThisSession.append(photo)
    }

    // MARK: Licences

    /// Fetches, in the background, the licences of those of `photos` whose
    /// credit is not yet known, and merges them into their cached entries
    /// and the credits list. Called only where a credit is shown: a
    /// long-pressed photo, and Settings → Photo Credits. Silent on failure:
    /// the credit stays "Photo via Wikimedia Commons" until asked again.
    func requestLicenses(for photos: [CommonsPhoto]) {
        guard enabled, !isBackingOff else { return }
        var titles: [String] = []
        for photo in photos where !photo.hasLicense {
            let title = photo.fileTitle
            if let license = licenses[title] {
                merge([title: license])
            } else if !licensesInFlight.contains(title), !titles.contains(title) {
                titles.append(title)
            }
        }
        guard !titles.isEmpty else { return }
        licensesInFlight.formUnion(titles)
        let previous = licenseTask
        licenseTask = Task { [weak self] in
            await previous?.value
            await self?.fetchLicenses(titles)
        }
    }

    /// One Commons request per `WikidataHeadshots.commonsTitleLimit` titles.
    /// A failure drops the rest; they are asked for again on the next look.
    private func fetchLicenses(_ titles: [String]) async {
        defer { licensesInFlight.subtract(titles) }
        for start in stride(from: 0, to: titles.count, by: WikidataHeadshots.commonsTitleLimit) {
            guard !isBackingOff else { return }
            let chunk = Array(titles[start..<min(start + WikidataHeadshots.commonsTitleLimit, titles.count)])
            guard let url = WikidataHeadshots.commonsInfoURL(fileTitles: chunk) else { continue }
            let info = await client.fetchResponse(url)
            // A maxlag answer is a 200 carrying `error`.
            guard let json = info.result.document, json["error"].isNull else {
                backOff(info)
                return
            }
            merge(WikidataHeadshots.parseLicenses(json, requested: chunk))
        }
    }

    /// Writes `fetched` into every cached photo of those files, on disk,
    /// and into the credits list.
    private func merge(_ fetched: [String: CommonsLicense]) {
        guard !fetched.isEmpty else { return }
        licenses.merge(fetched) { _, new in new }
        for property in records.keys.sorted() {
            guard var resolved = records[property] else { continue }
            var changed = false
            for (id, record) in resolved {
                guard var photo = record.photo, !photo.hasLicense,
                      let license = fetched[photo.fileTitle]
                else { continue }
                photo.apply(license)
                resolved[id]?.photo = photo
                changed = true
            }
            if changed {
                records[property] = resolved
                save(property)
            }
        }
        if shownThisSession.contains(where: { !$0.hasLicense && fetched[$0.fileTitle] != nil }) {
            shownThisSession = shownThisSession.map { photo in
                guard !photo.hasLicense, let license = fetched[photo.fileTitle] else { return photo }
                var photo = photo
                photo.apply(license)
                return photo
            }
        }
    }

    /// Sends batches until nothing is pending: each after the debounce, or
    /// `maxWait` after its oldest request, or at once for a roster prefetch.
    private func runBatches() async {
        while !pending.isEmpty {
            let due = sendsNow
                ? ContinuousClock.now
                : min(deadline, (oldestPending ?? deadline) + Self.maxWait)
            if ContinuousClock.now < due {
                do {
                    try await Task.sleep(until: due, clock: .continuous)
                } catch {
                    return
                }
                // A request during the sleep moved the deadline.
                continue
            }
            oldestPending = nil
            sendsNow = false
            let batches = pending
            pending = [:]
            for (property, ids) in batches.sorted(by: { $0.key < $1.key }) {
                for start in stride(from: 0, to: ids.count, by: WikidataHeadshots.batchLimit) {
                    // Backing off: drop the rest, and whatever came in
                    // meanwhile. Rows that come back on screen ask again.
                    guard !isBackingOff else {
                        pending = [:]
                        oldestPending = nil
                        sendsNow = false
                        return
                    }
                    let chunk = Array(ids[start..<min(start + WikidataHeadshots.batchLimit, ids.count)])
                    await resolve(chunk, property: property)
                }
            }
        }
    }

    /// One SPARQL query: item and file title only, so a photo found is
    /// drawable at once; its licence waits for `requestLicenses(for:)`.
    /// Caches every id in `ids` on success; nothing on failure.
    private func resolve(_ ids: [String], property: String) async {
        let keys = ids.map { Self.key(property, $0) }
        inFlight.formUnion(keys)
        defer { inFlight.subtract(keys) }

        guard let url = WikidataHeadshots.sparqlURL(ids: ids, property: property) else { return }
        let response = await client.fetchResponse(url)
        guard let document = response.result.document else {
            backOff(response)
            return
        }
        let matches = WikidataHeadshots.parseMatches(document)

        let checked = now()
        var resolved = records[property] ?? [:]
        for id in ids {
            var photo: CommonsPhoto?
            if let match = matches[id], let title = match.fileTitle {
                var found = CommonsPhoto(
                    qid: match.qid,
                    fileTitle: title,
                    licenseShortName: nil,
                    artist: nil,
                    descriptionPage: WikidataHeadshots.descriptionPage(fileTitle: title)
                )
                if let license = licenses[title] { found.apply(license) }
                photo = found
            }
            resolved[id] = HeadshotRecord(photo: photo, checked: checked)
        }
        records[property] = resolved
        save(property)
        logger.debug("Resolved \(ids.count) \(property) ids, \(matches.count) on Wikidata")
    }

    /// Whether a failed query has the store keeping quiet.
    var isBackingOff: Bool {
        retryNotBefore.map { ContinuousClock.now < $0 } ?? false
    }

    private func backOff(_ response: FetchResponse) {
        if case .failure(.cancelled) = response.result { return }
        retryNotBefore = ContinuousClock.now + max(Self.failureBackoff, response.retryAfter ?? .zero)
        logger.debug("Headshot lookup failed; backing off")
    }

    private static func key(_ property: String, _ id: String) -> String {
        "\(property)/\(id)"
    }

    // MARK: Disk

    func fileURL(for property: String) -> URL {
        directory.appending(path: "\(property).json", directoryHint: .notDirectory)
    }

    /// Every `<property>.json` in `directory`, by property.
    private static func load(from directory: URL) -> [String: [String: HeadshotRecord]] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var records: [String: [String: HeadshotRecord]] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let stored = try? JSONDecoder().decode([String: HeadshotRecord].self, from: data)
            else { continue }
            records[file.deletingPathExtension().lastPathComponent] = stored
        }
        return records
    }

    private func save(_ property: String) {
        guard let data = try? JSONEncoder().encode(records[property] ?? [:]) else { return }
        let file = fileURL(for: property)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.error("Could not write \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

// MARK: - Images

/// Loads Commons thumbnails with the app's User-Agent, keeping them decoded
/// in memory and on disk in a URL cache that revalidates with the CDN's
/// ETag. A thumbnail asked for again while it is downloading — the same
/// athlete on a card and in its sheet, say — waits on that one download
/// rather than starting another. Every failure is `nil`.
actor CommonsImageLoader {
    static let shared = CommonsImageLoader()

    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": WikidataHeadshots.userAgent]
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

    /// Downloads in progress, by URL. Every caller of a URL in here awaits
    /// the same task.
    private var loads: [URL: Task<UIImage?, Never>] = [:]

    init(
        transport: any HTTPTransport = CommonsImageLoader.session,
        enabled: Bool = !HTTPClient.servesFixtures
    ) {
        self.transport = transport
        self.enabled = enabled
    }

    func image(for url: URL) async -> UIImage? {
        guard enabled else { return nil }
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        // Already downloading: share it.
        if let existing = loads[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [transport] in
            do {
                let (data, response) = try await transport.load(url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                return UIImage(data: data)
            } catch {
                logger.debug("Commons image failed: \(error.localizedDescription)")
                return nil
            }
        }
        loads[url] = task
        let image = await task.value
        // Cached before the entry goes, so no caller in between misses both.
        if let image { memory.setObject(image, forKey: url as NSURL) }
        loads[url] = nil
        return image
    }
}
