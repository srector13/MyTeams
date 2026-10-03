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
    static let nba = LeagueID(sport: "basketball", league: "nba")
    static let wnba = LeagueID(sport: "basketball", league: "wnba")
    static let womensCollegeBasketball = LeagueID(sport: "basketball", league: "womens-college-basketball")
    static let nhl = LeagueID(sport: "hockey", league: "nhl")
    static let collegeFootball = LeagueID(sport: "football", league: "college-football")
    static let premierLeague = LeagueID(sport: "soccer", league: "eng.1")
    static let laLiga = LeagueID(sport: "soccer", league: "esp.1")
    static let ligaMX = LeagueID(sport: "soccer", league: "mex.1")
    static let nwsl = LeagueID(sport: "soccer", league: "usa.nwsl")

    /// A soccer competition by its ESPN slug, such as a cup a league's teams
    /// also play in (`LeagueDescriptor.cupCompetitions`): `"eng.fa"`,
    /// `"uefa.champions"`.
    static func soccer(_ slug: String) -> LeagueID {
        LeagueID(sport: "soccer", league: slug)
    }

    /// Every league with its own `LeagueDescriptor`, in registry order. Any
    /// other league still works, with a descriptor derived from its path.
    static let knownLeagues: [LeagueID] = [
        .mensCollegeBasketball, .nfl, .mlb, .mls,
        .nba, .wnba, .womensCollegeBasketball, .nhl, .collegeFootball,
        .premierLeague, .laLiga, .ligaMX, .nwsl,
    ]

    /// Whether the league is a college one. Unknown leagues are judged by
    /// their path (`college-football`, `womens-college-basketball`).
    var isCollege: Bool { descriptor.isCollege || league.contains("college") }

    // MARK: URLs

    private static let siteAPI = "https://site.api.espn.com/apis/site/v2/sports"
    /// Standings are served without the `/site` segment; the site-API
    /// standings path answers with an empty stub.
    private static let standingsAPI = "https://site.api.espn.com/apis/v2/sports"
    private static let commonAPI = "https://site.web.api.espn.com/apis/common/v3/sports"
    /// Stat leaders are served by the v3 site API; the v2 path is a 404.
    private static let siteAPIv3 = "https://site.api.espn.com/apis/site/v3/sports"

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

    /// Every game in the league on one day, `YYYYMMDD` as
    /// `scoreboardDay(for:)` forms it. One request answers for every team in
    /// the league (see `LeagueScoreboardCenter`).
    ///
    /// College basketball's scoreboard lists only featured games unless it is
    /// asked for all of Division I (`groups=50`); college football's default
    /// is FBS, which `groups=50` would narrow instead, so it is left alone.
    func scoreboardURL(day: String) -> String {
        let divisionI = isCollege && sport == "basketball" ? "&groups=50&limit=1000" : ""
        return "\(Self.siteAPI)/\(path)/scoreboard?dates=\(day)" + divisionI
    }

    /// The league's standings: a tree whose root is the league, with the
    /// tables in its `children` (conferences, divisions, or one child holding
    /// a soccer league's whole table). See FIXTURES.md, "Standings".
    ///
    /// College leagues name their division (`standingsGroup`). `season` is
    /// the year ESPN files the season under — the ending year for the NBA,
    /// NHL and college basketball (2027 is 2026-27), the starting year for
    /// football and soccer; `nil` asks for the current season.
    func standingsURL(season: Int? = nil) -> String {
        var query: [String] = []
        if let group = descriptor.standingsGroup { query.append("group=\(group)") }
        if let season { query.append("season=\(season)") }
        let url = "\(Self.standingsAPI)/\(path)/standings"
        return query.isEmpty ? url : url + "?" + query.joined(separator: "&")
    }

    /// The league's polls — for college leagues, the AP Top 25 and the
    /// coaches' poll — each a ranked list of teams with their records. The
    /// standings fall back to these when a college tree has no table yet.
    /// See `downloadStandings`.
    var rankingsURL: String {
        "\(Self.siteAPI)/\(path)/rankings"
    }

    /// The league's statistical leaders, `limit` players deep in each
    /// category — or, given `teamID`, that team's own. See FIXTURES.md,
    /// "Stat leaders".
    ///
    /// `season` is named only for a league with a `leadersSeasonType`
    /// (soccer), together with that type; `leadersSeason(at:)` gives it.
    /// Every other league's feed answers with its latest regular season —
    /// in an NBA preseason, the one just finished.
    func leadersURL(teamID: String? = nil, season: Int? = nil, limit: Int = 10) -> String {
        var query = ["limit=\(limit)"]
        if let seasonType = descriptor.leadersSeasonType, let season {
            query.append("season=\(season)")
            query.append("seasontype=\(seasonType)")
        }
        if let teamID { query.append("team=\(teamID)") }
        return "\(Self.siteAPIv3)/\(path)/leaders?" + query.joined(separator: "&")
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

    /// Splits an `id` back into its league and ESPN id. League paths hold a
    /// `/` but never a `:`, so the id splits at its last `:`. `nil` for
    /// anything `id(league:espnID:)` could not have produced.
    static func parse(id: String) -> (league: LeagueID, espnID: String)? {
        guard let separator = id.lastIndex(of: ":"),
              let league = LeagueID(path: String(id[..<separator]))
        else { return nil }
        let espnID = String(id[id.index(after: separator)...])
        guard !espnID.isEmpty else { return nil }
        return (league, espnID)
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

// MARK: - Deep links

/// The URL a widget opens the app with: `myteams://team/<TeamRef.id>`, e.g.
/// `myteams://team/football/nfl:12`. Built by the widget, the Live Activity
/// (`GameActivityInfo.deepLink`) and the score alerts, read by the app.
///
/// Always built from the team's own `TeamRef.id`, in its home league: a cup
/// tie is listed under the cup's board (`"soccer/uefa.champions"`), which is
/// no league the team is filed under.
enum WidgetDeepLink {
    static let scheme = "myteams"
    static let teamHost = "team"

    /// The link that opens `teamID`'s page. `nil` for anything
    /// `TeamRef.parse(id:)` rejects.
    static func url(forTeamID teamID: TeamRef.ID) -> URL? {
        guard TeamRef.parse(id: teamID) != nil,
              let path = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(scheme)://\(teamHost)/\(path)")
    }

    /// The `TeamRef.id` a link names, or `nil` unless it is a `myteams://team/`
    /// link to a well-formed id. Scheme and host match case-insensitively.
    static func teamID(from url: URL) -> TeamRef.ID? {
        guard url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == teamHost
        else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/") else { return nil }
        let id = String(path.dropFirst())
        // `parse` would take "football/nfl:12/extra" as ESPN id "12/extra".
        guard let parsed = TeamRef.parse(id: id), !parsed.espnID.contains("/") else { return nil }
        return id
    }
}

// MARK: - Leagues

/// A league offered in the picker's chip row.
struct BrowsableLeague: Identifiable, Hashable, Sendable {
    /// The chip and badge text, e.g. `"NCAAF"`.
    let label: String
    let league: LeagueID

    var id: LeagueID { league }
}

extension LeagueID {
    /// The leagues the picker lists, in chip order.
    static let browsable: [BrowsableLeague] = [
        BrowsableLeague(label: "NFL", league: .nfl),
        BrowsableLeague(label: "NBA", league: .nba),
        BrowsableLeague(label: "MLB", league: .mlb),
        BrowsableLeague(label: "NHL", league: .nhl),
        BrowsableLeague(label: "MLS", league: .mls),
        BrowsableLeague(label: "WNBA", league: .wnba),
        BrowsableLeague(label: "NCAAF", league: .collegeFootball),
        BrowsableLeague(label: "NCAAM", league: .mensCollegeBasketball),
        BrowsableLeague(label: "NCAAW", league: .womensCollegeBasketball),
        BrowsableLeague(label: "EPL", league: .premierLeague),
    ]

    /// The short label a team row's badge shows, e.g. `"NFL"`. Leagues the
    /// picker does not list show their league path component, uppercased.
    var badge: String {
        Self.browsable.first { $0.league == self }?.label ?? league.uppercased()
    }
}

// MARK: - Search

/// Matching teams against a search query. Shared with the widget's team
/// search; the app adds ESPN's remote search in TeamBrowserView.swift.
enum TeamSearch {
    /// `text` lowercased and without diacritics, so "malmo" finds "Malmö".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The names a team can be found by: display name, short name,
    /// abbreviation, location, and the nickname (the display name after its
    /// location — `TeamRef` keeps no separate nickname).
    static func searchableFields(of team: TeamRef) -> [String] {
        var fields = [team.displayName, team.shortName, team.abbreviation, team.location]
        if !team.location.isEmpty, team.displayName.hasPrefix(team.location) {
            let nickname = team.displayName.dropFirst(team.location.count).trimmingCharacters(in: .whitespaces)
            if !nickname.isEmpty { fields.append(nickname) }
        }
        return fields.filter { !$0.isEmpty }
    }

    /// Whether any of the team's names contains the query, ignoring case and
    /// diacritics. An empty query matches every team.
    static func matches(_ team: TeamRef, query: String) -> Bool {
        let folded = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty else { return true }
        return searchableFields(of: team).contains { fold($0).contains(folded) }
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
///
/// An unfollowed team stays stored as a tombstone (`isRemoved`), so the
/// removal reaches the reader's other devices instead of the team coming
/// back from their copies.
struct FavoriteTeam: Codable, Identifiable, Equatable, Sendable {
    /// A `TeamRef.id`, `"<leaguePath>:<espnID>"`.
    let teamID: String
    var addedAt: Date
    /// When the team was unfollowed. `nil`, or earlier than `addedAt`, while
    /// it is followed.
    var removedAt: Date?
    /// Whether game alerts are wanted for the team (`ScoreAlertEngine`).
    var notify: Bool
    /// When the reader last set `notify`. `nil` until they do, which counts
    /// as `addedAt`: following a team sets it to the default.
    var notifyChangedAt: Date?

    var id: String { teamID }

    /// When `notify` took its value, for merging.
    var notifySetAt: Date { notifyChangedAt ?? addedAt }

    /// Whether the entry is a tombstone: removed no earlier than it was added.
    var isRemoved: Bool {
        guard let removedAt else { return false }
        return removedAt >= addedAt
    }

    init(teamID: String, addedAt: Date = Date(), removedAt: Date? = nil, notify: Bool = true, notifyChangedAt: Date? = nil) {
        self.teamID = teamID
        self.addedAt = addedAt
        self.removedAt = removedAt
        self.notify = notify
        self.notifyChangedAt = notifyChangedAt
    }
}

/// The iCloud side of the favorites mirror. `NSUbiquitousKeyValueStore`
/// conforms as is; tests substitute an in-memory store.
protocol FavoritesCloudStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    /// Exchanges pending changes with iCloud, as
    /// `NSUbiquitousKeyValueStore.synchronize()` does.
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: FavoritesCloudStore {}

/// Reads, writes and merges the favorites list, with no UI or WidgetKit in
/// the way.
///
/// The list is JSON `{"favorites": [FavoriteTeam]}` under `key` in the App
/// Group's `UserDefaults`, which the widget reads directly, and the same
/// bytes are mirrored to iCloud key-value storage for other devices. The
/// entries include tombstones; `decode` leaves them out. Version 1 stored a
/// bare `[FavoriteTeam]` array, which still decodes.
enum FavoritesCodec {
    /// The favorites JSON, in the shared defaults and in iCloud. The key
    /// predates the v2 shape and is kept so stored lists carry over.
    static let key = "favorites.v1"
    /// Set once the favorites have been seeded or restored, so the seed never
    /// runs twice.
    static let seededKey = "favorites.v1.seeded"
    /// The seed teams' `addedAt`: older than any edit, so a device's seed
    /// never outweighs a removal synced from another device.
    static let seedDate = Date(timeIntervalSince1970: 0)

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

    /// The v2 shape.
    private struct Stored: Codable {
        var favorites: [FavoriteTeam]
    }

    /// Encodes the entries, tombstones included, in the v2 shape.
    static func encode(_ entries: [FavoriteTeam]) -> Data? {
        try? encoder.encode(Stored(favorites: entries))
    }

    /// Every stored entry, tombstones included, from a v2 or v1 list. `nil`
    /// for missing or unreadable data.
    static func decodeEntries(_ data: Data?) -> [FavoriteTeam]? {
        guard let data else { return nil }
        if let stored = try? decoder.decode(Stored.self, from: data) {
            return stored.favorites
        }
        return try? decoder.decode([FavoriteTeam].self, from: data)
    }

    /// The followed teams, in order: the stored entries less tombstones.
    /// `nil` for missing or unreadable data.
    static func decode(_ data: Data?) -> [FavoriteTeam]? {
        decodeEntries(data)?.filter { !$0.isRemoved }
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
        seedIDs: [TeamRef.ID]
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
        let seeded = seedIDs.map { FavoriteTeam(teamID: $0, addedAt: seedDate) }
        save(seeded, defaults: defaults, cloud: cloud)
        defaults.set(true, forKey: seededKey)
        return (seeded, .seeded)
    }

    /// Writes the entries to `defaults` and mirrors the same JSON to `cloud`.
    static func save(_ entries: [FavoriteTeam], defaults: UserDefaults, cloud: (any FavoritesCloudStore)?) {
        guard let data = encode(entries) else { return }
        defaults.set(data, forKey: key)
        cloud?.set(data, forKey: key)
    }

    // MARK: Merging

    /// Merges two devices' entries into one list both can adopt.
    ///
    /// Each team keeps whichever copy was edited last (`newer(_:_:)`), so an
    /// add and a remove made apart resolve to the later one. Its alerts
    /// setting is merged on its own: the copy whose `notify` was set last
    /// wins, so turning alerts off is not undone by a device that never saw
    /// it, and a follow made after it resets it. The result is
    /// the followed teams — first those `local` shows, in its order, then the
    /// rest oldest-added first — followed by the tombstones. Apart from that
    /// order, `merge(a, b)` and `merge(b, a)` hold the same entries.
    static func merge(_ local: [FavoriteTeam], _ remote: [FavoriteTeam]) -> [FavoriteTeam] {
        var winners: [TeamRef.ID: FavoriteTeam] = [:]
        for entry in local + remote {
            guard let current = winners[entry.teamID] else {
                winners[entry.teamID] = entry
                continue
            }
            var winner = newer(current, entry)
            if current.notifySetAt != entry.notifySetAt {
                let setting = current.notifySetAt > entry.notifySetAt ? current : entry
                winner.notify = setting.notify
                winner.notifyChangedAt = setting.notifyChangedAt
            }
            winners[entry.teamID] = winner
        }
        let localOrder = Dictionary(
            local.filter { !$0.isRemoved }.enumerated().map { ($1.teamID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sorted = winners.values.sorted { a, b in
            switch (localOrder[a.teamID], localOrder[b.teamID]) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (a.addedAt, a.teamID) < (b.addedAt, b.teamID)
            }
        }
        return sorted.filter { !$0.isRemoved } + sorted.filter(\.isRemoved)
    }

    /// Whether two lists hold the same entries, whatever their order.
    static func sameEntries(_ a: [FavoriteTeam], _ b: [FavoriteTeam]) -> Bool {
        func byID(_ entries: [FavoriteTeam]) -> [TeamRef.ID: FavoriteTeam] {
            Dictionary(entries.map { ($0.teamID, $0) }, uniquingKeysWith: { $1 })
        }
        return a.count == b.count && byID(a) == byID(b)
    }

    /// The later-edited of two entries for one team. Ties go to the removal,
    /// then fall through the other fields, so every device picks the same one.
    private static func newer(_ a: FavoriteTeam, _ b: FavoriteTeam) -> FavoriteTeam {
        func rank(_ entry: FavoriteTeam) -> (Date, Int, Date, Date, Int, Date) {
            let removedAt = entry.removedAt ?? .distantPast
            return (
                max(entry.addedAt, removedAt),
                entry.isRemoved ? 1 : 0,
                entry.addedAt,
                removedAt,
                entry.notify ? 1 : 0,
                entry.notifyChangedAt ?? .distantPast
            )
        }
        return rank(b) > rank(a) ? b : a
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
