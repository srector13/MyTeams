//
//  RemoteTeamCatalogTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Answers every catalog request with a fixed status and body, counting calls.
private final class CatalogTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private let status: Int
    private let body: Data

    init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    var calls: Int { lock.withLock { _calls } }

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        lock.withLock { _calls += 1 }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
}

/// Captured `teams` documents: `nfl_teams` and `college_football_teams`.
/// See FIXTURES.md.
@Suite("Remote team catalog")
struct RemoteTeamCatalogTests {
    private func teams(_ fixture: String, league: LeagueID) throws -> [TeamRef] {
        RemoteTeamCatalog.parseTeams(try Fixture.json(fixture), league: league)
    }

    private let collegeFootball = LeagueID(sport: "football", league: "college-football")

    // MARK: Parsing

    @Test("NFL teams map onto TeamRef, with the rel-selected 500 px crests")
    func nflMapping() throws {
        let nfl = try teams("nfl_teams", league: .nfl)
        #expect(nfl.count == 15)

        let chiefs = try #require(nfl.first { $0.espnID == "12" })
        #expect(chiefs.id == "football/nfl:12")
        #expect(chiefs.displayName == "Kansas City Chiefs")
        #expect(chiefs.shortName == "Chiefs")  // shortDisplayName
        #expect(chiefs.abbreviation == "KC")
        #expect(chiefs.location == "Kansas City")
        #expect(chiefs.colorHex == "e31837")  // six hex digits, no "#"
        #expect(chiefs.alternateColorHex == "ffb612")
        #expect(chiefs.logoURL == URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/kc.png"))
        #expect(chiefs.logoDarkURL == URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500-dark/kc.png"))
        #expect(chiefs.logoAsset == nil)

        // Every NFL team has both crests, and none is a scoreboard or
        // brand-service (guid) variant.
        for team in nfl {
            let light = try #require(team.logoURL?.absoluteString)
            let dark = try #require(team.logoDarkURL?.absoluteString)
            #expect(light.hasPrefix("https://a.espncdn.com/i/teamlogos/nfl/500/"))
            #expect(dark.hasPrefix("https://a.espncdn.com/i/teamlogos/nfl/500-dark/"))
            #expect(!light.contains("scoreboard") && !dark.contains("scoreboard"))
            #expect(team.colorHex.count == 6 && team.alternateColorHex.count == 6)
        }
    }

    @Test("Crests are chosen by rel even when scoreboard and guid entries come first")
    func selectionIgnoresOrder() throws {
        // nfl_teams.json lists the Chiefs' 17 logos default-first; reversed,
        // the scoreboard, grayscale and 4096 px guid entries all come first,
        // including ["full", "scoreboard", "dark"].
        let document = try Fixture.json("nfl_teams")
        let entries = document["sports", 0, "leagues", 0, "teams"].arrayValue
        let index = try #require(entries.firstIndex { $0["team"]["id"].stringValue == "12" })
        let logos = entries[index]["team"]["logos"].arrayValue
        #expect(logos.count == 17)
        let reversed = document.setting(
            ["sports", 0, "leagues", 0, "teams", .index(index), "team", "logos"],
            to: .array(logos.reversed())
        )
        #expect(reversed["sports", 0, "leagues", 0, "teams", .index(index), "team", "logos", 0, "href"].stringValue
            .contains("/guid/"))

        let chiefs = try #require(RemoteTeamCatalog.parseTeams(reversed, league: .nfl).first { $0.espnID == "12" })
        #expect(chiefs.logoURL == URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/kc.png"))
        #expect(chiefs.logoDarkURL == URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500-dark/kc.png"))
    }

    @Test("College teams: logo-less teams get no URL; colourless ones empty hex")
    func collegeMapping() throws {
        let college = try teams("college_football_teams", league: collegeFootball)
        #expect(college.count == 15)

        let kansas = try #require(college.first { $0.espnID == "2305" })
        #expect(kansas.displayName == "Kansas Jayhawks")
        #expect(kansas.abbreviation == "KU")
        #expect(kansas.colorHex == "0051ba")
        #expect(kansas.logoURL == URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500/2305.png"))
        #expect(kansas.logoDarkURL == URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500-dark/2305.png"))

        // Adams State lists just the two crests, no brand-service set.
        let adams = try #require(college.first { $0.espnID == "2001" })
        #expect(adams.logoURL == URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500/2001.png"))
        #expect(adams.alternateColorHex.isEmpty)  // no alternateColor in the feed

        // Andrew (134002) has no logos, colour or alternate colour at all:
        // the monogram path, with a hash-picked fill.
        let andrew = try #require(college.first { $0.espnID == "134002" })
        #expect(andrew.abbreviation == "AND")
        #expect(andrew.logoURL == nil)
        #expect(andrew.logoDarkURL == nil)
        #expect(andrew.colorHex.isEmpty)

        // Apprentice School (3111): a colour but no logos.
        let apprentice = try #require(college.first { $0.espnID == "3111" })
        #expect(apprentice.logoURL == nil)
        #expect(apprentice.colorHex == "000000")
    }

    @Test("A team with a default crest but no dark one has no dark URL")
    func darkAbsent() throws {
        // No captured team lacks a dark crest, so drop it from a real one:
        // Adams State's logos without the ["full", "dark"] entry.
        let document = try Fixture.json("college_football_teams")
        let entries = document["sports", 0, "leagues", 0, "teams"].arrayValue
        let index = try #require(entries.firstIndex { $0["team"]["id"].stringValue == "2001" })
        let lightOnly = entries[index]["team"]["logos"].arrayValue.filter {
            !$0["rel"].arrayValue.contains(.string("dark"))
        }
        #expect(lightOnly.count == 1)
        let edited = document.setting(
            ["sports", 0, "leagues", 0, "teams", .index(index), "team", "logos"],
            to: .array(lightOnly)
        )

        let adams = try #require(RemoteTeamCatalog.parseTeams(edited, league: collegeFootball).first { $0.espnID == "2001" })
        #expect(adams.logoURL == URL(string: "https://a.espncdn.com/i/teamlogos/ncaa/500/2001.png"))
        #expect(adams.logoDarkURL == nil)
        #expect(LogoStore.sourceURL(for: adams, variant: .dark) == nil)
    }

    @Test("Seed teams in a fetched list keep their bundled crest; others have none")
    func seedAssets() throws {
        let nfl = RemoteTeamCatalog.withSeedAssets(try teams("nfl_teams", league: .nfl))
        #expect(nfl.first { $0.espnID == "12" }?.logoAsset == "chiefs")
        #expect(nfl.filter { $0.logoAsset != nil }.count == 1)
    }

    @Test("Refreshing a seed takes the feed's name, colours and URLs, not its tab label")
    func refreshingSeed() throws {
        let fetched = try #require(try teams("nfl_teams", league: .nfl).first { $0.espnID == "12" })
        let refreshed = RemoteTeamCatalog.refreshing(.chiefs, from: fetched)
        #expect(refreshed.colorHex == "e31837")
        #expect(refreshed.logoURL == fetched.logoURL)
        #expect(refreshed.shortName == "Chiefs")
        #expect(refreshed.location == TeamRef.chiefs.location)
        #expect(refreshed.logoAsset == "chiefs")
    }

    @Test("Teams URLs ask for every team; college ones for all divisions")
    func teamsURL() {
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        #expect(LeagueID.nfl.teamsURL == "\(site)/football/nfl/teams?limit=1000")
        #expect(collegeFootball.teamsURL == "\(site)/football/college-football/teams?limit=1000&groups=50")
        #expect(LeagueID.mensCollegeBasketball.teamsURL.hasSuffix("&groups=50"))
    }

    // MARK: Cache tiers

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "RemoteTeamCatalogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Network, then fresh cache, then stale cache, then the seed")
    func tiers() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = try Data(contentsOf: Fixture.url("nfl_teams"))

        // Network: fetched, parsed and written to the league's cache file.
        let online = CatalogTransport(status: 200, body: body)
        let catalog = RemoteTeamCatalog(client: HTTPClient(transport: online), directory: directory)
        let fetched = await catalog.teams(for: .nfl)
        #expect(fetched.count == 15)
        let file = await catalog.cacheURL(for: .nfl)
        #expect(file.lastPathComponent == "football.nfl.json")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        // The fetch refreshed the Chiefs seed in memory.
        #expect(await catalog.refreshedSeed(.chiefs).colorHex == "e31837")
        #expect(TeamRef.chiefs.colorHex == "E31837")  // teams.json untouched

        // Fresh cache: a new catalog on the same directory, offline, reads the
        // file without asking the network.
        let offline = CatalogTransport(status: 503)
        let cachedCatalog = RemoteTeamCatalog(client: HTTPClient(transport: offline), directory: directory)
        #expect(await cachedCatalog.teams(for: .nfl).map(\.id) == fetched.map(\.id))
        #expect(offline.calls == 0)
        #expect(await cachedCatalog.team(id: "football/nfl:13")?.displayName == "Las Vegas Raiders")

        // Stale cache: a month later, still offline, the old list is served.
        let later = RemoteTeamCatalog(
            client: HTTPClient(transport: offline),
            directory: directory,
            now: { Date().addingTimeInterval(30 * 24 * 60 * 60) }
        )
        #expect(await later.teams(for: .nfl).count == 15)
        #expect(offline.calls == 1)

        // Nothing cached and offline: the seed teams in the league.
        let empty = RemoteTeamCatalog(client: HTTPClient(transport: offline), directory: temporaryDirectory())
        #expect(await empty.teams(for: .nfl).map(\.id) == ["football/nfl:12"])
        #expect(await empty.teams(for: LeagueID(sport: "hockey", league: "nhl")).isEmpty)
        #expect(await empty.team(id: "not-an-id") == nil)
    }
}
