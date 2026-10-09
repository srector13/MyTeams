//
//  MyTeamsShortcuts.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents

/// The Siri phrases and Shortcuts app actions the app offers without any
/// setup (R-12). Each phrase names the app, as Siri requires; the team slot
/// is filled from `TeamEntityQuery`'s suggestions, the favorites, refreshed
/// as they change (`TeamSpotlightIndexer`).
struct MyTeamsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextGameIntent(),
            phrases: [
                "When do \(.applicationName)'s \(\.$team) play next",
                "When do the \(\.$team) play next in \(.applicationName)",
                "When does \(\.$team) play next in \(.applicationName)",
                "Next \(\.$team) game in \(.applicationName)",
            ],
            shortTitle: "Next Game",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenTeamIntent(),
            phrases: [
                "Open \(\.$team) in \(.applicationName)",
                "Open the \(\.$team) in \(.applicationName)",
                "Show \(\.$team) in \(.applicationName)",
            ],
            shortTitle: "Open Team",
            systemImageName: "sportscourt"
        )
    }
}
