//
//  GameStoryView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Charts
import SwiftUI

/// A game sheet's "story" (R-2), between the scoreboard and the box score:
/// the scoring timeline, the home side's win probability, and each team's
/// injury report. A part the summary doesn't carry draws nothing.
///
/// A timeline row naming a player the sheet's own tables list opens their
/// sheet through `onPlayer` (C-6); `player` resolves the athlete id.
struct GameStoryView: View {
    let story: GameStory
    let league: LeagueDescriptor
    var player: (String) -> GameSheetPlayer? = { _ in nil }
    var onPlayer: ((GameSheetPlayer) -> Void)? = nil

    /// How many of a long timeline's latest events show before "Show all".
    private static let collapsedCount = 10

    @State private var showsAllEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !story.timeline.isEmpty {
                timeline
            }
            if story.winProbability.count > 1 {
                WinProbabilityStrip(points: story.winProbability, homeAbbreviation: story.homeAbbreviation)
            }
            let reports = story.injuries.filter { !$0.injuries.isEmpty }
            if !reports.isEmpty {
                injuries(reports)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    private var shownEvents: [TimelineEvent] {
        guard !showsAllEvents, story.timeline.count > Self.collapsedCount else { return story.timeline }
        return Array(story.timeline.suffix(Self.collapsedCount))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Timeline")

            if story.timeline.count > Self.collapsedCount {
                let title = showsAllEvents
                    ? "Show latest \(Self.collapsedCount)"
                    : "Show all \(story.timeline.count)"
                Button(title) {
                    withAnimation { showsAllEvents.toggle() }
                }
                .font(Theme.Typography.caption)
                .accessibilityIdentifier("gameDetail.timeline.toggle")
            }

            ForEach(shownEvents) { event in
                TimelineRow(
                    event: event,
                    periodLabel: periodLabel(event),
                    teamAbbreviation: story.abbreviation(teamID: event.teamID)
                )
                .opensPlayerSheet(event.athleteIDs.lazy.compactMap(player).first, onPlayer: onPlayer)

                if event.id != shownEvents.last?.id {
                    Divider()
                }
            }
        }
    }

    /// The feed's period name, or the league's; soccer's minute says enough.
    private func periodLabel(_ event: TimelineEvent) -> String {
        if !event.periodLabel.isEmpty { return event.periodLabel }
        guard league.kind != .soccer, event.period > 0 else { return "" }
        return league.liveCardPeriodLabel(String(event.period))
    }

    // MARK: - Injuries

    private func injuries(_ reports: [TeamInjuries]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionTitle("Injuries")

            ForEach(reports) { report in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(report.injuries) { injury in
                            InjuryRow(injury: injury)
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                } label: {
                    Text("\(report.name) (\(report.injuries.count))")
                        .font(.subheadline.bold())
                }
                .accessibilityIdentifier("gameDetail.injuries.\(report.id)")
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Rows

/// One timeline event: period and clock, what happened, and the score after.
private struct TimelineRow: View {
    let event: TimelineEvent
    let periodLabel: String
    let teamAbbreviation: String

    private var when: String {
        [periodLabel, event.clock].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    if event.kind != .score {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(event.kind == .redCard ? Color.red : Color.yellow)
                            .frame(width: 8, height: 11)
                            .accessibilityHidden(true)
                    }
                    Text([teamAbbreviation, when].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(event.text)
                    .font(Theme.Typography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let home = event.homeScore, let away = event.awayScore {
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    // Home first, as the rest of the sheet puts home first.
                    Text("\(home) - \(away)")
                        .font(.subheadline.bold().monospacedDigit())
                    if let points = event.points, points > 0 {
                        Text("+\(points)")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One injured player: name and position, status, and when they're due back.
private struct InjuryRow: View {
    let injury: InjuryEntry

    private var injuryText: String {
        [injury.side, injury.injury, injury.detail].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(injury.position.isEmpty ? injury.name : "\(injury.name), \(injury.position)")
                    .font(Theme.Typography.caption.bold())
                Spacer(minLength: Theme.Spacing.s)
                Text(injury.status)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            let extra = [
                injuryText,
                injury.returnDate.isEmpty ? "" : "Return \(Self.returnDate(injury.returnDate))",
            ].filter { !$0.isEmpty }.joined(separator: " · ")
            if !extra.isEmpty {
                Text(extra)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `"2026-10-15"` as a short date in the reader's locale; anything else
    /// as the feed wrote it.
    private static func returnDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = parser.timeZone
        return date.formatted(style)
    }
}

// MARK: - Win probability

/// The home side's chance of winning over the game's plays, 0–100%, with
/// an even-odds rule at 50%.
private struct WinProbabilityStrip: View {
    let points: [WinProbabilityPoint]
    let homeAbbreviation: String

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 90

    private var title: String {
        homeAbbreviation.isEmpty ? "Home win probability" : "\(homeAbbreviation) win probability"
    }

    private var latest: Int {
        Int(((points.last?.homeWinPercentage ?? 0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(latest)%")
                    .font(.subheadline.bold().monospacedDigit())
            }

            Chart {
                RuleMark(y: .value("Even", 50.0))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(points) { point in
                    LineMark(
                        x: .value("Play", point.index),
                        y: .value("Win %", point.homeWinPercentage * 100)
                    )
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let pct = value.as(Double.self) { Text("\(Int(pct))%") }
                    }
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(latest)% after the latest play")
        }
    }
}
