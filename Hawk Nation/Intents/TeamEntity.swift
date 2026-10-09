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

    /// The teams a placed widget or a shortcut names. Each is resolved again
    /// every timeline, so the lookup is bounded: the app's copy of the
    /// favorites first, then the bundle, then the catalog within
    /// `WidgetTeams.resolveDeadline`.
    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        let mirrored = SharedContainer.live.favoritesMirror()?.teams ?? []
        var entities: [TeamEntity] = []
        for id in identifiers {
            if let team = mirrored.first(where: { $0.id == id }) {
                entities.append(TeamEntity(team: team))
            } else if let team = await WidgetTeams.resolve(id, within: WidgetTeams.resolveDeadline) {
                entities.append(TeamEntity(team: team))
            }
        }
        return entities
    }

    /// The reader's favorites, as the app shares them
    /// (`suggestions(in:resolve:samples:)`).
    func suggestedEntities() async throws -> [TeamEntity] {
        await Self.suggestions(in: .live)
    }

    /// The configuration's suggestions: the favorites the app shares, in
    /// order, noted with the store when it is not the project's App Group.
    ///
    /// With none to offer, the bundled `samples`, each subtitled as a sample
    /// and why: none followed, or the favorites unreadable and from which
    /// store. Never the bundled teams passed off as the reader's own, which
    /// is what an unreadable store used to look like. A team chosen here is
    /// kept by the system, so the widget still shows it.
    static func suggestions(
        in container: SharedContainer,
        resolve: (TeamRef.ID) async -> TeamRef? = { await WidgetTeams.resolve($0, within: WidgetTeams.resolveDeadline) },
        samples: [TeamRef] = FavoriteTeams.teams
    ) async -> [TeamEntity] {
        let status = container.status
        let favorites = await WidgetTeams.favorites(in: container, resolve: resolve)
        guard favorites.isEmpty else {
            let note = suggestionNote(status)
            return favorites.map { TeamEntity(team: $0, note: note) }
        }
        let note = sampleNote(status)
        return samples.map { TeamEntity(team: $0, note: note) }
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
    func entities(matching string: String) async throws -> [TeamEntity] {
        let catalog = RemoteTeamCatalog.shared
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

        var matches: [TeamRef] = []
        for league in leagues {
            for team in await catalog.teams(for: league) where TeamSearch.matches(team, query: string) {
                matches.append(team)
            }
        }
        return Self.entities(for: matches)
    }

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
