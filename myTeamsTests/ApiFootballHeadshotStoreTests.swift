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

/// The page asked for in a `/players` URL.
private func page(of url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "page" }?.value
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

    /// Answers each EPL page from its fixture.
    private static func eplTransport() -> RecordingTransport {
        RecordingTransport { url, _ in
            let name = page(of: url) == "2" ? "apifootball_players_epl_p2" : "apifootball_players_epl_p1"
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

    @Test("Key and toggle: the sweep pages through the league with the key, and photos join")
    func sweeps() async throws {
        let settings = try settings(key: Self.key, enabled: true)
        let harness = try makeHarness { settings.activeKey() }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/players?league=39&season=2026&page=1",
            "https://v3.football.api-sports.io/players?league=39&season=2026&page=2",
        ])
        for request in harness.transport.requests {
            #expect(request.value(forHTTPHeaderField: "x-apisports-key") == Self.key)
        }
        #expect(ApiFootballBudget(defaults: harness.defaults).used == 2)

        let raya = try #require(harness.store.photo(espnID: "196176", league: .premierLeague))
        #expect(raya.playerID == 900001)
        #expect(raya.imageURL?.absoluteString == "https://media.api-sports.io/football/players/900001.png")
        #expect(harness.store.photo(espnID: "280555", league: .premierLeague)?.playerID == 900009)

        // Swept this week: another roster load asks nothing.
        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.requestCount == 2)

        // Turning the toggle off hides the photos at once.
        settings.isEnabled = false
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague) == nil)
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

        let capped = try makeHarness(cap: 1, directory: directory) { Self.key }
        defer { capped.tearDown() }
        capped.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await capped.store.settle()
        #expect(capped.transport.urls.map { page(of: $0) } == ["1"])
        // Page 1's rows are drawable already.
        #expect(capped.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)

        // A later day (a fresh budget), from the cache on disk: page 2 only.
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
            let season = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "season" }?.value
            let name = season == "2024"
                ? (page(of: url) == "2" ? "apifootball_players_epl_p2" : "apifootball_players_epl_p1")
                : "apifootball_players_plan_error"
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
        let harness = try makeHarness(transport: transport) { Self.key }
        defer { harness.tearDown() }
        let (roster, team) = try espnRoster("epl_roster")

        harness.store.prefetch(roster: roster, team: team, league: .premierLeague)
        await harness.store.settle()
        #expect(harness.transport.urls.map(\.absoluteString) == [
            "https://v3.football.api-sports.io/players?league=39&season=2026&page=1",
            "https://v3.football.api-sports.io/players?league=39&season=2024&page=1",
            "https://v3.football.api-sports.io/players?league=39&season=2024&page=2",
        ])
        #expect(harness.store.photo(espnID: "196176", league: .premierLeague)?.playerID == 900001)
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
