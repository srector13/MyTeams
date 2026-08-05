//
//  JSONTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Covers the traversal and coercion rules the ESPN parsers depend on.
///
/// These were written when `JSON` replaced the SwiftyJSON package, to pin the
/// behaviour the parsers had been built against: subscripting that never
/// traps, numbers that read out of display strings, and zero values wherever
/// a feed leaves a field out.
@Suite("JSON")
struct JSONTests {
    /// An abridged ESPN schedule response, carrying the shapes the parsers
    /// actually reach into.
    static let schedule = JSON(data: Data("""
    {
      "events": [{
        "name": "Kansas at Baylor",
        "date": "2021-01-18T23:00Z",
        "competitions": [{
          "id": "401265",
          "venue": {"fullName": "Allen Fieldhouse", "capacity": 16300},
          "status": {
            "displayClock": "12:34",
            "period": 2,
            "type": {"completed": true, "description": "Halftime", "detail": "Final"}
          },
          "broadcasts": [{"media": {"shortName": "ESPN"}}],
          "competitors": [
            {"homeAway": "home", "winner": true,
             "team": {"nickname": "Jayhawks",
                      "logos": [{"href": "a/light.png"}, {"href": "b/dark.png"}]},
             "score": {"displayValue": "78"}},
            {"homeAway": "away", "winner": false,
             "team": {"nickname": "Bears",
                      "logos": [{"href": "c/light.png"}, {"href": "d-dark.png"}]},
             "score": {"displayValue": "64"}}
          ]
        }]
      }],
      "boxscore": {"teams": [
        {"team": {"name": "Jayhawks"},
         "statistics": [{"displayValue": "28-55"}, {"displayValue": "50.9"}]}
      ]},
      "predictor": {"homeTeam": {"gameProjection": 72.5}}
    }
    """.utf8))

    // MARK: - Traversal

    @Test("Nested keys read through chained subscripts")
    func nestedKeys() {
        let event = Self.schedule["events"][0]
        #expect(event["name"].stringValue == "Kansas at Baylor")
        #expect(event["competitions"][0]["venue"]["fullName"].stringValue == "Allen Fieldhouse")
    }

    @Test("A key path reads through mixed string and integer steps")
    func keyPaths() {
        #expect(
            Self.schedule["boxscore", "teams", 0, "team", "name"].stringValue == "Jayhawks"
        )
        #expect(
            Self.schedule["events", 0, "competitions", 0, "broadcasts", 0, "media", "shortName"]
                .stringValue == "ESPN"
        )
    }

    @Test("Iterating an array visits its elements in order")
    func iteratesArrays() {
        let competitors = Self.schedule["events", 0, "competitions", 0, "competitors"]
        let nicknames = competitors.map { _, competitor in
            competitor["team"]["nickname"].stringValue
        }
        #expect(nicknames == ["Jayhawks", "Bears"])
    }

    @Test("Iterating an object yields its keys")
    func iteratesObjects() {
        let keys = Set(Self.schedule.map { key, _ in key })
        #expect(keys == ["events", "boxscore", "predictor"])
    }

    @Test("Iterating a leaf or an absent key yields nothing")
    func iteratesNothing() {
        #expect(Self.schedule["events", 0, "name"].map { _, _ in 1 }.isEmpty)
        #expect(Self.schedule["nope"].map { _, _ in 1 }.isEmpty)
    }

    // MARK: - Coercion

    @Test("Numbers read as numbers, whatever accessor is used")
    func numbers() {
        #expect(Self.schedule["predictor"]["homeTeam"]["gameProjection"].floatValue == 72.5)
        #expect(Self.schedule["events", 0, "competitions", 0, "venue", "capacity"].intValue == 16300)
    }

    @Test("A number renders as a string without a trailing decimal")
    func numberAsString() {
        #expect(Self.schedule["events", 0, "competitions", 0, "status", "period"].stringValue == "2")
        #expect(
            Self.schedule["events", 0, "competitions", 0, "venue", "capacity"].stringValue == "16300"
        )
    }

    @Test("A display string reads as the number it leads with")
    func numbersFromDisplayStrings() {
        let statistics = Self.schedule["boxscore", "teams", 0, "statistics"]
        #expect(statistics[1]["displayValue"].floatValue == 50.9)
        // "28-55" is made-attempted; the parsers read the leading figure.
        #expect(statistics[0]["displayValue"].intValue == 28)
        #expect(statistics[0]["displayValue"].stringValue == "28-55")
    }

    @Test("Booleans and the numbers 0 and 1 stay distinct")
    func booleansAreNotNumbers() {
        let json = JSON(data: Data(#"{"t":true,"f":false,"one":1,"zero":0}"#.utf8))
        #expect(json["t"].boolValue)
        #expect(!json["f"].boolValue)
        // The pitfall this guards: an NSNumber holding 1 bridges to Bool just
        // as readily as one holding true.
        #expect(json["t"].stringValue == "true")
        #expect(json["one"].stringValue == "1")
        #expect(json["zero"].stringValue == "0")
        #expect(json["one"].boolValue)
    }

    @Test("Strings spelling a boolean read as one")
    func booleansFromStrings() {
        let json = JSON(data: Data(#"{"yes":"true","no":"false","other":"maybe"}"#.utf8))
        #expect(json["yes"].boolValue)
        #expect(!json["no"].boolValue)
        #expect(json["other"].bool == nil)
    }

    // MARK: - Missing values

    @Test("An absent key reads as a zero value rather than trapping")
    func missingKeys() {
        #expect(Self.schedule["nope"]["deeper"].stringValue == "")
        #expect(Self.schedule["nope", 0, "deeper"].intValue == 0)
        #expect(Self.schedule["nope"]["x"].floatValue == 0)
        #expect(!Self.schedule["nope"]["x"].boolValue)
        #expect(Self.schedule["nope"].isNull)
    }

    @Test("Indexing past the end, or into the wrong kind of node, reads as absent")
    func mismatchedAccess() {
        #expect(Self.schedule["events"][99]["name"].stringValue == "")
        #expect(Self.schedule["events"]["name"].isNull)
        #expect(Self.schedule["boxscore"][0].isNull)
    }

    @Test("A response that is not JSON parses to null instead of throwing")
    func malformedData() {
        #expect(JSON(data: Data("not json".utf8))["a"]["b"].stringValue == "")
        #expect(JSON(data: Data()).isNull)
    }
}
