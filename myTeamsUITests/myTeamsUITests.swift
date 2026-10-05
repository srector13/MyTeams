//
//  myTeamsUITests.swift
//  myTeamsUITests
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import XCTest

final class myTeamsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Switches teams from the crest bar. Keyed on accessibility
    /// identifiers and the selected trait rather than team names, so it
    /// holds whichever teams are followed, as long as there are two.
    @MainActor
    func testCrestBarSwitchesTeams() throws {
        let app = launchWithFixtures()

        // A fresh install opens on the "Pick Your Teams" sheet with the seed
        // teams already followed; Done finishes onboarding. Later launches
        // skip the sheet.
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        // The system tab bar: a tab per favorite, and the Teams (add/edit) tab.
        XCTAssertTrue(teamsTab(app).waitForExistence(timeout: 10))
        let crests = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamPicker.team."))
        XCTAssertTrue(
            crests.element(boundBy: 1).waitForExistence(timeout: 10),
            "Needs two followed teams; a fresh install follows four."
        )
        let first = app.buttons[crests.element(boundBy: 0).identifier]
        let second = app.buttons[crests.element(boundBy: 1).identifier]

        // The first favorite opens selected.
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(second.isSelected)

        second.tap()

        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
    }

    /// Drills the team browser from a sport to a league to its teams and
    /// back, keyed on row identifiers. Basketball lists the NBA.
    @MainActor
    func testBrowserDrillsDownSportToLeague() throws {
        let app = XCUIApplication()
        app.launch()
        openTeamBrowser(app)

        let basketball = app.buttons["teamBrowser.sport.basketball"]
        XCTAssertTrue(basketball.waitForExistence(timeout: 5))
        basketball.tap()

        let nba = app.buttons["teamBrowser.league.NBA"]
        XCTAssertTrue(nba.waitForExistence(timeout: 5))
        nba.tap()

        // The league's teams; with no network and no cache the league can
        // be empty, so the toggle is checked only when a row loads.
        let teams = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.team."))
        let team = teams.firstMatch
        if team.waitForExistence(timeout: 15) {
            let row = app.buttons[team.identifier]
            let wasFollowed = row.isSelected
            row.tap()
            dismissNotificationPrompt()
            XCTAssertTrue(row.wait(for: \.isSelected, toEqual: !wasFollowed, timeout: 5))
            // Put the favorites back as they were.
            row.tap()
            dismissNotificationPrompt()
            XCTAssertTrue(row.wait(for: \.isSelected, toEqual: wasFollowed, timeout: 5))
        }

        // Back to the leagues, then the sports.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(nba.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(basketball.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["teamBrowser.done"].exists)
    }

    /// Searches every sport from the browser's first page. The league
    /// catalogs are served from fixtures, so the NBA's always lists the
    /// Lakers.
    @MainActor
    func testBrowserSearchFindsTeams() throws {
        let app = launchWithFixtures()
        openTeamBrowser(app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field on screen.")
        field.tap()
        field.typeText("Lakers")

        // Search replaces the sports list.
        let lakers = app.buttons["teamBrowser.team.basketball/nba:13"].firstMatch
        XCTAssertTrue(lakers.waitForExistence(timeout: 20), "The NBA catalog fixture's Lakers never showed.")
        XCTAssertFalse(app.buttons["teamBrowser.sport.basketball"].exists)
    }

    /// The app, serving its ESPN requests from the unit tests' captured
    /// documents (`FixtureTransport`) instead of the network, so the tests
    /// that read feeds assert rather than skip when ESPN doesn't answer
    /// (A-20). Crests still load from the network.
    ///
    /// The simulator shares the Mac's file system, so the app reads
    /// `myTeamsTests/Fixtures` straight from the checkout, found from this
    /// file's path.
    @MainActor
    private func launchWithFixtures() -> XCUIApplication {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("myTeamsTests")
            .appendingPathComponent("Fixtures")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures.path), "No fixtures at \(fixtures.path)")

        let app = XCUIApplication()
        // `FixtureTransport.directoryKey`, read by Debug builds of the app.
        app.launchEnvironment["MYTEAMS_FIXTURES_DIR"] = fixtures.path
        app.launch()
        return app
    }

    /// Declines the notification prompt a first follow raises on a fresh
    /// install, if it shows.
    @MainActor
    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        alert.buttons.element(boundBy: 0).tap()
    }

    /// Opens the team browser: the onboarding sheet on a fresh install,
    /// past onboarding the tab bar's "Teams" tab.
    ///
    /// On a cold launch the tab bar redraws as the favorites and their
    /// crests resolve, and a tap located before a redraw can land on a
    /// team's tab instead, which opens nothing. So the tap is retried until
    /// the browser shows.
    @MainActor
    private func openTeamBrowser(_ app: XCUIApplication) {
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) { return }
        let edit = teamsTab(app)
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            edit.tap()
            if done.waitForExistence(timeout: 5) { return }
        }
        XCTFail("The team browser never opened from the Teams tab.")
    }

    /// The tab bar's "Teams" tab, with the bar at full size.
    ///
    /// The bar minimizes to the selected tab as the page scrolls down
    /// (`tabBarMinimizeBehavior(.onScrollDown)`), and the other tabs leave
    /// the accessibility tree with it. A page whose cards all land at once,
    /// as fixtures make them, can move its offset enough to do that at
    /// launch, so a missing tab is brought back the way a reader would:
    /// by scrolling up.
    @MainActor
    private func teamsTab(_ app: XCUIApplication) -> XCUIElement {
        let edit = app.buttons["teamPicker.edit"]
        if !edit.waitForExistence(timeout: 5) {
            print("No \"teamPicker.edit\" after 5 s; scrolling up. The app:\n\(app.debugDescription)")
            app.swipeDown()
        }
        return edit
    }

    /// The team page's crest and name are pinned in the navigation bar
    /// (t_5478d64e): visible at rest with no pull needed, still there with
    /// the page scrolled down and pulled past the top, and always inside the
    /// bar, so never drawn over the cards scrolling beneath it.
    @MainActor
    func testTeamPageHeaderPinnedInBar() throws {
        let app = XCUIApplication()
        app.launch()

        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let header = app.descendants(matching: .any)["teamPage.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))

        func assertPinned(_ moment: String) {
            XCTAssertTrue(header.exists && header.isHittable, "Header not visible \(moment).")
            XCTAssertFalse(header.frame.isEmpty, "Header not laid out \(moment).")
            XCTAssertGreaterThanOrEqual(header.frame.minY, bar.frame.minY - 1, "Header above the bar \(moment).")
            XCTAssertLessThanOrEqual(header.frame.maxY, bar.frame.maxY + 1, "Header below the bar, over the cards, \(moment).")
        }

        assertPinned("at rest")
        let resting = header.frame

        // The cards are at least a screen tall, so the page always scrolls
        // well past the summary, down towards the news.
        app.swipeUp()
        app.swipeUp()
        assertPinned("scrolled down")
        XCTAssertEqual(header.frame.minY, resting.minY, accuracy: 1, "Header moved with the scroll.")
        // The record and next game scroll with the page, under the bar.
        let summary = app.descendants(matching: .any)["teamPage.summary"]
        XCTAssertFalse(summary.exists && summary.isHittable)

        // Back to the top and pulled past it: the header doesn't ride the
        // overscroll.
        for _ in 0..<4 {
            app.swipeDown()
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        assertPinned("after pulling past the top")
        XCTAssertEqual(header.frame.minY, resting.minY, accuracy: 1, "Header moved with the overscroll.")
    }

    /// The myTeams mark sits small in the leading slot of the team page's
    /// bar (t_829bb3cc), alongside the pinned crest and name.
    @MainActor
    func testBrandLogoInTeamPageBar() throws {
        let app = XCUIApplication()
        app.launch()

        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let header = app.descendants(matching: .any)["teamPage.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let logo = app.descendants(matching: .any)["home.brandLogo"].firstMatch
        XCTAssertTrue(logo.waitForExistence(timeout: 5))
        let bar = app.navigationBars.firstMatch
        XCTAssertGreaterThanOrEqual(logo.frame.minY, bar.frame.minY - 1, "Logo above the bar.")
        XCTAssertLessThanOrEqual(logo.frame.maxY, bar.frame.maxY + 1, "Logo below the bar.")
        XCTAssertLessThan(logo.frame.maxX, header.frame.minX, "Logo overlaps the crest and name.")
    }

    /// The schedule cards (UI-3) speak a whole game, never a placeholder
    /// such as "nil" or "Optional(…)" for a field the feed left out. The
    /// first team's schedule is served from fixtures, so cards always load.
    @MainActor
    func testScheduleCardsReadWithoutPlaceholders() throws {
        let app = launchWithFixtures()

        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule.game."))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "The schedule fixture never loaded.")
        for card in cards.allElementsBoundByIndex.prefix(8) {
            let label = card.label
            XCTAssertFalse(label.isEmpty, card.identifier)
            // Whole words, so "Manila" passes and "nil" doesn't.
            let words = label.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            XCTAssertFalse(words.contains("nil"), label)
            XCTAssertFalse(words.contains("optional"), label)
        }
    }

    /// A cold launch shows the brand splash over the first frames, then
    /// clears it for the app: it never stays up. The earliest screenshot
    /// is attached; whether it caught the splash depends on how fast the
    /// first frame came.
    @MainActor
    func testSplashLogoOnLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "splash-launch"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(app.state, .runningForeground)

        // Gone, and the app under it reachable: onboarding on a fresh
        // install, the tab bar after.
        let splash = app.images["splash.logo"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)
        waitForExpectations(timeout: 5)
        let done = app.buttons["teamBrowser.done"]
        let edit = app.buttons["teamPicker.edit"]
        XCTAssertTrue(done.waitForExistence(timeout: 5) || edit.waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
