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

/// One cell in a player sheet's grid.
enum PlayerSheetCell: Sendable {
    /// A biography fact, drawn by `BioView`.
    case fact(title: String, info: String)
    /// A season statistic, drawn by `StatView`.
    case stat(title: String, info: String)
    /// A rate drawn as a ring by `StatPercentageView`: `progress` runs 0–1,
    /// and a non-finite one (a rate over zero attempts) reads "N/A".
    case percentage(title: String, progress: Double)
}

/// One tab of a player sheet: its cells, optionally under section titles.
///
/// Cells come grouped in rows of up to three, the order they read in; the
/// sheet lays them out in as many columns as the text size allows (P-4).
struct PlayerSheetGrid: Sendable {
    struct Section: Sendable {
        var title: String?
        var rows: [[PlayerSheetCell]]
    }

    var sections: [Section]
    /// Shown beneath the sections, e.g. once a fetch found nothing.
    var message: String?

    init(sections: [Section], message: String? = nil) {
        self.sections = sections
        self.message = message
    }

    /// A single untitled section.
    init(rows: [[PlayerSheetCell]]) {
        self.init(sections: [Section(rows: rows)])
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
        hasSeasonStats ? seasonTotals : PlayerSheetGrid(sections: [])
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
            ]]
            : [[
                .stat(title: "Games Started", info: stats.starts),
                .stat(title: "Sub Appearances", info: stats.substituteAppearances),
                .stat(title: "Total Goals", info: stats.goals),
            ], [
                .stat(title: "Goal Assists", info: stats.assists),
                .stat(title: "Total Shots", info: stats.shots),
            ]]
        guard stats.hasFigures else {
            return PlayerSheetGrid(
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
    /// A grid cell's narrowest width: three columns at the default text
    /// size, fewer as the text grows, one at the largest sizes (P-4).
    @ScaledMetric(relativeTo: .body) private var cellMinimumWidth: CGFloat = 96

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
                    // Square on top, where the sheet's own corners round it,
                    // and rounded where it meets the card below.
                    ZStack(alignment: .top) {
                        Rectangle()
                            .frame(height: 40)

                        Theme.Radius.cardShape
                    }
                    .foregroundStyle(teamColor)
                    // Carries the colour into any safe area beside the
                    // header (landscape), where `ignoresSafeArea` used to
                    // stretch it.
                    .backgroundExtensionEffect()

                    //TEAM LOGO
                    TeamLogo(team: team, size: 300, forceVariant: .default)
                        .opacity(0.1)
                        .saturation(0.1)
                        .contrast(0.5)

                    VStack(spacing: 0) {
                        // Where the grabber and close button float.
                        Color.clear
                            .frame(height: Self.closeButtonClearance)

                        // Takes up the sheet's full width.
                        HStack() {
                            Spacer()
                        }

                        //PLAYER NAME
                        HStack(alignment: .top) {
                            Text(player.name)
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.white)

                            Text(player.number)
                                .font(.largeTitle.bold().monospacedDigit())
                                .foregroundStyle(Color.white)
                                .opacity(0.5)
                        }
                        .padding(.horizontal, Theme.Spacing.l)

                        //PLAYER PHOTO
                        RemoteImage(url: URL(string: player.photo)) {
                            Image("blank")
                                .resizable()
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 180, height: 180)
                    }
                }

                // Below the header rather than on it: the segmented control's
                // translucent track is drawn for the sheet's surface, not
                // for an arbitrary team colour.
                Picker("Section", selection: $pickerSelectedItem) {
                    Text("About").tag(0)
                    Text("Statistics").tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("playerDetail.section")
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)

                VStack(spacing: 0) {
                    if pickerSelectedItem == 0 {
                        card(player.about)
                            .transition(.blurReplace)
                    } else {
                        card(statistics)
                            .transition(.blurReplace)
                    }
                    Spacer()
                }
                .animation(.snappy, value: pickerSelectedItem)
            }

            Spacer()
        }
        .scrollIndicators(.hidden)
        // No background of its own: the system sheet draws the surface, and
        // the team-colour header runs under the grabber to its top edge.
        .overlay(alignment: .topTrailing) {
            SheetCloseButton()
                // Pinned to its 44 pt circle, as the crest picker's "+" is.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("playerDetail.close")
                .padding(Theme.Spacing.m)
        }
        // Full height: the header and photo alone fill a medium detent.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            statistics = await player.statistics(league: team.league)
        }
    }

    /// The band at the top of the sheet left to the system grabber and the
    /// close button floating over it: the button's 44 pt and its inset.
    private static var closeButtonClearance: CGFloat { 44 + Theme.Spacing.m }

    /// A tab's grid on a rounded card that sizes to its content (P-5).
    private func card(_ grid: PlayerSheetGrid) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Array(grid.sections.enumerated()), id: \.offset) { _, section in
                if let title = section.title {
                    Text(title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(teamColor)
                        .padding(.top, 5)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellMinimumWidth), spacing: Theme.Spacing.s, alignment: .top)],
                    spacing: Theme.Spacing.m
                ) {
                    ForEach(Array(section.rows.joined().enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                }
            }

            if let message = grid.message {
                Text(message)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: Theme.Radius.cardShape)
        .padding(.horizontal, Theme.Spacing.m)
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
