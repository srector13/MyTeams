//
//  PlayerDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation

struct BasketballPlayerDetailView: View {
    @Environment(\.containerSize) private var containerSize

    var player: BasketballPlayer
    @Environment(\.dismiss) private var dismiss
    @State var pickerSelectedItem = 0
    @State var playerStats = BasketballPlayerStats(gamesPlayed: 0, avgMinutes: 0, fieldGoalPct: 0, threePointFieldGoalPct: 0, freeThrowPct: 0, avgOffensiveRebounds: 0, avgDefensiveRebounds: 0, avgRebounds: 0, avgAssists: 0, avgBlocks: 0, avgSteals: 0, avgFouls: 0, avgTurnovers: 0, avgPoints: 0)
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundStyle(Color(red: 0 / 255, green: 81 / 255, blue: 186 / 255))
                        .frame(height: 40)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(Color(red: 0 / 255, green: 81 / 255, blue: 186 / 255))
                    
                    //JAYHAWK LOGO
                    Team.jayhawks.logoImage
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)
                        .frame(width: 300, height: 300)
                    
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
                        
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            
                            Text(player.number)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            .opacity(0.5)
                        }
                        
                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        
                        //SELECTOR VIEW
                        ZStack() {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(height: 30)
                            
                            
                            HStack(spacing: 0) {
                                
                                Button(action: {
                                    pickerSelectedItem = 0
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 0) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("About")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                                .opacity(0.8)
                                            Text("About")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                                
                                Button(action: {
                                    pickerSelectedItem = 1
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 1) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .opacity(0.8)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                            }
                            
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .padding([.bottom, .leading, .trailing], 10)
                    }
                }
                
                
                VStack(spacing: 0) {
                    //PLAYER BIO
                    if(pickerSelectedItem == 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 240)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                //ROW 1
                                HStack(alignment: .center) {
                                    BioView(title: "Position", info: player.position)
                                    Spacer()
                                    BioView(title: "Class", info: player.grade)
                                    Spacer()
                                    BioView(title: "Status", info: player.status)
                                    
                                }
                                
                                //ROW 2
                                HStack(alignment: .center) {
                                    BioView(title: "Height", info: player.height)
                                    Spacer()
                                    BioView(title: "Weight", info: player.weight)
                                    Spacer()
                                    BioView(title: "HomeTown", info: player.hometown)
                                }
                                Spacer()
                            }.padding(.all, 20)
                        }
                        .ignoresSafeArea(.top)
                    } else if(pickerSelectedItem == 1) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                //ROW 1
                                HStack(alignment: .center) {
                                    StatView(title: "Games Played", info: "\(playerStats.gamesPlayed)")
                                    Spacer()
                                    StatView(title: "Average Minutes", info: String(format: "%.1f", playerStats.avgMinutes))
                                    Spacer()
                                    StatView(title: "Average Points", info: String(format: "%.1f", playerStats.avgPoints))
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
                                    StatView(title: "Average Rebounds", info: String(format: "%.1f", playerStats.avgRebounds))
                                    Spacer()
                                    StatView(title: "Avg. Defensive Rebounds", info: String(format: "%.1f", playerStats.avgDefensiveRebounds))
                                    Spacer()
                                    StatView(title: "Avg. Offensive Rebounds", info: String(format: "%.1f", playerStats.avgOffensiveRebounds))
                                }
                                
                                //ROW 4
                                HStack(alignment: .center) {
                                    StatView(title: "Average Assists", info: String(format: "%.1f", playerStats.avgAssists))
                                    Spacer()
                                    StatView(title: "Average Blocks", info: String(format: "%.1f", playerStats.avgBlocks))
                                    Spacer()
                                    StatView(title: "Average Steals", info: String(format: "%.1f", playerStats.avgSteals))
                                }
                                
                                //ROW 5
                                HStack(alignment: .center) {
                                    StatView(title: "Average Fouls", info: String(format: "%.1f", playerStats.avgFouls))
                                    Spacer()
                                    StatView(title: "Average Turnovers", info: String(format: "%.1f", playerStats.avgTurnovers))
                                    Spacer()
                                    StatView(title: "", info: " ")
                                }
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                    }
                    Spacer()
                }
            }
            
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task {
            playerStats = await downloadBasketballPlayerStats(playerID: player.playerID)
        }
    }
}

struct FootballPlayerDetailView: View {
    @Environment(\.containerSize) private var containerSize

    var player: FootBallPlayer
    var teamColor: Color
    @Environment(\.dismiss) private var dismiss
    @State var pickerSelectedItem = 0
    @State var playerStats = FootballPlayerStats.empty
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundStyle(teamColor)
                        .frame(height: 40)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(teamColor)
                    
                    //CHIEFS LOGO
                    Team.chiefs.logoImage
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)
                        .frame(width: 300, height: 300)
                    
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
                        
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            
                            Text(player.number)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            .opacity(0.5)
                        }
                        
                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        
                        //SELECTOR VIEW
                        ZStack() {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(height: 30)
                            
                            
                            HStack(spacing: 0) {
                                
                                Button(action: {
                                    pickerSelectedItem = 0
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 0) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("About")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                                .opacity(0.8)
                                            Text("About")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                                
                                Button(action: {
                                    pickerSelectedItem = 1
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 1) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .opacity(0.8)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                            }
                            
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .padding([.bottom, .leading, .trailing], 10)
                    }
                }
                
                
                VStack(spacing: 0) {
                    //PLAYER BIO
                    if(pickerSelectedItem == 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 360)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                //ROW 1
                                HStack(alignment: .center) {
                                    BioView(title: "Position", info: player.position)
                                    Spacer()
                                    BioView(title: "Debut Year", info: player.debutYear)
                                    Spacer()
                                    BioView(title: "College", info: player.college)
                                    
                                }
                                
                                //ROW 2
                                HStack(alignment: .center) {
                                    BioView(title: "HomeTown", info: player.hometown)
                                    Spacer()
                                    BioView(title: "Height", info: player.height)
                                    Spacer()
                                    BioView(title: "Weight", info: player.weight)
                                }
                                
                                //ROW 3
                                HStack(alignment: .center) {
                                    BioView(title: "Age", info: player.age)
                                    Spacer()
                                    BioView(title: "", info: " ")
                                    Spacer()
                                    BioView(title: "", info: " ")
                                }
                                Spacer()
                            }.padding(.all, 20)
                        }
                        .ignoresSafeArea(.top)
                    } else if(pickerSelectedItem == 1) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 680)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .center, spacing: 15) {
                                Spacer()
                                Text("Statistics are not available for this team yet.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(uiColor: .systemGray))
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                    }
                    Spacer()
                }
            }
            
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)

    }
}

struct BaseballPlayerDetailView: View {
    @Environment(\.containerSize) private var containerSize

    var player: BaseballPlayer
    var teamColor: Color
    @Environment(\.dismiss) private var dismiss
    @State var pickerSelectedItem = 0
    @State var playerStats = BaseballPlayerStats(EarnedRunAverage: 0, wins: 0, losses: 0, saves: 0, saveOpportunities: 0, gamesPlayed: 0, gamesStarted: 0, completeGames: 0, innings: 0.0, hits: 0, runs: 0, earnedRuns: 0, homeRuns: 0, walks: 0, strikeouts: 0, opponentAvg: 0.0, AtBats: 0, Runs: 0, Hits: 0, Doubles: 0, Triples: 0, HomeRuns: 0, RBIs: 0.0, Walks: 0, HitByPitch: 0, Strikeouts: 0, StolenBases: 0, CaughtStealing: 0, Avg: 0.0, OnBasePct: 0.0, SlugAvg: 0.0, OPS: 0.0)
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundStyle(teamColor)
                        .frame(height: 40)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(teamColor)
                    
                    //ROYALS LOGO
                    Team.royals.logoImage
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)
                        .frame(width: 300, height: 300)
                    
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
                        
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            
                            Text(player.number)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            .opacity(0.5)
                        }
                        
                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        
                        //SELECTOR VIEW
                        ZStack() {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(height: 30)
                            
                            
                            HStack(spacing: 0) {
                                
                                Button(action: {
                                    pickerSelectedItem = 0
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 0) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("About")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                                .opacity(0.8)
                                            Text("About")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                                
                                Button(action: {
                                    pickerSelectedItem = 1
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 1) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .opacity(0.8)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                            }
                            
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .padding([.bottom, .leading, .trailing], 10)
                    }
                }
                
                
                VStack(spacing: 0) {
                    //PLAYER BIO
                    if(pickerSelectedItem == 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 360)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                //ROW 1
                                HStack(alignment: .center) {
                                    BioView(title: "Position", info: player.position)
                                    Spacer()
                                    BioView(title: "Home Town", info: player.hometown)
                                    Spacer()
                                    BioView(title: "College", info: player.college)
                                    
                                }
                                
                                //ROW 2
                                HStack(alignment: .center) {
                                    BioView(title: "Age", info: player.age)
                                    Spacer()
                                    BioView(title: "Debut Year", info: player.debutYear)
                                    Spacer()
                                    BioView(title: "Height", info: player.height)
                                    
                                    
                                }
                                
                                //ROW 3
                                HStack(alignment: .center) {
                                    BioView(title: "Weight", info: player.weight)
                                    Spacer()
                                    BioView(title: "Batting Hand", info: player.batHand)
                                    Spacer()
                                    BioView(title: "Throwing Hand", info: player.throwHand)
                                }
                                
                                Spacer()
                            }.padding(.all, 20)
                        }
                        .ignoresSafeArea(.top)
                    } else if(pickerSelectedItem == 1) {
                        if(player.position.contains("Pitcher")) {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: (containerSize.width - 25), height: 720)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    //ROW 1
                                    HStack(alignment: .center) {
                                        StatView(title: "Games Played", info: "\(playerStats.gamesPlayed)")
                                        Spacer()
                                        StatView(title: "Games Started", info: "\(playerStats.gamesStarted)")
                                        Spacer()
                                        StatView(title: "Complete Games", info: "\(playerStats.completeGames)")
                                    }
                                    
                                    //ROW 2
                                    HStack(alignment: .center) {
                                        StatView(title: "Innings Pitched", info: "\(playerStats.innings)")
                                        Spacer()
                                        StatView(title: "Wins", info: "\(playerStats.wins)")
                                        Spacer()
                                        StatView(title: "Losses", info: "\(playerStats.losses)")
                                    }
                                    
                                    //ROW 3
                                    HStack(alignment: .center) {
                                        StatView(title: "Saves", info: "\(playerStats.saves)")
                                        Spacer()
                                        StatView(title: "Save Opportunites", info: "\(playerStats.saveOpportunities)")
                                        Spacer()
                                        StatView(title: "Opp. Batting Avg.", info: "\(playerStats.opponentAvg)")
                                    }
                                    
                                    //ROW 4
                                    HStack(alignment: .center) {
                                        StatView(title: "Runs", info: "\(playerStats.runs)")
                                        Spacer()
                                        StatView(title: "Earned Run Avg.", info: "\(playerStats.EarnedRunAverage)")
                                        Spacer()
                                        StatView(title: "Earned Runs", info: "\(playerStats.earnedRuns)")
                                    }
                                    
                                    //ROW 5
                                    HStack(alignment: .center) {
                                        StatView(title: "Hits", info: "\(playerStats.hits)")
                                        Spacer()
                                        StatView(title: "Home Runs", info: "\(playerStats.homeRuns)")
                                        Spacer()
                                        StatView(title: "Strikeouts", info: "\(playerStats.strikeouts)")
                                    }
                                    
                                    //ROW 6
                                    HStack(alignment: .center) {
                                        StatView(title: "Walks", info: "\(playerStats.walks)")
                                        Spacer()
                                        StatView(title: "", info: " ")
                                        Spacer()
                                        StatView(title: "", info: " ")
                                    }
                                    
                                    Spacer()
                                }.padding([.all], 20)
                            }
                            .ignoresSafeArea(.top)
                        } else {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: (containerSize.width - 25), height: 600)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    //ROW 1
                                    HStack(alignment: .center) {
                                        StatView(title: "At Bats", info: "\(playerStats.AtBats)")
                                        Spacer()
                                        StatView(title: "Runs", info: "\(playerStats.Runs)")
                                        Spacer()
                                        StatView(title: "Hits", info: "\(playerStats.Hits)")
                                    }
                                    
                                    //ROW 2
                                    HStack(alignment: .center) {
                                        StatView(title: "Doubles", info: "\(playerStats.Doubles)")
                                        Spacer()
                                        StatView(title: "Triples", info: "\(playerStats.Triples)")
                                        Spacer()
                                        StatView(title: "Home Runs", info: "\(playerStats.HomeRuns)")
                                    }
                                    
                                    //ROW 3
                                    HStack(alignment: .center) {
                                        StatView(title: "RBIs", info: "\(playerStats.RBIs)")
                                        Spacer()
                                        StatView(title: "Walks", info: "\(playerStats.Walks)")
                                        Spacer()
                                        StatView(title: "Hit By Pitches", info: "\(playerStats.HitByPitch)")
                                    }
                                    
                                    //ROW 4
                                    HStack(alignment: .center) {
                                        StatView(title: "Strikeouts", info: "\(playerStats.Strikeouts)")
                                        Spacer()
                                        StatView(title: "Stolen Bases", info: "\(playerStats.StolenBases)")
                                        Spacer()
                                        StatView(title: "Caught Stealing", info: "\(playerStats.CaughtStealing)")
                                    }
                                    
                                    //ROW 5
                                    HStack(alignment: .center) {
                                        StatView(title: "OPS", info: "\(playerStats.OPS)")
                                        Spacer()
                                        StatView(title: "", info: " ")
                                        Spacer()
                                        StatView(title: "", info: " ")
                                    }                                        
                                    Spacer()
                                }.padding([.all], 20)
                            }
                            .ignoresSafeArea(.top)
                        }
                    }
                    Spacer()
                }
            }
            
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task {
            playerStats = await downloadBaseballPlayerStats(
                playerID: player.playerID,
                playerPosition: player.position
            )
        }
    }
}

struct SoccerPlayerDetailView: View {
    @Environment(\.containerSize) private var containerSize

    var player: SoccerPlayer
    var teamColor: Color
    @Environment(\.dismiss) private var dismiss
    
    @State var pickerSelectedItem = 0
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundStyle(teamColor)
                        .frame(height: 40)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(teamColor)
                    
                    //SPORTING LOGO
                    Team.sporting.logoImage
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)
                        .frame(width: 300, height: 300)
                    
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
                        
                        //?USED TO TAKE UP ALL SPACE?//
                        HStack() {
                            Spacer()
                        }
                        
                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            
                            Text(player.number)
                            .fontWeight(.bold)
                            .font(.system(size: 35))
                            .foregroundStyle(Color.white)
                            .opacity(0.5)
                        }
                        
                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                        
                        //SELECTOR VIEW
                        ZStack() {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(height: 30)
                            
                            
                            HStack(spacing: 0) {
                                
                                Button(action: {
                                    pickerSelectedItem = 0
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 0) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("About")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                                .opacity(0.8)
                                            Text("About")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                                
                                Button(action: {
                                    pickerSelectedItem = 1
                                }) {
                                    
                                    
                                    if(pickerSelectedItem == 1) {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    } else {
                                        ZStack(alignment: .center) {
                                            Rectangle()
                                                .foregroundStyle(Color(uiColor: .systemBackground))
                                                .frame(height: 30)
                                                .opacity(0.8)
                                                .clipped()
                                            Text("Statistics")
                                        }
                                    }
                                    
                                }.buttonStyle(.plain)
                            }
                            
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .padding([.bottom, .leading, .trailing], 10)
                    }
                }
                
                
                VStack(spacing: 0) {
                    //PLAYER BIO
                    if(pickerSelectedItem == 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 240)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                //ROW 1
                                HStack(alignment: .center) {
                                    BioView(title: "Position", info: player.position)
                                    Spacer()
                                    BioView(title: "Age", info: player.age)
                                    Spacer()
                                    BioView(title: "Birth Country", info: player.birthPlace)
                                    
                                }
                                
                                //ROW 2
                                HStack(alignment: .center) {
                                    BioView(title: "Citizenship", info: player.citizenshipCountry)
                                    Spacer()
                                    BioView(title: "Height", info: player.height)
                                    Spacer()
                                    BioView(title: "Weight", info: player.weight)
                                }
                                Spacer()
                            }.padding(.all, 20)
                        }
                        .ignoresSafeArea(.top)
                    } else if(pickerSelectedItem == 1) {
                        if(player.position.contains("Goalkeeper")) {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: (containerSize.width - 25), height: 360)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    //ROW 1
                                    HStack(alignment: .center) {
                                        StatView(title: "Starts", info: "\(player.appearances)")
                                        Spacer()
                                        StatView(title: "Shots Faced", info: "\(player.shotsFaced)")
                                        Spacer()
                                        StatView(title: "Goals Saved", info: "\(player.saves)")
                                    }
                                    
                                    HStack(alignment: .center) {
                                        StatView(title: "Goals Conceded", info: "\(player.goalsConceded)")
                                        Spacer()
                                        StatPercentageView(progress: CGFloat(Double(player.saves)/Double(player.shotsFaced)), color: UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00), title: "Save Percentage")
                                            .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                                        Spacer()
                                        StatPercentageView(progress: CGFloat(Double(player.goalsConceded)/Double(player.shotsFaced)), color: UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00), title: "Conceded Percentage")
                                            .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                                    }
                                    
                                    HStack(alignment: .center) {
                                        StatView(title: "Fouls Committed", info: "\(player.fouls)")
                                        Spacer()
                                        StatView(title: "Yellow Cards", info: "\(player.yellowCards)")
                                        Spacer()
                                        StatView(title: "Red Cards", info: "\(player.redCards)")
                                    }
                                    Spacer()
                                }.padding([.all], 20)
                            }
                            .ignoresSafeArea(.top)
                        } else {
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 20)
                                    .frame(width: (containerSize.width - 25), height: 600)
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    //ROW 1
                                    HStack(alignment: .center) {
                                        StatView(title: "Games Started", info: "\(player.appearances)")
                                        Spacer()
                                        StatView(title: "Games Played", info: "\(player.subAppearances + player.appearances)")
                                        Spacer()
                                        StatView(title: "Goal Assists", info: "\(player.goalAssists)")
                                    }
                                    
                                    //ROW 2
                                    HStack(alignment: .center) {
                                        StatView(title: "Total Shots", info: "\(player.totalShots)")
                                        Spacer()
                                        StatView(title: "Shots On Target", info: "\(player.shotsOnTarget)")
                                        Spacer()
                                        StatView(title: "Total Goals", info: "\(player.totalGoals)")
                                    }
                                    
                                    //ROW 3
                                    HStack(alignment: .center) {
                                        StatPercentageView(progress: CGFloat(Double(player.totalGoals)/Double(player.totalShots)), color: UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00), title: "Goal Percentage")
                                            .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                                        Spacer()
                                        StatPercentageView(progress: CGFloat(Double(player.shotsOnTarget)/Double(player.totalShots)), color: UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00), title: "On Target Percentage")
                                            .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0))
                                        Spacer()
                                        StatView(title: "Own Goals", info: "\(player.ownGoals)")
                                    }
                                    
                                    
                                    //ROW 4
                                    HStack(alignment: .center) {
                                        StatView(title: "Offsides", info: "\(player.offsides)")
                                        Spacer()
                                        StatView(title: "Fouls Suffered", info: "\(player.foulsSuffered)")
                                        Spacer()
                                        StatView(title: "Fouls Committed", info: "\(player.fouls)")
                                    }
                                    
                                    //ROW 5
                                    HStack(alignment: .center) {
                                        StatView(title: "Yellow Cards", info: "\(player.yellowCards)")
                                        Spacer()
                                        StatView(title: "Red Cards", info: "\(player.redCards)")
                                        Spacer()
                                        StatView(title: "", info: " ")
                                    }
                                    Spacer()
                                }.padding([.all], 20)
                            }
                            .ignoresSafeArea(.top)
                        }
                    }
                    Spacer()
                }
            }
            
            Spacer()
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
    }
}
