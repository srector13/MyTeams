//
//  MyDayWidget.swift
//  myTeamWidget
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import WidgetKit
import SwiftUI
import UIKit

/// The "My Day" widget's entry: up to six of the favorites' games, live,
/// today's and next (R-9), each with its crests.
struct DayEntry: TimelineEntry {
    /// A row and the crests it draws, read downscaled from `LogoStore`.
    struct Row: Identifiable, Sendable {
        let row: WidgetDayRow
        var teamCrest: Data?
        var opponentCrest: Data?

        var id: String { row.id }
    }

    var date: Date
    var rows: [Row]
    /// Whether no team is followed: the widget then asks for one.
    var needsTeam = false
}

/// Builds the "My Day" entries.
enum DayTimelines {
    /// The one line the widget shows with favorites but no games in Home's
    /// windows.
    static let noGamesMessage = "No games in the next 7 days"

    static var noTeam: DayEntry {
        DayEntry(date: .now, rows: [], needsTeam: true)
    }

    /// Every favorite's games, from the stored schedules when fresh (R-4)
    /// and the app's scoreboard snapshot.
    static func entry(now: Date = .now) async -> DayEntry {
        let teams = await WidgetTeams.favorites()
        guard !teams.isEmpty else { return noTeam }
        let seasons = await WidgetScheduleLoader.seasons(for: teams)
        let rows = WidgetDayBuilder().rows(
            teams: teams,
            seasons: seasons,
            snapshots: WidgetScoreboardCodec.read(),
            now: now
        )
        return DayEntry(date: now, rows: rows.map(WidgetScheduleLoader.dayRow))
    }

    /// Looks again every few minutes while a game is under way, else at the
    /// next start, else hourly; never sooner than a minute.
    static func timeline(now: Date = .now) async -> Timeline<DayEntry> {
        let current = await Self.entry(now: now)
        var reload = now + WidgetTimelines.refreshInterval
        if current.rows.contains(where: { $0.row.kind == .live }) {
            reload = now + WidgetScheduleLoader.liveRefreshInterval
        } else if let start = current.rows.compactMap({ $0.row.score == nil ? $0.row.start : nil }).filter({ $0 > now }).min() {
            reload = min(reload, max(start, now + 60))
        }
        #if os(iOS)
        // The snapshot that changed this timeline may change the control's
        // live game too.
        await LiveGameControl.reload()
        #endif
        return Timeline(entries: [current], policy: .after(reload))
    }
}

/// The "My Day" widget has no settings; an intent without parameters lets
/// its provider use the async methods, as `TeamTimelineProvider` does,
/// rather than hold completion handlers across a task.
struct MyDayIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "My Day"
    static let description = IntentDescription("Your favorites' live games, today's games and what's next.")

    init() {}
}

struct DayTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        .preview
    }

    func snapshot(for configuration: MyDayIntent, in context: Context) async -> DayEntry {
        if context.isPreview {
            // The gallery shows what the widget does, on sample games.
            return .preview
        }
        return await DayTimelines.entry()
    }

    func timeline(for configuration: MyDayIntent, in context: Context) async -> Timeline<DayEntry> {
        await DayTimelines.timeline()
    }
}

/// The large tile: a header, then a row per game, each a link to the game's
/// sheet (R-3).
///
/// Follows the Team Schedule tile's rendering-mode rules (W-1): nothing the
/// reader needs lives in the container background, the header is the
/// accented line, and crests keep their shape, desaturated, when the system
/// tints. Takes `renderingMode` rather than reading it, so previews can draw
/// each mode.
struct MyDayView: View {
    var entry: DayEntry
    var renderingMode: WidgetRenderingMode

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.needsTeam {
            NoTeamView(family: family)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("My Day")
                    .font(Theme.Typography.cardTitle)
                    .widgetAccentable()
                if entry.rows.isEmpty {
                    Spacer()
                    Text(DayTimelines.noGamesMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(entry.rows) { row in
                        rowLink(row)
                        if row.id != entry.rows.last?.id {
                            Divider()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private func rowLink(_ row: DayEntry.Row) -> some View {
        if let url = row.row.url {
            Link(destination: url) { DayRowView(row: row, renderingMode: renderingMode) }
        } else {
            DayRowView(row: row, renderingMode: renderingMode)
        }
    }
}

/// One game: the favorite's crest, the matchup, and the score or start.
private struct DayRowView: View {
    var row: DayEntry.Row
    var renderingMode: WidgetRenderingMode

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            crest(row.teamCrest)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(row.row.team.shortName) vs \(row.row.opponentName)")
                    .font(Theme.Typography.footnote.weight(.semibold))
                if let channel = row.row.channel {
                    Text(channel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 0) {
                if let score = row.row.score {
                    Text(score)
                        .font(Theme.Typography.footnote.weight(.bold))
                        .monospacedDigit()
                }
                Text(row.row.status)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(
                        row.row.kind == .live && renderingMode == .fullColor
                            ? AnyShapeStyle(Color.red)
                            : AnyShapeStyle(HierarchicalShapeStyle.secondary)
                    )
                    .widgetAccentable(row.row.kind == .live)
            }
            .layoutPriority(1)
            crest(row.opponentCrest)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func crest(_ data: Data?) -> some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    // Kept recognisable, in grey, when the system tints.
                    .widgetAccentedRenderingMode(.desaturated)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

/// The favorites' day in one widget (R-9): up to six games across every
/// favorite, so six favorites need one widget rather than six.
struct MyDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "myTeamsDay", intent: MyDayIntent.self, provider: DayTimelineProvider()) { entry in
            MyDayEntryView(entry: entry)
        }
        .configurationDisplayName("My Day")
        .description("Your favorites' live games, today's games and what's next.")
        // The system offers the extra-large size on iPad only.
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// Reads the rendering mode for `MyDayView`.
struct MyDayEntryView: View {
    var entry: DayEntry

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        MyDayView(entry: entry, renderingMode: renderingMode)
    }
}

// Previews: as the Team Schedule widget's (`myTeamWidget.swift`), the widget
// previews draw in full colour, and the `MyDayView` previews draw the tile
// as the Clear and Tinted appearances (`.accented`) leave it.

extension DayEntry {
    /// A day with a game under way, one later today and the next, with
    /// stand-in crests.
    static var preview: DayEntry {
        let team = WidgetTeams.fallback
        let crest = UIImage(systemName: "shield.fill")?.pngData()
        let now = Date.now
        func row(_ kind: WidgetDayRow.Kind, _ id: String, _ opponent: String, score: String?, status: String, inline: String) -> Row {
            Row(
                row: WidgetDayRow(
                    kind: kind, team: team, gameID: id, league: team.league, opponentName: opponent,
                    opponentID: "", score: score, status: status, start: now, channel: kind == .live ? nil : "ESPN",
                    inline: inline, id: id
                ),
                teamCrest: crest,
                opponentCrest: crest
            )
        }
        return DayEntry(date: now, rows: [
            row(.live, "1", "Missouri", score: "41–38", status: "Live · 4:12", inline: "KU 41–38 H2"),
            row(.today, "2", "Kansas State", score: nil, status: "8:00 PM", inline: "KU vs KSU 8:00 PM"),
            row(.next, "3", "Baylor", score: nil, status: "Sat 1:00 PM", inline: "KU vs BAY Sat 1:00 PM"),
            row(.next, "4", "Iowa State", score: nil, status: "Tue 7:00 PM", inline: "KU vs ISU Tue 7:00 PM"),
        ])
    }
}

#Preview("Large · full colour", as: .systemLarge) {
    MyDayWidget()
} timeline: {
    DayEntry.preview
    DayEntry(date: .now, rows: [])
    DayTimelines.noTeam
}

#Preview("Large · Clear/Tinted (accented)", traits: .fixedLayout(width: 364, height: 382)) {
    MyDayView(entry: .preview, renderingMode: .accented)
        .background(Theme.Surface.content)
}

#Preview("Large · full colour (view)", traits: .fixedLayout(width: 364, height: 382)) {
    MyDayView(entry: .preview, renderingMode: .fullColor)
        .background(Theme.Surface.content)
}
