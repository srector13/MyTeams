//
//  GameView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

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
    @State private var gameTeamStats = BasketballGameTeamStats.placeholderPair
    
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack() {
                Rectangle()
                    .foregroundStyle(self.teamColor)
                
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
                                .foregroundStyle(Color.white)
                            
                            if(game.opponentLogo == "") {
                                Image("blankTeam")
                                    .frame(width: 60, height: 60)
                            } else {
                                RemoteImage(url: URL(string: game.opponentLogo))
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                            }
                            
                            Text(game.date)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                            Text(game.time)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                            Text(game.channel)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                        }
                            
                            Rectangle()
                                .foregroundStyle(teamColor)
                                .opacity(0.5)
                            
                            if(game.cancelled) {
                                Text("Cancelled")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
                            }else if (game.postponed) {
                                Text("Postponed")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
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
                                        .foregroundStyle(Color.white)
                                    
                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                        Image("blankTeam")
                                            .resizable()
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .opacity(0.5)
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                }//.padding(.all, 0.5)
                                
                                Rectangle()
                                    .foregroundStyle(teamColor)
                                    .opacity(0.5)
                                
                                if (game.gameWin) {
                                    VStack {
                                        Text("Win")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.white)
                                        
                                        Text(game.score + " - " + game.opponentScore)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
                                    }
                                } else if (!game.gameWin) {
                                    VStack {
                                        Text("Loss")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.white)
                                        
                                        Text(game.opponentScore + " - " + game.score)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
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
                                            .foregroundStyle(Color.white)
                                        
                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                            Image("blankTeam")
                                                .resizable()
                                        }
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .opacity(0.5)
                                        
                                        Text(game.date)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.time)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.channel)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                    }//.padding(.all, 0.5)
                                    
                                    Rectangle()
                                        .foregroundStyle(teamColor)
                                        .opacity(0.5)
                                    
                                    VStack {
                                        
                                        if(game.gameHalftime) {
                                            Text("Halftime")
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                        } else {
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                        }
                                        
                                        Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                            .font(.system(size: 24))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
                                    }
                                }
                            }
                        } else {
                            Group {
                                VStack(alignment: .center, spacing: 0) {
                                    Text(game.opponent)
                                        .font(.system(size: 12))
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.white)
                                    
                                    if(game.opponentLogo == "") {
                                        Image("blankTeam")
                                            .frame(width: 60, height: 60)
                                    } else {
                                        RemoteImage(url: URL(string: game.opponentLogo))
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                    }
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                }
                            }
                        }
                    }
                }
                
                
            }.frame(height: 120)
            ZStack() {
                Rectangle()
                    .foregroundStyle(Color(uiColor: .systemGray4))
                
                Group() {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 80, height: 25)
                        .foregroundStyle(teamColor)
                    
                    Text("Info")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }
                
            }.frame(height: 40)
            
        }.background(Color(uiColor: .systemBackground))
            .frame(width: 120, height: 160)
            .clipShape(.rect(cornerRadius: 10))
        .task(repeatingEvery: .seconds(60)) {
            gameTeamStats = await downloadBasketballGameTeamStatsData(gameID: game.gameID)
        }
    }
}

struct FootballGameView : View {
    
    var game: Game
    var teamColor: Color
    var teamLogo: String
    @State private var gameTeamStats = FootballGameTeamStats.placeholderPair
    
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack() {
                Rectangle()
                    .foregroundStyle(self.teamColor)
                
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
                                .foregroundStyle(Color.white)
                            
                            if(game.opponentLogo == "") {
                                Image("blankTeam")
                                    .frame(width: 60, height: 60)
                            } else {
                                RemoteImage(url: URL(string: game.opponentLogo))
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                            }
                            
                            Text(game.date)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                            Text(game.time)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                            Text(game.channel)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                            
                        }
                            
                            Rectangle()
                                .foregroundStyle(teamColor)
                                .opacity(0.5)
                            
                            if(game.cancelled) {
                                Text("Cancelled")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
                            }else if (game.postponed) {
                                Text("Postponed")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
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
                                        .foregroundStyle(Color.white)
                                    
                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                        Image("blankTeam")
                                            .resizable()
                                    }
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .opacity(0.5)
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                        .opacity(0.5)
                                }//.padding(.all, 0.5)
                                
                                Rectangle()
                                    .foregroundStyle(teamColor)
                                    .opacity(0.5)
                                
                                if (game.gameWin) {
                                    VStack {
                                        Text("Win")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.white)
                                        
                                        Text(game.score + " - " + game.opponentScore)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
                                    }
                                } else if (!game.gameWin) {
                                    VStack {
                                        Text("Loss")
                                            .font(.system(size: 24))
                                            .fontWeight(.bold)
                                            .foregroundStyle(Color.white)
                                        
                                        Text(game.opponentScore + " - " + game.score)
                                            .font(.system(size: 20))
                                            .fontWeight(.heavy)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
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
                                            .foregroundStyle(Color.white)
                                        
                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                            Image("blankTeam")
                                                .resizable()
                                        }
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .opacity(0.5)
                                        
                                        Text(game.date)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.time)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                        
                                        Text(game.channel)
                                            .font(.system(size: 10))
                                            .fontWeight(.medium)
                                            .foregroundStyle(Color.white)
                                            .opacity(0.5)
                                    }//.padding(.all, 0.5)
                                    
                                    Rectangle()
                                        .foregroundStyle(teamColor)
                                        .opacity(0.5)
                                    
                                    if (gameTeamStats[0].score > gameTeamStats[0].opponentScore) {
                                        VStack {
                                            HStack() {
                                                Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                    .font(.system(size: 24))
                                                    .fontWeight(.heavy)
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundStyle(Color.white)
                                                
                                                Image(systemName: "arrow.up")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(Color.green)
                                                
                                            }
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                        }
                                    } else if (gameTeamStats[0].score == gameTeamStats[0].opponentScore) {
                                        VStack {
                                            Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                .font(.system(size: 24))
                                                .fontWeight(.heavy)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 15))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
                                        }
                                    } else {
                                        VStack {
                                            HStack() {
                                                Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                    .font(.system(size: 24))
                                                    .fontWeight(.heavy)
                                                    .minimumScaleFactor(0.5)
                                                    .foregroundStyle(Color.white)
                                                
                                                Image(systemName: "arrow.down")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(Color.red)
                                                
                                            }
                                            
                                            
                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                            .font(.system(size: 12))
                                            .fontWeight(.bold)
                                            .minimumScaleFactor(0.5)
                                            .foregroundStyle(Color.white)
                                            
                                            
                                            Text(game.gameClock)
                                                .font(.system(size: 12))
                                                .fontWeight(.bold)
                                                .minimumScaleFactor(0.5)
                                                .foregroundStyle(Color.white)
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
                                        .foregroundStyle(Color.white)
                                    
                                    if(game.opponentLogo == "") {
                                        Image("blankTeam")
                                            .frame(width: 60, height: 60)
                                    } else {
                                        RemoteImage(url: URL(string: game.opponentLogo))
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                    }
                                    
                                    Text(game.date)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                    Text(game.time)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                    Text(game.channel)
                                        .font(.system(size: 10))
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.white)
                                    
                                }//.padding(.all, 0.5)
                            }
                        }
                    }
                }
                
                
            }.frame(height: 120)
            ZStack() {
                Rectangle()
                    .foregroundStyle(Color(uiColor: .systemGray4))
                
                Group() {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 80, height: 25)
                        .foregroundStyle(teamColor)
                    
                    Text("Info")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }
                
            }.frame(height: 40)
            
        }.background(Color(uiColor: .systemBackground))
            .frame(width: 120, height: 160)
            .clipShape(.rect(cornerRadius: 10))
        .task(repeatingEvery: .seconds(60)) {
            gameTeamStats = await downloadFootballGameTeamStatsData(gameID: game.gameID)
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

