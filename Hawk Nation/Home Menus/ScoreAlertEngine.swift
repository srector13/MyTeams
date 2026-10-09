//
//  ScoreAlertEngine.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import OSLog
#if canImport(UserNotifications)
import UserNotifications
#endif

private let logger = Logger(subsystem: "com.myTeams", category: "alerts")

/// Posts local alerts for the games of favorites that want them
/// (`FavoriteTeam.notify`): the start, each score, each period's end, and
/// the final.
///
/// Watches `LeagueScoreboardCenter.games` and, on each change, reduces the
/// followed games to `ScoreSnapshot`s, diffs them against the last look
/// (`ScoreDiff`) and posts what `ScoreAlertDebounce` lets through: one alert
/// per game per two minutes, but always the final. An event held back by
/// the window goes out, with the latest score, on the first look after it.
///
/// The reader's `AlertPreferences` apply on top (C-3): kinds turned off are
/// never posted, and during quiet hours alerts are delivered quietly
/// (`ScoreAlertDelivery.quiet`), to Notification Center only.
///
/// Hybrid limitation, accepted for now: the trigger is the scoreboard
/// center's polling, which follows every favorite's live games but runs only
/// while the app is in the foreground. With the app suspended or closed, no
/// alert fires. The server upgrade (P4-e: APNs pushes from a poller of our own)
/// replaces only that trigger source; `ScoreSnapshot`, `ScoreEvent` and the
/// debounce stay the event model on both sides.
///
/// Tapping an alert opens the favorite's page: each alert carries the
/// favorite's `WidgetDeepLink` (`request(for:teamID:)`), and the tap is
/// handed to `MyTeamsApp` through `ScoreAlertTaps`, as a widget's link is
/// through `onOpenURL`.
@MainActor
final class ScoreAlertEngine {
    static let shared = ScoreAlertEngine()

    private let center: LeagueScoreboardCenter
    private let favorites: @MainActor () -> [FavoriteTeam]
    private let now: @MainActor () -> Date
    /// The reader's kinds and quiet hours, read at each look.
    private let preferences: @MainActor () -> AlertPreferences
    /// Whether alerts may be posted now. Checked before each batch.
    private let isAuthorized: @Sendable () async -> Bool
    /// Posts one alert, for the favorite whose page a tap on it opens, as
    /// loud as quiet hours allow. Tests stand in a recorder for the
    /// system's center.
    private let deliver: @Sendable (ScoreEvent, TeamRef.ID?, ScoreAlertDelivery) async -> Void
    /// Waits until a held event's window ends (`scheduleRelease`).
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The last look at every followed game seen so far, by game id. Games
    /// that drop off a board keep their entry, so one that comes back is not
    /// taken for a new game. Memory only: a game's first look each launch
    /// seeds its entry without an alert (`ScoreDiff`), so a relaunch
    /// mid-game does not announce a start.
    private var snapshots: [String: ScoreSnapshot] = [:]
    /// The favorite each followed game was last seen for, by game id: the
    /// `TeamRef.id` in its home league, even for a cup tie.
    private var followers: [String: TeamRef.ID] = [:]
    private var debounce = ScoreAlertDebounce()
    /// Wakes when the first held event's window ends.
    private var releaseTask: Task<Void, Never>?
    private var isStarted = false

    init(
        center: LeagueScoreboardCenter = .shared,
        favorites: @escaping @MainActor () -> [FavoriteTeam] = { FavoritesStore.shared.favorites },
        now: @escaping @MainActor () -> Date = { Date() },
        preferences: @escaping @MainActor () -> AlertPreferences = { AlertPreferencesStore.shared.preferences },
        isAuthorized: @escaping @Sendable () async -> Bool = { await ScoreAlertEngine.systemIsAuthorized() },
        deliver: @escaping @Sendable (ScoreEvent, TeamRef.ID?, ScoreAlertDelivery) async -> Void = {
            await ScoreAlertEngine.systemDeliver($0, teamID: $1, delivery: $2)
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.center = center
        self.favorites = favorites
        self.now = now
        self.preferences = preferences
        self.isAuthorized = isAuthorized
        self.deliver = deliver
        self.sleep = sleep
    }

    /// Begins watching the scoreboards. Calling it again does nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if canImport(UserNotifications)
        // Alerts only fire while the app is open, so they must show there.
        // `AppDelegate` sets this at launch as well, for taps that launch the app.
        Self.presentAlerts()
        #endif
        observe()
    }

    /// Reads the games once and re-arms for their next change.
    private func observe() {
        let games = withObservationTracking {
            center.games
        } onChange: {
            // Called before the change lands; read it on the next turn.
            Task { @MainActor in
                self.observe()
            }
        }
        update(games)
    }

    private func update(_ games: [LeagueID: [ScoreboardGame]]) {
        let (current, followedBy) = followedSnapshots(in: games)
        let events = ScoreDiff.diff(previous: snapshots, current: current)
        snapshots.merge(current) { _, new in new }
        followers.merge(followedBy) { _, new in new }
        // Kinds turned off are dropped before the debounce, so they neither
        // take a game's window nor wait in it.
        let preferences = self.preferences()
        let wanted = events.filter { preferences.sends($0) }
        post(debounce.admit(wanted, at: now()), preferences: preferences)
        scheduleRelease()
    }

    /// Posts the held events whose window has ended, on the first look
    /// after it, or, should none come, when it ends: the center only
    /// publishes a change, and a board can sit unchanged through a break in
    /// play with a goal held.
    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = nil
        guard let due = debounce.nextRelease else { return }
        // A second's margin, so the wake lands past the window, not on it.
        let delay = max(0, due.timeIntervalSince(now())) + 1
        let sleep = self.sleep
        releaseTask = Task {
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            // Superseded by a later look, which scheduled its own.
            guard !Task.isCancelled else { return }
            self.releaseHeld()
        }
    }

    private func releaseHeld() {
        post(debounce.release(at: now()), preferences: preferences())
        scheduleRelease()
    }

    /// The games of every favorite that wants alerts, in its league and its
    /// cups, and the favorite each is followed for (the first, for two
    /// favorites playing each other).
    private func followedSnapshots(
        in games: [LeagueID: [ScoreboardGame]]
    ) -> (snapshots: [String: ScoreSnapshot], followers: [String: TeamRef.ID]) {
        var result: [String: ScoreSnapshot] = [:]
        var followers: [String: TeamRef.ID] = [:]
        for favorite in favorites() where favorite.notify {
            guard let team = TeamRef.parse(id: favorite.teamID) else { continue }
            let competitions = [team.league] + team.league.descriptor.cupCompetitions
            for competition in competitions {
                for game in games[competition] ?? [] {
                    guard game.competitors.contains(where: { $0.teamID == team.espnID }),
                          let snapshot = Self.snapshot(of: game, league: competition)
                    else { continue }
                    result[game.gameID] = snapshot
                    if followers[game.gameID] == nil {
                        followers[game.gameID] = favorite.teamID
                    }
                }
            }
        }
        return (result, followers)
    }

    /// A two-team game as the diff sees it. A game called off (`"post"`
    /// without `completed`) reads as not started, so it never goes final.
    ///
    /// - Parameter league: the league or cup whose scoreboard lists the
    ///   game, whose rules name its periods (`PeriodNaming`, A-11): "End of
    ///   OT" after a hockey overtime, not "End of 4th". Without one, periods
    ///   read as plain ordinals.
    nonisolated static func snapshot(of game: ScoreboardGame, league: LeagueID? = nil) -> ScoreSnapshot? {
        guard game.competitors.count == 2,
              let home = game.competitors.first(where: { $0.homeAway == "home" }),
              let away = game.competitors.first(where: { $0.homeAway == "away" })
        else { return nil }

        let state: ScoreSnapshot.State
        if game.state == "in" {
            state = .inProgress
        } else if game.state == "post" && game.completed {
            state = .final
        } else {
            state = .scheduled
        }

        return ScoreSnapshot(
            homeName: game.teamNames[home.teamID] ?? "Home",
            awayName: game.teamNames[away.teamID] ?? "Away",
            homeScore: home.score ?? 0,
            awayScore: away.score ?? 0,
            period: game.period,
            state: state,
            periodNaming: league.map(PeriodNaming.init(league:)) ?? .ordinal
        )
    }

    // MARK: Posting

    /// Posts `events`, quietly during the reader's quiet hours: still to
    /// Notification Center, so a final overnight is there in the morning,
    /// but without a sound or a banner.
    private func post(_ events: [ScoreEvent], preferences: AlertPreferences) {
        // Checked again here: a held event may be of a kind turned off
        // since it was held.
        let events = events.filter { preferences.sends($0) }
        guard !events.isEmpty else { return }
        let isAuthorized = self.isAuthorized
        let deliver = self.deliver
        let delivery: ScoreAlertDelivery = preferences.isQuiet(at: now()) ? .quiet : .standard
        let alerts = events.map { ($0, followers[$0.gameID]) }
        Task {
            // Denied or never asked: alerts stay off, silently.
            guard await isAuthorized() else { return }
            for (event, teamID) in alerts {
                await deliver(event, teamID, delivery)
            }
        }
    }

    /// The system's answer: `ScoreAlertsPermissions.isAuthorized()`.
    nonisolated static func systemIsAuthorized() async -> Bool {
        #if canImport(UserNotifications)
        return await ScoreAlertsPermissions.isAuthorized()
        #else
        return false
        #endif
    }

    /// Posts `event` through `UNUserNotificationCenter`, opening `teamID`'s
    /// page when tapped.
    nonisolated static func systemDeliver(_ event: ScoreEvent, teamID: TeamRef.ID?, delivery: ScoreAlertDelivery = .standard) async {
        #if canImport(UserNotifications)
        do {
            try await UNUserNotificationCenter.current().add(request(for: event, teamID: teamID, delivery: delivery))
        } catch {
            logger.error("Could not post a score alert: \(error.localizedDescription)")
        }
        #endif
    }

    /// The `userInfo` key of an alert's `WidgetDeepLink`, as a string.
    nonisolated static let teamLinkKey = "teamLink"

    /// The team whose page a tapped alert opens: the `TeamRef.id` its
    /// `userInfo` links to, or `nil` without a well-formed team link.
    nonisolated static func teamID(in userInfo: [AnyHashable: Any]) -> TeamRef.ID? {
        guard let link = userInfo[teamLinkKey] as? String,
              let url = URL(string: link)
        else { return nil }
        return WidgetDeepLink.teamID(from: url)
    }

    #if canImport(UserNotifications)
    /// The alert for `event`, threaded by game so one game's alerts group
    /// together, and linked to `teamID`'s page (`WidgetDeepLink`) when
    /// given. `teamID` is the favorite's own id, in its home league, so a
    /// cup tie's alert opens the team and not the cup.
    ///
    /// A quiet alert (quiet hours) is passive and silent: it goes to
    /// Notification Center without lighting the screen, sounding or showing
    /// a banner.
    nonisolated static func request(
        for event: ScoreEvent,
        teamID: TeamRef.ID? = nil,
        delivery: ScoreAlertDelivery = .standard
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.snapshot.summary
        switch delivery {
        case .standard:
            content.sound = .default
        case .quiet:
            content.sound = nil
            content.interruptionLevel = .passive
        }
        content.threadIdentifier = event.gameID
        if let url = teamID.flatMap(WidgetDeepLink.url(forTeamID:)) {
            content.userInfo = [teamLinkKey: url.absoluteString]
        }
        return UNNotificationRequest(
            identifier: "\(event.gameID).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }

    /// How an alert shows while the app is open: in Notification Center
    /// only for a quiet one (quiet hours), or for one about the team whose
    /// page is on screen (C-8) — the page already shows the score, so a
    /// banner over it says nothing new. Otherwise as a banner with sound.
    nonisolated static func presentationOptions(
        for content: UNNotificationContent,
        foregroundTeamID: TeamRef.ID?
    ) -> UNNotificationPresentationOptions {
        if content.interruptionLevel == .passive {
            return [.list]
        }
        if let foregroundTeamID, teamID(in: content.userInfo) == foregroundTeamID {
            return [.list]
        }
        return [.banner, .list, .sound]
    }

    nonisolated private static let presenter = ForegroundPresenter()

    /// Makes the app the notification center's delegate: alerts show while
    /// it is open, and taps reach `ScoreAlertTaps`. Early enough at launch
    /// (`AppDelegate`) that a tap which launched the app is not missed.
    nonisolated static func presentAlerts() {
        UNUserNotificationCenter.current().delegate = presenter
    }
    #else
    nonisolated static func presentAlerts() {}
    #endif
}

/// The team a tapped score alert asked for, until `MyTeamsApp` hands it to
/// `Home` — the notification's counterpart of a widget link's `onOpenURL`,
/// feeding the same `deepLinkedTeamID`.
@MainActor
@Observable
final class ScoreAlertTaps {
    static let shared = ScoreAlertTaps()

    var teamID: TeamRef.ID?
}

/// How loud a score alert is.
enum ScoreAlertDelivery: Equatable, Sendable {
    /// A banner and a sound.
    case standard
    /// During quiet hours: to Notification Center only, passive and silent.
    case quiet
}

/// The team whose page is on screen, for the alerts presenter (C-8), which
/// the system calls off the main actor. Locked, so any thread may read it.
///
/// Set by whoever owns the tab bar's selection, `nil` while no team page is
/// foremost: `Home` (`NavigationBar/TabBar.swift`) sets it from the tab
/// view's `.onChange(of: selection, initial: true)`, and leaves it `nil` on
/// the Home tab, so every alert shows as a banner there.
final class ScoreAlertForeground: @unchecked Sendable {
    static let shared = ScoreAlertForeground()

    private let lock = NSLock()
    private var storedTeamID: TeamRef.ID?

    var teamID: TeamRef.ID? {
        get { lock.withLock { storedTeamID } }
        set { lock.withLock { storedTeamID = newValue } }
    }
}

#if canImport(UserNotifications)
/// Shows alerts as banners while the app is open, which the system does not
/// do by default, except quiet ones and those for the team on screen
/// (`ScoreAlertEngine.presentationOptions`); and opens the team page of one
/// tapped.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        ScoreAlertEngine.presentationOptions(
            for: notification.request.content,
            foregroundTeamID: ScoreAlertForeground.shared.teamID
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let teamID = ScoreAlertEngine.teamID(in: response.notification.request.content.userInfo)
        else { return }
        await MainActor.run {
            ScoreAlertTaps.shared.teamID = teamID
        }
    }
}
#endif
