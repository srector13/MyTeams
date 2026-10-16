//
//  HomeDashboardCards.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

// The cards in Home's carousels (`HomeView`): a favorite's card in My
// Teams, a day in This Week's strip, a favorite's slice of its standings,
// and its top performer. Each nests in its section's card on the inset
// surface (X-4), in the team page's language: the team colour with its
// ink (G-3), crests cut out on it with nothing behind them
// (`CutoutCrest`), the followed row on a faint band.

// MARK: - My Teams

/// A favorite's card in My Teams: over its colour, its crest, poll rank and
/// short name, its record large, its standing and its last five results;
/// beneath, on the inset surface, where its season is — the game under
/// way, the next game, the last result, or the season over or to come.
///
/// Fixed width in the carousel, scaled with its text; at accessibility
/// sizes, where My Teams is a vertical list, it spans the list's width.
struct HomeTeamCard: View {
    let summary: HomeTeamSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 196
    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 32

    private var team: TeamRef { summary.team }
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isLoading: Bool { summary.status == .loading }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            foot
        }
        .frame(width: fillsRow ? nil : cardWidth, alignment: .leading)
        // As tall as the carousel's tallest card, so the feet line up.
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil, maxHeight: .infinity, alignment: .top)
        .background(Theme.Surface.insetCard)
        // Nested in the section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
        .contentShape(Theme.Radius.innerShape)
    }

    /// The team colour, with the crest, name, record, standing and form in
    /// its ink.
    private var top: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                CutoutCrest(team: team, size: crestSize, onHex: TeamColors.fillHex(for: team))
                if let badge = PollRanks.badge(rank: summary.pollRank) {
                    Text(badge)
                        .font(.subheadline.weight(.heavy))
                        .monospacedDigit()
                }
                Text(team.shortName)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(fillsRow ? nil : 1)
                    .minimumScaleFactor(0.8)
            }

            figures
        }
        .foregroundStyle(TeamColors.ink(on: team))
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hexString: TeamColors.fillHex(for: team)))
    }

    /// The record, standing and form; placeholders while the season loads
    /// (D-7).
    @ViewBuilder
    private var figures: some View {
        let header = summary.header
        let content = VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // No record yet (a season not started): the season's state
            // in the figure's place, not a dash.
            Text(header.record ?? (isLoading ? "0-0" : summary.status.text))
                .font(header.record == nil && !isLoading ? Theme.Typography.cardTitle : Theme.Typography.statFigure)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let standing = header.standing {
                Text(standing)
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .lineLimit(fillsRow ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading {
                Text("1st in Conference")
                    .font(Theme.Typography.footnote.weight(.semibold))
            }

            if !header.form.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(header.form.enumerated()), id: \.offset) { _, outcome in
                        FormCapsule(outcome: outcome)
                    }
                }
            }
        }
        if isLoading {
            content
                .redacted(reason: .placeholder)
                .placeholderPulse()
        } else {
            content
        }
    }

    /// Where the season is, in secondary text on the inset surface.
    @ViewBuilder
    private var foot: some View {
        let status = Label(summary.status.text, systemImage: summary.status.systemImage)
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(fillsRow ? nil : 2)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        if isLoading {
            status
                .redacted(reason: .placeholder)
                .placeholderPulse()
        } else {
            status
        }
    }
}

extension HomeTeamSummary {
    /// "Chiefs, ranked number 7, record 4 and 0, 1st in AFC West, last 5:
    /// won, won, lost, won, won, Next vs Chargers · Sun 3:25 PM": the card
    /// read as one line, its record's dashes spoken.
    var accessibilityLabel: String {
        var parts = [team.shortName]
        if let pollRank, pollRank > 0 {
            parts.append("ranked number \(pollRank)")
        }
        if status == .loading {
            parts.append("Loading")
            return parts.joined(separator: ", ")
        }
        if let record = header.record {
            parts.append("record " + record.replacingOccurrences(of: "-", with: " and "))
        }
        if let standing = header.standing {
            parts.append(standing)
        }
        if let form = header.formAccessibilityLabel {
            parts.append(form)
        }
        parts.append(status.text)
        return parts.joined(separator: ", ")
    }
}

// MARK: - This Week

/// A day in This Week's strip: its weekday (or "Today") over its date, and
/// a dot in each game's team colour beneath. The day picked is ringed and
/// washed in the accent; the date's figure is bold on today. At least 44 pt
/// in each direction (T-1).
struct HomeWeekDayButton: View {
    let day: HomeWeekDay
    let isToday: Bool
    let isSelected: Bool
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var minWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 6

    /// The most dots a day draws; a busier day still says its count to
    /// VoiceOver.
    static let maxDots = 4

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected || isToday ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(day.date.formatted(.dateTime.day()))
                    .font(.headline.weight(isToday || isSelected ? .heavy : .regular))
                    .monospacedDigit()
                dots
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.s)
            .frame(minWidth: minWidth, minHeight: 44)
            .background { background }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// One dot per game, up to `maxDots`; a quiet day keeps the row's
    /// height with nothing in it.
    private var dots: some View {
        HStack(spacing: 2) {
            ForEach(Array(day.games.prefix(Self.maxDots))) { entry in
                Circle()
                    .fill(Color(hexString: TeamColors.fillHex(for: entry.team)))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                    }
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .frame(height: dotSize)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            // The app's tint, the reader's brand theme's accent.
            ZStack {
                Capsule()
                    .fill(.tint)
                    .opacity(0.18)
                Capsule()
                    .strokeBorder(.tint, lineWidth: 1.5)
            }
        } else {
            Capsule()
                .fill(Theme.Surface.insetCard)
        }
    }

    /// "Saturday, September 26, today, 2 games".
    private var spokenLabel: String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if isToday {
            parts.append("today")
        }
        switch day.games.count {
        case 0: parts.append("no games")
        case 1: parts.append("1 game")
        default: parts.append("\(day.games.count) games")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Standings

/// A favorite's slice of its table: the table's name beside its crest,
/// then its row and the rows either side — rank, crest, name, record, and
/// the points (soccer) or the streak — the favorite's on one continuous
/// band of its colour, as a team page's standings pick it out (T-7).
struct HomeStandingsCard: View {
    let slice: HomeStandingsSlice

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .footnote) private var cardWidth: CGFloat = 264
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var rankWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) private var recordWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .footnote) private var lastWidth: CGFloat = 36

    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The last column: a soccer table's points, else the streak where the
    /// feed keeps one; none for a poll.
    private enum LastColumn {
        case points
        case streak
    }

    private var lastColumn: LastColumn? {
        switch slice.kind {
        case .pointsTable: return .points
        case .rankings: return nil
        case .records: return slice.rows.contains { !$0.entry.streak.isEmpty } ? .streak : nil
        }
    }

    var body: some View {
        let column = lastColumn
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                // On the inset surface: the crest as the rows draw theirs,
                // outlined in Dark Mode only where it would sink into the
                // card (`crestOutlineRule`).
                TeamLogo(team: slice.team, size: crestSize + 6)
                Text(slice.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(fillsRow ? nil : 1)
            }

            VStack(spacing: 2) {
                heading(column)
                ForEach(slice.rows) { row in
                    rowView(row, lastColumn: column)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: fillsRow ? nil : cardWidth, alignment: .leading)
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil, alignment: .leading)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .contentShape(Theme.Radius.innerShape)
    }

    /// The columns' headings, silent to VoiceOver: each row says its own.
    private func heading(_ lastColumn: LastColumn?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("#")
                .frame(minWidth: rankWidth, alignment: .trailing)
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(slice.kind == .pointsTable ? "W-D-L" : "Record")
                .frame(minWidth: recordWidth, alignment: .trailing)
            if let lastColumn {
                Text(lastColumn == .points ? "Pts" : "Strk")
                    .frame(minWidth: lastWidth, alignment: .trailing)
            }
        }
        .font(Theme.Typography.statLabel)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityHidden(true)
    }

    private func rowView(_ row: HomeStandingsSlice.Row, lastColumn: LastColumn?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("\(row.rank)")
                .foregroundStyle(.secondary)
                .frame(minWidth: rankWidth, alignment: .trailing)
            HStack(spacing: Theme.Spacing.xs) {
                TeamLogo(team: crestTeam(for: row.entry), size: crestSize)
                Text(name(of: row.entry))
                    .lineLimit(1)
                if row.isFollowed {
                    FollowedMarker()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(record(of: row.entry))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: recordWidth, alignment: .trailing)
            if let lastColumn {
                Text(value(of: row.entry, in: lastColumn))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: lastWidth, alignment: .trailing)
            }
        }
        .font(.footnote)
        .fontWeight(row.isFollowed ? .bold : .regular)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.xs)
        // One band behind the whole row: a stack's background spans its
        // columns, where a grid's broke into one per cell.
        .background {
            if row.isFollowed {
                RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous)
                    .fill(Color(hexString: TeamColors.fillHex(for: slice.team)).opacity(Theme.selectionWashOpacity(contrast: contrast)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow(row, lastColumn: lastColumn))
        .accessibilityAddTraits(row.isFollowed ? .isSelected : [])
    }

    private func name(of entry: StandingsEntry) -> String {
        entry.shortName.isEmpty ? entry.name : entry.shortName
    }

    /// The record without the points a soccer row's summary carries, which
    /// have their own column: `"5-0-0"`.
    private func record(of entry: StandingsEntry) -> String {
        let record = entry.record
        if slice.kind == .pointsTable {
            return "\(record.wins)-\(record.ties)-\(record.losses)"
        }
        return record.summary
    }

    private func value(of entry: StandingsEntry, in column: LastColumn) -> String {
        switch column {
        case .points: return entry.record.points.map(String.init) ?? ""
        case .streak: return entry.streak
        }
    }

    /// "1st, Chiefs, 4-0, streak W4".
    private func spokenRow(_ row: HomeStandingsSlice.Row, lastColumn: LastColumn?) -> String {
        var parts = [ordinalString(row.rank), name(of: row.entry), record(of: row.entry)]
        if let lastColumn {
            let value = value(of: row.entry, in: lastColumn)
            if !value.isEmpty {
                parts.append(lastColumn == .points ? "\(value) points" : "streak \(value)")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// A stand-in `TeamRef` for drawing a row's crest through `TeamLogo`,
    /// which falls back to a monogram, as the team page's table does.
    private func crestTeam(for entry: StandingsEntry) -> TeamRef {
        TeamRef(
            league: slice.team.league, espnID: entry.teamID,
            displayName: entry.name, shortName: entry.shortName,
            abbreviation: entry.abbreviation, location: "",
            colorHex: "", alternateColorHex: "",
            logoURL: entry.logoURL, logoDarkURL: nil, logoAsset: nil
        )
    }
}

extension HomeStandingsSlice {
    /// "Chiefs standings, AFC West: 1st, Chiefs, 4-0; 2nd, Chargers, 3-1".
    var accessibilityLabel: String {
        let lines = rows.map { row -> String in
            let name = row.entry.shortName.isEmpty ? row.entry.name : row.entry.shortName
            return "\(ordinalString(row.rank)), \(name), \(row.entry.record.summary)"
        }
        return "\(team.shortName) standings, \(title): " + lines.joined(separator: "; ")
    }
}

/// A slice's placeholder while the standings load (X-6): its size, in
/// skeleton blocks.
struct HomeStandingsCardPlaceholder: View {
    @ScaledMetric(relativeTo: .footnote) private var cardWidth: CGFloat = 264
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            LoadingView()
                .frame(width: 120, height: lineHeight)
            ForEach(0..<4, id: \.self) { _ in
                LoadingView()
                    .frame(height: lineHeight)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: cardWidth, alignment: .leading)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }
}

// MARK: - Top performers

/// A favorite's top performer: the team page's leader card
/// (`TeamLeaderCard`), its headshot found as a roster's is, with the
/// favorite's crest in its corner, nothing behind it, to say whose leader
/// it is.
struct HomePerformerCard: View {
    let performer: HomePerformer

    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 20

    var body: some View {
        TeamLeaderCard(
            board: performer.board,
            row: performer.row,
            teamColor: Color(hexString: TeamColors.fillHex(for: performer.team)),
            team: performer.team
        )
        .overlay(alignment: .topLeading) {
            // On the inset surface: outlined in Dark Mode only where it
            // would sink into the card (`crestOutlineRule`).
            TeamLogo(team: performer.team, size: crestSize)
                .padding(Theme.Spacing.s)
        }
        .contentShape(Theme.Radius.innerShape)
    }
}

extension HomePerformer {
    /// "Chiefs: Patrick Mahomes, 1,234 passing yards".
    var accessibilityLabel: String {
        let name = row.leader.name.isEmpty ? row.leader.shortName : row.leader.name
        return "\(team.shortName): \(name), \(row.value) \(board.title)"
    }
}
