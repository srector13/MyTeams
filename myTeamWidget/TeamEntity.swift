//
//  TeamEntity.swift
//  myTeamsWidget
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import Foundation

// MARK: - Team entity

/// A team, as the widget's configuration offers it. Identified by
/// `TeamRef.id`, which is all the system persists for a placed widget; the
/// team itself is resolved again through `TeamEntityQuery`.
struct TeamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    static let defaultQuery = TeamEntityQuery()

    /// `TeamRef.id`, e.g. `"football/nfl:12"`.
    let id: String
    let team: TeamRef

    init(team: TeamRef) {
        self.id = team.id
        self.team = team
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(team.displayName)", subtitle: "\(team.league.badge)")
    }
}

/// Finds teams for the widget's configuration: the reader's favorites as
/// suggestions, and a search over the team catalogs already on disk.
struct TeamEntityQuery: EntityStringQuery {
    /// The most teams a search returns.
    private static let searchLimit = 30

    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        var entities: [TeamEntity] = []
        for id in identifiers {
            if let team = await WidgetTeams.resolve(id) {
                entities.append(TeamEntity(team: team))
            }
        }
        return entities
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        await WidgetTeams.favorites().map(TeamEntity.init(team:))
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

        var matches: [TeamEntity] = []
        for league in leagues {
            for team in await catalog.teams(for: league) where TeamSearch.matches(team, query: string) {
                matches.append(TeamEntity(team: team))
                if matches.count == Self.searchLimit { return matches }
            }
        }
        return matches
    }
}

// MARK: - Configuration intent

/// The configurable widget's settings: which team it follows.
struct SelectTeamIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Team"
    static let description = IntentDescription("Choose the team whose next game the widget shows.")

    /// The team to show. When unset, the widget shows the first favorite.
    @Parameter(title: "Team")
    var team: TeamEntity?

    init() {}

    init(team: TeamEntity?) {
        self.team = team
    }
}

// MARK: - Resolving teams

/// Turns stored team ids into teams inside the widget process, which has no
/// `FavoritesStore`: favorites come from `SharedPaths.favoriteTeamIDs()`.
enum WidgetTeams {
    /// The team a widget shows when nothing else resolves: the Jayhawks, the
    /// original widget's team.
    static let fallback = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")

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

    /// The favorites, in order, dropping any that do not resolve. The seed
    /// teams when the app has stored none.
    static func favorites() async -> [TeamRef] {
        let ids = SharedPaths.favoriteTeamIDs()
        guard !ids.isEmpty else { return FavoriteTeams.teams }
        var teams: [TeamRef] = []
        for id in ids {
            if let team = await resolve(id) {
                teams.append(team)
            }
        }
        return teams
    }

    /// The first favorite the bundle knows, for a placeholder that must be
    /// built synchronously.
    static var firstSeedFavorite: TeamRef {
        SharedPaths.favoriteTeamIDs().lazy.compactMap(TeamCatalog.team(id:)).first ?? fallback
    }

    /// The team a configured widget shows: the chosen one, else the first
    /// favorite, else `fallback`.
    static func team(for configuration: SelectTeamIntent) async -> TeamRef {
        if let chosen = configuration.team?.team {
            return chosen
        }
        if let first = SharedPaths.favoriteTeamIDs().first, let team = await resolve(first) {
            return team
        }
        return fallback
    }
}
