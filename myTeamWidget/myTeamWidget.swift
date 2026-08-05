//
//  myTeamsWidget.swift
//  myTeamsWidget
//
//  Created by Stephen Rector on 11/25/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import WidgetKit
import SwiftUI

struct JahawkGameTimeline: TimelineProvider {
    typealias Entry = WidgetEntry
    let teamColor = Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00))
    
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), tempGame: GameInfo(backgroundLogo: "jayhawk", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor)
        let entry = WidgetEntry(date: Date(), tempGame: tempGame)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .second, value: 5, to: currentDate)!
        print("In Timelinex x       ")
        jayhawkSchedule.GameLoader.fetch { result in
            let game: GameInfo
            if case .success(let fetchedGame) = result {
                game = fetchedGame
            } else {
                game = GameInfo(backgroundLogo: "jayhawk", teamName: "N/A", gameDate: "N/A", gameTime: "N/A", gameChannel: "N/A", teamLogo: "", teamColor: teamColor)
            }
            let entry = WidgetEntry(date: currentDate, tempGame: game)
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }
}

struct ChiefsGameTimeline: TimelineProvider {
    typealias Entry = WidgetEntry
    let teamColor = Color(UIColor(red: 227/255, green: 24/255, blue: 55/255, alpha: 1.00))
    
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), tempGame: GameInfo(backgroundLogo: "chiefs", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let tempGame = GameInfo(backgroundLogo: "chiefs", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor)
        let entry = WidgetEntry(date: Date(), tempGame: tempGame)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        print("In Timelinex x       ")
        chiefsSchedule.GameLoader.fetch { result in
            let game: GameInfo
            if case .success(let fetchedGame) = result {
                game = fetchedGame
            } else {
                game = GameInfo(backgroundLogo: "chiefs", teamName: "N/A", gameDate: "N/A", gameTime: "N/A", gameChannel: "N/A", teamLogo: "", teamColor: teamColor)
            }
            let entry = WidgetEntry(date: currentDate, tempGame: game)
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }
}

struct RoyalsGameTimeline: TimelineProvider {
    typealias Entry = WidgetEntry
    let teamColor = Color(UIColor(red: 0/255, green: 70/255, blue: 135/255, alpha: 1.00))
    
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), tempGame: GameInfo(backgroundLogo: "royals", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let tempGame = GameInfo(backgroundLogo: "royals", teamName: "Opponent", gameDate: "Date", gameTime: "Time", gameChannel: "Channel", teamLogo: "", teamColor: teamColor)
        let entry = WidgetEntry(date: Date(), tempGame: tempGame)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        print("In Timelinex x       ")
        royalsSchedule.GameLoader.fetch { result in
            let game: GameInfo
            if case .success(let fetchedGame) = result {
                game = fetchedGame
            } else {
                game = GameInfo(backgroundLogo: "royals", teamName: "N/A", gameDate: "N/A", gameTime: "N/A", gameChannel: "N/A", teamLogo: "", teamColor: teamColor)
            }
            let entry = WidgetEntry(date: currentDate, tempGame: game)
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }
}

struct GameInfo {
    var backgroundLogo: String
    var teamName: String
    var gameDate: String
    var gameTime: String
    var gameChannel: String
    var teamLogo: String
    var teamColor: Color
}

struct WidgetEntry: TimelineEntry {
    var date: Date
    public let tempGame: GameInfo
}

struct PlaceHolderView: View {
    var body: some View {
        Text("Loading...")
    }
}

struct WidgetEntryView : View {
    var entry: WidgetEntry
    
    var body: some View {
        ZStack(alignment: .center) {
            Image(entry.tempGame.backgroundLogo)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fill)
                .opacity(0.1)
                .saturation(0.1)
                .contrast(0.5)
                .frame(width: 200, height: 200)
                .offset(x: 40, y: 50)
            
            HStack() {
                VStack(spacing: 1) {
                    Text(entry.tempGame.teamName)
                        .font(.system(size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(Color.white)
                        //.minimumScaleFactor(0.5)
                        .padding(.horizontal, 15)
                    
                    if let url = URL(string: entry.tempGame.teamLogo), let imageData = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: imageData) {
                        
                        Image(uiImage: uiImage)
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            //.offset(y: -15)
                            .minimumScaleFactor(0.1)
                    }
                    else {
                        //Show Nothing
                    }
                    
                        Text(entry.tempGame.gameDate)
                            .font(.system(size: 12))
                            //.fontWeight(.bold)
                            .foregroundColor(Color.white)
                        
                        Text(entry.tempGame.gameTime)
                            .font(.system(size: 12))
                            //.fontWeight(.bold)
                            .foregroundColor(Color.white)
                        Text(entry.tempGame.gameChannel)
                            .font(.system(size: 12))
                            //.fontWeight(.bold)
                            .foregroundColor(Color.white)
                    
                    
                }.padding(.all, 10)
                .frame(height: smallWidgetWidth())
            }
            //.frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
        }.background(entry.tempGame.teamColor)
        .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
    }
}

func smallWidgetWidth() -> CGFloat {
    switch UIScreen.main.bounds.size {
    case CGSize(width: 414, height: 896):
        return 169
    case CGSize(width: 375, height: 812):
        return 155
    case CGSize(width: 414, height: 736):
        return 159
    case CGSize(width: 375, height: 667):
        return 148
    case CGSize(width: 320, height: 568):
        return 141
    default:
        return 155
    }
}

struct myTeamsWidget: Widget {
    let kind: String = "myTeamsWidget"
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JahawkGameTimeline()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Jayhawk Schedule")
        .description("This widget will show the next upcoming Kansas Jayhawk basketball game.")
        .supportedFamilies([.systemSmall])
    }
}

struct myTeamsWidget2: Widget {
    let kind: String = "myTeamsWidget2"
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChiefsGameTimeline()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Chiefs Schedule")
        .description("This widget will show the next upcoming Kansas City Chiefs football game.")
        .supportedFamilies([.systemSmall])
    }
}

struct myTeamsWidget3: Widget {
    let kind: String = "myTeamsWidget3"
    
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoyalsGameTimeline()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Royals Schedule")
        .description("This widget will show the next upcoming Kansas City Royals baseball game.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ScheduleWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        myTeamsWidget()
        myTeamsWidget2()
        myTeamsWidget3()
    }
}
