//
//  TeamEntity.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import Foundation

// Compiled into both targets, like `LogoStore`: the widget's configuration
// (`SelectTeamIntent`) and the app's intents, Siri phrases and Spotlight
// results (R-12) offer the same teams.

// MARK: - Team entity

/// A team, as the widget's configuration and the app's intents offer it.
/// Identified by `TeamRef.id`, which is all the system persists for a placed
/// widget or a shortcut; the team itself is resolved again through
/// `TeamEntityQuery`.
struct TeamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static let defaultQuery = TeamEntityQuery()

    /// `TeamRef.id`, e.g. `"football/nfl:12"`.
    let id: String
    let team: TeamRef
    /// A status line added to the subtitle: the widget's configuration
    /// sheet is drawn by the system, and its suggestions are the one place
    /// it can say the shared data is unreachable (`SharedDataStatus`).
    let note: String?

    init(team: TeamRef) {
        self.init(team: team, note: nil)
    }

    init(team: TeamRef, note: String?) {
        self.id = team.id
        self.team = team
        self.note = note
    }

    var displayRepresentation: DisplayRepresentation {
        if let note {
            return DisplayRepresentation(title: "\(team.displayName)", subtitle: "\(team.league.badge) · \(note)")
        }
        return DisplayRepresentation(title: "\(team.displayName)", subtitle: "\(team.league.badge)")
    }
}

/// Finds teams for the widget's configuration: the reader's favorites as
/// suggestions, and a search over the team catalogs already on disk.
struct TeamEntityQuery: EntityStringQuery {
    /// The most teams a search returns.
    private static let searchLimit = 30

    /// The teams a placed widget or a shortcut names
    /// (`configured(_:mirrored:remembered:resolve:)`).
    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        await Self.configured(identifiers, mirrored: SharedContainer.live.favoritesMirror()?.teams ?? [])
    }

    /// The teams `identifiers` name. Each is resolved again every timeline,
    /// so the lookup is bounded: the app's copy of the favorites first, then
    /// the teams this process offered or resolved before (`remembered`, its
    /// own defaults, so no App Group or keychain is needed), then the bundle
    /// and the catalog within `WidgetTeams.resolveDeadline`, and last a
    /// placeholder named for the league. A chosen id is never dropped: the
    /// system keeps it in the widget's configuration, and dropping it here
    /// is what turned a configured widget back into its first favorite, or
    /// the sample teams, whenever sharing failed.
    static func configured(
        _ identifiers: [TeamEntity.ID],
        mirrored: [TeamRef],
        remembered: UserDefaults = .standard,
        resolve: (TeamRef.ID) async -> TeamRef? = { await WidgetTeams.resolve($0, within: WidgetTeams.resolveDeadline) }
    ) async -> [TeamEntity] {
        var entities: [TeamEntity] = []
        for id in identifiers {
            if let team = mirrored.first(where: { $0.id == id }) ?? WidgetConfigTeams.team(id: id, in: remembered) {
                entities.append(TeamEntity(team: team))
            } else if let team = await resolve(id) {
                WidgetConfigTeams.remember([team], in: remembered)
                entities.append(TeamEntity(team: team))
            } else if let placeholder = TeamRef.placeholder(id: id) {
                entities.append(TeamEntity(team: placeholder))
            }
        }
        return entities
    }

    /// The reader's favorites, as the app shares them
    /// (`suggestions(in:resolve:samples:)`).
    func suggestedEntities() async throws -> [TeamEntity] {
        let entities = await Self.suggestions(in: .live, chosen: WidgetConfigTeams.chosen())
        WidgetConfigTeams.remember(entities.map(\.team))
        return entities
    }

    /// The configuration's suggestions: the favorites the app shares, in
    /// order, noted with the store when it is not the project's App Group.
    ///
    /// With none to offer, the teams already `chosen` for a widget on this
    /// device, then the bundled `samples`, each subtitled as what it is and
    /// why the favorites are missing: none followed, or unreadable and from
    /// which store. Never the bundled teams passed off as the reader's own,
    /// which is what an unreadable store used to look like. A team chosen
    /// here is kept by the system and remembered by this process
    /// (`WidgetConfigTeams`), so the widget still shows it.
    static func suggestions(
        in container: SharedContainer,
        chosen: [TeamRef] = [],
        resolve: (TeamRef.ID) async -> TeamRef? = { await WidgetTeams.resolve($0, within: WidgetTeams.resolveDeadline) },
        samples: [TeamRef] = FavoriteTeams.teams
    ) async -> [TeamEntity] {
        let status = container.status
        let favorites = await WidgetTeams.favorites(in: container, resolve: resolve)
        guard favorites.isEmpty else {
            let note = suggestionNote(status)
            return favorites.map { TeamEntity(team: $0, note: note) }
        }
        let chosenNote = self.chosenNote(status)
        let note = sampleNote(status)
        let chosenIDs = Set(chosen.map(\.id))
        return chosen.map { TeamEntity(team: $0, note: chosenNote) }
            + samples.filter { !chosenIDs.contains($0.id) }.map { TeamEntity(team: $0, note: note) }
    }

    /// The subtitle of a team offered because a widget here showed it
    /// before, with no favorites to offer.
    static func chosenNote(_ status: SharedDataStatus) -> String {
        guard let note = status.note, !status.isAvailable else {
            return "Chosen before · no favorites in myTeams"
        }
        return "Chosen before · \(note)"
    }

    /// The status line the favorites carry: none while the project's group
    /// carries the app's data, else the store read (`SharedDataStatus.note`).
    static func suggestionNote(_ status: SharedDataStatus) -> String? {
        status.note
    }

    /// The subtitle of a bundled team offered in place of favorites.
    static func sampleNote(_ status: SharedDataStatus) -> String {
        guard let note = status.note, !status.isAvailable else {
            return "Sample team · no favorites in myTeams"
        }
        return "Sample team · \(note)"
    }

    /// Searches the leagues of the reader's favorites, plus every listed
    /// league whose catalog is already cached, by the same folded matching
    /// as the app's picker.
    ///
    /// Without the app's favorites or caches (a store the widget can't
    /// read), the bundled teams, those this process remembers, and the
    /// small professional leagues are searched too, so any of them can still
    /// be chosen; the college leagues' catalogs are too large to load here.
    func entities(matching string: String) async throws -> [TeamEntity] {
        let catalog = RemoteTeamCatalog.shared
        var matches = (TeamCatalog.all + WidgetConfigTeams.known()).filter { TeamSearch.matches($0, query: string) }
        var leagues: [LeagueID] = []
        for id in SharedPaths.favoriteTeamIDs() {
            if let league = TeamRef.parse(id: id)?.league, !leagues.contains(league) {
                leagues.append(league)
            }
        }
        for item in LeagueID.browsable where !leagues.contains(item.league) {
            let file = await catalog.cacheURL(for: item.league)
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                leagues.append(item.league)
            }
        }

        for league in Self.searchedWithoutCache where !leagues.contains(league) {
            leagues.append(league)
        }
        let searched = leagues
        let found = await Deadline.value(within: WidgetTeams.resolveDeadline) { () async -> [TeamRef]? in
            var found: [TeamRef] = []
            for league in searched {
                for team in await catalog.teams(for: league) where TeamSearch.matches(team, query: string) {
                    found.append(team)
                }
            }
            return found
        } ?? []
        let bundled = Set(matches.map(\.id))
        matches += found.filter { !bundled.contains($0.id) }
        let entities = Self.entities(for: matches)
        WidgetConfigTeams.remember(entities.map(\.team))
        return entities
    }

    /// Leagues a few dozen teams long, searched even when not cached.
    static let searchedWithoutCache: [LeagueID] = [.nfl, .nba, .mlb, .nhl, .mls, .wnba, .nwsl]

    /// One entity per club, as the app's search lists them
    /// (`TeamSearch.canonicalClubs(from:)`), at most `searchLimit`.
    static func entities(for matches: [TeamRef]) -> [TeamEntity] {
        TeamSearch.canonicalClubs(from: matches)
            .prefix(searchLimit)
            .map(TeamEntity.init(team:))
    }
}

// MARK: - Resolving teams

/// Turns stored team ids into teams inside the widget process, which has no
/// `FavoritesStore`: favorites come from `SharedPaths.favoriteTeamIDs()`.
/// The app's intents resolve through it too, so both offer the same teams.
enum WidgetTeams {
    /// The team a widget shows when a favorite does not resolve, and the
    /// gallery's sample: the Jayhawks, the original widget's team. Never
    /// shown for a reader who follows no team (`team(for:)`). Spelled out
    /// here too, so a broken bundled catalog can't leave the widget teamless.
    static let fallback = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305") ?? TeamRef(
        league: .mensCollegeBasketball,
        espnID: "2305",
        displayName: "Kansas Jayhawks",
        shortName: "Jayhawks",
        abbreviation: "KU",
        location: "Kansas",
        colorHex: "0051BA",
        alternateColorHex: "E8000D"
    )

    /// How long a lookup the catalog must answer may take in the widget:
    /// it loads and parses the team's whole league, and the timeline must
    /// still finish inside the extension's budget.
    static let resolveDeadline: Duration = .seconds(8)

    /// A team by `TeamRef.id`. Seed teams resolve from the bundle without
    /// reading a catalog; any other goes through `RemoteTeamCatalog`, which
    /// serves its disk cache offline.
    static func resolve(_ id: String) async -> TeamRef? {
        guard TeamRef.parse(id: id) != nil else { return nil }
        if let seed = TeamCatalog.team(id: id) {
            return await RemoteTeamCatalog.shared.refreshedSeed(seed)
        }
        return await RemoteTeamCatalog.shared.team(id: id)
    }

    /// `resolve(_:)`, giving up after `deadline`.
    static func resolve(_ id: String, within deadline: Duration) async -> TeamRef? {
        if let seed = TeamCatalog.team(id: id) {
            return await RemoteTeamCatalog.shared.refreshedSeed(seed)
        }
        return await Deadline.value(within: deadline) { await WidgetTeams.resolve(id) }
    }

    /// The favorites, in order, as the app shares them: its copy of each
    /// team when it wrote one, else `resolve`d, else a placeholder named
    /// for the league, so a favorite is never dropped or swapped for
    /// another team. Empty when none are followed, or none can be read.
    static func favorites(
        in container: SharedContainer = .live,
        resolve: (TeamRef.ID) async -> TeamRef? = { await WidgetTeams.resolve($0, within: WidgetTeams.resolveDeadline) }
    ) async -> [TeamRef] {
        let ids = container.favoriteTeamIDs()
        guard !ids.isEmpty else { return [] }
        let mirrored = container.favoritesMirror()?.teams ?? []
        var teams: [TeamRef] = []
        for id in ids {
            if let team = mirrored.first(where: { $0.id == id }) {
                teams.append(team)
            } else if let team = await resolve(id) {
                teams.append(team)
            } else if let placeholder = TeamRef.placeholder(id: id) {
                teams.append(placeholder)
            }
        }
        return teams
    }

    /// The first favorite, for a placeholder that must be built
    /// synchronously: the app's copy of it, else the bundle's, else
    /// `fallback`.
    static var firstSeedFavorite: TeamRef {
        let container = SharedContainer.live
        if let mirror = container.favoritesMirror(),
           let first = mirror.teams.first(where: { $0.id == mirror.ids.first }) {
            return first
        }
        return container.favoriteTeamIDs().lazy.compactMap(TeamCatalog.team(id:)).first ?? fallback
    }
}

// MARK: - Widget configuration teams

/// The teams this process has offered, resolved or shown for a widget's
/// configuration, in its own `UserDefaults` (the widget extension's own
/// container): what lets a configured widget show its team with no App
/// Group or keychain shared with the app. The system keeps only the chosen
/// team's id in the configuration (`TeamEntity.id`); this keeps the team
/// that id names.
enum WidgetConfigTeams {
    static let knownKey = "widgetConfig.knownTeams.v1"
    static let chosenKey = "widgetConfig.chosenTeams.v1"
    /// The most teams kept: a search offers up to 30 at a time.
    static let knownLimit = 120
    static let chosenLimit = 12

    /// A team remembered under `id`.
    static func team(id: TeamRef.ID, in defaults: UserDefaults = .standard) -> TeamRef? {
        chosen(in: defaults).first { $0.id == id } ?? known(in: defaults).first { $0.id == id }
    }

    /// Every team remembered, most recent first.
    static func known(in defaults: UserDefaults = .standard) -> [TeamRef] {
        read(knownKey, from: defaults)
    }

    /// The teams widgets here have shown, most recent first.
    static func chosen(in defaults: UserDefaults = .standard) -> [TeamRef] {
        read(chosenKey, from: defaults)
    }

    /// Remembers `teams`, most recent first; placeholders are left out.
    static func remember(_ teams: [TeamRef], in defaults: UserDefaults = .standard) {
        write(teams, to: knownKey, limit: knownLimit, in: defaults)
    }

    /// Records that a widget shows `team`: it is offered first when the
    /// favorites can't be read, and resolves from here.
    static func markChosen(_ team: TeamRef, in defaults: UserDefaults = .standard) {
        write([team], to: chosenKey, limit: chosenLimit, in: defaults)
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> [TeamRef] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TeamRef].self, from: data)) ?? []
    }

    private static func write(_ teams: [TeamRef], to key: String, limit: Int, in defaults: UserDefaults) {
        let fresh = teams.filter { $0 != TeamRef.placeholder(id: $0.id) }
        guard !fresh.isEmpty else { return }
        let current = read(key, from: defaults)
        var merged: [TeamRef] = []
        for team in fresh + current where !merged.contains(where: { $0.id == team.id }) {
            merged.append(team)
        }
        merged = Array(merged.prefix(limit))
        guard merged != current, let data = try? JSONEncoder().encode(merged) else { return }
        defaults.set(data, forKey: key)
    }
}
