//
//  LiveGameControl.swift
//  myTeamWidget
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center and Lock Screen control "Open Live Game" (R-9): opens
/// the first favorite's game under way on its sheet (R-3), or the app's Home
/// with none under way.
@available(iOS 18.0, *)
struct LiveGameControl: ControlWidget {
    static let kind = "myTeamsLiveGame"

    /// Where the control opens the app with no game under way: Home, which
    /// the app selects (`WidgetDeepLink.isHome`), from whatever it showed.
    nonisolated static let homeURL = WidgetDeepLink.homeURL

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: LiveGameControlProvider()) { url in
            ControlWidgetButton(action: OpenURLIntent(url)) {
                Label("Open Live Game", systemImage: "sportscourt.fill")
            }
        }
        .displayName("Open Live Game")
        .description("Opens your favorite's game under way, or myTeams when none is.")
    }

    /// Asks the system for the control's link again: the widgets' timelines
    /// call this, since the app reloads them whenever its scoreboard
    /// snapshot changes.
    static func reload() async {
        await MainActor.run {
            ControlCenter.shared.reloadControls(ofKind: kind)
        }
    }
}

/// The link the control opens, read from the app's scoreboard snapshot.
@available(iOS 18.0, *)
struct LiveGameControlProvider: ControlValueProvider {
    var previewValue: URL {
        LiveGameControl.homeURL
    }

    /// Opens Home when the App Group is unreachable: with no favorites or
    /// scores to read, the control cannot know of a game, and the app says
    /// the rest.
    func currentValue() async throws -> URL {
        let shared = SharedContainer.live
        guard shared.isReachable else { return LiveGameControl.homeURL }
        return WidgetDayBuilder.liveGameURL(
            favoriteIDs: shared.favoriteTeamIDs(),
            snapshots: shared.scoreboardSnapshots(),
            now: .now
        ) ?? LiveGameControl.homeURL
    }
}
#endif
