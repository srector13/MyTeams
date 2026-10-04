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

        // The crest bar: a button per favorite, then the add/edit button.
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

        // The bar slides away shortly after the tap, leaving a strip along
        // the bottom edge that brings it back.
        let reveal = app.buttons["tabBar.reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.tap()
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
    /// past onboarding the crest bar's add/edit button.
    @MainActor
    private func openTeamBrowser(_ app: XCUIApplication) {
        let done = app.buttons["teamBrowser.done"]
        if !done.waitForExistence(timeout: 5) {
            let edit = app.buttons["teamPicker.edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            edit.tap()
            XCTAssertTrue(done.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
