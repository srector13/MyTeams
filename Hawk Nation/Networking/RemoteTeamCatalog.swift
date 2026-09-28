//
//  RemoteTeamCatalog.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.myTeams", category: "catalog")

// MARK: - Logo selection

/// Picks a team's crests out of an ESPN `logos` array.
///
/// Pro teams list about sixteen entries, including 4096 px brand-service
/// variants under `guid/…`, so the first entry is never the one to take. Each
/// entry's `rel` is an array of tokens; the crests are chosen by those:
///
/// - default: `rel` contains `"full"` and `"default"` — `…/teamlogos/{league}/500/{abbr}.png`
/// - dark: `rel` contains `"full"` and `"dark"` — `…/500-dark/{abbr}.png`
///
/// Entries tagged `scoreboard` or `grayscale`, and every `guid/…` href (the
/// `primary_logo_*` / `secondary_logo_*` set), are never chosen. The first
/// qualifying entry of each kind wins.
enum ESPNLogos {
    struct Selection: Equatable, Sendable {
        var `default`: URL?
        var dark: URL?
    }

    private static let excludedRels: Set<String> = ["scoreboard", "grayscale"]

    static func select(_ logos: JSON) -> Selection {
        var selection = Selection()
        for (_, logo) in logos {
            let rel = Set(logo["rel"].arrayValue.map(\.stringValue))
            let href = logo["href"].stringValue
            guard rel.contains("full"),
                  rel.isDisjoint(with: excludedRels),
                  !href.contains("/guid/"),
                  let url = URL(string: href)
            else { continue }

            if rel.contains("default"), selection.default == nil {
                selection.default = url
            } else if rel.contains("dark"), selection.dark == nil {
                selection.dark = url
            }
        }
        return selection
    }
}

// MARK: - Remote catalog

/// Every team in a league, from ESPN's `teams` endpoint.
///
/// Lists are cached on disk per league for a week, at
/// `{shared caches}/TeamCatalog/{sport}.{league}.json`. That file is also the
/// offline catalog: a list is served from a fresh cache, then the network,
/// then a stale cache of any age, then the bundled seed teams in the league.
/// Nothing here throws; each failure falls through to the next source.
actor RemoteTeamCatalog {
    static let shared = RemoteTeamCatalog()

    /// How long a cached league list is served without asking ESPN again.
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    /// A league's cache file.
    struct CacheFile: Codable, Sendable {
        var fetchedAt: Date
        var teams: [TeamRef]
    }

    private let client: HTTPClient
    private let directory: URL
    private let now: @Sendable () -> Date

    /// League lists read or fetched this session.
    private var cached: [LeagueID: CacheFile] = [:]
    /// Loads in flight, so concurrent callers share one request.
    private var loads: [LeagueID: Task<[TeamRef], Never>] = [:]
    /// The seed teams as the latest pro-league fetch described them.
    private var refreshedSeeds: [TeamRef.ID: TeamRef] = [:]

    init(
        client: HTTPClient = .shared,
        directory: URL = SharedPaths.teamCatalog,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.directory = directory
        self.now = now
    }

    // MARK: Lookup

    /// The league's teams, in ESPN's order.
    func teams(for league: LeagueID) async -> [TeamRef] {
        if let file = cached[league], isFresh(file) {
            return file.teams
        }
        if let existing = loads[league] {
            return await existing.value
        }
        let task = Task { await self.load(league) }
        loads[league] = task
        let teams = await task.value
        loads[league] = nil
        return teams
    }

    /// The team with the given `TeamRef.id`, e.g. `"football/nfl:12"`.
    func team(id: TeamRef.ID) async -> TeamRef? {
        guard let parsed = TeamRef.parse(id: id) else { return nil }
        return await teams(for: parsed.league).first { $0.id == id }
    }

    /// A seed team with the names, colours and crest URLs of the latest
    /// successful fetch of its league, or unchanged if there has been none.
    /// The bundled `teams.json` stays the launch default.
    func refreshedSeed(_ team: TeamRef) -> TeamRef {
        refreshedSeeds[team.id] ?? team
    }

    /// Fetches a league's list if its cache has expired and none was fetched
    /// within `minimumInterval`. For the widget, whose timeline reloads hourly.
    func refreshIfDue(_ league: LeagueID, minimumInterval: TimeInterval, defaults: UserDefaults = .standard) async {
        let key = "RemoteTeamCatalog.lastRefresh.\(league.path)"
        if let last = defaults.object(forKey: key) as? Date, now().timeIntervalSince(last) < minimumInterval {
            return
        }
        defaults.set(now(), forKey: key)
        _ = await teams(for: league)
    }

    /// Stores the crests of `teams` (the default variant, plus the dark one
    /// where the feed lists a separate URL) in the catalog cache, four at a
    /// time. Call with the rows actually on screen, not whole leagues.
    func prefetchLogos(for teams: [TeamRef]) async {
        await withTaskGroup(of: Void.self) { group in
            var pending = teams.makeIterator()
            for _ in 0..<4 {
                guard let team = pending.next() else { break }
                group.addTask { await LogoStore.prefetchAllVariants(team) }
            }
            while await group.next() != nil {
                guard let team = pending.next() else { continue }
                group.addTask { await LogoStore.prefetchAllVariants(team) }
            }
        }
    }

    // MARK: Loading

    private func isFresh(_ file: CacheFile) -> Bool {
        now().timeIntervalSince(file.fetchedAt) < Self.timeToLive
    }

    private func load(_ league: LeagueID) async -> [TeamRef] {
        let disk = cached[league] ?? readCache(league)
        if let disk, isFresh(disk) {
            cached[league] = disk
            return disk.teams
        }

        if let document = await client.fetch(league.teamsURL).document {
            let teams = Self.withSeedAssets(Self.parseTeams(document, league: league))
            if !teams.isEmpty {
                let file = CacheFile(fetchedAt: now(), teams: teams)
                cached[league] = file
                writeCache(file, for: league)
                if !league.isCollege {
                    refreshSeeds(from: teams)
                }
                return teams
            }
        }

        if let disk {
            cached[league] = disk
            return disk.teams
        }
        return TeamCatalog.all.filter { $0.league == league }
    }

    private func refreshSeeds(from teams: [TeamRef]) {
        for seed in TeamCatalog.all {
            guard let fetched = teams.first(where: { $0.id == seed.id }) else { continue }
            refreshedSeeds[seed.id] = Self.refreshing(seed, from: fetched)
        }
    }

    // MARK: Parsing

    /// Reads a `teams` document: `sports[0].leagues[0].teams[].team`.
    ///
    /// Colours are the feed's six-digit hex strings without a `#`, or empty
    /// when the feed has none. Remote teams carry no bundled crest.
    static func parseTeams(_ document: JSON, league: LeagueID) -> [TeamRef] {
        document["sports", 0, "leagues", 0, "teams"].arrayValue.compactMap { entry in
            let team = entry["team"]
            let espnID = team["id"].stringValue
            guard !espnID.isEmpty else { return nil }
            let logos = ESPNLogos.select(team["logos"])
            return TeamRef(
                league: league,
                espnID: espnID,
                displayName: team["displayName"].stringValue,
                shortName: team["shortDisplayName"].stringValue,
                abbreviation: team["abbreviation"].stringValue,
                location: team["location"].stringValue,
                colorHex: team["color"].stringValue,
                alternateColorHex: team["alternateColor"].stringValue,
                logoURL: logos.default,
                logoDarkURL: logos.dark,
                logoAsset: nil
            )
        }
    }

    /// Gives the seed teams in a fetched list their bundled crest name, so
    /// they keep the offline fallback wherever the list is shown.
    static func withSeedAssets(_ teams: [TeamRef]) -> [TeamRef] {
        teams.map { team in
            guard let asset = TeamCatalog.team(id: team.id)?.logoAsset else { return team }
            var team = team
            team.logoAsset = asset
            return team
        }
    }

    /// `seed` with the feed's name, colours and crest URLs. The tab label
    /// (`shortName`), abbreviation, location and bundled crest stay the seed's.
    static func refreshing(_ seed: TeamRef, from fetched: TeamRef) -> TeamRef {
        var seed = seed
        if !fetched.displayName.isEmpty { seed.displayName = fetched.displayName }
        if !fetched.colorHex.isEmpty { seed.colorHex = fetched.colorHex }
        if !fetched.alternateColorHex.isEmpty { seed.alternateColorHex = fetched.alternateColorHex }
        if let url = fetched.logoURL { seed.logoURL = url }
        if let url = fetched.logoDarkURL { seed.logoDarkURL = url }
        return seed
    }

    // MARK: Cache files

    /// e.g. `TeamCatalog/football.nfl.json`.
    func cacheURL(for league: LeagueID) -> URL {
        directory.appending(path: "\(league.sport).\(league.league).json", directoryHint: .notDirectory)
    }

    private func readCache(_ league: LeagueID) -> CacheFile? {
        guard let data = try? Data(contentsOf: cacheURL(for: league)) else { return nil }
        return try? Self.decoder.decode(CacheFile.self, from: data)
    }

    private func writeCache(_ file: CacheFile, for league: LeagueID) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(file).write(to: cacheURL(for: league), options: .atomic)
        } catch {
            logger.error("Could not cache the \(league.path) catalog: \(error.localizedDescription)")
        }
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
