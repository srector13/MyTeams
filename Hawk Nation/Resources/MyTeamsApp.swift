//
//  MyTeamsApp.swift
//  myTeams
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

@main
struct MyTeamsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Load (or seed) the favorites before the launch task below marks
        // the crests seeded: the store reads that mark to tell an existing
        // install from a fresh one when deciding on onboarding.
        _ = FavoritesStore.shared
    }

    /// The team a widget, Live Activity or score alert tap asked for,
    /// until `Home` shows it.
    @State private var deepLinkedTeamID: TeamRef.ID?
    /// Taps on score alerts, which arrive through the notification center
    /// rather than as a URL.
    @State private var alertTaps = ScoreAlertTaps.shared
    /// Light, dark or the system's, from Settings (`SettingsView`).
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            Home(deepLinkedTeamID: $deepLinkedTeamID)
                .preferredColorScheme(appearance.colorScheme)
                // Accessibility settings a UI test asked for at launch;
                // nothing otherwise (`Theme.LaunchAccessibility`).
                .launchAccessibilityOverrides()
                .onOpenURL { url in
                    if let teamID = WidgetDeepLink.teamID(from: url) {
                        deepLinkedTeamID = teamID
                    }
                }
                .onChange(of: alertTaps.teamID, initial: true) { _, teamID in
                    // Initially too: the tap may have launched the app.
                    guard let teamID else { return }
                    deepLinkedTeamID = teamID
                    alertTaps.teamID = nil
                }
                .task {
                    // Watch the live scoreboards for favorites' alerts. Asks
                    // for no permission; following a team does.
                    ScoreAlertEngine.shared.start()

                    // And for Live Activities of their games under way.
                    #if canImport(ActivityKit)
                    LiveActivityManager.shared.start()
                    #endif

                    // Put the bundled crests on disk once, then keep the
                    // favorites' crests current (weekly revalidation).
                    await LogoStore.seedBundledCrestsIfNeeded()
                    for team in await FavoritesStore.shared.teamRefs() {
                        await LogoStore.prefetchAllVariants(team, favorite: true)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up favorites edited on other devices meanwhile.
                    if phase == .active {
                        FavoritesStore.shared.synchronize()
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Poll every favorite's live games, not only the page
                    // on screen's, while the app is in the foreground.
                    LeagueScoreboardCenter.shared.sceneDidChange(to: phase)
                }
        }
    }
}

extension LeagueScoreboardCenter {
    /// Follows the favorites (`startFollowingFavorites()`) from the moment
    /// the app is active until it goes to the background. A passing
    /// `.inactive` — the app switcher, a system sheet — changes nothing, and
    /// nothing polls in the background.
    func sceneDidChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            startFollowingFavorites()
        case .background:
            stopFollowingFavorites()
        default:
            break
        }
    }
}

extension EnvironmentValues {
    /// The size of the window the app is drawn into.
    ///
    /// The layouts size a good deal of their content against the full width of
    /// the screen — news cards, the parallax team crest, the trailing spacer
    /// in each carousel. They used to read `UIScreen.main.bounds` for it, which
    /// is deprecated, is not reactive, and reports the whole display rather
    /// than the app's share of it when the window is not full screen. `Home`
    /// measures its own container instead and publishes the result here.
    @Entry var containerSize: CGSize = .zero
}
