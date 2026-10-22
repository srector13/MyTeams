//
//  PlayerGameLogView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The rows of a player sheet's game-log card: the most recent games, each
/// with its result in a coloured chip, the opponent's crest and name, the
/// score with the team first ("L 0–4", P6, F5) over the date, and the
/// player's line as compact chips ("2 G", "5 SH") from the log's headline
/// columns (`AthleteGameLog.headlineColumns`). A goal, touchdown or home
/// run is picked out in the team's accent. A log that didn't load says so,
/// with a Retry (P8).
///
/// The chips sit in one line beside the game and wrap under it when they
/// don't fit; at accessibility sizes each game stacks, so nothing
/// truncates. VoiceOver reads each game as one element.
struct PlayerGameLogView: View {
    let log: AthleteGameLog
    var limit = 5
    /// The team's accent on a content card (F3), behind a scoring chip.
    var accent: Color = .accentColor
    /// The log's league, for the opponents' crests; `nil` draws none.
    var league: LeagueID? = nil
    /// Fetches the log again after a failed load; `nil` offers no Retry.
    var onRetry: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 28

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rows: [GameLogRow] { Array(log.rows.prefix(limit)) }

    var body: some View {
        if log.loaded && log.loadFailed && rows.isEmpty {
            failedMessage
        } else if log.loaded && rows.isEmpty {
            message("No games are logged for this player this season.")
        } else if rows.isEmpty {
            // Stand-in games, redacted, until the first fetch lands.
            games(Self.placeholderRows, columns: Self.placeholderColumns)
                .loadingPlaceholder()
        } else if log.loaded {
            games(rows, columns: log.headlineColumns)
        } else {
            // Another season's games on their way.
            games(rows, columns: log.headlineColumns)
                .loadingPlaceholder()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The log didn't arrive: not "no games" (P8).
    private var failedMessage: some View {
        VStack(spacing: Theme.Spacing.s) {
            message("Couldn't load recent games.")
                .accessibilityIdentifier("playerDetail.gameLogFailed")

            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("playerDetail.gameLogRetry")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func games(_ rows: [GameLogRow], columns: [GameLogColumn]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                }
                game(row, columns: columns)
                    .padding(.vertical, Theme.Spacing.m)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(Self.accessibilityLabel(row, columns: columns)))
            }
        }
    }

    @ViewBuilder
    private func game(_ row: GameLogRow, columns: [GameLogColumn]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    GameResultChip(result: row.result)
                    Text(row.opponentSummary)
                        .font(Theme.Typography.cardTitle)
                }
                Text(Self.detail(row))
                    .font(Theme.Typography.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Palette.metadata)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    chipList(row, columns: columns)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                GameResultChip(result: row.result)

                if let league {
                    TeamLogo(team: Self.opponent(row, league: league), size: crestSize)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(row.opponentSummary)
                        .font(Theme.Typography.cardTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // One line when the chips fit beside each other, else
                    // one under another.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.xs) {
                            chipList(row, columns: columns)
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            chipList(row, columns: columns)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The score team first, over the date (P6).
                VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                    if !row.resultSummary.isEmpty {
                        Text(row.resultSummary)
                            .font(Theme.Typography.body.weight(.semibold).monospacedDigit())
                    }
                    if let date = Self.date(row) {
                        Text(date)
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    /// The player's line in the game, a chip a column, in the columns'
    /// order; a figure the feed left out reads "–".
    private func chipList(_ row: GameLogRow, columns: [GameLogColumn]) -> some View {
        ForEach(columns) { column in
            let value = row.stats[column.id] ?? "–"
            GameStatChip(
                value: value,
                label: column.label,
                emphasized: gameLogEmphasizes(columnID: column.id, value: value),
                accent: accent
            )
        }
    }

    /// A stand-in team for the opponent's crest: the log's logo, or a
    /// monogram from its abbreviation where the feed gave none.
    private static func opponent(_ row: GameLogRow, league: LeagueID) -> TeamRef {
        TeamRef(
            league: league,
            espnID: row.opponentID.isEmpty ? row.opponentAbbreviation : row.opponentID,
            displayName: row.opponentName,
            shortName: row.opponentAbbreviation,
            abbreviation: row.opponentAbbreviation,
            location: "",
            colorHex: "",
            alternateColorHex: "",
            logoURL: URL(string: row.opponentLogo),
            logoDarkURL: nil,
            logoAsset: nil
        )
    }

    /// "Oct 4", or `nil` where the feed's date didn't parse.
    private static func date(_ row: GameLogRow) -> String? {
        row.date.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
    }

    /// "Oct 4 · L 0–4", team first (P6), leaving out what the feed left
    /// out: the stacked row's line under the opponent.
    private static func detail(_ row: GameLogRow) -> String {
        [date(row) ?? "", row.resultSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "October 4, 2026, at Las Vegas Raiders, won 30–27, 225 Passing
    /// Yards, 2 Passing Touchdowns, …", the score team first.
    private static func accessibilityLabel(_ row: GameLogRow, columns: [GameLogColumn]) -> String {
        var parts: [String] = []
        if let date = row.date {
            parts.append(date.formatted(date: .long, time: .omitted))
        }
        let opponent = row.opponentName.isEmpty ? row.opponentAbbreviation : row.opponentName
        parts.append("\(row.isHome ? "versus" : "at") \(opponent)")
        let outcome: String
        switch row.result {
        case "W": outcome = "won"
        case "L": outcome = "lost"
        case "D": outcome = "drew"
        case "T": outcome = "tied"
        default: outcome = row.result
        }
        let result = [outcome, row.teamScore].filter { !$0.isEmpty }.joined(separator: " ")
        if !result.isEmpty {
            parts.append(result)
        }
        if !row.note.isEmpty {
            parts.append(row.note)
        }
        for column in columns {
            guard let value = row.stats[column.id] else { continue }
            parts.append("\(value) \(column.displayName)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Placeholder

    private static let placeholderColumns: [GameLogColumn] = (0..<4).map {
        GameLogColumn(id: "placeholder\($0)", label: "STAT", displayName: "")
    }

    private static let placeholderRows: [GameLogRow] = (0..<5).map { index in
        GameLogRow(
            id: "placeholder\(index)",
            date: Date(timeIntervalSince1970: 0),
            opponentID: "",
            opponentName: "Opponent",
            opponentAbbreviation: "OPP",
            isHome: true,
            result: "W",
            score: "00-00",
            note: "",
            seasonType: "",
            stats: Dictionary(uniqueKeysWithValues: placeholderColumns.map { ($0.id, "00") })
        )
    }
}

/// A game's result as a letter on a tinted square: a win in the outcome
/// green, a loss in its red (`Theme.Outcome`), a draw or tie in grey. The
/// letter carries the result; the colour only echoes it (G-4).
private struct GameResultChip: View {
    let result: String

    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 26

    private var color: Color {
        switch result {
        case "W": return Theme.Outcome.win
        case "L": return Theme.Outcome.loss
        default: return Theme.Palette.metadata
        }
    }

    var body: some View {
        Text(result.isEmpty ? "–" : result)
            .font(.caption.weight(.heavy))
            .foregroundStyle(color)
            .frame(minWidth: side, minHeight: side)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
    }
}

/// One figure of a game's line, "2 G": the number over the inset surface,
/// or over a wash of the team colour for a goal, touchdown or home run.
private struct GameStatChip: View {
    let value: String
    let label: String
    let emphasized: Bool
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(emphasized ? .heavy : .semibold).monospacedDigit())
            Text(label)
                .font(Theme.Typography.caption.weight(.medium))
                .foregroundStyle(Theme.Palette.metadata)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 3)
        .background(emphasized ? accent.opacity(0.2) : Theme.Surface.insetCard, in: Capsule())
    }
}
