//
//  AlertsSettingsTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UserNotifications

@testable import myTeams

/// Stands in for the notification center, ActivityKit and the Settings app.
@MainActor
private final class FakeSystem {
    var permission: AlertPermission
    var activitiesEnabled: Bool
    /// What the prompt answers, if shown.
    var answer: AlertPermission = .granted
    private(set) var prompts = 0
    private(set) var settingsOpened = 0

    init(permission: AlertPermission, activitiesEnabled: Bool = true) {
        self.permission = permission
        self.activitiesEnabled = activitiesEnabled
    }

    func model() -> AlertsSettingsModel {
        AlertsSettingsModel(
            readPermission: { self.permission },
            requestPermission: {
                self.prompts += 1
                self.permission = self.answer
            },
            readActivitiesEnabled: { self.activitiesEnabled },
            openSettings: { self.settingsOpened += 1 }
        )
    }
}

@Suite("Alerts settings")
struct AlertsSettingsTests {
    // MARK: Mapping

    @Test("Each authorization status maps to a permission", arguments: [
        (UNAuthorizationStatus.notDetermined, AlertPermission.notDetermined),
        (.denied, .denied),
        (.authorized, .granted),
        (.provisional, .granted),
        (.ephemeral, .granted),
    ])
    func mapsStatus(status: UNAuthorizationStatus, expected: AlertPermission) {
        #expect(AlertPermission(status) == expected)
    }

    @Test("Not asked yet offers to ask")
    func notDeterminedRow() {
        let row = AlertsStatusRow.notifications(.notDetermined)
        #expect(row.action == .ask)
        #expect(row.actionTitle == "Ask Now")
        #expect(row.actionAccessibilityLabel == "Allow notifications")
    }

    @Test("Denied offers Settings")
    func deniedRow() {
        let row = AlertsStatusRow.notifications(.denied)
        #expect(row.action == .openSettings)
        #expect(row.actionTitle == "Open Settings")
        #expect(row.actionAccessibilityLabel == "Open Settings to turn on notifications")
        #expect(row.title == "Notifications Off")
        #expect(row.tint == .off)
    }

    @Test("Granted offers nothing")
    func grantedRow() {
        let row = AlertsStatusRow.notifications(.granted)
        #expect(row.action == nil)
        #expect(row.actionTitle == nil)
        #expect(row.actionAccessibilityLabel == nil)
        #expect(row.title == "Notifications On")
        #expect(row.tint == .standard)
    }

    @Test("Live Activities off offers Settings with a note; on offers nothing")
    func liveActivitiesRows() {
        let off = AlertsStatusRow.liveActivities(enabled: false)
        #expect(off.action == .openSettings)
        #expect(off.actionAccessibilityLabel == "Open Settings to turn on Live Activities")
        #expect(off.detail.contains("Settings"))
        #expect(off.tint == .off)
        let on = AlertsStatusRow.liveActivities(enabled: true)
        #expect(on.action == nil)
        #expect(on.title == "Live Activities On")
        #expect(on.tint == .standard)
    }

    // MARK: Model

    @MainActor
    @Test("Refreshing reads both settings", arguments: [AlertPermission.notDetermined, .denied, .granted])
    func refreshReads(permission: AlertPermission) async {
        let system = FakeSystem(permission: permission, activitiesEnabled: false)
        let model = system.model()
        #expect(model.notificationsRow == nil)

        await model.refresh()
        #expect(model.permission == permission)
        #expect(model.notificationsRow == .notifications(permission))
        #expect(!model.activitiesEnabled)
        #expect(model.liveActivitiesRow == .liveActivities(enabled: false))

        // Changed in Settings, then back in the foreground.
        system.activitiesEnabled = true
        system.permission = .granted
        await model.refresh()
        #expect(model.notificationsRow?.action == nil)
        #expect(model.liveActivitiesRow.action == nil)
        #expect(system.prompts == 0)
        #expect(system.settingsOpened == 0)
    }

    @MainActor
    @Test("Asking shows the prompt once and shows the answer", arguments: [AlertPermission.granted, .denied])
    func askPrompts(answer: AlertPermission) async {
        let system = FakeSystem(permission: .notDetermined)
        system.answer = answer
        let model = system.model()
        await model.refresh()
        #expect(model.notificationsRow?.action == .ask)

        await model.perform(.ask)
        #expect(system.prompts == 1)
        #expect(model.permission == answer)
        let expected: AlertsSettingsAction? = answer == .granted ? nil : .openSettings
        #expect(model.notificationsRow?.action == expected)

        // Answered: asking again shows nothing.
        await model.perform(.ask)
        #expect(system.prompts == 1)
    }

    @MainActor
    @Test("Asking once answered shows no prompt", arguments: [AlertPermission.denied, .granted])
    func askWhenAnswered(permission: AlertPermission) async {
        let system = FakeSystem(permission: permission)
        let model = system.model()
        await model.perform(.ask)
        #expect(system.prompts == 0)
        #expect(model.permission == permission)
    }

    @MainActor
    @Test("Open Settings opens Settings and asks nothing")
    func openSettings() async {
        let system = FakeSystem(permission: .denied, activitiesEnabled: false)
        let model = system.model()
        await model.refresh()
        #expect(model.notificationsRow?.action == .openSettings)
        #expect(model.liveActivitiesRow.action == .openSettings)

        await model.perform(.openSettings)
        #expect(system.settingsOpened == 1)
        #expect(system.prompts == 0)
    }
}

@Suite("Alert preferences: kinds and quiet hours")
struct AlertPreferencesTests {
    /// A clock on UTC, so times of day don't depend on the machine's zone.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// `hour`:`minute` UTC on 1 January 1970.
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval((hour * 60 + minute) * 60))
    }

    private let snapshot = ScoreSnapshot(
        homeName: "Kansas", awayName: "K-State", homeScore: 7, awayScore: 3, period: 2, state: .inProgress
    )

    @Test("By default every kind goes out and there are no quiet hours")
    func defaults() {
        let preferences = AlertPreferences()
        for kind in ScoreAlertKind.allCases {
            #expect(preferences.sends(kind))
        }
        #expect(!preferences.quietHoursEnabled)
        #expect(!preferences.isQuiet(at: time(23), calendar: utc))
    }

    @Test("Nothing stored, or an older payload, decodes with the defaults for what it lacks")
    func backwardCompatibleDecoding() throws {
        let empty = try JSONDecoder().decode(AlertPreferences.self, from: Data("{}".utf8))
        #expect(empty == AlertPreferences())

        let partial = try JSONDecoder().decode(
            AlertPreferences.self, from: Data(#"{"sendsScores":false,"someLaterField":1}"#.utf8)
        )
        var expected = AlertPreferences()
        expected.sendsScores = false
        #expect(partial == expected)

        // Out-of-range times are read as times of day.
        let wrapped = try JSONDecoder().decode(
            AlertPreferences.self, from: Data(#"{"quietStart":1500,"quietEnd":-60}"#.utf8)
        )
        #expect(wrapped.quietStart == 60)
        #expect(wrapped.quietEnd == 23 * 60)
    }

    @Test("Preferences round-trip through JSON")
    func roundTrip() throws {
        let preferences = AlertPreferences(
            sendsStarts: false, sendsScores: true, sendsFinals: true,
            quietHoursEnabled: true, quietStart: 23 * 60 + 30, quietEnd: 6 * 60
        )
        let decoded = try JSONDecoder().decode(AlertPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded == preferences)
    }

    @Test("Each event has its kind; a period's end counts as a score update")
    func kinds() {
        #expect(ScoreAlertKind(.gameStart(gameID: "1", snapshot: snapshot)) == .starts)
        #expect(ScoreAlertKind(.scoreChange(gameID: "1", previous: snapshot, snapshot: snapshot)) == .scores)
        #expect(ScoreAlertKind(.periodEnd(gameID: "1", period: 1, snapshot: snapshot)) == .scores)
        #expect(ScoreAlertKind(.final(gameID: "1", snapshot: snapshot)) == .finals)
        #expect(ScoreAlertKind(.closeLate(gameID: "1", snapshot: snapshot)) == .closeGames)
        #expect(ScoreAlertKind(.overtime(gameID: "1", snapshot: snapshot)) == .closeGames)
    }

    @Test("Each kind has its own bit, and the preferences read as the kinds they send")
    func masks() {
        let bits = ScoreAlertKind.allCases.map(\.mask)
        #expect(Set(bits.map(\.rawValue)).count == ScoreAlertKind.allCases.count)
        #expect(AlertPreferences().kinds == [.starts, .scores, .finals, .closeGames])
        var preferences = AlertPreferences()
        preferences.setSends(false, for: .scores)
        preferences.setSends(false, for: .closeGames)
        #expect(preferences.kinds == [.starts, .finals])
        #expect(!preferences.sendsCloseGames)
    }

    @Test("A team's own kinds take precedence over the global ones; without them, the global ones apply")
    func teamKindsPrecedence() {
        var global = AlertPreferences()
        global.setSends(false, for: .finals)
        let score = ScoreEvent.scoreChange(gameID: "1", previous: snapshot, snapshot: snapshot)
        let final = ScoreEvent.final(gameID: "1", snapshot: snapshot)
        let closeLate = ScoreEvent.closeLate(gameID: "1", snapshot: snapshot)

        // Finals only, for this team: finals go though they're off globally.
        #expect(global.sends(final, teamKinds: .finals))
        #expect(!global.sends(score, teamKinds: .finals))
        #expect(!global.sends(closeLate, teamKinds: .finals))
        // Following the global kinds.
        #expect(!global.sends(final, teamKinds: nil))
        #expect(global.sends(score, teamKinds: nil))
        // Off: nothing.
        #expect(!global.sends(score, teamKinds: AlertMask()))
    }

    @Test("A game two favorites follow alerts for whatever either wants")
    func followedKinds() {
        var global = AlertPreferences()
        global.setSends(false, for: .scores)
        let score = ScoreEvent.scoreChange(gameID: "1", previous: snapshot, snapshot: snapshot)
        let start = ScoreEvent.gameStart(gameID: "1", snapshot: snapshot)
        let final = ScoreEvent.final(gameID: "1", snapshot: snapshot)

        var kinds = FollowedKinds()
        kinds.add(.finals)
        #expect(kinds.sends(final, preferences: global))
        #expect(!kinds.sends(start, preferences: global))
        // A second favorite on the global kinds adds starts, not scores.
        kinds.add(nil)
        #expect(kinds.sends(start, preferences: global))
        #expect(!kinds.sends(score, preferences: global))
        // A third with scores of its own adds them.
        kinds.add(.scores)
        #expect(kinds.sends(score, preferences: global))
    }

    @Test("A payload from before close-game alerts reads them as on")
    func closeGamesDefault() throws {
        let older = try JSONDecoder().decode(
            AlertPreferences.self, from: Data(#"{"sendsStarts":true,"sendsScores":true,"sendsFinals":false}"#.utf8)
        )
        #expect(older.sendsCloseGames)
        #expect(!older.sendsFinals)
    }

    @Test("Finals only: starts and scores are filtered out")
    func finalsOnly() {
        var preferences = AlertPreferences()
        preferences.setSends(false, for: .starts)
        preferences.setSends(false, for: .scores)
        let events: [ScoreEvent] = [
            .gameStart(gameID: "1", snapshot: snapshot),
            .scoreChange(gameID: "1", previous: snapshot, snapshot: snapshot),
            .periodEnd(gameID: "1", period: 1, snapshot: snapshot),
            .final(gameID: "1", snapshot: snapshot),
        ]
        let sent = events.filter { preferences.sends($0) }
        #expect(sent == [.final(gameID: "1", snapshot: snapshot)])
        #expect(!preferences.sendsStarts)
        #expect(!preferences.sendsScores)
        #expect(preferences.sendsFinals)
    }

    @Test("Quiet hours across midnight: 22:00 to 07:00")
    func overnight() {
        var preferences = AlertPreferences()
        preferences.quietHoursEnabled = true
        preferences.quietStart = 22 * 60
        preferences.quietEnd = 7 * 60
        #expect(preferences.isQuiet(at: time(22), calendar: utc))
        #expect(preferences.isQuiet(at: time(23, 30), calendar: utc))
        #expect(preferences.isQuiet(at: time(0), calendar: utc))
        #expect(preferences.isQuiet(at: time(6, 59), calendar: utc))
        #expect(!preferences.isQuiet(at: time(7), calendar: utc))
        #expect(!preferences.isQuiet(at: time(12), calendar: utc))
        #expect(!preferences.isQuiet(at: time(21, 59), calendar: utc))

        // Off, the window says nothing.
        preferences.quietHoursEnabled = false
        #expect(!preferences.isQuiet(at: time(23, 30), calendar: utc))
    }

    @Test("Quiet hours within a day, and a window that ends where it starts")
    func sameDay() {
        var preferences = AlertPreferences()
        preferences.quietHoursEnabled = true
        preferences.quietStart = 13 * 60
        preferences.quietEnd = 14 * 60
        #expect(!preferences.isQuiet(at: time(12, 59), calendar: utc))
        #expect(preferences.isQuiet(at: time(13), calendar: utc))
        #expect(preferences.isQuiet(at: time(13, 59), calendar: utc))
        #expect(!preferences.isQuiet(at: time(14), calendar: utc))

        preferences.quietEnd = 13 * 60
        #expect(!preferences.isQuiet(at: time(13), calendar: utc))
    }

    // MARK: Store

    private func scratchDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "AlertPreferencesTests.\(UUID().uuidString)"))
    }

    @MainActor
    @Test("The store starts at the defaults, writes changes through, and a new store reads them")
    func store() throws {
        let defaults = try scratchDefaults()
        let store = AlertPreferencesStore(defaults: defaults)
        #expect(store.preferences == AlertPreferences())

        store.update {
            $0.quietHoursEnabled = true
            $0.setSends(false, for: .scores)
        }
        #expect(store.preferences.quietHoursEnabled)
        #expect(!store.preferences.sendsScores)

        let relaunched = AlertPreferencesStore(defaults: defaults)
        #expect(relaunched.preferences == store.preferences)
    }

    @MainActor
    @Test("A stored payload that doesn't read falls back to the defaults")
    func unreadableStore() throws {
        let defaults = try scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: AlertPreferencesStore.defaultsKey)
        #expect(AlertPreferencesStore.load(from: defaults) == AlertPreferences())
    }
}
