//
//  GlassUIScreenshotTests.swift
//  myTeamsUITests
//
//  Created by Stephen Rector on 10/3/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import XCTest

/// The GlassUI verification harness (docs/UI_AUDIT_IOS27_GLASSUI.md §4,
/// Phase 0 step 0.7): the reachable screens, screenshotted at each Dynamic
/// Type size × appearance × accessibility setting in `matrix`, as named
/// attachments in the result bundle.
///
/// Opt-in, so the gate stays fast: runs only with `GLASSUI_SCREENSHOTS=1` in
/// the test runner's environment. From the command line, prefix the variable
/// with `TEST_RUNNER_`, which xcodebuild forwards to the runner:
///
///     TEST_RUNNER_GLASSUI_SCREENSHOTS=1 xcodebuild test -project myTeams.xcodeproj \
///       -scheme myTeams -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:myTeamsUITests/GlassUIScreenshotTests -resultBundlePath glassui.xcresult
final class GlassUIScreenshotTests: XCTestCase {

    // MARK: Knobs

    /// Dynamic Type sizes, as the `UIPreferredContentSizeCategoryName` the
    /// app reads from its launch arguments.
    enum TypeSize: String, CaseIterable {
        case large = "UICTContentSizeCategoryL"
        case xxxLarge = "UICTContentSizeCategoryXXXL"
        /// SwiftUI's `.accessibility3` is UIKit's `.accessibilityExtraLarge`.
        case accessibility3 = "UICTContentSizeCategoryAccessibilityXL"

        var label: String {
            switch self {
            case .large: "L"
            case .xxxLarge: "XXXL"
            case .accessibility3: "AX3"
            }
        }
    }

    /// The axes of the matrix. Each is a one-line switch: add a value to
    /// widen the pass.
    static let typeSizes = TypeSize.allCases
    static let darkModes = [false, true]
    // XCUITest can't toggle Increase Contrast, Reduce Transparency or
    // Reduce Motion in-process (they're `xcrun simctl ui` / Settings knobs
    // on the host), so the app stands them in from the launch environment
    // keys below (`Theme.LaunchAccessibility`). The full matrix leaves them
    // off to stay bounded; `accessibilityVariants` covers them on the main
    // screens. Add `true` here to widen the whole pass.
    static let increaseContrastModes = [false]
    static let reduceTransparencyModes = [false]
    static let reduceMotionModes = [false]

    /// Each accessibility setting on its own, at the default text size in
    /// both appearances, for the main screens (`captureMainScreens`).
    static var accessibilityVariants: [Configuration] {
        darkModes.flatMap { dark in
            [
                Configuration(typeSize: .large, dark: dark, increaseContrast: true, reduceTransparency: false, reduceMotion: false),
                Configuration(typeSize: .large, dark: dark, increaseContrast: false, reduceTransparency: true, reduceMotion: false),
                Configuration(typeSize: .large, dark: dark, increaseContrast: false, reduceTransparency: false, reduceMotion: true),
            ]
        }
    }

    struct Configuration {
        var typeSize: TypeSize
        var dark: Bool
        var increaseContrast: Bool
        var reduceTransparency: Bool
        var reduceMotion: Bool

        /// Stamped on every screenshot, e.g. `AX3-dark-hc`.
        var name: String {
            var parts = [typeSize.label, dark ? "dark" : "light"]
            if increaseContrast { parts.append("hc") }
            if reduceTransparency { parts.append("rt") }
            if reduceMotion { parts.append("rm") }
            return parts.joined(separator: "-")
        }
    }

    static var matrix: [Configuration] {
        typeSizes.flatMap { typeSize in
            darkModes.flatMap { dark in
                increaseContrastModes.flatMap { increaseContrast in
                    reduceTransparencyModes.flatMap { reduceTransparency in
                        reduceMotionModes.map { reduceMotion in
                            Configuration(
                                typeSize: typeSize,
                                dark: dark,
                                increaseContrast: increaseContrast,
                                reduceTransparency: reduceTransparency,
                                reduceMotion: reduceMotion
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: Pass

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard ProcessInfo.processInfo.environment["GLASSUI_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Set GLASSUI_SCREENSHOTS=1 (TEST_RUNNER_GLASSUI_SCREENSHOTS=1 via xcodebuild) to run the GlassUI screenshot pass.")
        }
    }

    @MainActor
    func testScreenshotMatrix() throws {
        // Appearance is device-wide, so put it back for the tests after.
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        defer { device.appearance = originalAppearance }

        for configuration in Self.matrix {
            device.appearance = configuration.dark ? .dark : .light
            let app = launch(configuration)
            captureScreens(app, configuration)
            app.terminate()
        }
    }

    /// The main screens under Increase Contrast, Reduce Transparency and
    /// Reduce Motion: the scrims, washes and placeholders that adapt to
    /// them (GlassUI 2c).
    @MainActor
    func testAccessibilityVariants() throws {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        defer { device.appearance = originalAppearance }

        for configuration in Self.accessibilityVariants {
            device.appearance = configuration.dark ? .dark : .light
            let app = launch(configuration)
            captureMainScreens(app, configuration)
            app.terminate()
        }
    }

    @MainActor
    private func launch(_ configuration: Configuration) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", configuration.typeSize.rawValue]
        // Read by the app's `Theme.LaunchAccessibility`.
        if configuration.increaseContrast {
            app.launchEnvironment["GLASSUI_INCREASE_CONTRAST"] = "1"
        }
        if configuration.reduceTransparency {
            app.launchEnvironment["GLASSUI_REDUCE_TRANSPARENCY"] = "1"
        }
        if configuration.reduceMotion {
            app.launchEnvironment["GLASSUI_REDUCE_MOTION"] = "1"
        }
        app.launch()
        return app
    }

    /// The main screens only: the first team page, and its player and game
    /// sheets. Onboarding, if it shows, is dismissed unrecorded.
    @MainActor
    private func captureMainScreens(_ app: XCUIApplication, _ configuration: Configuration) {
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        guard app.buttons["teamPicker.edit"].waitForExistence(timeout: 10) else {
            XCTFail("\(configuration.name): the crest bar never appeared")
            return
        }
        snapshot("team-page-1", configuration)

        capturePlayerSheet(app, configuration)
        captureGameSheet(app, configuration)
    }

    /// Walks the screens reachable by identifier: onboarding, the first team
    /// page and its player, game, leaders and news sheets, a second team
    /// page, the team browser, a sport and a league in it, and Alerts.
    @MainActor
    private func captureScreens(_ app: XCUIApplication, _ configuration: Configuration) {
        // A fresh install opens on the "Pick Your Teams" sheet.
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            snapshot("onboarding", configuration)
            done.tap()
        }

        let edit = app.buttons["teamPicker.edit"]
        guard edit.waitForExistence(timeout: 10) else {
            XCTFail("\(configuration.name): the crest bar never appeared")
            return
        }
        snapshot("team-page-1", configuration)

        captureSheets(app, configuration)
        // Scrolling down the page for the sheets minimized the tab bar.
        expandTabBar(app)

        let crests = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamPicker.team."))
        let second = crests.element(boundBy: 1)
        if second.waitForExistence(timeout: 5) {
            second.tap()
            snapshot("team-page-2", configuration)
        }

        edit.tap()
        guard done.waitForExistence(timeout: 5) else {
            XCTFail("\(configuration.name): the team browser never opened")
            return
        }
        snapshot("team-browser", configuration)

        // A sport's leagues, then a league's teams, then back to the top
        // for Alerts.
        let sports = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.sport."))
        let firstSport = sports.element(boundBy: 0)
        if firstSport.waitForExistence(timeout: 5) {
            firstSport.tap()
            let leagues = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.league."))
            let firstLeague = leagues.element(boundBy: 0)
            if firstLeague.waitForExistence(timeout: 5) {
                snapshot("team-browser-sport", configuration)
                firstLeague.tap()
                let teams = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.team."))
                _ = teams.firstMatch.waitForExistence(timeout: 10)
                snapshot("team-browser-league", configuration)
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        let alerts = app.buttons["teamBrowser.alerts"]
        if alerts.waitForExistence(timeout: 5) {
            alerts.tap()
            if app.navigationBars["Alerts"].waitForExistence(timeout: 5) {
                snapshot("alerts-settings", configuration)
            }
        }
    }

    /// The first team page's player, game and news sheets, each opened from
    /// its first card in view and closed again. A card that never loads
    /// (no network, an empty feed) skips its sheet rather than failing.
    @MainActor
    private func captureSheets(_ app: XCUIApplication, _ configuration: Configuration) {
        capturePlayerSheet(app, configuration)
        captureGameSheet(app, configuration)
        captureLeadersSheet(app, configuration)

        if let article = firstHittable("news.article", in: app, swipes: 12) {
            article.tap()
            // Safari's own Done (labelled "Close" where it draws an xmark),
            // or the sheet's close button when the link isn't a web page.
            let safariDone = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Close"])).firstMatch
            let close = app.buttons["newsDetail.close"]
            if safariDone.waitForExistence(timeout: 10) || close.exists {
                snapshot("news-detail", configuration)
                (close.exists ? close : safariDone).tap()
            } else {
                XCTFail("\(configuration.name): the news sheet never opened")
            }
        }
    }

    /// The first roster card's player sheet, opened and closed again.
    @MainActor
    private func capturePlayerSheet(_ app: XCUIApplication, _ configuration: Configuration) {
        guard let player = firstHittable("roster.player", in: app) else { return }
        player.tap()
        let close = app.buttons["playerDetail.close"]
        if close.waitForExistence(timeout: 5) {
            snapshot("player-detail", configuration)
            close.tap()
        } else {
            XCTFail("\(configuration.name): the player sheet never opened")
        }
    }

    /// The first schedule card's game sheet, opened and closed again.
    @MainActor
    private func captureGameSheet(_ app: XCUIApplication, _ configuration: Configuration) {
        guard let game = firstHittable("schedule.game", in: app, swipes: 4) else { return }
        game.tap()
        // Best effort: the sheet zooming out of its card (X-13), or the
        // system's slide under Reduce Motion. Whatever frame the screenshot
        // lands on, it's mid-presentation or just past it.
        snapshot("game-detail-zoom", configuration)
        let close = app.buttons["gameDetail.close"]
        if close.waitForExistence(timeout: 5) {
            // Opens at the medium detent; the drag indicator is there
            // to take it to large.
            snapshot("game-detail", configuration)
            close.tap()
        } else {
            XCTFail("\(configuration.name): the game sheet never opened")
        }
    }

    /// The league leaders sheet, opened from the leaders section's header
    /// button and closed again: its season shows as the title's subtitle
    /// (LL-3). Skipped if the section never shows the button.
    @MainActor
    private func captureLeadersSheet(_ app: XCUIApplication, _ configuration: Configuration) {
        guard let leaders = firstHittable("leaders.league", in: app, swipes: 6) else { return }
        leaders.tap()
        let close = app.buttons["leagueLeaders.close"]
        if close.waitForExistence(timeout: 5) {
            snapshot("league-leaders", configuration)
            close.tap()
        } else {
            XCTFail("\(configuration.name): the leaders sheet never opened")
        }
    }

    /// Brings the system tab bar back to full size if scrolling down the
    /// page minimized it: scrolling back up does, as in the system's apps.
    @MainActor
    private func expandTabBar(_ app: XCUIApplication) {
        let edit = app.buttons["teamPicker.edit"]
        for _ in 0..<3 where !edit.isHittable {
            app.swipeDown()
        }
    }

    /// The first element whose identifier starts with `identifier` that's
    /// on screen and tappable, scrolling the page up to `swipes` times to
    /// bring one into view. A prefix, since cards carry their item's id
    /// ("roster.player.<id>", "schedule.game.<id>").
    @MainActor
    private func firstHittable(_ identifier: String, in app: XCUIApplication, swipes: Int = 0) -> XCUIElement? {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifier))
        guard matches.firstMatch.waitForExistence(timeout: 10) else { return nil }
        for attempt in 0...swipes {
            if attempt > 0 {
                app.swipeUp()
            }
            if let element = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                return element
            }
        }
        return nil
    }

    @MainActor
    private func snapshot(_ screen: String, _ configuration: Configuration) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(screen)__\(configuration.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
