//
//  BoxScoreTables.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

// MARK: - Linescore

/// A game's period-by-period score beneath the scoreline: one column per
/// period (`Linescore.periodLabels`, sized from the feed), then the total.
/// The home row comes first, as the rest of the sheet puts home first.
struct LinescoreView: View {
    let linescore: Linescore

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                BoxScoreText("", style: .heading)
                    .gridColumnAlignment(.leading)
                ForEach(Array(linescore.periodLabels.enumerated()), id: \.offset) { _, label in
                    BoxScoreText(label, style: .heading)
                }
                BoxScoreText("T", style: .heading)
            }

            Divider()

            ForEach([linescore.home, linescore.away]) { line in
                GridRow {
                    BoxScoreText(line.abbreviation, style: .emphasis)
                    ForEach(Array(line.periods.enumerated()), id: \.offset) { _, score in
                        BoxScoreText(score)
                    }
                    BoxScoreText(line.total, style: .emphasis)
                }
            }
        }
        .scrollsSidewaysAtAccessibilitySizes()
        .padding(.vertical, 5)
    }
}

// MARK: - Hockey

/// A hockey game's player tables, one team after the other: forwards,
/// defense, then goalies. The comparison strip above them is the sheet's
/// usual `BoxScore` rows (`BoxScore.init(hockey:)`).
///
/// A player's name opens their sheet through `onPlayer` (C-6).
struct HockeyBoxScoreView: View {
    let boxScore: HockeyBoxScore
    var onPlayer: ((GameSheetPlayer) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(boxScore.teams) { team in
                VStack(alignment: .leading, spacing: 10) {
                    BoxScoreTeamTitle(team.name)

                    if !team.forwards.isEmpty {
                        HockeySkaterTable(title: "Forwards", skaters: team.forwards, onPlayer: onPlayer)
                    }
                    if !team.defense.isEmpty {
                        HockeySkaterTable(title: "Defense", skaters: team.defense, onPlayer: onPlayer)
                    }
                    if !team.goalies.isEmpty {
                        HockeyGoalieTable(goalies: team.goalies, onPlayer: onPlayer)
                    }
                }
            }
        }
        .padding(.top, 10)
    }
}

/// One group of skaters: POS, name, TOI, G, A, P, +/-, S, PIM.
///
/// The name cell is the button: a `GridRow` wrapped in one would stop being
/// a row of the grid.
private struct HockeySkaterTable: View {
    let title: String
    let skaters: [HockeyBoxScore.Skater]
    let onPlayer: ((GameSheetPlayer) -> Void)?

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                BoxScoreText("POS", style: .heading)
                    .gridColumnAlignment(.leading)
                BoxScoreText(title, style: .heading)
                    .gridColumnAlignment(.leading)
                BoxScoreText("TOI", style: .heading)
                BoxScoreText("G", style: .heading)
                BoxScoreText("A", style: .heading)
                BoxScoreText("P", style: .heading)
                BoxScoreText("+/-", style: .heading)
                BoxScoreText("S", style: .heading)
                BoxScoreText("PIM", style: .heading)
            }

            Divider()

            ForEach(skaters) { skater in
                GridRow {
                    BoxScoreText(skater.position)
                    BoxScoreText(skater.shortName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opensPlayerSheet(GameSheetPlayer(skater: skater), onPlayer: onPlayer)
                    BoxScoreText(skater.timeOnIce)
                    BoxScoreText("\(skater.goals)")
                    BoxScoreText("\(skater.assists)")
                    BoxScoreText("\(skater.points)", style: .emphasis)
                    BoxScoreText(signed(skater.plusMinus))
                    BoxScoreText("\(skater.shots)")
                    BoxScoreText("\(skater.penaltyMinutes)")
                }
            }
        }
        .scrollsSidewaysAtAccessibilitySizes()
    }

    /// Plus-minus as hockey writes it: "+1", "0", "-2".
    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

/// A team's goalies: name, TOI, SA, SV, GA, SV%.
private struct HockeyGoalieTable: View {
    let goalies: [HockeyBoxScore.Goalie]
    let onPlayer: ((GameSheetPlayer) -> Void)?

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                BoxScoreText("Goalies", style: .heading)
                    .gridColumnAlignment(.leading)
                BoxScoreText("TOI", style: .heading)
                BoxScoreText("SA", style: .heading)
                BoxScoreText("SV", style: .heading)
                BoxScoreText("GA", style: .heading)
                BoxScoreText("SV%", style: .heading)
            }

            Divider()

            ForEach(goalies) { goalie in
                GridRow {
                    BoxScoreText(goalie.shortName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opensPlayerSheet(GameSheetPlayer(goalie: goalie), onPlayer: onPlayer)
                    BoxScoreText(goalie.timeOnIce)
                    BoxScoreText("\(goalie.shotsAgainst)")
                    BoxScoreText("\(goalie.saves)", style: .emphasis)
                    BoxScoreText("\(goalie.goalsAgainst)")
                    BoxScoreText(goalie.savePct)
                }
            }
        }
        .scrollsSidewaysAtAccessibilitySizes()
    }
}

// MARK: - Soccer

/// Both sides' lineups: the starting eleven, then the substitutes who came
/// on, each marked with goals, cards and substitution minutes.
///
/// A row opens the player's sheet through `onPlayer` (C-6).
struct SoccerLineupsView: View {
    let lineups: SoccerLineups
    var onPlayer: ((GameSheetPlayer) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(lineups.lineups) { lineup in
                VStack(alignment: .leading, spacing: 6) {
                    BoxScoreTeamTitle(lineup.formation.isEmpty
                        ? lineup.name
                        : "\(lineup.name) · \(lineup.formation)")

                    BoxScoreText("Starting XI", style: .heading)
                    ForEach(lineup.starters) { player in
                        SoccerLineupRow(player: player)
                            .opensPlayerSheet(GameSheetPlayer(lineupRow: player), onPlayer: onPlayer)
                    }

                    if !lineup.substitutes.isEmpty {
                        BoxScoreText("Substitutes", style: .heading)
                            .padding(.top, 6)
                        ForEach(lineup.substitutes) { player in
                            SoccerLineupRow(player: player)
                            .opensPlayerSheet(GameSheetPlayer(lineupRow: player), onPlayer: onPlayer)
                        }
                    }
                }
            }
        }
        .padding(.top, 10)
    }
}

/// One player in a lineup: number, name, then what happened to them.
private struct SoccerLineupRow: View {
    let player: SoccerLineups.Player

    @ScaledMetric(relativeTo: .caption2) private var jerseyWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var cardWidth: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var cardHeight: CGFloat = 11

    var body: some View {
        HStack(spacing: 6) {
            BoxScoreText(player.jersey, style: .heading)
                .frame(width: jerseyWidth, alignment: .trailing)

            BoxScoreText(player.name)

            Spacer(minLength: 4)

            ForEach(0 ..< player.goals, id: \.self) { _ in
                Image(systemName: "soccerball")
                    .font(.caption2)
                    .symbolRenderingMode(.hierarchical)
            }
            ForEach(0 ..< player.yellowCards, id: \.self) { _ in
                card(.yellow)
            }
            ForEach(0 ..< player.redCards, id: \.self) { _ in
                card(.red)
            }

            if !player.substitutedAt.isEmpty {
                // A starter taken off, or a substitute brought on.
                let cameOn = !player.starter
                Image(systemName: cameOn ? "arrow.up" : "arrow.down")
                    .font(.caption2.bold())
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(cameOn ? Color.green : Color.red)
                BoxScoreText(player.substitutedAt, style: .heading)
            }
        }
        // One element that says what the ball, the cards and the arrow
        // show, which colour and shape alone told before (D-6).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(player.accessibilitySummary)
    }

    /// A referee's card, drawn as a glyph: its corner is part of the
    /// drawing at this size, not a surface radius, so not a `Theme.Radius`.
    private func card(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Player sheets

/// The player a lineup or box-score row opens a sheet for (C-6): the sport's
/// own roster type, built from what the row knows, so the sheet is the
/// roster's `PlayerDetailView`.
///
/// A row knows the athlete's id, name, number and position, and nothing of
/// their biography, so the About facts read "N/A"; the season statistics
/// load from the athlete's id once the sheet opens.
enum GameSheetPlayer: Identifiable, Hashable, Sendable {
    case soccer(SoccerPlayer)
    case hockey(HockeyPlayer)

    /// The ESPN athlete id: never empty, as the factories refuse a row
    /// without one.
    var id: String {
        switch self {
        case .soccer(let player): player.playerID
        case .hockey(let player): player.playerID
        }
    }

    /// The player in a soccer lineup row, or `nil` when the feed gave the
    /// row no athlete id.
    init?(lineupRow row: SoccerLineups.Player) {
        guard !row.athleteID.isEmpty else { return nil }
        self = .soccer(SoccerPlayer(
            name: row.name,
            number: row.jersey,
            numberInt: Self.numberInt(row.jersey),
            height: Self.unknown,
            weight: Self.unknown,
            position: Self.soccerPosition(row.position),
            photo: "",
            age: Self.unknown,
            playerID: row.athleteID,
            birthPlace: Self.unknown,
            citizenshipCountry: Self.unknown,
            fouls: 0,
            foulsSuffered: 0,
            redCards: 0,
            yellowCards: 0,
            ownGoals: 0,
            appearances: 0,
            subAppearances: 0,
            goalAssists: 0,
            offsides: 0,
            shotsOnTarget: 0,
            totalShots: 0,
            totalGoals: 0,
            saves: 0,
            shotsFaced: 0,
            goalsConceded: 0,
            lastName: Self.lastName(row.name),
            // No roster totals: the sheet reads the athlete document.
            hasSeasonStats: false
        ))
    }

    /// The player in a hockey skater row, or `nil` without an athlete id.
    init?(skater: HockeyBoxScore.Skater) {
        guard let player = Self.hockeyPlayer(
            id: skater.athleteID, name: skater.name, jersey: skater.jersey, position: skater.position
        ) else { return nil }
        self = .hockey(player)
    }

    /// The player in a hockey goalie row, or `nil` without an athlete id.
    init?(goalie: HockeyBoxScore.Goalie) {
        guard let player = Self.hockeyPlayer(
            id: goalie.athleteID, name: goalie.name, jersey: goalie.jersey, position: "Goalie"
        ) else { return nil }
        self = .hockey(player)
    }

    private static func hockeyPlayer(id: String, name: String, jersey: String, position: String) -> HockeyPlayer? {
        guard !id.isEmpty else { return nil }
        return HockeyPlayer(
            playerID: id,
            name: name,
            number: jersey,
            numberInt: numberInt(jersey),
            height: unknown,
            weight: unknown,
            position: position.isEmpty ? unknown : position,
            hometown: unknown,
            photo: "",
            age: unknown,
            shoots: unknown,
            lastName: lastName(name)
        )
    }

    /// An About fact the row can't supply, written as the roster writes one
    /// its feed left out.
    private static let unknown = "N/A"

    /// The jersey as a number, or the roster's no-number value.
    private static func numberInt(_ jersey: String) -> Int {
        Int(jersey) ?? 1000
    }

    private static func lastName(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    /// The lineup's abbreviation as the roster's position name where the
    /// sheet depends on it: `SoccerPlayer` picks the keeper's statistics by
    /// `"Goalkeeper"`. A substitute's `"SUB"` names no position.
    private static func soccerPosition(_ abbreviation: String) -> String {
        switch abbreviation {
        case "G", "GK": "Goalkeeper"
        case "", "SUB": unknown
        default: abbreviation
        }
    }
}

private extension View {
    /// The row as a button that opens `player`'s sheet, or the row as it is
    /// when it has no player (no athlete id) or nothing to open the sheet.
    @ViewBuilder
    func opensPlayerSheet(_ player: GameSheetPlayer?, onPlayer: ((GameSheetPlayer) -> Void)?) -> some View {
        if let player, let onPlayer {
            Button {
                onPlayer(player)
            } label: {
                self.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the player's details")
            .accessibilityIdentifier("gameDetail.player.\(player.id)")
        } else {
            self
        }
    }
}

// MARK: - Shared cells

/// A team's name above its tables.
private struct BoxScoreTeamTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline)
    }
}

/// One cell of a box-score table.
private struct BoxScoreText: View {
    enum Style {
        /// A figure or a name.
        case body
        /// A column heading, or a detail beside a name.
        case heading
        /// A figure that sums up its row: a total, points, saves.
        case emphasis
    }

    let text: String
    let style: Style

    init(_ text: String, style: Style = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        // At accessibility sizes the tables scroll sideways, so a cell only
        // trims a little at the larger standard sizes (D-4: no lower than 0.8).
        Text(text)
            .font(style == .heading ? .caption2 : Theme.Typography.caption)
            .fontWeight(style == .body ? .regular : .bold)
            .foregroundStyle(style == .heading ? HierarchicalShapeStyle.secondary : .primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
