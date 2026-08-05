//
//  DownloadAthleteData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct BasketballPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var gamesPlayed: Int
    var avgMinutes: Float
    var fieldGoalPct: Float
    var threePointFieldGoalPct: Float
    var freeThrowPct: Float
    var avgOffensiveRebounds: Float
    var avgDefensiveRebounds: Float
    var avgRebounds: Float
    var avgAssists: Float
    var avgBlocks: Float
    var avgSteals: Float
    var avgFouls: Float
    var avgTurnovers: Float
    var avgPoints: Float

    /// The value shown before a player's splits have loaded.
    static let empty = BasketballPlayerStats(
        gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0,
        freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0,
        avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0,
        avgTurnovers: 0, avgPoints: 0
    )
}

struct SoccerPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()
    var starts: String
    var saves: String
    var cleanSheets: String
    var goalsConceded: String

    static let empty = SoccerPlayerStats(
        starts: "", saves: "", cleanSheets: "", goalsConceded: ""
    )
}

struct BaseballPlayerStats: Identifiable, Hashable, Sendable {
    var id = UUID()

    // Pitching
    var EarnedRunAverage: Int
    var wins: Int
    var losses: Int
    var saves: Int
    var saveOpportunities: Int
    var gamesPlayed: Int
    var gamesStarted: Int
    var completeGames: Int
    var innings: Float
    var hits: Int
    var runs: Int
    var earnedRuns: Int
    var homeRuns: Int
    var walks: Int
    var strikeouts: Int
    var opponentAvg: Float

    // Batting
    var AtBats: Int
    var Runs: Int
    var Hits: Int
    var Doubles: Int
    var Triples: Int
    var HomeRuns: Int
    var RBIs: Float
    var Walks: Int
    var HitByPitch: Int
    var Strikeouts: Int
    var StolenBases: Int
    var CaughtStealing: Int
    var Avg: Float
    var OnBasePct: Float
    var SlugAvg: Float
    var OPS: Float

    /// The value shown before a player's splits have loaded, and the base the
    /// loader fills in either the pitching or the batting half of.
    static let empty = BaseballPlayerStats(
        EarnedRunAverage: 0, wins: 0, losses: 0, saves: 0, saveOpportunities: 0,
        gamesPlayed: 0, gamesStarted: 0, completeGames: 0, innings: 0, hits: 0,
        runs: 0, earnedRuns: 0, homeRuns: 0, walks: 0, strikeouts: 0, opponentAvg: 0,
        AtBats: 0, Runs: 0, Hits: 0, Doubles: 0, Triples: 0, HomeRuns: 0, RBIs: 0,
        Walks: 0, HitByPitch: 0, Strikeouts: 0, StolenBases: 0, CaughtStealing: 0,
        Avg: 0, OnBasePct: 0, SlugAvg: 0, OPS: 0
    )
}

/// Loads a Kansas player's season averages.
///
/// The splits feed reports home and away separately, so a rate stat is the
/// mean of the two and games played is their sum. Values are addressed by
/// position because the feed lists them in a fixed order with no keys.
func downloadBasketballPlayerStats(playerID: String) async -> BasketballPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/basketball/mens-college-basketball/athletes/\(playerID)/splits"
    )

    let splits = json["splitCategories"][0]["splits"]

    /// The mean of the home and away values at `index`.
    func average(_ index: Int) -> Float {
        (splits[0]["stats"][index].floatValue + splits[1]["stats"][index].floatValue) / 2
    }

    return BasketballPlayerStats(
        gamesPlayed: splits[0]["stats"][0].intValue + splits[1]["stats"][0].intValue,
        avgMinutes: average(1),
        fieldGoalPct: average(3),
        threePointFieldGoalPct: average(5),
        freeThrowPct: average(7),
        avgOffensiveRebounds: average(8),
        avgDefensiveRebounds: average(9),
        avgRebounds: average(10),
        avgAssists: average(11),
        avgBlocks: average(12),
        avgSteals: average(13),
        avgFouls: average(14),
        avgTurnovers: average(15),
        avgPoints: average(16)
    )
}

/// Loads a Royals player's season totals.
///
/// Pitchers and position players get different stat lines from the feed, in
/// the same positions, so the player's position decides which half of
/// `BaseballPlayerStats` is filled in.
func downloadBaseballPlayerStats(
    playerID: String,
    playerPosition: String
) async -> BaseballPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/baseball/mlb/athletes/\(playerID)/splits"
    )

    let stats = json["splitCategories"][0]["splits"][0]["stats"]
    var result = BaseballPlayerStats.empty

    if playerPosition.contains("Pitcher") {
        result.EarnedRunAverage = stats[0].intValue
        result.wins = stats[1].intValue
        result.losses = stats[2].intValue
        result.saves = stats[3].intValue
        result.saveOpportunities = stats[4].intValue
        result.gamesPlayed = stats[5].intValue
        result.gamesStarted = stats[6].intValue
        result.completeGames = stats[7].intValue
        result.innings = stats[8].floatValue
        result.hits = stats[9].intValue
        result.runs = stats[10].intValue
        result.earnedRuns = stats[11].intValue
        result.homeRuns = stats[12].intValue
        result.walks = stats[13].intValue
        result.strikeouts = stats[14].intValue
        result.opponentAvg = stats[15].floatValue
    } else {
        result.AtBats = stats[0].intValue
        result.Runs = stats[1].intValue
        result.Hits = stats[2].intValue
        result.Doubles = stats[3].intValue
        result.Triples = stats[4].intValue
        result.HomeRuns = stats[5].intValue
        result.RBIs = stats[6].floatValue
        result.Walks = stats[7].intValue
        result.HitByPitch = stats[8].intValue
        result.Strikeouts = stats[9].intValue
        result.StolenBases = stats[10].intValue
        result.CaughtStealing = stats[11].intValue
        result.Avg = stats[12].floatValue
        result.OnBasePct = stats[13].floatValue
        result.SlugAvg = stats[14].floatValue
        result.OPS = stats[15].floatValue
    }

    return result
}

/// Loads a Sporting Kansas City player's headline statistics.
///
/// Only the keeper line is filled in; outfield players show "N/A", as they
/// always have.
func downloadSoccerPlayerStats(
    playerID: String,
    playerPosition: String
) async -> SoccerPlayerStats {
    let json = await HTTPClient.json(
        from: "https://site.web.api.espn.com/apis/common/v3/sports/soccer/usa.1/athletes/\(playerID)"
    )

    guard playerPosition.contains("Goalkeeper") else {
        return SoccerPlayerStats(
            starts: "N/A", saves: "N/A", cleanSheets: "N/A", goalsConceded: "N/A"
        )
    }

    let summary = json["athlete"]["statsSummary"]["statistics"]

    return SoccerPlayerStats(
        starts: summary[0]["value"].stringValue,
        saves: summary[1]["value"].stringValue,
        cleanSheets: summary[2]["value"].stringValue,
        goalsConceded: summary[3]["value"].stringValue
    )
}
