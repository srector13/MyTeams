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
    // TODO(GlassUI 2c): XCUITest can't toggle Increase Contrast or Reduce
    // Transparency in-process (they're `xcrun simctl ui` / Settings knobs on
    // the host). Add `true` here once the app maps the launch environment
    // keys below onto its accessibility environment for UI tests.
    static let increaseContrastModes = [false]
    static let reduceTransparencyModes = [false]

    struct Configuration {
        var typeSize: TypeSize
        var dark: Bool
        var increaseContrast: Bool
        var reduceTransparency: Bool

        /// Stamped on every screenshot, e.g. `AX3-dark-hc`.
        var name: String {
            var parts = [typeSize.label, dark ? "dark" : "light"]
            if increaseContrast { parts.append("hc") }
            if reduceTransparency { parts.append("rt") }
            return parts.joined(separator: "-")
        }
    }

    static var matrix: [Configuration] {
        typeSizes.flatMap { typeSize in
            darkModes.flatMap { dark in
                increaseContrastModes.flatMap { increaseContrast in
                    reduceTransparencyModes.map { reduceTransparency in
                        Configuration(
                            typeSize: typeSize,
                            dark: dark,
                            increaseContrast: increaseContrast,
                            reduceTransparency: reduceTransparency
                        )
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

    @MainActor
    private func launch(_ configuration: Configuration) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", configuration.typeSize.rawValue]
        // Not read by the app yet; see `increaseContrastModes`.
        if configuration.increaseContrast {
            app.launchEnvironment["GLASSUI_INCREASE_CONTRAST"] = "1"
        }
        if configuration.reduceTransparency {
            app.launchEnvironment["GLASSUI_REDUCE_TRANSPARENCY"] = "1"
        }
        app.launch()
        return app
    }

    /// Walks the screens `myTeamsUITests` reaches by identifier: onboarding,
    /// two team pages, the team browser and Alerts.
    // TODO(GlassUI 1c): add game, player, leaders and news sheets once their
    // cards and close buttons carry accessibility identifiers.
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

        let alerts = app.buttons["teamBrowser.alerts"]
        if alerts.waitForExistence(timeout: 5) {
            alerts.tap()
            if app.navigationBars["Alerts"].waitForExistence(timeout: 5) {
                snapshot("alerts-settings", configuration)
            }
        }
    }

    @MainActor
    private func snapshot(_ screen: String, _ configuration: Configuration) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(screen)__\(configuration.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
