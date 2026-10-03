//
//  ScoreAlertsPermissions.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.myTeams", category: "alerts")

/// Permission to post score alerts (`ScoreAlertEngine`).
///
/// Asked for when the reader follows a team that wants alerts
/// (`FavoriteTeam.notify`), or taps "Ask Now" in the Alerts settings, never
/// at launch. The system shows its prompt only while the status is
/// undetermined, so the reader is asked at most once; after a denial the
/// Alerts settings point to Settings instead.
enum ScoreAlertsPermissions {
    /// The reader's current answer.
    static func permission() async -> AlertPermission {
        AlertPermission(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// Shows the system prompt if the reader has never answered it.
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            logger.info("Score alerts \(granted ? "allowed" : "declined")")
        } catch {
            logger.error("Could not ask for score alerts: \(error.localizedDescription)")
        }
    }

    /// Whether alerts may be posted now. Denied or undetermined reads as no.
    static func isAuthorized() async -> Bool {
        await permission() == .granted
    }
}
