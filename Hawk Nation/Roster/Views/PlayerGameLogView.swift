//
//  PlayerGameLogView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The rows of a player sheet's game-log card: the most recent games, each
/// with its opponent, date, result and the log's headline columns
/// (`AthleteGameLog.headlineColumns`).
///
/// The figures sit in columns under their headers; at accessibility sizes
/// each game stacks instead, its figures labelled inline, so nothing
/// truncates. VoiceOver reads each game as one element.
struct PlayerGameLogView: View {
    let log: AthleteGameLog
    var limit = 5

    /// A stat column's width: four fit beside the game at the default text
    /// size, as do the widest figures ("24:10", "119.8").
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth: CGFloat = 48

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rows: [GameLogRow] { Array(log.rows.prefix(limit)) }

    var body: some View {
        if log.loaded && rows.isEmpty {
            Text("No games are logged for this player this season.")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .center)
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

    private func games(_ rows: [GameLogRow], columns: [GameLogColumn]) -> some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                header(columns)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 || !dynamicTypeSize.isAccessibilitySize {
                    Divider()
                }
                game(row, columns: columns)
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(Self.accessibilityLabel(row, columns: columns)))
            }
        }
    }

    private func header(_ columns: [GameLogColumn]) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Game")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { column in
                Text(column.label)
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .font(Theme.Typography.statLabel)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.bottom, Theme.Spacing.xs)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func game(_ row: GameLogRow, columns: [GameLogColumn]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(row.opponentSummary)
                    .font(Theme.Typography.cardTitle)
                Text(Self.detail(row))
                    .foregroundStyle(.secondary)
                Text(columns.map { "\(row.stats[$0.id] ?? "–") \($0.label)" }.joined(separator: " · "))
                    .font(Theme.Typography.body.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.opponentSummary)
                        .font(Theme.Typography.cardTitle)
                    Text(Self.detail(row))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(columns) { column in
                    Text(row.stats[column.id] ?? "–")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: columnWidth, alignment: .trailing)
                }
            }
        }
    }

    /// "Oct 4 · W 30-27", leaving out what the feed left out.
    private static func detail(_ row: GameLogRow) -> String {
        [row.date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "", row.resultSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "October 4, 2026, at Las Vegas Raiders, won 30-27, 225 Passing
    /// Yards, 2 Passing Touchdowns, …".
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
        let result = [outcome, row.score].filter { !$0.isEmpty }.joined(separator: " ")
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
