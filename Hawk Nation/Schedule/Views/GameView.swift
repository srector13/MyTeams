//
//  GameView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct LoadingGameView : View {
    var body: some View {
        LoadingView()
            .frame(width: 120, height: 160)
    }
}

struct GameView : View {
    
    var game: Game
    var teamColor: Color
    var teamLogo: String
    @State var gameTeamStats = [BasketballGameTeamStats(name: "", fieldGoals: "0", fieldGoalPct: 0.00, threePoints: "0", threePointPct: 0.00, freeThrows: "0", freeThrowPct: 0.00, offensiveRebounds: 0, defensiveRebounds: 0, assists: 0, steals: 5, blocks: 0, turnOvers: 0, fouls: 0, largestLead: 0, projection: 0.00, score: 0, opponentScore: 0, gameClock: ""), BasketballGameTeamStats(name: "", fieldGoals: "0", fieldGoalPct: 0.00, threePoints: "0", threePointPct: 0.00, freeThrows: "0", freeThrowPct: 0.00, offensiveRebounds: 0, defensiveRebounds: 0, assists: 0, steals: 5, blocks: 0, turnOvers: 0, fouls: 0, largestLead: 0, projection: 0.00, score: 0, opponentScore: 0, gameClock: "")]
    
    //Timer to reload ever 60 seconds
    let timer = Timer.publish(every: 60, on: .current, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack() {
                Rectangle()
                    .foregroundColor(self.teamColor)
                
                Image(teamLogo)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.1)
                    .saturation(0.1)
                    .contrast(0.5)
                    .frame(width: 200, height: 200)
                    .offset(x: 40, y: 50)
                if(game.cancelled || game.postponed) {
                    Group {
                        ZStack {
                        VStack(alignment: .center, spacing: 0) {
                            Text(game.opponent)
                                .font(.system(size: 12))
                                .fontWeight(.bold)
                                .foregroundColor(Color.white)
                            
                            if(game.opponentLogo == "") {
                                Image("blankTeam")
                                    .resizable()
                                    .frame(width: 60, height: 60)
                            } else {
                                WebImage(url: URL(string: game.opponentLogo))
                                    .onSuccess { image, cacheType in
                                        // Success
                                }
                                .resizable()
                                .indicator(.activity)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                            }
                            
                            Text(game.date)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                            Text(game.time)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                            Text(game.channel)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                        }
                            
                            Rectangle()
                                .foregroundColor(teamColor)
                                .opacity(0.5)
                            
                            if(game.cancelled) {
                                Text("Cancelled")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.white)
                            }else if (game.postponed) {
                                Text("Postponed")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.white)
                            }
                            
                            
                        }
                    }
                } else {
                    if(game.completed) {
                        Group {
                            ZStack {
                                VStack(alignment: .center, spacing: 0) {
                                    Text(game.opponent)
                                        .font(.system(size: 12))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.white)
                                    
                                    WebImage(url: URL(string: game.opponentLogo))
                                        .onSuccess { image, cacheType in
                                            // Success
                                    }
                                    .resizable()
                                    .placeholder(Image("blankTeam"))
                                    .indicator(.activity)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .opacity(0.5)
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                }//.padding(.all, 0.5)
                                
                                Rectangle()
                                    .foregroundColor(teamColor)
                                    .opacity(0.5)
                                
                                if (game.gameWin) {
                                    VStack {
                                        Text("Win")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        Text(game.score + " - " + game.opponentScore)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                    }
                                } else if (!game.gameWin) {
                                    VStack {
                                        Text("Loss")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        Text(game.opponentScore + " - " + game.score)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                    }
                                }
                            }
                        }
                    } else {
                        if(game.dateAsDate < Date()) {
                            Group {
                                ZStack {
                                    VStack(alignment: .center, spacing: 0) {
                                        Text(game.opponent)
                                            .font(.system(size: 12))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        WebImage(url: URL(string: game.opponentLogo))
                                            .onSuccess { image, cacheType in
                                                // Success
                                        }
                                        .resizable()
                                        .placeholder(Image("blankTeam"))
                                        .indicator(.activity)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .opacity(0.5)
                                        
                                        Text(game.date)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.time)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.channel)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                    }//.padding(.all, 0.5)
                                    
                                    Rectangle()
                                        .foregroundColor(teamColor)
                                        .opacity(0.5)
                                    
                                    VStack {
                                        
                                        if(game.gameHalftime) {
                                            Text("Halftime")
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                        } else {
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                        }
                                        
                                        Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                            .font(.system(size: 24))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                    }
                                }
                            }
                        } else {
                            Group {
                                VStack(alignment: .center, spacing: 0) {
                                    Text(game.opponent)
                                        .font(.system(size: 12))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.white)
                                    
                                    if(game.opponentLogo == "") {
                                        Image("blankTeam")
                                            .resizable()
                                            .frame(width: 60, height: 60)
                                    } else {
                                        WebImage(url: URL(string: game.opponentLogo))
                                            .onSuccess { image, cacheType in
                                                // Success
                                        }
                                        .resizable()
                                        .indicator(.activity)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                    }
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                }
                            }
                        }
                    }
                }
                
                
            }.frame(height: 120)
            ZStack() {
                Rectangle()
                    .foregroundColor(Color(UIColor.systemGray4))
                
                Group() {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 80, height: 25)
                        .foregroundColor(teamColor)
                    
                    Text("Info")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white)
                }
                
            }.frame(height: 40)
            
        }.background(Color(UIColor.systemBackground))
            .frame(width: 120, height: 160)
            .cornerRadius(10)
        .onAppear {
            downloadBasketballGameTeamStatsData(gameID: self.game.gameID, completion: { stats in
                self.gameTeamStats = stats
            })
        }
        .onReceive(timer) {time in
            downloadBasketballGameTeamStatsData(gameID: self.game.gameID, completion: { stats in
                self.gameTeamStats = stats
            })
        }
    }
}

struct FootballGameView : View {
    
    var game: Game
    var teamColor: Color
    var teamLogo: String
    @State var gameTeamStats = [FootballGameTeamStats(name: "", yards: 0, passingYards: 0, rushingYards: 0, firstDowns: 0, drives: 0, score: 0, interceptions: 0, possesionTime: "", completionAttempts: 0, opponentScore: 0, gameClock: ""), FootballGameTeamStats(name: "", yards: 0, passingYards: 0, rushingYards: 0, firstDowns: 0, drives: 0, score: 0, interceptions: 0, possesionTime: "", completionAttempts: 0, opponentScore: 0, gameClock: "")]
    
    //Timer to reload ever 60 seconds
    let timer = Timer.publish(every: 60, on: .current, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack() {
                Rectangle()
                    .foregroundColor(self.teamColor)
                
                Image(teamLogo)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.1)
                    .saturation(0.1)
                    .contrast(0.5)
                    .frame(width: 200, height: 200)
                    .offset(x: 40, y: 50)
                if(game.cancelled || game.postponed) {
                    Group {
                        ZStack {
                        VStack(alignment: .center, spacing: 0) {
                            Text(game.opponent)
                                .font(.system(size: 12))
                                .fontWeight(.bold)
                                .foregroundColor(Color.white)
                            
                            if(game.opponentLogo == "") {
                                Image("blankTeam")
                                    .resizable()
                                    .frame(width: 60, height: 60)
                            } else {
                                WebImage(url: URL(string: game.opponentLogo))
                                    .onSuccess { image, cacheType in
                                        // Success
                                }
                                .resizable()
                                .indicator(.activity)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                            }
                            
                            Text(game.date)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                            Text(game.time)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                            Text(game.channel)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Color.white)
                            
                        }
                            
                            Rectangle()
                                .foregroundColor(teamColor)
                                .opacity(0.5)
                            
                            if(game.cancelled) {
                                Text("Cancelled")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.white)
                            }else if (game.postponed) {
                                Text("Postponed")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.white)
                            }
                            
                            
                        }
                    }
                } else {
                    if(game.completed) {
                        Group {
                            ZStack {
                                VStack(alignment: .center, spacing: 0) {
                                    Text(game.opponent)
                                        .font(.system(size: 12))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.white)
                                    
                                    WebImage(url: URL(string: game.opponentLogo))
                                        .onSuccess { image, cacheType in
                                            // Success
                                    }
                                    .resizable()
                                    .placeholder(Image("blankTeam"))
                                    .indicator(.activity)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .opacity(0.5)
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                        .opacity(0.5)
                                }//.padding(.all, 0.5)
                                
                                Rectangle()
                                    .foregroundColor(teamColor)
                                    .opacity(0.5)
                                
                                if (game.gameWin) {
                                    VStack {
                                        Text("Win")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        Text(game.score + " - " + game.opponentScore)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                    }
                                } else if (!game.gameWin) {
                                    VStack {
                                        Text("Loss")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        Text(game.opponentScore + " - " + game.score)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                    }
                                }
                            }
                        }
                    } else {
                        if(game.dateAsDate < Date()) {
                            Group {
                                ZStack {
                                    VStack(alignment: .center, spacing: 0) {
                                        Text(game.opponent)
                                            .font(.system(size: 12))
                                            .fontWeight(.bold)
                                            .foregroundColor(Color.white)
                                        
                                        WebImage(url: URL(string: game.opponentLogo))
                                            .onSuccess { image, cacheType in
                                                // Success
                                        }
                                        .resizable()
                                        .placeholder(Image("blankTeam"))
                                        .indicator(.activity)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .opacity(0.5)
                                        
                                        Text(game.date)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.time)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.channel)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundColor(Color.white)
                                            .opacity(0.5)
                                    }//.padding(.all, 0.5)
                                    
                                    Rectangle()
                                        .foregroundColor(teamColor)
                                        .opacity(0.5)
                                    
                                    if (gameTeamStats[0].score > gameTeamStats[0].opponentScore) {
                                        VStack {
                                            HStack() {
                                                Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                    .font(.system(size: 24))
                                                    .fontWeight(.heavy)
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundColor(Color.white)
                                                
                                                Image(systemName: "arrow.up")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(Color.green)
                                                
                                            }
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                        }
                                    } else if (gameTeamStats[0].score == gameTeamStats[0].opponentScore) {
                                        VStack {
                                            Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                .font(.system(size: 24))
                                                .fontWeight(.heavy)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                        }
                                    } else {
                                        VStack {
                                            HStack() {
                                                Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                    .font(.system(size: 24))
                                                    .fontWeight(.heavy)
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundColor(Color.white)
                                                
                                                Image(systemName: "arrow.down")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(Color.red)
                                                
                                            }
                                            
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                            .font(.system(size: 12))
                                            .fontWeight(.bold)
                                            .minimumScaleFactor(0.5)
                                            .foregroundColor(Color.white)
                                            
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 12))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundColor(Color.white)
                                        }
                                    }
                                }
                            }
                        } else {
                            Group {
                                VStack(alignment: .center, spacing: 0) {
                                    Text(game.opponent)
                                        .font(.system(size: 12))
                                        .fontWeight(.bold)
                                        .foregroundColor(Color.white)
                                    
                                    if(game.opponentLogo == "") {
                                        Image("blankTeam")
                                            .resizable()
                                            .frame(width: 60, height: 60)
                                    } else {
                                        WebImage(url: URL(string: game.opponentLogo))
                                            .onSuccess { image, cacheType in
                                                // Success
                                        }
                                        .resizable()
                                        .indicator(.activity)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                    }
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.white)
                                    
                                }//.padding(.all, 0.5)
                            }
                        }
                    }
                }
                
                
            }.frame(height: 120)
            ZStack() {
                Rectangle()
                    .foregroundColor(Color(UIColor.systemGray4))
                
                Group() {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 80, height: 25)
                        .foregroundColor(teamColor)
                    
                    Text("Info")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white)
                }
                
            }.frame(height: 40)
            
        }.background(Color(UIColor.systemBackground))
            .frame(width: 120, height: 160)
            .cornerRadius(10)
        .onAppear {
            downloadFootballGameTeamStatsData(gameID: self.game.gameID, completion: { stats in
                self.gameTeamStats = stats
            })
        }
        .onReceive(timer) {time in
            downloadFootballGameTeamStatsData(gameID: self.game.gameID, completion: { stats in
                self.gameTeamStats = stats
            })
        }
    }
}

extension UIColor {
    var customAccent: UIColor {
        if #available(iOS 13, *) {
            return UIColor { (traitCollection: UITraitCollection) -> UIColor in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemYellow
                } else {
                    return UIColor.systemBackground
                }
            }
        } else {
            return UIColor.white
        }
    }
}

func getPeriod(period: String, team: String) -> String {
    var returnPeriod = ""
    
    if(team == "Kansas" || team == "Kansas City") {
        if(period == "2") {
            returnPeriod = "2nd Half"
        } else if (period == "1") {
            returnPeriod = "1st Half"
        }
    } else if (team == "Royals") {
        
    } else if (team == "KC") {
        if(period == "4") {
            returnPeriod = "4th Quarter"
        } else if (period == "3") {
            returnPeriod = "3rd Quarter"
        } else if(period == "2") {
            returnPeriod = "2nd Quarter"
        } else if (period == "1") {
            returnPeriod = "1st Quarter"
        }
    }
    
    return returnPeriod
}

