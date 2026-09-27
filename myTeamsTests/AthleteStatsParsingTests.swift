//
//  AthleteStatsParsingTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// Covers the player-detail readers for the athlete splits feeds.
///
/// The fixtures mirror the splits documents' shape: each split row carries a
/// positional `stats` array of display strings with no keys, so the readers
/// address values by index.
@Suite("Athlete stats parsing")
struct AthleteStatsParsingTests {
    // MARK: - Baseball

    /// An abridged MLB pitcher splits document. The first value is the ERA,
    /// which the feed publishes as a decimal string.
    static let pitcher = JSON(data: Data("""
    {
      "splitCategories": [{"splits": [{
        "displayName": "All Splits",
        "stats": ["3.45", "12", "8", "0", "0", "31", "31", "1", "180.2",
                  "160", "75", "69", "20", "50", "190", ".231"]
      }]}]
    }
    """.utf8))

    @Test("A pitcher's ERA keeps its decimals")
    func pitcherEarnedRunAverage() {
        let stats = parseBaseballPlayerStats(from: Self.pitcher, playerPosition: "Starting Pitcher")
        // An Int field truncated this to 3.
        #expect(abs(stats.EarnedRunAverage - 3.45) < 0.001)
        #expect(String(format: "%.2f", stats.EarnedRunAverage) == "3.45")
        #expect(stats.wins == 12)
        #expect(stats.losses == 8)
        #expect(stats.earnedRuns == 69)
        #expect(abs(stats.opponentAvg - 0.231) < 0.001)
    }

    @Test("A sub-one ERA does not read as zero")
    func pitcherLowEarnedRunAverage() {
        let reliever = JSON(data: Data("""
        {"splitCategories": [{"splits": [{"stats": ["0.87", "3", "1"]}]}]}
        """.utf8))
        let stats = parseBaseballPlayerStats(from: reliever, playerPosition: "Relief Pitcher")
        #expect(String(format: "%.2f", stats.EarnedRunAverage) == "0.87")
    }

    // MARK: - Basketball

    /// An abridged NCAA splits document: 10 home games at 20.0 points, 5 away
    /// games at 11.0. Index 0 is games played, 1 minutes, 10 rebounds and
    /// 16 points.
    static let basketball = JSON(data: Data("""
    {
      "splitCategories": [{"splits": [
        {"displayName": "Home",
         "stats": ["10", "30.0", "0", "45.0", "0", "35.0", "0", "70.0",
                   "2.0", "4.0", "6.0", "3.0", "1.0", "1.0", "2.0", "2.0", "20.0"]},
        {"displayName": "Away",
         "stats": ["5", "24.0", "0", "42.0", "0", "30.0", "0", "80.0",
                   "1.0", "2.0", "3.0", "1.5", "0.5", "0.5", "1.0", "1.0", "11.0"]}
      ]}]
    }
    """.utf8))

    @Test("Season averages weight each split by its games played")
    func basketballWeightedAverages() {
        let stats = parseBasketballPlayerStats(from: Self.basketball)
        #expect(stats.gamesPlayed == 15)
        // (20 * 10 + 11 * 5) / 15 = 17.0; the plain mean would be 15.5.
        #expect(abs(stats.avgPoints - 17.0) < 0.001)
        // (30 * 10 + 24 * 5) / 15 = 28.0
        #expect(abs(stats.avgMinutes - 28.0) < 0.001)
        // (6 * 10 + 3 * 5) / 15 = 5.0
        #expect(abs(stats.avgRebounds - 5.0) < 0.001)
    }

    @Test("A player with no games in either split averages without dividing by zero")
    func basketballNoGames() {
        let empty = JSON(data: Data("""
        {"splitCategories": [{"splits": [
          {"stats": ["0", "0.0"]},
          {"stats": ["0", "0.0"]}
        ]}]}
        """.utf8))
        let stats = parseBasketballPlayerStats(from: empty)
        #expect(stats.gamesPlayed == 0)
        #expect(stats.avgPoints == 0)
        #expect(!stats.avgMinutes.isNaN)

        // A failed fetch parses to zeros too.
        #expect(parseBasketballPlayerStats(from: JSON(data: Data())).avgPoints == 0)
    }
}
