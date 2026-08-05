//
//  ContentView2.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

// TabItems..
var tabItems = ["jayhawk","chiefs","royals","sporting"]

struct Home : View {
    @State var jayhawkArticles = [News]()
    @State var chiefsArticles = [News]()
    @State var sportingArticles = [News]()
    @State var royalsArticles = [News]()
    
    @State var chiefsGames = [Game]()
    @State var jayhawkGames = [Game]()
    @State var sportingGames = [Game]()
    @State var royalsGames = [Game]()
    
    @State var chiefsPlayers = [FootBallPlayer]()
    @State var jayhawkPlayers = [BasketballPlayer]()
    @State var sportingPlayers = [SoccerPlayer]()
    @State var royalsPlayers = [BaseballPlayer]()
    
    @State var jayhawksGamePointer = 0
    @State var chiefsGamePointer = 0
    @State var sportingGamePointer = 0
    @State var royalsGamePointer = 0
    
    @State var index = 0
    @State var centerX : CGFloat = 0
    
    // for sticky header view...
    @State var timeKU = Timer.publish(every: 0.1, on: .current, in: .tracking).autoconnect()
    @State var showKU = false
    @State var timeChiefs = Timer.publish(every: 0.1, on: .current, in: .tracking).autoconnect()
    @State var showChiefs = false
    @State var timeRoyals = Timer.publish(every: 0.1, on: .current, in: .tracking).autoconnect()
    @State var showRoyals = false
    @State var timeSporting = Timer.publish(every: 0.1, on: .current, in: .tracking).autoconnect()
    @State var showSporting = false
    
    @Environment(\.verticalSizeClass) var size
    
    init() {
          UIScrollView.appearance().bounces = false
       }
    
    var body: some View {
        
        VStack(spacing: 0){
            ZStack{
                //Jayhawks
                ZStack(alignment: .top, content: {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
                        .frame(height: 500)
                    
                    ScrollView(.vertical, showsIndicators: false, content: {
                        VStack{
                            GeometryReader{g in
                                Image("jayhawk")
                                    .resizable()
                                    .opacity(0.5)
                                    .frame(width: UIScreen.main.bounds.width - 50, height: UIScreen.main.bounds.width - 50)
                                    .offset(x: 50)
                                    .onReceive(self.timeKU) { (_) in
                                        // its not a timer...
                                        // for tracking the image is scrolled out or not...
                                        let y = g.frame(in: .global).minY
                                        
                                        if -y > (UIScreen.main.bounds.height / 4) - 50{
                                            withAnimation{
                                                self.showKU = true
                                            }
                                        }
                                        else{
                                            withAnimation{
                                                self.showKU = false
                                            }
                                        }
                                    }
                            }
                            // fixing default height...
                            .frame(height: UIScreen.main.bounds.height / 14 )
                            
                            VStack{
                                HStack(alignment: .bottom){
                                    Text("Kansas Jayhawks")
                                        .fontWeight(.bold)
                                        .font(.system(size: 35))
                                        .foregroundColor(.white)
                                        .padding(.leading, 15)
                                    Spacer()
                                }.ignoresSafeArea()
                                
                            JayhawksHome(articles: jayhawkArticles, players: jayhawkPlayers, playersUnfiltered: jayhawkPlayers, games: jayhawkGames, nextGame: jayhawksGamePointer)

                            }
                            .padding([.top, .horizontal])
                        }
                    })
                    
                    if self.showKU{
                        TopView(logoName: "jayhawk", teamName: "Kansas Jayhawks")
                    }
                })
                .edgesIgnoringSafeArea(.top)
                .opacity(self.index == 0 ? 1 : 0)
                
                
                //chiefs
                ZStack(alignment: .top, content: {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 227/255, green: 24/255, blue: 55/255, alpha: 1.00)))
                        .frame(height: 500)
                    
                    ScrollView(.vertical, showsIndicators: false, content: {
                        VStack{
                            GeometryReader{g in
                                Image("chiefs")
                                    .resizable()
                                    .opacity(0.5)
                                    .frame(width: UIScreen.main.bounds.width - 50, height: UIScreen.main.bounds.width - 50)
                                    .offset(x: 50)
                                    .onReceive(self.timeChiefs) { (_) in
                                        // its not a timer...
                                        // for tracking the image is scrolled out or not...
                                        let y = g.frame(in: .global).minY
                                        
                                        if -y > (UIScreen.main.bounds.height / 4) - 50{
                                            withAnimation{
                                                self.showChiefs = true
                                            }
                                        }
                                        else{
                                            withAnimation{
                                                self.showChiefs = false
                                            }
                                        }
                                    }
                            }
                            // fixing default height...
                            .frame(height: UIScreen.main.bounds.height / 14 )
                            
                            VStack{
                                HStack(alignment: .bottom){
                                    Text("Kansas City Chiefs")
                                        .fontWeight(.bold)
                                        .font(.system(size: 35))
                                        .foregroundColor(.white)
                                        .padding(.leading, 15)
                                    Spacer()
                                }.ignoresSafeArea()
                                

                                ChiefsHome(articles: chiefsArticles, players: chiefsPlayers, playersUnfiltered: chiefsPlayers, games: chiefsGames, nextGame: chiefsGamePointer)

                            }
                            .padding([.top, .horizontal])
                        }
                    })
                    
                    if self.showChiefs{
                        TopView(logoName: "chiefs", teamName: "Kansas City Chiefs")
                    }
                })
                .edgesIgnoringSafeArea(.top)
                .opacity(self.index == 1 ? 1 : 0)
                
                
                //royals
                ZStack(alignment: .top, content: {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 70/255, blue: 135/255, alpha: 1.00)))
                        .frame(height: 500)
                    
                    ScrollView(.vertical, showsIndicators: false, content: {
                        VStack{
                            GeometryReader{g in
                                Image("royals")
                                    .resizable()
                                    .opacity(0.5)
                                    .frame(width: UIScreen.main.bounds.width - 50, height: UIScreen.main.bounds.width - 50)
                                    .offset(x: 50)
                                    .onReceive(self.timeRoyals) { (_) in
                                        // its not a timer...
                                        // for tracking the image is scrolled out or not...
                                        let y = g.frame(in: .global).minY
                                        
                                        if -y > (UIScreen.main.bounds.height / 4) - 50{
                                            withAnimation{
                                                self.showRoyals = true
                                            }
                                        }
                                        else{
                                            withAnimation{
                                                self.showRoyals = false
                                            }
                                        }
                                    }
                            }
                            // fixing default height...
                            .frame(height: UIScreen.main.bounds.height / 14 )
                            
                            VStack{
                                HStack(alignment: .bottom){
                                    Text("Kansas City Royals")
                                        .fontWeight(.bold)
                                        .font(.system(size: 35))
                                        .foregroundColor(.white)
                                        .padding(.leading, 15)
                                    Spacer()
                                }.ignoresSafeArea()
                                

                                RoyalsHome(articles: royalsArticles, players: royalsPlayers, playersUnfiltered: royalsPlayers, games: royalsGames, nextGame: royalsGamePointer)

                            }
                            .padding([.top, .horizontal])
                        }
                    })
                    
                    if self.showRoyals{
                        TopView(logoName: "royals", teamName: "Kansas City Royals")
                    }
                })
                .edgesIgnoringSafeArea(.top)
                .opacity(self.index == 2 ? 1 : 0)
                
                //sporting
                ZStack(alignment: .top, content: {
                    Rectangle()
                        .foregroundColor(Color(UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00)))
                        .frame(height: 500)
                    
                    ScrollView(.vertical, showsIndicators: false, content: {
                        VStack{
                            GeometryReader{g in
                                Image("sporting")
                                    .resizable()
                                    .opacity(0.5)
                                    .frame(width: UIScreen.main.bounds.width - 50, height: UIScreen.main.bounds.width - 50)
                                    .offset(x: 50)
                                    .onReceive(self.timeSporting) { (_) in
                                        // its not a timer...
                                        // for tracking the image is scrolled out or not...
                                        let y = g.frame(in: .global).minY
                                        
                                        if -y > (UIScreen.main.bounds.height / 4) - 50{
                                            withAnimation{
                                                self.showSporting = true
                                            }
                                        }
                                        else{
                                            withAnimation{
                                                self.showSporting = false
                                            }
                                        }
                                    }
                            }
                            // fixing default height...
                            .frame(height: UIScreen.main.bounds.height / 14 )
                            
                            VStack{
                                HStack(alignment: .bottom){
                                    Text("Sporting Kansas City")
                                        .fontWeight(.bold)
                                        .font(.system(size: 35))
                                        .foregroundColor(.white)
                                        .padding(.leading, 15)
                                    Spacer()
                                }.ignoresSafeArea()
                                

                                SportingHome(articles: sportingArticles, players: sportingPlayers, playersUnfiltered: sportingPlayers, games: sportingGames, nextGame: sportingGamePointer)

                            }
                            .padding([.top, .horizontal])
                        }
                    })
                    
                    if self.showSporting{
                        TopView(logoName: "sporting", teamName: "Sporting Kansas City")
                    }
                })
                .edgesIgnoringSafeArea(.top)
                .opacity(self.index == 3 ? 1 : 0)
            }
            
            HStack{
                Button(action: {
                    self.index = 0
                }) {
                    HStack(spacing: 6){
                        Image("jayhawk")
                            .resizable()
                            .frame(width: 25, height: 25)
    
                        if self.index == 0{
                            Text("Jayhawks")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical,10)
                    .padding(.horizontal)
                    .background(self.index == 0 ? Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)) : Color.clear)
                    .clipShape(Capsule())
                }
                
                Spacer(minLength: 0)
                
                Button(action: {
                    self.index = 1
                }) {
                    HStack(spacing: 6){
                        Image("chiefs")
                            .resizable()
                            .frame(width: 25, height: 25)
                        
                        if self.index == 1{
                            Text("Chiefs")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical,10)
                    .padding(.horizontal)
                    .background(self.index == 1 ? Color(UIColor(red: 227/255, green: 24/255, blue: 55/255, alpha: 1.00)) : Color.clear)
                    .clipShape(Capsule())
                }
                
                Spacer(minLength: 0)
                
                Button(action: {
                    self.index = 2
                }) {
                    HStack(spacing: 6){
                        Image("royals")
                            // dark mode adoption...\
                            .resizable()
                            .frame(width: 25, height: 25)
                        
                        if self.index == 2{
                            Text("Royals")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical,10)
                    .padding(.horizontal)
                    .background(self.index == 2 ? Color(UIColor(red: 0/255, green: 70/255, blue: 135/255, alpha: 1.00)) : Color.clear)
                    .clipShape(Capsule())
                }
                
                Spacer(minLength: 0)
                
                Button(action: {
                    self.index = 3
                }) {
                    HStack(spacing: 6){
                        Image("sporting")
                            .resizable()
                            .frame(width: 25, height: 25)

                        if self.index == 3{
                            Text("Sporting")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical,10)
                    .padding(.horizontal)
                    .background(self.index == 3 ? Color(UIColor(red: 0/255, green: 42/255, blue: 92/255, alpha: 1.00)) : Color.clear)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal,25)
            .padding(.top)
            // based on device bottom padding will be changed...\
            .padding(.bottom,UIApplication.shared.windows.first?.safeAreaInsets.bottom == 0 ? 10 : UIApplication.shared.windows.first?.safeAreaInsets.bottom)
            .background(BlurBG())
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

// TopView...
struct TopView : View {
    var logoName: String
    var teamName: String
    
    var body: some View{
        HStack(alignment: .center){
            Image(logoName)
                //.renderingMode(.template)
                .resizable()
                .frame(width: 40, height: 40)
                .padding(.leading)
            
            Text(teamName)
                .font(.title)
                .fontWeight(.bold)
            Spacer(minLength: 0)
        }
        // for non safe area phones padding will be 15...
        .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top == 0 ? 15 : (UIApplication.shared.windows.first?.safeAreaInsets.top)! + 5)
        .padding(.horizontal)
        .padding(.bottom)
        .background(BlurBG())
    }
}

// Blur background...
struct BlurBG : UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView{
        // for dark mode adoption...
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        
    }
}
