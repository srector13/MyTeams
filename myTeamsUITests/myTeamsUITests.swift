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

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
