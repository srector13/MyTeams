//
//  GUIAuditScreenshotTests.swift
//  myTeamsUITests
//
//  A best-effort screenshot tour for a GUI audit: every reachable screen,
//  written as PNGs to `AUDIT_SHOTS_DIR` (and kept as attachments). Opt-in:
//  runs only with `AUDIT_SHOTS=1` in the runner's environment
//  (TEST_RUNNER_AUDIT_SHOTS=1 via xcodebuild). Nothing here asserts; a
//  screen that can't be reached is skipped and logged in `_missed.txt`.
//

import XCTest

final class GUIAuditScreenshotTests: XCTestCase {

    static let bundledTeams = [
        "basketball/mens-college-basketball:2305",
        "football/nfl:12",
        "baseball/mlb:7",
        "soccer/usa.1:186",
    ].joined(separator: ",")

    /// More favorites than the bar holds, so the overflow shows.
    static let manyTeams = [
        "basketball/mens-college-basketball:2305",
        "football/nfl:12",
        "baseball/mlb:7",
        "soccer/usa.1:186",
        "football/nfl:16",
        "basketball/nba:13",
        "hockey/nhl:21",
        "football/college-football:2305",
    ].joined(separator: ",")

    enum TypeSize: String {
        case large = "UICTContentSizeCategoryL"
        case accessibility3 = "UICTContentSizeCategoryAccessibilityXL"
        case extraSmall = "UICTContentSizeCategoryXS"
    }

    private var run = "run"
    private var counter = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard ProcessInfo.processInfo.environment["AUDIT_SHOTS"] == "1" else {
            throw XCTSkip("Set AUDIT_SHOTS=1 to run the GUI audit tour.")
        }
    }

    // MARK: Runs (alphabetical = execution order)

    @MainActor
    func test01_Onboarding() {
        for dark in [false, true] {
            run = "01-onboarding-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark, environment: ["MYTEAMS_ONBOARDING": "1"])
            let skip = app.buttons["onboarding.walkthrough.skip"]
            guard skip.waitForExistence(timeout: 15) else { miss("walkthrough"); app.terminate(); continue }
            pause(1.5)
            shot("walkthrough-page1")
            let next = app.buttons["onboarding.walkthrough.next"]
            if next.exists { next.tap(); pause(1.2); shot("walkthrough-page2") }
            if next.exists { next.tap(); pause(1.2); shot("walkthrough-page3") }
            let getStarted = app.buttons["onboarding.walkthrough.getStarted"]
            if getStarted.waitForExistence(timeout: 3) { getStarted.tap() } else if skip.exists { skip.tap() }
            if app.buttons["onboarding.theme.continue"].waitForExistence(timeout: 8) {
                pause(1.5)
                shot("theme-step")
                app.swipeUp(); pause(1)
                shot("theme-step-scrolled")
                app.buttons["onboarding.theme.skip"].tapIfExists()
                pause(1.5)
                shot("after-onboarding")
            } else {
                miss("theme step")
            }
            app.terminate()
        }
    }

    @MainActor
    func test02_EmptyState() {
        for dark in [false, true] {
            run = "02-empty-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark, favorites: "none")
            let add = app.buttons["home.addTeams"]
            guard add.waitForExistence(timeout: 15) else { miss("empty home"); app.terminate(); continue }
            pause(2)
            shot("home-empty")
            add.tap()
            if app.buttons["teamBrowser.done"].waitForExistence(timeout: 8) {
                pause(2)
                shot("team-browser-first-run")
            }
            app.terminate()
        }
    }

    @MainActor
    func test03_LiveTourLight() { liveTour(dark: false) }

    @MainActor
    func test04_LiveTourDark() { liveTour(dark: true) }

    @MainActor
    func test05_DynamicTypeAX3() {
        typeTour(name: "05-ax3", size: .accessibility3)
    }

    @MainActor
    func test06_DynamicTypeXS() {
        typeTour(name: "06-xs", size: .extraSmall)
    }

    @MainActor
    func test07_FixtureHomeMidSeason() {
        for dark in [false, true] {
            run = "07-fixtures-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark, favorites: "football/nfl:12", environment: [
                "MYTEAMS_FIXTURES_DIR": fixturesPath,
                "MYTEAMS_HOME_NOW": "1790424000",
            ])
            guard waitForHome(app) else { app.terminate(); continue }
            pause(3)
            shot("home-midseason")
            app.swipeUp(); pause(1.2); shot("home-midseason-scrolled")
            app.swipeUp(); pause(1.2); shot("home-midseason-scrolled2")
            app.terminate()
        }
    }

    @MainActor
    func test08_ManyTeamsOverflow() {
        run = "08-many-teams"
        counter = 0
        let app = launch(dark: false, favorites: Self.manyTeams)
        guard waitForHome(app) else { app.terminate(); return }
        pause(4)
        shot("home-many-teams")
        let more = app.tabBars.buttons["More"]
        if more.waitForExistence(timeout: 3) {
            more.tap(); pause(2); shot("more-list")
        } else {
            shot("tabbar-no-more")
        }
        app.terminate()
    }

    @MainActor
    func test09_Accessibility() {
        let variants: [(String, [String: String], Bool)] = [
            ("hc-light", ["GLASSUI_INCREASE_CONTRAST": "1"], false),
            ("rt-dark", ["GLASSUI_REDUCE_TRANSPARENCY": "1"], true),
        ]
        for (name, env, dark) in variants {
            run = "09-a11y-\(name)"
            counter = 0
            let app = launch(dark: dark, environment: env)
            guard waitForHome(app) else { app.terminate(); continue }
            pause(4)
            shot("home")
            if openTeam(app, index: 0) {
                pause(4)
                shot("team-page")
                app.swipeUp(); pause(1.2); shot("team-page-scrolled")
            }
            app.terminate()
        }
    }

    /// Last: it changes the stored palette, then puts Classic back.
    @MainActor
    func test10_ThemePalette() {
        run = "10-theme"
        counter = 0
        let app = launch(dark: false)
        guard waitForHome(app), openSettings(app) else { app.terminate(); return }
        let themeRow = app.buttons["settings.theme"]
        guard themeRow.waitForExistence(timeout: 5) else { miss("theme row"); app.terminate(); return }
        themeRow.tap(); pause(1.5)
        for palette in ["red", "graphite"] {
            let tile = element("settings.theme.\(palette)", in: app)
            for _ in 0..<4 where !(tile.exists && tile.isHittable) { app.swipeUp(); pause(0.5) }
            guard tile.exists else { miss("tile \(palette)"); continue }
            tile.tap(); pause(1.5)
            shot("theme-settings-\(palette)")
        }
        app.buttons["settings.done"].tapIfExists()
        if !app.buttons["settings.done"].exists { pause(1) } else { app.swipeDown() }
        pause(1.5)
        shot("home-graphite")
        if openTeam(app, index: 1) { pause(4); shot("team-page-graphite") }
        // Dark with the palette.
        app.terminate()
        let darkApp = launch(dark: true)
        if waitForHome(darkApp) {
            pause(3); shot("home-graphite-dark")
            if openTeam(darkApp, index: 1) { pause(4); shot("team-page-graphite-dark") }
            // Restore Classic.
            if openSettings(darkApp) {
                darkApp.buttons["settings.theme"].tapIfExists(); pause(1.5)
                let classic = element("settings.theme.classic", in: darkApp)
                for _ in 0..<4 where !(classic.exists && classic.isHittable) { darkApp.swipeDown(); pause(0.5) }
                classic.tapIfExists()
            }
        }
        darkApp.terminate()
    }

    /// The redesigned Home: the hero, each section, the week strip's days,
    /// Customize Home, and a team card opening its tab; live data in both
    /// appearances, then the fixture-pinned mid-season week.
    @MainActor
    func test11_HomeRedesign() {
        for dark in [false, true] {
            run = "11-home-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark)
            guard waitForHome(app) else { app.terminate(); continue }
            pause(6)
            shot("top")
            for i in 1...6 { app.swipeUp(); pause(1.2); shot("scroll\(i)") }
            // Customize Home, at the foot.
            let customize = app.buttons["home.customize"]
            for _ in 0..<3 where !(customize.exists && customize.isHittable) { app.swipeUp(); pause(0.6) }
            if customize.exists && customize.isHittable {
                customize.tap(); pause(1.5); shot("customize")
                app.buttons["home.customize.done"].tapIfExists(); pause(1)
            } else { miss("customize") }
            for _ in 0..<8 { app.swipeDown() }
            pause(1)
            // Another day in the strip.
            let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.week.day."))
            if days.count > 4 {
                let day = days.element(boundBy: 4)
                if day.isHittable { day.tap(); pause(1.5); shot("week-day") }
            }
            // A team card opens its tab.
            let card = app.descendants(matching: .any)["home.myTeams.football/nfl:12"].firstMatch
            if card.waitForExistence(timeout: 5), card.isHittable {
                card.tap(); pause(4); shot("team-from-card")
            } else { miss("my teams card") }
            app.terminate()
        }

        run = "11-home-fixtures"
        counter = 0
        let app = launch(dark: false, favorites: "football/nfl:12", environment: [
            "MYTEAMS_FIXTURES_DIR": fixturesPath,
            "MYTEAMS_HOME_NOW": "1790424000",
        ])
        if waitForHome(app) {
            pause(4)
            shot("midseason-top")
            app.swipeUp(); pause(1.2); shot("midseason-scroll1")
            app.swipeUp(); pause(1.2); shot("midseason-scroll2")
        }
        app.terminate()
    }

    /// Player sheets across sports (soccer first), each scrolled through,
    /// and a game sheet's header, for the player-sheet audit.
    @MainActor
    func test12_PlayerSheets() {
        for dark in [false, true] {
            run = "12-players-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark)
            guard waitForHome(app) else { app.terminate(); continue }
            pause(3)
            for index in [3, 1, 2] {
                app.terminate(); app.launch()
                _ = waitForHome(app)
                pause(2)
                guard openTeam(app, index: index) else { continue }
                pause(5)
                let players = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", "roster.player"))
                guard players.firstMatch.waitForExistence(timeout: 10) else { miss("team\(index) roster"); continue }
                // The first two players with a sheet each.
                for n in 0..<2 {
                    let hittable = players.allElementsBoundByIndex.filter { $0.isHittable }
                    guard hittable.count > n else { break }
                    hittable[n].tap()
                    let close = app.buttons["playerDetail.close"]
                    guard close.waitForExistence(timeout: 8) else { miss("team\(index) player \(n)"); continue }
                    pause(4)
                    shot("team\(index)-player\(n)-top")
                    for i in 1...3 { app.swipeUp(); pause(1.2); shot("team\(index)-player\(n)-scroll\(i)") }
                    close.tapIfExists(); pause(1.5)
                }
                if !dark, let game = firstHittable("schedule.game", in: app, swipes: 4) {
                    game.tap()
                    if app.buttons["gameDetail.close"].waitForExistence(timeout: 8) {
                        pause(3); shot("team\(index)-game-sheet")
                        app.buttons["gameDetail.close"].tapIfExists(); pause(1)
                    }
                }
            }
            app.terminate()
        }
    }

    // MARK: Tours

    @MainActor
    private func liveTour(dark: Bool) {
        run = dark ? "04-live-dark" : "03-live-light"
        counter = 0
        let app = launch(dark: dark)
        guard waitForHome(app) else { app.terminate(); return }
        pause(5)
        shot("home")
        for i in 1...4 { app.swipeUp(); pause(1.2); shot("home-scroll\(i)") }
        for _ in 0..<5 { app.swipeDown() }

        // A Home news story.
        let row = app.buttons["home.news.row"].firstMatch
        if row.exists && row.isHittable {
            row.tap(); pause(3); shot("home-news-detail")
            dismissSheet(app)
        }

        // Each bundled team's page, scrolled to its end.
        for index in 0..<4 {
            app.terminate()
            app.launch()
            _ = waitForHome(app)
            pause(2)
            guard openTeam(app, index: index) else { continue }
            pause(5)
            shot("team\(index + 1)-top")
            for i in 1...7 { app.swipeUp(); pause(1.0); shot("team\(index + 1)-scroll\(i)") }
            for _ in 0..<9 { app.swipeDown() }
            pause(0.8)
            if index == 0 || index == 1 {
                playerSheet(app, team: index + 1)
                gameSheet(app, team: index + 1)
                leadersSheet(app, team: index + 1)
                newsSheet(app, team: index + 1)
                for _ in 0..<9 { app.swipeDown() }
            }
        }

        // Settings and everything under it.
        if openSettings(app) {
            pause(1.5)
            shot("settings")
            app.swipeUp(); pause(1); shot("settings-scrolled")
            app.swipeDown(); app.swipeDown()
            for (id, name) in [("settings.theme", "theme"), ("settings.alerts", "alerts"), ("settings.teams", "teams"), ("settings.advanced", "advanced")] {
                let button = app.buttons[id]
                for _ in 0..<3 where !(button.exists && button.isHittable) { app.swipeUp(); pause(0.4) }
                guard button.exists else { miss("settings row \(id)"); continue }
                button.tap(); pause(2)
                shot("settings-\(name)")
                app.swipeUp(); pause(1); shot("settings-\(name)-scrolled")
                backOrClose(app)
                pause(1)
                for _ in 0..<2 { app.swipeDown() }
            }
            // Team browser from Settings.
            let addTeams = app.buttons["settings.addTeams"]
            for _ in 0..<3 where !(addTeams.exists && addTeams.isHittable) { app.swipeUp(); pause(0.4) }
            if addTeams.exists {
                addTeams.tap()
                if app.buttons["teamBrowser.done"].waitForExistence(timeout: 8) {
                    pause(1.5)
                    shot("browser")
                    let sport = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.sport.")).element(boundBy: 1)
                    if sport.waitForExistence(timeout: 5) {
                        sport.tap(); pause(2); shot("browser-sport")
                        let league = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamBrowser.league.")).firstMatch
                        if league.waitForExistence(timeout: 5) {
                            league.tap(); pause(4); shot("browser-league")
                            app.swipeUp(); pause(1); shot("browser-league-scrolled")
                            app.navigationBars.buttons.element(boundBy: 0).tapIfExists(); pause(1)
                        }
                        app.navigationBars.buttons.element(boundBy: 0).tapIfExists(); pause(1)
                    }
                    let search = app.searchFields.firstMatch
                    if search.waitForExistence(timeout: 3) {
                        search.tap(); search.typeText("Lakers"); pause(4)
                        shot("browser-search")
                        app.buttons["Cancel"].tapIfExists(); pause(1)
                    }
                    let edit = app.buttons["Edit"]
                    if edit.exists { edit.tap(); pause(1.5); shot("browser-edit"); app.buttons["Done"].firstMatch.tapIfExists() }
                }
            }
        }
        app.terminate()
    }

    @MainActor
    private func typeTour(name: String, size: TypeSize) {
        for dark in [false] {
            run = "\(name)-\(dark ? "dark" : "light")"
            counter = 0
            let app = launch(dark: dark, typeSize: size)
            guard waitForHome(app) else { app.terminate(); continue }
            pause(5)
            shot("home")
            app.swipeUp(); pause(1.2); shot("home-scroll1")
            app.swipeUp(); pause(1.2); shot("home-scroll2")
            app.terminate()
            app.launch()
            _ = waitForHome(app)
            pause(2)
            if openTeam(app, index: 1) {
                pause(5)
                shot("team-top")
                for i in 1...5 { app.swipeUp(); pause(1); shot("team-scroll\(i)") }
                for _ in 0..<7 { app.swipeDown() }
                playerSheet(app, team: 2)
                gameSheet(app, team: 2)
            }
            if openSettings(app) {
                pause(1.5); shot("settings")
                app.swipeUp(); pause(1); shot("settings-scrolled")
                let theme = app.buttons["settings.theme"]
                for _ in 0..<3 where !(theme.exists && theme.isHittable) { app.swipeDown(); pause(0.4) }
                if theme.exists { theme.tap(); pause(1.5); shot("settings-theme") }
            }
            app.terminate()
        }
    }

    // MARK: Sheets

    @MainActor
    private func playerSheet(_ app: XCUIApplication, team: Int) {
        guard let player = firstHittable("roster.player", in: app, swipes: 5) else { miss("team\(team) roster"); return }
        player.tap()
        let close = app.buttons["playerDetail.close"]
        guard close.waitForExistence(timeout: 8) else { miss("team\(team) player sheet"); return }
        pause(3)
        shot("team\(team)-player")
        app.swipeUp(); pause(1); shot("team\(team)-player-scrolled")
        // The sheet's sections, if it has a picker.
        let picker = element("playerDetail.section", in: app)
        if picker.exists {
            let segments = picker.buttons
            for i in stride(from: 1, to: min(segments.count, 4), by: 1) {
                segments.element(boundBy: i).tapIfExists(); pause(2)
                shot("team\(team)-player-section\(i)")
            }
        }
        close.tapIfExists()
        pause(1)
        for _ in 0..<6 { app.swipeDown() }
    }

    @MainActor
    private func gameSheet(_ app: XCUIApplication, team: Int) {
        guard let game = firstHittable("schedule.game", in: app, swipes: 6) else { miss("team\(team) schedule"); return }
        shot("team\(team)-schedule-cards")
        game.tap()
        let close = app.buttons["gameDetail.close"]
        guard close.waitForExistence(timeout: 8) else { miss("team\(team) game sheet"); return }
        pause(3)
        shot("team\(team)-game-medium")
        // Drag the sheet to large, then scroll its content.
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        top.press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        pause(1.5)
        shot("team\(team)-game-large")
        for i in 1...4 { app.swipeUp(); pause(1); shot("team\(team)-game-scroll\(i)") }
        let timeline = element("gameDetail.timeline.toggle", in: app)
        if timeline.exists && timeline.isHittable { timeline.tap(); pause(1.5); shot("team\(team)-game-timeline") }
        close.tapIfExists()
        pause(1)
        for _ in 0..<6 { app.swipeDown() }
    }

    @MainActor
    private func leadersSheet(_ app: XCUIApplication, team: Int) {
        guard let leaders = firstHittable("leaders.league", in: app, swipes: 7) else { miss("team\(team) leaders button"); return }
        leaders.tap()
        let close = app.buttons["leagueLeaders.close"]
        guard close.waitForExistence(timeout: 8) else { miss("team\(team) leaders sheet"); return }
        pause(3)
        shot("team\(team)-league-leaders")
        app.swipeUp(); pause(1); shot("team\(team)-league-leaders-scrolled")
        close.tapIfExists()
        pause(1)
        for _ in 0..<8 { app.swipeDown() }
    }

    @MainActor
    private func newsSheet(_ app: XCUIApplication, team: Int) {
        guard let article = firstHittable("news.article", in: app, swipes: 12) else { miss("team\(team) news"); return }
        article.tap()
        pause(4)
        shot("team\(team)-news-detail")
        dismissSheet(app)
    }

    // MARK: Helpers

    private var fixturesPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("myTeamsTests")
            .appendingPathComponent("Fixtures")
            .path
    }

    @MainActor
    private func launch(dark: Bool, favorites: String = bundledTeams, typeSize: TypeSize = .large, environment: [String: String] = [:]) -> XCUIApplication {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = XCUIApplication()
        app.launchEnvironment["MYTEAMS_FAVORITES"] = favorites
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", typeSize.rawValue]
        // The app's own Appearance setting (`AppAppearance.storageKey`), as
        // the device appearance alone doesn't reach a relaunched app here.
        app.launchArguments += ["-settings.appearance", dark ? "dark" : "light"]
        app.launch()
        return app
    }

    @MainActor
    private func waitForHome(_ app: XCUIApplication) -> Bool {
        let gear = app.buttons["home.settings"]
        if gear.waitForExistence(timeout: 20) { return true }
        shot("home-never-appeared")
        miss("home")
        return false
    }

    @MainActor
    private func openTeam(_ app: XCUIApplication, index: Int) -> Bool {
        let byID = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "teamPicker.team."))
        for _ in 0..<3 where !(byID.count > index && byID.element(boundBy: index).isHittable) { app.swipeDown(); pause(0.4) }
        var tab = byID.count > index ? byID.element(boundBy: index) : app.tabBars.buttons.element(boundBy: index + 1)
        if !tab.exists {
            // By label, for a bar that lost its identifiers.
            let names = ["Hawkeyes", "Chiefs", "Royals", "Sporting"]
            if index < names.count {
                tab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS %@", names[index])).firstMatch
            }
        }
        guard tab.waitForExistence(timeout: 5), tab.isHittable else {
            shot("team-tab-\(index)-not-found")
            miss("team tab \(index)")
            return false
        }
        tab.tap()
        return true
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) -> Bool {
        let gear = app.buttons["home.settings"].firstMatch
        guard gear.waitForExistence(timeout: 5) else { miss("settings gear"); return false }
        let done = app.buttons["settings.done"]
        for _ in 0..<3 where !done.exists {
            gear.tap()
            _ = done.waitForExistence(timeout: 4)
        }
        if !done.exists { miss("settings"); return false }
        return true
    }

    @MainActor
    private func backOrClose(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap() }
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        let candidates = [app.buttons["newsDetail.close"], app.buttons["Done"].firstMatch, app.buttons["Close"].firstMatch]
        for button in candidates where button.exists && button.isHittable {
            button.tap(); pause(1); return
        }
        app.swipeDown(velocity: .fast)
        pause(1)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func firstHittable(_ identifier: String, in app: XCUIApplication, swipes: Int = 0) -> XCUIElement? {
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifier))
        guard matches.firstMatch.waitForExistence(timeout: 8) else { return nil }
        for attempt in 0...swipes {
            if attempt > 0 { app.swipeUp(); pause(0.6) }
            if let element = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                return element
            }
        }
        return nil
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private var outputDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["AUDIT_SHOTS_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func shot(_ screen: String) {
        counter += 1
        let name = String(format: "%@__%02d-%@", run, counter, screen)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = outputDirectory {
            try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private func miss(_ what: String) {
        guard let dir = outputDirectory else { return }
        let line = "\(run): missed \(what)\n"
        let file = dir.appendingPathComponent("_missed.txt")
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}

@MainActor
private extension XCUIElement {
    func tapIfExists() {
        if exists && isHittable { tap() }
    }
}
