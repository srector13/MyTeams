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

/// The kinds of score alert a reader can turn off (C-3).
enum ScoreAlertKind: String, CaseIterable, Sendable {
    /// "Game started".
    case starts
    /// Each score, and each period's end, which reads as one.
    case scores
    case finals

    /// The kind of `event`.
    init(_ event: ScoreEvent) {
        switch event {
        case .gameStart: self = .starts
        case .scoreChange, .periodEnd: self = .scores
        case .final: self = .finals
        }
    }

    /// The toggle's title in the Alerts settings.
    var title: String {
        switch self {
        case .starts: "Game Starts"
        case .scores: "Score Updates"
        case .finals: "Finals"
        }
    }
}

/// The reader's choices for score alerts beyond each team's toggle (C-3):
/// which kinds go out, and quiet hours, when they still arrive in
/// Notification Center but without a sound or a banner.
///
/// Persisted as JSON (`AlertPreferencesStore`). Every field decodes to its
/// default when missing, so nothing stored, or a payload from an older
/// build, reads as every kind on and no quiet hours.
struct AlertPreferences: Codable, Equatable, Sendable {
    static let minutesPerDay = 24 * 60

    var sendsStarts = true
    var sendsScores = true
    var sendsFinals = true

    var quietHoursEnabled = false
    /// When quiet hours begin and end, in minutes after local midnight. The
    /// window runs across midnight when the end is earlier than the start;
    /// a window that ends where it starts is empty.
    var quietStart = 22 * 60
    var quietEnd = 7 * 60

    /// Whether alerts of `kind` go out.
    func sends(_ kind: ScoreAlertKind) -> Bool {
        switch kind {
        case .starts: sendsStarts
        case .scores: sendsScores
        case .finals: sendsFinals
        }
    }

    /// Whether `event`'s kind goes out.
    func sends(_ event: ScoreEvent) -> Bool {
        sends(ScoreAlertKind(event))
    }

    mutating func setSends(_ sends: Bool, for kind: ScoreAlertKind) {
        switch kind {
        case .starts: sendsStarts = sends
        case .scores: sendsScores = sends
        case .finals: sendsFinals = sends
        }
    }

    /// Whether `date` falls in quiet hours, read on `calendar`'s clock.
    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let start = Self.normalized(quietStart)
        let end = Self.normalized(quietEnd)
        guard start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start < end {
            return minute >= start && minute < end
        }
        // Across midnight: 22:00 to 07:00.
        return minute >= start || minute < end
    }

    /// `minutes` as a time of day, 0 to 1439.
    static func normalized(_ minutes: Int) -> Int {
        let remainder = minutes % minutesPerDay
        return remainder < 0 ? remainder + minutesPerDay : remainder
    }
}

extension AlertPreferences {
    // In an extension, so the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlertPreferences()
        sendsStarts = try container.decodeIfPresent(Bool.self, forKey: .sendsStarts) ?? defaults.sendsStarts
        sendsScores = try container.decodeIfPresent(Bool.self, forKey: .sendsScores) ?? defaults.sendsScores
        sendsFinals = try container.decodeIfPresent(Bool.self, forKey: .sendsFinals) ?? defaults.sendsFinals
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? defaults.quietHoursEnabled
        quietStart = Self.normalized(try container.decodeIfPresent(Int.self, forKey: .quietStart) ?? defaults.quietStart)
        quietEnd = Self.normalized(try container.decodeIfPresent(Int.self, forKey: .quietEnd) ?? defaults.quietEnd)
    }
}

/// Keeps `AlertPreferences` in `defaults`, for the Alerts settings to edit
/// and `ScoreAlertEngine` to read before each batch.
@MainActor
@Observable
final class AlertPreferencesStore {
    static let shared = AlertPreferencesStore()
    static let defaultsKey = "alerts.preferences"

    private(set) var preferences: AlertPreferences

    private let defaults: UserDefaults

    /// Kept in `defaults`: the standard ones in the app, a scratch suite in
    /// tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Self.load(from: defaults)
    }

    /// What `defaults` holds; the defaults for nothing stored, or for a
    /// payload that does not read.
    static func load(from defaults: UserDefaults) -> AlertPreferences {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(AlertPreferences.self, from: data)
        else { return AlertPreferences() }
        return stored
    }

    /// Changes the preferences and writes them through.
    func update(_ change: (inout AlertPreferences) -> Void) {
        var next = preferences
        change(&next)
        guard next != preferences else { return }
        preferences = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.defaultsKey)
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
