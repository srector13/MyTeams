//
//  BasketballPlayerDetailView.swift
//  myTeams
//
//  Created by Stephen Rector on 11/30/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct BasketballPlayerDetailView2: View {
    var player: BasketballPlayer
    @State var playerStats = BasketballPlayerStats(gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0, freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0, avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0, avgTurnovers: 0, avgPoints: 0)
    
    var body: some View {
        VStack(spacing: 10) {
            BasketballPlayerBioView(player: player)
            BasketballPlayerStatView(player: player, playerStats: playerStats)
        }
    }
}

struct BasketballPlayerBioView: View {
    @Environment(\.dismiss) private var dismiss
    var player: BasketballPlayer
    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 20)
                    .foregroundStyle(Color(red: 0 / 255, green: 81 / 255, blue: 186 / 255))
                
                VStack(spacing: 0) {
                    //DISMISS BUTTON
                    Button(action: {
                        dismiss()
                    }) {
                        RoundedRectangle(cornerRadius: 20)
                        .frame(width: 100, height: 5)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                            .opacity(0.5)
                    }.padding([.top, .trailing, .leading, .bottom], 10)
                }
                
                HStack() {
                    VStack() {
                        Image("\(player.photo)")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(.circle)
                        Text("\(player.name)")
                            .fontWeight(.bold)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.white)
                    }
                    Spacer()
                    VStack() {
                        HStack {
                            VStack {
                                Text("\(player.number)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .frame(minWidth: 0, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Number")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.white)
                            }
                            VStack {
                                Text("\(player.position)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Position")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.white)
                            }
                            VStack {
                                Text("\(player.grade)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .frame(minWidth: 0, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Class")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.white)
                            }
                        }.frame(height: 50)
                        
                        Spacer()
                        
                        HStack {
                            VStack {
                                Text("\(player.height)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .frame(minWidth: 0, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Height")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.white)
                            }
                            VStack {
                                Text("\(player.weight)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Weight")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.white)
                            }
                            VStack {
                                Text("\(player.hometown)")
                                    .fontWeight(.bold)
                                    .font(.system(size: 20))
                                    .opacity(0.5)
                                    .foregroundStyle(Color.white)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)
                                    .multilineTextAlignment(.center)
                                    .frame(minWidth: 0, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
                                Text ("Home Town")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Color.white)
                            }
                        }.frame(height: 50)
                    }.frame(height: 120)
                }.padding()
                .padding(.top, 50)
            }//.ignoresSafeArea()
            .frame(height: 160)
        }
    }
}

struct BasketballPlayerStatView: View {
    var player: BasketballPlayer
    @State var playerStats = BasketballPlayerStats(gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0, freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0, avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0, avgTurnovers: 0, avgPoints: 0)
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                //ROW 1
                HStack(alignment: .center) {
                    StatView(title: "Games Played", info: "\(playerStats.gamesPlayed)")
                    Spacer()
                    StatView(title: "Average Minutes", info: "\(playerStats.avgMinutes)")
                    Spacer()
                    StatView(title: "Average Points", info: "\(playerStats.avgPoints)")
                }
                
                //ROW 2
                HStack(alignment: .center) {
                    StatPercentageView(progress: CGFloat(Double(playerStats.fieldGoalPct)/100), color: UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00), title: "Field Goal Percentage")
                        .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                    Spacer()
                    StatPercentageView(progress: CGFloat(Double(playerStats.threePointFieldGoalPct)/100), color: UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00), title: "3-Point Percentage")
                        .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                    Spacer()
                    StatPercentageView(progress: CGFloat(Double(playerStats.freeThrowPct)/100), color: UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00), title: "Free Throw Percentage")
                    .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                }

                //ROW 3
                HStack(alignment: .center) {
                    StatView(title: "Average Rebounds", info: "\(playerStats.avgRebounds)")
                    Spacer()
                    StatView(title: "Avg. Defensive Rebounds", info: "\(playerStats.avgDefensiveRebounds)")
                    Spacer()
                    StatView(title: "Avg. Offensive Rebounds", info: "\(playerStats.avgOffensiveRebounds)")
                }
                
                //ROW 4
                HStack(alignment: .center) {
                    StatView(title: "Average Assists", info: "\(playerStats.avgAssists)")
                    Spacer()
                    StatView(title: "Average Blocks", info: "\(playerStats.avgBlocks)")
                    Spacer()
                    StatView(title: "Average Steals", info: "\(playerStats.avgSteals)")
                }
                
                //ROW 5
                HStack(alignment: .center) {
                    StatView(title: "Average Fouls", info: "\(playerStats.avgFouls)")
                    Spacer()
                    StatView(title: "Average Turnovers", info: "\(playerStats.avgTurnovers)")
                    Spacer()
                    StatView(title: "", info: " ")
                }
                Spacer()
            }.padding([.all], 20)
        }
        .task {
            playerStats = await downloadBasketballPlayerStats(playerID: player.playerID)
        }
    }
}

#Preview {
    BasketballPlayerBioView(
        player: BasketballPlayer(
            playerID: "test", name: "Ochai Agbaji", number: "30", numberInt: 30,
            height: "6' 5\"", weight: "210 lbs", position: "Guard",
            grade: "Junior", hometown: "Kansas City, MO", photo: "blank",
            status: "Active", lastName: "Agbaji"
        )
    )
}
