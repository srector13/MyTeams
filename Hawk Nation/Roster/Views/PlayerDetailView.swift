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
    /// A biography fact, drawn as a `FactTile` on the About card.
    case fact(title: String, info: String)
    /// A season statistic, drawn as a `StatRow` or a key-stat tile.
    case stat(title: String, info: String)
    /// A rate drawn as a `StatRow` with a slim bar in the team's accent:
    /// `progress` runs 0–1, and a non-finite one (a rate over zero
    /// attempts) reads "N/A". With its `attempts`, where the feed gives
    /// them, a rate over fewer than `minimumBarAttempts` reads "0 of 3"
    /// with no bar (P3).
    case percentage(title: String, progress: Double, attempts: MadeAttempted? = nil)
}

/// One card of a player sheet: its cells, optionally under section titles.
///
/// Cells come grouped in rows, the order they read in. The Season Stats
/// card lifts its key statistics into tiles (`featuredCells(for:)`) and
/// lists the rest as labelled rows under each section's title.
struct PlayerSheetGrid: Sendable {
    struct Section: Sendable {
        var title: String?
        var rows: [[PlayerSheetCell]]
    }

    var sections: [Section]
    /// Shown beneath the sections, e.g. once a fetch found nothing.
    var message: String?
    /// The seasons the sheet's season picker offers, from the splits
    /// document the grid was read from.
    var seasons: AthleteSeasons = .empty
    /// Whether the fetch behind the grid failed, or answered without its
    /// season list: the sheet says it couldn't load the season, with a
    /// Retry, rather than that there is nothing in it (P8).
    var loadFailed = false

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

    /// The Season Stats card before `statistics(league:season:)` has
    /// answered.
    var placeholderStatistics: PlayerSheetGrid { get }

    /// Loads the player's statistics in `league` for `season`, an
    /// `AthleteSeason.value`, or for the feed's current season when `nil`.
    /// The grid's `seasons` are those the feed offers.
    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid

    /// The statistics lifted out of the grid into the sheet's key-stat
    /// tiles, by their cell titles, in the order they're shown, chosen for
    /// the sport and the player's position. A title the grid lacks is
    /// skipped, so one list can serve two stat lines.
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
    /// Whether the tile takes a row of its own above the others, for a
    /// figure too wide to share one. It doesn't count toward the four
    /// tiles.
    var spansRow: Bool
    /// The title of the section the cell is looked for in, for a title
    /// several sections share (football's "Yards"); `nil` looks in all.
    var section: String?
    /// What VoiceOver calls the tile ("Goals" for "Total Goals"); `nil`
    /// reads the cell's title.
    var spokenTitle: String?

    init(
        _ title: String,
        _ abbreviation: String,
        spansRow: Bool = false,
        in section: String? = nil,
        spoken spokenTitle: String? = nil
    ) {
        self.title = title
        self.abbreviation = abbreviation
        self.spansRow = spansRow
        self.section = section
        self.spokenTitle = spokenTitle
    }
}

extension PlayerSheetCell {
    /// The label the cell is drawn with, whatever its kind.
    var title: String {
        switch self {
        case .fact(let title, _), .stat(let title, _), .percentage(let title, _, _):
            return title
        }
    }

    /// Whether a feed value says nothing: empty, or one of the placeholders
    /// the feed and the parsers stand in for a missing value ("N/A", "--",
    /// "-"), whatever its case or padding.
    static func isMissing(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || ["n/a", "--", "-"].contains(trimmed.lowercased())
    }

    /// Whether the cell's figure is missing or zero however it's written
    /// ("0", "0.0", ".000/.000/.000", "0:00"), or its rate is zero or over
    /// no attempts. A fact is never empty in this sense.
    var isEmptyFigure: Bool {
        switch self {
        case .fact:
            return false
        case .stat(_, let info):
            return Self.isMissing(info)
                || info.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy { "0.,:/%-".contains($0) }
        case .percentage(_, let progress, _):
            return !progress.isFinite || progress == 0
        }
    }
}

extension PlayerSheetGrid {
    /// Whether the grid is a season with nothing in it yet: "0" games
    /// played, or every figure zero or missing, as a college line reads in
    /// October. The sheet says so in a line rather than drawing a grid of
    /// 0.0s. A grid with no cells at all isn't one: it has its own message.
    var hasNoFigures: Bool {
        let cells = sections.flatMap(\.rows).flatMap { $0 }
        guard !cells.isEmpty else { return false }
        let noGames = cells.contains { cell in
            guard case .stat(let title, _) = cell, title == "Games Played" else { return false }
            return cell.isEmptyFigure
        }
        return noGames || cells.allSatisfy(\.isEmptyFigure)
    }

    /// The About card's facts with something in them, trimmed: a fact the
    /// feed left empty or filled with "N/A" or "--" (a player opened from a
    /// box score has little else) is left out. Position is too: the sheet's
    /// header shows it.
    var aboutFacts: [(title: String, info: String)] {
        sections.flatMap(\.rows).flatMap { $0 }.compactMap { cell -> (title: String, info: String)? in
            guard case .fact(let title, let info) = cell, title != "Position",
                  !PlayerSheetCell.isMissing(info)
            else { return nil }
            return (title: title, info: info.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The columns a stat grid lays `cells` out in, given the `fitting`
    /// that fit across it at their narrowest (P-4): one fewer where all of
    /// them would leave a lone cell on the last row and one fewer fills
    /// every row, as ten cells in threes left "Average Turnovers" alone.
    static func columnCount(fitting: Int, cells: Int) -> Int {
        let columns = max(fitting, 1)
        if columns > 2, cells % columns == 1, cells % (columns - 1) == 0 {
            return columns - 1
        }
        return columns
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
                .fact(title: "Hometown", info: hometown),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid {
        let stats = await downloadBasketballPlayerStats(playerID: playerID, league: league, season: season)
        var sheet = Self.grid(stats)
        sheet.seasons = stats.seasons
        sheet.loadFailed = stats.loadFailed
        return sheet
    }

    /// Points, rebounds and assists a game, then minutes.
    var featuredStatistics: [PlayerSheetFeature] {
        [
            PlayerSheetFeature("Average Points", "PPG", spoken: "Points per game"),
            PlayerSheetFeature("Average Rebounds", "RPG", spoken: "Rebounds per game"),
            PlayerSheetFeature("Average Assists", "APG", spoken: "Assists per game"),
            PlayerSheetFeature("Average Minutes", "MPG", spoken: "Minutes per game"),
        ]
    }

    /// Scoring with its shooting rates, each over its season's attempts
    /// where the feed gives them (P3), rebounding, then the rest.
    static func grid(_ stats: BasketballPlayerStats) -> PlayerSheetGrid {
        func average(_ value: Float) -> String { String(format: "%.1f", value) }

        return PlayerSheetGrid(sections: [
            PlayerSheetGrid.Section(title: "Scoring", rows: [
                [
                    .stat(title: "Games Played", info: "\(stats.gamesPlayed)"),
                    .stat(title: "Average Minutes", info: average(stats.avgMinutes)),
                    .stat(title: "Average Points", info: average(stats.avgPoints)),
                ],
                [
                    .percentage(
                        title: "Field Goal Percentage",
                        progress: Double(stats.fieldGoalPct) / 100,
                        attempts: stats.fieldGoals
                    ),
                    .percentage(
                        title: "3-Point Percentage",
                        progress: Double(stats.threePointFieldGoalPct) / 100,
                        attempts: stats.threePointers
                    ),
                    .percentage(
                        title: "Free Throw Percentage",
                        progress: Double(stats.freeThrowPct) / 100,
                        attempts: stats.freeThrows
                    ),
                ],
            ]),
            PlayerSheetGrid.Section(title: "Rebounding", rows: [
                [
                    .stat(title: "Average Rebounds", info: average(stats.avgRebounds)),
                    .stat(title: "Avg. Defensive Rebounds", info: average(stats.avgDefensiveRebounds)),
                    .stat(title: "Avg. Offensive Rebounds", info: average(stats.avgOffensiveRebounds)),
                ],
            ]),
            PlayerSheetGrid.Section(title: "Playmaking & Defense", rows: [
                [
                    .stat(title: "Average Assists", info: average(stats.avgAssists)),
                    .stat(title: "Average Blocks", info: average(stats.avgBlocks)),
                    .stat(title: "Average Steals", info: average(stats.avgSteals)),
                ],
                [
                    .stat(title: "Average Fouls", info: average(stats.avgFouls)),
                    .stat(title: "Average Turnovers", info: average(stats.avgTurnovers)),
                ],
            ]),
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
                .fact(title: "Hometown", info: hometown),
                .fact(title: "Height", info: height),
                .fact(title: "Weight", info: weight),
            ],
            [
                .fact(title: "Age", info: age),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid {
        let stats = await downloadFootballPlayerStats(playerID: playerID, league: league, season: season)
        var sheet = Self.grid(stats)
        sheet.seasons = stats.seasons
        sheet.loadFailed = stats.loadFailed
        return sheet
    }

    /// By position group: a passer's, a runner's, a receiver's, a
    /// kicker's, a punter's or a defender's line (`footballKeyStats`).
    var featuredStatistics: [PlayerSheetFeature] {
        footballKeyStats(position: position)
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
            message: stats.loaded && stats.groups.isEmpty && !stats.loadFailed
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
                .fact(title: "Hometown", info: hometown),
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

    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid {
        let stats = await downloadBaseballPlayerStats(
            playerID: playerID,
            playerPosition: position,
            league: league,
            season: season
        )
        var sheet = grid(stats)
        sheet.seasons = stats.seasons
        sheet.loadFailed = stats.loadFailed
        return sheet
    }

    /// A starter's ERA, win-loss record, strikeouts and WHIP, a
    /// reliever's ERA, innings, strikeouts and WHIP
    /// (`baseballPitcherKeyStats`); a batter's average, home runs, RBIs and
    /// OPS.
    var featuredStatistics: [PlayerSheetFeature] {
        if position.contains("Pitcher") {
            return baseballPitcherKeyStats(position: position)
        }
        return [
            PlayerSheetFeature("Batting Average", "AVG", spoken: "Batting average"),
            PlayerSheetFeature("Home Runs", "HR", spoken: "Home runs"),
            PlayerSheetFeature("RBIs", "RBI", spoken: "Runs batted in"),
            PlayerSheetFeature("OPS", "OPS", spoken: "On-base plus slugging"),
        ]
    }

    /// Pitchers get the pitching line, titled from one table
    /// (`PlayerStatWording.pitching`); everyone else the batting line. A
    /// reliever's line has no win-loss record: his wins and losses have
    /// rows of their own, mostly zeros behind "Show all stats" (P9).
    func grid(_ stats: BaseballPlayerStats) -> PlayerSheetGrid {
        if position.contains("Pitcher") {
            func pitching(_ name: String, _ info: String) -> PlayerSheetCell {
                PlayerStatWording.pitching(name).stat(info)
            }
            var record: [PlayerSheetCell] = [
                pitching("ERA", String(format: "%.2f", stats.EarnedRunAverage)),
            ]
            if !isReliefPitcher(position) {
                record.append(pitching("winLoss", "\(stats.wins)-\(stats.losses)"))
            }
            record.append(pitching("WHIP", baseballWHIP(walks: stats.walks, hits: stats.hits, innings: stats.innings)))
            record.append(pitching("innings", "\(stats.innings)"))

            return PlayerSheetGrid(sections: [
                PlayerSheetGrid.Section(title: "Pitching", rows: [
                    record,
                    [
                        pitching("gamesPlayed", "\(stats.gamesPlayed)"),
                        pitching("gamesStarted", "\(stats.gamesStarted)"),
                        pitching("completeGames", "\(stats.completeGames)"),
                    ],
                    [
                        pitching("wins", "\(stats.wins)"),
                        pitching("losses", "\(stats.losses)"),
                        pitching("saves", "\(stats.saves)"),
                        pitching("saveOpportunities", "\(stats.saveOpportunities)"),
                    ],
                ]),
                PlayerSheetGrid.Section(title: "Against", rows: [
                    [
                        pitching("strikeouts", "\(stats.strikeouts)"),
                        pitching("walks", "\(stats.walks)"),
                        pitching("hits", "\(stats.hits)"),
                        pitching("homeRuns", "\(stats.homeRuns)"),
                    ],
                    [
                        pitching("runs", "\(stats.runs)"),
                        pitching("earnedRuns", "\(stats.earnedRuns)"),
                        pitching("opponentAvg", baseballRate(stats.opponentAvg)),
                    ],
                ]),
            ])
        }

        return PlayerSheetGrid(sections: [
            PlayerSheetGrid.Section(title: "Hitting", rows: [
                [
                    .stat(title: "Batting Average", info: baseballRate(stats.Avg)),
                    .stat(title: "Home Runs", info: "\(stats.HomeRuns)"),
                    .stat(title: "RBIs", info: String(format: "%.0f", stats.RBIs)),
                    .stat(title: "OPS", info: baseballRate(stats.OPS)),
                ],
                [
                    .stat(title: "At Bats", info: "\(stats.AtBats)"),
                    .stat(title: "Runs", info: "\(stats.Runs)"),
                    .stat(title: "Hits", info: "\(stats.Hits)"),
                    .stat(title: "Doubles", info: "\(stats.Doubles)"),
                    .stat(title: "Triples", info: "\(stats.Triples)"),
                ],
                [
                    .stat(title: Self.slashLineTitle, info: baseballSlashLine(stats)),
                ],
            ]),
            PlayerSheetGrid.Section(title: "Plate Discipline", rows: [
                [
                    .stat(title: "Walks", info: "\(stats.Walks)"),
                    .stat(title: "Strikeouts", info: "\(stats.Strikeouts)"),
                    .stat(title: "Hit By Pitches", info: "\(stats.HitByPitch)"),
                ],
            ]),
            PlayerSheetGrid.Section(title: "Base Running", rows: [
                [
                    .stat(title: "Stolen Bases", info: "\(stats.StolenBases)"),
                    .stat(title: "Caught Stealing", info: "\(stats.CaughtStealing)"),
                ],
            ]),
        ])
    }

    /// The slash line's cell title, which VoiceOver reads for its row.
    private static let slashLineTitle = "Batting Average / On-Base / Slugging"
}

/// A batter's AVG/OBP/SLG as a box score prints it, `".281/.357/.455"`: a
/// rate under one loses its leading zero, a rate of one or more
/// (`"1.000"`) keeps it.
func baseballSlashLine(_ stats: BaseballPlayerStats) -> String {
    [stats.Avg, stats.OnBasePct, stats.SlugAvg]
        .map(baseballRate)
        .joined(separator: "/")
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
    /// document's headline figures instead. Neither has seasons to pick
    /// from, so `season` goes unused.
    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid {
        guard !hasSeasonStats else { return seasonTotals }
        let stats = await downloadSoccerPlayerStats(playerID: playerID, playerPosition: position, league: league)
        return Self.headline(stats, keeper: isSoccerGoalkeeper(position))
    }

    /// The player's line on the pitch (`SoccerRole`), which picks the
    /// tiles and the order of the groups (P1).
    var soccerRole: SoccerRole { SoccerRole(position: position) }

    /// The tiles for the player's line (`soccerKeyStats(role:)`). One list
    /// serves both the roster's season totals and the athlete document's
    /// headline figures, skipping what a line lacks (the roster has no
    /// clean sheets; no soccer feed has minutes, tackles or interceptions).
    var featuredStatistics: [PlayerSheetFeature] {
        soccerKeyStats(role: soccerRole)
    }

    /// The roster's `appearances` counts substitute appearances too, so
    /// starts are the difference. (They used to be shown as `appearances`,
    /// and games played as `appearances + subAppearances`, counting every
    /// substitute appearance twice.)
    private var starts: Int { max(appearances - subAppearances, 0) }

    /// Keepers get the goalkeeping line; everyone else the outfield line:
    /// appearances, attacking (with shot accuracy and conversion as rates
    /// over the shots, and rates a game: no soccer feed carries minutes, so
    /// per 90 can't be worked out) and discipline, in the order the
    /// player's line reads them (P1): a defender's discipline before his
    /// attacking, a forward's attacking first. A defender's appearances
    /// add the goals let in while he was on the pitch, the roster's
    /// `goalsConceded` for an outfield player. Every row is titled from one
    /// table (`PlayerStatWording.soccer`), so a tile and its row agree (P7).
    private var seasonTotals: PlayerSheetGrid {
        func stat(_ name: String, _ value: Int) -> PlayerSheetCell {
            PlayerStatWording.soccer(name).stat("\(value)")
        }
        func rate(_ name: String, _ made: Int, of attempts: Int) -> PlayerSheetCell {
            .percentage(
                title: PlayerStatWording.soccer(name).title,
                progress: Double(made) / Double(attempts),
                attempts: MadeAttempted(made: made, attempted: attempts)
            )
        }
        func perGame(_ name: String, _ total: Int) -> PlayerSheetCell {
            PlayerStatWording.soccer(name).stat(perGameRate(total, games: appearances))
        }

        let discipline = PlayerSheetGrid.Section(title: "Discipline", rows: [
            [
                stat("foulsCommitted", fouls),
                stat("foulsSuffered", foulsSuffered),
            ],
            [
                stat("yellowCards", yellowCards),
                stat("redCards", redCards),
                stat("ownGoals", ownGoals),
            ],
        ])

        if soccerRole == .goalkeeper {
            return PlayerSheetGrid(sections: [
                PlayerSheetGrid.Section(title: "Appearances", rows: [
                    [
                        stat("appearances", appearances),
                        stat("starts", starts),
                    ],
                ]),
                PlayerSheetGrid.Section(title: "Goalkeeping", rows: [
                    [
                        stat("saves", saves),
                        stat("goalsConceded", goalsConceded),
                        stat("shotsFaced", shotsFaced),
                    ],
                    [
                        rate("savePct", saves, of: shotsFaced),
                        perGame("savesPerGame", saves),
                        perGame("concededPerGame", goalsConceded),
                    ],
                ]),
                discipline,
            ])
        }

        var appearing: [PlayerSheetCell] = [
            stat("appearances", appearances),
            stat("starts", starts),
            stat("subIns", subAppearances),
        ]
        if soccerRole == .defender {
            appearing.append(stat("goalsConcededOnPitch", goalsConceded))
        }
        let appearancesSection = PlayerSheetGrid.Section(title: "Appearances", rows: [appearing])
        let attacking = PlayerSheetGrid.Section(title: "Attacking", rows: [
            [
                stat("totalGoals", totalGoals),
                stat("goalAssists", goalAssists),
            ],
            [
                stat("totalShots", totalShots),
                stat("shotsOnTarget", shotsOnTarget),
                rate("shotAccuracy", shotsOnTarget, of: totalShots),
                rate("conversionRate", totalGoals, of: totalShots),
            ],
            [
                perGame("goalsPerGame", totalGoals),
                perGame("shotsPerGame", totalShots),
                stat("offsides", offsides),
            ],
        ])

        switch soccerRole {
        case .defender:
            return PlayerSheetGrid(sections: [appearancesSection, discipline, attacking])
        case .forward:
            return PlayerSheetGrid(sections: [attacking, appearancesSection, discipline])
        case .midfielder, .goalkeeper:
            return PlayerSheetGrid(sections: [appearancesSection, attacking, discipline])
        }
    }

    /// The athlete document's headline figures, titled as the roster's
    /// are. See `SoccerPlayerStats`. A document that didn't arrive is a
    /// failed load (P8), not a player with no statistics.
    private static func headline(_ stats: SoccerPlayerStats, keeper: Bool) -> PlayerSheetGrid {
        func stat(_ name: String, _ info: String) -> PlayerSheetCell {
            PlayerStatWording.soccer(name).stat(info)
        }
        guard !stats.loadFailed else {
            var failed = PlayerSheetGrid(sections: [])
            failed.loadFailed = true
            return failed
        }
        guard stats.hasFigures else {
            return PlayerSheetGrid(
                sections: [],
                message: "No season statistics are available for this player yet."
            )
        }
        if keeper {
            return PlayerSheetGrid(sections: [
                PlayerSheetGrid.Section(title: "Goalkeeping", rows: [[
                    stat("starts", stats.starts),
                    stat("saves", stats.saves),
                    stat("cleanSheet", stats.cleanSheets),
                    stat("goalsConceded", stats.goalsConceded),
                ]]),
            ])
        }
        return PlayerSheetGrid(sections: [
            PlayerSheetGrid.Section(title: "Appearances", rows: [[
                stat("starts", stats.starts),
                stat("subIns", stats.substituteAppearances),
            ]]),
            PlayerSheetGrid.Section(title: "Attacking", rows: [[
                stat("totalGoals", stats.goals),
                stat("goalAssists", stats.assists),
                stat("totalShots", stats.shots),
            ]]),
        ])
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
                .fact(title: "Hometown", info: hometown),
            ],
        ])
    }

    var placeholderStatistics: PlayerSheetGrid { Self.grid(.empty) }

    func statistics(league: LeagueID, season: String?) async -> PlayerSheetGrid {
        let line = await downloadHockeyPlayerStats(playerID: playerID, league: league, season: season)
        var sheet = Self.grid(line)
        sheet.seasons = line.seasons
        sheet.loadFailed = line.loadFailed
        return sheet
    }

    /// The feed's own labels (`displayNames`): a goalie's line first, as a
    /// skater's has none of its stats, then a skater's goals, assists,
    /// points and plus/minus. A goalie's line also has "Time On Ice Per
    /// Game", but the sheet shows four at most.
    var featuredStatistics: [PlayerSheetFeature] {
        [
            PlayerSheetFeature("Goals Against Average", "GAA", spoken: "Goals against average"),
            PlayerSheetFeature("Save Percentage", "SV%", spoken: "Save percentage"),
            PlayerSheetFeature("Wins", "W", spoken: "Wins"),
            PlayerSheetFeature("Shutouts", "SO", spoken: "Shutouts"),
            PlayerSheetFeature("Goals", "G", spoken: "Goals"),
            PlayerSheetFeature("Assists", "A", spoken: "Assists"),
            PlayerSheetFeature("Points", "PTS", spoken: "Points"),
            PlayerSheetFeature("Plus/Minus Rating", "+/-", spoken: "Plus-minus"),
        ]
    }

    /// The season line under "Skating" or "Goaltending", three stats a
    /// row, each labelled with the feed's own name for it. A skater and a
    /// goalie get different stats; see `hockeySheetStats(from:)`.
    private static func grid(_ line: SplitsSeasonLine) -> PlayerSheetGrid {
        let stats = hockeySheetStats(from: line)
        let title = line.stat("savePct") != nil ? "Goaltending" : "Skating"
        let rows = stride(from: 0, to: stats.count, by: 3).map { start in
            stats[start ..< min(start + 3, stats.count)].map {
                PlayerSheetCell.stat(title: $0.label, info: $0.display)
            }
        }
        return PlayerSheetGrid(
            sections: stats.isEmpty ? [] : [PlayerSheetGrid.Section(title: title, rows: rows)],
            message: line.loaded && stats.isEmpty && !line.loadFailed
                ? "No season statistics are available for this player yet."
                : nil
        )
    }
}


// MARK: - Sheet

/// The sheet a roster card opens: the player over the team's colour, then
/// their season statistics, recent games and biography on cards over the
/// grouped page, which scrolls up over the colour as the team page's does
/// (T-4). On an iPad the cards keep to a 640 pt column, the stat groups
/// two across (P11).
///
/// The header fades as it scrolls under the sheet's top edge, the headshot
/// first so the grabber never sits over it, and a compact bar with the
/// player's name fades in there in its place. A short page is padded so
/// the header always finishes collapsing into that bar (P10).
struct PlayerDetailView<Player: PlayerSheetDescribing>: View {
    /// A key-stat tile's narrowest width: four across at the default text
    /// size, fewer as the text grows (P-4).
    @ScaledMetric(relativeTo: .title) private var featureMinimumWidth: CGFloat = 68
    /// An About tile's narrowest width: two across at the default text
    /// size, one at the largest.
    @ScaledMetric(relativeTo: .body) private var factMinimumWidth: CGFloat = 140
    /// The headshot, growing with the name beside it, to a point.
    @ScaledMetric(relativeTo: .largeTitle) private var headshotSize: CGFloat = 120

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let player: Player
    let team: TeamRef

    @State private var statistics: PlayerSheetGrid
    /// Whether `statistics(league:season:)` has answered for `season`.
    @State private var loaded = false
    /// Bumped by Retry, to fetch the season again after a failed load (P8).
    @State private var statisticsAttempt = 0
    /// Bumped by the game-log card's Retry.
    @State private var gameLogAttempt = 0
    /// Whether "Show all stats" has opened the zero rows and groups (P2).
    @State private var showsAllStats = false
    /// The seasons the picker offers, from the first fetch: a past season's
    /// document lists only itself.
    @State private var seasons: [AthleteSeason] = []
    /// The picker's selection, an `AthleteSeason.value`; empty until the
    /// first fetch says which season it is for.
    @State private var season = ""
    /// The season `statistics` is for.
    @State private var statisticsSeason = ""
    /// The season the first fetch was for: the feed's current one.
    @State private var currentSeason = ""
    @State private var gameLog = AthleteGameLog.empty
    /// The `gameLogRequest` `gameLog` answers, once it has.
    @State private var gameLogAnswers: String?
    /// Whether the game-log card has scrolled into view. Its request waits
    /// for that, so a sheet opened and closed costs no extra fetch.
    @State private var gameLogVisible = false
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// The scroll view's height, which the page grows to fill so a short
    /// sheet can still scroll the header away (P10).
    @State private var viewportHeight: CGFloat = 0
    /// The key-stat tiles' width, for their column count; zero until
    /// measured.
    @State private var tileWidth: CGFloat = 0

    init(player: Player, team: TeamRef) {
        self.player = player
        self.team = team
        _statistics = State(initialValue: player.placeholderStatistics)
    }

    /// The team colour as a fill: the hero and the compact bar. `fillHex`
    /// stands in a fallback for a team the feed gave no colour, which would
    /// otherwise draw clear (B-1).
    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    /// The team's colour as a mark on the cards (F3): the section bars, the
    /// rate bars, a scoring chip's wash. Lightened where the team colour
    /// would vanish on a dark card, as navy does.
    private var accentColor: Color { TeamColors.accent(for: team) }

    /// The hero's own ink, white or black, whichever reads on `teamColor`:
    /// the name, the position, the headshot's ring (P4).
    private var heroInk: Color {
        Color(hexString: TeamColors.inkHex(on: TeamColors.fillHex(for: team)))
    }

    /// The team's tint on its colour (G-3), its alternate colour where that
    /// reads: only the number capsule wears it (P4).
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                viewportHeight = height
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
        // A page-sized sheet on iPad, not the small form sheet.
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
        .task(id: "\(season)#\(statisticsAttempt)") {
            await loadStatistics()
        }
    }

    /// Loads the statistics for the picked season, or for the feed's current
    /// one before anything is picked. Adopting that first fetch's season
    /// into the picker re-runs this, which then has nothing to do; a Retry
    /// after a failed load fetches again.
    private func loadStatistics() async {
        guard !loaded || season != statisticsSeason || statistics.loadFailed else { return }
        let requested = season.isEmpty ? nil : season
        loaded = false
        let loadedStatistics = await player.statistics(league: team.league, season: requested)
        // A newer pick has taken over.
        guard !Task.isCancelled else { return }
        statistics = loadedStatistics
        if seasons.isEmpty {
            seasons = loadedStatistics.seasons.options
        }
        statisticsSeason = requested ?? loadedStatistics.seasons.selected ?? ""
        if requested == nil {
            currentSeason = statisticsSeason
        }
        loaded = true
        if season.isEmpty {
            season = statisticsSeason
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

    /// The headshot is gone before its top edge reaches the grabber and
    /// the close button's band: it fades over the first scroll it takes to
    /// get there, ahead of the rest of the header (P10).
    private var headshotOpacity: Double {
        let distance = max(Self.closeButtonClearance - Theme.Spacing.s, 1)
        return Double(1 - min(max(scrollOffset / distance, 0), 1))
    }

    /// The page's least height: enough, under the header, for the scroll
    /// to carry the header all the way under the compact bar however
    /// little the page holds (P10), and to cover the hero's overscroll.
    private var pageMinimumHeight: CGFloat {
        max(Self.heroOverscroll + Self.closeButtonClearance, viewportHeight - Self.closeButtonClearance)
    }

    /// The page's column: 640 pt on an iPad's regular width (P11), the
    /// readable width otherwise (a no-op on an iPhone).
    private var columnWidth: CGFloat {
        horizontalSizeClass == .regular ? 640 : Theme.readableWidth
    }

    /// Whether the stat groups sit two across: on an iPad's regular width,
    /// below the accessibility text sizes (P11).
    private var groupsInTwoColumns: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
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
                .opacity(headshotOpacity)

            VStack(spacing: Theme.Spacing.s) {
                Text(player.name)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                subtitle
            }
            // The hero's own white or black, whichever reads on this
            // team's fill, for every team (P4, B-1); only the number
            // capsule takes the team's tint.
            .foregroundStyle(heroInk)
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
    /// at accessibility sizes, in the team's tint (`inkColor`, P4). An
    /// outline rather than a tinted fill, so the ink keeps its full
    /// contrast on the team colour.
    @ViewBuilder
    private var subtitle: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        layout {
            if !number.isEmpty {
                Text("#\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(inkColor)
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

    /// The headshot in a circle. Where no source has one (ESPN, then for
    /// soccer FotMob, API-Football, TheSportsDB and Wikimedia Commons —
    /// `AthleteHeadshot`), ESPN's grey silhouette; the app's own while it
    /// loads, or where ESPN's would not load. Long-press a fallback photo
    /// for its credit.
    private var headshot: some View {
        let size = min(headshotSize, 180)
        return AthleteHeadshot(player, league: team.league, team: team, showsProgress: false) {
            Image("blank")
                .resizable()
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .background(heroInk.opacity(0.15), in: Circle())
        .clipShape(.circle)
        .overlay {
            Circle()
                .strokeBorder(heroInk.opacity(0.35), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    /// The headshot again, small, at the head of the compact bar.
    private var compactHeadshot: some View {
        AthleteHeadshot(player, league: team.league, team: team, showsProgress: false) {
            Image("blank")
                .resizable()
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 28, height: 28)
        .background(heroInk.opacity(0.15), in: Circle())
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    /// The player's name, pinned under the sheet's top edge once the header
    /// has scrolled away. VoiceOver reads the header instead.
    private var compactBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            compactHeadshot

            Text(player.name)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(heroInk)
            if !number.isEmpty {
                Text("#\(number)")
                    .font(Theme.Typography.cardTitle.monospacedDigit())
                    .foregroundStyle(inkColor)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

            // No log to show for a season with no games yet: the stats
            // card already says so. A failed load may still have games.
            if !player.playerID.isEmpty && !(loaded && statistics.seasonState == .noFigures) {
                gameLogCard
            }

            if !facts.isEmpty {
                aboutCard
            }
        }
        // A column on an iPad's page sheet, where a row of stats ran
        // 1,300 pt wide (B-14): 640 pt in regular width (P11). A no-op on
        // an iPhone.
        .readableContentWidth(columnWidth)
        .padding(Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xl)
        // Tall enough to scroll the header fully away and to cover the
        // hero's overscroll, however short the page (P10).
        .frame(maxWidth: .infinity, minHeight: pageMinimumHeight, alignment: .top)
        .background(Theme.Surface.content, in: Theme.Radius.pageShape)
    }

    /// A card's heading: label ink on the card, the team's accent (F3) as
    /// a bar beside it, so it shows on a dark card too (P5, B-3).
    private func cardTitle(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            TeamAccentBar(color: accentColor)
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
            HStack(spacing: Theme.Spacing.s) {
                cardTitle("Season Stats")
                    .accessibilityIdentifier("playerDetail.section")

                // Whenever a season is known, even after a failed load
                // (P8).
                if !seasons.isEmpty {
                    Spacer(minLength: Theme.Spacing.s)
                    seasonPicker
                }
            }

            statisticsContent
                .motionAnimation(Theme.Motion.stateChange, value: loaded)
                .motionAnimation(Theme.Motion.stateChange, value: showsAllStats)
        }
    }

    /// The seasons the splits feed offers, newest first. Picking one
    /// reloads the season stats and the game log for it.
    private var seasonPicker: some View {
        Picker("Season", selection: $season) {
            ForEach(seasons) { option in
                Text(option.label)
                    .tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("playerDetail.season")
    }

    // MARK: Game log

    /// The season the game log is fetched for once the statistics have
    /// said which season they show: empty for the feed's current season,
    /// `nil` until then. It waits for its card to scroll into view, unless
    /// the season has no statistics, when the log may stand in for them
    /// (`logTotals`).
    private var gameLogRequest: String? {
        guard loaded, gameLogVisible || allCells.isEmpty else { return nil }
        return statisticsSeason == currentSeason ? "" : statisticsSeason
    }

    /// Whether `gameLog` is the answer to the current `gameLogRequest`,
    /// not still another season's.
    private var gameLogIsCurrent: Bool {
        gameLog.loaded && gameLogAnswers != nil && gameLogAnswers == gameLogRequest
    }

    /// How many games the log card lists.
    private static var gameLogLimit: Int { 5 }

    /// The `task` id the game log loads under: the season it asks for and
    /// the Retry count.
    private var gameLogTaskID: String {
        let request = gameLogRequest.map { "season:" + $0 } ?? "waiting"
        return request + "#" + String(gameLogAttempt)
    }

    /// The player's five most recent games in the season shown, fetched
    /// only once the card scrolls into view, under a title that counts the
    /// games it lists (P7).
    private var gameLogCard: some View {
        card {
            cardTitle(gameLogCardTitle(shown: gameLog.loaded ? min(gameLog.rows.count, Self.gameLogLimit) : nil))

            PlayerGameLogView(
                log: gameLog,
                limit: Self.gameLogLimit,
                accent: accentColor,
                league: team.league,
                onRetry: { gameLogAttempt += 1 }
            )
            .motionAnimation(Theme.Motion.stateChange, value: gameLog.loaded)
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible in
            if visible {
                gameLogVisible = true
            }
        }
        .task(id: gameLogTaskID) {
            await loadGameLog()
        }
    }

    private func loadGameLog() async {
        guard let request = gameLogRequest else { return }
        gameLog.loaded = false
        let log = await downloadGameLog(
            athlete: player.playerID,
            league: team.league,
            season: request.isEmpty ? nil : request
        )
        // A newer season has taken over.
        guard !Task.isCancelled else { return }
        gameLog = log
        gameLogAnswers = request
    }

    /// Every cell in the grid, in reading order.
    private var allCells: [PlayerSheetCell] {
        statistics.sections.flatMap(\.rows).flatMap { $0 }
    }

    /// The season summed from the game log, for a season the feed has no
    /// statistics for but has logged games in (`summedTotals`): an NFL
    /// receiver with no catches yet has no splits, only his games.
    private var logTotals: [PlayerSeasonStat] {
        gameLogIsCurrent ? gameLog.summedTotals : []
    }

    @ViewBuilder
    private var statisticsContent: some View {
        if loaded && statistics.seasonState == .loadFailed {
            // Not "No stats yet": the feed didn't answer (P8).
            loadFailedState
        } else if allCells.isEmpty {
            if !loaded {
                statisticsSkeleton
            } else if !logTotals.isEmpty {
                logTotalsBody
            } else if gameLogIsCurrent && !gameLog.rows.isEmpty {
                emptyMessage("Season totals aren't published yet. Recent games are below.")
            } else if !gameLogIsCurrent && !player.playerID.isEmpty {
                // The game log is on its way, and may hold the season.
                statisticsSkeleton
            } else {
                emptyMessage(statistics.message ?? "No season statistics are available for this player yet.")
            }
        } else if loaded {
            if statistics.seasonState == .noFigures {
                noFiguresState
            } else {
                statisticsBody
            }
        } else {
            // The placeholder line's layout, redacted, until the real one
            // lands (D-7).
            statisticsBody
                .loadingPlaceholder()
        }
    }

    /// The key statistics for the player's sport and position as tiles
    /// (`featuredStatistics`), then the rest of the line in titled groups
    /// of labelled rows, a rate with a bar in the team's accent. Zero rows,
    /// and groups of nothing but, wait behind "Show all stats" at the end
    /// (P2, `statGroups(excluding:)`).
    private var statisticsBody: some View {
        let featured = statistics.featuredCells(for: player.featuredStatistics)
        let wide = featured.filter { $0.feature.spansRow }.map { KeyStat($0) }
        let tiles = featured.filter { !$0.feature.spansRow }.map { KeyStat($0) }
        let groups = statistics.statGroups(excluding: featured)
        // The placeholder line, all zeros, keeps its full layout while the
        // real one loads.
        let sections = showsAllStats || !loaded ? groups.all : groups.shown
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if !wide.isEmpty || !tiles.isEmpty {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(wide.enumerated()), id: \.offset) { _, stat in
                        KeyStatTile(stat: stat)
                    }

                    if !tiles.isEmpty {
                        keyStatGrid(tiles)
                    }
                }
            }

            statSectionList(sections)

            if let message = statistics.message {
                emptyMessage(message)
            }

            if loaded && groups.hiddenCount > 0 {
                showAllStatsButton(hidden: groups.hiddenCount)
            }
        }
    }

    /// The stat groups one under another, or two across on an iPad
    /// (`groupsInTwoColumns`, P11).
    @ViewBuilder
    private func statSectionList(_ sections: [PlayerSheetGrid.Section]) -> some View {
        if groupsInTwoColumns && sections.count > 1 {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.l, alignment: .top),
                    count: 2
                ),
                alignment: .leading,
                spacing: Theme.Spacing.l
            ) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    statSection(section)
                }
            }
        } else {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                statSection(section)
            }
        }
    }

    /// Opens, and closes again, the rows "Show all stats" holds back: the
    /// zeros, and the groups of nothing but (P2).
    private func showAllStatsButton(hidden: Int) -> some View {
        Button {
            showsAllStats.toggle()
        } label: {
            Text(showsAllStats ? "Show fewer stats" : "Show all stats (\(hidden) more)")
                .font(Theme.Typography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityIdentifier("playerDetail.showAllStats")
    }

    /// The logged games summed (`logTotals`), under a line saying how many:
    /// the log's headline figures as tiles, any other count that isn't zero
    /// as a row.
    private var logTotalsBody: some View {
        let totals = logTotals
        let headline = Set(gameLog.headlineColumns.map(\.id))
        let tiles = Array(totals.filter { headline.contains($0.id) }.prefix(4))
        let tileIDs = Set(tiles.map(\.id))
        let rows = totals
            .filter { !tileIDs.contains($0.id) }
            .map { PlayerSheetCell.stat(title: $0.label, info: $0.display) }
            .filter { !$0.isEmptyFigure }
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Label(gameLogTotalsCaption(games: gameLog.rows.count), systemImage: "sum")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.metadata)

            if !tiles.isEmpty {
                keyStatGrid(tiles.map { stat in
                    KeyStat(
                        label: stat.abbreviation,
                        spokenTitle: stat.label,
                        cell: .stat(title: stat.label, info: stat.display)
                    )
                })
            }

            if !rows.isEmpty {
                statSection(PlayerSheetGrid.Section(title: nil, rows: [rows]))
            }
        }
    }

    /// Key-stat tiles in as many columns as fit at `featureMinimumWidth`,
    /// no more than there are tiles, and without a lone tile on a row of
    /// its own (`PlayerSheetGrid.columnCount`). Adaptive until measured.
    private func keyStatGrid(_ stats: [KeyStat]) -> some View {
        LazyVGrid(columns: tileColumns(count: stats.count), spacing: Theme.Spacing.s) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                KeyStatTile(stat: stat)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            tileWidth = width
        }
    }

    private func tileColumns(count: Int) -> [GridItem] {
        let spacing = Theme.Spacing.s
        guard tileWidth > 0, count > 0 else {
            return [GridItem(.adaptive(minimum: featureMinimumWidth), spacing: spacing, alignment: .top)]
        }
        let fitting = Int((tileWidth + spacing) / (featureMinimumWidth + spacing))
        let columns = min(count, PlayerSheetGrid.columnCount(fitting: fitting, cells: count))
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: max(columns, 1))
    }

    /// A group of the line under its title: each statistic a row on the
    /// inset surface, its figure trailing.
    private func statSection(_ section: PlayerSheetGrid.Section) -> some View {
        let cells = Array(section.rows.joined())
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let title = section.title {
                Text(title)
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.metadata)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    if index > 0 {
                        Divider()
                    }
                    StatRow(cell: cell, accent: accentColor)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        }
    }

    /// The season before the one shown, if the picker offers one: seasons
    /// run newest first.
    private var earlierSeason: AthleteSeason? {
        guard let index = seasons.firstIndex(where: { $0.value == statisticsSeason }),
              index + 1 < seasons.count
        else { return nil }
        return seasons[index + 1]
    }

    /// A season the player has no figures in (`hasNoFigures`), as a
    /// college line reads before tip-off or an injured pitcher's all year:
    /// one short line in place of a grid of zeros, and for the current
    /// season a way to the one before. The season picker above stays.
    private var noFiguresState: some View {
        let current = statisticsSeason == currentSeason
        let title: String = current ? "No stats yet this season" : "No stats for this season"
        let detail: String = current
            ? "Nothing has been recorded for this player so far this season."
            : "Nothing was recorded for this player that season."
        let earlier = current ? earlierSeason : nil
        return VStack(spacing: Theme.Spacing.m) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.bottom, Theme.Spacing.xs)

                Text(title)
                    .font(Theme.Typography.cardTitle)

                Text(detail)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.metadata)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("playerDetail.noStats")

            if let earlier {
                Button {
                    season = earlier.value
                } label: {
                    Text("Show \(earlier.label) Season")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("playerDetail.earlierSeason")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
    }

    /// A season whose statistics didn't load: the fetch failed, or the feed
    /// answered without its season list (P8). Says so, with a Retry that
    /// fetches the season again (and the game log, if that failed too), and
    /// keeps the way to the season before. The season picker above stays
    /// whenever a season is known.
    private var loadFailedState: some View {
        let earlier = earlierSeason
        return VStack(spacing: Theme.Spacing.m) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.bottom, Theme.Spacing.xs)

                Text("Couldn't load this season's stats")
                    .font(Theme.Typography.cardTitle)

                Text("ESPN didn't send them just now. Check your connection, then try again.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.metadata)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("playerDetail.loadFailed")

            Button {
                statisticsAttempt += 1
                if gameLog.loadFailed {
                    gameLogAttempt += 1
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("playerDetail.retry")

            if let earlier {
                Button {
                    season = earlier.value
                } label: {
                    Text("Show \(earlier.label) Season")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("playerDetail.earlierSeason")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
    }

    /// Stand-in key-stat tiles while a line with nothing to lay out yet
    /// (football's, soccer's without roster totals) loads.
    private var statisticsSkeleton: some View {
        keyStatGrid(Array(
            repeating: KeyStat(label: "STAT", spokenTitle: "Statistic", cell: .stat(title: "Statistic", info: "00.0")),
            count: 4
        ))
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

    // MARK: About

    /// The biography facts with something in them, less "N/A"s and
    /// Position (`aboutFacts`). With none left the About card is hidden.
    private var facts: [(title: String, info: String)] {
        player.about.aboutFacts
    }

    /// The facts as tiles, each with its symbol: two across at the default
    /// text size, one at the largest.
    private var aboutCard: some View {
        card {
            cardTitle("About")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: factMinimumWidth), spacing: Theme.Spacing.s, alignment: .top)],
                alignment: .leading,
                spacing: Theme.Spacing.s
            ) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    FactTile(title: fact.title, value: fact.info)
                }
            }
        }
    }
}

// MARK: - Cells

/// What a key-stat tile shows: its short label ("Goals", "PPG"), what
/// VoiceOver calls it, and the cell its figure comes from.
private struct KeyStat {
    var label: String
    var spokenTitle: String
    var cell: PlayerSheetCell
}

extension KeyStat {
    init(_ featured: PlayerSheetFeaturedCell) {
        self.init(label: featured.feature.abbreviation, spokenTitle: featured.spokenTitle, cell: featured.cell)
    }
}

/// A key statistic: a large figure over its short label on the inset
/// surface, without the accent dash it once had (P5): the section's bar
/// carries the team. VoiceOver reads it as one element, "Goals, 7".
private struct KeyStatTile: View {
    let stat: KeyStat

    var body: some View {
        let value = stat.cell.displayValue
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                .lineLimit(1)
                // No further: half size read as a different figure from its
                // neighbours. A hockey "17:15" still fits four across on a
                // 375 pt phone at 0.7.
                .minimumScaleFactor(0.7)

            Text(stat.label)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(Theme.Palette.metadata)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs / 2)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stat.spokenTitle))
        .accessibilityValue(Text(value))
    }
}

/// A season statistic as a row: its label leading, the figure trailing in
/// tabular digits, a rate's bar in the team's accent beneath (only over
/// enough attempts, P3), a card beside a booking. Stacked at
/// accessibility sizes so neither truncates; VoiceOver reads label and
/// figure as one element.
private struct StatRow: View {
    let cell: PlayerSheetCell
    let accent: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let value = cell.displayValue
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.m))
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            layout {
                HStack(spacing: Theme.Spacing.s) {
                    if let glyph = cell.glyph {
                        BookingCardGlyph(glyph: glyph)
                    }
                    Text(cell.title)
                }
                if !stacked {
                    Spacer(minLength: Theme.Spacing.m)
                }
                Text(value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .multilineTextAlignment(stacked ? .leading : .trailing)
            }

            if let fraction = cell.barFraction {
                StatPercentageView(fraction: fraction, color: accent)
            }
        }
        .font(Theme.Typography.body)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cell.title))
        .accessibilityValue(Text(value))
    }
}

/// A referee's card beside a booking row: yellow or red. Decorative: the
/// row's label says which.
private struct BookingCardGlyph: View {
    let glyph: PlayerStatGlyph

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(glyph == .yellowCard ? Color.yellow : Color.red)
            .frame(width: height * 0.72, height: height)
            .rotationEffect(.degrees(8))
            .accessibilityHidden(true)
    }
}

/// A biography fact as a tile: its symbol, the label over the value, and a
/// nationality's flag where the country maps to one (`countryFlag`).
/// VoiceOver reads label and value, without the flag, as one element.
private struct FactTile: View {
    let title: String
    let value: String

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    /// The value as shown: a nationality led by its flag.
    private var shownValue: String {
        guard title == "Citizenship" || title == "Birth Country",
              let flag = countryFlag(value)
        else { return value }
        return "\(flag) \(value)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: playerFactSymbol(title))
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.metadata)
                Text(shownValue)
                    .font(Theme.Typography.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}
