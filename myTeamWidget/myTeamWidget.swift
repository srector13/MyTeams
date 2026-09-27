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
    /// A fixture starting sooner than that reloads at its kickoff instead.
    private let refreshInterval: TimeInterval = 60 * 60

    /// How soon a failed load is retried. Showing "N/A" for a whole hour
    /// after one dropped request was the old behaviour.
    private let retryInterval: TimeInterval = 5 * 60

    /// How long a snapshot waits for real data before settling for the
    /// placeholder. WidgetKit wants snapshots back promptly, and the gallery
    /// preview most of all.
    private let previewDeadline: Duration = .seconds(3)
    private let snapshotDeadline: Duration = .seconds(10)

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, tempGame: .placeholder(for: team))
    }

    /// Renders the real next fixture — in the widget gallery too, where it
    /// waits only briefly before falling back to the placeholder.
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let deadline = context.isPreview ? previewDeadline : snapshotDeadline
        Task {
            let result = await WidgetScheduleLoader.nextGame(for: team, within: deadline)

            let game: WidgetGame
            switch result {
            case .game(let next, _):
                game = next
            case .seasonOver:
                game = .placeholder(for: team, teamName: "N/A", detail: "N/A")
            case .failed:
                game = .placeholder(for: team)
            }
            completion(WidgetEntry(date: .now, tempGame: game))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task {
            let now = Date.now
            let game: WidgetGame
            let reload: Date

            let result = await WidgetScheduleLoader.nextGame(for: team)
            switch result {
            case .game(let next, let kickoff):
                game = next
                // Once the game starts it is no longer the next one; reload
                // then (but never sooner than a minute) so the widget moves
                // on to the following fixture.
                reload = min(now + refreshInterval, max(kickoff, now + 60))
            case .seasonOver:
                game = .placeholder(for: team, teamName: "N/A", detail: "N/A")
                reload = now + refreshInterval
            case .failed:
                game = .placeholder(for: team, teamName: "N/A", detail: "N/A")
                reload = now + retryInterval
            }

            completion(
                Timeline(
                    entries: [WidgetEntry(date: now, tempGame: game)],
                    policy: .after(reload)
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

struct SportingScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget4",
            provider: GameTimelineProvider(team: .sporting)
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sporting Schedule")
        .description("This widget will show the next upcoming Sporting Kansas City soccer game.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ScheduleWidgets: WidgetBundle {
    var body: some Widget {
        JayhawksScheduleWidget()
        ChiefsScheduleWidget()
        RoyalsScheduleWidget()
        SportingScheduleWidget()
    }
}

#Preview(as: .systemSmall) {
    JayhawksScheduleWidget()
} timeline: {
    WidgetEntry(date: .now, tempGame: .placeholder(for: .jayhawks))
}
