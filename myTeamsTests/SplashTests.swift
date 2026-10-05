//
//  SplashTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// The launch screen Info.plist describes, and the splash overlay that
/// takes over from it (`SplashView`, `SplashCoordinator`).
@Suite("Splash")
struct SplashTests {
    @Test("The launch screen centres the logo on the launch colour")
    func launchScreenNamesLogoAndColour() throws {
        // The tests run hosted in the app, so this is the app's Info.plist.
        let launchScreen = try #require(Bundle.main.infoDictionary?["UILaunchScreen"] as? [String: Any])
        #expect(launchScreen["UIColorName"] as? String == "LaunchscreenColor")
        #expect(launchScreen["UIImageName"] as? String == "myTeamsLogo")
    }

    @Test("The logo the launch screen and splash name is in the asset catalog")
    func logoResolves() {
        #expect(UIImage(named: "myTeamsLogo") != nil)
    }

    @Test("The splash starts up and goes for good on dismiss, with or without Reduce Motion")
    @MainActor
    func coordinatorDismisses() {
        for reduceMotion in [false, true] {
            let coordinator = SplashCoordinator()
            #expect(coordinator.isVisible)
            coordinator.dismiss(reduceMotion: reduceMotion)
            #expect(!coordinator.isVisible)
            coordinator.dismiss(reduceMotion: reduceMotion)
            #expect(!coordinator.isVisible)
        }
    }
}
