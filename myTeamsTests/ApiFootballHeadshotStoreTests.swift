//
//  ApiFootballHeadshotStoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/7/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// A clock a test moves by hand.
private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// 2026-10-07 12:00 UTC.
private let october7 = Date(timeIntervalSince1970: 1_791_374_400)

/// A query item of a request URL.
private func query(_ name: String, of url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

/// The page asked for in a `/players` URL.
private func page(of url: URL) -> String? {
    query("page", of: url)
}

/// The players of the live team-route captures: Arsenal (team 42), 2024.
private func team42Players() throws -> [ApiFootballPlayer] {
    try (1...3).flatMap { page in
        ApiFootball.parsePlayers(try Fixture.json("apifootball_players_team42_p\(page)"), league: 39).players
    }
}

/// The ESPN roster in a roster fixture, as the join takes it, and its team.
private func espnRoster(_ fixture: String) throws -> (roster: [ApiFootballRosterEntry], team: String) {
    let json = try Fixture.json(fixture)
    let roster = parseSoccerRoster(from: json).map { ApiFootballRosterEntry(espnID: $0.playerID, name: $0.name) }
    return (roster, json["team"]["displayName"].stringValue)
}

// MARK: - Parsing

/// The `/players` and `/status` parsers, over hand-made answers in the
/// shape API-Football documents (see FIXTURES.md, "API-Football").
@Suite("API-Football parsing")
struct ApiFootballParserTests {
    @Test("A /players page gives each row's id, names, teams and photo, and the paging")
    func playersPage() throws {
        let first = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p1"), league: 39)
        #expect(first.current == 1)
        #expect(first.total == 2)
        #expect(first.errors.isEmpty)
        #expect(first.players.count == 6)
        let raya = try #require(first.players.first)
        #expect(raya.id == 900001)
        #expect(raya.name == "D. Raya")
        #expect(raya.firstname == "David")
        #expect(raya.lastname == "Raya Martín")
        #expect(raya.teams == ["Arsenal"])
        #expect(raya.league == 39)
        #expect(raya.photo == "https://media.api-sports.io/football/players/900001.png")

        let last = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p2"), league: 39)
        #expect(last.current == 2)
        #expect(last.total == 2)
    }

    @Test("A free plan's season error names the newest season it offers")
    func planError() throws {
        let page = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_plan_error"), league: 39)
        #expect(page.players.isEmpty)
        #expect(page.errors.keys.sorted() == ["plan"])
        #expect(ApiFootball.fallbackSeason(from: page.errors) == 2024)
        #expect(ApiFootball.fallbackSeason(from: ["token": "Error 2024"]) == nil)
    }

    @Test("A free plan's page-cap error names the last page it allows, and no season")
    func pageCapError() throws {
        let page = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_page_cap"), league: 39)
        #expect(page.players.isEmpty)
        #expect(ApiFootball.pageCap(from: page.errors) == 3)
        // Not a season error: no fallback season in it.
        #expect(ApiFootball.fallbackSeason(from: page.errors) == nil)
        let season = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_plan_error"), league: 39)
        #expect(ApiFootball.pageCap(from: season.errors) == nil)
    }

    @Test("A /teams answer gives each club's id; ESPN's team name finds its id")
    func teams() throws {
        let (teams, errors) = ApiFootball.parseTeams(try Fixture.json("apifootball_teams_epl_live"))
        #expect(errors.isEmpty)
        #expect(teams.count == 20)
        #expect(teams.contains(ApiFootballTeam(id: 42, name: "Arsenal", code: "ARS")))
        #expect(ApiFootball.teamID(for: "Arsenal", in: teams) == 42)
        #expect(ApiFootball.teamID(for: "Chelsea", in: teams) == 49)
        #expect(ApiFootball.teamID(for: "Manchester City", in: teams) == 50)
        #expect(ApiFootball.teamID(for: "Manchester United", in: teams) == 33)
        #expect(ApiFootball.teamID(for: "Tottenham Hotspur", in: teams) == 47)
        // No match: that club gets no tier 3.
        #expect(ApiFootball.teamID(for: "Sunderland", in: teams) == nil)
    }

    @Test("Aliases find the clubs teamsMatch cannot; the club code is the last resort")
    func aliasesAndCodes() throws {
        let (teams, _) = ApiFootball.parseTeams(try Fixture.json("apifootball_teams_epl_live"))
        #expect(teams.first { $0.id == 39 }?.code == "WOL")
        // The live diagnostic's known gap.
        #expect(!ApiFootball.teamsMatch("Wolverhampton Wanderers", "Wolves"))
        #expect(ApiFootball.teamID(for: "Wolverhampton Wanderers", in: teams) == 39)
        #expect(ApiFootball.teamID(for: "Brighton & Hove Albion", in: teams) == 51)
        // No name match: ESPN's abbreviation against the club code.
        #expect(ApiFootball.teamID(for: "Spurs", in: teams) == nil)
        #expect(ApiFootball.teamID(for: "Spurs", abbreviation: "TOT", in: teams) == 47)
        #expect(ApiFootball.teamID(for: "Spurs", abbreviation: "tot", in: teams) == 47)
        #expect(ApiFootball.teamID(for: "Spurs", abbreviation: "XYZ", in: teams) == nil)
        // A name match wins over a code that says otherwise.
        #expect(ApiFootball.teamID(for: "Arsenal", abbreviation: "CHE", in: teams) == 42)
        // Maps on disk from before codes were kept still decode, codeless.
        let legacy = try JSONDecoder().decode(
            ApiFootballTeamMap.self,
            from: Data(#"{"season":2026,"served":2024,"teams":[{"id":39,"name":"Wolves"}]}"#.utf8)
        )
        #expect(legacy.teams == [ApiFootballTeam(id: 39, name: "Wolves")])
        #expect(ApiFootball.teamID(for: "Wolverhampton Wanderers", in: legacy.teams) == 39)
    }

    @Test("/status: a good key's plan and usage; a bad key's errors")
    func status() throws {
        #expect(
            ApiFootball.parseStatus(try Fixture.json("apifootball_status_ok"), status: 200)
                == .accepted(summary: "Free plan, 3 of 100 requests used today")
        )
        guard case .failed(let message) = ApiFootball.parseStatus(
            try Fixture.json("apifootball_status_bad_key"), status: 200
        ) else {
            Issue.record("A bad key's answer was accepted")
            return
        }
        #expect(message.contains("Missing application key"))
        guard case .failed = ApiFootball.parseStatus(.null, status: 403) else {
            Issue.record("A 403 was accepted")
            return
        }
    }

    @Test("The key header goes to the keyed API only, never the CDN")
    func requestGate() throws {
        let players = try #require(ApiFootball.playersURL(league: 39, season: 2026, page: 3))
        #expect(players.absoluteString == "https://v3.football.api-sports.io/players?league=39&season=2026&page=3")
        let request = try #require(ApiFootball.keyedRequest(players, key: "k"))
        #expect(request.value(forHTTPHeaderField: "x-apisports-key") == "k")
        let team = try #require(ApiFootball.teamPlayersURL(team: 42, season: 2024, page: 2))
        #expect(team.absoluteString == "https://v3.football.api-sports.io/players?team=42&season=2024&page=2")
        #expect(ApiFootball.keyedRequest(team, key: "k")?.value(forHTTPHeaderField: "x-apisports-key") == "k")
        let teams = try #require(ApiFootball.teamsURL(league: 39, season: 2026))
        #expect(teams.absoluteString == "https://v3.football.api-sports.io/teams?league=39&season=2026")
        #expect(ApiFootball.keyedRequest(teams, key: "k")?.value(forHTTPHeaderField: "x-apisports-key") == "k")

        let photo = try #require(ApiFootball.photoURL(playerID: 900001))
        #expect(photo.absoluteString == "https://media.api-sports.io/football/players/900001.png")
        #expect(ApiFootball.keyedRequest(photo, key: "k") == nil)
        #expect(ApiFootball.keyedRequest(try #require(URL(string: "http://v3.football.api-sports.io/status")), key: "k") == nil)
        #expect(ApiFootball.keyedRequest(try #require(URL(string: "https://example.com/status")), key: "k") == nil)
    }

    @Test("Soccer leagues map to API-Football's ids and seasons; other sports to none")
    func leagues() {
        #expect(ApiFootball.leagueID(for: .premierLeague) == 39)
        #expect(ApiFootball.leagueID(for: .bundesliga) == 78)
        #expect(ApiFootball.leagueID(for: .ligue1) == 61)
        #expect(ApiFootball.leagueID(for: .ligaMX) == 262)
        #expect(ApiFootball.leagueID(for: .wsl) == 44)
        #expect(ApiFootball.leagueID(for: .nwsl) == 254)
        #expect(ApiFootball.leagueID(for: .nba) == nil)
        #expect(ApiFootball.leagueID(for: .championsLeague) == nil)
        for league in ApiFootball.leagueIDs.keys {
            #expect(league.descriptor.kind == .soccer)
        }
        // 2026-27 is 2026; MLS plays in the calendar year.
        #expect(ApiFootball.season(for: .premierLeague, at: october7) == 2026)
        #expect(ApiFootball.season(for: .premierLeague, at: october7.addingTimeInterval(150 * 86_400)) == 2026)
        #expect(ApiFootball.season(for: .mls, at: october7) == 2026)
    }

    @Test("Only the CDN's two placeholder images, byte for byte, count as no photo")
    func placeholders() {
        #expect(Set(ApiFootball.placeholderHashes.keys) == [5192, 8624])
        #expect(!ApiFootball.isPlaceholder(Data(count: 5192)))
        #expect(!ApiFootball.isPlaceholder(Data(count: 100)))
    }
}

// MARK: - Join

/// Joining API-Football rows to ESPN rosters by name and team, never id.
@Suite("API-Football name join")
struct ApiFootballJoinTests {
    @Test("Names fold accents, ligatures, hyphens, apostrophes and initials")
    func tokens() {
        #expect(ApiFootball.tokens("Martin Ødegaard") == ["martin", "odegaard"])
        #expect(ApiFootball.tokens("Gabriel Magalhães") == ["gabriel", "magalhaes"])
        #expect(ApiFootball.tokens("Myles Lewis-Skelly") == ["myles", "lewis", "skelly"])
        #expect(ApiFootball.tokens("J. O’Neil") == ["j", "oneil"])
    }

    @Test("Teams match across suffixes and women's markers, not across clubs")
    func teams() {
        #expect(ApiFootball.teamsMatch("Arsenal", "Arsenal"))
        #expect(ApiFootball.teamsMatch("Chelsea", "Chelsea W"))
        #expect(ApiFootball.teamsMatch("Paris Saint-Germain", "Paris Saint Germain"))
        #expect(ApiFootball.teamsMatch("Inter", "Internazionale"))
        #expect(!ApiFootball.teamsMatch("Manchester United", "Manchester City"))
        #expect(!ApiFootball.teamsMatch("Arsenal", "Brighton"))
        #expect(!ApiFootball.teamsMatch("FC", "W"))
    }

    @Test("Arsenal's ESPN roster joins its API-Football rows by name and team")
    func arsenal() throws {
        let (roster, team) = try espnRoster("epl_roster")
        #expect(team == "Arsenal")
        let players = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p1"), league: 39).players
            + ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p2"), league: 39).players

        let joined = ApiFootball.join(roster: roster, team: team, league: .premierLeague, players: players)
            .mapValues(\.id)
        #expect(joined == [
            "196176": 900001,  // David Raya ↔ David / Raya Martín
            "236322": 900002,  // Gabriel Magalhães ↔ the short name
            "241077": 900003,  // Ben White ↔ B. White, not Brighton's Ben White
            "169532": 900004,  // Kepa Arrizabalaga ↔ Kepa / Arrizabalaga Revuelta
            "203669": 900007,  // Martin Ødegaard
            "352758": 900008,  // Myles Lewis-Skelly
            "280555": 900009,  // Bukayo Saka
        ])
        // Meslier is on Arsenal's ESPN roster but Leeds' row: no match.
        #expect(joined["265921"] == nil)
    }

    @Test("A WSL player never matches a men's row, however alike the name and club")
    func genderSafe() throws {
        let (roster, team) = try espnRoster("wsl_roster")
        #expect(team == "Chelsea")
        let mens = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p2"), league: 39).players
        let womens = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_wsl_p1"), league: 44).players
        let laurenJames = "294253"

        // The hazard: Chelsea's men's "L. James" fits Lauren James on name
        // and club alone.
        let unscoped = ApiFootball.join(roster: roster, team: team, league: .premierLeague, players: mens)
        #expect(unscoped[laurenJames]?.id == 900010)

        // Scoped to the WSL's own league, only the women's rows count.
        let men = ApiFootball.join(roster: roster, team: team, league: .wsl, players: mens)
        #expect(men.isEmpty)
        let joined = ApiFootball.join(roster: roster, team: team, league: .wsl, players: mens + womens)
            .mapValues(\.id)
        #expect(joined == [
            laurenJames: 910001,
            "188448": 910002,  // Lucy Bronze ↔ L. Bronze
            "312460": 910003,  // Hannah Hampton
        ])
    }

    @Test("An aliased club joins its rows by name and team; the alias never joins a player by id")
    func aliasJoin() {
        let rows = [
            ApiFootballPlayer(id: 1001, name: "José Sá", firstname: "José", lastname: "Sá", photo: nil, teams: ["Wolves"], league: 39),
            ApiFootballPlayer(id: 1002, name: "M. Cunha", firstname: "Matheus", lastname: "Cunha", photo: nil, teams: ["Wolves"], league: 39),
            ApiFootballPlayer(id: 1003, name: "J. Sá", firstname: "João", lastname: "Sá", photo: nil, teams: ["Brighton"], league: 39),
        ]
        let roster = [
            ApiFootballRosterEntry(espnID: "1001", name: "Someone Else"),
            ApiFootballRosterEntry(espnID: "w-sa", name: "José Sá"),
            ApiFootballRosterEntry(espnID: "w-cunha", name: "Matheus Cunha"),
        ]
        let joined = ApiFootball.join(roster: roster, team: "Wolverhampton Wanderers", league: .premierLeague, players: rows)
            .mapValues(\.id)
        #expect(joined == ["w-sa": 1001, "w-cunha": 1002])
        // Sharing an id with a row is no match.
        #expect(joined["1001"] == nil)
    }

    @Test("Two candidate rows for one player are left unmatched")
    func ambiguous() {
        let rows = [
            ApiFootballPlayer(id: 1, name: "B. White", firstname: "Ben", lastname: "White", photo: nil, teams: ["Arsenal"], league: 39),
            ApiFootballPlayer(id: 2, name: "B. White", firstname: "Bradley", lastname: "White", photo: nil, teams: ["Arsenal"], league: 39),
        ]
        let roster = [ApiFootballRosterEntry(espnID: "241077", name: "Ben White")]
        // The full name settles it…
        #expect(ApiFootball.join(roster: roster, team: "Arsenal", league: .premierLeague, players: rows)["241077"]?.id == 1)
        // …but initials alone do not.
        let initialsOnly = rows.map { row in
            var row = row
            row.firstname = "B"
            return row
        }
        #expect(ApiFootball.join(roster: roster, team: "Arsenal", league: .premierLeague, players: initialsOnly).isEmpty)
    }

    /// The device bug of 2026-10-07, replayed over live captures: the free
    /// plan's three league pages are its longest-serving players, none on
    /// Arsenal's roster today; Arsenal's own three pages match most of it.
    @Test("Live data: the league route joins no current Arsenal player; the team route joins 10+")
    func liveRoutes() throws {
        let (roster, team) = try espnRoster("arsenal_roster_live")
        #expect(team == "Arsenal")
        #expect(roster.count == 27)

        let league = try (1...3).flatMap { page in
            ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_live_p\(page)"), league: 39).players
        }
        #expect(league.count == 60)
        #expect(ApiFootball.join(roster: roster, team: team, league: .premierLeague, players: league).isEmpty)

        let joined = ApiFootball.join(roster: roster, team: team, league: .premierLeague, players: try team42Players())
            .mapValues(\.id)
        #expect(joined.count >= 10)
        #expect(joined["196176"] == 19465)  // David Raya
        #expect(joined["169532"] == 2273)  // Kepa Arrizabalaga ↔ Kepa
        #expect(joined["241077"] == 19959)  // Ben White ↔ B. White
        #expect(joined["236322"] == 22224)  // Gabriel Magalhães
        #expect(joined["203669"] == 37127)  // Martin Ødegaard ↔ M. Ødegaard
        #expect(joined["231182"] == 978)  // Kai Havertz
        #expect(joined["280555"] == 1460)  // Bukayo Saka
    }
}

// MARK: - Budget

/// The per-UTC-day request cap.
@Suite("API-Football budget")
struct ApiFootballBudgetTests {
    @Test("The 40th request of a day is allowed, the 41st is not, and the next day starts again")
    func capAndRollover() throws {
        let suite = "ApiFootballBudgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(october7)
        let budget = ApiFootballBudget(defaults: defaults, now: { clock.now })
        #expect(budget.cap == 40)

        for _ in 1...40 {
            #expect(budget.spend())
        }
        #expect(budget.used == 40)
        #expect(!budget.canSpend)
        #expect(!budget.spend())
        #expect(budget.used == 40)

        // 11:59 pm UTC is still the same day.
        clock.now = october7.addingTimeInterval(12 * 3600 - 60)
        #expect(!budget.canSpend)

        clock.now = october7.addingTimeInterval(12 * 3600)
        #expect(ApiFootballBudget.day(clock.now) == "2026-10-08")
        #expect(budget.used == 0)
        #expect(budget.canSpend)
        #expect(budget.spend())
        #expect(budget.used == 1)
    }
}

// MARK: - Store

/// The store's sweep, gated on the key and toggle, paced by the budget,
/// cached on disk.
@Suite("API-Football store", .serialized)
@MainActor
struct ApiFootballGatingTests {
    private static let key = "test-key-not-real-0000"

    private struct Harness {
        let store: ApiFootballHeadshotStore
        let transport: RecordingTransport
        let directory: URL
        let defaults: UserDefaults
        let suite: String

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    /// Answers `/teams` with the EPL's clubs, and each `/players` page
    /// from its fixture.
    private static func eplTransport() -> RecordingTransport {
        RecordingTransport { url, _ in
            let name = url.path() == "/teams"
                ? "apifootball_teams_epl_live"
                : page(of: url) == "2" ? "apifootball_players_epl_p2" : "apifootball_players_epl_p1"
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
    }

    private func makeHarness(
        transport: RecordingTransport = ApiFootballGatingTests.eplTransport(),
        cap: Int = ApiFootball.dailyRequestCap,
        directory: URL? = nil,
        credentials: @escaping @MainActor () -> String?
    ) throws -> Harness {
        let suite = "ApiFootballGatingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = directory ?? FileManager.default.temporaryDirectory
            .appending(path: "ApiFootballGatingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = ApiFootballHeadshotStore(
            transport: transport,
            directory: directory,
            credentials: credentials,
            budget: ApiFootballBudget(defaults: defaults, cap: cap),
            spacing: .zero,
            now: { october7 },
            enabled: true
        )
        return Harness(store: store, transport: transport, directory: directory, defaults: defaults, suite: suite)
    }

    private func settings(key: String?, enabled: Bool) throws -> ApiFootballSettings {
        let suite = "ApiFootballGatingTests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(enabled, forKey: ApiFootballSettings.enabledKey)
        return ApiFootballSettings(
            storage: InMemorySecretStorage(key),
            defaults: defaults,
            transport: RecordingTransport(always: .status(500))
        )
    }

    @Test("No key: not one request")
    func noKey() async throws {
        let settings = try settings(key: nil, enabled: true)
        let harness = try makeHarness { settings.activeKey() }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.isEmpty)
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague) == nil)
    }

    @Test("Toggle off: not one request")
    func toggleOff() async throws {
        let settings = try settings(key: Self.key, enabled: false)
        let harness = try makeHarness { settings.activeKey() }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.isEmpty)
    }

    @Test("Key and toggle: the sweep finds the club and pages through it with the key, and photos join")
    func sweeps() async throws {
        let settings = try settings(key: Self.key, enabled: true)
        let harness = try makeHarness { settings.activeKey() }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=1",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=2",
        ])
        for request in harness.transport.requests {
            #expect(request.value(forHTTPHeaderField: "x-apisports-key") == Self.key)
        }
        #expect(ApiFootballBudget(defaults: harness.defaults).used == 3)

        let raya = try #require(harness.store.photo(espnID: "196176", league: .premierLeague))
        #expect(raya.playerID == 900001)
        #expect(raya.imageURL?.absoluteString == "https://media.api-sports.io/football/players/900001.png")
        #expect(harness.store.photo(espnID: "280555", league: .premierLeague)?.playerID == 900009)

        // Swept this week: another roster load asks nothing.
        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 3)

        // Turning the toggle off hides the photos at once.
        settings.isEnabled = false
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague) == nil)
    }

    /// The field bug in 1.0.10: a fresh install opens a soccer team's page,
    /// its roster loads (no key yet: nothing asked), then the reader saves
    /// a key from Settings — a sheet over that same page. The roster does
    /// not change, so the page's roster hook never runs again, and the
    /// league was never swept. Saving the key must start the sweep for the
    /// roster already on screen.
    @Test("A key saved after the roster loaded sweeps that roster's league")
    func keySavedAfterRosterLoad() async throws {
        let suite = "ApiFootballGatingTests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // A fresh install: no key, no toggle, no sweep on disk.
        let probe = RecordingTransport { _, _ in
            (try? RecordingTransport.Reply.fixture("apifootball_status_ok")) ?? .status(500)
        }
        let settings = ApiFootballSettings(storage: InMemorySecretStorage(), defaults: defaults, transport: probe)
        let harness = try makeHarness { settings.activeKey() }
        defer { harness.tearDown() }
        #expect(!FileManager.default.fileExists(atPath: harness.store.fileURL(for: 39).path()))
        #expect(!FileManager.default.fileExists(atPath: harness.store.teamMapURL(for: 39).path()))
        let (roster, team) = try espnRoster("epl_roster")

        // The roster loads before there is a key: not one request.
        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.isEmpty)

        // Settings → API-Football: the key is checked and saved, which
        // turns the toggle on. The app then calls `resume()`.
        await settings.save(Self.key)
        #expect(settings.activeKey() == Self.key)
        harness.store.resume()
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=1",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=2",
        ])
        for request in harness.transport.requests {
            #expect(request.value(forHTTPHeaderField: "x-apisports-key") == Self.key)
        }
        // The roster seen before the key joins without loading again.
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)
    }

    @Test("Resuming without a key, or with the toggle off, asks nothing")
    func resumeWithoutKey() async throws {
        let (roster, team) = try espnRoster("epl_roster")
        for (key, enabled) in [(nil, true), (Self.key, false)] as [(String?, Bool)] {
            let settings = try settings(key: key, enabled: enabled)
            let harness = try makeHarness { settings.activeKey() }
            defer { harness.tearDown() }

            harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
            harness.store.resume()
            await harness.store.settle()
            #expect(harness.transport.urls.isEmpty)
            #expect(harness.store.photo(espnID: "196176", league: .premierLeague) == nil)
        }
    }

    @Test("Other sports, and soccer leagues with no API-Football id, ask nothing")
    func otherLeagues() async throws {
        let harness = try makeHarness { Self.key }
        defer { harness.tearDown() }
        let roster = [ApiFootballRosterEntry(espnID: "1", name: "Some One")]

        harness.store.prefetch(roster: roster, team: "Lakers", league: .nba)
        harness.store.prefetch(roster: roster, team: "Arsenal", league: .championsLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.isEmpty)
    }

    @Test("A capped day pauses the sweep; it resumes where it stopped")
    func budgetPauses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ApiFootballGatingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let (roster, team) = try espnRoster("epl_roster")

        // The club map, then page 1.
        let capped = try makeHarness(cap: 2, directory: directory) { Self.key }
        defer { capped.tearDown() }
        capped.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await capped.store.settle()
        #expect(capped.transport.urls.map { page(of: $0) } == [nil, "1"])
        // Page 1's rows are drawable already.
        #expect(capped.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)

        // A later day (a fresh budget), from the cache on disk: page 2
        // only — the map is on disk too.
        let resumed = try makeHarness(directory: directory) { Self.key }
        defer { resumed.tearDown() }
        resumed.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await resumed.store.settle()
        #expect(resumed.transport.urls.map { page(of: $0) } == ["2"])
        #expect(resumed.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)
        #expect(resumed.store.photo(espnID: "280555", league: .premierLeague)?.playerID == 900009)
    }

    @Test("A free plan's season error falls back to the newest season it offers")
    func seasonFallback() async throws {
        let transport = RecordingTransport { url, _ in
            let name = query("season", of: url) != "2024"
                ? "apifootball_players_plan_error"
                : url.path() == "/teams"
                    ? "apifootball_teams_epl_live"
                    : (page(of: url) == "2" ? "apifootball_players_epl_p2" : "apifootball_players_epl_p1")
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
        let harness = try makeHarness(transport: transport) { Self.key }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        // The map falls back; the club's sweep starts at the season it got.
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/teams?league=39&season=2024",
            "https://v3.football.api-sports.io/players?team=42&season=2024&page=1",
            "https://v3.football.api-sports.io/players?team=42&season=2024&page=2",
        ])
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)
    }

    /// The device bug of 2026-10-07: the free plan refuses any page past 3,
    /// and the sweep paused an hour on that refusal, then asked for page 4
    /// again at the next roster load — forever, never finishing. A page-cap
    /// error now ends the sweep with what it found.
    @Test("Free-plan page cap completes the sweep")
    func pageCapCompletes() async throws {
        // Pages 1-3 are live league pages (`paging.total` 57); page 4 is
        // the live refusal.
        let route: @Sendable (URL, Int) -> RecordingTransport.Reply = { url, _ in
            let name = switch (url.path(), page(of: url) ?? "") {
            case ("/teams", _): "apifootball_teams_epl_live"
            case (_, "1"): "apifootball_players_epl_live_p1"
            case (_, "2"): "apifootball_players_epl_live_p2"
            case (_, "3"): "apifootball_players_epl_live_p3"
            default: "apifootball_players_page_cap"
            }
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
        let transport = RecordingTransport(route)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ApiFootballGatingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let harness = try makeHarness(transport: transport, directory: directory) { Self.key }
        defer { harness.tearDown() }
        // The two Arsenal players in the league's first three pages.
        let roster = [
            ApiFootballRosterEntry(espnID: "e-partey", name: "Thomas Partey"),
            ApiFootballRosterEntry(espnID: "e-cedric", name: "Cédric Soares"),
        ]

        harness.store.prefetch(roster: roster, team: "Arsenal", league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=1",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=2",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=3",
            "https://v3.football.api-sports.io/players?team=42&season=2026&page=4",
        ])

        // Finished, on disk, with every row the plan gave.
        let data = try Data(contentsOf: harness.store.teamFileURL(for: 42))
        let sweep = try JSONDecoder().decode(ApiFootballSweep.self, from: data)
        #expect(sweep.route == .team)
        #expect(sweep.completed == october7)
        #expect(sweep.pageCap == 3)
        #expect(sweep.players.count == 60)
        #expect(harness.store.photo(espnID: "e-partey", league: .premierLeague)?.playerID == 49)
        #expect(harness.store.photo(espnID: "e-cedric", league: .premierLeague)?.playerID == 190)

        // No pause loop: the next roster load asks nothing…
        harness.store.prefetch(roster: roster, team: "Arsenal", league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 5)

        // …nor does a relaunch, from the cache on disk (its own transport,
        // so the first run's requests don't count against it)…
        let relaunched = try makeHarness(transport: RecordingTransport(route), directory: directory) { Self.key }
        defer { relaunched.tearDown() }
        relaunched.store.prefetch(roster: roster, team: "Arsenal", league: .premierLeague)
        await relaunched.store.settle()
        #expect(relaunched.transport.requestCount == 0)
        #expect(relaunched.store.photo(espnID: "e-partey", league: .premierLeague)?.playerID == 49)

        // …and the store is not paused: another club still sweeps.
        harness.store.prefetch(roster: [ApiFootballRosterEntry(espnID: "1", name: "Cole Palmer")], team: "Chelsea", league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.dropFirst(5).first?.absoluteString
            == "https://v3.football.api-sports.io/players?team=49&season=2026&page=1")
    }

    @Test("Team route: opening a club sweeps that team and joins it")
    func teamRoute() async throws {
        // Live captures: the free plan refuses 2026 and offers 2024, for
        // `/teams` as for `/players`.
        let transport = RecordingTransport { url, _ in
            let name = query("season", of: url) != "2024"
                ? "apifootball_players_plan_error"
                : url.path() == "/teams"
                    ? "apifootball_teams_epl_live"
                    : "apifootball_players_team\(query("team", of: url) ?? "")_p\(page(of: url) ?? "")"
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
        let harness = try makeHarness(transport: transport) { Self.key }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("arsenal_roster_live")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/teams?league=39&season=2024",
            "https://v3.football.api-sports.io/players?team=42&season=2024&page=1",
            "https://v3.football.api-sports.io/players?team=42&season=2024&page=2",
            "https://v3.football.api-sports.io/players?team=42&season=2024&page=3",
        ])
        for request in harness.transport.requests {
            #expect(request.value(forHTTPHeaderField: "x-apisports-key") == Self.key)
        }
        #expect(ApiFootballBudget(defaults: harness.defaults).used == 5)

        let raya = try #require(harness.store.photo(espnID: "196176", league: .premierLeague))
        #expect(raya.playerID == 19465)
        #expect(raya.imageURL?.absoluteString == "https://media.api-sports.io/football/players/19465.png")
        #expect(harness.store.photo(espnID: "280555", league: .premierLeague)?.playerID == 1460)  // Saka
        #expect(harness.store.photo(espnID: "203669", league: .premierLeague)?.playerID == 37127)  // Ødegaard
        #expect(harness.store.photo(espnID: "231182", league: .premierLeague)?.playerID == 978)  // Havertz
        let matched = roster.filter { harness.store.photo(espnID: $0.espnID, league: .premierLeague) != nil }
        #expect(matched.count >= 10)

        // Swept this week, map and club: another roster load asks nothing.
        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 5)
    }

    @Test("A sweep file from the league route still loads and joins")
    func legacyLeagueFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ApiFootballGatingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Written before `route` and `pageCap` existed.
        let players = ApiFootball.parsePlayers(try Fixture.json("apifootball_players_epl_p1"), league: 39).players
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            ApiFootballSweep(season: 2026, nextPage: 1, completed: october7, players: players)
        )) as? [String: Any] ?? [:]
        legacy["route"] = nil
        legacy["pageCap"] = nil
        let harness = try makeHarness(transport: RecordingTransport(always: .status(500)), directory: directory) { Self.key }
        defer { harness.tearDown() }
        try JSONSerialization.data(withJSONObject: legacy).write(to: harness.store.fileURL(for: 39))
        let sweep = try JSONDecoder().decode(ApiFootballSweep.self, from: Data(contentsOf: harness.store.fileURL(for: 39)))
        #expect(sweep.route == .league)
        #expect(sweep.players.count == players.count)

        let reloaded = try makeHarness(transport: RecordingTransport(always: .status(500)), directory: directory) { Self.key }
        defer { reloaded.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")
        reloaded.store.prefetch(roster: roster, team: team, league: .premierLeague)
        #expect(reloaded.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)
        await reloaded.store.settle()
    }

    @Test("A failed page stops the sweep quietly")
    func failureIsSilent() async throws {
        let harness = try makeHarness(transport: RecordingTransport(always: .status(500))) { Self.key }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 1)
        // Paused: the next roster load asks nothing.
        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 1)
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague) == nil)
    }

    @Test("The image loader fetches from the CDN only, with no key")
    func imageLoaderHost() async throws {
        let transport = RecordingTransport(always: .status(404))
        let loader = ApiFootballImageLoader(transport: transport, enabled: true)

        let api = try #require(URL(string: "https://v3.football.api-sports.io/players?id=1"))
        #expect(await loader.image(for: api) == nil)
        #expect(transport.urls.isEmpty)

        let photo = try #require(ApiFootball.photoURL(playerID: 900001))
        #expect(await loader.image(for: photo) == nil)
        #expect(transport.urls == [photo])
        // Plain URL loads: no keyed request was ever made.
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - Coverage

/// Answers `/players` with `rows` as one page.
private func playersReply(_ rows: [(id: Int, first: String, last: String, team: String)]) -> RecordingTransport.Reply {
    let response = rows.map { row in
        #"{"player":{"id":\#(row.id),"name":"\#(row.first) \#(row.last)","firstname":"\#(row.first)","#
            + #""lastname":"\#(row.last)","photo":"https://media.api-sports.io/football/players/\#(row.id).png"},"#
            + #""statistics":[{"team":{"name":"\#(row.team)"}}]}"#
    }
    let body = #"{"errors":[],"paging":{"current":1,"total":1},"response":["# + response.joined(separator: ",") + "]}"
    return RecordingTransport.Reply(body: Data(body.utf8))
}

/// A transport that notes the day's count as each request goes out, then
/// fails with no answer or answers `status`.
private final class BudgetProbeTransport: KeyedHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []
    private let defaults: UserDefaults
    private let status: Int?

    /// - Parameter status: the answer's status; `nil` for no answer at all.
    init(defaults: UserDefaults, status: Int?) {
        self.defaults = defaults
        self.status = status
    }

    /// The day's count as each request went out.
    var countsAtSend: [Int] { lock.withLock { counts } }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let used = ApiFootballBudget(defaults: defaults).used
        lock.withLock { counts.append(used) }
        guard let status, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else { throw URLError(.notConnectedToInternet) }
        return (Data(), response)
    }
}

/// Club aliases and codes, the budget spent on answers, the persisted
/// pause and the usage readout (R-11).
@Suite("API-Football coverage", .serialized)
@MainActor
struct ApiFootballCoverageTests {
    private static let key = "test-key-not-real-0000"

    private func scratch() throws -> (directory: URL, defaults: UserDefaults, suite: String) {
        let suite = "ApiFootballCoverageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ApiFootballCoverageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (directory, defaults, suite)
    }

    private func makeStore(
        _ transport: any KeyedHTTPTransport,
        directory: URL,
        defaults: UserDefaults,
        now: @escaping () -> Date = { october7 }
    ) -> ApiFootballHeadshotStore {
        ApiFootballHeadshotStore(
            transport: transport,
            directory: directory,
            credentials: { Self.key },
            budget: ApiFootballBudget(defaults: defaults, now: now),
            spacing: .zero,
            now: now,
            enabled: true
        )
    }

    /// The EPL's live club map, and Wolves' players (team 39).
    private static func wolvesTransport() -> RecordingTransport {
        RecordingTransport { url, _ in
            if url.path() == "/teams" {
                return (try? RecordingTransport.Reply.fixture("apifootball_teams_epl_live")) ?? .status(404)
            }
            guard query("team", of: url) == "39" else { return .status(404) }
            return playersReply([(1001, "José", "Sá", "Wolves"), (1002, "Matheus", "Cunha", "Wolves")])
        }
    }

    @Test("ESPN's \"Wolverhampton Wanderers\" sweeps API-Football's \"Wolves\" and joins its rows")
    func wolvesAlias() async throws {
        let (directory, defaults, suite) = try scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let transport = Self.wolvesTransport()
        let store = makeStore(transport, directory: directory, defaults: defaults)
        let roster = [
            ApiFootballRosterEntry(espnID: "w-sa", name: "José Sá"),
            ApiFootballRosterEntry(espnID: "w-cunha", name: "Matheus Cunha"),
        ]

        store.prefetch(roster: roster, team: "Wolverhampton Wanderers", league: .premierLeague)
        await store.settle()
        #expect(transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/teams?league=39&season=2026",
            "https://v3.football.api-sports.io/players?team=39&season=2026&page=1",
        ])
        #expect(store.photo(espnID: "w-sa", league: .premierLeague)?.playerID == 1001)
        #expect(store.photo(espnID: "w-cunha", league: .premierLeague)?.playerID == 1002)
        #expect(store.unmatchedClubs[.premierLeague] == nil)
    }

    @Test("A club no name matches is found by ESPN's abbreviation, and joined under API-Football's name")
    func codeFallback() async throws {
        let (directory, defaults, suite) = try scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let transport = RecordingTransport { url, _ in
            if url.path() == "/teams" {
                return (try? RecordingTransport.Reply.fixture("apifootball_teams_epl_live")) ?? .status(404)
            }
            guard query("team", of: url) == "47" else { return .status(404) }
            return playersReply([(2001, "Heung-min", "Son", "Tottenham")])
        }
        let store = makeStore(transport, directory: directory, defaults: defaults)
        let roster = [ApiFootballRosterEntry(espnID: "s-son", name: "Heung-min Son")]

        store.prefetch(roster: roster, team: "Spurs", abbreviation: "TOT", league: .premierLeague)
        await store.settle()
        #expect(transport.urls.last?.absoluteString == "https://v3.football.api-sports.io/players?team=47&season=2026&page=1")
        // The rows name "Tottenham", not "Spurs": joined by the club the code found.
        #expect(store.photo(espnID: "s-son", league: .premierLeague)?.playerID == 2001)
    }

    @Test("A club nothing matches is logged once and never swept")
    func unmatchedClubLogged() async throws {
        let (directory, defaults, suite) = try scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let transport = Self.wolvesTransport()
        let store = makeStore(transport, directory: directory, defaults: defaults)
        let roster = [ApiFootballRosterEntry(espnID: "1", name: "Some One")]

        store.prefetch(roster: roster, team: "Sunderland", abbreviation: "SUN", league: .premierLeague)
        await store.settle()
        #expect(transport.urls.map { $0.path() } == ["/teams"])
        #expect(store.unmatchedClubs[.premierLeague] == ["Sunderland"])
        store.prefetch(roster: roster, team: "Sunderland", league: .premierLeague)
        await store.settle()
        #expect(transport.requestCount == 1)
        #expect(store.unmatchedClubs[.premierLeague] == ["Sunderland"])
    }

    @Test("The budget is spent once API-Football answers, error or not; no answer spends nothing")
    func budgetAfterResponse() async throws {
        let (roster, team) = try espnRoster("epl_roster")
        for (status, spent) in [(500, 1), (nil, 0)] as [(Int?, Int)] {
            let (directory, defaults, suite) = try scratch()
            defer {
                try? FileManager.default.removeItem(at: directory)
                defaults.removePersistentDomain(forName: suite)
            }
            let transport = BudgetProbeTransport(defaults: defaults, status: status)
            let store = makeStore(transport, directory: directory, defaults: defaults, now: { Date() })

            store.prefetch(roster: roster, team: team, league: .premierLeague)
            await store.settle()
            // Nothing was counted as the request went out…
            #expect(transport.countsAtSend == [0])
            // …the answer was; a request that got none was not.
            #expect(ApiFootballBudget(defaults: defaults).used == spent)
            // Either way the store pauses.
            #expect(store.isPaused)
        }
    }

    @Test("The failure pause outlives a relaunch and ends an hour later on the injected clock")
    func persistedPause() async throws {
        let (directory, defaults, suite) = try scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let (roster, team) = try espnRoster("epl_roster")
        let clock = TestClock(october7)

        let failing = RecordingTransport(always: .status(500))
        let first = makeStore(failing, directory: directory, defaults: defaults) { clock.now }
        first.prefetch(roster: roster, team: team, league: .premierLeague)
        await first.settle()
        #expect(failing.requestCount == 1)
        #expect(defaults.object(forKey: ApiFootballBudget.pauseKey) as? Date == october7.addingTimeInterval(3600))

        // Relaunched 59 minutes on: still paused, nothing asked.
        clock.now = october7.addingTimeInterval(59 * 60)
        let transport = EPLReplies.epl()
        let relaunched = makeStore(transport, directory: directory, defaults: defaults) { clock.now }
        #expect(relaunched.isPaused)
        relaunched.prefetch(roster: roster, team: team, league: .premierLeague)
        await relaunched.settle()
        #expect(transport.requestCount == 0)

        // 61 minutes on: the sweep runs.
        clock.now = october7.addingTimeInterval(61 * 60)
        #expect(!relaunched.isPaused)
        relaunched.prefetch(roster: roster, team: team, league: .premierLeague)
        await relaunched.settle()
        #expect(transport.urls.first?.absoluteString == "https://v3.football.api-sports.io/teams?league=39&season=2026")
    }

    @Test("Usage: today's requests of 40, clubs swept and photos found; the count starts again each UTC day")
    func usage() async throws {
        let (directory, defaults, suite) = try scratch()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let (roster, team) = try espnRoster("epl_roster")
        let clock = TestClock(october7)
        let transport = EPLReplies.epl()
        let store = makeStore(transport, directory: directory, defaults: defaults) { clock.now }
        #expect(store.usage == ApiFootballUsage(requestsToday: 0, cap: 40, clubsSwept: 0, photosFound: 0))

        store.prefetch(roster: roster, team: team, league: .premierLeague)
        await store.settle()
        // The map and Arsenal's two pages; Arsenal's seven joined players.
        #expect(store.usage == ApiFootballUsage(requestsToday: 3, cap: 40, clubsSwept: 1, photosFound: 7))
        #expect(store.usage.summary == "3/40 requests today · 1 club swept · 7 photos found")

        // Past UTC midnight: a new day's count; the sweep and photos stay.
        clock.now = october7.addingTimeInterval(12 * 3600)
        #expect(store.usage == ApiFootballUsage(requestsToday: 0, cap: 40, clubsSwept: 1, photosFound: 7))
        #expect(
            ApiFootballUsage(requestsToday: 12, cap: 40, clubsSwept: 3, photosFound: 1).summary
                == "12/40 requests today · 3 clubs swept · 1 photo found"
        )
    }
}

/// `/teams` with the EPL's clubs and each `/players` page from its fixture,
/// as `ApiFootballGatingTests` answers.
private enum EPLReplies {
    static func epl() -> RecordingTransport {
        RecordingTransport { url, _ in
            let name = url.path() == "/teams"
                ? "apifootball_teams_epl_live"
                : page(of: url) == "2" ? "apifootball_players_epl_p2" : "apifootball_players_epl_p1"
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
    }
}
