//
//  DownloadScheduleData.swift
//  myTeams
//
//  Created by Stephen Rector on 2/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

struct Game: Identifiable, Decodable, Hashable {
    var id = UUID()
    var team: String
    var opponent: String
    var score: String
    var opponentScore: String
    var time: String
    var date: String
    var dateAsDate: Date
    var opponentLogo: String
    var channel: String
    var location: String
    var gameHome: Bool
    var gameID: String
    var pointer: Int
    var gameWin: Bool
    var completed: Bool
    var competitionName: String
    var cancelled: Bool
    var postponed: Bool
    var gameClock: String
    var gamePeriod: String
    var gameHalftime: Bool
}

func downloadScheduleData(queryURL: String, teamName: String, completion: @escaping ([Game]) -> Void) {
    var returnGames = [Game]()
    var count = 0
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            
            for (_, subJson):(String, JSON) in json["events"] {
                
                var gameOpponent = ""
                var gameScore = ""
                var gameOpponentScore = ""
                var gameTime = ""
                var gameDate = ""
                var gameOpponentLogo = ""
                var gameChannel = ""
                var gameLocation = ""
                var gameHome = Bool()
                var id = ""
                var gameDateAsDate = Date()
                var Win = Bool()
                var gameCompleted = Bool()
                let gameCompetitionName = subJson["name"].stringValue
                var gameCancelled = Bool()
                var gamePostponed = Bool()
                var tempGameClock = ""
                var tempGamePeriod = ""
                var tempGameHalftime = false
                
                for (_, competitionsJson):(String, JSON) in subJson["competitions"] {
                    gameLocation = competitionsJson["venue"]["fullName"].stringValue
                    id = competitionsJson["id"].stringValue
                    var date = subJson["date"].stringValue
                    date = date.replacingOccurrences(of: "T", with: " ")
                    date = date.replacingOccurrences(of: "Z", with: "")
                    
                    let dateFormatterGet = DateFormatter()
                    dateFormatterGet.dateFormat = "yyyy-MM-dd HH:mm"
                    
                    let dateFormatterPrint = DateFormatter()
                    let timeFormatterPrint = DateFormatter()
                    dateFormatterPrint.dateFormat = "MMM dd, yyyy"
                    timeFormatterPrint.dateFormat = "h:mm a"
                    
                    if var tempDate = dateFormatterGet.date(from: date) {
                        tempDate.addTimeInterval(TimeInterval(-6.0 * 3600.0))
                        gameDateAsDate = tempDate
                        gameDate = dateFormatterPrint.string(from: tempDate)
                        gameTime = timeFormatterPrint.string(from: tempDate)
                    } else {
                        print("There was an error decoding the string")
                    }
                    
                    gameCompleted = competitionsJson["status"]["type"]["completed"].boolValue
                    
                    if competitionsJson["status"]["type"]["description"].stringValue == "Halftime" {
                        tempGameHalftime = true
                    }
                    
                    gameChannel = competitionsJson["broadcasts",0,"media","shortName"].stringValue
                    
                    if(competitionsJson["status"]["type"]["detail"].stringValue == "Postponed") {
                        gamePostponed = true
                    } else {
                        gamePostponed = false
                    }
                    
                    if(competitionsJson["status"]["type"]["detail"].stringValue == "Canceled") {
                        gameCancelled = true
                    } else {
                        gameCancelled = false
                    }
                    
                    if (gameChannel == "") {
                        gameChannel = "TBD"
                    }
                    tempGameClock = competitionsJson["status","displayClock"].stringValue
                    tempGamePeriod = competitionsJson["status","period"].stringValue
                    
                    for (_, competitorsJson):(String, JSON) in competitionsJson["competitors"] {
                        if((competitorsJson["team"]["nickname"]).stringValue == teamName) {
                            if(competitorsJson["homeAway"].stringValue == "home") {
                                gameHome = true
                            } else {
                                gameHome = false
                            }
                            
                            Win = competitorsJson["winner"].boolValue
                        }
                        
                        if ((competitorsJson["team"]["nickname"]).stringValue == teamName) { //us
                            gameScore = competitorsJson["score"]["displayValue"].stringValue
                        } else { //Opponent
                            gameOpponent = competitorsJson["team"]["nickname"].stringValue
                            gameOpponentScore = competitorsJson["score"]["displayValue"].stringValue
                            
                            for (_, logosJson):(String, JSON) in competitorsJson["team"]["logos"] {
                                let link = logosJson["href"].stringValue
                                
                                if (!link.contains("dark")) {
                                    gameOpponentLogo = logosJson["href"].stringValue
                                }
                            }
                        }
                    }
                }
                
                let tempGame = Game(team: teamName, opponent: gameOpponent, score: gameScore, opponentScore: gameOpponentScore, time: gameTime, date: gameDate, dateAsDate: gameDateAsDate, opponentLogo: gameOpponentLogo, channel: gameChannel, location: gameLocation, gameHome: gameHome, gameID: id, pointer: count, gameWin: Win, completed: gameCompleted, competitionName: gameCompetitionName, cancelled: gameCancelled, postponed: gamePostponed, gameClock: tempGameClock, gamePeriod: tempGamePeriod, gameHalftime: tempGameHalftime)
                returnGames.append(tempGame)
                count += 1
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

func downloadScheduleData2(queryURL: String, teamName: String, completion: @escaping ([Game]) -> Void) {
    var returnGames = [Game]()
    var count = 0
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["events"] {
                
                var gameOpponent = ""
                var gameScore = ""
                var gameOpponentScore = ""
                var gameTime = ""
                var gameDate = ""
                var gameOpponentLogo = ""
                var gameChannel = ""
                var gameLocation = ""
                var gameHome = Bool()
                var gameDateAsDate = Date()
                var id = ""
                var Win = Bool()
                var gameCompleted = Bool()
                let gameCompetitionName = subJson["name"].stringValue
                var gameCancelled = Bool()
                var gamePostponed = Bool()
                var tempGameClock = ""
                var tempGamePeriod = ""
                var tempGameHalftime = false
                
                for (_, competitionsJson):(String, JSON) in subJson["competitions"] {
                    gameLocation = competitionsJson["venue"]["fullName"].stringValue
                    id = competitionsJson["id"].stringValue
                    var date = subJson["date"].stringValue
                    date = date.replacingOccurrences(of: "T", with: " ")
                    date = date.replacingOccurrences(of: "Z", with: "")
                    
                    let dateFormatterGet = DateFormatter()
                    dateFormatterGet.dateFormat = "yyyy-MM-dd HH:mm"
                    
                    let dateFormatterPrint = DateFormatter()
                    let timeFormatterPrint = DateFormatter()
                    dateFormatterPrint.dateFormat = "MMM dd, yyyy"
                    timeFormatterPrint.dateFormat = "h:mm a"
                    
                    if var tempDate = dateFormatterGet.date(from: date) {
                        tempDate.addTimeInterval(TimeInterval(-6.0 * 3600.0))
                        gameDateAsDate = tempDate
                        gameDate = dateFormatterPrint.string(from: tempDate)
                        gameTime = timeFormatterPrint.string(from: tempDate)
                    } else {
                        print("There was an error decoding the string")
                    }
                    
                    gameCompleted = competitionsJson["status"]["type"]["completed"].boolValue
                    
                    if competitionsJson["status"]["type"]["description"].stringValue == "Halftime" {
                        tempGameHalftime = true
                    }
                    
                    gameChannel = competitionsJson["broadcasts",0,"media","shortName"].stringValue
                    
                    if (gameChannel == "") {
                        gameChannel = "TBD"
                    }
                    
                    tempGameClock = competitionsJson["status","displayClock"].stringValue
                    tempGamePeriod = competitionsJson["status","period"].stringValue
                    
                    if(competitionsJson["status"]["type"]["detail"].stringValue == "Canceled") {
                        gameCancelled = true
                    } else {
                        gameCancelled = false
                    }
                    
                    if(competitionsJson["status"]["type"]["detail"].stringValue == "Postponed") {
                        gamePostponed = true
                    } else {
                        gamePostponed = false
                    }
                    
                    for (_, competitorsJson):(String, JSON) in competitionsJson["competitors"] {
                                               
                        if((competitorsJson["team"]["shortDisplayName"]).stringValue == teamName) {
                            if(competitorsJson["homeAway"].stringValue == "home") {
                                gameHome = true
                            } else {
                                gameHome = false
                            }
                            
                            Win = competitorsJson["winner"].boolValue
                        }
                        
                        if ((competitorsJson["team"]["shortDisplayName"]).stringValue == teamName) { //us
                            gameScore = competitorsJson["score"]["displayValue"].stringValue
                        } else { //Opponent
                            gameOpponent = competitorsJson["team"]["shortDisplayName"].stringValue
                            gameOpponentScore = competitorsJson["score"]["displayValue"].stringValue
                            
                            for (_, logosJson):(String, JSON) in competitorsJson["team"]["logos"] {
                                let link = logosJson["href"].stringValue
                                
                                if (!link.contains("dark")) {
                                    gameOpponentLogo = logosJson["href"].stringValue
                                }
                            }
                        }
                    }
                }
                
                let tempGame = Game(team: teamName, opponent: gameOpponent, score: gameScore, opponentScore: gameOpponentScore, time: gameTime, date: gameDate, dateAsDate: gameDateAsDate, opponentLogo: gameOpponentLogo, channel: gameChannel, location: gameLocation, gameHome: gameHome, gameID: id, pointer: count, gameWin: Win, completed: gameCompleted, competitionName: gameCompetitionName, cancelled: gameCancelled, postponed: gamePostponed, gameClock: tempGameClock, gamePeriod: tempGamePeriod, gameHalftime: tempGameHalftime)
                
                returnGames.append(tempGame)
                count += 1
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




