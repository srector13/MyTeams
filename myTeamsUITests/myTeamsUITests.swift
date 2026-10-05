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
        let app = XCUIApplication()
        app.launch()

        // A fresh install opens on the "Pick Your Teams" sheet with the seed
        // teams already followed; Done finishes onboarding. Later launches
        // skip the sheet.
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        // The system tab bar: a tab per favorite, and the Teams (add/edit) tab.
        XCTAssertTrue(app.buttons["teamPicker.edit"].waitForExistence(timeout: 10))
        let crests = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamPicker.team."))
        guard crests.element(boundBy: 1).waitForExistence(timeout: 10) else {
            throw XCTSkip("Needs two followed teams; a fresh install follows four.")
        }
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

    /// Searches every sport from the browser's first page. Results need a
    /// catalog or ESPN, so an empty search is skipped rather than failed.
    @MainActor
    func testBrowserSearchFindsTeams() throws {
        let app = XCUIApplication()
        app.launch()
        openTeamBrowser(app)

        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 5) else {
            throw XCTSkip("No search field on screen.")
        }
        field.tap()
        field.typeText("Lakers")

        // Search replaces the sports list.
        let hits = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.team."))
        guard hits.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("No team catalog or ESPN search available.")
        }
        XCTAssertFalse(app.buttons["teamBrowser.sport.basketball"].exists)
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
        let edit = app.buttons["teamPicker.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            edit.tap()
            if done.waitForExistence(timeout: 5) { return }
        }
        XCTFail("The team browser never opened from the Teams tab.")
    }

    /// The team page's header — its crest, name and record — sits at the
    /// top of the page, goes under the cards as the page scrolls down and
    /// comes back on scrolling up (UI-1).
    @MainActor
    func testTeamPageHeaderRecedesAndReturns() throws {
        let app = XCUIApplication()
        app.launch()

        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let header = app.descendants(matching: .any)["teamPage.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.isHittable)

        // The cards are at least a screen tall, so the page always scrolls
        // far enough to cover the header.
        app.swipeUp()
        app.swipeUp()
        XCTAssertFalse(header.exists && header.isHittable)

        for _ in 0..<4 where !(header.exists && header.isHittable) {
            app.swipeDown()
        }
        expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: header)
        waitForExpectations(timeout: 5)
    }

    /// The schedule cards (UI-3) speak a whole game, never a placeholder
    /// such as "nil" or "Optional(…)" for a field the feed left out.
    /// Skipped if the schedule never loads (no network).
    @MainActor
    func testScheduleCardsReadWithoutPlaceholders() throws {
        let app = XCUIApplication()
        app.launch()

        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "schedule.game."))
        guard cards.firstMatch.waitForExistence(timeout: 15) else {
            throw XCTSkip("The schedule never loaded.")
        }
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
