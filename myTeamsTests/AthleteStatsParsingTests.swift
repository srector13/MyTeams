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
}
