//
//  HomeUITests.swift
//  myTeamsUITests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import XCTest

/// The Home tab (t_0b94af11): first in the bar, where the app opens, with
/// the way to Settings. Its page leads with the hero, then My Teams, This
/// Week's strip of days and their games, and the favorites' news feed.
/// Keyed on accessibility identifiers; the week tests pin Home's clock
/// (`MYTEAMS_HOME_NOW`) against the Chiefs' fixture season, so the strip
/// holds the same days and games whenever they run.
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
    /// the week tests are pinned against.
    private static let chiefs = "football/nfl:12"

    /// Sat, Sep 26, 2026, 12:00 UTC, in the Chiefs' fixture season: This
    /// Week runs Sep 23 to Oct 3. Last played Sep 21 (401872945, final, five
    /// days back, before the strip); next Sep 27 (401872952, in it) then
    /// Oct 4 (401872976, past it). No scoreboard is served, so nothing is
    /// live.
    private static let midSeason = "1790424000"

    /// Mon, Sep 21, 2026, 18:00 UTC, the day after the Chiefs beat the
    /// Colts: This Week runs Sep 18 to Sep 28, holding that result
    /// (401872945) and the next game (401872952), but not the Sep 15 result
    /// (401872931) or the Oct 4 game (401872976).
    private static let dayAfterResult = "1790013600"

    /// Mon, Jun 1, 2026, 12:00 UTC: months before the Chiefs' first game,
    /// so This Week has nothing to show.
    private static let offSeason = "1780315200"

    /// The fixture games' starts, in seconds since 1970.
    private static let colts = 1_789_950_000.0     // 401872945, Sep 21 00:20 UTC, final
    private static let dolphins = 1_790_528_400.0  // 401872952, Sep 27 17:00 UTC
    private static let broncos = 1_789_431_300.0   // 401872931, Sep 15 00:15 UTC, final

    /// Home's sections on `midSeason` in the default layout, top to bottom.
    private static let sections = [
        "home.section.myTeams",
        "home.section.week",
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

    /// Home's identifiers are there: the page, the hero leading with the
    /// next game, the sections in order with a card for the favorite, and
    /// the Settings gear in its bar.
    @MainActor
    func testHomeShowsItsSections() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.midSeason)
        XCTAssertTrue(homeTab(app).waitForExistence(timeout: 10))

        XCTAssertTrue(element("home.page", in: app).waitForExistence(timeout: 10), "Home's page never showed.")
        XCTAssertTrue(app.buttons["home.settings"].exists, "No Settings button in Home's bar.")
        XCTAssertTrue(element("home.hero", in: app).waitForExistence(timeout: 10), "No hero at the top of Home.")
        XCTAssertTrue(app.buttons["home.hero.details"].waitForExistence(timeout: 10), "The hero has no next game to open.")
        XCTAssertTrue(app.buttons["home.myTeams.\(Self.chiefs)"].waitForExistence(timeout: 10), "No card for the Chiefs in My Teams.")

        for identifier in Self.sections {
            let section = element(identifier, in: app)
            // The page scrolls; the lower sections may need bringing up.
            for _ in 0..<6 where !section.exists {
                app.swipeUp()
            }
            XCTAssertTrue(section.waitForExistence(timeout: 10), "No \(identifier) on Home.")
        }

        // Top to bottom, as laid out: back to the top and read their
        // frames together.
        for _ in 0..<6 {
            app.swipeDown()
        }
        let laidOut = Self.sections.map { element($0, in: app).frame.minY }
        XCTAssertEqual(laidOut, laidOut.sorted(), "Home's sections are out of order.")
        XCTAssertTrue(app.buttons["home.customize"].exists, "No Customize Home at the foot of the page.")
    }

    /// This Week runs three days back to seven on: it opens on the next
    /// day with a game, whose card is there; a day without games says so;
    /// the game eight days on and the result five days back are past its
    /// ends.
    @MainActor
    func testThisWeekOpensOnTheNextGame() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.midSeason)

        XCTAssertTrue(element("home.section.week", in: app).waitForExistence(timeout: 15), "No This Week on Home.")
        let tomorrow = app.buttons["home.upcoming.401872952"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 10), "This Week didn't open on tomorrow's game.")

        // The strip's ends: Sep 23 and Oct 3.
        let now = TimeInterval(Self.midSeason) ?? 0
        let day: TimeInterval = 24 * 60 * 60
        XCTAssertTrue(app.buttons["home.week.day.\(dayKey(now - 3 * day))"].exists, "The strip doesn't reach three days back.")
        XCTAssertTrue(app.buttons["home.week.day.\(dayKey(now + 7 * day))"].exists, "The strip doesn't reach seven days on.")
        XCTAssertFalse(app.buttons["home.week.day.\(dayKey(now - 4 * day))"].exists, "The strip reaches four days back.")
        XCTAssertFalse(app.buttons["home.week.day.\(dayKey(now + 8 * day))"].exists, "The strip reaches eight days on.")
        XCTAssertFalse(app.buttons["home.upcoming.401872976"].exists, "A game eight days on is in This Week.")
        XCTAssertFalse(app.buttons["home.result.401872945"].exists, "A result five days back is in This Week.")

        // Today has no game: picking it says so, and the card goes.
        let today = app.buttons["home.week.day.\(dayKey(now))"]
        XCTAssertTrue(today.exists, "No day for today in the strip.")
        today.tap()
        XCTAssertTrue(element("home.week.dayEmpty", in: app).waitForExistence(timeout: 5), "A day without games didn't say so.")
        XCTAssertTrue(tomorrow.waitForNonExistence(timeout: 5), "Tomorrow's game stayed under today.")

        // And back to the game's day.
        app.buttons["home.week.day.\(dayKey(Self.dolphins))"].tap()
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5), "Picking the game's day didn't show its game.")
    }

    /// A result in the strip is a result card on its day: the day after
    /// the Colts game, its day shows the final, and the next game is a day
    /// away in the same strip. The Sep 15 result, six days back, is not.
    @MainActor
    func testThisWeekShowsResults() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.dayAfterResult)

        XCTAssertTrue(element("home.section.week", in: app).waitForExistence(timeout: 15), "No This Week on Home.")
        let resultDay = app.buttons["home.week.day.\(dayKey(Self.colts))"]
        XCTAssertTrue(resultDay.waitForExistence(timeout: 10), "The Colts game's day isn't in the strip.")
        resultDay.tap()
        XCTAssertTrue(app.buttons["home.result.401872945"].waitForExistence(timeout: 5), "The Colts result isn't on its day.")
        XCTAssertFalse(app.buttons["home.upcoming.401872945"].exists, "A result showed as a game to come.")

        XCTAssertFalse(app.buttons["home.week.day.\(dayKey(Self.broncos))"].exists, "A day six days back is in the strip.")
        XCTAssertFalse(app.buttons["home.result.401872931"].exists, "A result six days back is in This Week.")

        app.buttons["home.week.day.\(dayKey(Self.dolphins))"].tap()
        XCTAssertTrue(app.buttons["home.upcoming.401872952"].waitForExistence(timeout: 5), "The next game isn't on its day.")
        XCTAssertFalse(app.buttons["home.result.401872945"].exists, "The result stayed on the next game's day.")
    }

    /// With no game this week, This Week is one line and the news feed is
    /// still there below it, its stories there to open.
    @MainActor
    func testNewsFeedWithoutGames() throws {
        let app = launchWithFixtures(following: Self.chiefs, now: Self.offSeason)

        XCTAssertTrue(element("home.section.week", in: app).waitForExistence(timeout: 15), "No This Week on Home.")
        XCTAssertTrue(element("home.week.empty", in: app).waitForExistence(timeout: 10), "This Week didn't say it has no games.")
        let weekGames = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
            "home.upcoming.", "home.result.", "home.live."
        ))
        XCTAssertEqual(weekGames.count, 0, "This Week showed games in the off-season.")

        let news = element("home.section.news", in: app)
        for _ in 0..<6 where !news.exists {
            app.swipeUp()
        }
        XCTAssertTrue(news.waitForExistence(timeout: 15), "No news feed on Home.")
        let row = app.buttons["home.news.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The news feed has no stories.")
        for _ in 0..<6 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "The feed's first story never scrolled into view.")

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

    /// A launch that asks for onboarding (`ThemeOnboarding.launchKey`)
    /// opens on the walkthrough's first page; swiping and Next step
    /// through its pages, the last offering Get Started, which hands off
    /// to the theme step; Continue there closes the sheet.
    @MainActor
    func testWalkthroughStepsToThemeStep() throws {
        let app = launch(environment: ["MYTEAMS_ONBOARDING": "1"])
        let skip = app.buttons["onboarding.walkthrough.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "The walkthrough never showed.")
        XCTAssertTrue(waitOnScreen(element("onboarding.walkthrough.page.1", in: app), in: app), "The walkthrough didn't open on its first page.")

        // Swiped to the second page.
        element("onboarding.walkthrough.page.1", in: app).swipeLeft()
        XCTAssertTrue(waitOnScreen(element("onboarding.walkthrough.page.2", in: app), in: app), "A swipe didn't turn to the second page.")
        XCTAssertFalse(app.buttons["onboarding.walkthrough.getStarted"].exists, "Get Started before the last page.")

        // Next to the last.
        let next = app.buttons["onboarding.walkthrough.next"]
        XCTAssertTrue(next.exists, "No Next on the second page.")
        next.tap()
        XCTAssertTrue(waitOnScreen(element("onboarding.walkthrough.page.3", in: app), in: app), "Next didn't turn to the last page.")
        XCTAssertTrue(skip.exists, "Skip went missing on the last page.")

        let getStarted = app.buttons["onboarding.walkthrough.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "No Get Started on the last page.")
        XCTAssertFalse(next.exists, "Next on the last page.")
        getStarted.tap()

        let continueButton = app.buttons["onboarding.theme.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Get Started didn't hand off to the theme step.")
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "The walkthrough stayed under the theme step.")
        continueButton.tap()
        XCTAssertTrue(continueButton.waitForNonExistence(timeout: 5), "Continue didn't close onboarding.")
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
    }

    /// The walkthrough's Skip goes straight to the theme step, from its
    /// first page.
    @MainActor
    func testWalkthroughSkipsToThemeStep() throws {
        let app = launch(environment: ["MYTEAMS_ONBOARDING": "1"])
        let skip = app.buttons["onboarding.walkthrough.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "The walkthrough never showed.")
        skip.tap()

        XCTAssertTrue(app.buttons["onboarding.theme.continue"].waitForExistence(timeout: 5), "Skip didn't go to the theme step.")
        XCTAssertFalse(element("onboarding.walkthrough.page.1", in: app).exists, "The walkthrough stayed up.")
    }

    /// Past the walkthrough, the theme step shows over Home, with every
    /// palette, Continue pinned below the grid; Skip closes it. (That it
    /// never comes back is `BrandThemeTests`'.)
    @MainActor
    func testThemeOnboardingSkips() throws {
        let app = launch(environment: ["MYTEAMS_ONBOARDING": "1"])
        let walkthroughSkip = app.buttons["onboarding.walkthrough.skip"]
        XCTAssertTrue(walkthroughSkip.waitForExistence(timeout: 10), "The walkthrough never showed.")
        walkthroughSkip.tap()

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

    /// `"2026-09-27"`: the day `seconds` falls on in the device's calendar,
    /// which the app's strip keys its days by (`home.week.day.<key>`). The
    /// tests run on the same device, so the two agree in any time zone.
    private func dayKey(_ seconds: TimeInterval) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: seconds))
        func padded(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(parts.year, 4))-\(padded(parts.month, 2))-\(padded(parts.day, 2))"
    }

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

    /// Waits for `element` to be in view: centred in the window, not just
    /// in the hierarchy, as a paged view's neighbouring pages are.
    @MainActor
    private func waitOnScreen(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists {
                let frame = element.frame
                if app.windows.firstMatch.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
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
