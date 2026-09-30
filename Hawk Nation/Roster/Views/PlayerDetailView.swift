//
//  PlayerDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation

// MARK: - Sheet content

/// One cell in a player sheet's three-column grid.
enum PlayerSheetCell: Sendable {
    /// A biography fact, drawn by `BioView`.
    case fact(title: String, info: String)
    /// A season statistic, drawn by `StatView`.
    case stat(title: String, info: String)
    /// A rate drawn as a ring by `StatPercentageView`: `progress` runs 0–1,
    /// and a non-finite one (a rate over zero attempts) reads "N/A".
    case percentage(title: String, progress: Double)

    /// An empty About column that keeps the grid aligned.
    static let blankFact = PlayerSheetCell.fact(title: "", info: " ")
    /// An empty Statistics column that keeps the grid aligned.
    static let blankStat = PlayerSheetCell.stat(title: "", info: " ")
}

/// One tab of a player sheet: rows of three cells, optionally under section
/// titles.
struct PlayerSheetGrid: Sendable {
    enum Layout: Sendable {
        /// Three full cells per row, spread across the card.
        case spread
        /// Cells packed from the leading edge under a section title, short
        /// rows padded out to three columns. The card grows with the rows.
        case titledSections
    }

    struct Section: Sendable {
        var title: String?
        var rows: [[PlayerSheetCell]]
    }

    var layout: Layout
    var sections: [Section]
    /// Shown beneath the sections, e.g. once a fetch found nothing.
    var message: String?

    init(layout: Layout = .spread, sections: [Section], message: String? = nil) {
        self.layout = layout
        self.sections = sections
        self.message = message
    }

    /// A single untitled section of spread rows.
    init(rows: [[PlayerSheetCell]]) {
        self.init(sections: [Section(rows: rows)])
    }

    /// The height of the card the grid sits on.
    var cardHeight: CGFloat {
        let rowCount = sections.reduce(0) { $0 + $1.rows.count }
        switch layout {
        case .spread:
            return CGFloat(120 * rowCount)
        case .titledSections:
            return CGFloat(max(240, 130 * (1 + rowCount)))
        }
    }
}

/// A roster player the generic `PlayerDetailView` can describe: the facts on
/// its About tab and the season statistics on its Statistics tab.
///
/// Each sport's player type conforms below; what the sheet shows is data, the
/// sheet itself is shared.
protocol PlayerSheetDescribing: RosterPlayer {
    /// The About tab.
    var about: PlayerSheetGrid { get }

    /// The Statistics tab before `statistics(league:)` has answered.
    var placeholderStatistics: PlayerSheetGrid { get }

    /// Loads the player's season statistics in `league`.
    func statistics(league: LeagueID) async -> PlayerSheetGrid
}

extension BasketballPlayer: PlayerSheetDescribing {
    var about: PlayerSheetGrid {
        PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: position),
                .fact(title: "Class", info: grade),
                .fact(title: "Status", info: status),
            ],
            [
                .fact(title: "Height", info: height),
                .fact(title: "Weight", info: weight),
                .fact(title: "HomeTown", info: hometown),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID) async -> PlayerSheetGrid {
        Self.grid(await downloadBasketballPlayerStats(playerID: playerID, league: league))
    }

    private static func grid(_ stats: BasketballPlayerStats) -> PlayerSheetGrid {
        func average(_ value: Float) -> String { String(format: "%.1f", value) }

        return PlayerSheetGrid(rows: [
            [
                .stat(title: "Games Played", info: "\(stats.gamesPlayed)"),
                .stat(title: "Average Minutes", info: average(stats.avgMinutes)),
                .stat(title: "Average Points", info: average(stats.avgPoints)),
            ],
            [
                .percentage(title: "Field Goal Percentage", progress: Double(stats.fieldGoalPct) / 100),
                .percentage(title: "3-Point Percentage", progress: Double(stats.threePointFieldGoalPct) / 100),
                .percentage(title: "Free Throw Percentage", progress: Double(stats.freeThrowPct) / 100),
            ],
            [
                .stat(title: "Average Rebounds", info: average(stats.avgRebounds)),
                .stat(title: "Avg. Defensive Rebounds", info: average(stats.avgDefensiveRebounds)),
                .stat(title: "Avg. Offensive Rebounds", info: average(stats.avgOffensiveRebounds)),
            ],
            [
                .stat(title: "Average Assists", info: average(stats.avgAssists)),
                .stat(title: "Average Blocks", info: average(stats.avgBlocks)),
                .stat(title: "Average Steals", info: average(stats.avgSteals)),
            ],
            [
                .stat(title: "Average Fouls", info: average(stats.avgFouls)),
                .stat(title: "Average Turnovers", info: average(stats.avgTurnovers)),
                .blankStat,
            ],
        ])
    }
}

extension FootBallPlayer: PlayerSheetDescribing {
    var about: PlayerSheetGrid {
        PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: position),
                .fact(title: "Debut Year", info: debutYear),
                .fact(title: "College", info: college),
            ],
            [
                .fact(title: "HomeTown", info: hometown),
                .fact(title: "Height", info: height),
                .fact(title: "Weight", info: weight),
            ],
            [
                .fact(title: "Age", info: age),
                .blankFact,
                .blankFact,
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID) async -> PlayerSheetGrid {
        Self.grid(await downloadFootballPlayerStats(playerID: playerID, league: league))
    }

    /// One titled section per position-appropriate stat group.
    private static func grid(_ stats: FootballPlayerStats) -> PlayerSheetGrid {
        PlayerSheetGrid(
            layout: .titledSections,
            sections: stats.groups.map { group in
                PlayerSheetGrid.Section(
                    title: group.title,
                    rows: group.rows.map { row in
                        row.map { PlayerSheetCell.stat(title: $0.label, info: $0.display) }
                    }
                )
            },
            message: stats.loaded && stats.groups.isEmpty
                ? "No season statistics are available for this player yet."
                : nil
        )
    }
}

extension BaseballPlayer: PlayerSheetDescribing {
    var about: PlayerSheetGrid {
        PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: position),
                .fact(title: "Home Town", info: hometown),
                .fact(title: "College", info: college),
            ],
            [
                .fact(title: "Age", info: age),
                .fact(title: "Debut Year", info: debutYear),
                .fact(title: "Height", info: height),
            ],
            [
                .fact(title: "Weight", info: weight),
                .fact(title: "Batting Hand", info: batHand),
                .fact(title: "Throwing Hand", info: throwHand),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { grid(.empty) }

    func statistics(league: LeagueID) async -> PlayerSheetGrid {
        grid(await downloadBaseballPlayerStats(
            playerID: playerID,
            playerPosition: position,
            league: league
        ))
    }

    /// Pitchers get the pitching line; everyone else the batting line.
    private func grid(_ stats: BaseballPlayerStats) -> PlayerSheetGrid {
        if position.contains("Pitcher") {
            return PlayerSheetGrid(rows: [
                [
                    .stat(title: "Games Played", info: "\(stats.gamesPlayed)"),
                    .stat(title: "Games Started", info: "\(stats.gamesStarted)"),
                    .stat(title: "Complete Games", info: "\(stats.completeGames)"),
                ],
                [
                    .stat(title: "Innings Pitched", info: "\(stats.innings)"),
                    .stat(title: "Wins", info: "\(stats.wins)"),
                    .stat(title: "Losses", info: "\(stats.losses)"),
                ],
                [
                    .stat(title: "Saves", info: "\(stats.saves)"),
                    .stat(title: "Save Opportunites", info: "\(stats.saveOpportunities)"),
                    .stat(title: "Opp. Batting Avg.", info: "\(stats.opponentAvg)"),
                ],
                [
                    .stat(title: "Runs", info: "\(stats.runs)"),
                    .stat(title: "Earned Run Avg.", info: String(format: "%.2f", stats.EarnedRunAverage)),
                    .stat(title: "Earned Runs", info: "\(stats.earnedRuns)"),
                ],
                [
                    .stat(title: "Hits", info: "\(stats.hits)"),
                    .stat(title: "Home Runs", info: "\(stats.homeRuns)"),
                    .stat(title: "Strikeouts", info: "\(stats.strikeouts)"),
                ],
                [
                    .stat(title: "Walks", info: "\(stats.walks)"),
                    .blankStat,
                    .blankStat,
                ],
            ])
        }

        return PlayerSheetGrid(rows: [
            [
                .stat(title: "At Bats", info: "\(stats.AtBats)"),
                .stat(title: "Runs", info: "\(stats.Runs)"),
                .stat(title: "Hits", info: "\(stats.Hits)"),
            ],
            [
                .stat(title: "Doubles", info: "\(stats.Doubles)"),
                .stat(title: "Triples", info: "\(stats.Triples)"),
                .stat(title: "Home Runs", info: "\(stats.HomeRuns)"),
            ],
            [
                .stat(title: "RBIs", info: "\(stats.RBIs)"),
                .stat(title: "Walks", info: "\(stats.Walks)"),
                .stat(title: "Hit By Pitches", info: "\(stats.HitByPitch)"),
            ],
            [
                .stat(title: "Strikeouts", info: "\(stats.Strikeouts)"),
                .stat(title: "Stolen Bases", info: "\(stats.StolenBases)"),
                .stat(title: "Caught Stealing", info: "\(stats.CaughtStealing)"),
            ],
            [
                .stat(title: "OPS", info: "\(stats.OPS)"),
                .blankStat,
                .blankStat,
            ],
        ])
    }
}

extension SoccerPlayer: PlayerSheetDescribing {
    var about: PlayerSheetGrid {
        PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: position),
                .fact(title: "Age", info: age),
                .fact(title: "Birth Country", info: birthPlace),
            ],
            [
                .fact(title: "Citizenship", info: citizenshipCountry),
                .fact(title: "Height", info: height),
                .fact(title: "Weight", info: weight),
            ],
        ])
    }

    /// The season totals usually arrive with the roster, so there is nothing
    /// to wait for.
    var placeholderStatistics: PlayerSheetGrid {
        hasSeasonStats ? seasonTotals : PlayerSheetGrid(layout: .titledSections, sections: [])
    }

    /// A player the roster listed without totals gets the athlete
    /// document's headline figures instead.
    func statistics(league: LeagueID) async -> PlayerSheetGrid {
        guard !hasSeasonStats else { return seasonTotals }
        let stats = await downloadSoccerPlayerStats(playerID: playerID, playerPosition: position, league: league)
        return Self.headline(stats, keeper: position.contains("Goalkeeper"))
    }

    /// The roster's `appearances` counts substitute appearances too, so
    /// starts are the difference. (They used to be shown as `appearances`,
    /// and games played as `appearances + subAppearances`, counting every
    /// substitute appearance twice.)
    private var starts: Int { max(appearances - subAppearances, 0) }

    /// Keepers get the goalkeeping line; everyone else the outfield line.
    private var seasonTotals: PlayerSheetGrid {
        if position.contains("Goalkeeper") {
            return PlayerSheetGrid(rows: [
                [
                    .stat(title: "Starts", info: "\(starts)"),
                    .stat(title: "Shots Faced", info: "\(shotsFaced)"),
                    .stat(title: "Goals Saved", info: "\(saves)"),
                ],
                [
                    .stat(title: "Goals Conceded", info: "\(goalsConceded)"),
                    .percentage(title: "Save Percentage", progress: Double(saves) / Double(shotsFaced)),
                    .percentage(title: "Conceded Percentage", progress: Double(goalsConceded) / Double(shotsFaced)),
                ],
                [
                    .stat(title: "Fouls Committed", info: "\(fouls)"),
                    .stat(title: "Yellow Cards", info: "\(yellowCards)"),
                    .stat(title: "Red Cards", info: "\(redCards)"),
                ],
            ])
        }

        return PlayerSheetGrid(rows: [
            [
                .stat(title: "Games Started", info: "\(starts)"),
                .stat(title: "Games Played", info: "\(appearances)"),
                .stat(title: "Goal Assists", info: "\(goalAssists)"),
            ],
            [
                .stat(title: "Total Shots", info: "\(totalShots)"),
                .stat(title: "Shots On Target", info: "\(shotsOnTarget)"),
                .stat(title: "Total Goals", info: "\(totalGoals)"),
            ],
            [
                .percentage(title: "Goal Percentage", progress: Double(totalGoals) / Double(totalShots)),
                .percentage(title: "On Target Percentage", progress: Double(shotsOnTarget) / Double(totalShots)),
                .stat(title: "Own Goals", info: "\(ownGoals)"),
            ],
            [
                .stat(title: "Offsides", info: "\(offsides)"),
                .stat(title: "Fouls Suffered", info: "\(foulsSuffered)"),
                .stat(title: "Fouls Committed", info: "\(fouls)"),
            ],
            [
                .stat(title: "Yellow Cards", info: "\(yellowCards)"),
                .stat(title: "Red Cards", info: "\(redCards)"),
                .blankStat,
            ],
        ])
    }

    /// The athlete document's headline figures. See `SoccerPlayerStats`.
    private static func headline(_ stats: SoccerPlayerStats, keeper: Bool) -> PlayerSheetGrid {
        let rows: [[PlayerSheetCell]] = keeper
            ? [[
                .stat(title: "Starts", info: stats.starts),
                .stat(title: "Saves", info: stats.saves),
                .stat(title: "Clean Sheets", info: stats.cleanSheets),
            ], [
                .stat(title: "Goals Conceded", info: stats.goalsConceded),
                .blankStat,
                .blankStat,
            ]]
            : [[
                .stat(title: "Games Started", info: stats.starts),
                .stat(title: "Sub Appearances", info: stats.substituteAppearances),
                .stat(title: "Total Goals", info: stats.goals),
            ], [
                .stat(title: "Goal Assists", info: stats.assists),
                .stat(title: "Total Shots", info: stats.shots),
                .blankStat,
            ]]
        guard stats.hasFigures else {
            return PlayerSheetGrid(
                layout: .titledSections,
                sections: [],
                message: "No season statistics are available for this player yet."
            )
        }
        return PlayerSheetGrid(rows: rows)
    }
}

extension HockeyPlayer: PlayerSheetDescribing {
    var about: PlayerSheetGrid {
        PlayerSheetGrid(rows: [
            [
                .fact(title: "Position", info: position),
                .fact(title: "Age", info: age),
                .fact(title: "Shoots", info: shoots),
            ],
            [
                .fact(title: "Height", info: height),
                .fact(title: "Weight", info: weight),
                .fact(title: "HomeTown", info: hometown),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID) async -> PlayerSheetGrid {
        Self.grid(await downloadHockeyPlayerStats(playerID: playerID, league: league))
    }

    /// The season line under its title, three stats a row, each labelled
    /// with the feed's own name for it. A skater and a goalie get different
    /// stats; see `hockeySheetStats(from:)`.
    private static func grid(_ line: SplitsSeasonLine) -> PlayerSheetGrid {
        let stats = hockeySheetStats(from: line)
        let rows = stride(from: 0, to: stats.count, by: 3).map { start in
            stats[start ..< min(start + 3, stats.count)].map {
                PlayerSheetCell.stat(title: $0.label, info: $0.display)
            }
        }
        return PlayerSheetGrid(
            layout: .titledSections,
            sections: stats.isEmpty ? [] : [PlayerSheetGrid.Section(title: line.title.isEmpty ? nil : line.title, rows: rows)],
            message: line.loaded && stats.isEmpty
                ? "No season statistics are available for this player yet."
                : nil
        )
    }
}

// MARK: - Sheet

/// The sheet a roster card opens: the player's photo over an About tab and a
/// Statistics tab, in the team's colours.
struct PlayerDetailView<Player: PlayerSheetDescribing>: View {
    @Environment(\.containerSize) private var containerSize
    @Environment(\.dismiss) private var dismiss

    let player: Player
    let team: TeamRef

    @State private var pickerSelectedItem = 0
    @State private var statistics: PlayerSheetGrid

    init(player: Player, team: TeamRef) {
        self.player = player
        self.team = team
        _statistics = State(initialValue: player.placeholderStatistics)
    }

    private var teamColor: Color { team.color }

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                ZStack(alignment: .top) {
                    Rectangle()
                        .foregroundStyle(teamColor)
                        .frame(height: 40)

                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(teamColor)

                    //TEAM LOGO
                    TeamLogo(team: team, size: 300, forceVariant: .default)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)

                    VStack(spacing: 0) {
                        //DISMISS BUTTON
                        Button(action: {
                            dismiss()
                        }) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: 100, height: 5)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .opacity(0.5)
                        }.padding([.top, .trailing, .leading, .bottom], 10)

                        // Takes up the sheet's full width.
                        HStack() {
                            Spacer()
                        }

                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                                .fontWeight(.bold)
                                .font(.system(size: 35))
                                .foregroundStyle(Color.white)

                            Text(player.number)
                                .fontWeight(.bold)
                                .font(.system(size: 35))
                                .foregroundStyle(Color.white)
                                .opacity(0.5)
                        }

                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)

                        //SELECTOR VIEW
                        ZStack() {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(height: 30)

                            HStack(spacing: 0) {
                                tabButton("About", tag: 0)
                                tabButton("Statistics", tag: 1)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 20))
                        .padding([.bottom, .leading, .trailing], 10)
                    }
                }

                VStack(spacing: 0) {
                    if(pickerSelectedItem == 0) {
                        card(player.about)
                    } else if(pickerSelectedItem == 1) {
                        card(statistics)
                    }
                    Spacer()
                }
            }

            Spacer()
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .task {
            statistics = await player.statistics(league: team.league)
        }
    }

    /// One segment of the About / Statistics picker; the unselected one is
    /// faded.
    private func tabButton(_ title: String, tag: Int) -> some View {
        Button(action: {
            pickerSelectedItem = tag
        }) {
            ZStack(alignment: .center) {
                Rectangle()
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(height: 30)
                    .clipped()
                    .opacity(pickerSelectedItem == tag ? 1 : 0.8)
                Text(title)
            }
        }.buttonStyle(.plain)
    }

    /// A tab's grid on its rounded card.
    private func card(_ grid: PlayerSheetGrid) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: (containerSize.width - 25), height: grid.cardHeight)
                .foregroundStyle(Color(uiColor: .systemBackground))

            VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(grid.sections.enumerated()), id: \.offset) { _, section in
                    if let title = section.title {
                        Text(title)
                            .font(.system(size: 17))
                            .fontWeight(.bold)
                            .foregroundStyle(teamColor)
                            .padding(.top, 5)
                    }

                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                        gridRow(row, layout: grid.layout)
                    }
                }

                if let message = grid.message {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer()
            }.padding([.all], 20)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func gridRow(_ row: [PlayerSheetCell], layout: PlayerSheetGrid.Layout) -> some View {
        HStack(alignment: .center) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                if layout == .spread, index > 0 {
                    Spacer()
                }
                cellView(cell)
            }

            if layout == .titledSections {
                // Keep three columns so rows line up under the header.
                ForEach(0 ..< max(0, 3 - row.count), id: \.self) { _ in
                    Color.clear
                        .frame(width: (containerSize.width/4), height: containerSize.width/3)
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: PlayerSheetCell) -> some View {
        switch cell {
        case .fact(let title, let info):
            BioView(title: title, info: info)
        case .stat(let title, let info):
            StatView(title: title, info: info)
        case .percentage(let title, let progress):
            StatPercentageView(progress: CGFloat(progress), color: UIColor(teamColor), title: title)
                .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0), value: progress)
        }
    }
}
