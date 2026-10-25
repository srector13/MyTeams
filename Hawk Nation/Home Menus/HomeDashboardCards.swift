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
/// way, the next game, the last result — or, when the header already
/// shows the season's state, what's next (H2: the status shows once).
///
/// Every card's coloured header is at least `headerMinHeight` tall and its
/// foot one line, so the feet line up across a row (H2). The width is the
/// row's: a share of the carousel on an iPhone, a grid column on an iPad
/// (H10), the list's width at accessibility sizes.
struct HomeTeamCard: View {
    let summary: HomeTeamSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 32
    /// The header's height with a record, a one-line standing and form
    /// pills: the tallest it is outside accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var headerMinHeight: CGFloat = 136

    private var team: TeamRef { summary.team }
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isLoading: Bool { summary.status == .loading }
    private var fill: Color { Color(hexString: TeamColors.fillHex(for: team)) }
    private var ink: Color { TeamColors.ink(on: team) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            foot
        }
        // As tall as the row's tallest card, its header taking up the
        // difference, so the feet line up.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Surface.insetCard)
        // Nested in the section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
        .contentShape(Theme.Radius.innerShape)
    }

    /// The team colour, with the crest, name, record, standing and form in
    /// its ink (F2).
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
        .foregroundStyle(ink)
        .padding(Theme.Spacing.m)
        .frame(
            maxWidth: .infinity,
            minHeight: fillsRow ? nil : headerMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(fill)
    }

    /// The record, standing and form; placeholders while the season loads
    /// (D-7).
    @ViewBuilder
    private var figures: some View {
        let header = summary.header
        let content = VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // No record yet (a season not started): the season's state
            // in the figure's place, not a dash; the foot then says
            // what's next rather than repeating it.
            Text(header.record ?? (isLoading ? "0-0" : summary.headerStatusText))
                .font(header.record == nil && !isLoading ? Theme.Typography.cardTitle : Theme.Typography.statFigure)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let standing = header.standing {
                Text(standing)
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .lineLimit(fillsRow ? nil : 1)
                    .minimumScaleFactor(0.75)
            } else if isLoading {
                Text("1st in Conference")
                    .font(Theme.Typography.footnote.weight(.semibold))
            }

            if !header.form.isEmpty {
                // Solid pills on the team colour (F4, H7).
                HStack(spacing: 3) {
                    ForEach(Array(header.form.enumerated()), id: \.offset) { _, outcome in
                        FormCapsule(outcome: outcome, ink: ink, fill: fill)
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

    /// Where the season is, or what's next, in the metadata grey on the
    /// inset surface (F1). One line in a row of cards, so the feet match.
    @ViewBuilder
    private var foot: some View {
        let status = Label(summary.footText, systemImage: summary.status.systemImage)
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundStyle(Theme.Palette.metadata)
            .lineLimit(fillsRow ? nil : 1)
            .minimumScaleFactor(0.85)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        } else {
            parts.append(headerStatusText)
        }
        if let standing = header.standing {
            parts.append(standing)
        }
        if let form = header.formAccessibilityLabel {
            parts.append(form)
        }
        parts.append(footText)
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
                    .foregroundStyle(isSelected || isToday ? Color.primary : Theme.Palette.metadata)
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
                // The team's accent, which reads on the inset surface in
                // light and dark (F3).
                Circle()
                    .fill(TeamColors.accent(for: entry.team))
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
///
/// As wide as its row gives it: a share of the carousel on an iPhone, the
/// column on an iPad.
struct HomeStandingsCard: View {
    let slice: HomeStandingsSlice

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    .foregroundStyle(Theme.Palette.metadata)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .foregroundStyle(Theme.Palette.metadata)
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityHidden(true)
    }

    private func rowView(_ row: HomeStandingsSlice.Row, lastColumn: LastColumn?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("\(row.rank)")
                .foregroundStyle(row.isFollowed ? Color.primary : Theme.Palette.metadata)
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
                    // The team's accent, so the band shows on a dark card
                    // too (F3).
                    .fill(TeamColors.accent(for: slice.team).opacity(Theme.selectionWashOpacity(contrast: contrast)))
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
            // The accent bar in the team's accent, visible on a dark card
            // (F3).
            teamColor: TeamColors.accent(for: performer.team),
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

// MARK: - Around Your Leagues

/// A league block's heading in Around Your Leagues: its sport's symbol and
/// the league's name, "Premier League", "NFL", "NCAA Football".
struct HomeLeagueBlockHeader: View {
    let league: LeagueID

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: TeamColors.symbolName(for: league.descriptor.kind))
                .foregroundStyle(Theme.Palette.metadata)
                .accessibilityHidden(true)
            Text(league.descriptor.displayName)
                .font(.subheadline.bold())
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A game in one of Around Your Leagues' blocks, compact: the away side
/// over the home side, each its crest, poll rank (college), short name and
/// score, the winner's bold; and where the game stands at the trailing
/// end — "Live" by a red dot over its stage, its start over the
/// broadcast, "Final" over its day. A favorite's game (with Include My
/// Teams' Games on) has a bar in the team's accent at its leading edge and
/// the star beside its name (F3, T-7). At accessibility sizes the status
/// goes beneath the teams.
///
/// One element to VoiceOver: the button around it carries the game's
/// label (`HomeLeagueGame.accessibilityLabel(now:)`).
struct HomeLeagueGameRow: View {
    let entry: HomeLeagueGame
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var crestSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var statusWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 6

    private var stacksStatus: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let status = HomeFeed.leagueStatus(of: entry, now: now)
        let layout = stacksStatus
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
        layout {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                sideLine(entry.away, team: entry.awayTeam)
                sideLine(entry.home, team: entry.homeTeam)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusView(status)
        }
        .padding(.vertical, Theme.Spacing.s)
        .padding(.leading, Theme.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(alignment: .leading) {
            if let favorite = entry.favorite {
                Capsule()
                    .fill(TeamColors.accent(for: favorite))
                    .frame(width: 3)
                    .padding(.vertical, Theme.Spacing.s)
            }
        }
        .contentShape(.rect)
    }

    /// One side: crest, rank, name and score.
    private func sideLine(_ competitor: ScoreboardCompetitor, team: TeamRef) -> some View {
        let isWinner = entry.isWinner(competitor)
        return HStack(spacing: Theme.Spacing.s) {
            // On the inset surface, as the standings rows draw theirs.
            TeamLogo(team: team, size: crestSize)
            if let badge = PollRanks.badge(rank: entry.rank(of: competitor)) {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.metadata)
            }
            Text(team.shortName)
                .font(.subheadline)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(Color.primary)
                .lineLimit(stacksStatus ? nil : 1)
            if entry.isFavorite(competitor) {
                FollowedMarker()
            }
            Spacer(minLength: Theme.Spacing.s)
            if let score = entry.shownScore(competitor) {
                Text(score)
                    .font(.subheadline)
                    .fontWeight(isWinner ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            }
        }
    }

    /// Where the game stands: the line, the live dot beside it, and the
    /// detail beneath in the metadata grey (F1).
    private func statusView(_ status: HomeLeagueStatus) -> some View {
        VStack(alignment: stacksStatus ? .leading : .trailing, spacing: 2) {
            HStack(spacing: Theme.Spacing.xs) {
                if status.isLive {
                    // The word says it too: never colour alone (G-4).
                    Circle()
                        .fill(.red)
                        .frame(width: dotSize, height: dotSize)
                        .accessibilityHidden(true)
                }
                Text(status.primary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.isLive ? Color.primary : Theme.Palette.metadata)
            }
            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.metadata)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(stacksStatus ? .leading : .trailing)
        .lineLimit(stacksStatus ? nil : 2)
        .frame(minWidth: stacksStatus ? nil : statusWidth, alignment: stacksStatus ? .leading : .trailing)
    }
}

/// A league game's row while its board loads (X-6): two crests and names
/// and a status, in skeleton blocks, the row's height.
struct HomeLeagueGameRowPlaceholder: View {
    @ScaledMetric(relativeTo: .subheadline) private var crestSize: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var lineHeight: CGFloat = 12

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: Theme.Spacing.s) {
                        LoadingViewCircle()
                            .frame(width: crestSize, height: crestSize)
                        LoadingView()
                            .frame(width: 96, height: lineHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LoadingView()
                .frame(width: 56, height: lineHeight)
        }
        .padding(.vertical, Theme.Spacing.s)
        .padding(.leading, Theme.Spacing.s)
        .accessibilityHidden(true)
    }
}
