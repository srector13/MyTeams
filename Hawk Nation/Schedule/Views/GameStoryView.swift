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
/// the scoring timeline, the followed team's win probability, and each
/// team's injury report. A part the summary doesn't carry draws nothing.
///
/// A timeline row naming a player the sheet's own tables list opens their
/// sheet through `onPlayer` (C-6); `player` resolves the athlete id.
struct GameStoryView: View {
    let story: GameStory
    let league: LeagueDescriptor
    /// Whether the followed team is the home side: the win probability is
    /// drawn for the followed team, whichever side it is, and every running
    /// score reads the followed team's first (F5).
    var followedIsHome = true
    /// The followed team's accent (`TeamColors.accent(for:)`, F3), which
    /// draws the win-probability line (G4).
    var accent: Color = .accentColor
    var player: (String) -> GameSheetPlayer? = { _ in nil }
    var onPlayer: ((GameSheetPlayer) -> Void)? = nil

    /// How many of a timeline's latest events show before "Show all" (G3).
    nonisolated static let collapsedCount = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !story.timeline.isEmpty {
                timeline
            }
            if story.winProbability.count > 1 {
                WinProbabilityStrip(
                    points: story.winProbability,
                    marks: WinProbabilityMarks(
                        starts: story.winProbabilityPeriodStarts,
                        pointCount: story.winProbability.count,
                        style: league.periodStyle
                    ),
                    followedIsHome: followedIsHome,
                    abbreviation: followedIsHome ? story.homeAbbreviation : story.awayAbbreviation,
                    accent: accent
                )
            }
            let reports = story.injuries.filter { !$0.injuries.isEmpty }
            if !reports.isEmpty {
                injuries(reports)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    /// The events a timeline of `events` shows: the latest `limit` while
    /// collapsed, and every one once expanded or when there are no more
    /// than `limit` (G3).
    nonisolated static func visibleEvents(
        _ events: [TimelineEvent],
        showsAll: Bool,
        limit: Int = GameStoryView.collapsedCount
    ) -> [TimelineEvent] {
        guard !showsAll, events.count > limit else { return events }
        return Array(events.suffix(limit))
    }

    /// Whether a timeline row shows the points a score added ("+7"): only
    /// where one score can be worth more than one, so not a soccer goal or
    /// a hockey goal, whose "+1" said nothing (G6).
    nonisolated static func showsPointDeltas(_ kind: SportKind) -> Bool {
        kind != .soccer && kind != .hockey
    }

    /// "Show all 11" while collapsed, "Show fewer" once expanded.
    private var toggleTitle: String {
        showsAllEvents ? "Show fewer" : "Show all \(story.timeline.count)"
    }

    private var shownEvents: [TimelineEvent] {
        Self.visibleEvents(story.timeline, showsAll: showsAllEvents)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                sectionTitle("Timeline")
                Spacer(minLength: Theme.Spacing.s)
                if story.timeline.count > Self.collapsedCount {
                    // Expands in place, so a plain text button rather than
                    // the "See All ›" that opens another screen (F6).
                    Button(toggleTitle) {
                        withAnimation(Theme.Motion.animation(Theme.Motion.stateChange, reduceMotion: reduceMotion)) {
                            showsAllEvents.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityIdentifier("gameDetail.timeline.toggle")
                }
            }

            ForEach(shownEvents) { event in
                eventRow(event)
                    .opensPlayerSheet(event.athleteIDs.lazy.compactMap(player).first, onPlayer: onPlayer)

                if event.id != shownEvents.last?.id {
                    Divider()
                }
            }
        }
    }

    /// Soccer's one-line goal or card (G6); every other sport's scoring
    /// play with its period, clock and the feed's description.
    @ViewBuilder
    private func eventRow(_ event: TimelineEvent) -> some View {
        let abbreviation = story.abbreviation(teamID: event.teamID)
        if league.kind == .soccer {
            SoccerEventRow(line: SoccerEventLine(
                event: event,
                teamAbbreviation: abbreviation,
                followedIsHome: followedIsHome
            ))
        } else {
            TimelineRow(
                event: event,
                periodLabel: periodLabel(event),
                teamAbbreviation: abbreviation,
                followedIsHome: followedIsHome,
                showsPoints: Self.showsPointDeltas(league.kind)
            )
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

/// The running score after an event, the followed team's first with an en
/// dash (F5): "7–10"; `nil` for an event with no score (a card).
func teamFirstRunningScore(_ event: TimelineEvent, followedIsHome: Bool) -> String? {
    guard let home = event.homeScore, let away = event.awayScore else { return nil }
    return followedIsHome
        ? ScoreLine.score(team: "\(home)", opponent: "\(away)")
        : ScoreLine.score(team: "\(away)", opponent: "\(home)")
}

/// One scoring play: the team, period and clock, what happened, and the
/// score after, the followed team's first.
private struct TimelineRow: View {
    let event: TimelineEvent
    let periodLabel: String
    let teamAbbreviation: String
    let followedIsHome: Bool
    /// Whether to show the points the play added. See
    /// `GameStoryView.showsPointDeltas(_:)`.
    let showsPoints: Bool

    private var when: String {
        [periodLabel, event.clock].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text([teamAbbreviation, when].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.metadata)
                Text(event.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let score = teamFirstRunningScore(event, followedIsHome: followedIsHome) {
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text(score)
                        .font(.body.bold().monospacedDigit())
                    if showsPoints, let points = event.points, points > 0 {
                        Text("+\(points)")
                            .font(Theme.Typography.caption.bold().monospacedDigit())
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One soccer event as its timeline line reads it (G6): the minute, a
/// glyph for the goal or card, the player in bold, a caption ("Assist
/// Andy Nájar · NSH", "Header · assist … · NSH", "Yellow card · NSH") and,
/// for a goal, the running score with the followed team's first. ESPN's
/// long commentary is left out. Pure, so the tests drive it.
struct SoccerEventLine: Equatable {
    enum Glyph: Equatable {
        case goal
        case yellowCard
        case redCard
    }

    /// "10′", "90+5′"; empty when the feed gives no clock.
    var minute: String
    var glyph: Glyph
    /// The scorer or the booked player, or what happened when the feed
    /// names no one.
    var title: String
    /// The goal's kind and assist, or the card, then the team; empty when
    /// there is none of those.
    var caption: String
    /// The score after a goal, the followed team's first: "0–1". `nil` for
    /// a card.
    var score: String?

    init(event: TimelineEvent, teamAbbreviation: String, followedIsHome: Bool) {
        minute = TimelineEvent.soccerMinute(event.clock)
        let what: String
        switch event.kind {
        case .score:
            glyph = .goal
            what = "Goal"
        case .yellowCard:
            glyph = .yellowCard
            what = "Yellow card"
        case .redCard:
            glyph = .redCard
            what = "Red card"
        }
        let names = event.athleteNames
        let named = names.first ?? ""
        title = named.isEmpty ? what : named

        var parts: [String] = []
        if event.kind == .score {
            if !event.detail.isEmpty { parts.append(event.detail) }
            // The second participant of a goal is its assist; an own goal
            // has none.
            if event.detail != "Own goal", names.count > 1 {
                parts.append(parts.isEmpty ? "Assist \(names[1])" : "assist \(names[1])")
            }
        } else if !named.isEmpty {
            // The glyph's colour is not the only cue (D-6).
            parts.append(what)
        }
        let team = teamAbbreviation.trimmingCharacters(in: .whitespaces)
        if !team.isEmpty { parts.append(team) }
        caption = parts.joined(separator: " · ")
        score = event.kind == .score ? teamFirstRunningScore(event, followedIsHome: followedIsHome) : nil
    }

    /// What VoiceOver reads: "Goal, minute 10, Hany Mukhtar, Assist Andy
    /// Nájar · NSH, 0–1".
    var accessibilityText: String {
        let word: String = switch glyph {
        case .goal: "Goal"
        case .yellowCard: "Yellow card"
        case .redCard: "Red card"
        }
        let spokenMinute = minute.isEmpty ? "" : "minute \(minute.replacingOccurrences(of: "\u{2032}", with: ""))"
        let head = title == word ? [word, spokenMinute] : [word, spokenMinute, title]
        return (head + [caption, score ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A soccer event's line (G6): minute, glyph, player and caption, score.
private struct SoccerEventRow: View {
    let line: SoccerEventLine

    @ScaledMetric(relativeTo: .subheadline) private var minuteWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text(line.minute)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(Theme.Palette.metadata)
                .lineLimit(1)
                .frame(minWidth: minuteWidth, alignment: .leading)

            glyph
                .frame(width: glyphSize, height: glyphSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.body.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !line.caption.isEmpty {
                    Text(line.caption)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.metadata)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let score = line.score {
                Text(score)
                    .font(.body.bold().monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        // One element that says what the ball and the card's colour show.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityText)
    }

    @ViewBuilder
    private var glyph: some View {
        switch line.glyph {
        case .goal:
            Image(systemName: "soccerball")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
        case .yellowCard:
            card(.yellow)
        case .redCard:
            card(.red)
        }
    }

    /// A referee's card, drawn as a glyph: its corner is part of the
    /// drawing at this size, not a surface radius.
    private func card(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: glyphSize * 0.55, height: glyphSize * 0.8)
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
                    .font(Theme.Typography.caption.bold())
                    .foregroundStyle(Theme.Palette.metadata)
            }
            let extra = [
                injuryText,
                injury.returnDate.isEmpty ? "" : "Return \(Self.returnDate(injury.returnDate))",
            ].filter { !$0.isEmpty }.joined(separator: " · ")
            if !extra.isEmpty {
                Text(extra)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.metadata)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `"2026-10-15"` in the sheet's one date style, "Thu, Oct 15" (with the
    /// year when it isn't this one), read as the calendar day it names;
    /// anything else as the feed wrote it.
    private static func returnDate(_ value: String) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = utc
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = utc
        return GameCardContent.fullDate(of: date, now: .now, calendar: calendar)
    }
}

// MARK: - Win probability

/// Where the win-probability chart marks its periods (G4): a rule where
/// each period after the first begins, and each period's label ("Q1",
/// "H2", "OT", or an inning's number) centred over its stretch of the
/// line. Empty when the summary placed no point in a period. Pure, so the
/// tests drive it.
struct WinProbabilityMarks: Equatable {
    /// The x of each period's first point after the first period's.
    var boundaries: [Double] = []
    /// Each period's label, in order.
    var labels: [String] = []
    /// The x of the middle of each period's stretch, parallel to `labels`.
    var centers: [Double] = []

    init(starts: [GameStory.PeriodStart], pointCount: Int, style: LeagueDescriptor.PeriodStyle) {
        guard pointCount > 1, !starts.isEmpty else { return }
        let last = Double(pointCount - 1)
        boundaries = starts.dropFirst().map { Double($0.index) }
        for (offset, start) in starts.enumerated() {
            // The first period runs from the chart's left edge, over any
            // opening point that precedes its first play.
            let from = offset == 0 ? 0 : Double(start.index)
            let to = offset + 1 < starts.count ? Double(starts[offset + 1].index) : last
            labels.append(Self.label(period: start.period, style: style))
            centers.append((from + to) / 2)
        }
    }

    /// The label under period `period`: "Q1"–"Q4" for quarters, "H1" and
    /// "H2" for halves, "P1"–"P3" for hockey's periods, then "OT", "2OT" …;
    /// baseball's innings by number.
    static func label(period: Int, style: LeagueDescriptor.PeriodStyle) -> String {
        let regulation: Int?
        let prefix: String
        switch style {
        case .quarters:
            regulation = 4
            prefix = "Q"
        case .halves:
            regulation = 2
            prefix = "H"
        case .periods:
            regulation = 3
            prefix = "P"
        case .unnamed:
            regulation = nil
            prefix = ""
        }
        if let regulation, period > regulation {
            return overtimeLabel(period - regulation)
        }
        return "\(prefix)\(period)"
    }

    /// `labels[index]`, or empty past its end.
    func label(at index: Int) -> String {
        labels.indices.contains(index) ? labels[index] : ""
    }
}

/// The followed team's chance of winning over the game's plays, 0–100%,
/// with an even-odds rule at 50%, drawn in the team's accent with the
/// periods marked beneath (G4). The feed gives the home side's chance: an
/// away team's is its complement.
private struct WinProbabilityStrip: View {
    let points: [WinProbabilityPoint]
    let marks: WinProbabilityMarks
    let followedIsHome: Bool
    /// The followed team's abbreviation, or empty.
    let abbreviation: String
    /// The followed team's accent, for the line.
    let accent: Color

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 120

    private var title: String {
        if abbreviation.isEmpty {
            return followedIsHome ? "Home win probability" : "Away win probability"
        }
        return "\(abbreviation) win probability"
    }

    /// The followed team's chance after `point`, from 0 to 1.
    private func chance(_ point: WinProbabilityPoint) -> Double {
        followedIsHome ? point.homeWinPercentage : 1 - point.homeWinPercentage
    }

    private var latest: Int {
        Int(((points.last.map(chance) ?? 0) * 100).rounded())
    }

    /// The x axis's right edge: the last point's index.
    private var lastX: Double { Double(max(points.count - 1, 1)) }

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
                        x: .value("Play", Double(point.index)),
                        y: .value("Win %", chance(point) * 100)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...lastX)
            .chartXAxis {
                // A rule where each period after the first begins…
                AxisMarks(values: marks.boundaries) { _ in
                    AxisGridLine()
                }
                // …and each period's name under the middle of its stretch.
                AxisMarks(values: marks.centers) { value in
                    AxisValueLabel {
                        Text(marks.label(at: value.index))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let pct = value.as(Double.self) {
                            Text("\(Int(pct))%")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.metadata)
                        }
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
