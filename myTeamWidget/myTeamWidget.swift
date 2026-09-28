//
//  myTeamsWidget.swift
//  myTeamsWidget
//
//  Created by Stephen Rector on 11/25/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import AppIntents
import WidgetKit
import SwiftUI
import UIKit

struct WidgetEntry: TimelineEntry {
    var date: Date
    let tempGame: WidgetGame
    /// The followed team's short name, for the Lock Screen layouts.
    var followedTeam = ""
}

/// Builds a team's entries. Shared by the configurable widget's provider
/// and the legacy fixed-team one.
enum WidgetTimelines {
    /// How long a rendered fixture stays good for.
    ///
    /// A fixture's date, time and channel rarely change, so the widget asks
    /// for a new timeline hourly rather than the five seconds the Jayhawks
    /// provider used to request — a budget WidgetKit would never have granted.
    /// A fixture starting sooner than that reloads at its kickoff instead.
    static let refreshInterval: TimeInterval = 60 * 60

    /// How soon a failed load is retried. Showing "N/A" for a whole hour
    /// after one dropped request was the old behaviour.
    static let retryInterval: TimeInterval = 5 * 60

    /// How long a snapshot waits for real data before settling for the
    /// placeholder. WidgetKit wants snapshots back promptly, and the gallery
    /// preview most of all.
    static let previewDeadline: Duration = .seconds(3)
    static let snapshotDeadline: Duration = .seconds(10)

    static func placeholder(for team: TeamRef) -> WidgetEntry {
        WidgetEntry(date: .now, tempGame: .placeholder(for: team), followedTeam: team.shortName)
    }

    /// Renders the real next fixture — in the widget gallery too, where it
    /// waits only briefly before falling back to the placeholder.
    static func snapshot(for team: TeamRef, isPreview: Bool) async -> WidgetEntry {
        let deadline = isPreview ? previewDeadline : snapshotDeadline
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
        return WidgetEntry(date: .now, tempGame: game, followedTeam: team.shortName)
    }

    static func timeline(for team: TeamRef) async -> Timeline<WidgetEntry> {
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

        return Timeline(
            entries: [WidgetEntry(date: now, tempGame: game, followedTeam: team.shortName)],
            policy: .after(reload)
        )
    }
}

/// Supplies the configurable widget: the team chosen in its settings, else
/// the reader's first favorite, else the Jayhawks.
struct TeamTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetTimelines.placeholder(for: WidgetTeams.firstSeedFavorite)
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> WidgetEntry {
        let team = await WidgetTeams.team(for: configuration)
        return await WidgetTimelines.snapshot(for: team, isPreview: context.isPreview)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let team = await WidgetTeams.team(for: configuration)
        let timeline = await WidgetTimelines.timeline(for: team)
        // After the timeline is built, so the league's team list (up to a
        // megabyte for college leagues) is never parsed while the schedule
        // is in memory.
        Task {
            await WidgetScheduleLoader.refreshCatalog(for: team)
        }
        return timeline
    }
}

/// Supplies one fixed team's next fixture, ignoring favorites. Only the
/// legacy per-team widgets use it.
struct GameTimelineProvider: TimelineProvider {
    let team: TeamRef

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetTimelines.placeholder(for: team)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let isPreview = context.isPreview
        Task {
            completion(await WidgetTimelines.snapshot(for: team, isPreview: isPreview))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task {
            completion(await WidgetTimelines.timeline(for: team))

            // After the timeline is handed over, so the league's team list
            // (up to a megabyte for college leagues) is never parsed while
            // the schedule is in memory.
            await WidgetScheduleLoader.refreshCatalog(for: team)
        }
    }
}

struct WidgetEntryView: View {
    var entry: WidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryRectangular, .accessoryCircular:
            AccessoryEntryView(entry: entry, family: family)
        #endif
        default:
            systemSmall
        }
    }

    private var systemSmall: some View {
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

                if let data = entry.tempGame.backgroundLogo, let image = UIImage(data: data) {
                    Image(uiImage: image)
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
}

#if os(iOS)
/// The Lock Screen's compact layouts: the followed team, its opponent and
/// when they play.
private struct AccessoryEntryView: View {
    var entry: WidgetEntry
    var family: WidgetFamily

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(entry.tempGame.teamName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(entry.tempGame.gameTime)
                            .font(.system(size: 10))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(4)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.followedTeam)
                        .font(.headline)
                        .widgetAccentable()
                    Text("vs \(entry.tempGame.teamName)")
                    Text("\(entry.tempGame.gameDate) \(entry.tempGame.gameTime)")
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
#endif

/// The one configurable widget: any team, chosen in its settings. Keeps the
/// original Jayhawks widget's kind, so those placements carry over and, left
/// unconfigured, show the first favorite (the Jayhawks, on an existing
/// install that has not reordered them).
struct TeamScheduleWidget: Widget {
    private var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .accessoryRectangular, .accessoryCircular]
        #else
        return [.systemSmall]
        #endif
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "myTeamsWidget",
            intent: SelectTeamIntent.self,
            provider: TeamTimelineProvider()
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Team Schedule")
        .description("Shows the next game of the team you choose, or your first favorite.")
        .supportedFamilies(families)
    }
}

// Legacy fixed-team widgets, kept for one release so placed Chiefs, Royals
// and Sporting widgets survive the move to the configurable one. Each pins
// its seed team and ignores favorites. Remove in the release after next;
// removing a kind deletes its placed widgets.

struct ChiefsScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget2",
            provider: GameTimelineProvider(team: TeamCatalog.seeded(league: .nfl, espnID: "12"))
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Chiefs Schedule (Legacy)")
        .description("The Kansas City Chiefs' next game. Use Team Schedule for any team.")
        .supportedFamilies([.systemSmall])
    }
}

struct RoyalsScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget3",
            provider: GameTimelineProvider(team: TeamCatalog.seeded(league: .mlb, espnID: "7"))
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Royals Schedule (Legacy)")
        .description("The Kansas City Royals' next game. Use Team Schedule for any team.")
        .supportedFamilies([.systemSmall])
    }
}

struct SportingScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "myTeamsWidget4",
            provider: GameTimelineProvider(team: TeamCatalog.seeded(league: .mls, espnID: "186"))
        ) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sporting Schedule (Legacy)")
        .description("Sporting Kansas City's next game. Use Team Schedule for any team.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ScheduleWidgets: WidgetBundle {
    var body: some Widget {
        TeamScheduleWidget()
        ChiefsScheduleWidget()
        RoyalsScheduleWidget()
        SportingScheduleWidget()
    }
}

#Preview(as: .systemSmall) {
    TeamScheduleWidget()
} timeline: {
    WidgetTimelines.placeholder(for: WidgetTeams.fallback)
}

#if os(iOS)
#Preview(as: .accessoryRectangular) {
    TeamScheduleWidget()
} timeline: {
    WidgetTimelines.placeholder(for: WidgetTeams.fallback)
}
#endif
