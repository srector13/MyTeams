//
//  DownloadAthleteData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

struct BasketballPlayerStats: Identifiable {
    var id = UUID()
    var gamesPlayed: Int
    var avgMinutes: Float
    //var avgFieldGoalsMadeDashavgFieldGoalsAttempted
    var fieldGoalPct: Float
    //var avgThreePointFieldGoalsMadeDashavgThreePointFieldGoalsAttempted
    var threePointFieldGoalPct: Float
    //var freeThrowsMadeDashAttemptedPerGame
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
}

struct SoccerPlayerStats: Identifiable {
    var id = UUID()
    var starts: String
    var saves: String
    var cleanSheets: String
    var goalsConceded: String
}

struct BaseballPlayerStats: Identifiable {
    var id = UUID()
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
    
}


func downloadBasketballPlayerStats(playerID: String, completion: @escaping (BasketballPlayerStats) -> Void) {
    var returnStats = BasketballPlayerStats(gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0, freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0, avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0, avgTurnovers: 0, avgPoints: 0)
    
    let requestURL = "https://site.web.api.espn.com/apis/common/v3/sports/basketball/mens-college-basketball/athletes/" + playerID + "/splits"
    
    OperationQueue().addOperation { AF.request(requestURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            let tempGamesPlayed = json["splitCategories",0,"splits",0,"stats",0].intValue + json["splitCategories",0,"splits",1,"stats",0].intValue
            let tempAvgMinutes = (json["splitCategories",0,"splits",0,"stats",1].floatValue + json["splitCategories",0,"splits",1,"stats",1].floatValue)/2
            //var avgFieldGoalsMadeDashavgFieldGoalsAttempted
            let tempFieldGoalPct = (json["splitCategories",0,"splits",0,"stats",3].floatValue + json["splitCategories",0,"splits",1,"stats",3].floatValue)/2
            //var avgThreePointFieldGoalsMadeDashavgThreePointFieldGoalsAttempted
            let tempThreePointFieldGoalPct = (json["splitCategories",0,"splits",0,"stats",5].floatValue + json["splitCategories",0,"splits",1,"stats",5].floatValue)/2
            //var freeThrowsMadeDashAttemptedPerGame
            let tempFreeThrowPct = (json["splitCategories",0,"splits",0,"stats",7].floatValue + json["splitCategories",0,"splits",1,"stats",7].floatValue)/2
            let tempAvgOffensiveRebounds = (json["splitCategories",0,"splits",0,"stats",8].floatValue + json["splitCategories",0,"splits",1,"stats",8].floatValue)/2
            let tempAvgDefensiveRebounds = (json["splitCategories",0,"splits",0,"stats",9].floatValue + json["splitCategories",0,"splits",1,"stats",9].floatValue)/2
            let tempAvgRebounds = (json["splitCategories",0,"splits",0,"stats",10].floatValue + json["splitCategories",0,"splits",1,"stats",10].floatValue)/2
            let tempAvgAssists = (json["splitCategories",0,"splits",0,"stats",11].floatValue + json["splitCategories",0,"splits",1,"stats",11].floatValue)/2
            let tempAvgBlocks = (json["splitCategories",0,"splits",0,"stats",12].floatValue + json["splitCategories",0,"splits",1,"stats",12].floatValue)/2
            let tempAvgSteals = (json["splitCategories",0,"splits",0,"stats",13].floatValue + json["splitCategories",0,"splits",1,"stats",13].floatValue)/2
            let tempAvgFouls = (json["splitCategories",0,"splits",0,"stats",14].floatValue + json["splitCategories",0,"splits",1,"stats",14].floatValue)/2
            let tempAvgTurnovers = (json["splitCategories",0,"splits",0,"stats",15].floatValue + json["splitCategories",0,"splits",1,"stats",15].floatValue)/2
            let tempAvgPoints = (json["splitCategories",0,"splits",0,"stats",16].floatValue + json["splitCategories",0,"splits",1,"stats",16].floatValue)/2
            
            returnStats = BasketballPlayerStats(gamesPlayed: tempGamesPlayed, avgMinutes: tempAvgMinutes, fieldGoalPct: tempFieldGoalPct, threePointFieldGoalPct: tempThreePointFieldGoalPct, freeThrowPct: tempFreeThrowPct, avgOffensiveRebounds: tempAvgOffensiveRebounds, avgDefensiveRebounds: tempAvgDefensiveRebounds, avgRebounds: tempAvgRebounds, avgAssists: tempAvgAssists, avgBlocks: tempAvgBlocks, avgSteals: tempAvgSteals, avgFouls: tempAvgFouls, avgTurnovers: tempAvgTurnovers, avgPoints: tempAvgPoints)
        case .failure(let error):
            print(error)
        }
        OperationQueue.main.addOperation {
            completion(returnStats)
        }
        }
    }
}

func downloadBaseballPlayerStats(playerID: String, playerPosition: String, completion: @escaping (BaseballPlayerStats) -> Void) {
    var returnStats = BaseballPlayerStats(EarnedRunAverage: 0, wins: 0, losses: 0, saves: 0, saveOpportunities: 0, gamesPlayed: 0, gamesStarted: 0, completeGames: 0, innings: 0.0, hits: 0, runs: 0, earnedRuns: 0, homeRuns: 0, walks: 0, strikeouts: 0, opponentAvg: 0.0, AtBats: 0, Runs: 0, Hits: 0, Doubles: 0, Triples: 0, HomeRuns: 0, RBIs: 0.0, Walks: 0, HitByPitch: 0, Strikeouts: 0, StolenBases: 0, CaughtStealing: 0, Avg: 0.0, OnBasePct: 0.0, SlugAvg: 0.0, OPS: 0.0)
    
    let requestURL = "https://site.web.api.espn.com/apis/common/v3/sports/baseball/mlb/athletes/" + playerID + "/splits"
    print(requestURL)
    
    OperationQueue().addOperation { AF.request(requestURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            var earnedRunAverage = 0
            var wins = 0
            var losses = 0
            var saves = 0
            var saveOpportunities = 0
            var gamesPlayed = 0
            var gamesStarted = 0
            var completeGames = 0
            var innings: Float = 0.0
            var hits = 0
            var runs = 0
            var earnedRuns = 0
            var homeRuns = 0
            var walks = 0
            var strikeouts = 0
            var opponentAvg: Float = 0.0
            
            var tempAtBats = 0
            var tempRuns = 0
            var tempHits = 0
            var tempDoubles = 0
            var tempTriples = 0
            var tempHomeRuns = 0
            var tempRBIs: Float = 0.0
            var tempWalks = 0
            var tempHitByPitch = 0
            var tempStrikeouts = 0
            var tempStolenBases = 0
            var tempCaughtStealing = 0
            var tempAvg: Float = 0.0
            var tempOnBasePct: Float = 0.0
            var tempSlugAvg: Float = 0.0
            var tempOPS: Float = 0.0
            
            
            
            
            if(playerPosition.contains("Pitcher")) {
                earnedRunAverage = json["splitCategories",0,"splits",0,"stats",0].intValue
                wins = json["splitCategories",0,"splits",0,"stats",1].intValue
                losses = json["splitCategories",0,"splits",0,"stats",2].intValue
                saves = json["splitCategories",0,"splits",0,"stats",3].intValue
                saveOpportunities = json["splitCategories",0,"splits",0,"stats",4].intValue
                gamesPlayed = json["splitCategories",0,"splits",0,"stats",5].intValue
                gamesStarted = json["splitCategories",0,"splits",0,"stats",6].intValue
                completeGames = json["splitCategories",0,"splits",0,"stats",7].intValue
                innings = json["splitCategories",0,"splits",0,"stats",8].floatValue
                hits = json["splitCategories",0,"splits",0,"stats",9].intValue
                runs = json["splitCategories",0,"splits",0,"stats",10].intValue
                earnedRuns = json["splitCategories",0,"splits",0,"stats",11].intValue
                homeRuns = json["splitCategories",0,"splits",0,"stats",12].intValue
                walks = json["splitCategories",0,"splits",0,"stats",13].intValue
                strikeouts = json["splitCategories",0,"splits",0,"stats",14].intValue
                opponentAvg = json["splitCategories",0,"splits",0,"stats",15].floatValue
            } else {
                tempAtBats = json["splitCategories",0,"splits",0,"stats",0].intValue
                tempRuns = json["splitCategories",0,"splits",0,"stats",1].intValue
                tempHits = json["splitCategories",0,"splits",0,"stats",2].intValue
                tempDoubles = json["splitCategories",0,"splits",0,"stats",3].intValue
                tempTriples = json["splitCategories",0,"splits",0,"stats",4].intValue
                tempHomeRuns = json["splitCategories",0,"splits",0,"stats",5].intValue
                tempRBIs = json["splitCategories",0,"splits",0,"stats",6].floatValue
                tempWalks = json["splitCategories",0,"splits",0,"stats",7].intValue
                tempHitByPitch = json["splitCategories",0,"splits",0,"stats",8].intValue
                tempStrikeouts = json["splitCategories",0,"splits",0,"stats",9].intValue
                tempStolenBases = json["splitCategories",0,"splits",0,"stats",10].intValue
                tempCaughtStealing = json["splitCategories",0,"splits",0,"stats",11].intValue
                tempAvg = json["splitCategories",0,"splits",0,"stats",12].floatValue
                tempOnBasePct = json["splitCategories",0,"splits",0,"stats",13].floatValue
                tempSlugAvg = json["splitCategories",0,"splits",0,"stats",14].floatValue
                tempOPS = json["splitCategories",0,"splits",0,"stats",15].floatValue
            }
            
            returnStats = BaseballPlayerStats(EarnedRunAverage: earnedRunAverage, wins: wins, losses: losses, saves: saves, saveOpportunities: saveOpportunities, gamesPlayed: gamesPlayed, gamesStarted: gamesStarted, completeGames: completeGames, innings: innings, hits: hits, runs: runs, earnedRuns: earnedRuns, homeRuns: homeRuns, walks: walks, strikeouts: strikeouts, opponentAvg: opponentAvg, AtBats: tempAtBats, Runs: tempRuns, Hits: tempHits, Doubles: tempDoubles, Triples: tempTriples, HomeRuns: tempHomeRuns, RBIs: tempRBIs, Walks: tempWalks, HitByPitch: tempHitByPitch, Strikeouts: tempStrikeouts, StolenBases: tempStolenBases, CaughtStealing: tempCaughtStealing, Avg: tempAvg, OnBasePct: tempOnBasePct, SlugAvg: tempSlugAvg, OPS: tempOPS)
            
            print(returnStats)
        case .failure(let error):
            print(error)
        }
        OperationQueue.main.addOperation {
            completion(returnStats)
        }
        }
    }
}

func downloadSoccerPlayerStats(playerID: String, playerPosition: String, completion: @escaping (SoccerPlayerStats) -> Void) {
    var returnStats = SoccerPlayerStats(starts: "", saves: "", cleanSheets: "", goalsConceded: "")
    
    let requestURL = "https://site.web.api.espn.com/apis/common/v3/sports/soccer/usa.1/athletes/" + playerID
    print(requestURL)
    
    OperationQueue().addOperation { AF.request(requestURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            var starts = "N/A"
            var saves = "N/A"
            var cleanSheets = "N/A"
            var goalsConceded = "N/A"
            
            
            
            
            if(playerPosition.contains("Goalkeeper")) {
                starts = json["athlete","statsSummary","statistics",0,"value"].stringValue
                saves = json["athlete","statsSummary","statistics",1,"value"].stringValue
                cleanSheets = json["athlete","statsSummary","statistics",2,"value"].stringValue
                goalsConceded = json["athlete","statsSummary","statistics",3,"value"].stringValue
            } else {
                    //Do Things Here
            }
            
            returnStats = SoccerPlayerStats(starts: starts, saves: saves, cleanSheets: cleanSheets, goalsConceded: goalsConceded)
            
            print(returnStats)
        case .failure(let error):
            print(error)
        }
        OperationQueue.main.addOperation {
            completion(returnStats)
        }
        }
    }
}
