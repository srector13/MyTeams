//
//  HomeUITests.swift
//  myTeamsUITests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import XCTest

/// The Home tab (t_0b94af11): first in the bar, where the app opens, with
/// the way to Settings. Its page (t_191edd79) is the favorites' news feed,
/// under Live Now, Upcoming and Recent Results only when each has games.
/// Keyed on accessibility identifiers; the window tests pin Home's clock
/// (`MYTEAMS_HOME_NOW`) against the Chiefs' fixture season, so the ±7-day
/// windows hold the same games whenever they run.
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

    /// The Chiefs alone: the one bundled team whose news the fixtures
    /// serve (`chiefs_news`), and a season (`chiefs_schedule`) whose dates
    /// the window tests are pinned against.
    private static let chiefs = "football/nfl:12"

    /// Sat, Sep 26, 2026, 12:00 UTC, in the Chiefs' fixture season: last
    /// played Sep 21 (401872945, final) and Sep 15 (401872931, final, 11
    /// days back); next Sep 27 (401872952) then Oct 4 (401872976, 8 days
    /// on). No scoreboard is served, so nothing is live.
    private static let midSeason = "1790424000"

    /// Mon, Jun 1, 2026, 12:00 UTC: months before the Chiefs' first game,
    /// so no game section has anything to show.
    private static let offSeason = "1780315200"

    /// Home's sections on `midSeason`, top to bottom: Live Now has no game
    /// to show.
    private static let sections = [
        "home.section.upcoming",
        "home.section.results",
        "home.section.news",
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

    /// Home's identifiers are there: the page, its sections with games in
    /// order over the news feed, none for a section without games, and the
    /// Settings gear in its bar.
    @MainActor
    func testHomeShowsItsSections() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.midSeason)
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

        // No game under way: Live Now takes no room.
        XCTAssertFalse(element("home.section.live", in: app).exists, "Live Now showed with no game live.")
    }

    /// Upcoming is the next seven days' games and Recent Results the last
    /// seven days': each window's edge game is in, the one past it out.
    @MainActor
    func testGameSectionsHoldSevenDays() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.midSeason)

        let upcoming = element("home.section.upcoming", in: app)
        XCTAssertTrue(upcoming.waitForExistence(timeout: 15), "No Upcoming with a game tomorrow.")
        XCTAssertTrue(app.buttons["home.upcoming.401872952"].waitForExistence(timeout: 5), "Tomorrow's game isn't in Upcoming.")
        XCTAssertFalse(app.buttons["home.upcoming.401872976"].exists, "A game eight days on is in Upcoming.")
        XCTAssertTrue(element("home.upcoming.date", in: app).exists, "Upcoming has no date header.")

        let results = element("home.section.results", in: app)
        XCTAssertTrue(results.waitForExistence(timeout: 5), "No Recent Results with a game five days back.")
        XCTAssertTrue(app.buttons["home.result.401872945"].exists, "Sep 21's result isn't in Recent Results.")
        XCTAssertFalse(app.buttons["home.result.401872931"].exists, "A result eleven days back is in Recent Results.")
        XCTAssertFalse(app.buttons["home.result.401872952"].exists, "A game still to play is in Recent Results.")
    }

    /// With no game live, upcoming or recent, the game sections take no
    /// room and the page is the news feed, its stories there to open.
    @MainActor
    func testNewsFeedWithoutGames() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.offSeason)

        XCTAssertTrue(element("home.section.news", in: app).waitForExistence(timeout: 15), "No news feed on Home.")
        let row = app.buttons["home.news.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The news feed has no stories.")
        XCTAssertTrue(row.isHittable, "The feed's first story isn't on screen without games above it.")

        for identifier in ["home.section.live", "home.section.upcoming", "home.section.results"] {
            XCTAssertFalse(element(identifier, in: app).exists, "\(identifier) showed with no games.")
        }

        // The feed runs on below the fold, uncapped: still stories after
        // scrolling well past the first.
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["home.news.row"].firstMatch.waitForExistence(timeout: 5), "The feed ran out of stories.")
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

    /// Settings' Theme row opens the theme screen, which holds the one
    /// palette picker; Settings' own list doesn't.
    @MainActor
    func testSettingsOpensTheme() throws {
        let app = launchWithFixtures()
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "No Settings button in Home's bar.")

        let themeRow = app.buttons["settings.theme"]
        // On a cold launch the bar can redraw under the first tap.
        for _ in 0..<3 where !themeRow.exists {
            gear.tap()
            _ = themeRow.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(themeRow.exists, "Settings never opened, or has no Theme row.")

        let current = element("settings.theme.current", in: app)
        XCTAssertFalse(current.exists, "The theme is still in Settings' own list.")
        for _ in 0..<3 where !current.exists {
            themeRow.tap()
            _ = current.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(current.exists, "The Theme row never opened the theme screen.")
        XCTAssertFalse(element("settings.brandAccent.current", in: app).exists, "The old accent grid is still there.")

        // The grid's last tile: scrolled to only if it isn't in view.
        let graphite = element("settings.theme.graphite", in: app)
        for _ in 0..<4 where !graphite.exists || !graphite.isHittable {
            app.swipeUp()
            _ = graphite.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(graphite.exists, "The theme screen has no Graphite tile.")
        XCTAssertTrue(element("settings.theme.classic", in: app).exists, "The theme screen has no Classic tile.")
    }

    /// A launch that asks for the theme step (`ThemeOnboarding.launchKey`)
    /// shows it over Home, with every palette, Continue pinned below the
    /// grid; Skip closes it. (That it never comes back is
    /// `BrandThemeTests`'.)
    @MainActor
    func testThemeOnboardingSkips() throws {
        let app = launch(environment: ["MYTEAMS_ONBOARDING": "1"])
        let skip = app.buttons["onboarding.theme.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "The theme step never showed.")
        XCTAssertTrue(element("onboarding.theme.classic", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.theme.continue"].exists, "No Continue on the theme step.")

        // The grid's last tile: scrolled to only if it isn't in view.
        let graphite = element("onboarding.theme.graphite", in: app)
        for _ in 0..<4 where !graphite.exists || !graphite.isHittable {
            app.swipeUp()
            _ = graphite.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(graphite.exists, "The theme step has no Graphite tile.")

        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "Skip didn't close the theme step.")
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
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
    /// network. See `myTeamsUITests.launchWithFixtures`. `now`, in seconds
    /// since 1970, pins Home's clock (`HomeViewModel.launchNowKey`).
    @MainActor
    private func launchWithFixtures(following favorites: String = bundledTeams, now: String? = nil) -> XCUIApplication {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("myTeamsTests")
            .appendingPathComponent("Fixtures")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures.path), "No fixtures at \(fixtures.path)")
        var environment = ["MYTEAMS_FIXTURES_DIR": fixtures.path]
        if let now {
            environment["MYTEAMS_HOME_NOW"] = now
        }
        return launch(following: favorites, environment: environment)
    }
}
