//
//  TeamRef.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - League identity

/// An ESPN league, named by the two path components its site-API URLs use:
/// `football/nfl`, `basketball/mens-college-basketball`, `baseball/mlb`,
/// `soccer/usa.1`.
///
/// Every ESPN URL the app builds for a league goes through here, so a new
/// league needs no new URL code. Encodes as its path string.
struct LeagueID: Hashable, Sendable, CustomStringConvertible {
    /// The sport component, e.g. `football`.
    let sport: String
    /// The league component, e.g. `nfl` or `usa.1`.
    let league: String

    init(sport: String, league: String) {
        self.sport = sport
        self.league = league
    }

    /// Reads a path such as `"football/nfl"`. Returns `nil` unless it has
    /// exactly two non-empty components.
    init?(path: String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        self.init(sport: String(components[0]), league: String(components[1]))
    }

    /// The path ESPN URLs embed, e.g. `football/nfl`.
    var path: String { "\(sport)/\(league)" }

    var description: String { path }

    /// The behaviour that differs by league. See `LeagueDescriptor`.
    var descriptor: LeagueDescriptor { LeagueDescriptor.descriptor(for: self) }

    static let mensCollegeBasketball = LeagueID(sport: "basketball", league: "mens-college-basketball")
    static let nfl = LeagueID(sport: "football", league: "nfl")
    static let mlb = LeagueID(sport: "baseball", league: "mlb")
    static let mls = LeagueID(sport: "soccer", league: "usa.1")

    /// Whether the league is a college one. Unknown leagues are judged by
    /// their path (`college-football`, `womens-college-basketball`).
    var isCollege: Bool { descriptor.isCollege || league.contains("college") }

    // MARK: URLs

    private static let siteAPI = "https://site.api.espn.com/apis/site/v2/sports"
    private static let commonAPI = "https://site.web.api.espn.com/apis/common/v3/sports"

    /// Every team in the league. The default page is short, so ask for more
    /// than any league has; college leagues also name the all-divisions group
    /// (`groups=50`), which returns all 762 college-football teams in one call.
    var teamsURL: String {
        "\(Self.siteAPI)/\(path)/teams?limit=1000" + (isCollege ? "&groups=50" : "")
    }

    /// A team's season schedule.
    func scheduleURL(teamID: String) -> String {
        "\(Self.siteAPI)/\(path)/teams/\(teamID)/schedule"
    }

    /// A team's current roster.
    func rosterURL(teamID: String) -> String {
        "\(Self.siteAPI)/\(path)/teams/\(teamID)/roster"
    }

    /// A team's news feed, newest first.
    func newsURL(teamID: String) -> String {
        "\(Self.siteAPI)/\(path)/news?team=\(teamID)&limit=25"
    }

    /// One game's summary: header, box score, venue.
    func summaryURL(gameID: String) -> String {
        "\(Self.siteAPI)/\(path)/summary?event=\(gameID)"
    }

    /// An athlete's profile, including the headline stats summary.
    func athleteURL(athleteID: String) -> String {
        "\(Self.commonAPI)/\(path)/athletes/\(athleteID)"
    }

    /// An athlete's season splits.
    func athleteSplitsURL(athleteID: String) -> String {
        "\(athleteURL(athleteID: athleteID))/splits"
    }
}

extension LeagueID: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        guard let id = LeagueID(path: path) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "League path \"\(path)\" is not of the form sport/league"
            )
        }
        self = id
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

// MARK: - Team identity

/// One team the app can follow, identified by its league and ESPN team id.
///
/// This replaces the closed `Team` enum. Feeds are matched on `espnID` —
/// every competitor node ESPN publishes carries `team.id` — so no per-team
/// name strings are needed to tell the followed team from its opponent.
struct TeamRef: Codable, Identifiable, Hashable, Sendable {
    let league: LeagueID
    /// The team's id in ESPN's site API, e.g. `"2305"`.
    let espnID: String

    /// The full name shown in the header and the sticky title bar.
    var displayName: String
    /// The short name shown beside the crest on the selected tab.
    var shortName: String
    var abbreviation: String
    var location: String

    /// The brand colour as a six-digit hex string, e.g. `"0051BA"` — the form
    /// ESPN uses in its feeds.
    var colorHex: String
    var alternateColorHex: String

    var logoURL: URL?
    var logoDarkURL: URL?

    /// The bundled crest's asset name, for the seed teams only; teams loaded
    /// from ESPN have none. Only the app bundles these imagesets now: views
    /// draw crests through `TeamLogo`, which falls back to this asset, and
    /// `LogoStore.seedBundledCrestsIfNeeded` copies them to disk for the
    /// widget.
    var logoAsset: String?

    /// The stable key for persistence and widgets: `"<leaguePath>:<espnID>"`,
    /// e.g. `"football/nfl:12"`.
    var id: String { Self.id(league: league, espnID: espnID) }

    static func id(league: LeagueID, espnID: String) -> String {
        "\(league.path):\(espnID)"
    }

    // MARK: Display

    /// The team's colour for SwiftUI views.
    var color: Color { Color(hexString: colorHex) }

    /// The label for one of this team's game periods. See
    /// `LeagueDescriptor.periodName`.
    func periodName(_ period: String) -> String {
        league.descriptor.periodName(period)
    }

    // MARK: URLs

    var scheduleURL: String { league.scheduleURL(teamID: espnID) }

    var rosterURL: String { league.rosterURL(teamID: espnID) }

    var newsURL: String { league.newsURL(teamID: espnID) }

    func summaryURL(gameID: String) -> String {
        league.summaryURL(gameID: gameID)
    }
}

// MARK: - Catalog

/// The teams the app knows about, read from the bundled `teams.json`.
///
/// A static seed of the four teams the app has always followed. Loading
/// catalogs from ESPN is Phase 2; the file's `teams` key leaves room for that
/// without a format change.
enum TeamCatalog {
    /// Every catalogued team, in the file's order.
    ///
    /// The file ships in the app and widget bundles; one that is missing or
    /// malformed is a packaging error, so it traps rather than launching with
    /// no teams.
    static let all: [TeamRef] = {
        do {
            return try load()
        } catch {
            fatalError("The bundled teams.json could not be read: \(error)")
        }
    }()

    /// The team with the given `TeamRef.id`, if catalogued.
    static func team(id: TeamRef.ID) -> TeamRef? {
        all.first { $0.id == id }
    }

    /// The team with the given ESPN id in `league`, if catalogued.
    static func team(league: LeagueID, espnID: String) -> TeamRef? {
        team(id: TeamRef.id(league: league, espnID: espnID))
    }

    /// A team the app ships with. Traps if the catalog lacks it, which only a
    /// broken build can cause.
    static func seeded(league: LeagueID, espnID: String) -> TeamRef {
        guard let team = team(league: league, espnID: espnID) else {
            fatalError("teams.json has no \(TeamRef.id(league: league, espnID: espnID))")
        }
        return team
    }

    // MARK: Legacy migration

    /// The raw values of the retired `Team` enum, mapped to the teams they
    /// named. Kept only to migrate anything persisted under the old
    /// identifiers (`"jayhawk"` was also the crest's asset name).
    static let legacyTeamIDs: [String: TeamRef.ID] = [
        "jayhawk": TeamRef.id(league: .mensCollegeBasketball, espnID: "2305"),
        "chiefs": TeamRef.id(league: .nfl, espnID: "12"),
        "royals": TeamRef.id(league: .mlb, espnID: "7"),
        "sporting": TeamRef.id(league: .mls, espnID: "186"),
    ]

    /// The team a retired `Team` raw value named, if any.
    static func team(legacyID: String) -> TeamRef? {
        legacyTeamIDs[legacyID].flatMap(team(id:))
    }

    // MARK: Loading

    private struct File: Decodable {
        var teams: [TeamRef]
    }

    /// Anchors `Bundle(for:)` to whichever bundle carries this code — the app
    /// or the widget extension.
    private final class BundleToken {}

    /// Reads `teams.json` from `bundle`, by default the one carrying this code.
    static func load(from bundle: Bundle? = nil) throws -> [TeamRef] {
        let bundle = bundle ?? Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "teams", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [TeamRef] {
        try JSONDecoder().decode(File.self, from: data).teams
    }
}

// MARK: - Favorites

/// The four teams the app followed before favorites were editable.
///
/// Now only the seed: `FavoritesCodec.loadOrSeed` writes them as the first
/// favorites of an install that has none, and the widget falls back to them.
/// The live, user-edited list is `FavoritesStore` in the app and
/// `SharedPaths.favoriteTeamIDs()` in the widget.
enum FavoriteTeams {
    /// The seed teams, in their original tab order.
    static var teams: [TeamRef] { TeamCatalog.all }

    /// The seed teams' `TeamRef.id`s, in order.
    static var seedIDs: [TeamRef.ID] { teams.map(\.id) }

    /// Turns stored identifiers into teams, in order, dropping unknown and
    /// repeated ones. Accepts both `TeamRef.id` values and the retired `Team`
    /// raw values (`"jayhawk"`, `"chiefs"`, `"royals"`, `"sporting"`).
    static func resolve(storedIDs: [String]) -> [TeamRef] {
        var seen: Set<TeamRef.ID> = []
        return storedIDs.compactMap { stored in
            guard let team = TeamCatalog.team(id: stored) ?? TeamCatalog.team(legacyID: stored),
                  seen.insert(team.id).inserted
            else { return nil }
            return team
        }
    }
}

/// One followed team, as persisted. The array's order is the display order.
///
/// Holds only the id: names, colours and crests are resolved through
/// `RemoteTeamCatalog.team(id:)`, whose disk cache and bundled seed keep that
/// working offline.
struct FavoriteTeam: Codable, Identifiable, Equatable, Sendable {
    /// A `TeamRef.id`, `"<leaguePath>:<espnID>"`.
    let teamID: String
    var addedAt: Date
    /// Whether game alerts are wanted for the team. Nothing reads it yet.
    var notify: Bool

    var id: String { teamID }

    init(teamID: String, addedAt: Date = Date(), notify: Bool = true) {
        self.teamID = teamID
        self.addedAt = addedAt
        self.notify = notify
    }
}

/// The iCloud side of the favorites mirror. `NSUbiquitousKeyValueStore`
/// conforms as is; tests substitute an in-memory store.
protocol FavoritesCloudStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension NSUbiquitousKeyValueStore: FavoritesCloudStore {}

/// Reads and writes the favorites list, with no UI or WidgetKit in the way.
///
/// The list is JSON `[FavoriteTeam]` under `key` in the App Group's
/// `UserDefaults`, which the widget reads directly, and the same bytes are
/// mirrored to iCloud key-value storage for other devices.
enum FavoritesCodec {
    /// The favorites JSON, in the shared defaults and in iCloud.
    static let key = "favorites.v1"
    /// Set once the favorites have been seeded or restored, so the seed never
    /// runs twice.
    static let seededKey = "favorites.v1.seeded"

    /// Where the favorites a load returned came from.
    enum Source: Equatable, Sendable {
        /// The shared defaults already held them.
        case local
        /// The shared defaults had none; iCloud did.
        case restoredFromCloud
        /// Neither store had any and the seed had not run: the seed teams.
        case seeded
        /// The seed has run before but no list is stored. Empty.
        case empty
    }

    static func encode(_ favorites: [FavoriteTeam]) -> Data? {
        try? encoder.encode(favorites)
    }

    /// `nil` for missing or unreadable data.
    static func decode(_ data: Data?) -> [FavoriteTeam]? {
        guard let data else { return nil }
        return try? decoder.decode([FavoriteTeam].self, from: data)
    }

    /// The stored favorites' ids, in order, or `nil` when none are stored.
    static func storedIDs(in defaults: UserDefaults) -> [TeamRef.ID]? {
        decode(defaults.data(forKey: key))?.map(\.teamID)
    }

    /// Loads the favorites, restoring or seeding them the first time.
    ///
    /// In order: the list in `defaults`, even an empty one; else the iCloud
    /// copy, written back to `defaults`; else, unless `seededKey` is set, the
    /// `seedIDs`, written to both stores. Seeding and restoring set
    /// `seededKey`; nothing here overwrites a stored list.
    static func loadOrSeed(
        defaults: UserDefaults,
        cloud: (any FavoritesCloudStore)?,
        seedIDs: [TeamRef.ID],
        now: Date = Date()
    ) -> (favorites: [FavoriteTeam], source: Source) {
        if let local = decode(defaults.data(forKey: key)) {
            return (local, .local)
        }
        if let data = cloud?.data(forKey: key), let restored = decode(data) {
            defaults.set(data, forKey: key)
            defaults.set(true, forKey: seededKey)
            return (restored, .restoredFromCloud)
        }
        guard !defaults.bool(forKey: seededKey) else {
            return ([], .empty)
        }
        let seeded = seedIDs.map { FavoriteTeam(teamID: $0, addedAt: now) }
        save(seeded, defaults: defaults, cloud: cloud)
        defaults.set(true, forKey: seededKey)
        return (seeded, .seeded)
    }

    /// Writes the list to `defaults` and mirrors the same JSON to `cloud`.
    static func save(_ favorites: [FavoriteTeam], defaults: UserDefaults, cloud: (any FavoritesCloudStore)?) {
        guard let data = encode(favorites) else { return }
        defaults.set(data, forKey: key)
        cloud?.set(data, forKey: key)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
