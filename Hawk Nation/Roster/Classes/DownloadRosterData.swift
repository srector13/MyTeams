//
//  DownloadRosterData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/28/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

struct BasketballPlayer: Identifiable {
    var id = UUID()
    var playerID: String
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var grade: String
    var hometown: String
    var photo: String
    var status: String
    var lastName: String
}
struct FootBallPlayer: Identifiable {
    var id = UUID()
    var name: String
    var numberInt: Int
    var number: String
    var height: String
    var weight: String
    var position: String
    var hometown: String
    var photo: String
    var debutYear: String
    var college: String
    var age: String
    var lastName: String
    var team: String
}
struct SoccerPlayer: Identifiable {
    var id = UUID()
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var photo: String
    var age: String
    var playerID: String
    var birthPlace: String
    var citizenshipCountry: String
    var fouls: Int
    var foulsSuffered: Int
    var redCards: Int
    var yellowCards: Int
    var ownGoals: Int
    var appearances: Int
    var subAppearances: Int
    var goalAssists: Int
    var offsides: Int
    var shotsOnTarget: Int
    var totalShots: Int
    var totalGoals: Int
    var saves: Int
    var shotsFaced: Int
    var goalsConceded: Int
    var lastName: String
    
}
struct BaseballPlayer: Identifiable {
    var id = UUID()
    var playerID: String
    var name: String
    var number: String
    var numberInt: Int
    var height: String
    var weight: String
    var position: String
    var hometown: String
    var photo: String
    var debutYear: String
    var college: String
    var batHand: String
    var throwHand: String
    var age: String
    var lastName: String
}

func downloadBasketballRoster(completion: @escaping ([BasketballPlayer]) -> Void) {
    var returnRoster = [BasketballPlayer]()
    
    OperationQueue().addOperation { AF.request("http://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/roster").responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["athletes"] {
                
                var playerName = ""
                var playerID = ""
                var playerNumber = ""
                var playerHeight = ""
                var playerWeight = ""
                var playerPosition = ""
                var playerGrade = ""
                var numberInt = 1000
                var playerHometown = ""
                var playerPhoto = ""
                var playerStatus = ""
                var playerState = ""
                var playerLastName = ""
                
                playerName = subJson["fullName"].stringValue
                playerLastName = subJson["lastName"].stringValue
                playerID = subJson["id"].stringValue
                playerHeight = subJson["displayHeight"].stringValue
                playerWeight = subJson["displayWeight"].stringValue
                
                playerNumber = subJson["jersey"].stringValue
                numberInt = Int(playerNumber) ?? 1000
                
                let playerCity = subJson["birthPlace"]["city"].stringValue
                if (subJson["birthPlace"]["state"].stringValue != "") {
                    playerState = subJson["birthPlace"]["state"].stringValue
                } else {
                    playerState = subJson["birthPlace"]["country"].stringValue
                }
                
                
                
                playerHometown = ("\(playerCity), \(playerState)")
                
                playerPosition = subJson["position"]["displayName"].stringValue
                playerGrade = subJson["experience"]["displayValue"].stringValue
                
                playerPhoto = subJson["headshot"]["href"].stringValue
                
                playerStatus = subJson["status"]["name"].stringValue
                
                if (playerPhoto == "") {
                    playerPhoto = "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png"
                }
                
                let tempPlayer = BasketballPlayer(playerID: playerID, name: playerName, number: playerNumber, numberInt: numberInt, height: playerHeight, weight: playerWeight, position: playerPosition, grade: playerGrade, hometown: playerHometown, photo: playerPhoto, status: playerStatus, lastName: playerLastName)
                
                returnRoster.append(tempPlayer)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            returnRoster = returnRoster.sorted(by: { $0.lastName < $1.lastName })
            completion(returnRoster)
        }
        }
    }
}

func downloadFootballRoster(completion: @escaping ([FootBallPlayer]) -> Void) {
    var returnRoster = [FootBallPlayer]()
    
    OperationQueue().addOperation { AF.request("http://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/roster").responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["athletes"] {
                
                var playerName = ""
                var playerNumber = ""
                var playerHeight = ""
                var playerWeight = ""
                var playerPosition = ""
                var playerHometown = ""
                var playerPhoto = ""
                var playerDebutYear = ""
                var playerCollege = ""
                var numberInt = 1000
                var playerAge = ""
                var playerLastName = ""
                let playerTeam = subJson["position"].stringValue
                
                for (_, itemsJson):(String, JSON) in subJson["items"] {
                    
                    playerName = itemsJson["fullName"].stringValue
                    playerLastName = itemsJson["lastName"].stringValue
                    playerHeight = itemsJson["displayHeight"].stringValue
                    playerWeight = itemsJson["displayWeight"].stringValue
                    playerNumber = itemsJson["jersey"].stringValue
                    playerAge = itemsJson["age"].stringValue
                    
                    numberInt = Int(playerNumber) ?? 1000
                    
                    playerDebutYear = itemsJson["debutYear"].stringValue
                    playerPosition = itemsJson["position"]["displayName"].stringValue
                    playerPhoto = itemsJson["headshot"]["href"].stringValue
                    playerCollege = itemsJson["college"]["name"].stringValue
                    
                    if (playerPhoto == "") {
                        playerPhoto = "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png"
                    }
                    
                    let playerCity = itemsJson["birthPlace"]["city"].stringValue
                    let playerState = itemsJson["birthPlace"]["state"].stringValue
                    
                    if (playerCity != "") {
                        playerHometown = ("\(playerCity), \(playerState)")
                    } else {
                        playerHometown = "N/A"
                    }
                    
                    let tempPlayer = FootBallPlayer(name: playerName, numberInt: numberInt, number: playerNumber, height: playerHeight, weight: playerWeight, position: playerPosition, hometown: playerHometown, photo: playerPhoto, debutYear: playerDebutYear, college: playerCollege, age: playerAge, lastName: playerLastName, team: playerTeam)
                    
                    returnRoster.append(tempPlayer)
                }
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            returnRoster = returnRoster.sorted(by: { $0.lastName < $1.lastName })
            completion(returnRoster)
        }
        }
    }
}

func downloadBaseballRoster(completion: @escaping ([BaseballPlayer]) -> Void) {
    var returnRoster = [BaseballPlayer]()
    
    OperationQueue().addOperation { AF.request("http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/7/roster").responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["athletes"] {
                
                var playerName = ""
                var playerID = ""
                var playerNumber = ""
                var playerHeight = ""
                var playerWeight = ""
                var playerPosition = ""
                var playerHometown = ""
                var numberInt = 1000
                var playerPhoto = ""
                var playerDebutYear = ""
                var playerCollege = ""
                var playerBatHand = ""
                var playerThrowHand = ""
                var playerAge = ""
                var playerLastName = ""
                
                for (_, itemsJson):(String, JSON) in subJson["items"] {
                    playerID = itemsJson["id"].stringValue
                    playerName = itemsJson["fullName"].stringValue
                    playerLastName = itemsJson["lastName"].stringValue
                    playerHeight = itemsJson["displayHeight"].stringValue
                    playerWeight = itemsJson["displayWeight"].stringValue
                    playerNumber = itemsJson["jersey"].stringValue
                    numberInt = Int(playerNumber) ?? 1000
                    playerDebutYear = itemsJson["debutYear"].stringValue
                    playerPosition = itemsJson["position"]["displayName"].stringValue
                    playerPhoto = itemsJson["headshot"]["href"].stringValue
                    playerAge = itemsJson["age"].stringValue
                    
                    if (playerPhoto == "") {
                        playerPhoto = "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png"
                    }
                    
                    playerCollege = itemsJson["college"]["name"].stringValue
                    playerBatHand = itemsJson["bats"]["displayValue"].stringValue
                    playerThrowHand = itemsJson["throws"]["displayValue"].stringValue
                    
                    let playerCity = itemsJson["birthPlace"]["city"].stringValue
                    let playerState = itemsJson["birthPlace"]["state"].stringValue
                    
                    playerHometown = ("\(playerCity), \(playerState)")

                    let tempPlayer = BaseballPlayer(playerID: playerID, name: playerName, number: playerNumber, numberInt: numberInt, height: playerHeight, weight: playerWeight, position: playerPosition, hometown: playerHometown, photo: playerPhoto, debutYear: playerDebutYear, college: playerCollege, batHand: playerBatHand, throwHand: playerThrowHand, age: playerAge, lastName: playerLastName)
                    
                    returnRoster.append(tempPlayer)
                }
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            returnRoster = returnRoster.sorted(by: { $0.lastName < $1.lastName })
            completion(returnRoster)
        }
        }
    }
}

func downloadSoccerRoster(completion: @escaping ([SoccerPlayer]) -> Void) {
    var returnRoster = [SoccerPlayer]()
    
    OperationQueue().addOperation { AF.request("http://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/teams/186/roster").responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["athletes"] {
                
                var playerName = ""
                var playerLastName = ""
                var playerNumber = ""
                var numberInt = 1000
                var playerHeight = ""
                var playerWeight = ""
                var playerPosition = ""
                var playerPhoto = ""
                var playerAge = ""
                var playerBirthPlace = "N/A"
                var playerCountry = "N/A"
                var playerID = ""
                var fouls = 0
                var foulsSuffered = 0
                var redCards = 0
                var yellowCards = 0
                var ownGoals = 0
                var appearances = 0
                var subAppearances = 0
                var goalAssists = 0
                var offsides = 0
                var shotsOnTarget = 0
                var totalShots = 0
                var totalGoals = 0
                var saves = 0
                var shotsFaced = 0
                var goalsConceded = 0
                
                playerName = subJson["fullName"].stringValue
                playerLastName = subJson["lastName"].stringValue
                playerID = subJson["id"].stringValue
                playerHeight = subJson["displayHeight"].stringValue
                playerWeight = subJson["displayWeight"].stringValue
                playerPosition = subJson["position"]["displayName"].stringValue
                playerNumber = subJson["jersey"].stringValue
                numberInt = Int(playerNumber) ?? 1000
                playerAge = subJson["age"].stringValue
                
                if (subJson["birthPlace"]["country"].stringValue != "")  {
                    playerBirthPlace = subJson["birthPlace"]["country"].stringValue
                }
                
                if (subJson["citizenship"].stringValue != "")  {
                    playerCountry = subJson["citizenship"].stringValue
                }
            
                playerPhoto = subJson["headshot"]["href"].stringValue
                
                if (playerPhoto == "") {
                    playerPhoto = "https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png"
                }
                
                fouls = subJson["statistics","splits","categories",0,"stats",0,"value"].intValue
                foulsSuffered = subJson["statistics","splits","categories",0,"stats",1,"value"].intValue
                redCards = subJson["statistics","splits","categories",0,"stats",2,"value"].intValue
                yellowCards = subJson["statistics","splits","categories",0,"stats",3,"value"].intValue
                ownGoals = subJson["statistics","splits","categories",0,"stats",4,"value"].intValue
                appearances = subJson["statistics","splits","categories",0,"stats",5,"value"].intValue
                subAppearances = subJson["statistics","splits","categories",0,"stats",6,"value"].intValue
                goalAssists = subJson["statistics","splits","categories",1,"stats",0,"value"].intValue
                offsides = subJson["statistics","splits","categories",1,"stats",1,"value"].intValue
                shotsOnTarget = subJson["statistics","splits","categories",1,"stats",2,"value"].intValue
                totalShots = subJson["statistics","splits","categories",1,"stats",3,"value"].intValue
                totalGoals = subJson["statistics","splits","categories",1,"stats",4,"value"].intValue
                saves = subJson["statistics","splits","categories",2,"stats",0,"value"].intValue
                goalsConceded = subJson["statistics","splits","categories",2,"stats",2,"value"].intValue
                shotsFaced = saves + goalsConceded
                
                
                let tempPlayer = SoccerPlayer(name: playerName, number: playerNumber, numberInt: numberInt, height: playerHeight, weight: playerWeight, position: playerPosition, photo: playerPhoto, age: playerAge, playerID: playerID, birthPlace: playerBirthPlace, citizenshipCountry: playerCountry, fouls: fouls, foulsSuffered: foulsSuffered, redCards: redCards, yellowCards: yellowCards, ownGoals: ownGoals, appearances: appearances, subAppearances: subAppearances, goalAssists: goalAssists, offsides: offsides, shotsOnTarget: shotsOnTarget, totalShots: totalShots, totalGoals: totalGoals, saves: saves, shotsFaced: shotsFaced, goalsConceded: goalsConceded, lastName: playerLastName)
                
                returnRoster.append(tempPlayer)
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            returnRoster = returnRoster.sorted(by: { $0.lastName < $1.lastName })
            completion(returnRoster)
        }
        }
    }
}
