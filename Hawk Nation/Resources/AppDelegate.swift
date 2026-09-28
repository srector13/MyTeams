//
//  AppDelegate.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "push")

/// The UIKit callbacks SwiftUI has no scene API for: remote-notification
/// registration.
///
/// This is the seam for P4-e's server-sent score alerts. Registration is off
/// (`pushRegistrationEnabled`) until the server and the push entitlement
/// exist; until then only local alerts post (`ScoreAlertEngine`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Compile-time switch for asking APNs for a device token.
    static let pushRegistrationEnabled = false

    /// The last device token, hex, in the standard defaults.
    static let deviceTokenKey = "push.deviceToken"

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if Self.pushRegistrationEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("Registered for push: \(token, privacy: .private)")
        UserDefaults.standard.set(token, forKey: Self.deviceTokenKey)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Push registration failed: \(error.localizedDescription)")
    }
}
