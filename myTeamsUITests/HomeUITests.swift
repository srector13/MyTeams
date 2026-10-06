//
//  HomeUITests.swift
//  myTeamsUITests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import XCTest

/// The Home tab (t_0b94af11): first in the bar, where the app opens, with
/// its four sections — Live Now, Today, Results, Headlines — and the way to
/// Settings. Keyed on accessibility identifiers, so it holds whichever
/// games and stories the feeds serve.
final class HomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The four bundled teams, as `TeamRef.id`s: they resolve from the app
    /// bundle, with no catalog to load.
    private static let bundledTeams = [
        "basketball/mens-college-basketball:2305",
        "football/nfl:12",
        "baseball/mlb:7",
        "soccer/usa.1:186",
    ].joined(separator: ",")

    /// Home's sections, top to bottom.
    private static let sections = [
        "home.section.live",
        "home.section.today",
        "home.section.results",
        "home.section.headlines",
    ]

    /// The app opens on Home, not on a team's page: Home's tab is selected,
    /// its bar is titled "Home", and no team page is on screen.
    @MainActor
    func testLaunchLandsOnHome() throws {
        let app = launchWithFixtures()

        let home = homeTab(app)
        XCTAssertTrue(home.waitForExistence(timeout: 10), "No Home tab in the bar.")
        XCTAssertTrue(home.isSelected, "The app didn't open on Home.")
        // First in the bar, before the teams.
        XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, home.label)

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5), "Home's bar isn't titled Home.")
        XCTAssertFalse(app.descendants(matching: .any)["teamPage.header"].exists, "A team's page is on screen.")
    }

    /// Home's identifiers are there: the page, its four sections in order,
    /// and the Settings gear in its bar.
    @MainActor
    func testHomeShowsItsSections() throws {
        let app = launchWithFixtures()
        XCTAssertTrue(homeTab(app).waitForExistence(timeout: 10))

        XCTAssertTrue(element("home.page", in: app).waitForExistence(timeout: 10), "Home's page never showed.")
        XCTAssertTrue(app.buttons["home.settings"].exists, "No Settings button in Home's bar.")

        for identifier in Self.sections {
            let section = element(identifier, in: app)
            // The page scrolls; the lower sections may need bringing up.
            for _ in 0..<4 where !section.exists {
                app.swipeUp()
            }
            XCTAssertTrue(section.waitForExistence(timeout: 10), "No \(identifier) on Home.")
        }

        // Top to bottom, as laid out: back to the top and read their
        // frames together.
        for _ in 0..<4 {
            app.swipeDown()
        }
        let laidOut = Self.sections.map { element($0, in: app).frame.minY }
        XCTAssertEqual(laidOut, laidOut.sorted(), "Home's sections are out of order.")
    }

    /// Home's gear opens Settings, the way to alerts and teams from where
    /// the app opens.
    @MainActor
    func testHomeOpensSettings() throws {
        let app = launchWithFixtures()
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "No Settings button in Home's bar.")

        let alerts = app.buttons["settings.alerts"]
        // On a cold launch the bar can redraw under the first tap.
        for _ in 0..<3 where !alerts.exists {
            gear.tap()
            _ = alerts.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(alerts.exists, "Settings never opened from Home.")
    }

    /// With no favorites Home is the only tab, and its empty state's "Add
    /// your first team" opens the team browser.
    @MainActor
    func testFirstRunAddsFirstTeam() throws {
        let app = launch(following: "none")

        let addTeams = app.buttons["home.addTeams"]
        XCTAssertTrue(addTeams.waitForExistence(timeout: 10), "No Add your first team on an empty Home.")
        XCTAssertTrue(homeTab(app).isSelected)

        let done = app.buttons["teamBrowser.done"]
        for _ in 0..<3 where !done.exists {
            addTeams.tap()
            _ = done.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(done.exists, "Add your first team never opened the team browser.")
    }

    // MARK: Helpers

    /// Home's tab, by its identifier, or by its label on a launch whose bar
    /// lost its identifiers (as `myTeamsUITests.teamTabs` explains).
    @MainActor
    private func homeTab(_ app: XCUIApplication) -> XCUIElement {
        let byID = app.tabBars.buttons["teamPicker.home"]
        return byID.exists ? byID : app.tabBars.buttons["Home"]
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// The app, following `favorites` in place of whatever an earlier test
    /// left stored (`FavoritesStore.launchFavoritesKey`, read by Debug
    /// builds).
    @MainActor
    private func launch(following favorites: String = bundledTeams, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MYTEAMS_FAVORITES"] = favorites
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        return app
    }

    /// The app, serving its ESPN requests from the unit tests' captured
    /// documents (`FixtureTransport`), so Home's feeds answer without the
    /// network. See `myTeamsUITests.launchWithFixtures`.
    @MainActor
    private func launchWithFixtures() -> XCUIApplication {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("myTeamsTests")
            .appendingPathComponent("Fixtures")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures.path), "No fixtures at \(fixtures.path)")
        return launch(environment: ["MYTEAMS_FIXTURES_DIR": fixtures.path])
    }
}
