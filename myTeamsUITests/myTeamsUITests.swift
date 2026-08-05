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

    @MainActor
    func testTeamPickerSwitchesTabs() throws {
        let app = XCUIApplication()
        app.launch()

        // The picker labels each crest with its team, and the selected one
        // spells its short name out beside the crest.
        XCTAssertTrue(app.staticTexts["Kansas Jayhawks"].waitForExistence(timeout: 10))

        app.buttons["Kansas City Chiefs"].tap()
        XCTAssertTrue(app.staticTexts["Kansas City Chiefs"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
