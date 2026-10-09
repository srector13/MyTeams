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
    /// favorite (`fallback` if it does not resolve). `nil` with no team
    /// chosen and none followed: a fresh install (t_afe5c297).
    static func team(for configuration: SelectTeamIntent) async -> TeamRef? {
        if let chosen = configuration.team?.team {
            return chosen
        }
        guard let first = SharedPaths.favoriteTeamIDs().first else {
            return nil
        }
        return await resolve(first) ?? fallback
    }
}
