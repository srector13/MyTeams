//
//  FotMobHeadshotStore.swift
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

/// A club in FotMob's search suggestions.
struct FotMobTeam: Codable, Hashable, Sendable {
    /// FotMob's team id, e.g. `6604`.
    var id: Int
    /// e.g. `Sporting Kansas City`, `Arsenal (W)`, `Sporting Kansas City II`.
    var name: String
    /// The league FotMob files the club under, e.g. `Major League Soccer`.
    var leagueName: String?
    /// That league's FotMob id, e.g. `130`.
    var leagueID: Int?
}

/// One player in a FotMob squad.
struct FotMobMember: Codable, Hashable, Sendable {
    /// FotMob's player id: the photo's file name.
    var id: Int
    var name: String
    var shirtNumber: Int?
}

/// What the store knows of one ESPN club: its FotMob team and squad, or
/// that search found no such club.
struct FotMobTeamRecord: Codable, Hashable, Sendable {
    /// `nil` when FotMob has no club that is ESPN's.
    var team: FotMobTeam?
    /// Every player but the coach.
    var squad: [FotMobMember]
    /// When FotMob answered.
    var checked: Date
}

// MARK: - Requests and parsing

/// FotMob's unofficial, undocumented public endpoints behind the
/// experimental soccer photo tier, and the parsers and joins over their
/// answers. Pure functions: `FotMobHeadshotStore` decides when to call
/// them. Probed 2026-10-16; they ask no key, but refuse a request without
/// a User-Agent, and may change or close at any time.
///
/// A club is found by name in `search/suggest`, checked against FotMob's
/// league (`leagueIDs`) and kept away from reserve and youth sides; one
/// `teams?id=` answer then names every player in the squad, whose photos
/// are `images.fotmob.com/image_resources/playerimages/<id>.png`.
enum FotMob {
    static let apiHost = "www.fotmob.com"
    static let imageHost = "images.fotmob.com"

    /// Safari on iOS, as FotMob's own site is seen.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    /// How long a club's squad stands before it is asked for again.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// How long "no such club" stands.
    static let notFoundInterval: TimeInterval = 3 * 24 * 60 * 60
    /// The fewest seconds between two requests.
    static let requestSpacing: Duration = .seconds(1)

    /// The credit every FotMob photo carries.
    static let creditLine = "Photo via FotMob"

    /// FotMob's id of each league the app follows, as its search
    /// suggestions give it (`leagueId`), checked 2026-10-16. The Champions
    /// League has none: its clubs are filed under their own leagues.
    static let leagueIDs: [LeagueID: Int] = [
        .premierLeague: 47,
        .laLiga: 87,
        .serieA: 55,
        .bundesliga: 54,
        .ligue1: 53,
        .mls: 130,
        .ligaMX: 230,
        .wsl: 9227,
        .nwsl: 9134,
        .premiereLigue: 9677,
    ]

    /// The same leagues by FotMob's name (`leagueName`), for a suggestion
    /// that gives no id.
    static let leagueNames: [LeagueID: String] = [
        .premierLeague: "Premier League",
        .laLiga: "LaLiga",
        .serieA: "Serie A",
        .bundesliga: "Bundesliga",
        .ligue1: "Ligue 1",
        .mls: "Major League Soccer",
        .ligaMX: "Liga MX",
        .wsl: "WSL",
        .nwsl: "NWSL",
        .premiereLigue: "Premiere Ligue",
    ]

    /// RFC 3986's unreserved characters: all a query value keeps unencoded.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// `GET https://www.fotmob.com/api/data/search/suggest?term=Sporting%20Kansas%20City&lang=en`.
    static func suggestURL(term: String) -> URL? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let encoded = term.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        return URL(string: "https://\(apiHost)/api/data/search/suggest?term=\(encoded)&lang=en")
    }

    /// `GET https://www.fotmob.com/api/data/teams?id=6604&ccode3=USA`.
    static func teamURL(id: Int) -> URL? {
        URL(string: "https://\(apiHost)/api/data/teams?id=\(id)&ccode3=USA")
    }

    /// `https://images.fotmob.com/image_resources/playerimages/1284944.png`:
    /// a transparent cutout, or a 403 when FotMob has no photo.
    static func photoURL(playerID: Int) -> URL? {
        guard playerID > 0 else { return nil }
        return URL(string: "https://\(imageHost)/image_resources/playerimages/\(playerID).png")
    }

    /// The clubs among a suggest answer's groups (`[{title, suggestions}]`),
    /// each once, in the order given. Players and matches are skipped.
    static func parseTeams(_ json: JSON) -> [FotMobTeam] {
        var rows: [JSON] = []
        for group in json.arrayValue {
            if let suggestions = group["suggestions"].array {
                rows.append(contentsOf: suggestions)
            } else {
                // A flat list of suggestions, should FotMob drop the groups.
                rows.append(group)
            }
        }
        var teams: [FotMobTeam] = []
        for row in rows where row["type"].stringValue == "team" {
            let name = row["name"].stringValue.trimmingCharacters(in: .whitespaces)
            guard let id = row["id"].int, id > 0, !name.isEmpty, !teams.contains(where: { $0.id == id }) else {
                continue
            }
            let league = row["leagueName"].stringValue
            teams.append(FotMobTeam(
                id: id,
                name: name,
                leagueName: league.isEmpty ? nil : league,
                leagueID: row["leagueId"].int
            ))
        }
        return teams
    }

    /// Whether a club is a reserve or youth side: `Sporting Kansas City II`,
    /// `Arsenal U21`, `Barcelona B`, `… Reserves`.
    static func isReserveSide(_ name: String) -> Bool {
        let words = HeadshotNameMatching.words(name)
        if words.contains(where: { ["ii", "iii", "reserve", "reserves", "academy", "youth"].contains($0) }) {
            return true
        }
        if words.contains(where: { $0.wholeMatch(of: /u\d{2}/) != nil }) { return true }
        return words.count > 1 && words.last == "b"
    }

    /// Whether a club is a women's side: `Arsenal (W)`, `CF América (W)`.
    static func isWomensSide(_ name: String) -> Bool {
        HeadshotNameMatching.words(name).contains { ["w", "women", "womens", "femenil", "femenino", "feminine"].contains($0) }
    }

    /// The FotMob club that is ESPN's `team`, of `teams`.
    ///
    /// Reserve sides, and women's sides for a men's roster, are passed
    /// over. Where the league has a FotMob id, only its clubs count: the
    /// one whose name matches (`HeadshotNameMatching.teamMatches`), else
    /// — the search having found ESPN's club under another name
    /// (`Bayern München`) — the league's only club in the answer. Without
    /// one, the name alone, the same words first. `nil` when none fits or
    /// several do.
    static func pickTeam(for team: TeamRef, among teams: [FotMobTeam]) -> FotMobTeam? {
        let womens = HeadshotNameMatching.isWomens(team.league)
        let sides = teams.filter { !isReserveSide($0.name) && (womens || !isWomensSide($0.name)) }
        let named = sides.filter { HeadshotNameMatching.teamMatches(team, $0.name) }

        if let leagueID = leagueIDs[team.league] {
            let leagueName = leagueNames[team.league]
            let inLeague = sides.filter { side in
                if let id = side.leagueID { return id == leagueID }
                return side.leagueName != nil && side.leagueName == leagueName
            }
            let both = inLeague.filter { side in named.contains { $0.id == side.id } }
            if both.count == 1 { return both[0] }
            if both.count > 1 { return sameWords(as: team, among: both) }
            return inLeague.count == 1 ? inLeague[0] : nil
        }
        if named.count == 1 { return named[0] }
        return sameWords(as: team, among: named)
    }

    /// The one of `teams` whose name has the same words as ESPN's.
    private static func sameWords(as team: TeamRef, among teams: [FotMobTeam]) -> FotMobTeam? {
        let espn = Set(HeadshotNameMatching.teamWords(team.displayName))
        let same = teams.filter { Set(HeadshotNameMatching.teamWords($0.name)) == espn }
        return same.count == 1 ? same[0] : nil
    }

    /// A `teams?id=` answer's squad: every member of every group but the
    /// coach's (`squad.squad[].members[]`), and the club's `details.gender`
    /// (`male`, `female`) when given.
    static func parseSquad(_ json: JSON) -> (gender: String?, members: [FotMobMember]) {
        let groups = json["squad"]["squad"].array ?? json["squad"].arrayValue
        var members: [FotMobMember] = []
        for group in groups where group["title"].stringValue.lowercased() != "coach" {
            for member in group["members"].arrayValue {
                let name = member["name"].stringValue.trimmingCharacters(in: .whitespaces)
                guard let id = member["id"].int, id > 0, !name.isEmpty,
                      member["role"]["key"].stringValue != "coach",
                      !members.contains(where: { $0.id == id })
                else { continue }
                members.append(FotMobMember(id: id, name: name, shirtNumber: member["shirtNumber"].int))
            }
        }
        let gender = json["details"]["gender"].stringValue
        return (gender.isEmpty ? nil : gender, members)
    }

    /// The squad member who is `query`'s player (`HeadshotNameMatching.pick`),
    /// or `nil`.
    static func member(for query: SoccerHeadshotQuery, in squad: [FotMobMember]) -> FotMobMember? {
        HeadshotNameMatching.pick(
            name: query.name,
            number: query.number,
            among: squad,
            nameOf: { $0.name },
            numberOf: { $0.shirtNumber }
        )
    }
}

// MARK: - Store

/// The experimental FotMob tier of the soccer headshot fallback, tried
/// first after ESPN while the reader has it on (Settings → Advanced →
/// Soccer Photos). Off by default.
///
/// Per club, not per player: the first headshot of a club that needs a
/// fallback asks FotMob's search for the club (`request(_:)`), then its
/// squad, and every teammate is then matched from that one answer by name
/// and shirt number. Both are kept in memory and on disk under
/// Caches/FotMob for `FotMob.refreshInterval`, then asked again lazily —
/// the squad only, the club's id being known — while the old squad keeps
/// answering: at most two JSON requests a club a week. Requests go out
/// one at a time, `FotMob.requestSpacing` apart. Photos load through
/// `SoccerPhotoImageLoader`; one FotMob lacks is a 403, and the view falls
/// through to the next tier.
///
/// Nothing is asked while the setting is off. A failure is silent, cached
/// nowhere, and quiets the store for `failureBackoff` (or the server's
/// `Retry-After`).
@MainActor
@Observable
final class FotMobHeadshotStore {
    static let shared = FotMobHeadshotStore()

    /// What is known, by `TeamRef.id`.
    private(set) var records: [String: FotMobTeamRecord] = [:]

    /// The players whose photos were drawn this session, in the order
    /// first shown, for Settings → Photo Credits.
    private(set) var shownThisSession: [FotMobMember] = []

    @ObservationIgnored private let client: HTTPClient
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let spacing: Duration
    /// Now, for a record's age.
    @ObservationIgnored private let now: () -> Date
    /// `false` keeps the store off the network: fixture launches.
    @ObservationIgnored private let enabled: Bool
    /// The reader's setting, read at each request.
    @ObservationIgnored private let isOn: @MainActor () -> Bool

    /// Clubs waiting to be asked about, in the order asked.
    @ObservationIgnored private var queue: [TeamRef] = []
    /// The club being asked about now.
    @ObservationIgnored private var inFlight: String?
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var lastSent: ContinuousClock.Instant?
    /// After a failure, no request before this.
    @ObservationIgnored private var retryNotBefore: ContinuousClock.Instant?
    /// Each player's squad member, by `SoccerHeadshotQuery.key`, with the
    /// `checked` of the record it was found in: worked out once a squad.
    @ObservationIgnored private var matched: [String: (checked: Date, member: FotMobMember?)] = [:]

    /// How long the store keeps quiet after a failed request.
    static let failureBackoff: Duration = .seconds(10 * 60)

    /// Caches/FotMob, beside Wikidata's Caches/Headshots.
    static var defaultDirectory: URL {
        SharedPaths.caches.appending(path: "FotMob", directoryHint: .isDirectory)
    }

    /// A session named as Safari on iOS (`FotMob.userAgent`), with no
    /// shared cache (answers are kept in the store's files) and a short
    /// timeout.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": FotMob.userAgent,
            "Accept": "application/json",
        ]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(
        client: HTTPClient = HTTPClient(transport: FotMobHeadshotStore.session),
        directory: URL = FotMobHeadshotStore.defaultDirectory,
        spacing: Duration = FotMob.requestSpacing,
        now: @escaping () -> Date = { Date() },
        enabled: Bool = !HTTPClient.servesFixtures,
        isOn: @escaping @MainActor () -> Bool = { SoccerPhotoSettings.fotMobEnabled() }
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

    /// What FotMob has said of the player: `.off` while the setting is;
    /// `.pending` until the club has been looked up (`.noPhoto` while the
    /// store keeps quiet); then the squad member's photo, or `.noPhoto` when
    /// the club or the player is not found. A stale record answers until
    /// it is replaced.
    func state(for query: SoccerHeadshotQuery) -> HeadshotTierState {
        guard enabled, isOn(), query.isSoccer else { return .off }
        guard let record = records[query.team.id] else { return isBackingOff ? .noPhoto : .pending }
        guard let found = squadMember(for: query, in: record), let url = FotMob.photoURL(playerID: found.id) else {
            return .noPhoto
        }
        return .photo(url)
    }

    /// The player's squad member, worked out once per squad.
    private func squadMember(for query: SoccerHeadshotQuery, in record: FotMobTeamRecord) -> FotMobMember? {
        guard record.team != nil else { return nil }
        if let known = matched[query.key], known.checked == record.checked { return known.member }
        let found = FotMob.member(for: query, in: record.squad)
        matched[query.key] = (record.checked, found)
        return found
    }

    /// Records that the player's photo was drawn, for the credits list:
    /// once per player.
    func noteShown(_ query: SoccerHeadshotQuery) {
        guard let record = records[query.team.id], let found = squadMember(for: query, in: record),
              !shownThisSession.contains(where: { $0.id == found.id })
        else { return }
        shownThisSession.append(found)
    }

    // MARK: Requesting

    /// Queues a lookup of the player's club, unless the setting is off, its
    /// record is fresh, or it is already queued or being looked up.
    func request(_ query: SoccerHeadshotQuery) {
        guard enabled, isOn(), query.isSoccer, !isBackingOff else { return }
        let team = query.team
        if let record = records[team.id], !isStale(record) { return }
        guard inFlight != team.id, !queue.contains(where: { $0.id == team.id }) else { return }
        queue.append(team)
        startQueue()
    }

    /// Waits for the queue to empty. For tests.
    func settle() async {
        await queueTask?.value
    }

    /// Whether a failed request has the store keeping quiet.
    var isBackingOff: Bool {
        retryNotBefore.map { ContinuousClock.now < $0 } ?? false
    }

    private func isStale(_ record: FotMobTeamRecord) -> Bool {
        let interval = record.team == nil ? FotMob.notFoundInterval : FotMob.refreshInterval
        return now().timeIntervalSince(record.checked) >= interval
    }

    private func startQueue() {
        guard queueTask == nil else { return }
        queueTask = Task { [weak self] in
            await self?.runQueue()
            self?.queueTask = nil
        }
    }

    private func runQueue() async {
        while !queue.isEmpty {
            guard isOn(), !isBackingOff else {
                queue = []
                return
            }
            let team = queue.removeFirst()
            if let record = records[team.id], !isStale(record) { continue }
            inFlight = team.id
            await refresh(team)
            inFlight = nil
        }
    }

    /// What one JSON request came to.
    private enum Answer {
        case answered(JSON)
        /// No usable answer: the store backs off, unless it was cancelled.
        case failed
    }

    /// Asks `url`, `spacing` after the last request.
    private func ask(_ url: URL?) async -> Answer {
        guard let url else { return .failed }
        if let lastSent, ContinuousClock.now < lastSent + spacing {
            do {
                try await Task.sleep(until: lastSent + spacing, clock: .continuous)
            } catch {
                return .failed
            }
        }
        lastSent = ContinuousClock.now
        let response = await client.fetchResponse(url)
        guard let json = response.result.document else {
            backOff(response)
            return .failed
        }
        return .answered(json)
    }

    /// Finds the club (unless its id is known), then its squad, and keeps
    /// both. A failure keeps whatever was known.
    private func refresh(_ team: TeamRef) async {
        var found = records[team.id]?.team
        if found == nil {
            var terms = [team.displayName]
            if !team.shortName.isEmpty, team.shortName != team.displayName { terms.append(team.shortName) }
            var suggested: [FotMobTeam] = []
            for term in terms where suggested.isEmpty {
                guard case .answered(let json) = await ask(FotMob.suggestURL(term: term)) else { return }
                suggested = FotMob.parseTeams(json)
            }
            found = FotMob.pickTeam(for: team, among: suggested)
        }
        guard let club = found else {
            logger.notice("No FotMob club matches \(team.displayName, privacy: .public)")
            store(FotMobTeamRecord(team: nil, squad: [], checked: now()), for: team)
            return
        }
        guard case .answered(let json) = await ask(FotMob.teamURL(id: club.id)) else { return }
        let squad = FotMob.parseSquad(json)
        if let gender = squad.gender,
           !HeadshotNameMatching.genderFits(gender, womens: HeadshotNameMatching.isWomens(team.league)) {
            logger.notice("FotMob's \(club.name, privacy: .public) is not \(team.displayName, privacy: .public)'s side")
            store(FotMobTeamRecord(team: nil, squad: [], checked: now()), for: team)
            return
        }
        // An answer with no squad (FotMob's shape changed, say) keeps the
        // squad known before.
        let kept = squad.members.isEmpty ? (records[team.id]?.squad ?? []) : squad.members
        store(FotMobTeamRecord(team: club, squad: kept, checked: now()), for: team)
        logger.debug("FotMob squad for \(team.displayName, privacy: .public): \(kept.count) players")
    }

    private func store(_ record: FotMobTeamRecord, for team: TeamRef) {
        records[team.id] = record
        save()
    }

    private func backOff(_ response: FetchResponse) {
        if case .failure(.cancelled) = response.result { return }
        retryNotBefore = ContinuousClock.now + max(Self.failureBackoff, response.retryAfter ?? .zero)
        logger.debug("FotMob lookup failed; backing off")
    }

    // MARK: Disk

    var fileURL: URL {
        directory.appending(path: "teams.json", directoryHint: .notDirectory)
    }

    private static func load(from directory: URL) -> [String: FotMobTeamRecord] {
        let file = directory.appending(path: "teams.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode([String: FotMobTeamRecord].self, from: data)
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
