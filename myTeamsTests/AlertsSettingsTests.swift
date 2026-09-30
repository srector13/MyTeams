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
    }

    @Test("Granted offers nothing")
    func grantedRow() {
        let row = AlertsStatusRow.notifications(.granted)
        #expect(row.action == nil)
        #expect(row.actionTitle == nil)
        #expect(row.actionAccessibilityLabel == nil)
        #expect(row.title == "Notifications On")
    }

    @Test("Live Activities off offers Settings with a note; on offers nothing")
    func liveActivitiesRows() {
        let off = AlertsStatusRow.liveActivities(enabled: false)
        #expect(off.action == .openSettings)
        #expect(off.actionAccessibilityLabel == "Open Settings to turn on Live Activities")
        #expect(off.detail.contains("Settings"))
        let on = AlertsStatusRow.liveActivities(enabled: true)
        #expect(on.action == nil)
        #expect(on.title == "Live Activities On")
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
