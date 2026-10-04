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

    /// Picks a league from the team browser's glass chips, keyed on their
    /// identifiers and the selected trait. Opens on NFL, the first chip.
    @MainActor
    func testLeagueChipsSelectLeague() throws {
        let app = XCUIApplication()
        app.launch()

        // The onboarding sheet is the browser; past onboarding, the crest
        // bar's add/edit button opens it.
        let done = app.buttons["teamBrowser.done"]
        if !done.waitForExistence(timeout: 5) {
            let edit = app.buttons["teamPicker.edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            edit.tap()
            XCTAssertTrue(done.waitForExistence(timeout: 5))
        }

        let nfl = app.buttons["teamBrowser.league.NFL"]
        let nba = app.buttons["teamBrowser.league.NBA"]
        XCTAssertTrue(nba.waitForExistence(timeout: 5))
        XCTAssertTrue(nfl.isSelected)
        XCTAssertFalse(nba.isSelected)

        nba.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: nba)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(nfl.isSelected)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
