//
//  SportingHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Combine

struct SportingHome: View {
    
    var loadingPlayers = [
        BasketballPlayer(playerID: "", name: "", number: "", numberInt: 1000, height: "", weight: "", position: "", grade: "", hometown: "", photo: "", status: "", lastName: ""),
        BasketballPlayer(playerID: "", name: "", number: "", numberInt: 1000, height: "", weight: "", position: "", grade: "", hometown: "", photo: "", status: "", lastName: ""),
        BasketballPlayer(playerID: "", name: "", number: "", numberInt: 1000, height: "", weight: "", position: "", grade: "", hometown: "", photo: "", status: "", lastName: ""),
        BasketballPlayer(playerID: "", name: "", number: "", numberInt: 1000, height: "", weight: "", position: "", grade: "", hometown: "", photo: "", status: "", lastName: ""),
        BasketballPlayer(playerID: "", name: "", number: "", numberInt: 1000, height: "", weight: "", position: "", grade: "", hometown: "", photo: "", status: "", lastName: "")
    ]
    var loadingGames = [
        Game(team: "", opponent: "", score: "", opponentScore: "", time: "", date: "", dateAsDate: Date(), opponentLogo: "", channel: "", location: "", gameHome: true, gameID: "", pointer: 0, gameWin: true, completed: true, competitionName: "", cancelled: true, postponed: true, gameClock: "", gamePeriod: "", gameHalftime: false),
        Game(team: "", opponent: "", score: "", opponentScore: "", time: "", date: "", dateAsDate: Date(), opponentLogo: "", channel: "", location: "", gameHome: true, gameID: "", pointer: 0, gameWin: true, completed: true, competitionName: "", cancelled: true, postponed: true, gameClock: "", gamePeriod: "", gameHalftime: false),
        Game(team: "", opponent: "", score: "", opponentScore: "", time: "", date: "", dateAsDate: Date(), opponentLogo: "", channel: "", location: "", gameHome: true, gameID: "", pointer: 0, gameWin: true, completed: true, competitionName: "", cancelled: true, postponed: true, gameClock: "", gamePeriod: "", gameHalftime: false),
        Game(team: "", opponent: "", score: "", opponentScore: "", time: "", date: "", dateAsDate: Date(), opponentLogo: "", channel: "", location: "", gameHome: true, gameID: "", pointer: 0, gameWin: true, completed: true, competitionName: "", cancelled: true, postponed: true, gameClock: "", gamePeriod: "", gameHalftime: false),
        Game(team: "", opponent: "", score: "", opponentScore: "", time: "", date: "", dateAsDate: Date(), opponentLogo: "", channel: "", location: "", gameHome: true, gameID: "", pointer: 0, gameWin: true, completed: true, competitionName: "", cancelled: true, postponed: true, gameClock: "", gamePeriod: "", gameHalftime: false)
    ]
    var loadingArticles = [
        News(author: "", title: "", articleDescription: "", url: URL(string: "www.google.com")!, urlToImage: URL(string: "www.google.com")!, publishedAt: Date(), content: "", source: ""),
        News(author: "", title: "", articleDescription: "", url: URL(string: "www.google.com")!, urlToImage: URL(string: "www.google.com")!, publishedAt: Date(), content: "", source: ""),
        News(author: "", title: "", articleDescription: "", url: URL(string: "www.google.com")!, urlToImage: URL(string: "www.google.com")!, publishedAt: Date(), content: "", source: ""),
        News(author: "", title: "", articleDescription: "", url: URL(string: "www.google.com")!, urlToImage: URL(string: "www.google.com")!, publishedAt: Date(), content: "", source: ""),
        News(author: "", title: "", articleDescription: "", url: URL(string: "www.google.com")!, urlToImage: URL(string: "www.google.com")!, publishedAt: Date(), content: "", source: "")
    ]
    
    @State var currentArticle: News? = nil
    @State var currentPlayer: SoccerPlayer? = nil
    @State var currentGame: Game? = nil
    @State var articles: [News]
    @State var players: [SoccerPlayer]
    @State var playersUnfiltered: [SoccerPlayer]
    @State var games: [Game]
    @State var currentGameInfo = GameInfo(venueImage: "", city: "", state: "", capacity: "", attendance: "", gameColor: "")
    @State var sortBy = "name"
    
    @State var nextGame: Int
    @State var teamColor = Color(UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00))
    
    //Timer to reload ever 60 seconds
    let timer = Timer.publish(every: 60, on: .current, in: .common).autoconnect()
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 5) {

                //Roster
                VStack(alignment: .leading) {
                    HStack() {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color(UIColor.systemGray))
                        
                        Text("Roster")
                            .font(.system(size: 20))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                        
                        Spacer()
                        
                        //Filter
                        Menu(content: {
                            //All Filter (Reset)
                            Button(action: {players = playersUnfiltered}, label: {
                                Text("All")
                            })
                            Button(action: {
                                    players = playersUnfiltered
                                    players = players.filter{$0.position == "Goalkeeper"}}, label: {
                                Text("Goalkeeper")
                            })
                            Button(action: {
                                    players = playersUnfiltered
                                    players = players.filter{$0.position == "Defender"}}, label: {
                                Text("Defense")
                            })
                            Button(action: {
                                    players = playersUnfiltered
                                    players = players.filter{$0.position == "Midfielder"}}, label: {
                                Text("Midfield")
                            })
                            Button(action: {
                                    players = playersUnfiltered
                                    players = players.filter{$0.position == "Forward"}}, label: {
                                Text("Attacker")
                            })
                        }, label: {
                            Image(systemName: "line.horizontal.3.decrease.circle")
                                .foregroundColor(Color(UIColor.systemGray))
                                .font(.system(size: 20))
                        }).padding(.horizontal, 5)
                        
                        //Sort
                        Menu(content: {
                            Button(action: {players = players.sorted(by: { $0.lastName < $1.lastName })
                                            playersUnfiltered = playersUnfiltered.sorted(by: { $0.lastName < $1.lastName })
                                            sortBy = "name"}, label: {
                                Text("Name")
                            })
                            Button(action: {players = players.sorted(by: { $0.numberInt < $1.numberInt })
                                            playersUnfiltered = playersUnfiltered.sorted(by: { $0.numberInt < $1.numberInt  })
                                            sortBy = "number"}, label: {
                                Text("Number")
                            })
                            Button(action: {players = players.sorted(by: { $0.position < $1.position })
                                            playersUnfiltered = playersUnfiltered.sorted(by: { $0.position < $1.position })
                                            sortBy = "position"}, label: {
                                Text("Position")
                            })
                            
                        }, label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundColor(Color(UIColor.systemGray))
                                .font(.system(size: 20))
                        }).padding(.horizontal, 5)
                    }.padding([.leading, .top, .trailing])
                    
                    if(players.count > 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack() {
                                ForEach(players) { player in
                                    SoccerPlayerView(player: player, state: sortBy)
                                        .padding(.leading, 10)
                                        .padding(.bottom, 15)
                                        .onTapGesture {
                                            self.currentPlayer = player
                                        }
                                        .sheet(item: $currentPlayer) { currentPlayer in
                                            SoccerPlayerDetailView(player: currentPlayer, teamColor: teamColor)
                                        }
                                }
                                
                                //SPACING AT END OF PLAYER VIEW
                                Rectangle()
                                    .fill(Color(UIColor.systemBackground))
                                    .frame(width: 10)
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack() {
                                ForEach(loadingPlayers) { player in
                                    PlayerView(player: player, state: sortBy)
                                        .padding(.leading, 10)
                                        .padding(.bottom, 15)
                                }
                                
                                //SPACING AT END OF PLAYER VIEW
                                Rectangle()
                                    .fill(Color(UIColor.systemBackground))
                                    .frame(width: 10)
                            }
                        }

                    }
                }.background(Color(UIColor.systemBackground))
                .padding(.top, 5)
                
                //Schedule
                VStack(alignment: .leading) {
                    HStack() {
                        Image(systemName: "calendar")
                            .foregroundColor(Color(UIColor.systemGray))
                        
                        Text("Schedule")
                            .font(.system(size: 20))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                        
                        Spacer()
                        
                        Text("\(games.filter{$0.gameWin == true}.count)-\(games.filter{$0.gameWin == false}.count)")
                            .font(.system(size: 15))
                            .foregroundColor(Color(UIColor.systemGray))
                        
                    }.padding([.leading, .top, .trailing])
                    
                    if (games.count > 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            ScrollViewReader { scrollView in
                                HStack() {
                                    ForEach(games, id: \.self.pointer) { game in
                                        GameView(game: game, teamColor: teamColor, teamLogo: "sporting")
                                            .padding(.leading, 10)
                                            .id(game.pointer)
                                            .onTapGesture {
                                                downloadSoccerGameInfo(gameID: game.gameID, type: "sporting", completion: { info in
                                                    self.currentGame = game
                                                    self.currentGameInfo = info
                                                })
                                            }
                                            .sheet(item: $currentGame) { currentGame in
                                                SoccerGameDetailView(game: currentGame, teamColor: teamColor, gameInfo: currentGameInfo, teamLogo: "sporting")
                                            }
                                    }
                                    
                                    Rectangle()
                                        .fill(Color(UIColor.systemBackground))
                                        .frame(width: 10)
                                }
                                .onAppear() {
                                    scrollView.scrollTo(nextGame+2, anchor: .leading)
                                }
                                .frame(height: 160)
                                .padding([.leading, .bottom], 10)
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            ScrollViewReader { scrollView in
                                HStack() {
                                    ForEach(loadingGames) { game in
                                        LoadingGameView()
                                            .padding(.leading, 10)
                                            .id(game.pointer)
                                    }
                                    
                                    Rectangle()
                                        .fill(Color(UIColor.systemBackground))
                                        .frame(width: 10)
                                }
                                .frame(height: 160)
                                .padding([.leading, .bottom], 10)
                                .onAppear() {
                                    scrollView.scrollTo(1, anchor: .leading)
                                }
                            }
                        }
                    }
                }.background(Color(UIColor.systemBackground))
                
                //News
                VStack(alignment: .leading) {
                    HStack() {
                        Image(systemName: "book")
                            .foregroundColor(Color(UIColor.systemGray))
                        
                        Text("News")
                            .font(.system(size: 20))
                            .fontWeight(.bold)
                            
                            .foregroundColor(Color(UIColor.systemGray))
                        Spacer()
                        
                    }.padding([.leading, .top])
                    if (articles.isEmpty) {
                        VStack(alignment: .center, spacing: 10) {
                            ForEach(loadingArticles) { article in
                                LoadingNewsView()
                                
                            }
                        }.padding(.leading)

                        Rectangle()
                            .frame(width: UIScreen.main.bounds.width, height: 40)
                            .foregroundColor(Color(UIColor.systemBackground))
                    } else {
                        VStack(alignment: .center, spacing: 10) {
                            ForEach(articles) { article in
                                Button(action: {
                                    self.currentArticle = article
                                }) {
                                    NewsView(article: article)
                                        //   .padding(.leading, 10)
                                        .padding(.top)
                                    
                                }.buttonStyle(PlainButtonStyle())
                            }
                            .sheet(item: $currentArticle) { currentArticle in
                                NewsDetailView(article: currentArticle, color: teamColor)
                            }
                        }.padding(.leading)
                        
                        Rectangle()
                            .frame(width: UIScreen.main.bounds.width, height: 40)
                            .foregroundColor(Color(UIColor.systemBackground))
                    }
                }.background(Color(UIColor.systemBackground))
                
            }.frame(alignment: .leading)
             .background(Color(UIColor.systemGray5))
        }.background(Color(UIColor.systemGray5))
        .onAppear(perform: {
            //Download Chiefs Data
            downloadSoccerRoster(completion: { roster in
                self.players = roster
                self.playersUnfiltered = roster
            })
            downloadScheduleData2(queryURL: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/teams/186/schedule", teamName: "Kansas City", completion: { schedule in
                games = schedule
                nextGame = getNextSportingGame(schedule: games)
            })
            self.getSportingNews()
        })
    }
    
    func getSportingNews() {
        downloadNewsData(queryURL: "https://newsapi.org/v2/everything?q=+sporting+kc+mls&sortBy=publishedAt&apiKey=0322e83bd89e4ecf9ba6a354546d4d8e", completion: { newsArticles in
            self.articles = newsArticles
        })
    }
}

