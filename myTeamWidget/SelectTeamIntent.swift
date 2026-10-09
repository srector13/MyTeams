//
//  SelectTeamIntent.swift
//  myTeamsWidget
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import Foundation

// `TeamEntity`, `TeamEntityQuery` and `WidgetTeams` are shared with the app
// (Hawk Nation/Intents/TeamEntity.swift, R-12).

// MARK: - Configuration intent

/// The configurable widget's settings: which team it follows.
struct SelectTeamIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Team"
    static let description = IntentDescription("Choose the team whose next game the widget shows.")

    /// The team to show. When unset, the widget shows the first favorite,
    /// or, with none followed, asks for one (`WidgetTimelines.noTeam`).
    @Parameter(title: "Team")
    var team: TeamEntity?

    init() {}
}

// MARK: - Resolving teams

extension WidgetTeams {
    /// The team a configured widget shows: the chosen one, else the first
    /// favorite, as the app shares it (`favorites(in:)`), so its link opens
    /// that favorite rather than `fallback`. `nil` with no team chosen and
    /// none readable: a fresh install (t_afe5c297), or a store the app does
    /// not share, which the entry then says (`WidgetMissingTeam`).
    static func team(for configuration: SelectTeamIntent) async -> TeamRef? {
        if let chosen = configuration.team?.team {
            return chosen
        }
        let container = SharedContainer.live
        guard let first = container.favoriteTeamIDs().first else {
            return nil
        }
        if let mirrored = container.favoritesMirror()?.teams.first(where: { $0.id == first }) {
            return mirrored
        }
        return await resolve(first, within: resolveDeadline) ?? TeamRef.placeholder(id: first) ?? fallback
    }
}
