//
//  myTeamsWidget.swift
//  myTeamsWidget
//
//  Created by Stephen Rector on 11/25/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import WidgetKit
import SwiftUI
import UIKit

struct WidgetEntry: TimelineEntry {
    var date: Date
    let tempGame: WidgetGame
}

/// Supplies one team's next fixture to its widget.
///
/// The three teams shared an identical provider apiece; they now share this
/// one, differing only in which team they are built for.
struct GameTimelineProvider: TimelineProvider {
    let team: Team

    /// How long a rendered fixture stays good for.
    ///
    /// A fixture's date, time and channel rarely change, so the widget asks
    /// for a new timeline hourly rather than the five seconds the Jayhawks
    /// provider used to request — a budget WidgetKit would never have granted.
    private let refreshInterval: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, tempGame: .placeholder(for: team))
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task {
            let game = await WidgetScheduleLoader.nextGame(for: team)
                ?? .placeholder(for: team, teamName: "N/A", detail: "N/A")

            completion(
                Timeline(
                    entries: [WidgetEntry(date: .now, tempGame: game)],
                    policy: .after(.now + refreshInterval)
                )
            )
        }
    }
}

struct WidgetEntryView: View {
    var entry: WidgetEntry

    var body: some View {
        VStack(spacing: 1) {
            Text(entry.tempGame.teamName)
                .font(.system(size: 16))
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 15)

            if let data = entry.tempGame.teamLogo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .minimumScaleFactor(0.1)
            }

            Text(entry.tempGame.gameDate)
                .font(.system(size: 12))
                .foregroundStyle(.white)

            Text(entry.tempGame.gameTime)
                .font(.system(size: 12))
                .foregroundStyle(.white)

            Text(entry.tempGame.gameChannel)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Widgets must declare their own background; without this the system
        // draws them on a default light surface.
        .containerBackground(for: .widget) {
            ZStack {
                entry.tempGame.teamColor

                Image(entry.tempGame.backgroundLogo)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.1)
                    .saturation(0.1)
                    .contrast(0.5)
                    .frame(width: 200, height: 200)
                    .offset(x: 40, y: 50)
            }
        }
    }
}

struct JayhawksScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget",
            provider: GameTimelineProvider(team: .jayhawks)
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Jayhawk Schedule")
        .description("This widget will show the next upcoming Kansas Jayhawk basketball game.")
        .supportedFamilies([.systemSmall])
    }
}

struct ChiefsScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget2",
            provider: GameTimelineProvider(team: .chiefs)
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Chiefs Schedule")
        .description("This widget will show the next upcoming Kansas City Chiefs football game.")
        .supportedFamilies([.systemSmall])
    }
}

struct RoyalsScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget3",
            provider: GameTimelineProvider(team: .royals)
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Royals Schedule")
        .description("This widget will show the next upcoming Kansas City Royals baseball game.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ScheduleWidgets: WidgetBundle {
    var body: some Widget {
        JayhawksScheduleWidget()
        ChiefsScheduleWidget()
        RoyalsScheduleWidget()
    }
}

#Preview(as: .systemSmall) {
    JayhawksScheduleWidget()
} timeline: {
    WidgetEntry(date: .now, tempGame: .placeholder(for: .jayhawks))
}
