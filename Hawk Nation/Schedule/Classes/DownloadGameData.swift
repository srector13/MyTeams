//
//  DownloadGameData.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire
import AlamofireImage
import UIKit

//NEED TO CREATE STRUCTS AND FUNCTIONS FOR BASEBALL AND SOCCER//

struct GameInfo: Identifiable, Decodable {
    var id = UUID()
    var venueImage: String
    var city: String
    var state: String
    var capacity: String
    var attendance: String
    var gameColor: String
}

struct BasketballGameTeamStats: Identifiable, Decodable {
    var id = UUID()
    var name: String
    var fieldGoals: String
    var fieldGoalPct: Float
    var threePoints: String
    var threePointPct: Float
    var freeThrows: String
    var freeThrowPct: Float
    var offensiveRebounds: Int
    var defensiveRebounds: Int
    var assists: Int
    var steals: Int
    var blocks: Int
    var turnOvers: Int
    var fouls: Int
    var largestLead: Int
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String
}

// NEED TO FINISH //
struct FootballGameTeamStats: Identifiable, Decodable {
    var id = UUID()
    var name: String
    var yards: Int
    var passingYards: Int
    var rushingYards: Int
    var firstDowns: Int
    var drives: Int
    var score: Int
    var interceptions: Int
    var possesionTime: String
    var completionAttempts: Int
    var opponentScore: Int
    var gameClock: String
}

struct BaseballGameTeamStats: Identifiable, Decodable {
    var id = UUID()
    var name: String
    var yards: Float
    var passingYards: Float
    var rushingYards: Float
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String
}

struct SoccerGameTeamStats: Identifiable, Decodable {
    var id = UUID()
    var name: String
    var yards: Float
    var passingYards: Float
    var rushingYards: Float
    var projection: Float
    var score: Int
    var opponentScore: Int
    var gameClock: String
}

func downloadGameInfo(gameID: String, type: String, completion: @escaping (GameInfo) -> Void) {
    var returnGames = GameInfo(venueImage: "", city: "", state: "", capacity: "", attendance: "", gameColor: "")
    var queryURL = ""
    
    switch type {
    case "jayhawk":
        queryURL = ("http://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/summary?event=" + gameID)
    case "chiefs":
        queryURL = ("http://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event=" + gameID)
    case "royals":
        queryURL = ("https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/summary?event=" + gameID)
        print(queryURL)
    case "sporting":
        queryURL = ("https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/summary?event=" + gameID)
        print(queryURL)
    default:
        print("error - No valid type found")
    }
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            let venueImage = json["gameInfo","venue","images",0,"href"].stringValue
            let city = json["gameInfo","venue","address","city"].stringValue
            let state = json["gameInfo","venue","address","state"].stringValue
            let capacity = json["gameInfo","venue","capacity"].stringValue
            let attendance = json["gameInfo","attendance"].stringValue
            var color = ""
            
            switch type {
            case "jayhawk":
                if (city == "Lawrence") {
                    color = "0051BA"
                } else {
                    if(json["boxscore","teams",0,"team","shortDisplayName"].stringValue == "Kansas") {
                        color = json["boxscore","teams",1,"team","color"].stringValue
                    } else {
                        color = json["boxscore","teams",0,"team","color"].stringValue
                    }
                }
            case "chiefs":
                if (city == "Kansas City") {
                    color = "E31837"
                } else {
                    if(json["boxscore","teams",0,"team","shortDisplayName"].stringValue == "Chiefs") {
                        color = json["boxscore","teams",1,"team","color"].stringValue
                    } else {
                        color = json["boxscore","teams",0,"team","color"].stringValue
                    }
                }
            case "royals":
                if (city == "Kansas City") {
                    color = "004687"
                } else {
                    if(json["boxscore","teams",0,"team","shortDisplayName"].stringValue == "Royals") {
                        color = json["boxscore","teams",1,"team","color"].stringValue
                    } else {
                        color = json["boxscore","teams",0,"team","color"].stringValue
                    }
                }
            default:
                print("error - No valid type found")
            }
            
            let tempGameInfo = GameInfo(venueImage: venueImage, city: city, state: state, capacity: capacity, attendance: attendance, gameColor: color)
            returnGames = tempGameInfo
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}

func downloadSoccerGameInfo(gameID: String, type: String, completion: @escaping (GameInfo) -> Void) {
    var returnGames = GameInfo(venueImage: "", city: "", state: "", capacity: "", attendance: "", gameColor: "")
    let queryURL = ("https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/summary?event=" + gameID)
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            let venueImage = json["gameInfo","venue","images",0,"href"].stringValue
            let city = json["gameInfo","venue","address","city"].stringValue
            let state = json["gameInfo","venue","address","state"].stringValue
            let capacity = json["gameInfo","venue","capacity"].stringValue
            let attendance = json["gameInfo","attendance"].stringValue
            var color = ""
            
            if (city == "Kansas City") {
                color = "002A5C"
            } else {
                if(json["boxscore","teams",0,"team","shortDisplayName"].stringValue == "Kansas City") {
                    //Do nothing
                    color = json["boxscore","teams",1,"team","color"].stringValue
                } else {
                    color = json["boxscore","teams",0,"team","color"].stringValue
                }
            }
            
            let tempGameInfo = GameInfo(venueImage: venueImage, city: city, state: state, capacity: capacity, attendance: attendance, gameColor: color)
            print(tempGameInfo)
            returnGames = tempGameInfo
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}

func downloadBasketballGameTeamStatsData(gameID: String, completion: @escaping ([BasketballGameTeamStats]) -> Void) {
    var returnGames = [BasketballGameTeamStats]()
    let queryURL = ("http://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/summary?event=" + gameID)
    print(queryURL)
    var counter = 0
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            var homeScore = 0
            var awayScore = 0
            let tempGameClock = json["header","competitions",0,"status","type","detail"].stringValue
            
            //Get Scores
            if json["header","competitions",0,"competitors",0,"team","name"].stringValue == "Jayhawks" {
                homeScore = json["header","competitions",0,"competitors",0,"linescores",0,"displayValue"].intValue + json["header","competitions",0,"competitors",0,"linescores",1,"displayValue"].intValue
                awayScore = json["header","competitions",0,"competitors",1,"linescores",0,"displayValue"].intValue + json["header","competitions",0,"competitors",1,"linescores",1,"displayValue"].intValue
            } else {
                homeScore = json["header","competitions",0,"competitors",1,"linescores",0,"displayValue"].intValue + json["header","competitions",0,"competitors",1,"linescores",1,"displayValue"].intValue
                awayScore = json["header","competitions",0,"competitors",0,"linescores",0,"displayValue"].intValue + json["header","competitions",0,"competitors",0,"linescores",1,"displayValue"].intValue
            }
            
            for (_, subJson):(String, JSON) in json["boxscore"]["teams"] {
                let tempName = subJson["team"]["name"].stringValue
                let tempFieldGoals = subJson["statistics",0,"displayValue"].stringValue
                let tempFieldGoalPct = subJson["statistics",1,"displayValue"].floatValue
                let tempThreePoints = subJson["statistics",2,"displayValue"].stringValue
                let tempThreePointPct = subJson["statistics",3,"displayValue"].floatValue
                let tempFreeThrows = subJson["statistics",4,"displayValue"].stringValue
                let tempFreeThrowPct = subJson["statistics",5,"displayValue"].floatValue
                let tempOffensiveRebounds = subJson["statistics",7,"displayValue"].intValue
                let tempDefensiveRebounds = subJson["statistics",8,"displayValue"].intValue
                let tempAssists = subJson["statistics",10,"displayValue"].intValue
                let tempSteals = subJson["statistics",11,"displayValue"].intValue
                let tempBlocks = subJson["statistics",12,"displayValue"].intValue
                let tempTurnOvers = subJson["statistics",13,"displayValue"].intValue
                let tempFouls = subJson["statistics",19,"displayValue"].intValue
                let tempLargestLead = subJson["statistics",20,"displayValue"].intValue
                var tempProjection = subJson["statistics",1,"displayValue"].floatValue
                
                
                //FIND LOGIC
                if(counter == 1) {
                    tempProjection = json["predictor"]["homeTeam"]["gameProjection"].floatValue
                    
                } else {
                    tempProjection = json["predictor"]["awayTeam"]["gameProjection"].floatValue
                }
                
                counter+=1
                
                let tempGameStats = BasketballGameTeamStats(name: tempName, fieldGoals: tempFieldGoals, fieldGoalPct: tempFieldGoalPct, threePoints: tempThreePoints, threePointPct: tempThreePointPct, freeThrows: tempFreeThrows, freeThrowPct: tempFreeThrowPct, offensiveRebounds: tempOffensiveRebounds, defensiveRebounds: tempDefensiveRebounds, assists: tempAssists, steals: tempSteals, blocks: tempBlocks, turnOvers: tempTurnOvers, fouls: tempFouls, largestLead: tempLargestLead, projection: tempProjection, score: homeScore, opponentScore: awayScore, gameClock: tempGameClock)
                returnGames.append(tempGameStats)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}

// NEED TO FINISH //
func downloadFootballGameTeamStatsData(gameID: String, completion: @escaping ([FootballGameTeamStats]) -> Void) {
    var returnGames = [FootballGameTeamStats]()
    
    let queryURL = ("http://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event=" + gameID)
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            var counter = 0
            
            var homeScore = 0
            var awayScore = 0
            let tempGameClock = json["header","competitions",0,"status","type","detail"].stringValue
            
            //Get Scores
            if json["header","competitions",0,"competitors",0,"team","name"].stringValue == "Chiefs" {
                homeScore = json["header","competitions",0,"competitors",0,"score"].intValue
                awayScore = json["header","competitions",0,"competitors",1,"score"].intValue
            } else {
                homeScore = json["header","competitions",0,"competitors",1,"score"].intValue
                awayScore = json["header","competitions",0,"competitors",0,"score"].intValue
            }
            
            for (_, subJson):(String, JSON) in json["boxscore"]["teams"] {
                let tempName = subJson["team"]["name"].stringValue
                let tempYards = subJson["statistics",7,"displayValue"].intValue
                let tempPassingYards = subJson["statistics",10,"displayValue"].intValue
                let tempRushingYards = subJson["statistics",15,"displayValue"].intValue
                let tempFirstDowns = subJson["statistics",0,"displayValue"].intValue
                let tempDrives = subJson["statistics",9,"displayValue"].intValue
                let tempInterceptions = subJson["statistics",13,"displayValue"].intValue
                let tempPossessionTime = subJson["statistics",24,"displayValue"].stringValue
                let tempCompletionAttempts = subJson["statistics",11,"displayValue"].intValue
                let tempFumbles = subJson["statistics",21,"displayValue"].intValue
                
                
                counter+=1
                
                let tempGameStats = FootballGameTeamStats(name: tempName, yards: tempYards, passingYards: tempPassingYards, rushingYards: tempRushingYards, firstDowns: tempFirstDowns, drives: tempDrives, score: homeScore, interceptions: tempInterceptions, possesionTime: tempPossessionTime, completionAttempts: tempCompletionAttempts, opponentScore: awayScore, gameClock: tempGameClock)
                returnGames.append(tempGameStats)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}

func downloadBaseballGameTeamStatsData(gameID: String, completion: @escaping ([BaseballGameTeamStats]) -> Void) {
    var returnGames = [BaseballGameTeamStats]()
    
    let queryURL = ("http://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event=" + gameID)
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, _):(String, JSON) in json["boxscore"]["teams"] {
                /*
                let tempName = subJson["team"]["name"].stringValue
                let tempFieldGoals = subJson["statistics",0,"displayValue"].stringValue
                let tempFieldGoalPct = subJson["statistics",1,"displayValue"].floatValue
                let tempThreePoints = subJson["statistics",2,"displayValue"].stringValue
                let tempThreePointPct = subJson["statistics",3,"displayValue"].floatValue
                let tempFreeThrows = subJson["statistics",4,"displayValue"].stringValue
                let tempFreeThrowPct = subJson["statistics",5,"displayValue"].floatValue
                let tempOffensiveRebounds = subJson["statistics",7,"displayValue"].intValue
                let tempDefensiveRebounds = subJson["statistics",8,"displayValue"].intValue
                let tempAssists = subJson["statistics",10,"displayValue"].intValue
                let tempSteals = subJson["statistics",11,"displayValue"].intValue
                let tempBlocks = subJson["statistics",12,"displayValue"].intValue
                let tempTurnOvers = subJson["statistics",13,"displayValue"].intValue
                let tempFouls = subJson["statistics",19,"displayValue"].intValue
                let tempLargestLead = subJson["statistics",20,"displayValue"].intValue
                var tempProjection = subJson["statistics",1,"displayValue"].floatValue
                
                //FIND LOGIC
                if(counter == 1) {
                    tempProjection = json["predictor"]["homeTeam"]["gameProjection"].floatValue
                } else {
                    tempProjection = json["predictor"]["awayTeam"]["gameProjection"].floatValue
                }
                
                counter+=1
                */
                let tempGameStats = BaseballGameTeamStats(name: "", yards: 0.0, passingYards: 0.0, rushingYards: 0.0, projection: 0.0, score: 0, opponentScore: 0, gameClock: "test")
                returnGames.append(tempGameStats)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}

func downloadSoccerGameTeamStatsData(gameID: String, completion: @escaping ([SoccerGameTeamStats]) -> Void) {
    var returnGames = [SoccerGameTeamStats]()
    
    let queryURL = ("https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/summary?event=" + gameID)
    print(queryURL)
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, _):(String, JSON) in json["boxscore"]["teams"] {
                /*
                let tempName = subJson["team"]["name"].stringValue
                let tempFieldGoals = subJson["statistics",0,"displayValue"].stringValue
                let tempFieldGoalPct = subJson["statistics",1,"displayValue"].floatValue
                let tempThreePoints = subJson["statistics",2,"displayValue"].stringValue
                let tempThreePointPct = subJson["statistics",3,"displayValue"].floatValue
                let tempFreeThrows = subJson["statistics",4,"displayValue"].stringValue
                let tempFreeThrowPct = subJson["statistics",5,"displayValue"].floatValue
                let tempOffensiveRebounds = subJson["statistics",7,"displayValue"].intValue
                let tempDefensiveRebounds = subJson["statistics",8,"displayValue"].intValue
                let tempAssists = subJson["statistics",10,"displayValue"].intValue
                let tempSteals = subJson["statistics",11,"displayValue"].intValue
                let tempBlocks = subJson["statistics",12,"displayValue"].intValue
                let tempTurnOvers = subJson["statistics",13,"displayValue"].intValue
                let tempFouls = subJson["statistics",19,"displayValue"].intValue
                let tempLargestLead = subJson["statistics",20,"displayValue"].intValue
                var tempProjection = subJson["statistics",1,"displayValue"].floatValue
                
                //FIND LOGIC
                if(counter == 1) {
                    tempProjection = json["predictor"]["homeTeam"]["gameProjection"].floatValue
                } else {
                    tempProjection = json["predictor"]["awayTeam"]["gameProjection"].floatValue
                }
                
                counter+=1
                */
                let tempGameStats = SoccerGameTeamStats(name: "", yards: 0.0, passingYards: 0.0, rushingYards: 0.0, projection: 0.0, score: 0, opponentScore: 0, gameClock: "test")
                returnGames.append(tempGameStats)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGames)
        }
        }
    }
}
