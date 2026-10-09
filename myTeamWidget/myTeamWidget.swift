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
    /// Whether there is no team to show: none chosen and none followed.
    /// The widget then asks for one (`NoTeamView`) and `tempGame` is unused.
    var needsTeam = false
    /// With `needsTeam`: why, when the favorites could not be read (no
    /// store reachable, or one holding nothing from the app), so the widget
    /// says that rather than "Add Teams".
    var missing: WidgetMissingTeam = .noneFollowed
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

    /// How soon a failed load is retried. Showing a failure for a whole
    /// hour after one dropped request was the old behaviour.
    static let retryInterval: TimeInterval = 5 * 60

    /// How long a snapshot waits for real data before settling for the
    /// placeholder. WidgetKit wants snapshots back promptly, and the gallery
    /// preview most of all.
    static let previewDeadline: Duration = .seconds(3)
    static let snapshotDeadline: Duration = .seconds(10)
    /// How long a timeline waits for its loads before showing the last
    /// good copy. The request timeout is shorter; the resource timeout is a
    /// minute, longer than an extension is given.
    static let timelineDeadline: Duration = .seconds(25)

    static func placeholder(for team: TeamRef) -> WidgetEntry {
        WidgetEntry(date: .now, tempGame: .placeholder(for: team), followedTeam: team.shortName, teamID: team.id)
    }

    /// The entry with no team to show (t_afe5c297). A tap opens the app,
    /// on its "Add Teams"; following a team reloads the timeline.
    static var noTeam: WidgetEntry {
        WidgetEntry(date: .now, tempGame: .placeholder(for: WidgetTeams.fallback), needsTeam: true)
    }

    /// The entry with no team to show: `noTeam`, or, with the favorites
    /// unreadable, one saying so and which store the widget reached.
    static func missingTeam(_ shared: SharedDataStatus) -> WidgetEntry {
        var entry = noTeam
        entry.missing = WidgetMissingTeam(shared: shared)
        return entry
    }

    /// The one line a tile shows when there is no game to show (B-16).
    static let seasonOverMessage = "No upcoming games"
    static let failedMessage = "Couldn't update"

    /// Renders the real featured game — in the widget gallery too, where it
    /// waits only briefly before falling back to the placeholder.
    static func snapshot(for team: TeamRef, isPreview: Bool) async -> WidgetEntry {
        let deadline = isPreview ? previewDeadline : snapshotDeadline
        let now = Date.now
        let result = await WidgetScheduleLoader.featuredGame(for: team, now: now, within: deadline)

        let fresh: WidgetGame?
        switch result {
        case .game(let featured, _):
            fresh = featured
        case .seasonOver:
            fresh = .notice(seasonOverMessage, for: team)
        case .failed:
            // The gallery shows sample data rather than a failure.
            guard !isPreview else {
                return WidgetEntry(date: now, tempGame: .placeholder(for: team), followedTeam: team.shortName, teamID: team.id)
            }
            fresh = nil
        }
        let game = self.game(fresh, for: team, now: now, shared: SharedContainer.live.status)
        return WidgetEntry(date: now, tempGame: game, followedTeam: team.shortName, teamID: team.id)
    }

    static func timeline(for team: TeamRef) async -> Timeline<WidgetEntry> {
        let now = Date.now
        let fresh: WidgetGame?
        let reload: Date

        let result = await WidgetScheduleLoader.featuredGame(for: team, now: now, within: timelineDeadline)
        switch result {
        case .game(let featured, let refresh):
            fresh = featured
            // A fixture reloads at its kickoff, to show it under way; a game
            // under way, every few minutes; a result, at midnight. Never
            // sooner than a minute, nor later than the hourly refresh.
            reload = min(now + refreshInterval, max(refresh, now + 60))
        case .seasonOver:
            fresh = .notice(seasonOverMessage, for: team)
            reload = now + refreshInterval
        case .failed:
            fresh = nil
            reload = now + retryInterval
        }
        let game = self.game(fresh, for: team, now: now, shared: SharedContainer.live.status)

        return Timeline(
            entries: [WidgetEntry(date: now, tempGame: game, followedTeam: team.shortName, teamID: team.id)],
            policy: .after(reload)
        )
    }

    /// The tile for what a load found (`WidgetContent.plan`): the fresh
    /// game, kept as the last good copy; else that copy, dated; else
    /// "Couldn't update". Noted when the App Group is unreachable, as the
    /// app's live scores then never reach the widget.
    static func game(
        _ fresh: WidgetGame?,
        for team: TeamRef,
        now: Date,
        shared: SharedDataStatus,
        lastGood defaults: UserDefaults = .standard
    ) -> WidgetGame {
        let key = WidgetLastGoodStore.teamKey(team.id)
        if let fresh {
            WidgetLastGoodStore.save(fresh.cached, at: now, key: key, in: defaults)
        }
        let content = WidgetContent<WidgetCachedGame>.plan(
            fresh: fresh?.cached,
            lastGood: fresh == nil ? WidgetLastGoodStore.load(WidgetCachedGame.self, key: key, from: defaults) : nil,
            shared: shared,
            now: now
        )
        var game = fresh
            ?? content.value.map { WidgetGame(cached: $0, team: team) }
            ?? WidgetGame.notice(failedMessage, for: team)
        game.note = content.note
        return game
    }
}

/// Supplies the configurable widget: the team chosen in its settings, else
/// the reader's first favorite, else, with none followed, a prompt to add
/// one (`WidgetTimelines.noTeam`).
struct TeamTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetTimelines.placeholder(for: WidgetTeams.firstSeedFavorite)
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> WidgetEntry {
        guard let team = await WidgetTeams.team(for: configuration) else {
            // The gallery shows what the widget does, on its sample team.
            return context.isPreview
                ? WidgetTimelines.placeholder(for: WidgetTeams.fallback)
                : WidgetTimelines.missingTeam(SharedContainer.live.status)
        }
        return await WidgetTimelines.snapshot(for: team, isPreview: context.isPreview)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<WidgetEntry> {
        guard let team = await WidgetTeams.team(for: configuration) else {
            // Following a team reloads every timeline (`FavoritesStore`);
            // the hourly refresh only backs that up.
            // Without the App Group, no favorite can be read: the entry says
            // so, rather than asking for a team the reader already follows.
            let entry = WidgetTimelines.missingTeam(SharedContainer.live.status)
            return Timeline(entries: [entry], policy: .after(.now + WidgetTimelines.refreshInterval))
        }
        let timeline = await WidgetTimelines.timeline(for: team)
        // Only for a team the app's copy of the favorites and the bundle
        // don't describe: the league's team list (megabytes for college
        // leagues) parsed here, while WidgetKit renders the entry in the
        // same process, can take the extension past its memory limit, and
        // the widget then never leaves its placeholder.
        let needsCatalog = TeamCatalog.team(id: team.id) == nil
            && SharedContainer.live.favoritesMirror()?.teams.contains(where: { $0.id == team.id }) != true
        Task {
            if needsCatalog {
                await WidgetScheduleLoader.refreshCatalog(for: team)
            }
            #if os(iOS)
            // The app reloads the timelines when its scoreboard snapshot
            // changes; the "Open Live Game" control reads the same snapshot.
            await LiveGameControl.reload()
            #endif
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
            if entry.needsTeam {
                NoTeamView(family: family, missing: entry.missing)
            } else {
                switch family {
                #if os(iOS)
                case .accessoryRectangular, .accessoryCircular, .accessoryInline:
                    AccessoryEntryView(entry: entry, family: family)
                #endif
                case .systemMedium:
                    MediumScheduleTile(game: entry.tempGame, renderingMode: renderingMode)
                default:
                    ScheduleTile(game: entry.tempGame, renderingMode: renderingMode)
                }
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

            // With no game to show, the followed team's own crest stands
            // with the one-line notice (B-16).
            if let data = (game.message == nil ? game.teamLogo : game.backgroundLogo),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    // Kept recognisable, in grey, when the system tints.
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fit)
            }

            Group {
                if let message = game.message {
                    Text(message)
                } else {
                    Text(game.gameDate)
                    Text(game.gameTime)
                    if let channel = game.gameChannel {
                        Text(channel)
                    }
                }
            }
            .font(Theme.Typography.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let note = game.note {
                TileNote(note: note)
            }
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
                if let message = game.message {
                    // No game to show: the followed team, and one line.
                    Text(game.team.shortName)
                        .font(Theme.Typography.cardTitle)
                        .widgetAccentable()
                    Text(message)
                        .font(Theme.Typography.footnote)
                } else {
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
                        if let channel = game.gameChannel {
                            Text(channel)
                        }
                    }
                    .font(Theme.Typography.footnote)
                }
                if let note = game.note {
                    TileNote(note: note)
                }
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

/// The caption-sized line under a tile's content: the age of a kept copy, or
/// the App Group being unreachable (`WidgetGame.note`).
struct TileNote: View {
    var note: String

    var body: some View {
        Text(note)
            .font(.caption2)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .opacity(0.8)
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

/// The widget with no team to show: none chosen in its settings and none
/// followed in the app (t_afe5c297). Asks for one rather than showing a team
/// the reader never picked; a tap opens the app, on its "Add Teams". "My
/// Day" (`MyDayView`) shows it too.
///
/// When the favorites could not be read at all (`missing`: no store
/// reachable, or one holding nothing from the app) it says that, with which
/// store the signature offers, rather than asking for a team.
struct NoTeamView: View {
    var family: WidgetFamily
    var missing: WidgetMissingTeam = .noneFollowed

    private var symbol: String {
        missing.isSharingProblem ? "exclamationmark.triangle" : "plus"
    }

    var body: some View {
        Group {
            #if os(iOS)
            if family == .accessoryInline {
                Text(missing.inline)
            } else if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .widgetAccentable()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(missing.title)
                .containerBackground(for: .widget) { Color.clear }
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 0) {
                    Text(missing.title)
                        .font(.headline)
                        .widgetAccentable()
                    Text(missing.detail)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(for: .widget) { Color.clear }
            } else {
                tile
            }
            #else
            tile
            #endif
        }
    }

    private var tile: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: missing.isSharingProblem ? "exclamationmark.triangle" : "plus.circle")
                .font(.title)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(missing.title)
                .font(Theme.Typography.cardTitle)
                .widgetAccentable()
            Text(missing.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if missing.isSharingProblem {
                // Which store the install was signed with, so the reader
                // (and a bug report) can tell a missing group from one the
                // app doesn't write to.
                Text(SharedStoreIdentity.current.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
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
            if family == .accessoryInline {
                // The line above the clock (R-9): "KC 21–17 Q3" or
                // "KC vs BUF 7:20 PM". The system draws one line of text.
                Text(entry.tempGame.inline.isEmpty ? entry.followedTeam : entry.tempGame.inline)
            } else if family == .accessoryCircular {
                // One glanceable value, the start time, under the opponent
                // that names it (AC-1). The opponent is the accented line,
                // as the team name is on the rectangular widget.
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Text(entry.tempGame.teamName)
                            .font(.caption2.weight(.semibold))
                            .widgetAccentable()
                        if let message = entry.tempGame.message {
                            Text(message)
                                .font(.caption2)
                        } else {
                            Text(entry.tempGame.gameTime)
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // A fixed circle: the text scales only a little.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .padding(Theme.Spacing.xs)
                    .accessibilityElement(children: .combine)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.followedTeam)
                        .font(.headline)
                        .widgetAccentable()
                    if let message = entry.tempGame.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("vs \(entry.tempGame.teamName)")
                        Text("\(entry.tempGame.gameDate) \(entry.tempGame.gameTime)")
                            .foregroundStyle(.secondary)
                    }
                    if let note = entry.tempGame.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
/// install that has not reordered them), or ask for a team with none
/// followed.
struct TeamScheduleWidget: Widget {
    private var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
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
        .description("Shows the live score, latest result or next game of the team you choose, or your first favorite.")
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
        MyDayWidget()
        #if canImport(ActivityKit) && os(iOS)
        GameLiveActivity()
        #endif
        #if os(iOS)
        LiveGameControl()
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
            team: team,
            inline: "\(WidgetDayBuilder.label(of: team)) vs MIZ Sat 7:00 PM"
        )
        return WidgetEntry(date: .now, tempGame: game, followedTeam: team.shortName, teamID: team.id)
    }

    /// The off-season tile: the crest and one line.
    fileprivate static var notice: WidgetEntry {
        let team = WidgetTeams.fallback
        var game = WidgetGame.notice(WidgetTimelines.seasonOverMessage, for: team)
        game.backgroundLogo = UIImage(systemName: "shield.fill")?.pngData()
        return WidgetEntry(date: .now, tempGame: game, followedTeam: team.shortName, teamID: team.id)
    }
}

#Preview("Small · full colour", as: .systemSmall) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
    WidgetTimelines.placeholder(for: WidgetTeams.fallback)
    WidgetEntry.notice
}

#Preview("Medium · full colour", as: .systemMedium) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.notice
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

#Preview("Lock Screen · inline", as: .accessoryInline) {
    TeamScheduleWidget()
} timeline: {
    WidgetEntry.preview
    WidgetEntry.notice
}
#endif

#Preview("Small · no team", as: .systemSmall) {
    TeamScheduleWidget()
} timeline: {
    WidgetTimelines.noTeam
    WidgetTimelines.missingTeam(.unavailable)
}
