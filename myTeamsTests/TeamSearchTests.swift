//
//  TeamSearchTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

private func team(
    _ league: LeagueID,
    _ espnID: String,
    displayName: String,
    shortName: String,
    abbreviation: String,
    location: String
) -> TeamRef {
    TeamRef(
        league: league,
        espnID: espnID,
        displayName: displayName,
        shortName: shortName,
        abbreviation: abbreviation,
        location: location,
        colorHex: "",
        alternateColorHex: "",
        logoURL: nil,
        logoDarkURL: nil,
        logoAsset: nil
    )
}

private let chiefs = team(.nfl, "12", displayName: "Kansas City Chiefs", shortName: "Chiefs", abbreviation: "KC", location: "Kansas City")
private let sporting = team(.mls, "186", displayName: "Sporting Kansas City", shortName: "Sporting KC", abbreviation: "SKC", location: "Sporting Kansas City")
private let realSaltLake = team(.mls, "4771", displayName: "Real Salt Lake", shortName: "Salt Lake", abbreviation: "RSL", location: "Real Salt Lake")
private let malmo = team(LeagueID(sport: "soccer", league: "swe.1"), "2720", displayName: "Malmö FF", shortName: "Malmö", abbreviation: "MFF", location: "Malmö")
private let dodgers = team(.mlb, "19", displayName: "Los Angeles Dodgers", shortName: "Dodgers", abbreviation: "LAD", location: "Los Angeles")

@Suite("Team search")
struct TeamSearchTests {
    @Test("\"kansas\" finds both Kansas City teams, and not the Dodgers")
    func kansas() {
        #expect(TeamSearch.matches(chiefs, query: "kansas"))
        #expect(TeamSearch.matches(sporting, query: "kansas"))
        #expect(TeamSearch.matches(sporting, query: "skc"))
        #expect(!TeamSearch.matches(dodgers, query: "kansas"))
    }

    @Test("Matching folds case and diacritics")
    func folding() {
        #expect(TeamSearch.matches(realSaltLake, query: "real salt lake"))
        #expect(TeamSearch.matches(realSaltLake, query: "  REAL SALT  ") == true)
        #expect(TeamSearch.matches(malmo, query: "malmo"))
        #expect(TeamSearch.matches(malmo, query: "MALMÖ"))
    }

    @Test("The nickname after the location is searchable")
    func nickname() {
        #expect(TeamSearch.searchableFields(of: dodgers).contains("Dodgers"))
        #expect(TeamSearch.matches(chiefs, query: "chie"))
    }

    @Test("An empty query matches everything")
    func emptyQuery() {
        #expect(TeamSearch.matches(dodgers, query: ""))
        #expect(TeamSearch.matches(dodgers, query: "   "))
    }

    @Test("League badges tell the Kansas City teams apart")
    func badges() {
        #expect(chiefs.league.badge == "NFL")
        #expect(sporting.league.badge == "MLS")
        #expect(LeagueID(sport: "football", league: "college-football").badge == "NCAAF")
        #expect(malmo.league.badge == "SWE.1")  // not listed: the league component
    }

    // MARK: Ids

    @Test("Team ids split back into league and ESPN id, as the widget and catalog read them")
    func idRoundTrip() throws {
        for original in [chiefs, sporting, malmo, team(LeagueID(sport: "football", league: "college-football"), "2583", displayName: "", shortName: "", abbreviation: "", location: "")] {
            let parsed = try #require(TeamRef.parse(id: original.id))
            #expect(parsed.league == original.league)
            #expect(parsed.espnID == original.espnID)
            #expect(TeamRef.id(league: parsed.league, espnID: parsed.espnID) == original.id)
        }
        #expect(TeamRef.parse(id: "football/college-football:2583")?.espnID == "2583")
        #expect(TeamRef.parse(id: "jayhawk") == nil)
        #expect(TeamRef.parse(id: "football/nfl:") == nil)
        #expect(TeamRef.parse(id: "nfl:12") == nil)  // a league path has two components
    }

    // MARK: ESPN search

    @Test("ESPN search hits become teams; other result types and malformed hits are dropped")
    func remoteParse() {
        let document = JSON(data: Data(#"""
        {"results": [
          {"type": "player", "contents": [{"displayName": "Patrick Mahomes", "sport": "football", "defaultLeagueSlug": "nfl", "uid": "s:20~l:28~a:3139477"}]},
          {"type": "team", "contents": [
            {"displayName": "Kansas City Current", "sport": "soccer", "defaultLeagueSlug": "usa.nwsl",
             "uid": "s:600~l:2323~t:20907", "image": {"default": "https://a.espncdn.com/i/teamlogos/soccer/500/20907.png"}},
            {"displayName": "Kansas City Current", "sport": "soccer", "defaultLeagueSlug": "usa.nwsl", "uid": "s:600~l:2323~t:20907"},
            {"displayName": "No League", "sport": "soccer", "uid": "s:600~t:1"},
            {"displayName": "Bad Id", "sport": "soccer", "defaultLeagueSlug": "usa.1", "id": "abc"}
          ]}
        ]}
        """#.utf8))
        let teams = TeamSearch.parseSearchResults(document)
        #expect(teams.map(\.id) == ["soccer/usa.nwsl:20907"])
        #expect(teams.first?.displayName == "Kansas City Current")
        #expect(teams.first?.logoURL?.absoluteString == "https://a.espncdn.com/i/teamlogos/soccer/500/20907.png")
    }

    @Test("An ESPN search document of another shape yields no teams")
    func remoteParseGuard() {
        #expect(TeamSearch.parseSearchResults(JSON(data: Data(#"{"items": [{"name": "Chiefs"}]}"#.utf8))).isEmpty)
        #expect(TeamSearch.parseSearchResults(JSON(data: Data(#"{"results": "none"}"#.utf8))).isEmpty)
        #expect(TeamSearch.parseSearchResults(JSON(data: Data("<html>".utf8))).isEmpty)
    }
}

// MARK: - Club search

private let royals = team(.mlb, "7", displayName: "Kansas City Royals", shortName: "Royals", abbreviation: "KC", location: "Kansas City")

/// A `UserDefaults` suite of its own, so tests never touch the App Group.
private func scratchDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "ClubSearchTests.\(UUID().uuidString)"))
}

/// Search grouping a club listed in its league and a cup into one result,
/// over the captured `bundes_teams` and `uclleague_teams` documents (both
/// list Bayern Munich, 132, and Borussia Dortmund, 124). See FIXTURES.md.
@Suite("Club search")
struct ClubSearchTests {
    private func teams(_ fixture: String, league: LeagueID) throws -> [TeamRef] {
        RemoteTeamCatalog.parseTeams(try Fixture.json(fixture), league: league)
    }

    /// The Bundesliga and UCL catalogs, as the picker holds them.
    private func europeanCatalogs() throws -> [LeagueID: [TeamRef]] {
        [
            .bundesliga: try teams("bundes_teams", league: .bundesliga),
            .championsLeague: try teams("uclleague_teams", league: .championsLeague),
        ]
    }

    /// A store holding only `ids`, writing nowhere shared.
    @MainActor
    private func makeStore(following ids: [TeamRef.ID]) throws -> FavoritesStore {
        FavoritesStore(defaults: try scratchDefaults(), cloud: nil, seedIDs: ids, isExistingInstall: true, reloadWidgets: {})
    }

    @Test("1. \"bayern\" is one row, the Bundesliga's, with the UCL as its other league")
    func bayern() throws {
        let clubs = TeamSearch.localClubs(in: try europeanCatalogs(), query: "bayern", current: nil)
        #expect(clubs.map { $0.id } == ["soccer/ger.1:132"])
        #expect(clubs.first?.members.map { $0.id } == ["soccer/ger.1:132", "soccer/uefa.champions:132"])
        #expect(clubs.first?.otherLeagues == [LeagueID.championsLeague])
        #expect(clubs.first?.canonical.league.badge == "Bundesliga")
    }

    @Test("2. A UCL club with no listed league is one row, the UCL's, with no other league")
    func aek() throws {
        let clubs = TeamSearch.localClubs(in: try europeanCatalogs(), query: "aek", current: nil)
        #expect(clubs.map { $0.id } == ["soccer/uefa.champions:887"])
        #expect(clubs.first?.otherLeagues.isEmpty == true)
    }

    @Test("3. \"kansas city\" is still four teams in four leagues")
    func kansasCity() throws {
        let catalogs: [LeagueID: [TeamRef]] = [
            .nfl: try teams("nfl_teams", league: .nfl),
            .nwsl: try teams("nwsl_teams", league: .nwsl),
            .mlb: [royals],
            .mls: [sporting],
        ]
        let clubs = TeamSearch.localClubs(in: catalogs, query: "kansas city", current: nil)
        #expect(Set(clubs.map { $0.id }) == ["football/nfl:12", "soccer/usa.nwsl:20907", "baseball/mlb:7", "soccer/usa.1:186"])
        #expect(clubs.count == 4)
        #expect(clubs.allSatisfy { $0.members.count == 1 && $0.otherLeagues.isEmpty })
    }

    @Test("4. A league with no club elsewhere searches exactly as before", arguments: ["a", "kansas", "new york", "chiefs", "zzz"])
    func nflUnchanged(_ query: String) throws {
        let nfl = try teams("nfl_teams", league: .nfl)
        let before = nfl.filter { TeamSearch.matches($0, query: query) }
        let clubs = TeamSearch.localClubs(in: [.nfl: nfl], query: query, current: nil)
        #expect(clubs.map { $0.canonical } == before)
        #expect(TeamSearch.canonicalClubs(from: nfl) == nfl)
        #expect(clubs.allSatisfy { $0.otherLeagues.isEmpty })
    }

    @MainActor
    @Test("5. A club followed under its cup shows as followed on its league's row")
    func siblingCheckmark() throws {
        // An existing UCL favorite, not migrated.
        let store = try makeStore(following: ["soccer/uefa.champions:132", "football/nfl:12"])
        let bayern = try #require(TeamSearch.localClubs(in: try europeanCatalogs(), query: "bayern", current: nil).first)
        #expect(!store.isFavorite(bayern.id))
        #expect(store.followedClubIDs(of: bayern.canonical) == ["soccer/uefa.champions:132"])
        #expect(store.teamIDs == ["soccer/uefa.champions:132", "football/nfl:12"])

        let dortmund = try #require(TeamSearch.localClubs(in: try europeanCatalogs(), query: "dortmund", current: nil).first)
        #expect(store.followedClubIDs(of: dortmund.canonical).isEmpty)
    }

    @MainActor
    @Test("6. Toggling a club follows its canonical row, and unfollows it under every league")
    func siblingToggle() throws {
        let catalogs = try europeanCatalogs()
        let bayern = try #require(TeamSearch.localClubs(in: catalogs, query: "bayern", current: nil).first).canonical
        let store = try makeStore(following: ["football/nfl:12"])

        store.toggleClub(bayern)
        #expect(store.teamIDs == ["football/nfl:12", "soccer/ger.1:132"])
        store.toggleClub(bayern)
        #expect(store.teamIDs == ["football/nfl:12"])

        // Followed under both before the change: one tap clears both.
        let both = try makeStore(following: ["soccer/uefa.champions:132", "football/nfl:12", "soccer/ger.1:132"])
        both.toggleClub(bayern)
        #expect(both.teamIDs == ["football/nfl:12"])
    }

    @Test("7. The widget's search offers one entity per club")
    func widgetEntities() throws {
        // The widget searches the favorites' leagues first: the UCL here.
        let catalogs = try europeanCatalogs()
        let matches = (catalogs[.championsLeague] ?? []) + (catalogs[.bundesliga] ?? [])
        let clubs = TeamSearch.canonicalClubs(from: matches.filter { TeamSearch.matches($0, query: "bayern") })
        #expect(clubs.map { $0.id } == ["soccer/ger.1:132"])
    }

    @Test("8. A league's own page keeps every team: the UCL catalog is not grouped")
    func leaguePagesUnchanged() throws {
        let catalogs = try europeanCatalogs()
        let ucl = try #require(catalogs[.championsLeague])
        #expect(ucl.count == 15)
        #expect(ucl.contains { $0.id == "soccer/uefa.champions:132" })
        #expect(ucl.allSatisfy { $0.league == .championsLeague })
        #expect(catalogs[.bundesliga]?.count == 15)
    }

    @Test("9. The same ESPN id in two sports, or the same name under two ids, is two clubs")
    func neverMergedAcrossSports() {
        let soccer12 = team(.mls, "12", displayName: "Kansas City Chiefs", shortName: "Chiefs", abbreviation: "KC", location: "Kansas City")
        let hockey12 = team(.nhl, "12", displayName: "Twelve", shortName: "Twelve", abbreviation: "TW", location: "")
        let clubs = TeamSearch.clubGroups(from: [chiefs, soccer12, hockey12, sporting])
        #expect(clubs.map { $0.id } == [chiefs.id, soccer12.id, hockey12.id, sporting.id])
        #expect(TeamSearch.clubCount([chiefs, soccer12, hockey12]) == 3)
    }

    @Test("10. Clubs keep the order they first appear in: the league on screen first")
    func firstOccurrenceOrder() throws {
        let catalogs = try europeanCatalogs()
        let onUCL = TeamSearch.localClubs(in: catalogs, query: "borussia", current: .championsLeague)
        // Dortmund comes first from the UCL page, but is still the Bundesliga's.
        #expect(onUCL.map { $0.id } == ["soccer/ger.1:124", "soccer/ger.1:268"])
        #expect(onUCL.first?.otherLeagues == [LeagueID.championsLeague])
        let onBundesliga = TeamSearch.localClubs(in: catalogs, query: "borussia", current: .bundesliga)
        #expect(Set(onBundesliga.map { $0.id }) == Set(onUCL.map { $0.id }))
    }

    @Test("11. A club followed under two leagues counts once")
    func followCount() throws {
        let catalogs = try europeanCatalogs()
        let bayern = try #require(catalogs[.bundesliga]?.first { $0.espnID == "132" })
        let bayernUCL = try #require(catalogs[.championsLeague]?.first { $0.espnID == "132" })
        let aek = try #require(catalogs[.championsLeague]?.first { $0.espnID == "887" })
        #expect(TeamSearch.clubCount([bayern, bayernUCL, aek]) == 2)
        #expect(TeamSearch.clubCount([chiefs, sporting]) == 2)
        #expect(TeamSearch.clubCount([]) == 0)
    }

    @Test("12. The domestic league is canonical whatever the order; cups are listed last")
    func canonicalChoice() {
        let ucl = team(.championsLeague, "500", displayName: "Club", shortName: "Club", abbreviation: "CLB", location: "")
        let europa = team(.soccer("uefa.europa"), "500", displayName: "Club", shortName: "Club", abbreviation: "CLB", location: "")
        let ligue1 = team(.ligue1, "500", displayName: "Club", shortName: "Club", abbreviation: "CLB", location: "")
        let laLiga = team(.laLiga, "500", displayName: "Club", shortName: "Club", abbreviation: "CLB", location: "")
        #expect(LeagueID.championsLeague.isCup)
        #expect(LeagueID.soccer("uefa.europa").isCup)
        #expect(!LeagueID.bundesliga.isCup && !LeagueID.nfl.isCup)

        #expect(TeamSearch.canonicalClubs(from: [ucl, ligue1]).map { $0.id } == [ligue1.id])
        #expect(TeamSearch.canonicalClubs(from: [ligue1, ucl]).map { $0.id } == [ligue1.id])
        // Two leagues, which cannot happen today: the shorter path, then
        // the first alphabetically, never the order loaded.
        let pair = TeamSearch.clubGroups(from: [ucl, ligue1, laLiga])
        #expect(pair.map { $0.id } == [laLiga.id])
        #expect(TeamSearch.clubGroups(from: [ucl, laLiga, ligue1]).map { $0.id } == [laLiga.id])
        // Leagues before cups; leagues the picker does not list are left out.
        #expect(pair.first?.otherLeagues == [LeagueID.ligue1, .championsLeague])
        #expect(TeamSearch.clubGroups(from: [europa, laLiga]).first?.otherLeagues.isEmpty == true)
        // Only cups: the same rule picks one of them; the UCL is still listed.
        let cups = TeamSearch.clubGroups(from: [ucl, europa])
        #expect(cups.map { $0.id } == [europa.id])
        #expect(cups.first?.otherLeagues == [LeagueID.championsLeague])
    }
}
