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
/// per game per two minutes, but always the final.
///
/// Hybrid limitation, accepted for now: the trigger is the scoreboard
/// center's polling, which runs only while the app is in the foreground and a
/// team page wants a live day. With the app suspended or closed, no alert
/// fires. The server upgrade (P4-e: APNs pushes from a poller of our own)
/// replaces only that trigger source; `ScoreSnapshot`, `ScoreEvent` and the
/// debounce stay the event model on both sides.
@MainActor
final class ScoreAlertEngine {
    static let shared = ScoreAlertEngine()

    private let center: LeagueScoreboardCenter
    private let favorites: @MainActor () -> [FavoriteTeam]
    private let now: @MainActor () -> Date
    /// Whether alerts may be posted now. Checked before each batch.
    private let isAuthorized: @Sendable () async -> Bool
    /// Posts one alert. Tests stand in a recorder for the system's center.
    private let deliver: @Sendable (ScoreEvent) async -> Void

    /// The last look at every followed game seen so far, by game id. Games
    /// that drop off a board keep their entry, so one that comes back is not
    /// taken for a new game.
    private var snapshots: [String: ScoreSnapshot] = [:]
    private var debounce = ScoreAlertDebounce()
    private var isStarted = false
    #if canImport(UserNotifications)
    private let presenter = ForegroundPresenter()
    #endif

    init(
        center: LeagueScoreboardCenter = .shared,
        favorites: @escaping @MainActor () -> [FavoriteTeam] = { FavoritesStore.shared.favorites },
        now: @escaping @MainActor () -> Date = { Date() },
        isAuthorized: @escaping @Sendable () async -> Bool = { await ScoreAlertEngine.systemIsAuthorized() },
        deliver: @escaping @Sendable (ScoreEvent) async -> Void = { await ScoreAlertEngine.systemDeliver($0) }
    ) {
        self.center = center
        self.favorites = favorites
        self.now = now
        self.isAuthorized = isAuthorized
        self.deliver = deliver
    }

    /// Begins watching the scoreboards. Calling it again does nothing.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if canImport(UserNotifications)
        // Alerts only fire while the app is open, so they must show there.
        UNUserNotificationCenter.current().delegate = presenter
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
        let current = followedSnapshots(in: games)
        let events = ScoreDiff.diff(previous: snapshots, current: current)
        snapshots.merge(current) { _, new in new }
        post(debounce.admit(events, at: now()))
    }

    /// The games of every favorite that wants alerts, in its league and its
    /// cups.
    private func followedSnapshots(in games: [LeagueID: [ScoreboardGame]]) -> [String: ScoreSnapshot] {
        var result: [String: ScoreSnapshot] = [:]
        for favorite in favorites() where favorite.notify {
            guard let team = TeamRef.parse(id: favorite.teamID) else { continue }
            let competitions = [team.league] + team.league.descriptor.cupCompetitions
            for competition in competitions {
                for game in games[competition] ?? [] {
                    guard game.competitors.contains(where: { $0.teamID == team.espnID }),
                          let snapshot = Self.snapshot(of: game)
                    else { continue }
                    result[game.gameID] = snapshot
                }
            }
        }
        return result
    }

    /// A two-team game as the diff sees it. A game called off (`"post"`
    /// without `completed`) reads as not started, so it never goes final.
    nonisolated static func snapshot(of game: ScoreboardGame) -> ScoreSnapshot? {
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
            state: state
        )
    }

    // MARK: Posting

    private func post(_ events: [ScoreEvent]) {
        guard !events.isEmpty else { return }
        let isAuthorized = self.isAuthorized
        let deliver = self.deliver
        Task {
            // Denied or never asked: alerts stay off, silently.
            guard await isAuthorized() else { return }
            for event in events {
                await deliver(event)
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

    /// Posts `event` through `UNUserNotificationCenter`.
    nonisolated static func systemDeliver(_ event: ScoreEvent) async {
        #if canImport(UserNotifications)
        do {
            try await UNUserNotificationCenter.current().add(request(for: event))
        } catch {
            logger.error("Could not post a score alert: \(error.localizedDescription)")
        }
        #endif
    }

    #if canImport(UserNotifications)
    /// The alert for `event`, threaded by game so one game's alerts group
    /// together.
    nonisolated static func request(for event: ScoreEvent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.snapshot.summary
        content.sound = .default
        content.threadIdentifier = event.gameID
        return UNNotificationRequest(
            identifier: "\(event.gameID).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
    }
    #endif
}

#if canImport(UserNotifications)
/// Shows alerts as banners while the app is open, which the system does not
/// do by default.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
#endif
