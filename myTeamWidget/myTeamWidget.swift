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
            case .systemMedium:
                MediumScheduleTile(game: entry.tempGame, renderingMode: renderingMode)
            default:
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
        // The small tile can't grow, so its text scales only as far as the
        // crest and four lines still fit (W-2).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .modifier(TileBackdrop(game: game, renderingMode: renderingMode))
    }
}

/// The medium Home Screen tile (W-3): the opponent's crest on the left, and
/// the matchup, date, time and channel on the right, rather than the small
/// tile's column centred in a tile twice as wide.
///
/// Shares the small tile's ink, watermark and container background
/// (`TileBackdrop`) and its rendering-mode rules (W-1): the opponent's name
/// is the accented line in both, and the crest keeps its shape, desaturated,
/// when the system tints.
struct MediumScheduleTile: View {
    var game: WidgetGame
    var renderingMode: WidgetRenderingMode

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            crest
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // The matchup, as the Lock Screen's rectangular widget
                // reads it: the followed team, then "vs" the opponent.
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.team.shortName)
                        .font(Theme.Typography.statLabel)
                    Text("vs \(game.teamName)")
                        .font(Theme.Typography.cardTitle)
                        .widgetAccentable()
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.gameDate)
                    Text(game.gameTime)
                    Text(game.gameChannel)
                }
                .font(Theme.Typography.footnote)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // The details take the width they need, first; the crest fits
            // the rest.
            .layoutPriority(1)
        }
        // Same ceiling as the small tile: the tile is as tall as the small
        // one, and five lines must still fit beside the crest (W-2).
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .modifier(TileBackdrop(game: game, renderingMode: renderingMode))
    }

    /// The opponent's crest, or the followed team's when the opponent has
    /// none (a placeholder, or a feed without a logo), so the left half is
    /// never empty.
    @ViewBuilder
    private var crest: some View {
        if let data = game.teamLogo ?? game.backgroundLogo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                // Kept recognisable, in grey, when the system tints.
                .widgetAccentedRenderingMode(.desaturated)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}

/// What the Home Screen tiles share around their content: the ink, the
/// padding, the faint followed-team crest, and the team colour as the
/// container background.
///
/// The container background is the team colour on the Home Screen families
/// only; the system drops it in the tinted modes (§5.4), which is why the
/// tiles draw their identity in the content layer. The Lock Screen
/// accessories keep their own clear background (`AccessoryEntryView`).
private struct TileBackdrop: ViewModifier {
    var game: WidgetGame
    var renderingMode: WidgetRenderingMode

    func body(content: Content) -> some View {
        content
            .modifier(TileInk(team: game.team, renderingMode: renderingMode))
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { watermark }
            // Widgets must declare their own background; without this the
            // system draws them on a default light surface.
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
                            .font(.caption2.weight(.semibold))
                        Text(entry.tempGame.gameTime)
                            .font(.caption2)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // A fixed circle: the text scales only a little.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
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

#Preview("Medium · Clear/Tinted (accented)", traits: .fixedLayout(width: 364, height: 170)) {
    MediumScheduleTile(game: WidgetEntry.preview.tempGame, renderingMode: .accented)
        .background(Theme.Surface.content)
}

#Preview("Medium · StandBy (vibrant)", traits: .fixedLayout(width: 364, height: 170)) {
    MediumScheduleTile(game: WidgetEntry.preview.tempGame, renderingMode: .vibrant)
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
