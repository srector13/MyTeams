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
    /// The followed team's `TeamRef.id`, for the link a tap opens.
    var teamID: TeamRef.ID?
}

/// Builds a team's entries for the configurable widget's provider.
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
        WidgetEntry(date: .now, tempGame: .placeholder(for: team), followedTeam: team.shortName, teamID: team.id)
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
        return WidgetEntry(date: .now, tempGame: game, followedTeam: team.shortName, teamID: team.id)
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
            entries: [WidgetEntry(date: now, tempGame: game, followedTeam: team.shortName, teamID: team.id)],
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

struct WidgetEntryView: View {
    var entry: WidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            #if os(iOS)
            case .accessoryRectangular, .accessoryCircular:
                AccessoryEntryView(entry: entry, family: family)
            #endif
            default:
                // Medium too: the column is sized by the height, which the
                // two share, and centred in the wider tile.
                ScheduleTile(game: entry.tempGame, renderingMode: renderingMode)
            }
        }
        // A tap opens the followed team's page in the app.
        .widgetURL(entry.teamID.flatMap(WidgetDeepLink.url(forTeamID:)))
    }
}

/// The Home Screen tile: the next opponent, its crest, and when and where
/// the game is, over the followed team's colour and crest.
///
/// The system removes the container background in the Clear and Tinted
/// appearances (`.accented`) and on StandBy (`.vibrant`), and tints the
/// content itself, so nothing the reader needs lives only in the background
/// (W-1): the team colour is the full-colour backdrop and no more, and the
/// followed team's crest, which says whose widget this is, is drawn in the
/// content layer, where every mode keeps it.
///
/// Takes `renderingMode` rather than reading it, so previews can draw each
/// mode.
struct ScheduleTile: View {
    var game: WidgetGame
    var renderingMode: WidgetRenderingMode

    var body: some View {
        VStack(spacing: 1) {
            Text(game.teamName)
                .font(Theme.Typography.cardTitle)
                .widgetAccentable()
                .padding(.horizontal, Theme.Spacing.l)

            if let data = game.teamLogo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    // Kept recognisable, in grey, when the system tints.
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fit)
            }

            Group {
                Text(game.gameDate)
                Text(game.gameTime)
                Text(game.gameChannel)
            }
            .font(Theme.Typography.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .modifier(TileInk(team: game.team, renderingMode: renderingMode))
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { watermark }
        // Widgets must declare their own background; without this the system
        // draws them on a default light surface.
        .containerBackground(for: .widget) {
            game.teamColor
        }
    }

    /// The followed team's crest, faint behind the fixture. In the tinted
    /// modes it takes the accent colour, desaturated, like the team name.
    @ViewBuilder
    private var watermark: some View {
        if let data = game.backgroundLogo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: .fill)
                .opacity(0.1)
                .saturation(0.1)
                .contrast(0.5)
                .frame(width: 200, height: 200)
                .offset(x: 40, y: 50)
                .accessibilityHidden(true)
        }
    }
}

/// The tile's ink: in full colour, the ink `teamInk(on:)` picks for the team
/// colour behind it (white on most, black on a light colour); otherwise the
/// system's primary ink, since the team colour is gone and the system tints
/// the content.
private struct TileInk: ViewModifier {
    var team: TeamRef
    var renderingMode: WidgetRenderingMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content.teamInk(on: team)
        } else {
            content.foregroundStyle(.primary)
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
        return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]
        #else
        return [.systemSmall, .systemMedium]
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

// The legacy fixed-team kinds ("myTeamsWidget2" to "myTeamsWidget4": the
// Chiefs, Royals and Sporting) are retired; their placed widgets are removed
// and can be replaced by a Team Schedule widget set to the same team.
@main
struct ScheduleWidgets: WidgetBundle {
    var body: some Widget {
        TeamScheduleWidget()
        #if canImport(ActivityKit) && os(iOS)
        GameLiveActivity()
        #endif
    }
}

// Previews (GlassUI step 0.7): each rendering mode the tile adapts to. The
// widget previews draw in full colour; the canvas's rendering-mode variants
// show the system's own tinting. The `ScheduleTile` previews below draw the
// tile as the tinted modes leave it, with no container background, to check
// that the team's identity survives without it.

extension WidgetEntry {
    /// A filled-in fixture with stand-in crests, for previews.
    fileprivate static var preview: WidgetEntry {
        let team = WidgetTeams.fallback
        let crest = UIImage(systemName: "shield.fill")?.pngData()
        let game = WidgetGame(
            backgroundLogo: crest,
            teamName: "Missouri",
            gameDate: "Sat Nov 7, 2026",
            gameTime: "7:00 PM",
            gameChannel: "ESPN",
            teamLogo: crest,
            team: team
        )
        return WidgetEntry(date: .now, tempGame: game, followedTeam: team.shortName, teamID: team.id)
    }
}

#Preview("Small · full colour", as: .systemSmall) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
    WidgetTimelines.placeholder(for: WidgetTeams.fallback)
}

#Preview("Medium · full colour", as: .systemMedium) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
}

#Preview("Small · Clear/Tinted (accented)", traits: .fixedLayout(width: 170, height: 170)) {
    ScheduleTile(game: WidgetEntry.preview.tempGame, renderingMode: .accented)
        .background(Theme.Surface.content)
}

#Preview("Small · StandBy (vibrant)", traits: .fixedLayout(width: 170, height: 170)) {
    ScheduleTile(game: WidgetEntry.preview.tempGame, renderingMode: .vibrant)
        .background(Theme.Surface.content)
        .environment(\.colorScheme, .dark)
}

#if os(iOS)
#Preview("Lock Screen · rectangular", as: .accessoryRectangular) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
    WidgetTimelines.placeholder(for: WidgetTeams.fallback)
}

#Preview("Lock Screen · circular", as: .accessoryCircular) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
}
#endif
