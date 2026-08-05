//
//  PlayerView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct PlayerView : View {
    
    var player: BasketballPlayer
    var state: String
    
    var body: some View {
        if player.name == "" {
            VStack(spacing: 5) {
                LoadingViewCircle()
                    .frame(width: 60, height: 60)
                
                LoadingView()
                    .frame(width: 70, height: 10)
            }
        } else {
            VStack(spacing: 5) {
                WebImage(url: URL(string: player.photo))
                    .onSuccess { image, cacheType in
                        // Success
                    }
                    .resizable()
                    .placeholder(Image("blank"))
                    .indicator(.activity)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                
                if (state == "name") {
                    Text(player.name)
                        .font(.system(size: 10))
                        .foregroundColor(Color(UIColor.systemGray))
                } else if (state == "number") {
                    if(player.number != "") {
                        Text("\(player.number)")
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                    }  else {
                        Text("N/A")
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                    }
                } else {
                    if(player.position != "") {
                        Text("\(player.position)")
                            .font(.system(size: 10))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                    }  else {
                        Text("N/A")
                            .font(.system(size: 10))
                            .fontWeight(.bold)
                            .foregroundColor(Color(UIColor.systemGray))
                    }
                }
            }
        }
        
    }
}

struct FootballPlayerView : View {
    
    var player: FootBallPlayer
    var state: String
    
    var body: some View {
        VStack(spacing: 5) {
            WebImage(url: URL(string: player.photo))
                .onSuccess { image, cacheType in
                    // Success
                }
                .resizable()
                .placeholder(Image("blank"))
                .indicator(.activity)
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            
            if (state == "name") {
                Text(player.name)
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.systemGray))
            } else if (state == "number") {
                if(player.number != "") {
                    Text("\(player.number)")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            } else {
                if(player.position != "") {
                    Text("\(player.position)")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            }
        }
    }
}

struct BaseballPlayerView : View {
    
    var player: BaseballPlayer
    var state: String
    var body: some View {
        VStack(spacing: 5) {
            WebImage(url: URL(string: player.photo))
                .onSuccess { image, cacheType in
                    // Success
                }
                .resizable()
                .placeholder(Image("blank"))
                .indicator(.activity)
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            
            if (state == "name") {
                Text(player.name)
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.systemGray))
            } else if (state == "number") {
                if(player.number != "") {
                    Text("\(player.number)")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            } else {
                if(player.position != "") {
                    Text("\(player.position)")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            }
        }
    }
}

struct SoccerPlayerView : View {
    
    var player: SoccerPlayer
    var state: String
    
    var body: some View {
        VStack(spacing: 5) {
            WebImage(url: URL(string: player.photo))
                .onSuccess { image, cacheType in
                    // Success
                }
                .resizable()
                .placeholder(Image("blank"))
                .indicator(.activity)
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(Circle())
            
            if (state == "name") {
                Text(player.name)
                    .font(.system(size: 10))
                    .foregroundColor(Color(UIColor.systemGray))
            } else if (state == "number") {
                if(player.number != "") {
                    Text("\(player.number)")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 12))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            } else {
                if(player.position != "") {
                    Text("\(player.position)")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }  else {
                    Text("N/A")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(Color(UIColor.systemGray))
                }
            }
        }
    }
}
