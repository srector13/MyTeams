//
//  TeamCatalogTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The four seeded teams, looked up in the bundled catalog, so tests can
/// keep writing `team: .jayhawks`.
extension TeamRef {
    static var jayhawks: TeamRef { TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305") }
    static var chiefs: TeamRef { TeamCatalog.seeded(league: .nfl, espnID: "12") }
    static var royals: TeamRef { TeamCatalog.seeded(league: .mlb, espnID: "7") }
    static var sporting: TeamRef { TeamCatalog.seeded(league: .mls, espnID: "186") }
}

@Suite("Team catalog")
struct TeamCatalogTests {
    @Test("The bundled catalog seeds the four teams, in tab order")
    func seededTeams() {
        #expect(TeamCatalog.all.map(\.id) == [
            "basketball/mens-college-basketball:2305",
            "football/nfl:12",
            "baseball/mlb:7",
            "soccer/usa.1:186",
        ])
        #expect(FavoriteTeams.teams == TeamCatalog.all)
    }

    // The literals below are the retired `Team` enum's computed values
    // (Sport.swift before the TeamRef refactor): what the four teams have
    // always displayed. A catalog edit that changes one fails here.
    @Test("Catalog display fields match the retired Team enum")
    func legacyDisplayValues() {
        let expected: [(TeamRef, display: String, short: String, hex: String, asset: String)] = [
            (.jayhawks, "Kansas Jayhawks", "Jayhawks", "0051BA", "jayhawk"),  // (0, 81, 186)
            (.chiefs, "Kansas City Chiefs", "Chiefs", "E31837", "chiefs"),  // (227, 24, 55)
            (.royals, "Kansas City Royals", "Royals", "004687", "royals"),  // (0, 70, 135)
            (.sporting, "Sporting Kansas City", "Sporting", "002A5C", "sporting"),  // (0, 42, 92)
        ]
        for (team, display, short, hex, asset) in expected {
            #expect(team.displayName == display)
            #expect(team.shortName == short)
            #expect(team.colorHex == hex)
            #expect(team.logoAsset == asset)
        }
    }

    @Test("ESPN URLs are the ones the enum and the hard-coded loaders built")
    func urls() {
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        #expect(TeamRef.jayhawks.scheduleURL == "\(site)/basketball/mens-college-basketball/teams/2305/schedule")
        #expect(TeamRef.chiefs.scheduleURL == "\(site)/football/nfl/teams/12/schedule")
        #expect(TeamRef.royals.summaryURL(gameID: "401817094") == "\(site)/baseball/mlb/summary?event=401817094")
        #expect(TeamRef.sporting.rosterURL == "\(site)/soccer/usa.1/teams/186/roster")
        #expect(TeamRef.jayhawks.rosterURL == "\(site)/basketball/mens-college-basketball/teams/2305/roster")

        let common = "https://site.web.api.espn.com/apis/common/v3/sports"
        #expect(LeagueID.nfl.athleteSplitsURL(athleteID: "4912218") == "\(common)/football/nfl/athletes/4912218/splits")
        #expect(LeagueID.mls.athleteURL(athleteID: "249729") == "\(common)/soccer/usa.1/athletes/249729")
    }

    @Test("League paths round-trip through LeagueID")
    func leaguePaths() throws {
        #expect(LeagueID(path: "football/nfl") == .nfl)
        #expect(LeagueID(path: "soccer/usa.1") == .mls)
        #expect(LeagueID(path: "nfl") == nil)
        #expect(LeagueID(path: "football/") == nil)
        #expect(LeagueID(path: "a/b/c") == nil)

        // Encoded as the bare path string, as teams.json writes it.
        let decoded = try JSONDecoder().decode([LeagueID].self, from: Data(#"["baseball/mlb"]"#.utf8))
        #expect(decoded == [.mlb])
        let encoded = try JSONEncoder().encode([LeagueID.mensCollegeBasketball])
        #expect(try JSONDecoder().decode([String].self, from: encoded) == ["basketball/mens-college-basketball"])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LeagueID].self, from: Data(#"["mlb"]"#.utf8))
        }
    }

    @Test("A TeamRef survives an encode/decode round trip")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(TeamCatalog.all)
        #expect(try JSONDecoder().decode([TeamRef].self, from: data) == TeamCatalog.all)
    }

    @Test("Retired Team raw values migrate to catalog teams")
    func legacyMigration() {
        #expect(TeamCatalog.team(legacyID: "jayhawk") == .jayhawks)
        #expect(TeamCatalog.team(legacyID: "chiefs") == .chiefs)
        #expect(TeamCatalog.team(legacyID: "royals") == .royals)
        #expect(TeamCatalog.team(legacyID: "sporting") == .sporting)
        #expect(TeamCatalog.team(legacyID: "jayhawks") == nil)  // the case name was never persisted

        // Stored favorites may mix old and new identifiers; order is kept,
        // unknown and repeated entries are dropped.
        let resolved = FavoriteTeams.resolve(storedIDs: [
            "royals", "soccer/usa.1:186", "unknown", "baseball/mlb:7", "jayhawk",
        ])
        #expect(resolved == [.royals, .sporting, .jayhawks])
    }

    @Test("League descriptors carry the rules the team pages used to hard-code")
    func leagueDescriptors() {
        #expect(TeamRef.jayhawks.league.descriptor.kind == .basketball)
        #expect(TeamRef.chiefs.league.descriptor.kind == .football)
        #expect(TeamRef.royals.league.descriptor.kind == .baseball)
        #expect(TeamRef.sporting.league.descriptor.kind == .soccer)

        // RoyalsHome passed countsAbandonedGamesAsLosses: true; SportingHome
        // passed usesDateForNextGame: true; the others passed neither.
        #expect(TeamRef.royals.league.descriptor.recordRule == RecordRule(countsAbandonedGamesAsLosses: true))
        #expect(TeamRef.sporting.league.descriptor.recordRule == RecordRule(usesDateForNextGame: true))
        #expect(TeamRef.jayhawks.league.descriptor.recordRule == RecordRule())
        #expect(TeamRef.chiefs.league.descriptor.recordRule == RecordRule())

        #expect(TeamRef.chiefs.league.descriptor.rosterShape == .grouped)
        #expect(TeamRef.royals.league.descriptor.rosterShape == .grouped)
        #expect(TeamRef.jayhawks.league.descriptor.rosterShape == .flat)
        #expect(TeamRef.sporting.league.descriptor.rosterShape == .flat)

        // Every period label getPeriod produced for its team strings.
        #expect(TeamRef.chiefs.periodName("1") == "1st Quarter")
        #expect(TeamRef.chiefs.periodName("3") == "3rd Quarter")
        #expect(TeamRef.chiefs.periodName("4") == "4th Quarter")
        #expect(TeamRef.jayhawks.periodName("2") == "2nd Half")
        #expect(TeamRef.sporting.periodName("1") == "1st Half")
        #expect(TeamRef.royals.periodName("1") == "")

        // An unknown league still gets a descriptor, keyed on its sport.
        let nhl = LeagueID(sport: "hockey", league: "nhl")
        #expect(nhl.descriptor.kind == .other)
        #expect(LeagueID(sport: "basketball", league: "nba").descriptor.kind == .basketball)
        #expect(nhl.descriptor.periodName("1") == "")
    }

    // The literals below are what the per-team home views and schedule cards
    // hard-coded before TeamHomeView: NewsFeed's four constants, the Chiefs
    // card's "Tie" and score-first live state, and each page's filter menu.
    @Test("Team and league data carry what the per-team views hard-coded")
    func formerViewConfiguration() {
        #expect(TeamRef.jayhawks.newsQuery == "q=+jayhawks+basketball&qInTitle=kansas&domains=espn.com,bleacherreport.com,foxsport.com")
        #expect(TeamRef.chiefs.newsQuery == "qInTitle=+chiefs&domains=espn.com,bleacherreport.com,foxsport.com,nfl.com")
        #expect(TeamRef.royals.newsQuery == "q=+royals+kansas+city&domains=espn.com,bleacherreport.com,foxsport.com")
        #expect(TeamRef.sporting.newsQuery == "q=+sporting+kc+mls")

        let nfl = TeamRef.chiefs.league.descriptor
        #expect(nfl.drawLabel == "Tie")
        #expect(nfl.liveCardStyle == .scoreFirst)
        for team in [TeamRef.jayhawks, .royals, .sporting] {
            #expect(team.league.descriptor.drawLabel == "Draw")
            #expect(team.league.descriptor.liveCardStyle == .periodFirst)
        }

        #expect(TeamRef.sporting.league.descriptor.venueBackdropAsset == "soccerField")
        #expect(TeamRef.chiefs.league.descriptor.venueBackdropAsset == nil)

        // ChiefsHome: a submenu per unit, each opening with the whole unit.
        guard case .menu(let title, let offense) = nfl.rosterFilters[1] else {
            Issue.record("NFL filters should open with unit submenus")
            return
        }
        #expect(title == "Offense")
        #expect(offense.first == RosterFilter(label: "All", unit: "offense"))
        #expect(offense.contains(RosterFilter(label: "Tackle", unit: "offense", position: "Offensive Tackle")))
        #expect(nfl.rosterFilters.count == 3)

        // JayhawksHome, RoyalsHome, SportingHome: flat position lists.
        #expect(TeamRef.jayhawks.league.descriptor.rosterFilters == [
            .filter(RosterFilter(label: "Forwards", position: "Forward")),
            .filter(RosterFilter(label: "Guards", position: "Guard")),
        ])
        #expect(TeamRef.royals.league.descriptor.rosterFilters.count == 8)
        #expect(TeamRef.sporting.league.descriptor.rosterFilters == [
            .filter(RosterFilter(label: "Goalkeeper", position: "Goalkeeper")),
            .filter(RosterFilter(label: "Defense", position: "Defender")),
            .filter(RosterFilter(label: "Midfield", position: "Midfielder")),
            .filter(RosterFilter(label: "Attacker", position: "Forward")),
        ])
    }
}
