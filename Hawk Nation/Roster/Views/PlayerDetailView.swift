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
    /// A biography fact, drawn as a `FactRow` on the About card.
    case fact(title: String, info: String)
    /// A season statistic, drawn as a `StatCell` or a headline tile.
    case stat(title: String, info: String)
    /// A rate drawn as a ring by `StatPercentageView`: `progress` runs 0–1,
    /// and a non-finite one (a rate over zero attempts) reads "N/A".
    case percentage(title: String, progress: Double)
}

/// One card of a player sheet: its cells, optionally under section titles.
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
/// its About card and the season statistics on its Season Stats card.
///
/// Each sport's player type conforms below; what the sheet shows is data, the
/// sheet itself is shared.
protocol PlayerSheetDescribing: RosterPlayer {
    /// The About card.
    var about: PlayerSheetGrid { get }

    /// The Season Stats card before `statistics(league:)` has answered.
    var placeholderStatistics: PlayerSheetGrid { get }

    /// Loads the player's season statistics in `league`.
    func statistics(league: LeagueID) async -> PlayerSheetGrid

    /// The statistics lifted out of the grid into the sheet's headline
    /// tiles, by their cell titles, in the order they're shown. A title the
    /// grid lacks is skipped, so one list can serve two stat lines.
    var featuredStatistics: [PlayerSheetFeature] { get }
}

extension PlayerSheetDescribing {
    var featuredStatistics: [PlayerSheetFeature] { [] }
}

/// A headline statistic on a player sheet: the grid cell it's drawn from,
/// and the short label its tile shows ("PPG" for "Average Points").
struct PlayerSheetFeature: Sendable {
    var title: String
    var abbreviation: String

    init(_ title: String, _ abbreviation: String) {
        self.title = title
        self.abbreviation = abbreviation
    }
}

extension PlayerSheetCell {
    /// The label the cell is drawn with, whatever its kind.
    var title: String {
        switch self {
        case .fact(let title, _), .stat(let title, _), .percentage(let title, _):
            return title
        }
    }
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

    var featuredStatistics: [PlayerSheetFeature] {
        [
            PlayerSheetFeature("Average Points", "PPG"),
            PlayerSheetFeature("Average Rebounds", "RPG"),
            PlayerSheetFeature("Average Assists", "APG"),
            PlayerSheetFeature("Average Minutes", "MPG"),
        ]
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

    /// The pitching line's headline, or the batting line's. The feed gives
    /// no AVG, OBP or SLG, so OPS stands in for the slash line.
    var featuredStatistics: [PlayerSheetFeature] {
        if position.contains("Pitcher") {
            return [
                PlayerSheetFeature("Earned Run Avg.", "ERA"),
                PlayerSheetFeature("Wins", "W"),
                PlayerSheetFeature("Losses", "L"),
                PlayerSheetFeature("Strikeouts", "K"),
            ]
        }
        return [
            PlayerSheetFeature("Hits", "H"),
            PlayerSheetFeature("Home Runs", "HR"),
            PlayerSheetFeature("RBIs", "RBI"),
            PlayerSheetFeature("OPS", "OPS"),
        ]
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

    /// Covers both the roster's season totals and the athlete document's
    /// headline figures, which title some stats differently.
    var featuredStatistics: [PlayerSheetFeature] {
        if position.contains("Goalkeeper") {
            return [
                PlayerSheetFeature("Goals Saved", "SV"),
                PlayerSheetFeature("Saves", "SV"),
                PlayerSheetFeature("Save Percentage", "SV%"),
                PlayerSheetFeature("Clean Sheets", "CS"),
                PlayerSheetFeature("Goals Conceded", "GA"),
            ]
        }
        return [
            PlayerSheetFeature("Total Goals", "G"),
            PlayerSheetFeature("Goal Assists", "A"),
            PlayerSheetFeature("Games Played", "GP"),
            PlayerSheetFeature("Games Started", "GS"),
        ]
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

    /// The feed's own labels (`displayNames`): a goalie's line first, as a
    /// skater's has none of its stats, then a skater's. A goalie's line
    /// also has "Time On Ice Per Game", but the sheet shows four at most.
    var featuredStatistics: [PlayerSheetFeature] {
        [
            PlayerSheetFeature("Goals Against Average", "GAA"),
            PlayerSheetFeature("Save Percentage", "SV%"),
            PlayerSheetFeature("Wins", "W"),
            PlayerSheetFeature("Shutouts", "SO"),
            PlayerSheetFeature("Goals", "G"),
            PlayerSheetFeature("Assists", "A"),
            PlayerSheetFeature("Penalty Minutes", "PIM"),
            PlayerSheetFeature("Time On Ice Per Game", "TOI"),
        ]
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

/// The sheet a roster card opens: the player over the team's colour, then
/// their season statistics and biography on cards over the grouped page,
/// which scrolls up over the colour as the team page's does (T-4).
///
/// The header fades as it scrolls under the sheet's top edge, and a compact
/// bar with the player's name fades in there in its place.
struct PlayerDetailView<Player: PlayerSheetDescribing>: View {
    /// A grid cell's narrowest width: three columns at the default text
    /// size, fewer as the text grows, one at the largest sizes (P-4).
    @ScaledMetric(relativeTo: .body) private var cellMinimumWidth: CGFloat = 96
    /// A headline tile's narrowest width: four across at the default size.
    @ScaledMetric(relativeTo: .title) private var featureMinimumWidth: CGFloat = 64
    /// The headshot, growing with the name beside it, to a point.
    @ScaledMetric(relativeTo: .largeTitle) private var headshotSize: CGFloat = 120

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let player: Player
    let team: TeamRef

    @State private var statistics: PlayerSheetGrid
    /// Whether `statistics(league:)` has answered.
    @State private var loaded = false
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    init(player: Player, team: TeamRef) {
        self.player = player
        self.team = team
        _statistics = State(initialValue: player.placeholderStatistics)
    }

    /// The team colour as a fill: the hero, the compact bar, the rate rings,
    /// the cards' accent bars. `fillHex` stands in a fallback for a team the
    /// feed gave no colour, which would otherwise draw clear (B-1).
    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    /// The ink that reads on `teamColor` (G-3), for strokes and fills; text
    /// takes it through `teamInk(on:)`.
    private var inkColor: Color { TeamColors.ink(on: team) }

    var body: some View {
        ZStack(alignment: .top) {
            heroBackdrop

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    header
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            headerHeight = height
                        }

                    page
                }
            }
            .scrollIndicators(.hidden)
            // The compact bar is opaque team colour: nothing to soften there.
            .scrollEdgeEffectHidden(true, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = max(offset, 0)
            }
        }
        // The grouped page, showing past the foot of a short page.
        .background(Theme.Surface.content)
        .overlay(alignment: .top) {
            compactBar
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton()
                // Pinned to its 44 pt circle, as the crest picker's "+" is.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("playerDetail.close")
                .padding(Theme.Spacing.m)
        }
        // Full height: the header alone fills most of a medium detent.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            let loadedStatistics = await player.statistics(league: team.league)
            statistics = loadedStatistics
            loaded = true
        }
    }

    // MARK: Hero

    /// The band at the top of the sheet left to the system grabber and the
    /// close button floating over it: the button's 44 pt and its inset.
    private static var closeButtonClearance: CGFloat { 44 + Theme.Spacing.m }

    /// How far the hero's colour runs below the header, so pulling the page
    /// down shows colour rather than the grouped page.
    private static var heroOverscroll: CGFloat { 240 }

    /// 0 with the header in full view, 1 once it has scrolled under the
    /// compact bar.
    private var collapseProgress: CGFloat {
        let distance = max(headerHeight - Self.closeButtonClearance, 1)
        return min(max(scrollOffset / distance, 0), 1)
    }

    /// The compact bar comes in over the last quarter of the collapse.
    private var compactBarOpacity: Double {
        Double(min(max((collapseProgress - 0.75) / 0.25, 0), 1))
    }

    /// The team colour behind the header. It never scrolls: the page covers
    /// it. It extends into any landscape side insets (B5).
    private var heroBackdrop: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(teamColor)
                .backgroundExtensionEffect()

            TeamLogo(team: team, size: 300, forceVariant: .default)
                .opacity(0.1)
                .saturation(0.1)
                .contrast(0.5)
        }
        .frame(height: headerHeight + Self.heroOverscroll, alignment: .top)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Where the grabber and close button float.
            Color.clear
                .frame(height: Self.closeButtonClearance)

            headshot

            VStack(spacing: Theme.Spacing.s) {
                Text(player.name)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                subtitle
            }
            // The ink that reads on this team's fill, not always white
            // (B-1, G-3).
            .teamInk(on: team)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .opacity(Double(1 - collapseProgress))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(headerAccessibilityLabel))
        .accessibilityAddTraits(.isHeader)
    }

    /// "Name, number 23, Guard", leaving out what the feed left out.
    private var headerAccessibilityLabel: String {
        var parts = [player.name]
        if !number.isEmpty { parts.append("number \(number)") }
        if !position.isEmpty { parts.append(position) }
        return parts.joined(separator: ", ")
    }

    private var number: String { player.number.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var position: String { player.position.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The number in an outlined capsule beside the position, or above it
    /// at accessibility sizes. An outline rather than a tinted fill, so the
    /// ink keeps its full contrast on the team colour.
    @ViewBuilder
    private var subtitle: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        layout {
            if !number.isEmpty {
                Text("#\(number)")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .overlay {
                        Capsule()
                            .strokeBorder(inkColor, lineWidth: 1.5)
                    }
            }
            if !position.isEmpty {
                Text(position)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The headshot in a circle; the player's initials stand in while it
    /// loads or where the feed has none, or their number without a name.
    private var headshot: some View {
        let size = min(headshotSize, 180)
        return RemoteImage(url: URL(string: player.photo), showsProgress: false) {
            monogram(size: size)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .background(inkColor.opacity(0.15), in: Circle())
        .clipShape(.circle)
        .overlay {
            Circle()
                .strokeBorder(inkColor.opacity(0.35), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    private func monogram(size: CGFloat) -> some View {
        let initials = Self.initials(of: player.name)
        let text = initials.isEmpty ? number : initials
        return ZStack {
            if text.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
            } else {
                // Proportional to the headshot, not to Dynamic Type: the
                // headshot already scales.
                Text(text)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .teamInk(on: team)
    }

    /// The first and last names' first letters ("FA" for "Felix
    /// Anudike-Uzomah"), one for a single name, none for no name.
    private static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return "\(first)\(last)".uppercased()
    }

    /// The player's name, pinned under the sheet's top edge once the header
    /// has scrolled away. VoiceOver reads the header instead.
    private var compactBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(player.name)
                .font(Theme.Typography.cardTitle)
            if !number.isEmpty {
                Text("#\(number)")
                    .font(Theme.Typography.cardTitle.monospacedDigit())
                    // Half-strength ink on the team colour, firmer under
                    // Increase Contrast and Reduce Transparency (X-5).
                    .adaptiveScrim(0.7)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .teamInk(on: team)
        // Clear of the close button, and centred.
        .padding(.horizontal, 44 + Theme.Spacing.m * 2)
        .frame(maxWidth: .infinity)
        .frame(height: Self.closeButtonClearance)
        .background(teamColor)
        .opacity(compactBarOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Page

    /// The cards on the grouped page, its top rounded where it meets the
    /// hero, as the team page's is (T-4). No glass: this scrolls (B1).
    private var page: some View {
        VStack(spacing: Theme.Spacing.m) {
            statisticsCard

            if !facts.isEmpty {
                aboutCard
            }
        }
        .padding(Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xl)
        // Tall enough to cover the hero's overscroll on a short page.
        .frame(maxWidth: .infinity, minHeight: Self.heroOverscroll + Self.closeButtonClearance, alignment: .top)
        .background(Theme.Surface.content, in: Theme.Radius.pageShape)
    }

    /// A card's heading: label ink on the card, the team colour as an
    /// accent bar beside it, as no team colour reads on every surface in
    /// both appearances (B-3).
    private func cardTitle(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            TeamAccentBar(color: teamColor)
            Text(title)
                .font(Theme.Typography.sectionTitle)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            content()
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The page cards' surface, so the sheet's cards match them (B-7).
        .contentCard()
    }

    // MARK: Season stats

    private var statisticsCard: some View {
        card {
            cardTitle("Season Stats")
                .accessibilityIdentifier("playerDetail.section")

            statisticsContent
                .motionAnimation(Theme.Motion.stateChange, value: loaded)
        }
    }

    /// Every cell in the grid, in reading order.
    private var allCells: [PlayerSheetCell] {
        statistics.sections.flatMap(\.rows).flatMap { $0 }
    }

    /// The player's headline statistics that the grid has, four at most.
    private var featuredCells: [(abbreviation: String, cell: PlayerSheetCell)] {
        let cells = allCells
        var used: Set<String> = []
        var featured: [(abbreviation: String, cell: PlayerSheetCell)] = []
        for feature in player.featuredStatistics where featured.count < 4 {
            guard !used.contains(feature.title),
                  let cell = cells.first(where: { $0.title == feature.title })
            else { continue }
            used.insert(feature.title)
            featured.append((abbreviation: feature.abbreviation, cell: cell))
        }
        return featured
    }

    /// The grid's sections less the headline cells, and less any section
    /// those leave empty.
    private func remainingSections(excluding titles: Set<String>) -> [PlayerSheetGrid.Section] {
        statistics.sections.compactMap { section -> PlayerSheetGrid.Section? in
            let rows = section.rows
                .map { row in row.filter { !titles.contains($0.title) } }
                .filter { !$0.isEmpty }
            return rows.isEmpty ? nil : PlayerSheetGrid.Section(title: section.title, rows: rows)
        }
    }

    @ViewBuilder
    private var statisticsContent: some View {
        if allCells.isEmpty {
            if loaded {
                emptyMessage(statistics.message ?? "No season statistics are available for this player yet.")
            } else {
                statisticsSkeleton
            }
        } else if loaded {
            statisticsBody
        } else {
            // The placeholder line's layout, redacted, until the real one
            // lands (D-7).
            statisticsBody
                .loadingPlaceholder()
        }
    }

    private var statisticsBody: some View {
        let featured = featuredCells
        let sections = remainingSections(excluding: Set(featured.map { $0.cell.title }))
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !featured.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: featureMinimumWidth), spacing: Theme.Spacing.s)],
                    spacing: Theme.Spacing.s
                ) {
                    ForEach(Array(featured.enumerated()), id: \.offset) { _, feature in
                        FeaturedStatTile(abbreviation: feature.abbreviation, cell: feature.cell)
                    }
                }
            }

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let title = section.title {
                        Text(title)
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
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
            }

            if let message = statistics.message {
                emptyMessage(message)
            }
        }
    }

    /// Stand-in headline tiles while a line with nothing to lay out yet
    /// (football's, soccer's without roster totals) loads.
    private var statisticsSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: featureMinimumWidth), spacing: Theme.Spacing.s)],
            spacing: Theme.Spacing.s
        ) {
            ForEach(0..<4, id: \.self) { _ in
                FeaturedStatTile(abbreviation: "STAT", cell: .stat(title: "Statistic", info: "00.0"))
            }
        }
        .loadingPlaceholder()
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func cellView(_ cell: PlayerSheetCell) -> some View {
        switch cell {
        case .fact(let title, let info), .stat(let title, let info):
            StatCell(title: title, info: info)
        case .percentage(let title, let progress):
            StatPercentageView(progress: progress, color: teamColor, title: title)
                .animation(.spring(response: 0.6, dampingFraction: 1.0, blendDuration: 1.0), value: progress)
        }
    }

    // MARK: About

    /// The biography facts with something in them. Position is left
    /// out: the header shows it.
    private var facts: [(title: String, info: String)] {
        player.about.sections.flatMap(\.rows).flatMap { $0 }.compactMap { cell -> (title: String, info: String)? in
            guard case .fact(let title, let info) = cell, title != "Position" else { return nil }
            let trimmed = info.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (title: title, info: trimmed)
        }
    }

    private var aboutCard: some View {
        card {
            cardTitle("About")

            VStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 {
                        Divider()
                    }
                    FactRow(title: fact.title, value: fact.info)
                }
            }
        }
    }
}

// MARK: - Cells

/// A headline statistic: a large figure over its short label, on the inset
/// surface. VoiceOver reads the full title and the value as one element.
private struct FeaturedStatTile: View {
    let abbreviation: String
    let cell: PlayerSheetCell

    private var value: String {
        switch cell {
        case .fact(_, let info), .stat(_, let info):
            return info.isEmpty ? "N/A" : info
        case .percentage(_, let progress):
            return progress.isFinite
                ? progress.formatted(.percent.precision(.fractionLength(0)))
                : "N/A"
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.title.weight(.black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(abbreviation)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.s)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cell.title))
        .accessibilityValue(Text(value))
    }
}

/// A season statistic in the grid: the figure over its label. The grid
/// sets the width (P-4); VoiceOver reads label and value as one element.
private struct StatCell: View {
    let title: String
    let info: String

    private var value: String { info.isEmpty ? "N/A" : info }

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .multilineTextAlignment(.center)

            Text(title)
                .font(Theme.Typography.statLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

/// A biography fact as a Settings-style row: the label leading, the value
/// trailing, stacked at accessibility sizes so neither truncates.
private struct FactRow: View {
    let title: String
    let value: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.m))
        layout {
            Text(title)
                .foregroundStyle(.secondary)
            if !stacked {
                Spacer(minLength: Theme.Spacing.m)
            }
            Text(value)
                .multilineTextAlignment(stacked ? .leading : .trailing)
        }
        .font(Theme.Typography.body)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
