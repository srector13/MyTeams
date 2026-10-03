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

/// The `myteams://team/<TeamRef.id>` links the widget opens the app with.
@Suite("Widget deep links")
struct WidgetDeepLinkTests {
    private func teamID(_ string: String) throws -> TeamRef.ID? {
        WidgetDeepLink.teamID(from: try #require(URL(string: string)))
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
        #expect(try teamID("myteams://game/football/nfl:12") == nil)
        #expect(try teamID("myteams://teams/football/nfl:12") == nil)
        #expect(try teamID("myteams:///football/nfl:12") == nil)
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
        #expect(ScoreAlertEngine.teamID(in: [:]) == nil)
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: "myteams://team/not-a-team"]) == nil)
        #expect(ScoreAlertEngine.teamID(in: [ScoreAlertEngine.teamLinkKey: 7]) == nil)
        #expect(ScoreAlertEngine.teamID(in: ["url": link]) == nil)

        #if canImport(UserNotifications)
        let snapshot = ScoreSnapshot(homeName: "Broncos", awayName: "Rams", homeScore: 23, awayScore: 26, period: 4, state: .inProgress)
        let event = ScoreEvent.gameStart(gameID: "401872962", snapshot: snapshot)
        let linked = ScoreAlertEngine.request(for: event, teamID: "football/nfl:7")
        #expect(linked.content.userInfo[ScoreAlertEngine.teamLinkKey] as? String == link)
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
