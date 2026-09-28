//
//  StatLeadersTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The P3-d leaders fixtures: `{key}_leaders` for every registered league and
/// `{key}_leaders_team_{id}` for four teams, captured by
/// `scripts/capture_fixtures_p3d.py` five deep (`limit=5`). See FIXTURES.md,
/// "Stat leaders (P3-d)".
private let leagueFixtures: [(fixture: String, league: LeagueID)] = [
    ("ncaam_leaders", .mensCollegeBasketball), ("nfl_leaders", .nfl), ("mlb_leaders", .mlb),
    ("mls_leaders", .mls), ("nba_leaders", .nba), ("wnba_leaders", .wnba),
    ("ncaaw_leaders", .womensCollegeBasketball), ("nhl_leaders", .nhl),
    ("ncaaf_leaders", .collegeFootball), ("epl_leaders", .premierLeague),
    ("laliga_leaders", .laLiga), ("ligamx_leaders", .ligaMX), ("nwsl_leaders", .nwsl),
]

private func leaders(_ fixture: String) throws -> StatLeaders {
    parseStatLeaders(from: try Fixture.json(fixture))
}

/// 2026-09-28, the day the fixtures were captured.
private let captureDay = Date(timeIntervalSince1970: 1_790_553_600)

// MARK: - Registry

@Suite("Stat leaders: registry URLs")
struct LeadersURLTests {
    private let site = "https://site.api.espn.com/apis/site/v3/sports"

    @Test("US leagues leave the season to the feed")
    func unnamedSeason() {
        #expect(LeagueID.nba.leadersURL() == "\(site)/basketball/nba/leaders?limit=10")
        // A season is named only alongside a season type, which the NBA has none of.
        #expect(LeagueID.nba.leadersURL(season: 2027) == "\(site)/basketball/nba/leaders?limit=10")
        #expect(LeagueID.nhl.leadersURL(teamID: "25", limit: 5) == "\(site)/hockey/nhl/leaders?limit=5&team=25")
        #expect(LeagueID.nba.descriptor.leadersSeason(at: captureDay) == nil)
        #expect(LeagueID.collegeFootball.descriptor.leadersSeason(at: captureDay) == nil)
    }

    @Test("Soccer names its season, by its own numbering, and the regular season type")
    func soccerSeason() {
        for league in LeagueID.knownLeagues {
            let expected: String? = league.descriptor.kind == .soccer ? "1" : nil
            #expect(league.descriptor.leadersSeasonType == expected, "\(league)")
        }
        // Starting year for European soccer (2026-27 is 2026); calendar year for MLS and NWSL.
        #expect(LeagueID.premierLeague.descriptor.leadersSeason(at: captureDay) == 2026)
        #expect(LeagueID.ligaMX.descriptor.leadersSeason(at: captureDay) == 2026)
        #expect(LeagueID.mls.descriptor.leadersSeason(at: captureDay) == 2026)
        #expect(
            LeagueID.premierLeague.leadersURL(teamID: "359", season: 2026, limit: 5)
                == "\(site)/soccer/eng.1/leaders?limit=5&season=2026&seasontype=1&team=359"
        )
    }

    @Test("The registry builds the URL each leaders fixture was captured from")
    func fixtureURLs() {
        // FIXTURES.md, "Stat leaders (P3-d)": every file's URL.
        for (fixture, league) in leagueFixtures {
            let season = league.descriptor.leadersSeason(at: captureDay)
            let query = season.map { "&season=\($0)&seasontype=1" } ?? ""
            #expect(
                league.leadersURL(season: season, limit: 5) == "\(site)/\(league.path)/leaders?limit=5\(query)",
                "\(fixture)"
            )
        }
    }
}

// MARK: - Parsing

@Suite("Stat leaders: parsing", .tags(.golden))
struct StatLeadersParsingTests {
    @Test("NBA: season, categories and the points leader, by name")
    func nba() throws {
        let nba = try leaders("nba_leaders")
        // requestedSeason: in the 2026-27 preseason the feed answers with 2025-26.
        #expect(nba.season == 2026)
        #expect(nba.seasonName == "2025-26")
        #expect(nba.seasonType == "Regular Season")
        #expect(nba.categories.map(\.name) == [
            "pointsPerGame", "assistsPerGame", "fieldGoalPercentage", "reboundsPerGame",
            "stealsPerGame", "blocksPerGame", "FreeThrowPct", "3PointPct", "PER",
            "3PointsMadePerGame", "doubleDouble", "minutesPerGame", "foulsPerGame",
            "points", "NBARating", "avgTurnovers",
        ])
        #expect(nba.categories.allSatisfy { $0.leaders.count == 5 })

        let points = try #require(nba.category(named: "pointsPerGame"))
        #expect(points.displayName == "Points Per Game")
        #expect(points.abbreviation == "PTS")
        let doncic = try #require(points.leaders.first)
        #expect(doncic.athleteID == "3945274")
        #expect(doncic.name == "Luka Doncic")
        #expect(doncic.shortName == "L. Doncic")
        #expect(doncic.position == "G")
        #expect(doncic.teamID == "13")
        #expect(doncic.teamAbbreviation == "LAL")
        #expect(doncic.value == 33.484375)
        #expect(doncic.displayValue == "33.5")
        #expect(doncic.headshotURL == "https://a.espncdn.com/i/headshots/nba/players/full/3945274.png")

        // reboundsPerGame[0]: Nikola Jokic (7, DEN) 12.861538887023926.
        #expect(nba.category(named: "reboundsPerGame")?.leaders.first?.name == "Nikola Jokic")
    }

    @Test("NHL: goals, points and the goalie boards")
    func nhl() throws {
        let nhl = try leaders("nhl_leaders")
        #expect(nhl.categories.map(\.name) == [
            "goals", "assists", "points", "plusMinus", "avgGoalsAgainst",
            "penaltyMinutes", "savePct", "wins", "shutouts",
        ])
        #expect(nhl.category(named: "goals")?.leaders.first?.name == "Nathan MacKinnon")
        #expect(nhl.category(named: "goals")?.leaders.first?.value == 53)
        #expect(nhl.category(named: "points")?.leaders.first?.name == "Connor McDavid")
        #expect(nhl.category(named: "points")?.leaders.first?.value == 138)
        #expect(nhl.category(named: "savePct")?.leaders.first?.value == 0.921)  // Scott Wedgewood
    }

    @Test("Premier League: the soccer boards, with no headshots")
    func premierLeague() throws {
        let epl = try leaders("epl_leaders")
        #expect(epl.season == 2026)
        #expect(epl.seasonName == "2026-27 English Premier League")
        #expect(epl.categories.count == 12)
        let haaland = try #require(epl.category(named: "goalsLeaders")?.leaders.first)
        #expect(haaland.name == "Erling Haaland")
        #expect(haaland.teamAbbreviation == "MNC")
        #expect(haaland.value == 5)
        #expect(haaland.displayValue == "Matches: 5, Goals: 5")
        #expect(haaland.headshotURL == "")
    }

    @Test("Every league's feed parses, and lists every board its sport shows")
    func everyLeague() throws {
        for (fixture, league) in leagueFixtures {
            let parsed = try leaders(fixture)
            #expect(parsed.season == 2026, "\(fixture)")
            let names = Set(parsed.categories.map(\.name))
            for spec in league.descriptor.leaderCategories {
                #expect(names.contains(spec.name), "\(fixture) lacks \(spec.name)")
            }
            #expect(parsed.categories.allSatisfy { !$0.leaders.isEmpty }, "\(fixture)")
        }
    }

    @Test("A team's feed lists only its players, and drops a board it leads nobody on")
    func teamFeeds() throws {
        let teams = [("nba_leaders_team_1", "1"), ("nhl_leaders_team_25", "25"),
                     ("epl_leaders_team_359", "359"), ("ncaaf_leaders_team_2305", "2305")]
        for (fixture, teamID) in teams {
            let parsed = try leaders(fixture)
            #expect(!parsed.isEmpty, "\(fixture)")
            #expect(parsed.categories.allSatisfy { $0.leaders.allSatisfy { $0.teamID == teamID } }, "\(fixture)")
        }

        // nhl_leaders_team_25: 9 categories, `shutouts` with no leaders.
        let ducks = try leaders("nhl_leaders_team_25")
        #expect(ducks.categories.count == 8)
        #expect(ducks.category(named: "shutouts") == nil)
        #expect(ducks.category(named: "goals")?.leaders.first?.name == "Cutter Gauthier")

        // ncaaf_leaders_team_2305: `interceptions` is empty.
        #expect(try leaders("ncaaf_leaders_team_2305").category(named: "interceptions") == nil)

        // nba_leaders_team_1 pointsPerGame[0]: Jalen Johnson 22.51388931274414.
        #expect(try leaders("nba_leaders_team_1").category(named: "pointsPerGame")?.leaders.first?.name == "Jalen Johnson")
    }

    @Test("A failed fetch parses to nothing")
    func emptyDocument() {
        #expect(parseStatLeaders(from: .null) == StatLeaders(season: nil, seasonName: "", seasonType: "", categories: []))
        #expect(parseStatLeaders(from: .null).isEmpty)
    }
}

// MARK: - Boards

@Suite("Stat leaders: boards by sport", .tags(.golden))
struct LeaderBoardTests {
    @Test("Values are formatted from the figure, not the feed's text")
    func formats() {
        #expect(LeaderValueFormat.whole.format(53, displayValue: "") == "53")
        #expect(LeaderValueFormat.tenths.format(33.484375, displayValue: "") == "33.5")
        #expect(LeaderValueFormat.hundredths.format(2.024, displayValue: "") == "2.02")
        #expect(LeaderValueFormat.rate.format(0.3156965970993042, displayValue: "") == ".316")
        #expect(LeaderValueFormat.rate.format(1.033491849899292, displayValue: "") == "1.033")
        #expect(LeaderValueFormat.signed.format(57, displayValue: "") == "+57")
        #expect(LeaderValueFormat.signed.format(-2, displayValue: "") == "-2")
        #expect(LeaderValueFormat.signed.format(0, displayValue: "") == "0")
        #expect(LeaderValueFormat.wholeOrTenths.format(3.5, displayValue: "4") == "3.5")
        #expect(LeaderValueFormat.wholeOrTenths.format(4, displayValue: "4") == "4")
        #expect(LeaderValueFormat.feed.format(0, displayValue: "Matches: 5") == "Matches: 5")
    }

    @Test("Basketball: points, rebounds, assists … labelled PPG, RPG, APG")
    func basketball() throws {
        let boards = leaderBoards(from: try leaders("nba_leaders"), kind: .basketball, depth: 5)
        #expect(boards.map(\.label) == ["PPG", "RPG", "APG", "SPG", "BPG", "FG%"])
        #expect(boards.map(\.title) == ["Points", "Rebounds", "Assists", "Steals", "Blocks", "Field Goal %"])
        #expect(boards.allSatisfy { $0.rows.map(\.rank) == [1, 2, 3, 4, 5] })

        let points = try #require(boards.first)
        #expect(points.rows[0].leader.name == "Luka Doncic")
        #expect(points.rows[0].value == "33.5")
        #expect(points.rows[0].detail == nil)
        // pointsPerGame[1]: Shai Gilgeous-Alexander 31.132352828979492.
        #expect(points.rows[1].value == "31.1")
        #expect(boards[1].rows[0].value == "12.9")  // Jokic 12.861538887023926 RPG
        #expect(boards[2].rows[0].value == "10.7")  // Jokic 10.723076820373535 APG
        #expect(boards[5].rows[0].value == "68.2")  // Rudy Gobert 68.22799682617188 FG%
    }

    @Test("Hockey: goals, assists, points, plus/minus and the goalies'")
    func hockey() throws {
        let boards = leaderBoards(from: try leaders("nhl_leaders"), kind: .hockey, depth: 5)
        #expect(boards.map(\.name) == ["goals", "assists", "points", "plusMinus", "wins", "avgGoalsAgainst", "savePct", "shutouts"])
        #expect(boards.map(\.label) == ["G", "A", "PTS", "+/-", "W", "GAA", "SV%", "SO"])
        func top(_ name: String) -> LeaderBoardRow? { boards.first { $0.name == name }?.rows.first }
        #expect(top("goals")?.value == "53")
        #expect(top("points")?.value == "138")
        #expect(top("plusMinus")?.value == "+57")  // MacKinnon 57.0
        #expect(top("avgGoalsAgainst")?.value == "2.02")  // Wedgewood 2.024
        #expect(top("savePct")?.value == ".921")  // Wedgewood 0.921
        #expect(top("wins")?.leader.name == "Andrei Vasilevskiy")
        #expect(top("wins")?.value == "39")

        // A team's feed: the Ducks lead no shutout board, so it is not shown.
        let ducks = leaderBoards(from: try leaders("nhl_leaders_team_25"), kind: .hockey, depth: 1)
        #expect(ducks.map(\.name) == ["goals", "assists", "points", "plusMinus", "wins", "avgGoalsAgainst", "savePct"])
        #expect(ducks[0].rows.map(\.value) == ["41"])  // Cutter Gauthier
        #expect(ducks[1].rows.first?.leader.name == "Jackson LaCombe")  // 48 assists
    }

    @Test("Football: sacks keep their half, which the feed's text rounds away")
    func football() throws {
        let boards = leaderBoards(from: try leaders("nfl_leaders"), kind: .football, depth: 5)
        #expect(boards.map(\.label) == ["PASS YDS", "PASS TD", "RUSH YDS", "REC YDS", "REC", "TCKL", "SACK", "INT"])
        #expect(boards[0].rows[0].leader.name == "Jordan Love")
        #expect(boards[0].rows[0].value == "844")
        let sacks = try #require(boards.first { $0.name == "sacks" })
        #expect(sacks.rows[0].value == "4")  // Greg Rousseau 4.0
        #expect(sacks.rows[1].leader.name == "T.J. Watt")
        #expect(sacks.rows[1].leader.displayValue == "4")
        #expect(sacks.rows[1].value == "3.5")
        #expect(sacks.rows[1].detail == nil)
    }

    @Test("Soccer: goals and assists, with the matches played as the detail")
    func soccer() throws {
        let boards = leaderBoards(from: try leaders("epl_leaders"), kind: .soccer, depth: 5)
        #expect(boards.map(\.name) == ["goalsLeaders", "assistsLeaders", "shotsOnTarget", "saves"])
        #expect(boards.map(\.label) == ["G", "A", "SOT", "SV"])
        #expect(boards[0].rows[0].leader.name == "Erling Haaland")
        #expect(boards[0].rows[0].value == "5")
        #expect(boards[0].rows[0].detail == "Matches: 5, Goals: 5")
        #expect(boards[1].rows[0].value == "3")  // Antoine Semenyo
        #expect(boards[1].rows[0].detail == "Matches: 5, Assists: 3")
        #expect(boards[2].rows[0].detail == nil)  // shotsOnTarget "10"

        // Arsenal's own: Bukayo Saka, 3 goals in 5.
        let arsenal = leaderBoards(from: try leaders("epl_leaders_team_359"), kind: .soccer, depth: 1)
        #expect(arsenal[0].rows.first?.leader.name == "Bukayo Saka")
        #expect(arsenal[0].rows.first?.value == "3")
    }

    @Test("Baseball: rates without a leading zero, the stat line as detail")
    func baseball() throws {
        let boards = leaderBoards(from: try leaders("mlb_leaders"), kind: .baseball, depth: 5)
        #expect(boards.map(\.label) == ["AVG", "HR", "RBI", "SB", "ERA", "W", "K", "SV"])
        let average = boards[0].rows[0]
        #expect(average.leader.name == "Yordan Alvarez")
        #expect(average.value == ".316")
        #expect(average.detail == "179-567, 42 HR, 3B, 34 2B, 106 RBI, 105 R, 109 BB, SB, 120 K")
        let era = try #require(boards.first { $0.name == "ERA" }?.rows.first)
        #expect(era.leader.name == "Jacob Misiorowski")
        #expect(era.value == "1.80")  // 1.8034000396728516
        #expect(era.detail == "174.2 IP, 35 ER, 96 H, 252 K, 44 BB")
    }

    @Test("A sport with no boards of its own shows the feed's, as the feed writes them")
    func otherSport() throws {
        let boards = leaderBoards(from: try leaders("nba_leaders"), kind: .other, depth: 1)
        #expect(boards.count == 16)
        #expect(boards[0].name == "pointsPerGame")
        #expect(boards[0].title == "Points Per Game")
        #expect(boards[0].label == "PTS")
        #expect(boards[0].rows.map(\.value) == ["33.5"])
    }
}

// MARK: - Team page cache

/// Counts the leaders requests a `TeamModel` makes, answering each from a
/// fixture — or with a failure while `failing` is set.
private actor LeadersFeed {
    private(set) var requests = 0
    var failing = false
    let leaders: StatLeaders

    init(_ leaders: StatLeaders) {
        self.leaders = leaders
    }

    func setFailing(_ failing: Bool) {
        self.failing = failing
    }

    func fetch() -> Result<StatLeaders, NetworkError> {
        requests += 1
        return failing ? .failure(.httpError(status: 503)) : .success(leaders)
    }
}

@Suite("Stat leaders: the team page's cache")
@MainActor
struct TeamLeadersCacheTests {
    /// The model's `loadLeaders` closure is the seam, as `loadStandings` is
    /// for the standings: `downloadStatLeaders` reads `HTTPClient.shared`,
    /// which the model cannot be handed.
    private func makeModel(_ feed: LeadersFeed) -> TeamModel<BasketballPlayer> {
        TeamModel(
            team: .jayhawks,
            newsURL: "",
            loadRoster: { _ in .success([]) },
            loadLeaders: { _ in await feed.fetch() }
        )
    }

    @Test("Leaders load once; a page coming back reads them from the model")
    func loadsOnce() async throws {
        let fixture = try leaders("ncaam_leaders")
        let feed = LeadersFeed(fixture)
        let model = makeModel(feed)
        #expect(model.leadersState == .loading)
        #expect(model.leaders.isEmpty)

        await model.loadLeadersIfNeeded()
        #expect(await feed.requests == 1)
        #expect(model.leadersState == .loaded)
        #expect(model.leaders == leaderBoards(from: fixture, kind: .basketball, depth: 1))
        #expect(!model.leaders.isEmpty)
        #expect(model.leaders.allSatisfy { $0.rows.count <= 1 })

        // The page reappears: no second request.
        await model.loadLeadersIfNeeded()
        #expect(await feed.requests == 1)

        // An explicit refresh does ask again.
        await model.reloadLeaders()
        #expect(await feed.requests == 2)
        #expect(model.leadersState == .loaded)
    }

    @Test("A failed load retries on the next appearance, and keeps what it had on a failed refresh")
    func failureRetries() async throws {
        let feed = LeadersFeed(try leaders("ncaam_leaders"))
        await feed.setFailing(true)
        let model = makeModel(feed)

        await model.loadLeadersIfNeeded()
        #expect(model.leadersState == .failed)
        #expect(await feed.requests == 1)

        await feed.setFailing(false)
        await model.loadLeadersIfNeeded()
        #expect(await feed.requests == 2)
        #expect(model.leadersState == .loaded)
        let shown = model.leaders.count
        #expect(shown > 0)

        // A refresh that fails leaves the boards on screen.
        await feed.setFailing(true)
        await model.reloadLeaders()
        #expect(await feed.requests == 3)
        #expect(model.leaders.count == shown)
    }
}
