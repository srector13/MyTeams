//
//  OpenTeamIntent.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import Foundation
import Observation

/// "Open the Chiefs in myTeams" (R-12): opens the app on the team's page,
/// through the same `myteams://team/` link the widget opens it with
/// (`WidgetDeepLink`), so `Home` routes it as it routes a widget tap.
///
/// The link opens a favorite's page; a team not followed opens the app as
/// it was, as a widget link to one does (`HomeRouting.linkChanged`). The
/// intent's suggestions are the favorites (`TeamEntityQuery`), so Siri and
/// Shortcuts offer those.
struct OpenTeamIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Team"
    static let description = IntentDescription("Opens a team's page.")
    static let openAppWhenRun = true

    @Parameter(title: "Team")
    var team: TeamEntity

    init() {}

    init(team: TeamEntity) {
        self.team = team
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // A team page only: a team has no game route of its own. Its next
        // game's sheet would need `WidgetDeepLink.url(forGame:)` and the
        // game's event id, which this intent does not load.
        AppIntentLinks.shared.link = Self.link(for: team.id)
        return .result()
    }

    /// The link the intent opens: `teamID`'s page, or `nil` for an id
    /// `TeamRef.parse(id:)` rejects.
    static func link(for teamID: TeamRef.ID) -> URL? {
        WidgetDeepLink.url(forTeamID: teamID)
    }
}

/// The link an intent run in the app asked for, until `MyTeamsApp` opens it
/// as it opens a widget's (`onOpenURL`) — the intents' counterpart of
/// `ScoreAlertTaps`.
@MainActor
@Observable
final class AppIntentLinks {
    static let shared = AppIntentLinks()

    var link: URL?
}
