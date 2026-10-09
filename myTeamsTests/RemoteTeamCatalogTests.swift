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

// MARK: - College conferences (R-5)

/// Conferences read from the standings tree onto each college `TeamRef`,
/// and the browser's sections built from them.
@Suite("College conferences")
struct CollegeConferenceTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "CollegeConferenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("A TeamRef written before conferences decodes with none, and round-trips one")
    func decodesWithoutConference() throws {
        // A cached Kansas as the catalog wrote it before R-5: no `conference`.
        let old = Data(#"""
        {"league": "football/college-football", "espnID": "2305",
         "displayName": "Kansas Jayhawks", "shortName": "Kansas", "abbreviation": "KU",
         "location": "Kansas", "colorHex": "0051ba", "alternateColorHex": "e8000d",
         "logoURL": "https://a.espncdn.com/i/teamlogos/ncaa/500/2305.png"}
        """#.utf8)
        let kansas = try JSONDecoder().decode(TeamRef.self, from: old)
        #expect(kansas.id == "football/college-football:2305")
        #expect(kansas.conference == nil)

        // A nil conference is left out of what is written, so a file stays
        // as it was; a set one is kept.
        let rewritten = try JSONSerialization.jsonObject(with: JSONEncoder().encode(kansas)) as? [String: Any]
        #expect(rewritten?["conference"] == nil)
        var big12 = kansas
        big12.conference = "Big 12 Conference"
        let decoded = try JSONDecoder().decode(TeamRef.self, from: JSONEncoder().encode(big12))
        #expect(decoded.conference == "Big 12 Conference")

        // The bundled seeds have none.
        #expect(TeamCatalog.all.allSatisfy { $0.conference == nil })
    }

    @Test("Each team's conference is the standings root's child, even a division down")
    func parseConferences() throws {
        let conferences = RemoteTeamCatalog.parseConferences(try Fixture.json("ncaaf_standings"))
        // Big 12's 16, and Sun Belt's 14 from its East and West tables.
        #expect(conferences.count == 30)
        #expect(conferences["2305"] == "Big 12 Conference")       // Kansas
        #expect(conferences["2026"] == "Sun Belt Conference")     // App State, East
        #expect(conferences["309"] == "Sun Belt Conference")      // Louisiana, West
        #expect(Set(conferences.values) == ["Big 12 Conference", "Sun Belt Conference"])

        let ncaaw = RemoteTeamCatalog.parseConferences(try Fixture.json("ncaaw_standings"))
        #expect(ncaaw.count == 25)
        #expect(ncaaw["261"] == "America East Conference")       // Vermont
        #expect(RemoteTeamCatalog.parseConferences(.null).isEmpty)
    }

    @Test("A college catalog load reads the standings for conferences; a pro one does not")
    func catalogLoad() async throws {
        let league = LeagueID.womensCollegeBasketball
        let teamsURL = league.teamsURL
        let standingsURL = league.standingsURL()
        let teams = try RecordingTransport.Reply.fixture("ncaaw_teams")
        let standings = try RecordingTransport.Reply.fixture("ncaaw_standings")
        let transport = RecordingTransport { url, _ in
            switch url.absoluteString {
            case teamsURL: teams
            case standingsURL: standings
            default: .status(404)
            }
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = RemoteTeamCatalog(client: HTTPClient(transport: transport), directory: directory)

        let loaded = await catalog.teams(for: league)
        #expect(loaded.count == 15)
        #expect(transport.urls.map(\.absoluteString) == [teamsURL, standingsURL])
        // Arizona State (9), Arizona (12) and Kansas (2305) are the Big 12
        // teams among the fixture's fifteen; the rest are in no captured
        // conference.
        let big12 = loaded.filter { $0.conference == "Big 12 Conference" }.map(\.espnID)
        #expect(Set(big12) == ["9", "12", "2305"])
        #expect(loaded.filter { $0.conference == nil }.count == 12)

        // The conferences are cached with the list: a new catalog on the
        // same directory serves them without asking again.
        let offline = RecordingTransport(always: .status(503))
        let cached = RemoteTeamCatalog(client: HTTPClient(transport: offline), directory: directory)
        #expect(await cached.team(id: "basketball/womens-college-basketball:2305")?.conference == "Big 12 Conference")
        #expect(offline.requestCount == 0)

        // A pro league asks only for its teams.
        let nflTeams = try RecordingTransport.Reply.fixture("nfl_teams")
        let pro = RecordingTransport { _, _ in nflTeams }
        let proCatalog = RemoteTeamCatalog(client: HTTPClient(transport: pro), directory: temporaryDirectory())
        #expect(await proCatalog.teams(for: .nfl).allSatisfy { $0.conference == nil })
        #expect(pro.urls.map(\.absoluteString) == [LeagueID.nfl.teamsURL])
    }

    @Test("Without standings the list loads conference-less; a fresh cache of such a list is refetched")
    func standingsUnavailable() async throws {
        let league = LeagueID.womensCollegeBasketball
        let teamsURL = league.teamsURL
        let teams = try RecordingTransport.Reply.fixture("ncaaw_teams")
        let noStandings = RecordingTransport { url, _ in
            url.absoluteString == teamsURL ? teams : .status(503)
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = RemoteTeamCatalog(client: HTTPClient(transport: noStandings), directory: directory)
        let loaded = await first.teams(for: league)
        #expect(loaded.count == 15)
        #expect(loaded.allSatisfy { $0.conference == nil })
        #expect(RemoteTeamCatalog.lacksConferences(loaded, league: league))
        #expect(!RemoteTeamCatalog.lacksConferences(loaded, league: .nfl))

        // Next session, offline: the fresh but conference-less cache is
        // asked about again, and served when the network can't be reached.
        let offline = RecordingTransport(always: .status(503))
        let second = RemoteTeamCatalog(client: HTTPClient(transport: offline), directory: directory)
        #expect(await second.teams(for: league).map(\.id) == loaded.map(\.id))
        #expect(offline.urls.map(\.absoluteString) == [teamsURL])

        // The session after, standings back: refetched, and it gains its
        // conferences, which the next session serves from the cache.
        let standings = try RecordingTransport.Reply.fixture("ncaaw_standings")
        let online = RecordingTransport { url, _ in
            url.absoluteString == teamsURL ? teams : standings
        }
        let third = RemoteTeamCatalog(client: HTTPClient(transport: online), directory: directory)
        #expect(await third.teams(for: league).contains { $0.conference != nil })
        #expect(online.requestCount == 2)

        let fourth = RemoteTeamCatalog(client: HTTPClient(transport: offline), directory: directory)
        #expect(await fourth.teams(for: league).contains { $0.conference != nil })
        #expect(offline.requestCount == 1)
    }

    @Test("Browser sections: conference-less teams first, then conferences alphabetically, order kept within")
    func sections() throws {
        func team(_ id: String, _ conference: String?) -> TeamRef {
            var team = TeamRef(
                league: .collegeFootball, espnID: id,
                displayName: id, shortName: id, abbreviation: "", location: id,
                colorHex: "", alternateColorHex: "",
                logoURL: nil, logoDarkURL: nil, logoAsset: nil
            )
            team.conference = conference
            return team
        }
        let teams = [
            team("Abilene Christian", nil),
            team("Air Force", "Mountain West Conference"),
            team("Arizona", "Big 12 Conference"),
            team("Arkansas State", "Sun Belt Conference"),
            team("Adrian", nil),
            team("Kansas", "Big 12 Conference"),
        ]
        let sections = ConferenceSection.sections(teams)
        #expect(sections.map(\.conference) == [nil, "Big 12 Conference", "Mountain West Conference", "Sun Belt Conference"])
        #expect(sections.map { $0.teams.map(\.espnID) } == [
            ["Abilene Christian", "Adrian"],
            ["Arizona", "Kansas"],
            ["Air Force"],
            ["Arkansas State"],
        ])
        #expect(Set(sections.map(\.id)).count == sections.count)

        // Every team in a conference: no leading conference-less section.
        #expect(ConferenceSection.sections(teams.filter { $0.conference != nil }).first?.conference == "Big 12 Conference")

        // No conferences at all (a pro list, or standings that never came):
        // no sections, so the browser keeps its one list.
        #expect(ConferenceSection.sections(teams.map { team($0.espnID, nil) }).isEmpty)
        #expect(ConferenceSection.sections([]).isEmpty)

        // From the captured catalog and standings: the women's Big 12 trio.
        let ncaaw = RemoteTeamCatalog.withConferences(
            RemoteTeamCatalog.parseTeams(try Fixture.json("ncaaw_teams"), league: .womensCollegeBasketball),
            from: RemoteTeamCatalog.parseConferences(try Fixture.json("ncaaw_standings"))
        )
        let captured = ConferenceSection.sections(ncaaw)
        #expect(captured.map(\.conference) == [nil, "Big 12 Conference"])
        #expect(captured[1].teams.map(\.espnID) == ["9", "12", "2305"])
    }
}
