//
//  WidgetDeepLinkTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

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
