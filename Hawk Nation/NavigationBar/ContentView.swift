//
//  ContentView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/23/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation
import CoreData

struct ContentView: View {
    
    var jayhawkArticles: [News]
    var chiefsArticles: [News]
    var sportingArticles: [News]
    var royalsArticles: [News]
    
    var chiefsGames: [Game]
    var jayhawkGames: [Game]
    var sportingGames: [Game]
    var royalsGames: [Game]

    @State var chiefsPlayers: [FootBallPlayer]
    @State var jayhawkPlayers: [BasketballPlayer]
    @State var sportingPlayers: [SoccerPlayer]
    @State var royalsPlayers: [BaseballPlayer]
    
    var jayhawkGamePointer: Int
    var chiefsGamePointer: Int
    var sportingGamePointer: Int
    var royalsGamePointer: Int
    
    var body: some View {
        TabView {
            NavigationView() {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
                        .edgesIgnoringSafeArea(.top)
                    Image("jayhawk")
                        .edgesIgnoringSafeArea(.top)
                        .opacity(0.5)
                    Text("Kansas Jayhawks")
                        .fontWeight(.bold)
                        .font(.system(size: 35))
                        .foregroundColor(Color.white)
                        .offset(x: -30, y: -50)
                    JayhawksHome(articles: jayhawkArticles, players: jayhawkPlayers, games: jayhawkGames, nextGame: jayhawkGamePointer)
                }
            }
            .tabItem {
                Image("jayhawkTab")
                Text("Jayhawks")
            }
            .tag(1)
            
            NavigationView() {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 227/255, green: 24/255, blue: 55/255, alpha: 1.00)))
                        .edgesIgnoringSafeArea(.top)
                    Image("chiefs")
                        .edgesIgnoringSafeArea(.top)
                        .opacity(0.5)
                    Text("Kansas City Chiefs")
                        .fontWeight(.bold)
                        .font(.system(size: 35))
                        .foregroundColor(Color.white)
                        .offset(x: -22, y: -50)
                    
                    ChiefsHome(articles: chiefsArticles, players: chiefsPlayers, games: chiefsGames, nextGame: chiefsGamePointer)
                }
            }
            .tabItem {
                Image("chiefsTab")
                Text("Chiefs")
            }.tag(2)
            
            NavigationView() {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 70/255, blue: 135/255, alpha: 1.00)))
                        .edgesIgnoringSafeArea(.top)
                    Image("royals")
                        .edgesIgnoringSafeArea(.top)
                        .opacity(0.5)
                    
                    Text("Kansas City Royals")
                        .fontWeight(.bold)
                        .font(.system(size: 35))
                        .foregroundColor(Color.white)
                        .offset(x: -22, y: -50)
                    
                    RoyalsHome(articles: royalsArticles, players: royalsPlayers, games: royalsGames, nextGame: royalsGamePointer)
                }
            }
            .tabItem {
                Image("royalsTab")
                Text("Royals")
            }.tag(3)
            
            NavigationView() {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00)))
                        .edgesIgnoringSafeArea(.top)
                    Image("sporting")
                        .edgesIgnoringSafeArea(.top)
                        .opacity(0.5)
                    
                    Text("Sporting Kansas City")
                        .fontWeight(.bold)
                        .font(.system(size: 35))
                        .foregroundColor(Color.white)
                        .offset(x: -5, y: -50)
                    
                    SportingHome(articles: sportingArticles, players: sportingPlayers, games: sportingGames, nextGame: sportingGamePointer)
                }
            }
            .tabItem {
                Image("sportingTab")
                Text("Sporting")
            }.tag(4)
        }
    }
}
