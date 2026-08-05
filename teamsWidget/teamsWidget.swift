//
//  teamsWidget.swift
//  teamsWidget
//
//  Created by Stephen Rector on 6/30/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import WidgetKit
import SwiftUI
import Foundation
import SwiftyJSON
import Alamofire
import AlamofireImage
import UIKit

struct Game2: Decodable {
    var id: Int
}

func getGameData() {
    let url = URL(string: "http://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule")!
      
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        
      // ensure there is no error for this HTTP response
      guard error == nil else {
        print ("error: \(error!)")
        return
      }
        
      // ensure there is data returned from this HTTP response
      guard let data = data else {
        print("No data")
        return
      }
        
        // Parse JSON into Dictionary that contains Array of Car struct using JSONDecoder
          guard let gameArrDict = try? JSONDecoder().decode([String: [Game2]].self, from: data) else {
            print("Error: Couldn't decode data into dictionary of array of cars")
            return
          }
          
          // if you are sure the key is "cars"
          let games = gameArrDict["competitions"]!
      
        for game in games {
        print("game ID: \(game.id)")
        print("---")
      }
    }
      
    // execute the HTTP request
    task.resume()
}



struct Game {
    var date: Date
    var team: String
    var opponent: String
    var score: String
    var opponentScore: String
    var timeString: String
    var dateString: String
    var homeLogo: String
    var opponentLogo: String
    var channel: String
    var location: String
    var homeTeam: String
}

struct nextGame: TimelineEntry {
    public let date: Date
    public let game: Game
    public let backgroundColor: Color
}

func downloadScheduleData(team: String, url: String, completion: @escaping (Game) -> Void) {
    var returnGame = Game(date: Date(), team: "team1", opponent: "team2", score: "", opponentScore: "", timeString: "N/A", dateString: "N/A", homeLogo: "N/A", opponentLogo: "N/A", channel: "N/A", location: "N/A", homeTeam: "N/A")
    
    
    OperationQueue().addOperation {
        AF.request(url).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            for (_, subJson):(String, JSON) in json["events"] {
                
                _ = ""
                var gameDate = Date()
                var gameOpponent = ""
                var gameScore = ""
                var gameOpponentScore = ""
                var gameTimeString = ""
                var gameDateString = ""
                var gameOpponentLogo = ""
                var gameHomeLogo = ""
                var gameChannel = ""
                var gameLocation = ""
                var gameHomeTeam = ""
                
                for (_, competitionsJson):(String, JSON) in subJson["competitions"] {
                    gameLocation = competitionsJson["venue"]["fullName"].stringValue
                    
                    var dateString = subJson["date"].stringValue
                    
                    dateString = dateString.replacingOccurrences(of: "T", with: " ")
                    dateString = dateString.replacingOccurrences(of: "Z", with: "")
                    
                    let dateFormatterGet = DateFormatter()
                    dateFormatterGet.dateFormat = "yyyy-MM-dd HH:mm"
                    
                    let dateFormatterPrint = DateFormatter()
                    let timeFormatterPrint = DateFormatter()
                    dateFormatterPrint.dateFormat = "MMM dd, yyyy"
                    timeFormatterPrint.dateFormat = "h:mm a"
                    
                    gameDate = dateFormatterGet.date(from: dateString)!
                    
                    if var tempDate = dateFormatterGet.date(from: dateString) {
                        tempDate.addTimeInterval(TimeInterval(-6.0 * 3600.0))
                        gameDateString = dateFormatterPrint.string(from: tempDate)
                        gameTimeString = timeFormatterPrint.string(from: tempDate)
                    } else {
                        print("There was an error decoding the string")
                    }
                    
                    for (_, broadcastsJson):(String, JSON) in competitionsJson["broadcasts"] {
                        if ((broadcastsJson["type"]["shortName"]) == "TV" || (broadcastsJson["type"]["shortName"]) == "Web") { //us
                            gameChannel = broadcastsJson["media"]["shortName"].stringValue
                        }
                    }
                    
                    for (_, competitorsJson):(String, JSON) in competitionsJson["competitors"] {
                        if((competitorsJson["homeAway"]).stringValue == "home") {
                            gameHomeTeam = competitorsJson["team"]["nickname"].stringValue
                        }
                        
                        
                        if ((competitorsJson["team"]["nickname"]).stringValue == team) { //us
                            gameScore = competitorsJson["score"]["displayValue"].stringValue
                            
                            for (_, logosJson):(String, JSON) in competitorsJson["team"]["logos"] {
                                let link = logosJson["href"].stringValue
                                
                                if (!link.contains("dark")) {
                                    gameHomeLogo = logosJson["href"].stringValue
                                }
                            }
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
                
                
                
                
                if(gameDate >= Date()) {
                    let tempGame = Game(date: Date(), team: "Chiefs", opponent: gameOpponent, score: gameScore, opponentScore: gameOpponentScore, timeString: gameTimeString, dateString: gameDateString, homeLogo: gameHomeLogo, opponentLogo: gameOpponentLogo, channel: gameChannel, location: gameLocation, homeTeam: gameHomeTeam)
                
                    returnGame = tempGame
                    break
                }
            }
        case .failure(let error):
            //print(error)
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGame)
        }
    }
    }
}

func getNextGame(completion: @escaping (Game) -> Void) {
    var returnGame = Game(date: Date(), team: "team1", opponent: "team2", score: "", opponentScore: "", timeString: "N/A", dateString: "N/A", homeLogo: "N/A", opponentLogo: "N/A", channel: "N/A", location: "N/A", homeTeam: "N/A")
    
    print("Getting Game!")
    
    OperationQueue().addOperation {
        downloadScheduleData(team: "KC", url: "http://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule",  completion: { game in
            let upNextGameKC = game
            downloadScheduleData(team: "jayhawks", url: "test", completion: { game in
                let upNextGameKU: Game
                upNextGameKU = game
                downloadScheduleData(team: "sporting", url: "test", completion: { game in
                    let upNextGameSporting: Game
                    upNextGameSporting = game
                    downloadScheduleData(team: "Royals", url: "test", completion: { game in
                        let upNextGameRoyals: Game
                        upNextGameRoyals = game
                        
                        //determine the least game based on date
                        var games = [upNextGameKU, upNextGameKC, upNextGameRoyals, upNextGameSporting]
                        
                        games = games.sorted(by: {$0.date > $1.date})

                        for game in (0..<games.count).reversed() {
                            if (games[game].team == "team1") {
                                games.remove(at: game)
                            }
                        }
 
                        returnGame = games[0]
                    })
                })
            })
        })
        
        OperationQueue.main.addOperation {
            print(returnGame)
            completion(returnGame)
        }
    }
}


struct Provider: TimelineProvider {

    public func snapshot(with context: Context, completion: @escaping (nextGame) -> ()) {
        let fakeGame = Game(date: Date(), team: "Home", opponent: "Away", score: "0", opponentScore: "0", timeString: "Time", dateString: "Date", homeLogo: "N/A", opponentLogo: "N/A", channel: "none", location: "N/A", homeTeam: "N/A")
        let entry = nextGame(date: Date(), game: fakeGame, backgroundColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
        getGameData()
        completion(entry)
        
        
    }

    public func timeline(with context: Context, completion: @escaping (Timeline<nextGame>) -> ()) {
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
        
        getNextGame(completion: { game in
            
        })
        
        downloadScheduleData(team: "KC", url: "http://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule",  completion: { game in
            let upNextGame: Game
            upNextGame = game
            
            let entry = nextGame(date: currentDate, game: upNextGame, backgroundColor: Color(UIColor(red: 227/255, green: 24/255, blue: 55/255, alpha: 1.00)))
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            
            completion(timeline)
        })
    }
}

struct PlaceholderView : View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
         
         Image("icon")
         .resizable()
         .aspectRatio(contentMode: .fill)
         .frame(width: 60, height: 60)
         
         Text("Next Game")
                .bold()
             .minimumScaleFactor(0.5)
         Text("Game Date")
                .foregroundColor(.secondary)
                .font(.footnote)
             .minimumScaleFactor(0.5)
         Text("Game Time")
                .foregroundColor(.secondary)
                .font(.footnote)
             .minimumScaleFactor(0.5)
         
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.systemBackground))
    }
}

struct teamsWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
           VStack(alignment: .leading, spacing: 5) {
            
            Image("KC")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
            
            Text(entry.game.team + " VS " + entry.game.opponent)
                   .bold()
                .minimumScaleFactor(0.5)
            Text(entry.game.dateString)
                   .foregroundColor(.secondary)
                   .font(.footnote)
                .minimumScaleFactor(0.5)
            Text(entry.game.timeString)
                   .foregroundColor(.secondary)
                   .font(.footnote)
                .minimumScaleFactor(0.5)
            
           }
           .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
           .padding()
           .background(entry.backgroundColor)
       }
}

@main
struct teamsWidget: Widget {
    private let kind: String = "teamsWidget"

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider(), placeholder: PlaceholderView()) { entry in
            teamsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("myTeams Widget")
        .description("This widget shows the next upcoming game from the myTeams app.")
    }
}
