//
//  LeagueRegistryTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// One league P3-a, BE-3 or t_67da893e registered, with the fixtures
/// captured for it (see FIXTURES.md, "New leagues (P3-a)", "European soccer
/// leagues (BE-3)" and "European women's leagues (t_67da893e)").
struct CapturedLeague: Sendable, CustomTestStringConvertible {
    let league: LeagueID
    /// The fixture name prefix, e.g. `"nba"`.
    let prefix: String
    /// The team whose schedule, roster and news were captured.
    let teamID: String
    /// The `dates` of the captured scoreboard.
    let scoreboardDay: String
    /// The summary fixture's full name.
    let summary: String

    var testDescription: String { prefix }

    /// Every fixture captured for the league.
    var fixtureNames: [String] {
        ["teams", "schedule", "roster", "news", "standings"].map { "\(prefix)_\($0)" }
            + ["\(prefix)_scoreboard_\(scoreboardDay)", summary]
    }

    static let all: [CapturedLeague] = [
        CapturedLeague(league: .nba, prefix: "nba", teamID: "1", scoreboardDay: "20261003",
                       summary: "nba_summary_pregame_401902644"),
        CapturedLeague(league: .wnba, prefix: "wnba", teamID: "20", scoreboardDay: "20260814",
                       summary: "wnba_summary_final_401857143"),
        CapturedLeague(league: .nhl, prefix: "nhl", teamID: "25", scoreboardDay: "20260919",
                       summary: "nhl_summary_final_401881922"),
        CapturedLeague(league: .collegeFootball, prefix: "ncaaf", teamID: "2305", scoreboardDay: "20260829",
                       summary: "ncaaf_summary_final_401864494"),
        CapturedLeague(league: .womensCollegeBasketball, prefix: "ncaaw", teamID: "2305", scoreboardDay: "20261102",
                       summary: "ncaaw_summary_pregame_401926040"),
        CapturedLeague(league: .premierLeague, prefix: "epl", teamID: "359", scoreboardDay: "20260821",
                       summary: "epl_summary_final_401879301"),
        CapturedLeague(league: .laLiga, prefix: "laliga", teamID: "83", scoreboardDay: "20260815",
                       summary: "laliga_summary_final_401882926"),
        CapturedLeague(league: .ligaMX, prefix: "ligamx", teamID: "227", scoreboardDay: "20260815",
                       summary: "ligamx_summary_final_401877018"),
        CapturedLeague(league: .nwsl, prefix: "nwsl", teamID: "21422", scoreboardDay: "20260814",
                       summary: "nwsl_summary_final_401853969"),
        CapturedLeague(league: .bundesliga, prefix: "bundes", teamID: "132", scoreboardDay: "20260918",
                       summary: "bundes_summary_final_401884790"),
        CapturedLeague(league: .serieA, prefix: "seriea", teamID: "110", scoreboardDay: "20260919",
                       summary: "seriea_summary_final_401874753"),
        CapturedLeague(league: .ligue1, prefix: "ligue1", teamID: "160", scoreboardDay: "20260920",
                       summary: "ligue1_summary_final_401876449"),
        CapturedLeague(league: .championsLeague, prefix: "uclleague", teamID: "359", scoreboardDay: "20260909",
                       summary: "uclleague_summary_final_401915423"),
        CapturedLeague(league: .wsl, prefix: "wsl", teamID: "19970", scoreboardDay: "20261004",
                       summary: "wsl_summary_final_401902895"),
        CapturedLeague(league: .premiereLigue, prefix: "premiere", teamID: "19256", scoreboardDay: "20261003",
                       summary: "premiere_summary_final_401885704"),
    ]
}

/// A team known only by league and id, as a favorite the catalog has not
/// named yet.
private func followed(_ league: LeagueID, _ espnID: String) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: espnID, shortName: espnID, abbreviation: "", location: "",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

/// Every player in a roster document, flat or grouped.
private func rosterPlayers(_ roster: JSON) -> [JSON] {
    roster["athletes"].arrayValue.flatMap { $0["items"].array ?? [$0] }
}

// MARK: - Registry

@Suite("League registry")
struct LeagueRegistryTests {
    @Test("Every known league has its own descriptor, and nothing else does")
    func knownLeaguesHaveDescriptors() {
        #expect(LeagueID.knownLeagues.count == 19)
        #expect(Set(LeagueID.knownLeagues).count == LeagueID.knownLeagues.count)
        #expect(Set(LeagueID.knownLeagues) == Set(LeagueDescriptor.known.keys))
        for league in LeagueID.knownLeagues {
            #expect(LeagueDescriptor.known[league]?.id == league)
            // A derived descriptor is named by its path; a known one is not.
            #expect(league.descriptor.displayName != league.path)
        }
    }

    @Test("The P3-a, BE-3 and women's European leagues are the known leagues beyond the original four")
    func capturedLeaguesAreTheNewOnes() {
        let original: Set<LeagueID> = [.mensCollegeBasketball, .nfl, .mlb, .mls]
        #expect(Set(CapturedLeague.all.map(\.league)) == Set(LeagueID.knownLeagues).subtracting(original))
    }

    @Test("Each new league's sport, college flag and periods")
    func newLeagueDescriptors() {
        #expect(LeagueID.nba.descriptor.kind == .basketball)
        #expect(LeagueID.wnba.descriptor.kind == .basketball)
        #expect(LeagueID.womensCollegeBasketball.descriptor.kind == .basketball)
        #expect(LeagueID.nhl.descriptor.kind == .hockey)
        #expect(LeagueID.collegeFootball.descriptor.kind == .football)
        for soccer in [LeagueID.premierLeague, .laLiga, .ligaMX, .nwsl, .bundesliga, .serieA, .ligue1, .championsLeague,
                       .wsl, .premiereLigue] {
            #expect(soccer.descriptor.kind == .soccer)
            #expect(soccer.descriptor.periodName("2") == "2nd Half")
            #expect(soccer.descriptor.drawLabel == "Draw")
            #expect(soccer.descriptor.venueBackdropAsset == "soccerField")
        }

        #expect(LeagueID.womensCollegeBasketball.isCollege)
        #expect(LeagueID.collegeFootball.isCollege)
        #expect(!LeagueID.nba.isCollege)

        #expect(LeagueID.nhl.descriptor.periodName("1") == "1st Period")
        #expect(LeagueID.nhl.descriptor.periodName("3") == "3rd Period")
        #expect(LeagueID.nhl.descriptor.periodName("4") == "")  // overtime
        #expect(LeagueID.nba.descriptor.periodName("4") == "4th Quarter")
        #expect(LeagueID.womensCollegeBasketball.descriptor.periodName("3") == "3rd Quarter")

        // College football reads like the NFL.
        #expect(LeagueID.collegeFootball.descriptor.drawLabel == "Tie")
        #expect(LeagueID.collegeFootball.descriptor.liveCardStyle == .scoreFirst)
    }

    @Test("The picker's chips name the registry's constants, European soccer after the EPL, then women's soccer")
    func browsableLeagues() {
        #expect(LeagueID.browsable.map(\.label) == [
            "NFL", "NBA", "MLB", "NHL", "MLS", "WNBA", "NCAAF", "NCAAM", "NCAAW", "EPL",
            "La Liga", "Bundesliga", "Serie A", "Ligue 1", "UCL",
            "NWSL", "WSL", "Première Ligue",
        ])
        #expect(LeagueID.browsable.suffix(8).map(\.league) == [
            .laLiga, .bundesliga, .serieA, .ligue1, .championsLeague,
            .nwsl, .wsl, .premiereLigue,
        ])
        #expect(LeagueID.nba.badge == "NBA")
        #expect(LeagueID.premierLeague.badge == "EPL")
        #expect(LeagueID.laLiga.badge == "La Liga")
        #expect(LeagueID.championsLeague.badge == "UCL")
        #expect(LeagueID.nwsl.badge == "NWSL")
        #expect(LeagueID.wsl.badge == "WSL")
        #expect(LeagueID.premiereLigue.badge == "Première Ligue")
        // Not offered in the picker yet: badged by its path component.
        #expect(LeagueID.ligaMX.badge == "MEX.1")
    }

    @Test("Standings use the /apis/v2 base, the league's group, and an optional season")
    func standingsURL() {
        let base = "https://site.api.espn.com/apis/v2/sports"
        #expect(LeagueID.nba.standingsURL() == "\(base)/basketball/nba/standings")
        #expect(LeagueID.premierLeague.standingsURL() == "\(base)/soccer/eng.1/standings")
        #expect(LeagueID.nhl.standingsURL(season: 2027) == "\(base)/hockey/nhl/standings?season=2027")
        // FBS is group 80; group 50 would be a single FCS conference.
        #expect(LeagueID.collegeFootball.standingsURL() == "\(base)/football/college-football/standings?group=80")
        #expect(LeagueID.womensCollegeBasketball.standingsURL(season: 2027)
            == "\(base)/basketball/womens-college-basketball/standings?group=50&season=2027")
        #expect(LeagueID.mensCollegeBasketball.standingsURL()
            == "\(base)/basketball/mens-college-basketball/standings?group=50")
        // A league with no descriptor of its own names no group.
        #expect(LeagueID(sport: "hockey", league: "ahl").standingsURL() == "\(base)/hockey/ahl/standings")
    }

    @Test("Every European league's teams can play all three UEFA club competitions (A-7)")
    func europeanCups() {
        let uefa: [LeagueID] = [.soccer("uefa.champions"), .soccer("uefa.europa"), .soccer("uefa.europa.conf")]
        for league in [LeagueID.premierLeague, .laLiga, .bundesliga, .serieA, .ligue1] {
            let cups = league.descriptor.cupCompetitions
            for competition in uefa {
                #expect(cups.contains(competition), "\(league) lacks \(competition)")
            }
            #expect(Set(cups).count == cups.count, "\(league) lists a cup twice")
        }
        #expect(LeagueID.soccer("uefa.europa.conf").scheduleURL(teamID: "359")
            == "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.europa.conf/teams/359/schedule")
    }

    @Test("The women's European leagues roll over in July and play the women's cups")
    func womensEuropeanLeagues() {
        // Both feeds start the 2026-27 season on July 1 (wsl_/premiere_scoreboard).
        for league in [LeagueID.wsl, .premiereLigue] {
            #expect(league.descriptor.seasonNaming == .startingYear(rolloverMonth: 7))
            #expect(league.descriptor.cupCompetitions.contains(.soccer("uefa.wchampions")))
        }
        #expect(LeagueID.wsl.descriptor.cupCompetitions
            == [.soccer("eng.w.fa"), .soccer("eng.w.league_cup"), .soccer("uefa.wchampions")])
        // ESPN serves no French women's cup; never the men's Coupe de France.
        #expect(LeagueID.premiereLigue.descriptor.cupCompetitions == [.soccer("uefa.wchampions")])
        #expect(LeagueID.soccer("uefa.wchampions").isCup)
        #expect(!LeagueID.wsl.isCup && !LeagueID.premiereLigue.isCup)
    }

    @Test("Scoreboards: women's college basketball asks for Division I like the men's")
    func scoreboardURLs() {
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        #expect(LeagueID.womensCollegeBasketball.scoreboardURL(day: "20261102")
            == "\(site)/basketball/womens-college-basketball/scoreboard?dates=20261102&groups=50&limit=1000")
        #expect(LeagueID.collegeFootball.scoreboardURL(day: "20260829")
            == "\(site)/football/college-football/scoreboard?dates=20260829")
        #expect(LeagueID.nwsl.scoreboardURL(day: "20260814") == "\(site)/soccer/usa.nwsl/scoreboard?dates=20260814")
    }

    @Test("Every sport kind has a captured summary")
    func summaryPerSportKind() {
        let kinds = Set(CapturedLeague.all.map(\.league.descriptor.kind))
        #expect(kinds.isSuperset(of: [.basketball, .hockey, .football, .soccer]))
    }

    // MARK: Fixture coverage

    @Test("Every fixture is captured and non-trivial", arguments: CapturedLeague.all)
    func fixtureCoverage(_ captured: CapturedLeague) throws {
        for name in captured.fixtureNames {
            _ = try Fixture.url(name)
        }
        let p = captured.prefix
        let teams = try Fixture.json("\(p)_teams")
        let schedule = try Fixture.json("\(p)_schedule")
        let roster = try Fixture.json("\(p)_roster")
        let news = try Fixture.json("\(p)_news")
        let scoreboard = try Fixture.json("\(p)_scoreboard_\(captured.scoreboardDay)")
        let standings = try Fixture.json("\(p)_standings")
        let summary = try Fixture.json(captured.summary)

        #expect(!teams["sports", 0, "leagues", 0, "teams"].arrayValue.isEmpty)
        // An empty season is fine; a missing key is not.
        #expect(schedule["events"].array != nil)
        #expect(!rosterPlayers(roster).isEmpty)
        #expect(news["articles"].array != nil)
        #expect(scoreboard["events"].array != nil)
        // The tables are in the tree's children (see FIXTURES.md, "Standings tree shape").
        #expect(!standings["children"].arrayValue.isEmpty)
        #expect(summary["header"].dictionary != nil)
        #expect(summary["boxscore"].dictionary != nil)
    }

    @Test("The roster shape matches the league's feed", arguments: CapturedLeague.all)
    func rosterShape(_ captured: CapturedLeague) throws {
        let roster = try Fixture.json("\(captured.prefix)_roster")
        let grouped = roster["athletes", 0, "items"].array != nil
        #expect(captured.league.descriptor.rosterShape == (grouped ? .grouped : .flat))
    }

    @Test("Every roster filter names a position the league's feed uses", arguments: CapturedLeague.all)
    func rosterFilterPositions(_ captured: CapturedLeague) throws {
        let roster = try Fixture.json("\(captured.prefix)_roster")
        let positions = Set(rosterPlayers(roster).map { $0["position", "displayName"].stringValue })
        let filters = captured.league.descriptor.rosterFilters.flatMap { entry -> [RosterFilter] in
            switch entry {
            case .filter(let filter): [filter]
            case .menu(_, let filters): filters
            }
        }
        #expect(!filters.isEmpty)
        for position in filters.compactMap(\.position) {
            #expect(positions.contains(position), "\(captured.prefix) roster has no \(position)")
        }
    }
}

// MARK: - Parsing

/// The existing parsers over the new leagues' feeds. Golden values come from
/// the fixtures named in each comment.
@Suite("New-league parsing")
struct NewLeagueParsingTests {
    @Test("Every captured schedule reads one game per event, naming the followed team", arguments: CapturedLeague.all)
    func schedules(_ captured: CapturedLeague) throws {
        let json = try Fixture.json("\(captured.prefix)_schedule")
        let team = followed(captured.league, captured.teamID)
        let games = parseSchedule(from: json, team: team)
        #expect(games.count == json["events"].arrayValue.count)
        for game in games {
            #expect(!game.gameID.isEmpty)
            #expect(!game.team.isEmpty)
            #expect(!game.opponent.isEmpty)
            #expect(!game.opponentID.isEmpty && game.opponentID != captured.teamID)
        }
    }

    @Test("Every captured scoreboard reads a two-sided game per event", arguments: CapturedLeague.all)
    func scoreboards(_ captured: CapturedLeague) throws {
        let json = try Fixture.json("\(captured.prefix)_scoreboard_\(captured.scoreboardDay)")
        let board = parseScoreboard(from: json)
        #expect(!board.games.isEmpty)
        #expect(board.games.count == json["events"].arrayValue.count)
        for game in board.games {
            #expect(game.competitors.count == 2)
        }
    }

    @Test("NBA scoreboard: a preseason game before tip-off carries no score")
    func nbaScoreboard() throws {
        // nba_scoreboard_20261003: Heat (14, away) at Raptors (28, home), "pre", both "0".
        let board = parseScoreboard(from: try Fixture.json("nba_scoreboard_20261003"))
        #expect(board.games.map(\.gameID) == ["401902644"])
        let game = try #require(board.games.first)
        #expect(game.state == "pre")
        #expect(!game.completed)
        #expect(Set(game.competitors) == [
            ScoreboardCompetitor(teamID: "28", homeAway: "home", score: 0),
            ScoreboardCompetitor(teamID: "14", homeAway: "away", score: 0),
        ])
        #expect(game.liveScore(for: "28") == nil)
        #expect(board.lines(for: "14").isEmpty)
    }

    @Test("EPL scoreboard: full time, scores keyed by team id")
    func eplScoreboard() throws {
        // epl_scoreboard_20260821: Arsenal (359, home) 3, Coventry (388, away) 0, "FT".
        let board = parseScoreboard(from: try Fixture.json("epl_scoreboard_20260821"))
        #expect(board.games.map(\.gameID) == ["401879301"])
        let game = try #require(board.games.first)
        #expect(game.state == "post" && game.completed)
        #expect(board.lines(for: "359") == [
            ScoreboardLine(gameID: "401879301", opponentID: "388", score: LiveGameScore(score: 3, opponentScore: 0)),
        ])
        #expect(board.lines(for: "388").first?.score == LiveGameScore(score: 0, opponentScore: 3))
    }

    @Test("NHL scoreboard: a team with two games on one day gets a line for each")
    func nhlSplitSquad() throws {
        // nhl_scoreboard_20260919: preseason split squads. Maple Leafs (21)
        // lost 1–4 at home (401881922) and 3–4 in Montreal (401881923, Final/OT).
        let board = parseScoreboard(from: try Fixture.json("nhl_scoreboard_20260919"))
        #expect(board.lines(for: "21") == [
            ScoreboardLine(gameID: "401881922", opponentID: "10", score: LiveGameScore(score: 1, opponentScore: 4)),
            ScoreboardLine(gameID: "401881923", opponentID: "10", score: LiveGameScore(score: 3, opponentScore: 4)),
        ])
    }

    @Test("NBA schedule: the Hawks' preseason, named by short display name")
    func nbaSchedule() throws {
        let hawks = followed(.nba, "1")
        let games = parseSchedule(from: try Fixture.json("nba_schedule"), team: hawks)
        #expect(games.map(\.gameID) == ["401898388", "401898394", "401898396", "401898402", "401898408"])

        // events[0]: Grizzlies (29) at Hawks, Oct 5 23:00Z, no broadcast listed.
        let opener = games[0]
        #expect(opener.team == "Hawks")
        #expect(opener.opponent == "Grizzlies")
        #expect(opener.opponentID == "29")
        #expect(opener.gameHome)
        #expect(opener.location == "State Farm Arena")
        #expect(!opener.completed)
        #expect(opener.score == "")
        #expect(opener.channel == "TBD")
        #expect(opener.dateAsDate == parseGameDate("2026-10-05T23:00Z"))

        // events[1]: at Spurs (24).
        #expect(!games[1].gameHome)
        #expect(games[1].opponent == "Spurs")
        #expect(games[1].location == "Frost Bank Center")
        #expect(getNextGame(schedule: games) == 0)
    }

    @Test("EPL schedule: Arsenal's results, newest first, and a 4–1 record")
    func eplSchedule() throws {
        let arsenal = followed(.premierLeague, "359")
        let games = parseSchedule(from: try Fixture.json("epl_schedule"), team: arsenal)
        // The feed lists this season's matches newest first.
        #expect(games.map(\.gameID) == ["401879274", "401878779", "401879292", "401879295", "401879301"])

        // events[0]: lost 0–3 at Brighton (331). Named by shortDisplayName,
        // not the feed's nickname ("Gunners", "Seagulls").
        let brighton = games[0]
        #expect(brighton.team == "Arsenal")
        #expect(brighton.opponent == "Brighton")
        #expect(brighton.opponentID == "331")
        #expect(!brighton.gameHome)
        #expect(brighton.completed && !brighton.gameWin)
        #expect(brighton.score == "0" && brighton.opponentScore == "3")
        #expect(brighton.location == "American Express Stadium")
        #expect(brighton.channel == "USA Net")

        // events[4]: the event of epl_scoreboard_20260821 and
        // epl_summary_final_401879301, 3–0 at home to Coventry (388).
        let coventry = games[4]
        #expect(coventry.gameHome && coventry.gameWin)
        #expect(coventry.opponentID == "388")
        #expect(coventry.score == "3" && coventry.opponentScore == "0")

        let record = seasonRecord(games: games)
        #expect(record.wins == 4 && record.losses == 1 && record.draws == 0)
    }
}
