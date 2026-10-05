//
//  SplashTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
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

    @Test("The splash draws the logo at the launch screen's size, the asset's point width")
    func splashMatchesLaunchScreen() throws {
        // The launch screen draws the image at its natural point size; the
        // splash must match it or the logo jumps at the hand-off (B-5).
        let logo = try #require(UIImage(named: "myTeamsLogo"))
        #expect(abs(logo.size.width - BrandLogo.launch) < 1)
    }

    @Test("One set of brand logo sizes")
    func brandLogoSizes() {
        #expect(BrandLogo.bar == 20)
        #expect(BrandLogo.inline == 120)
        #expect(BrandLogo.hero == 160)
        #expect(BrandLogo.bar < BrandLogo.inline && BrandLogo.inline < BrandLogo.hero)
    }

    @Test("The reader's appearance waits for the splash to go; the splash keeps the system's")
    func appearanceAfterSplash() {
        for preferred in [nil, ColorScheme.light, .dark] {
            #expect(SplashCoordinator.colorScheme(preferred: preferred, splashVisible: true) == nil)
            #expect(SplashCoordinator.colorScheme(preferred: preferred, splashVisible: false) == preferred)
        }
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
