//
//  AlertsSettings.swift
//  myTeams
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation
import UserNotifications

/// The reader's answer to the score alerts prompt, as the Alerts settings
/// show it.
enum AlertPermission: Equatable, Sendable {
    /// Never asked.
    case notDetermined
    /// Asked and declined, or turned off in Settings.
    case denied
    /// Alerts may be posted.
    case granted

    /// Provisional and ephemeral authorizations post alerts too, so they
    /// read as granted.
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized, .provisional, .ephemeral:
            self = .granted
        default:
            self = .denied
        }
    }
}

/// What a status row's button does.
enum AlertsSettingsAction: Equatable, Sendable {
    /// Show the system prompt.
    case ask
    /// Open the app's page in Settings, the only place a denial is undone.
    case openSettings
}

/// How a status row's symbol is coloured, so "off" doesn't look like "on"
/// (A-1). The view maps it to a style; this file stays free of SwiftUI.
enum AlertsStatusTint: Equatable, Sendable {
    /// The app's tint: set up, or not yet asked.
    case standard
    /// Red: turned off, and only Settings can turn it back on.
    case off
}

/// One status row of the Alerts settings: what it says, and what its button
/// (if any) does.
struct AlertsStatusRow: Equatable, Sendable {
    /// What the row is about, in a sentence: "notifications".
    var subject: String
    var title: String
    var detail: String
    var systemImage: String
    var action: AlertsSettingsAction?
    var tint: AlertsStatusTint = .standard

    /// The button's title for `action`.
    var actionTitle: String? {
        switch action {
        case .ask: "Ask Now"
        case .openSettings: "Open Settings"
        case nil: nil
        }
    }

    /// What VoiceOver reads for the button.
    var actionAccessibilityLabel: String? {
        switch action {
        case .ask: "Allow \(subject)"
        case .openSettings: "Open Settings to turn on \(subject)"
        case nil: nil
        }
    }

    /// The score alerts row for a permission state.
    static func notifications(_ permission: AlertPermission) -> AlertsStatusRow {
        switch permission {
        case .notDetermined:
            AlertsStatusRow(
                subject: "notifications",
                title: "Notifications",
                detail: "Not set up yet. Allow notifications to get alerts for the teams below.",
                systemImage: "bell.badge",
                action: .ask
            )
        case .denied:
            AlertsStatusRow(
                subject: "notifications",
                title: "Notifications Off",
                detail: "Alerts are turned off for myTeams. Turn on notifications in Settings to get them.",
                systemImage: "bell.slash",
                action: .openSettings,
                tint: .off
            )
        case .granted:
            AlertsStatusRow(
                subject: "notifications",
                title: "Notifications On",
                detail: "Alerts arrive for each team turned on below.",
                systemImage: "bell.fill",
                action: nil
            )
        }
    }

    /// The Live Activities row, for whether the system allows them.
    static func liveActivities(enabled: Bool) -> AlertsStatusRow {
        if enabled {
            AlertsStatusRow(
                subject: "Live Activities",
                title: "Live Activities On",
                detail: "Games under way appear on the Lock Screen and in the Dynamic Island, teams with alerts on first.",
                systemImage: "platter.filled.bottom.iphone",
                action: nil
            )
        } else {
            AlertsStatusRow(
                subject: "Live Activities",
                title: "Live Activities Off",
                detail: "Live scores cannot appear on the Lock Screen. Turn on Live Activities for myTeams in Settings.",
                systemImage: "platter.filled.bottom.iphone",
                action: .openSettings,
                tint: .off
            )
        }
    }
}

/// The state behind the Alerts settings, with the system behind closures so
/// tests can stand in for it.
@MainActor
@Observable
final class AlertsSettingsModel {
    /// The score alerts permission, once read.
    private(set) var permission: AlertPermission?
    /// Whether the system allows Live Activities.
    private(set) var activitiesEnabled = true

    private let readPermission: @MainActor () async -> AlertPermission
    private let requestPermission: @MainActor () async -> Void
    private let readActivitiesEnabled: @MainActor () -> Bool
    private let openSettings: @MainActor () -> Void

    init(
        readPermission: @escaping @MainActor () async -> AlertPermission,
        requestPermission: @escaping @MainActor () async -> Void,
        readActivitiesEnabled: @escaping @MainActor () -> Bool,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.readPermission = readPermission
        self.requestPermission = requestPermission
        self.readActivitiesEnabled = readActivitiesEnabled
        self.openSettings = openSettings
    }

    /// The score alerts row; `nil` until the permission has been read.
    var notificationsRow: AlertsStatusRow? {
        permission.map(AlertsStatusRow.notifications)
    }

    var liveActivitiesRow: AlertsStatusRow {
        .liveActivities(enabled: activitiesEnabled)
    }

    /// Reads both settings again. Called on appearing and on each return to
    /// the foreground, since either can change in Settings.
    func refresh() async {
        activitiesEnabled = readActivitiesEnabled()
        permission = await readPermission()
    }

    /// Carries out a row's button.
    func perform(_ action: AlertsSettingsAction) async {
        switch action {
        case .ask:
            // Only an undetermined status can show the prompt; otherwise
            // asking does nothing, so read it first.
            if await readPermission() == .notDetermined {
                await requestPermission()
            }
            await refresh()
        case .openSettings:
            openSettings()
        }
    }
}
