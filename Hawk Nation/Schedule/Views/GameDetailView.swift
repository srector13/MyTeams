//
//  GameDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct BasketballGameDetailView: View {
    @Environment(\.containerSize) private var containerSize

    @Environment(\.dismiss) private var dismiss
    let game: Game
    var teamColor: Color
    @State private var gameTeamStats = BasketballGameTeamStats.placeholderPair
    @State private var gameInfo = GameInfo.empty
    var teamLogo: String
    @State private var loading = true
    
    
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if(loading == false) {
                VStack {
                    ZStack(alignment: .top) {
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        RemoteImage(url: URL(string: gameInfo.venueImage))
                            .resizable()
                            .id(gameInfo.venueImage)
                            .frame(width: containerSize.width, height: 200)
                            .clipShape(.rect(cornerRadius: 10))
                        
                        Rectangle()
                            .foregroundStyle(Color(hexString: gameInfo.gameColor))
                            .background(Color(uiColor: .black))
                            .opacity(0.6)
                            .frame(width: containerSize.width, height: 200)
                            .clipShape(.rect(cornerRadius: 10))
                        
                        //GAME DETAILS
                        VStack(spacing: 0) {
                            //DISMISS BUTTON
                            Button(action: {
                                dismiss()
                            }) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: 100, height: 5)
                                    .foregroundStyle(Color(uiColor: .white))
                                    .opacity(0.7)
                            }.padding([.top, .trailing, .leading, .bottom], 10)
                            
                            
                            
                            Text(game.competitionName)
                                .fontWeight(.bold)
                                .font(.system(size: 25))
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.top, 5)
                            
                            Spacer()
                            
                            
                            Text(game.time)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Text(game.date)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Text(game.channel)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Spacer()
                            
                            Text("\(game.location) | \(gameInfo.city), \(gameInfo.state)")
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                        }.padding(.horizontal, 15)
                    }.frame(height: 200)
                    
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .center, spacing: 15) {
                                if(game.cancelled) {
                                    Spacer()
                                    
                                    Text("This game has been canceled.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                } else if (game.postponed) {
                                    Spacer()
                                    
                                    Text("This game has been postponed.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                } else {
                                    if(game.dateAsDate <= Date()) {
                                        HStack(alignment: .top) {
                                            if(game.gameHome) {
                                                HStack() {
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        //HOME TEAM PHOTO
                                                        Image("jayhawk")
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text("Kansas")
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                    
                                                    
                                                    VStack(alignment: .center) {
                                                        Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                            .font(.system(size: 30))
                                                            //.foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                        
                                                        if(game.completed) {
                                                            Text("Final")
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        } else if(game.gameHalftime) {
                                                            Text("Halftime")
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                        } else {
                                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            
                                                            Text(game.gameClock)
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                        }
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                    
                                                    
                                                    VStack(alignment: .trailing, spacing: 5) {
                                                        //AWAY TEAM PHOTO
                                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                                                Image("blankTeam")
                                                                    .resizable()
                                                        }
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text(game.opponent)
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                                }
                                            } else {
                                                HStack() {
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        //HOME TEAM PHOTO
                                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                                                Image("blankTeam")
                                                                    .resizable()
                                                        }
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text(game.opponent)
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                    
                                                    VStack(alignment: .center) {
                                                        Text("\(gameTeamStats[0].opponentScore) - \(gameTeamStats[0].score)")
                                                            .font(.system(size: 30))
                                                            //.foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                        
                                                        if(game.completed) {
                                                            Text("Final")
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        } else {
                                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                            
                                                            Text(game.gameClock)
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        }
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                    
                                                    //AWAY TEAM PHOTO
                                                    VStack(alignment: .trailing, spacing: 5) {
                                                        //PLAYER PHOTO
                                                        Image("jayhawk")
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text("Kansas")
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                                }
                                            }
                                        }.ignoresSafeArea()
                                        
                                        Group {
                                            StatRowView(title: "Field Goals", homeStat: gameTeamStats[1].fieldGoals.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].fieldGoals.replacingOccurrences(of: "-", with: "/"))
                                            
                                            StatRowView(title: "Field Goal %", homeStat: "\(Int(gameTeamStats[1].fieldGoalPct))%", awayStat: "\(Int(gameTeamStats[0].fieldGoalPct))%")
                                            
                                            StatRowView(title: "Three Points", homeStat: gameTeamStats[1].threePoints.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].threePoints.replacingOccurrences(of: "-", with: "/"))
                                            
                                            StatRowView(title: "Three Point %", homeStat: "\(Int(gameTeamStats[1].threePointPct))%", awayStat: "\(Int(gameTeamStats[0].threePointPct))%")
                                            
                                            StatRowView(title: "Free Throws", homeStat: gameTeamStats[1].freeThrows.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].freeThrows.replacingOccurrences(of: "-", with: "/"))
                                            
                                            StatRowView(title: "Free Throw %", homeStat: "\(Int(gameTeamStats[1].freeThrowPct))%", awayStat: "\(Int(gameTeamStats[0].freeThrowPct))%")
                                            
                                            StatRowView(title: "Offensive Rebounds", homeStat: "\(gameTeamStats[1].offensiveRebounds)", awayStat: "\(gameTeamStats[0].offensiveRebounds)")
                                            
                                            StatRowView(title: "Defensive Rebounds", homeStat: "\(gameTeamStats[1].defensiveRebounds)", awayStat: "\(gameTeamStats[0].defensiveRebounds)")
                                            
                                            StatRowView(title: "Assists", homeStat: "\(gameTeamStats[1].assists)", awayStat: "\(gameTeamStats[0].assists)")
                                            
                                            StatRowView(title: "Blocks", homeStat: "\(gameTeamStats[1].blocks)", awayStat: "\(gameTeamStats[0].blocks)")
                                        }
                                        
                                        Group {
                                            StatRowView(title: "Steals", homeStat: "\(gameTeamStats[1].steals)", awayStat: "\(gameTeamStats[0].steals)")
                                            
                                            StatRowView(title: "Turnovers", homeStat: "\(gameTeamStats[1].turnOvers)", awayStat: "\(gameTeamStats[0].turnOvers)")
                                            
                                            StatRowView(title: "Fouls", homeStat: "\(gameTeamStats[1].fouls)", awayStat: "\(gameTeamStats[0].fouls)")
                                        }
                                    } else {
                                        
                                        Spacer()
                                        
                                        Text("No game statistics at this time. Please check back later.")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color(uiColor: .systemGray))
                                            .fontWeight(.bold)
                                            .minimumScaleFactor(0.5)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 30)
                                            .offset(y: -50)
                                    }
                                }
                                
                                
                                
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                        Spacer()
                    }
                }
            }
            else {
                VStack {
                    ZStack(alignment: .top) {
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        LoadingView()
                            .frame(width: containerSize.width, height: 200)
                        
                        //GAME DETAILS
                        VStack(spacing: 5) {
                            //DISMISS BUTTON
                            Button(action: {
                                dismiss()
                            }) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: 100, height: 5)
                                    .foregroundStyle(Color(uiColor: .white))
                                    .opacity(0.7)
                            }.padding([.top, .trailing, .leading, .bottom], 10)
                            
                            LoadingView()
                                .frame(width: containerSize.width-20, height: 25)
                            
                            Spacer()
                            
                            LoadingView()
                                .frame(width: 100, height: 15)
                            
                            LoadingView()
                                .frame(width: 120, height: 15)
                            
                            LoadingView()
                                .frame(width: 50, height: 15)
                            
                            Spacer()
                            
                            LoadingView()
                                .frame(width: 200, height: 15)
                                .padding(.bottom, 10)
                        }.padding(.horizontal, 15)
                    }.frame(height: 200)
                    
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .center, spacing: 15) {
                                HStack() {
                                    VStack(alignment: .leading, spacing: 5) {
                                        LoadingViewCircle()
                                            .frame(width: 50, height: 50)
                                        
                                        
                                        LoadingView()
                                            .frame(width: 75, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                    
                                    
                                    VStack(alignment: .center) {
                                        LoadingView()
                                            .frame(width: 200, height: 30)
                                        
                                        LoadingView()
                                            .frame(width: 50, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                    
                                    
                                    VStack(alignment: .trailing, spacing: 5) {
                                        LoadingViewCircle()
                                            .frame(width: 50, height: 50)
                                        
                                        
                                        LoadingView()
                                            .frame(width: 75, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                }
                                
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                        Spacer()
                    }
                }
            }
            
            
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task(repeatingEvery: .seconds(10)) {
            async let stats = downloadBasketballGameTeamStatsData(gameID: game.gameID)
            async let info = downloadGameInfo(gameID: game.gameID, type: teamLogo)

            gameTeamStats = await stats
            gameInfo = await info
            loading = false
        }
    }
}

struct FootballGameDetailView: View {
    @Environment(\.containerSize) private var containerSize

    @Environment(\.dismiss) private var dismiss
    var game: Game
    var teamColor: Color
    @State private var gameTeamStats = FootballGameTeamStats.placeholderPair
    @State private var gameInfo = GameInfo.empty
    var teamLogo: String
    @State private var loading = true
    
    
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if(loading == false) {
                VStack {
                    ZStack(alignment: .top) {
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        RemoteImage(url: URL(string: gameInfo.venueImage))
                            .resizable()
                            //.id(gameInfo.venueImage)
                            .frame(width: containerSize.width, height: 200)
                            .clipShape(.rect(cornerRadius: 10))
                        
                        Rectangle()
                            .foregroundStyle(Color(hexString: gameInfo.gameColor))
                            .background(Color(uiColor: .black))//LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom))
                            .opacity(0.6)
                            .frame(width: containerSize.width, height: 200)
                            .clipShape(.rect(cornerRadius: 10))
                        
                        //GAME DETAILS
                        VStack(spacing: 0) {
                            //DISMISS BUTTON
                            Button(action: {
                                dismiss()
                            }) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: 100, height: 5)
                                    .foregroundStyle(Color(uiColor: .white))
                                    .opacity(0.7)
                            }.padding([.top, .trailing, .leading, .bottom], 10)
                            
                            
                            
                            Text(game.competitionName)
                                .fontWeight(.bold)
                                .font(.system(size: 25))
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.top, 5)
                            
                            Spacer()
                            
                            
                            Text(game.time)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Text(game.date)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Text(game.channel)
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                            
                            Spacer()
                            
                            Text("\(game.location) | \(gameInfo.city), \(gameInfo.state)")
                                .fontWeight(.bold)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.bottom, 10)
                                .minimumScaleFactor(0.2)
                        }.padding(.horizontal, 15)
                    }.frame(height: 200)
                    
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .center, spacing: 15) {
                                if(game.cancelled) {
                                    Spacer()
                                    
                                    Text("This game has been canceled.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                } else if (game.postponed) {
                                    Spacer()
                                    
                                    Text("This game has been postponed.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                } else {
                                    if(game.dateAsDate <= Date()) {
                                        HStack(alignment: .top) {
                                            if(game.gameHome) {
                                                HStack() {
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        //HOME TEAM PHOTO
                                                        Image("chiefs")
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text("Chiefs")
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                    
                                                    
                                                    VStack(alignment: .center) {
                                                        Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                            .font(.system(size: 30))
                                                            //.foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                        
                                                        if(game.completed) {
                                                            Text("Final")
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        } else {
                                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                            
                                                            Text(game.gameClock)
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        }
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                    
                                                    
                                                    VStack(alignment: .trailing, spacing: 5) {
                                                        //AWAY TEAM PHOTO
                                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                                                Image("blankTeam")
                                                                    .resizable()
                                                        }
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text(game.opponent)
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                                }
                                            } else {
                                                HStack() {
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        //HOME TEAM PHOTO
                                                        RemoteImage(url: URL(string: game.opponentLogo)) {
                                                                Image("blankTeam")
                                                                    .resizable()
                                                        }
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text(game.opponent)
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                    
                                                    VStack(alignment: .center) {
                                                        Text("\(gameTeamStats[0].opponentScore) - \(gameTeamStats[0].score)")
                                                            .font(.system(size: 30))
                                                            //.foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                        
                                                        if(game.completed) {
                                                            Text("Final")
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        } else {
                                                            Text(getPeriod(period: game.gamePeriod, team: game.team))
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                            
                                                            Text(game.gameClock)
                                                                .font(.system(size: 15))
                                                                .fontWeight(.bold)
                                                                .minimumScaleFactor(0.5)
                                                            //.foregroundStyle(Color.white)
                                                        }
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                    
                                                    //AWAY TEAM PHOTO
                                                    VStack(alignment: .trailing, spacing: 5) {
                                                        //PLAYER PHOTO
                                                        Image("chiefs")
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 50, height: 50)
                                                        
                                                        Text("Chiefs")
                                                            .font(.system(size: 15))
                                                            .foregroundStyle(Color(uiColor: .systemGray))
                                                            .fontWeight(.bold)
                                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                                }
                                            }
                                        }.ignoresSafeArea()
                                         Group {
                                            StatRowView(title: "Total Yards", homeStat: "\(gameTeamStats[1].yards)", awayStat: "\(gameTeamStats[0].yards)")
                                         
                                         StatRowView(title: "Passing Yards", homeStat: "\(gameTeamStats[1].passingYards)", awayStat: "\(gameTeamStats[0].passingYards)")
                                         
                                         StatRowView(title: "Rushing Yards", homeStat: "\(gameTeamStats[1].rushingYards)", awayStat: "\(gameTeamStats[0].rushingYards)")
                                         
                                         StatRowView(title: "First Downs", homeStat: "\(gameTeamStats[1].firstDowns)", awayStat: "\(gameTeamStats[0].firstDowns)")
                                         
                                         StatRowView(title: "Drives", homeStat: "\(gameTeamStats[1].drives)", awayStat: "\(gameTeamStats[0].drives)")
                                         
                                         StatRowView(title: "Interceptions", homeStat: "\(gameTeamStats[1].interceptions)", awayStat: "\(gameTeamStats[0].interceptions)")
                                         
                                         StatRowView(title: "Possession Time", homeStat: "\(gameTeamStats[1].possesionTime)", awayStat: "\(gameTeamStats[0].possesionTime)")
                                         
                                         StatRowView(title: "Completion Attempts", homeStat: "\(gameTeamStats[1].completionAttempts)", awayStat: "\(gameTeamStats[0].completionAttempts)")
                                         }
                                    } else {
                                        Spacer()
                                        
                                        Text("No game statistics at this time. Please check back later.")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color(uiColor: .systemGray))
                                            .fontWeight(.bold)
                                            .minimumScaleFactor(0.5)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 30)
                                            .offset(y: -50)
                                    }
                                }
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                        Spacer()
                    }
                }
            }
            else {
                VStack {
                    ZStack(alignment: .top) {
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        LoadingView()
                            .frame(width: containerSize.width, height: 200)
                        
                        //GAME DETAILS
                        VStack(spacing: 5) {
                            //DISMISS BUTTON
                            Button(action: {
                                dismiss()
                            }) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: 100, height: 5)
                                    .foregroundStyle(Color(uiColor: .white))
                                    .opacity(0.7)
                            }.padding([.top, .trailing, .leading, .bottom], 10)
                            
                            LoadingView()
                                .frame(width: containerSize.width-20, height: 25)
                            
                            Spacer()
                            
                            LoadingView()
                                .frame(width: 100, height: 15)
                            
                            LoadingView()
                                .frame(width: 120, height: 15)
                            
                            LoadingView()
                                .frame(width: 50, height: 15)
                            
                            Spacer()
                            
                            LoadingView()
                                .frame(width: 200, height: 15)
                                .padding(.bottom, 10)
                        }.padding(.horizontal, 15)
                    }.frame(height: 200)
                    
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .center, spacing: 15) {
                                HStack() {
                                    VStack(alignment: .leading, spacing: 5) {
                                        LoadingViewCircle()
                                            .frame(width: 50, height: 50)
                                        
                                        
                                        LoadingView()
                                            .frame(width: 75, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                    
                                    
                                    VStack(alignment: .center) {
                                        LoadingView()
                                            .frame(width: 200, height: 30)
                                        
                                        LoadingView()
                                            .frame(width: 50, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                    
                                    
                                    VStack(alignment: .trailing, spacing: 5) {
                                        LoadingViewCircle()
                                            .frame(width: 50, height: 50)
                                        
                                        
                                        LoadingView()
                                            .frame(width: 75, height: 15)
                                    }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                }
                                
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                        Spacer()
                    }
                }
            }
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task(repeatingEvery: .seconds(10)) {
            async let stats = downloadFootballGameTeamStatsData(gameID: game.gameID)
            async let info = downloadGameInfo(gameID: game.gameID, sport: .chiefs)

            gameTeamStats = await stats
            gameInfo = await info
            loading = false
        }
    }
}

struct BaseballGameDetailView: View {
    @Environment(\.containerSize) private var containerSize

    @Environment(\.dismiss) private var dismiss
    var game: Game
    var teamColor: Color
    @State private var gameTeamStats = BaseballGameTeamStats.placeholderPair
    @State private var gameInfo = GameInfo.empty
    var teamLogo: String
    
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {//?USED TO TAKE UP ALL SPACE?//
                    HStack() {
                        Spacer()
                    }
                    
                    RemoteImage(url: URL(string: gameInfo.venueImage), options: .refreshCached)
                        .resizable()
                        .id(gameInfo.venueImage)
                        .frame(width: containerSize.width, height: 200)
                        .clipShape(.rect(cornerRadius: 10))
                    
                    Rectangle()
                        .foregroundStyle(Color(hexString: gameInfo.gameColor))
                        .background(Color(uiColor: .black))//LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom))
                        .opacity(0.6)
                        .frame(width: containerSize.width, height: 200)
                        .clipShape(.rect(cornerRadius: 10))
                    
                    //GAME DETAILS
                    VStack(spacing: 0) {
                        //DISMISS BUTTON
                        Button(action: {
                            dismiss()
                        }) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: 100, height: 5)
                                .foregroundStyle(Color(uiColor: .white))
                                .opacity(0.7)
                        }.padding([.top, .trailing, .leading, .bottom], 10)
                        
                        
                        
                        Text(game.competitionName)
                            .fontWeight(.bold)
                            .font(.system(size: 25))
                            .minimumScaleFactor(0.2)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.top, 5)
                        
                        Spacer()
                        
                        
                        Text(game.time)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Text(game.date)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Text(game.channel)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Spacer()
                        
                        Text("\(game.location) | \(gameInfo.city), \(gameInfo.state)")
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                    }.padding(.horizontal, 15)
                }.frame(height: 200)
                
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: (containerSize.width - 25), height: 600)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                        
                        VStack(alignment: .center, spacing: 15) {
                            if(game.cancelled) {
                                Spacer()
                                
                                Text("This game has been canceled.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(uiColor: .systemGray))
                                    .fontWeight(.bold)
                                    .minimumScaleFactor(0.5)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            } else {
                                if(game.dateAsDate <= Date()) {
                                    HStack(alignment: .top) {
                                        if(game.gameHome) {
                                            HStack() {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    //HOME TEAM PHOTO
                                                    Image("royals")
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text("Royals")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                
                                                
                                                VStack(alignment: .center) {
                                                    Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                        .font(.system(size: 30))
                                                        //.foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                    
                                                    if(game.completed) {
                                                        Text("Final")
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
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                
                                                
                                                VStack(alignment: .trailing, spacing: 5) {
                                                    //AWAY TEAM PHOTO
                                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                                            Image("blankTeam")
                                                                .resizable()
                                                    }
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text(game.opponent)
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                            }
                                        } else {
                                            HStack() {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    //HOME TEAM PHOTO
                                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                                            Image("blankTeam")
                                                                .resizable()
                                                    }
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text(game.opponent)
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                
                                                VStack(alignment: .center) {
                                                    Text("\(gameTeamStats[0].opponentScore) - \(gameTeamStats[0].score)")
                                                        .font(.system(size: 30))
                                                        //.foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                    
                                                    if(game.completed) {
                                                        Text("Final")
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
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                
                                                //AWAY TEAM PHOTO
                                                VStack(alignment: .trailing, spacing: 5) {
                                                    //PLAYER PHOTO
                                                    Image("royals")
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text("Royals")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                            }
                                        }
                                    }.ignoresSafeArea()
                                    /*
                                     Group {
                                     StatRowView(title: "Field Goals", homeStat: gameTeamStats[1].fieldGoals.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].fieldGoals.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Field Goal %", homeStat: "\(Int(gameTeamStats[1].fieldGoalPct))%", awayStat: "\(Int(gameTeamStats[0].fieldGoalPct))%")
                                     
                                     StatRowView(title: "Three Points", homeStat: gameTeamStats[1].threePoints.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].threePoints.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Three Point %", homeStat: "\(Int(gameTeamStats[1].threePointPct))%", awayStat: "\(Int(gameTeamStats[0].threePointPct))%")
                                     
                                     StatRowView(title: "Free Throws", homeStat: gameTeamStats[1].freeThrows.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].freeThrows.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Free Throw %", homeStat: "\(Int(gameTeamStats[1].freeThrowPct))%", awayStat: "\(Int(gameTeamStats[0].freeThrowPct))%")
                                     
                                     StatRowView(title: "Offensive Rebounds", homeStat: "\(gameTeamStats[1].offensiveRebounds)", awayStat: "\(gameTeamStats[0].offensiveRebounds)")
                                     
                                     StatRowView(title: "Defensive Rebounds", homeStat: "\(gameTeamStats[1].defensiveRebounds)", awayStat: "\(gameTeamStats[0].defensiveRebounds)")
                                     
                                     StatRowView(title: "Assists", homeStat: "\(gameTeamStats[1].assists)", awayStat: "\(gameTeamStats[0].assists)")
                                     
                                     StatRowView(title: "Blocks", homeStat: "\(gameTeamStats[1].blocks)", awayStat: "\(gameTeamStats[0].blocks)")
                                     }
                                     
                                     Group {
                                     StatRowView(title: "Steals", homeStat: "\(gameTeamStats[1].steals)", awayStat: "\(gameTeamStats[0].steals)")
                                     
                                     StatRowView(title: "Turnovers", homeStat: "\(gameTeamStats[1].turnOvers)", awayStat: "\(gameTeamStats[0].turnOvers)")
                                     
                                     StatRowView(title: "Fouls", homeStat: "\(gameTeamStats[1].fouls)", awayStat: "\(gameTeamStats[0].fouls)")
                                     }
                                     */
                                } else {
                                    
                                    Spacer()
                                    
                                    Text("No game statistics at this time. Please check back later.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                        .offset(y: -50)
                                }
                            }
                            
                            
                            
                            Spacer()
                        }.padding([.all], 20)
                    }
                    .ignoresSafeArea(.top)
                    Spacer()
                }
            }
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task(repeatingEvery: .seconds(10)) {
            async let stats = downloadBaseballGameTeamStatsData(gameID: game.gameID)
            async let info = downloadGameInfo(gameID: game.gameID, sport: .royals)

            gameTeamStats = await stats
            gameInfo = await info
        }
    }
}

struct SoccerGameDetailView: View {
    @Environment(\.containerSize) private var containerSize

    @Environment(\.dismiss) private var dismiss
    var game: Game
    var teamColor: Color
    @State private var gameTeamStats = SoccerGameTeamStats.placeholderPair
    @State private var gameInfo = GameInfo.empty
    var teamLogo: String
    
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {//?USED TO TAKE UP ALL SPACE?//
                    HStack() {
                        Spacer()
                    }
                    
                    Image("soccerField")
                        .aspectRatio(contentMode: .fill)
                        .frame(width: containerSize.width, height: 200)
                        .clipShape(.rect(cornerRadius: 10))
                    
                    Rectangle()
                        .foregroundStyle(Color(hexString: gameInfo.gameColor))
                        .background(Color(uiColor: .black))//LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom))
                        .opacity(0.6)
                        .frame(width: containerSize.width, height: 200)
                        .clipShape(.rect(cornerRadius: 10))
                    
                    //GAME DETAILS
                    VStack(spacing: 0) {
                        //DISMISS BUTTON
                        Button(action: {
                            dismiss()
                        }) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: 100, height: 5)
                                .foregroundStyle(Color(uiColor: .white))
                                .opacity(0.7)
                        }.padding([.top, .trailing, .leading, .bottom], 10)
                        
                        
                        
                        Text(game.competitionName)
                            .fontWeight(.bold)
                            .font(.system(size: 25))
                            .minimumScaleFactor(0.2)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.top, 5)
                        
                        Spacer()
                        
                        
                        Text(game.time)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Text(game.date)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Text(game.channel)
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                        
                        Spacer()
                        
                        Text("\(game.location)")
                            .fontWeight(.bold)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.bottom, 10)
                            .minimumScaleFactor(0.2)
                    }.padding(.horizontal, 15)
                }.frame(height: 200)
                
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: (containerSize.width - 25), height: 600)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                        
                        VStack(alignment: .center, spacing: 15) {
                            if(game.cancelled) {
                                Spacer()
                                
                                Text("This game has been canceled.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(uiColor: .systemGray))
                                    .fontWeight(.bold)
                                    .minimumScaleFactor(0.5)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            } else {
                                if(game.dateAsDate <= Date()) {
                                    HStack(alignment: .top) {
                                        if(game.gameHome) {
                                            HStack() {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    //HOME TEAM PHOTO
                                                    Image("sporting")
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text("Kansas City")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                
                                                
                                                VStack(alignment: .center) {
                                                    Text("\(gameTeamStats[0].score) - \(gameTeamStats[0].opponentScore)")
                                                        .font(.system(size: 30))
                                                        //.foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                    
                                                    if(game.completed) {
                                                        Text("Final")
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
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                
                                                
                                                VStack(alignment: .trailing, spacing: 5) {
                                                    //AWAY TEAM PHOTO
                                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                                            Image("blankTeam")
                                                                .resizable()
                                                    }
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text(game.opponent)
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                            }
                                        } else {
                                            HStack() {
                                                VStack(alignment: .leading, spacing: 5) {
                                                    //HOME TEAM PHOTO
                                                    RemoteImage(url: URL(string: game.opponentLogo)) {
                                                            Image("blankTeam")
                                                                .resizable()
                                                    }
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text(game.opponent)
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                                                
                                                VStack(alignment: .center) {
                                                    Text("\(gameTeamStats[0].opponentScore) - \(gameTeamStats[0].score)")
                                                        .font(.system(size: 30))
                                                        //.foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                    
                                                    if(game.completed) {
                                                        Text("Final")
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
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .center)
                                                
                                                //AWAY TEAM PHOTO
                                                VStack(alignment: .trailing, spacing: 5) {
                                                    //PLAYER PHOTO
                                                    Image("sporting")
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 50, height: 50)
                                                    
                                                    Text("Kansas City")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(Color(uiColor: .systemGray))
                                                        .fontWeight(.bold)
                                                }.frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .trailing)
                                            }
                                        }
                                    }.ignoresSafeArea()
                                    /*
                                     Group {
                                     StatRowView(title: "Field Goals", homeStat: gameTeamStats[1].fieldGoals.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].fieldGoals.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Field Goal %", homeStat: "\(Int(gameTeamStats[1].fieldGoalPct))%", awayStat: "\(Int(gameTeamStats[0].fieldGoalPct))%")
                                     
                                     StatRowView(title: "Three Points", homeStat: gameTeamStats[1].threePoints.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].threePoints.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Three Point %", homeStat: "\(Int(gameTeamStats[1].threePointPct))%", awayStat: "\(Int(gameTeamStats[0].threePointPct))%")
                                     
                                     StatRowView(title: "Free Throws", homeStat: gameTeamStats[1].freeThrows.replacingOccurrences(of: "-", with: "/"), awayStat: gameTeamStats[0].freeThrows.replacingOccurrences(of: "-", with: "/"))
                                     
                                     StatRowView(title: "Free Throw %", homeStat: "\(Int(gameTeamStats[1].freeThrowPct))%", awayStat: "\(Int(gameTeamStats[0].freeThrowPct))%")
                                     
                                     StatRowView(title: "Offensive Rebounds", homeStat: "\(gameTeamStats[1].offensiveRebounds)", awayStat: "\(gameTeamStats[0].offensiveRebounds)")
                                     
                                     StatRowView(title: "Defensive Rebounds", homeStat: "\(gameTeamStats[1].defensiveRebounds)", awayStat: "\(gameTeamStats[0].defensiveRebounds)")
                                     
                                     StatRowView(title: "Assists", homeStat: "\(gameTeamStats[1].assists)", awayStat: "\(gameTeamStats[0].assists)")
                                     
                                     StatRowView(title: "Blocks", homeStat: "\(gameTeamStats[1].blocks)", awayStat: "\(gameTeamStats[0].blocks)")
                                     }
                                     
                                     Group {
                                     StatRowView(title: "Steals", homeStat: "\(gameTeamStats[1].steals)", awayStat: "\(gameTeamStats[0].steals)")
                                     
                                     StatRowView(title: "Turnovers", homeStat: "\(gameTeamStats[1].turnOvers)", awayStat: "\(gameTeamStats[0].turnOvers)")
                                     
                                     StatRowView(title: "Fouls", homeStat: "\(gameTeamStats[1].fouls)", awayStat: "\(gameTeamStats[0].fouls)")
                                     }
                                     */
                                } else {
                                    
                                    Spacer()
                                    
                                    Text("No game statistics at this time. Please check back later.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(uiColor: .systemGray))
                                        .fontWeight(.bold)
                                        .minimumScaleFactor(0.5)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                        .offset(y: -50)
                                }
                            }
                            
                            
                            
                            Spacer()
                        }.padding([.all], 20)
                    }
                    .ignoresSafeArea(.top)
                    Spacer()
                }
            }
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task(repeatingEvery: .seconds(10)) {
            async let stats = downloadSoccerGameTeamStatsData(gameID: game.gameID)
            async let info = downloadGameInfo(gameID: game.gameID, sport: .sporting)

            gameTeamStats = await stats
            gameInfo = await info
        }
    }
}

