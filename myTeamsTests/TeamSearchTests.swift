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
