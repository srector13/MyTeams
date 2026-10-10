//
//  MyTeamsApp.swift
//  myTeams
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import BackgroundTasks
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "backgroundRefresh")

@main
struct MyTeamsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Load (or restore from iCloud) the favorites before anything reads
        // them. A fresh install has none: `Home` shows "Add Teams".
        _ = FavoritesStore.shared
    }

    /// The team a widget, Live Activity or score alert tap asked for,
    /// until `Home` shows it.
    @State private var deepLinkedTeamID: TeamRef.ID?
    /// The game a link asked for, whose sheet `Home` opens over
    /// `deepLinkedTeamID`'s page (R-3).
    @State private var deepLinkedGame: WidgetDeepLink.GameTarget?
    /// Taps on score alerts, which arrive through the notification center
    /// rather than as a URL.
    @State private var alertTaps = ScoreAlertTaps.shared
    /// Links an intent run in the app asked for (`OpenTeamIntent`, R-12).
    @State private var intentLinks = AppIntentLinks.shared
    /// Light, dark or the system's, from Settings (`SettingsView`).
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    /// The brand accent, from Settings (`BrandAccent`).
    @AppStorage(BrandAccent.storageKey) private var brandAccent: BrandAccent = .classic
    /// The style of the logo, from Settings (`BrandIconStyle`).
    @AppStorage(BrandIconStyle.storageKey) private var brandIconStyle: BrandIconStyle = .classic

    var body: some Scene {
        WindowGroup {
            Home(deepLinkedTeamID: $deepLinkedTeamID, deepLinkedGame: $deepLinkedGame)
                // Accessibility settings a UI test asked for at launch;
                // nothing otherwise (`Theme.LaunchAccessibility`).
                .launchAccessibilityOverrides()
                // Outside the reader's appearance (B-6): the splash keeps the
                // system's, as the launch screen before it does, and applies
                // `appearance` once it has gone.
                .splashOverlay(preferredColorScheme: appearance.colorScheme)
                // Outside the splash, so it draws the logo in the accent too.
                // The tint reaches every screen and sheet under the root,
                // and changes the moment Settings does.
                .brandAccent(brandAccent)
                // Beside it, for the same reasons: the splash's logo too.
                .brandIconStyle(brandIconStyle)
                .onOpenURL { url in
                    open(url)
                }
                .onChange(of: alertTaps.link, initial: true) { _, link in
                    // Initially too: the tap may have launched the app.
                    guard let link else { return }
                    open(link)
                    alertTaps.link = nil
                }
                .onChange(of: intentLinks.link, initial: true) { _, link in
                    // Initially too: the intent may have launched the app.
                    guard let link else { return }
                    open(link)
                    intentLinks.link = nil
                }
                .task {
                    // Watch the live scoreboards for favorites' alerts. Asks
                    // for no permission; following a team does.
                    ScoreAlertEngine.shared.start()
                    WidgetScoreboardWriter.shared.start()

                    // And for Live Activities of their games under way.
                    #if canImport(ActivityKit)
                    LiveActivityManager.shared.start()
                    #endif

                    // Offer the favorites in Spotlight and Siri (R-12).
                    TeamSpotlightIndexer.shared.start()

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
                        // The widgets read the favorites from the store the
                        // signature names; write it on every launch.
                        FavoritesStore.shared.publishToWidgets()
                    }
                    // Ask for the first background look, timed by the
                    // favorites' seasons as last loaded.
                    if phase == .background {
                        BackgroundRefresh.schedule(
                            at: LeagueScoreboardCenter.shared.nextFollowedRefresh(after: Date())
                        )
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Poll every favorite's live games, not only the page
                    // on screen's, while the app is in the foreground.
                    LeagueScoreboardCenter.shared.sceneDidChange(to: phase)
                }
        }
        // Registers the handler at launch, a launch into the background too.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }

    /// A team link opens its page; a game link with a team, the game's
    /// sheet over that page; the Home link, Home. Anything else is ignored.
    private func open(_ url: URL) {
        if WidgetDeepLink.isHome(url) {
            deepLinkedGame = nil
            deepLinkedTeamID = HomeTabs.homeID
        } else if let teamID = WidgetDeepLink.teamID(from: url) {
            deepLinkedGame = nil
            deepLinkedTeamID = teamID
        } else if let game = WidgetDeepLink.game(from: url), let teamID = game.teamID {
            deepLinkedGame = game
            deepLinkedTeamID = teamID
        }
    }
}

/// Background app refresh (R-1): with the app in the background, one look
/// at the favorites' live games per wake, so alerts, the widget and Live
/// Activities move without the app open.
///
/// iOS decides when each wake comes, from how the app is used; the time
/// asked for is only the earliest. Each run asks for the next: in
/// `LeagueScoreboardCenter.backgroundLiveInterval` while a favorite's game
/// is in the live window, else as the next one's window opens.
@MainActor
enum BackgroundRefresh {
    /// Listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let identifier = "PolarReailty.Hawk-Nation.scoreboard-refresh"

    /// With no favorite's game ahead in the seasons loaded, how long until a
    /// look anyway: a fixture may be added, or a season loaded.
    static let idleInterval: TimeInterval = 6 * 60 * 60

    /// One wake's work: the scoreboards of the favorites' live leagues, the
    /// alerts, widget and Live Activity changes they bring, and the next
    /// wake asked for.
    static func run() async {
        // A launch into the background mounts no view, so `MyTeamsApp`'s
        // `.task` may not have run. Each starts once, and the alerts
        // restore their last looks (`ScoreAlertMemory`).
        ScoreAlertEngine.shared.start()
        WidgetScoreboardWriter.shared.start()
        #if canImport(ActivityKit)
        LiveActivityManager.shared.start()
        #endif

        let center = LeagueScoreboardCenter.shared
        let next = await center.refreshFavoritesOnce()
        // The readers hear of the last change on a later turn; give them
        // one, then let their alerts and updates land before iOS suspends
        // the app.
        try? await Task.sleep(for: .seconds(1))
        await ScoreAlertEngine.shared.finishPosting()
        #if canImport(ActivityKit)
        await LiveActivityManager.shared.finishWork()
        #endif
        // Opened meanwhile: the foreground's following carries on.
        if UIApplication.shared.applicationState != .active {
            center.stopFollowingFavorites()
        }
        schedule(at: next)
    }

    /// Asks for the next wake no earlier than `date`, or `idleInterval` on
    /// without one. Replaces any wake asked for before.
    static func schedule(at date: Date?) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date ?? Date().addingTimeInterval(idleInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Refused in the Simulator, and with Background App Refresh off.
            logger.error("Could not schedule a background refresh: \(error.localizedDescription)")
        }
    }
}

extension LeagueScoreboardCenter {
    /// Follows the favorites (`startFollowingFavorites()`) from the moment
    /// the app is active until it goes to the background. A passing
    /// `.inactive` — the app switcher, a system sheet — changes nothing. In
    /// the background only `BackgroundRefresh` looks, once per wake.
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
