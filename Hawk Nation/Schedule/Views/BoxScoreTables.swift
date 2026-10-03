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
struct HockeyBoxScoreView: View {
    let boxScore: HockeyBoxScore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(boxScore.teams) { team in
                VStack(alignment: .leading, spacing: 10) {
                    BoxScoreTeamTitle(team.name)

                    if !team.forwards.isEmpty {
                        HockeySkaterTable(title: "Forwards", skaters: team.forwards)
                    }
                    if !team.defense.isEmpty {
                        HockeySkaterTable(title: "Defense", skaters: team.defense)
                    }
                    if !team.goalies.isEmpty {
                        HockeyGoalieTable(goalies: team.goalies)
                    }
                }
            }
        }
        .padding(.top, 10)
    }
}

/// One group of skaters: POS, name, TOI, G, A, P, +/-, S, PIM.
private struct HockeySkaterTable: View {
    let title: String
    let skaters: [HockeyBoxScore.Skater]

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
struct SoccerLineupsView: View {
    let lineups: SoccerLineups

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
                    }

                    if !lineup.substitutes.isEmpty {
                        BoxScoreText("Substitutes", style: .heading)
                            .padding(.top, 6)
                        ForEach(lineup.substitutes) { player in
                            SoccerLineupRow(player: player)
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
                    .foregroundStyle(cameOn ? Color.green : Color.red)
                BoxScoreText(player.substitutedAt, style: .heading)
            }
        }
    }

    private func card(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: cardWidth, height: cardHeight)
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
            .foregroundStyle(style == .heading ? Color(uiColor: .systemGray) : Color.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
