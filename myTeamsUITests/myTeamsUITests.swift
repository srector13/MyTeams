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

        // The system tab bar: Home, then a tab per favorite; teams are
        // added from Settings (t_fa6748f4).
        let crests = teamTabs(app)
        XCTAssertTrue(crests.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["teamPicker.edit"].exists, "The tab bar still has a Teams tab.")
        XCTAssertTrue(
            crests.element(boundBy: 1).waitForExistence(timeout: 10),
            "Needs two followed teams; the launch follows four."
        )
        let first = pinnedTab(crests.element(boundBy: 0), in: app)
        let second = pinnedTab(crests.element(boundBy: 1), in: app)

        // The app opens on Home (t_0b94af11), no team selected.
        XCTAssertTrue(homeTab(app).isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertFalse(second.isSelected)

        first.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(homeTab(app).isSelected)

        second.tap()

        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
    }

    /// Drills the team browser from a sport to a league to its teams and
    /// back, keyed on row identifiers. Basketball lists the NBA.
    @MainActor
    func testBrowserDrillsDownSportToLeague() throws {
        let app = launch()
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
        app.teamBrowserBackButton.tap()
        XCTAssertTrue(nba.waitForExistence(timeout: 5))
        app.teamBrowserBackButton.tap()
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

    /// A first launch shows no teams, only Home's "Add your first team"
    /// (t_afe5c297, t_0b94af11): no favorites are followed by default, and
    /// no sheet opens over the home screen. Its button opens the team
    /// browser.
    @MainActor
    func testFreshLaunchShowsAddTeams() throws {
        let app = launch(following: Self.noTeams)

        let addTeams = app.buttons["home.addTeams"]
        XCTAssertTrue(addTeams.waitForExistence(timeout: 10), "No Add Teams on the empty home screen.")
        XCTAssertFalse(app.buttons["teamBrowser.done"].exists, "A sheet opened over the home screen at launch.")
        XCTAssertEqual(teamTabs(app).count, 0, "A fresh launch follows a team.")

        // On a cold launch the screen can redraw under the first tap.
        for _ in 0..<3 where !app.buttons["teamBrowser.done"].exists {
            addTeams.tap()
            _ = app.buttons["teamBrowser.done"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.buttons["teamBrowser.done"].exists, "Add Teams never opened the team browser.")
        XCTAssertTrue(app.buttons["teamBrowser.sport.basketball"].waitForExistence(timeout: 5))
    }

    /// The four bundled teams, as `TeamRef.id`s: they resolve from the app
    /// bundle, with no catalog to load. A fresh install follows none, so
    /// launches that need teams name them.
    private static let bundledTeams = [
        "basketball/mens-college-basketball:2305",
        "football/nfl:12",
        "baseball/mlb:7",
        "soccer/usa.1:186",
    ].joined(separator: ",")

    /// A favorites value naming no team: a launch following none.
    private static let noTeams = "none"

    /// The app, following `favorites` in place of whatever an earlier test
    /// left stored (`FavoritesStore.launchFavoritesKey`, read by Debug
    /// builds; iCloud is left out of the run).
    @MainActor
    private func launch(following favorites: String = bundledTeams, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MYTEAMS_FAVORITES"] = favorites
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        return app
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

        // `FixtureTransport.directoryKey`, read by Debug builds of the app.
        return launch(environment: ["MYTEAMS_FIXTURES_DIR": fixtures.path])
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

    /// Opens the team browser from Settings' "Add Teams" row, the tab bar
    /// holding Home and teams only (t_fa6748f4). The gear is in Home's bar,
    /// where the app opens, as in each team page's.
    ///
    /// On a cold launch the page redraws as the favorites and their crests
    /// resolve, and a tap located before a redraw can miss. So each step is
    /// retried until the next screen shows.
    @MainActor
    private func openTeamBrowser(_ app: XCUIApplication) {
        let done = app.buttons["teamBrowser.done"]
        let gear = app.buttons["home.settings"]
        let addTeams = app.buttons["settings.addTeams"]
        let settingsClose = app.buttons["settings.done"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "No Settings button on the team page.")
        for _ in 0..<3 where !settingsClose.exists && !addTeams.exists {
            gear.tap()
            _ = settingsClose.waitForExistence(timeout: 5)
        }
        // The accent grid put the row below the sheet's fold (t_e30988b7).
        for _ in 0..<4 where settingsClose.exists && !addTeams.exists {
            app.swipeUp()
            _ = addTeams.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(addTeams.exists, "Settings never opened.")
        for _ in 0..<3 {
            addTeams.tap()
            if done.waitForExistence(timeout: 5) { return }
        }
        XCTFail("The team browser never opened from Settings' Add Teams.")
    }

    /// The system's "More" tab, which lists the favorites past the bar's
    /// room; not a team's tab.
    private static let moreTabLabel = "More"

    /// Home's tab, first in the bar (t_0b94af11); not a team's tab.
    private static let homeTabLabel = "Home"

    /// Home's tab, by its identifier, or its label on a launch whose bar
    /// lost its identifiers (`teamTabs`).
    @MainActor
    private func homeTab(_ app: XCUIApplication) -> XCUIElement {
        let byID = app.tabBars.buttons["teamPicker.home"]
        return byID.exists ? byID : app.tabBars.buttons[Self.homeTabLabel]
    }

    /// The first favorite's tab chosen, from Home where the app opens
    /// (t_0b94af11), for the tests of a team's page.
    @MainActor
    private func openFirstTeam(_ app: XCUIApplication) {
        let first = teamTabs(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "No team's tab in the bar.")
        let tab = pinnedTab(first, in: app)
        // On a cold launch the bar can redraw under the first tap.
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            _ = tab.wait(for: \.isSelected, toEqual: true, timeout: 3)
        }
        XCTAssertTrue(tab.isSelected, "The first team's tab never opened.")
    }

    /// The favorites' tabs, in bar order: those with a `teamPicker.team.`
    /// identifier, or, on a launch whose bar lost its identifiers, every
    /// tab but Home and "More".
    ///
    /// SwiftUI copies a `Tab`'s accessibility identifier onto the system tab
    /// bar's button only some of the time on the iOS 26 simulator: on the
    /// launches that miss it, every tab still has its label but none has an
    /// identifier, for as long as the test waits.
    @MainActor
    private func teamTabs(_ app: XCUIApplication) -> XCUIElementQuery {
        app.tabBars.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR (identifier == '' AND label != %@ AND label != %@)",
            "teamPicker.team.", Self.moreTabLabel, Self.homeTabLabel
        ))
    }

    /// `tab` found again by its identifier, or its label without one, so it
    /// stays the same tab whatever the bar's order does.
    @MainActor
    private func pinnedTab(_ tab: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        tab.identifier.isEmpty ? app.tabBars.buttons[tab.label] : app.buttons[tab.identifier]
    }

    /// The team page's crest and name are pinned in the navigation bar
    /// (t_5478d64e): visible at rest with no pull needed, still there with
    /// the page scrolled down and pulled past the top, and always inside the
    /// bar, so never drawn over the cards scrolling beneath it.
    @MainActor
    func testTeamPageHeaderPinnedInBar() throws {
        let app = launch()
        openFirstTeam(app)

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
        let app = launch()
        openFirstTeam(app)

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
        openFirstTeam(app)

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
        let app = launch()

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "splash-launch"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(app.state, .runningForeground)

        // Gone, and the app under it reachable: the tab bar.
        let splash = app.images["splash.logo"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(teamTabs(app).firstMatch.waitForExistence(timeout: 10))
    }

    /// Tapping a leader on the league's boards opens their team's page and
    /// their player sheet on it (t_8d15e070). Flory Bidunga leads in blocks
    /// in the served men's college basketball leaders and is on the served
    /// Kansas roster, so from Kansas's page the boards close and his sheet
    /// opens over the same page.
    @MainActor
    func testLeaderOpensPlayerSheetOnTeamPage() throws {
        let app = launchWithFixtures()
        openKansasLeagueLeaders(app)

        let bidunga = app.buttons["leagueLeaders.row.5044426"].firstMatch
        for _ in 0..<12 where !(bidunga.exists && bidunga.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(bidunga.isHittable, "Bidunga's row never showed on the leaders fixture's boards.")
        bidunga.tap()

        // The boards close, then the player sheet opens on Kansas's page.
        let sheetClose = app.descendants(matching: .any)["playerDetail.close"].firstMatch
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 15), "The player sheet never opened.")
        XCTAssertFalse(app.buttons["leagueLeaders.close"].exists, "The leaders sheet is still up.")
        XCTAssertTrue(app.descendants(matching: .any)["playerDetail.section"].exists)
        // A favorite's own page: no follow button behind the sheet.
        XCTAssertFalse(app.buttons["teamPage.follow"].exists)

        // Closed, it stays closed: the request was used up.
        sheetClose.tap()
        XCTAssertTrue(sheetClose.waitForNonExistence(timeout: 5))
        XCTAssertFalse(sheetClose.waitForExistence(timeout: 2), "The player sheet opened again.")
    }

    /// A leader on a team nobody follows opens that team's page over the
    /// favorite's, with the follow button beside the gear (t_8d15e070). The
    /// button follows the team and, tapped again, undoes it; back returns
    /// to the favorite's page.
    @MainActor
    func testLeaderOfAnotherTeamOpensTheirTeamPage() throws {
        let app = launchWithFixtures()
        openKansasLeagueLeaders(app)

        // AJ Dybantsa, BYU: first on the points board.
        let dybantsa = app.buttons["leagueLeaders.row.5142718"].firstMatch
        for _ in 0..<6 where !(dybantsa.exists && dybantsa.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(dybantsa.isHittable, "Dybantsa's row never showed on the leaders fixture's boards.")
        dybantsa.tap()

        let follow = app.buttons["teamPage.follow"]
        XCTAssertTrue(follow.waitForExistence(timeout: 15), "BYU's page never opened with a follow button.")
        XCTAssertTrue(app.buttons["home.settings"].exists, "No Settings beside the follow button.")

        // A bar button doesn't carry the selected trait to XCUITest, so the
        // flip is read from its label: "Follow …" to "Following …" and back.
        let unfollowed = follow.label
        follow.tap()
        XCTAssertTrue(waitForLabel(of: follow, toDifferFrom: unfollowed), "Following didn't flip the button.")
        // Undo: the same button unfollows.
        follow.tap()
        XCTAssertTrue(follow.wait(for: \.label, toEqual: unfollowed, timeout: 5), "A second tap didn't undo the follow.")

        // Back to Kansas's page, which has no follow button.
        app.navigationBars.containing(.button, identifier: "teamPage.follow")
            .firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(follow.waitForNonExistence(timeout: 5), "Still on BYU's page.")
        XCTAssertTrue(app.descendants(matching: .any)["home.brandLogo"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Whether `element`'s label changes from `label` within `timeout`.
    @MainActor
    private func waitForLabel(of element: XCUIElement, toDifferFrom label: String, timeout: TimeInterval = 5) -> Bool {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", label), object: element)
        return XCTWaiter.wait(for: [changed], timeout: timeout) == .completed
    }

    /// Past onboarding, on Kansas's page, opens the league's leaderboards
    /// from the leaders card's button.
    @MainActor
    private func openKansasLeagueLeaders(_ app: XCUIApplication) {
        let done = app.buttons["teamBrowser.done"]
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }

        // Kansas, the first seed team: its tab by identifier, or by label
        // on a launch whose bar lost its identifiers (`teamTabs`).
        XCTAssertTrue(teamTabs(app).firstMatch.waitForExistence(timeout: 10))
        let byID = app.tabBars.buttons["teamPicker.team.basketball/mens-college-basketball:2305"]
        let kansas = byID.exists
            ? byID
            : app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Jayhawks")).firstMatch
        XCTAssertTrue(kansas.waitForExistence(timeout: 5), "Kansas isn't followed.")
        if !kansas.isSelected {
            kansas.tap()
        }

        // Down the page to the leaders card, which may not be laid out
        // until it's near the screen.
        XCTAssertTrue(app.descendants(matching: .any)["teamPage.header"].firstMatch.waitForExistence(timeout: 10))
        let league = app.buttons["leaders.league"].firstMatch
        for _ in 0..<12 where !(league.exists && league.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(league.exists && league.isHittable, "Couldn't scroll to the leaders card on Kansas's page.")
        league.tap()
        XCTAssertTrue(app.buttons["leagueLeaders.close"].waitForExistence(timeout: 5), "The league's leaders never opened.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

extension XCUIApplication {
    /// The team browser's back button: the first button of the navigation
    /// bar holding the browser's Done. Opened from Settings, the browser is
    /// a sheet over the Settings sheet, whose bar is still in the tree, so
    /// the app's first bar button can be Settings' Done (t_fa6748f4).
    var teamBrowserBackButton: XCUIElement {
        navigationBars
            .containing(.button, identifier: "teamBrowser.done")
            .firstMatch
            .buttons
            .element(boundBy: 0)
    }
}
