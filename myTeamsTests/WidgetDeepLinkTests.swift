//
//  WidgetDeepLinkTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
#if canImport(UserNotifications)
import UserNotifications
#endif

@testable import myTeams

/// The `myteams://team/<TeamRef.id>` links the widget opens the app with,
/// and the `myteams://game/` links to one game's sheet (R-3).
@Suite("Widget deep links")
struct WidgetDeepLinkTests {
    private func teamID(_ string: String) throws -> TeamRef.ID? {
        WidgetDeepLink.teamID(from: try #require(URL(string: string)))
    }

    private func game(_ string: String) throws -> WidgetDeepLink.GameTarget? {
        WidgetDeepLink.game(from: try #require(URL(string: string)))
    }

    @Test("A team link yields its TeamRef.id")
    func valid() throws {
        #expect(try teamID("myteams://team/football/nfl:12") == "football/nfl:12")
        #expect(try teamID("myteams://team/soccer/usa.1:186") == "soccer/usa.1:186")
        #expect(try teamID("myteams://team/basketball/mens-college-basketball:2305") == "basketball/mens-college-basketball:2305")
        // An encoded slash, and scheme and host in any case.
        #expect(try teamID("myteams://team/football%2Fnfl:12") == "football/nfl:12")
        #expect(try teamID("MyTeams://TEAM/baseball/mlb:7") == "baseball/mlb:7")
    }

    @Test("Links the widget builds read back to the same team")
    func roundTrip() throws {
        for team in TeamCatalog.all {
            let url = try #require(WidgetDeepLink.url(forTeamID: team.id))
            #expect(url.scheme == "myteams")
            #expect(url.host() == "team")
            #expect(WidgetDeepLink.teamID(from: url) == team.id)
        }
        #expect(WidgetDeepLink.url(forTeamID: "not-a-team") == nil)
    }

    @Test("Other schemes are ignored")
    func wrongScheme() throws {
        #expect(try teamID("https://team/football/nfl:12") == nil)
        #expect(try teamID("myteam://team/football/nfl:12") == nil)
        #expect(try teamID("widget://team/football/nfl:12") == nil)
    }

    @Test("Other hosts are ignored")
    func wrongHost() throws {
        // A game link is no team link: it routes to the game's sheet.
        #expect(try teamID("myteams://game/football/nfl:12") == nil)
        #expect(try game("myteams://game/football/nfl:12") == WidgetDeepLink.GameTarget(league: .nfl, eventID: "12", teamID: nil))
        #expect(try teamID("myteams://teams/football/nfl:12") == nil)
        #expect(try teamID("myteams:///football/nfl:12") == nil)
        #expect(try game("myteams://games/football/nfl:12") == nil)
        #expect(try game("myteams://team/football/nfl:12") == nil)
        #expect(try game("https://game/football/nfl:12") == nil)
    }

    @Test("A game link yields its league, event and team")
    func gameLink() throws {
        let chiefs = TeamRef.id(league: .nfl, espnID: "12")
        let linked = try #require(try game("myteams://game/football/nfl:401?team=football/nfl:12"))
        #expect(linked == WidgetDeepLink.GameTarget(league: .nfl, eventID: "401", teamID: chiefs))
        #expect(WidgetDeepLink.linkedTeamID(from: try #require(URL(string: "myteams://game/football/nfl:401?team=football/nfl:12"))) == chiefs)

        // Encoded, and scheme and host in any case: a cup tie, on the
        // cup's board, for the team in its home league.
        #expect(try game("MyTeams://GAME/soccer%2Fuefa.champions:401915423?team=soccer%2Feng.1%3A359")
            == WidgetDeepLink.GameTarget(league: .championsLeague, eventID: "401915423", teamID: "soccer/eng.1:359"))

        // A team that is not an id is read as none.
        #expect(try game("myteams://game/football/nfl:401?team=not-a-team")?.teamID == nil)
        #expect(try game("myteams://game/football/nfl:401?other=football/nfl:12")?.teamID == nil)

        // Malformed games.
        #expect(try game("myteams://game") == nil)
        #expect(try game("myteams://game/") == nil)
        #expect(try game("myteams://game/football/nfl") == nil)
        #expect(try game("myteams://game/football/nfl:") == nil)
        #expect(try game("myteams://game/nfl:401") == nil)
        #expect(try game("myteams://game/football/nfl:401/extra") == nil)
    }

    @Test("Game links the alerts and Live Activities build read back to the same game")
    func gameRoundTrip() throws {
        let arsenal = TeamRef.id(league: .premierLeague, espnID: "359")
        let url = try #require(WidgetDeepLink.url(forGame: "401915423", league: .championsLeague, teamID: arsenal))
        #expect(url.scheme == "myteams")
        #expect(url.host() == "game")
        #expect(WidgetDeepLink.game(from: url) == WidgetDeepLink.GameTarget(league: .championsLeague, eventID: "401915423", teamID: arsenal))
        #expect(WidgetDeepLink.teamID(from: url) == nil)
        #expect(WidgetDeepLink.linkedTeamID(from: url) == arsenal)

        let teamless = try #require(WidgetDeepLink.url(forGame: "401", league: .nfl, teamID: nil))
        #expect(teamless.absoluteString == "myteams://game/football/nfl:401")
        #expect(WidgetDeepLink.game(from: teamless)?.teamID == nil)

        #expect(WidgetDeepLink.url(forGame: "", league: .nfl, teamID: nil) == nil)
        #expect(WidgetDeepLink.url(forGame: "4/01", league: .nfl, teamID: nil) == nil)
        #expect(WidgetDeepLink.url(forGame: "4:01", league: .nfl, teamID: nil) == nil)
        #expect(WidgetDeepLink.url(forGame: "401", league: .nfl, teamID: "not-a-team") == nil)
    }

    @Test("A shared game links to its page on espn.com")
    func gameWebURL() {
        #expect(LeagueID.nfl.gameWebURL(gameID: "401")?.absoluteString == "https://www.espn.com/nfl/game/_/gameId/401")
        #expect(LeagueID.mensCollegeBasketball.gameWebURL(gameID: "401")?.absoluteString
            == "https://www.espn.com/mens-college-basketball/game/_/gameId/401")
        #expect(LeagueID.premierLeague.gameWebURL(gameID: "401")?.absoluteString == "https://www.espn.com/soccer/match/_/gameId/401")
    }

    @Test("A cup tie's Live Activity and alert link to the team in its home league, not the cup")
    func cupTieLinksHome() throws {
        // ucl_scoreboard_20260909 id 401915423: Arsenal (359, away) at
        // Napoli, on the Champions League board. Arsenal's page is filed
        // under the Premier League.
        let arsenal = TeamRef.id(league: .premierLeague, espnID: "359")
        let championsLeague = LeagueID.soccer("uefa.champions")
        let board = parseScoreboard(from: try Fixture.json("ucl_scoreboard_20260909"))
        let game = try #require(board.games.first { $0.gameID == "401915423" })

        let candidate = try #require(LiveActivityStateMapper.candidate(
            for: game, teamID: "359", homeLeague: .premierLeague, league: championsLeague
        ))
        // The activity still names the board it came from…
        #expect(candidate.info.league == "soccer/uefa.champions")
        // …but links to the team's own page.
        #expect(candidate.info.favoriteID == arsenal)
        let url = try #require(candidate.info.deepLink)
        #expect(WidgetDeepLink.teamID(from: url) == arsenal)
        let linked = try #require(WidgetDeepLink.teamID(from: url).flatMap(TeamRef.parse(id:)))
        #expect(linked.league == .premierLeague)
        #expect(linked.espnID == "359")
        #expect(url != WidgetDeepLink.url(forTeamID: TeamRef.id(league: championsLeague, espnID: "359")))

        // An activity from before the link was kept opens no page.
        var older = candidate.info
        older.favoriteID = nil
        #expect(older.deepLink == nil)

        #if canImport(UserNotifications)
        // The tie's score alert, posted for the Arsenal favorite, links the
        // same way.
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: game))
        let request = ScoreAlertEngine.request(for: .gameStart(gameID: game.gameID, snapshot: snapshot), teamID: arsenal)
        #expect(ScoreAlertEngine.teamID(in: request.content.userInfo) == arsenal)
        #endif
    }

    @Test("A score alert's tap reads its team from the alert's link, and nothing else")
    func alertUserInfo() throws {
        let link = try #require(WidgetDeepLink.url(forTeamID: "football/nfl:7")).absoluteString
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: link]) == "football/nfl:7")
        let gameLink = try #require(WidgetDeepLink.url(forGame: "401872962", league: .nfl, teamID: "football/nfl:7"))
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: gameLink.absoluteString]) == "football/nfl:7")
        #expect(ScoreAlertEngine.teamID(in: [:]) == nil)
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: "myteams://team/not-a-team"]) == nil)
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: 7]) == nil)
        #expect(ScoreAlertEngine.teamID(in: ["url": link]) == nil)

        #if canImport(UserNotifications)
        let snapshot = ScoreSnapshot(homeName: "Broncos", awayName: "Rams", homeScore: 23, awayScore: 26, period: 4, state: .inProgress)
        let event = ScoreEvent.gameStart(gameID: "401872962", snapshot: snapshot)
        let linked = ScoreAlertEngine.request(for: event, teamID: "football/nfl:7")
        // The game's sheet over the team's page (R-3).
        #expect(linked.content.userInfo[ScoreAlertEngine.teamLinkKey] as? String == gameLink.absoluteString)
        #expect(ScoreAlertEngine.link(in: linked.content.userInfo).flatMap(WidgetDeepLink.game(from:))
            == WidgetDeepLink.GameTarget(league: .nfl, eventID: "401872962", teamID: "football/nfl:7"))
        // No team, or one that is not an id: no link.
        #expect(ScoreAlertEngine.request(for: event).content.userInfo.isEmpty)
        #expect(ScoreAlertEngine.request(for: event, teamID: "not-a-team").content.userInfo.isEmpty)
        #endif
    }

    @Test("Malformed team ids are rejected")
    func badID() throws {
        #expect(try teamID("myteams://team") == nil)
        #expect(try teamID("myteams://team/") == nil)
        #expect(try teamID("myteams://team/football/nfl") == nil)      // no ESPN id
        #expect(try teamID("myteams://team/football/nfl:") == nil)     // empty ESPN id
        #expect(try teamID("myteams://team/nfl:12") == nil)            // league path missing sport
        #expect(try teamID("myteams://team/football//nfl:12") == nil)  // empty path component
        #expect(try teamID("myteams://team/football/nfl:12/extra") == nil)
    }
}

/// The scoreboard snapshot the app writes for the widget, and the game the
/// widget features from it: the one under way, else today's result, else
/// the next fixture (C-5).
@Suite("Widget scoreboard snapshot")
struct WidgetScoreboardSnapshotTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Sunday, Oct 4, 2026, 18:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_136_800)

    private var now: Date { Self.now }
    private let chiefs = TeamRef.id(league: .nfl, espnID: "12")

    private func snapshot(
        gameID: String = "401",
        teamID: String? = nil,
        state: WidgetScoreboardSnapshot.State = .inProgress,
        start: Date = WidgetScoreboardSnapshotTests.now.addingTimeInterval(-3_600),
        updated: Date = WidgetScoreboardSnapshotTests.now.addingTimeInterval(-60)
    ) -> WidgetScoreboardSnapshot {
        WidgetScoreboardSnapshot(
            gameID: gameID, league: "football/nfl", teamID: teamID ?? chiefs,
            homeTeamID: "12", awayTeamID: "13", homeName: "Chiefs", awayName: "Raiders",
            homeScore: 17, awayScore: 24, state: state, clock: "4:12", period: 3,
            gameDate: start, updated: updated
        )
    }

    private func game(
        id: String,
        start: Date,
        completed: Bool = false,
        cancelled: Bool = false
    ) -> Game {
        Game(
            team: "Chiefs", opponent: "Raiders", score: completed ? "21" : "", opponentScore: completed ? "20" : "",
            time: "", date: "Oct 04, 2026", dateAsDate: start, opponentLogo: "", channel: "CBS",
            location: "", gameHome: true, gameID: id, pointer: 0,
            gameWin: completed, completed: completed, competitionName: "",
            cancelled: cancelled, postponed: false, gameClock: "",
            gamePeriod: "", gameHalftime: false
        )
    }

    private func pick(_ snapshots: [WidgetScoreboardSnapshot], _ schedule: [Game]) -> WidgetFeaturedGame {
        WidgetFeaturedGame.pick(teamID: chiefs, snapshots: snapshots, schedule: schedule, now: now, calendar: Self.calendar)
    }

    // MARK: Codec

    @Test("Snapshots survive the round trip through the App Group defaults")
    func roundTrip() throws {
        let snapshots = [snapshot(), snapshot(gameID: "402", state: .final)]
        let data = try #require(WidgetScoreboardCodec.encode(snapshots))
        #expect(WidgetScoreboardCodec.decode(data) == snapshots)

        let suite = "WidgetScoreboardSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WidgetScoreboardCodec.read(from: defaults).isEmpty)
        WidgetScoreboardCodec.write(snapshots, to: defaults)
        #expect(WidgetScoreboardCodec.read(from: defaults) == snapshots)
    }

    @Test("Missing or unreadable data decodes to no snapshots")
    func unreadable() {
        #expect(WidgetScoreboardCodec.decode(nil).isEmpty)
        #expect(WidgetScoreboardCodec.decode(Data("not json".utf8)).isEmpty)
        #expect(WidgetScoreboardCodec.decode(Data("[{\"gameID\":\"1\"}]".utf8)).isEmpty)
    }

    @Test("A snapshot is fresh for 30 minutes, and never from the future")
    func staleness() {
        #expect(WidgetScoreboardCodec.isFresh(snapshot(updated: now), now: now))
        #expect(WidgetScoreboardCodec.isFresh(snapshot(updated: now.addingTimeInterval(-29 * 60)), now: now))
        #expect(!WidgetScoreboardCodec.isFresh(snapshot(updated: now.addingTimeInterval(-31 * 60)), now: now))
        #expect(!WidgetScoreboardCodec.isFresh(snapshot(updated: now.addingTimeInterval(10 * 60)), now: now))
    }

    @Test("The score and status read from the followed team's side")
    func display() {
        let live = snapshot()
        #expect(live.score(for: "12") == "17–24")
        #expect(live.score(for: "13") == "24–17")
        #expect(live.opponentName(of: "12") == "Raiders")
        #expect(live.opponentName(of: "13") == "Chiefs")
        #expect(live.opponentID(of: "12") == "13")
        #expect(live.statusText == "Live · 4:12")
        #expect(snapshot(state: .final).statusText == "Final")
        var noClock = live
        noClock.clock = "0:00"
        #expect(noClock.statusText == "Live")
    }

    // MARK: Selection

    @Test("A game under way beats today's result and the next game")
    func liveFirst() {
        let live = snapshot(gameID: "live")
        let final = snapshot(gameID: "early", state: .final, start: now.addingTimeInterval(-6 * 3_600))
        let schedule = [game(id: "next", start: now.addingTimeInterval(86_400))]
        #expect(pick([final, live], schedule) == .live(live))
    }

    @Test("Without a game under way, today's result beats the next game")
    func resultBeforeNext() {
        let final = snapshot(state: .final)
        let next = game(id: "next", start: now.addingTimeInterval(3_600))
        #expect(pick([final], [next]) == .result(final))

        // The schedule alone: today's finished game.
        let played = game(id: "401", start: now.addingTimeInterval(-4 * 3_600), completed: true)
        #expect(pick([], [played, next]) == .scheduleResult(played))
        // The board's look at the same game wins over the schedule's.
        #expect(pick([final], [played, next]) == .result(final))
    }

    @Test("A result from before today gives way to the next game")
    func yesterdaysResult() {
        let yesterday = now.addingTimeInterval(-86_400)
        let played = game(id: "1", start: yesterday, completed: true)
        let next = game(id: "2", start: now.addingTimeInterval(3 * 86_400))
        #expect(pick([], [played, next]) == .next(next))
    }

    @Test("Stale snapshots and other teams' snapshots fall back to the schedule")
    func fallback() {
        let stale = snapshot(updated: now.addingTimeInterval(-45 * 60))
        let otherTeam = snapshot(teamID: TeamRef.id(league: .nfl, espnID: "13"))
        let called = game(id: "1", start: now.addingTimeInterval(3_600), cancelled: true)
        let next = game(id: "2", start: now.addingTimeInterval(2 * 86_400))
        #expect(pick([stale, otherTeam], [called, next]) == .next(next))
        #expect(pick([stale], []) == WidgetFeaturedGame.none)
    }

    // MARK: Writing

    @Test("The app writes favorites' games under way or played out, in their league and cups")
    func writerSnapshots() {
        func board(_ id: String, _ state: String, completed: Bool = false, home: String, away: String) -> ScoreboardGame {
            ScoreboardGame(
                gameID: id, state: state, completed: completed,
                competitors: [
                    ScoreboardCompetitor(teamID: home, homeAway: "home", score: 2),
                    ScoreboardCompetitor(teamID: away, homeAway: "away", score: 1),
                ],
                period: 2, teamNames: [home: "Home \(home)", away: "Away \(away)"], clock: "67'", startDate: now
            )
        }
        let arsenal = TeamRef.id(league: .premierLeague, espnID: "359")
        let games: [LeagueID: [ScoreboardGame]] = [
            .premierLeague: [
                board("live", "in", home: "359", away: "360"),
                board("pre", "pre", home: "382", away: "359"),
                board("off", "post", home: "359", away: "361"),       // called off
                board("other", "in", home: "1", away: "2"),            // no favorite
            ],
            .soccer("uefa.champions"): [board("cup", "post", completed: true, home: "111", away: "359")],
        ]
        let written = WidgetScoreboardWriter.snapshots(in: games, favoriteIDs: [arsenal, "not-a-team"], updated: now)
        #expect(written.map(\.gameID).sorted() == ["cup", "live"])
        let live = written.first { $0.gameID == "live" }
        #expect(live?.state == .inProgress)
        #expect(live?.league == "soccer/eng.1")
        #expect(live?.teamID == arsenal)
        #expect(live?.score(for: "359") == "2–1")
        #expect(live?.clock == "67'")
        #expect(live?.updated == now)
        let cup = written.first { $0.gameID == "cup" }
        #expect(cup?.state == .final)
        #expect(cup?.league == "soccer/uefa.champions")
        #expect(cup?.opponentName(of: "359") == "Home 111")

        // What the app writes, the widget features.
        let featured = WidgetFeaturedGame.pick(teamID: arsenal, snapshots: written, schedule: [], now: now, calendar: Self.calendar)
        #expect(featured == live.map(WidgetFeaturedGame.live))
    }
}
