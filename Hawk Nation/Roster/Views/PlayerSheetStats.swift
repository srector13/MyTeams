//
//  PlayerSheetStats.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// The player sheet's pure logic: which statistics lead the Season Stats
// card, the rates worked out from a line's totals, a season summed from
// the game log, and the About card's symbols and flags. Free functions and
// plain types only, so the tests can call them off the main actor.

// MARK: - Key statistics

/// A headline statistic lifted out of a sheet's grid: the feature that
/// asked for it, the cell it found, and the section that cell was in.
struct PlayerSheetFeaturedCell: Sendable {
    var feature: PlayerSheetFeature
    var cell: PlayerSheetCell
    /// The cell's section, as an index into `PlayerSheetGrid.sections`.
    var section: Int

    /// What VoiceOver calls the tile: the feature's spoken title ("Goals"),
    /// else the cell's own ("Total Goals").
    var spokenTitle: String { feature.spokenTitle ?? cell.title }
}

extension PlayerSheetGrid {
    /// The cells `features` name, in their order: `tiles` at most, plus any
    /// that span a row. A feature is looked for in its `section` when it
    /// names one (football's "Yards" is in Passing, Rushing and Receiving),
    /// else in every section; one the grid lacks is skipped, so one list
    /// can serve two stat lines. No cell is picked twice.
    func featuredCells(for features: [PlayerSheetFeature], tiles limit: Int = 4) -> [PlayerSheetFeaturedCell] {
        var used: Set<String> = []
        var tiles = 0
        var featured: [PlayerSheetFeaturedCell] = []
        for feature in features where feature.spansRow || tiles < limit {
            guard let match = firstCell(titled: feature.title, inSection: feature.section, skipping: used) else { continue }
            used.insert(Self.cellKey(section: match.section, title: feature.title))
            featured.append(PlayerSheetFeaturedCell(feature: feature, cell: match.cell, section: match.section))
            if !feature.spansRow {
                tiles += 1
            }
        }
        return featured
    }

    /// The grid's sections less the `featured` cells, and less any section
    /// that leaves empty. Zero rows stay: `statGroups(excluding:)` decides
    /// which of these show at first.
    func remainingSections(excluding featured: [PlayerSheetFeaturedCell]) -> [Section] {
        var lifted = Set(featured.map { Self.cellKey(section: $0.section, title: $0.cell.title) })
        var remaining: [Section] = []
        for (index, section) in sections.enumerated() {
            var rows: [[PlayerSheetCell]] = []
            for row in section.rows {
                var kept: [PlayerSheetCell] = []
                for cell in row {
                    if lifted.remove(Self.cellKey(section: index, title: cell.title)) != nil { continue }
                    kept.append(cell)
                }
                if !kept.isEmpty {
                    rows.append(kept)
                }
            }
            if !rows.isEmpty {
                remaining.append(Section(title: section.title, rows: rows))
            }
        }
        return remaining
    }

    /// The groups under the tiles (`remainingSections(excluding:)`), split
    /// for "Show all stats" (P2): at first a group shows only its figures
    /// that aren't zero or missing ("Own Goals 0", a reliever's "Wins 0"),
    /// and a group with none of those doesn't show at all; the rest wait
    /// behind the button. A grid that is all zeros never gets here: the
    /// sheet says it has no figures (`hasNoFigures`).
    func statGroups(excluding featured: [PlayerSheetFeaturedCell]) -> PlayerSheetStatGroups {
        let all = remainingSections(excluding: featured)
        var shown: [Section] = []
        for section in all {
            let rows = section.rows
                .map { row in row.filter { !$0.isEmptyFigure } }
                .filter { !$0.isEmpty }
            if !rows.isEmpty {
                shown.append(Section(title: section.title, rows: rows))
            }
        }
        return PlayerSheetStatGroups(shown: shown, all: all)
    }

    /// What the Season Stats card shows for the grid once it has loaded
    /// (P8): a fetch that failed, or answered without its season list, is
    /// not a season with nothing in it.
    var seasonState: PlayerSheetSeasonState {
        if loadFailed { return .loadFailed }
        if hasNoFigures { return .noFigures }
        return .figures
    }

    /// The first cell titled `title`, in the section titled `sectionTitle`
    /// or, for `nil`, in any, that `used` doesn't hold.
    private func firstCell(
        titled title: String,
        inSection sectionTitle: String?,
        skipping used: Set<String>
    ) -> (section: Int, cell: PlayerSheetCell)? {
        for (index, section) in sections.enumerated() {
            if let sectionTitle, section.title != sectionTitle { continue }
            guard !used.contains(Self.cellKey(section: index, title: title)) else { continue }
            for cell in section.rows.joined() where cell.title == title {
                return (index, cell)
            }
        }
        return nil
    }

    private static func cellKey(section: Int, title: String) -> String {
        "\(section)|\(title)"
    }
}

/// The Season Stats card's groups: those shown at first, every one for
/// "Show all stats", and how many rows the button would add.
struct PlayerSheetStatGroups: Sendable {
    var shown: [PlayerSheetGrid.Section]
    var all: [PlayerSheetGrid.Section]

    /// The rows in `all` that `shown` leaves out: the button's "(5 more)".
    var hiddenCount: Int {
        func count(_ sections: [PlayerSheetGrid.Section]) -> Int {
            sections.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.count } }
        }
        return count(all) - count(shown)
    }
}

/// What a loaded Season Stats card says: its figures, that the season has
/// none yet, or that they couldn't be loaded, with a Retry (P8).
enum PlayerSheetSeasonState: Sendable, Equatable {
    case figures
    case noFigures
    case loadFailed
}

/// A small mark drawn beside a stat row's label.
enum PlayerStatGlyph: Sendable {
    case yellowCard
    case redCard
}

extension PlayerSheetCell {
    /// The fewest attempts a rate is drawn as a bar over (P3): one shot on
    /// target from two is "1 of 2", not a half-full bar.
    static let minimumBarAttempts = 5

    /// Whether a rate's attempts, where the feed gives them, are too few
    /// for a bar.
    private var hasFewAttempts: Bool {
        guard case .percentage(_, _, let given) = self, let attempts = given else { return false }
        return attempts.attempted < Self.minimumBarAttempts
    }

    /// The card a soccer discipline row is drawn with.
    var glyph: PlayerStatGlyph? {
        switch title {
        case "Yellow Cards": return .yellowCard
        case "Red Cards": return .redCard
        default: return nil
        }
    }

    /// The figure as a tile or row shows it: the feed's text, "N/A" for
    /// none, a rate as a whole percentage, or over fewer than
    /// `minimumBarAttempts` as its makes of its attempts ("0 of 3").
    var displayValue: String {
        switch self {
        case .fact(_, let info), .stat(_, let info):
            return info.isEmpty ? "N/A" : info
        case .percentage(_, let progress, let attempts):
            guard progress.isFinite else { return "N/A" }
            if let attempts, attempts.attempted > 0, hasFewAttempts {
                return "\(attempts.made) of \(attempts.attempted)"
            }
            return progress.formatted(.percent.precision(.fractionLength(0)))
        }
    }

    /// A rate's share of its bar, clamped to 0–1; `nil` for a figure that
    /// isn't a rate, a rate over no attempts, or one over fewer than
    /// `minimumBarAttempts` (P3).
    var barFraction: Double? {
        guard case .percentage(_, let progress, _) = self, progress.isFinite, !hasFewAttempts else { return nil }
        return min(max(progress, 0), 1)
    }
}

// MARK: - Positions

/// Whether a soccer position is the goalkeeper's: ESPN's "Goalkeeper", in
/// any case.
func isSoccerGoalkeeper(_ position: String) -> Bool {
    position.lowercased().contains("goalkeeper")
}

/// The four lines of a soccer team, which decide a sheet's tiles and the
/// order of its groups (P1).
enum SoccerRole: Sendable, Equatable {
    case goalkeeper
    case defender
    case midfielder
    case forward

    /// ESPN's "Goalkeeper", "Defender", "Midfielder" and "Forward", and
    /// the finer names some feeds use ("Center Back", "Attacking
    /// Midfielder", "Striker"). Anything else reads as a forward, whose
    /// goals-first line was every outfield player's before.
    init(position: String) {
        let lowered = position.lowercased()
        if lowered.contains("goalkeeper") || lowered.contains("keeper") {
            self = .goalkeeper
        } else if lowered.contains("midfield") {
            self = .midfielder
        } else if lowered.contains("defender") || lowered.contains("back") || lowered.contains("defen") {
            self = .defender
        } else {
            self = .forward
        }
    }
}

/// A soccer player's tiles by their line (P1), by the feeds' stat names
/// (`PlayerStatWording.soccer`): a keeper's saves, clean sheets, goals
/// conceded and save percentage; a defender's appearances, starts, goals
/// conceded while on the pitch and fouls; a midfielder's appearances,
/// starts, assists and fouls won; a forward's goals, assists, shots on
/// target and appearances. Each list runs on with stand-ins, for the
/// athlete document's shorter line (no fouls, no clean sheets in the
/// roster's): a name the grid lacks is skipped, and four are shown.
/// ESPN's feeds carry no tackles, interceptions or clearances.
func soccerKeyStats(role: SoccerRole) -> [PlayerSheetFeature] {
    let names: [String]
    switch role {
    case .goalkeeper:
        names = ["saves", "cleanSheet", "goalsConceded", "savePct", "appearances", "starts"]
    case .defender:
        names = ["appearances", "starts", "goalsConcededOnPitch", "foulsCommitted",
                 "totalGoals", "goalAssists", "subIns", "totalShots"]
    case .midfielder:
        names = ["appearances", "starts", "goalAssists", "foulsSuffered",
                 "totalGoals", "subIns", "totalShots"]
    case .forward:
        names = ["totalGoals", "goalAssists", "shotsOnTarget", "appearances",
                 "starts", "totalShots"]
    }
    return names.map { PlayerStatWording.soccer($0).feature }
}

/// Whether a baseball position is a reliever's: ESPN's "Relief Pitcher".
func isReliefPitcher(_ position: String) -> Bool {
    let lowered = position.lowercased()
    return lowered.contains("relief") || lowered.contains("reliever") || lowered.contains("closer")
}

/// A pitcher's tiles: a starter's ERA, win-loss record, strikeouts and
/// WHIP; a reliever's ERA, innings, strikeouts and WHIP (P9), as a
/// reliever's record is mostly "0-0".
func baseballPitcherKeyStats(position: String) -> [PlayerSheetFeature] {
    let names = isReliefPitcher(position)
        ? ["ERA", "innings", "strikeouts", "WHIP"]
        : ["ERA", "winLoss", "strikeouts", "WHIP"]
    return names.map { PlayerStatWording.pitching($0).feature }
}

/// An NFL player's headline statistics by position group: a passer's
/// yards, touchdowns, interceptions and rating; a runner's yards,
/// touchdowns and yards a carry; a receiver's catches, yards, touchdowns
/// and targets; a kicker's, a punter's, or a defender's line. Each is
/// looked for in its own group (`FootballStatGroup.title`), and the other
/// groups follow, so a line the position doesn't explain still leads with
/// something.
func footballKeyStats(position: String) -> [PlayerSheetFeature] {
    let passing = [
        PlayerSheetFeature("Yards", "Pass Yds", in: "Passing", spoken: "Passing yards"),
        PlayerSheetFeature("Touchdowns", "Pass TD", in: "Passing", spoken: "Passing touchdowns"),
        PlayerSheetFeature("Interceptions", "INT", in: "Passing", spoken: "Interceptions thrown"),
        PlayerSheetFeature("Rating", "Rating", in: "Passing", spoken: "Passer rating"),
    ]
    let rushing = [
        PlayerSheetFeature("Yards", "Rush Yds", in: "Rushing", spoken: "Rushing yards"),
        PlayerSheetFeature("Touchdowns", "Rush TD", in: "Rushing", spoken: "Rushing touchdowns"),
        PlayerSheetFeature("Avg / Carry", "YPC", in: "Rushing", spoken: "Yards per carry"),
    ]
    let receiving = [
        PlayerSheetFeature("Receptions", "Rec", in: "Receiving", spoken: "Receptions"),
        PlayerSheetFeature("Yards", "Rec Yds", in: "Receiving", spoken: "Receiving yards"),
        PlayerSheetFeature("Touchdowns", "Rec TD", in: "Receiving", spoken: "Receiving touchdowns"),
        PlayerSheetFeature("Targets", "Targets", in: "Receiving", spoken: "Targets"),
    ]
    let defense = [
        PlayerSheetFeature("Tackles", "Tackles", in: "Defense", spoken: "Tackles"),
        PlayerSheetFeature("Sacks", "Sacks", in: "Defense", spoken: "Sacks"),
        PlayerSheetFeature("Interceptions", "INT", in: "Defense", spoken: "Interceptions"),
        PlayerSheetFeature("Passes Defended", "PD", in: "Defense", spoken: "Passes defended"),
        PlayerSheetFeature("Forced Fumbles", "FF", in: "Defense", spoken: "Forced fumbles"),
    ]
    let kicking = [
        PlayerSheetFeature("Field Goals", "FG", in: "Kicking", spoken: "Field goals"),
        PlayerSheetFeature("Field Goal %", "FG%", in: "Kicking", spoken: "Field goal percentage"),
        PlayerSheetFeature("Long Field Goal", "Long", in: "Kicking", spoken: "Longest field goal"),
        PlayerSheetFeature("Points", "Pts", in: "Kicking", spoken: "Points"),
    ]
    let punting = [
        PlayerSheetFeature("Punts", "Punts", in: "Punting", spoken: "Punts"),
        PlayerSheetFeature("Gross Avg", "Avg", in: "Punting", spoken: "Gross average"),
        PlayerSheetFeature("Inside 20", "In 20", in: "Punting", spoken: "Punts inside the 20"),
        PlayerSheetFeature("Long", "Long", in: "Punting", spoken: "Longest punt"),
    ]

    let lowered = position.lowercased()
    let lead: [[PlayerSheetFeature]]
    if lowered.contains("quarterback") {
        lead = [passing, rushing]
    } else if lowered.contains("running back") || lowered.contains("fullback") {
        lead = [rushing, receiving]
    } else if lowered.contains("receiver") || lowered.contains("tight end") {
        lead = [receiving, rushing]
    } else if lowered.contains("kicker") {
        lead = [kicking]
    } else if lowered.contains("punter") {
        lead = [punting]
    } else {
        lead = [defense]
    }
    return (lead + [passing, rushing, receiving, defense, kicking, punting]).flatMap { $0 }
}

// MARK: - Wording

/// What one statistic is called on the player sheet, so a figure reads the
/// same on its tile, its row and its game-log chip (P7): its row's title,
/// its tile's short label, its chip's abbreviation, and what VoiceOver
/// calls its tile. Looked up by the feeds' stat names, one table a sport.
struct PlayerStatWording: Sendable {
    var title: String
    var short: String
    var abbreviation: String
    var spoken: String

    init(_ title: String, short: String, abbreviation: String, spoken: String) {
        self.title = title
        self.short = short
        self.abbreviation = abbreviation
        self.spoken = spoken
    }

    /// The tile that lifts this statistic out of the grid.
    var feature: PlayerSheetFeature {
        PlayerSheetFeature(title, short, spoken: spoken)
    }

    /// A row with this statistic's figure.
    func stat(_ info: String) -> PlayerSheetCell {
        .stat(title: title, info: info)
    }

    /// The wording for a soccer statistic, by the roster's and athlete
    /// document's names; the name itself for one the table lacks.
    static func soccer(_ name: String) -> PlayerStatWording {
        soccerTable[name] ?? PlayerStatWording(name, short: name, abbreviation: name, spoken: name)
    }

    /// The soccer wording for a feed name the table knows, else `nil`: for
    /// a game-log column, which may be any sport's.
    static func knownSoccer(_ name: String) -> PlayerStatWording? {
        soccerTable[name]
    }

    /// The wording for a pitching statistic, by the MLB splits' names.
    static func pitching(_ name: String) -> PlayerStatWording {
        pitchingTable[name] ?? PlayerStatWording(name, short: name, abbreviation: name, spoken: name)
    }

    /// Soccer, by the feeds' names. `goalsConcededOnPitch` is the roster's
    /// `goalsConceded` for an outfield player: the goals let in while they
    /// were on the pitch. The rates are the sheet's own.
    private static let soccerTable: [String: PlayerStatWording] = [
        "appearances": .init("Games Played", short: "Apps", abbreviation: "GP", spoken: "Appearances"),
        "starts": .init("Games Started", short: "Starts", abbreviation: "GS", spoken: "Starts"),
        "subIns": .init("Off the Bench", short: "Off Bench", abbreviation: "SUB", spoken: "Substitute appearances"),
        "totalGoals": .init("Goals", short: "Goals", abbreviation: "G", spoken: "Goals"),
        "goalAssists": .init("Assists", short: "Assists", abbreviation: "A", spoken: "Assists"),
        "totalShots": .init("Shots", short: "Shots", abbreviation: "SH", spoken: "Shots"),
        "shotsOnTarget": .init("On Target", short: "On Target", abbreviation: "SOT", spoken: "Shots on target"),
        "shotAccuracy": .init("Shot Accuracy", short: "Accuracy", abbreviation: "SH%", spoken: "Shot accuracy"),
        "conversionRate": .init("Conversion Rate", short: "Conversion", abbreviation: "CONV", spoken: "Conversion rate"),
        "goalsPerGame": .init("Goals per Game", short: "Goals/Game", abbreviation: "G/GM", spoken: "Goals per game"),
        "shotsPerGame": .init("Shots per Game", short: "Shots/Game", abbreviation: "SH/GM", spoken: "Shots per game"),
        "offsides": .init("Offsides", short: "Offsides", abbreviation: "OFF", spoken: "Offsides"),
        "foulsCommitted": .init("Fouls Committed", short: "Fouls", abbreviation: "FC", spoken: "Fouls committed"),
        "foulsSuffered": .init("Fouls Won", short: "Fouls Won", abbreviation: "FW", spoken: "Fouls won"),
        "yellowCards": .init("Yellow Cards", short: "Yellows", abbreviation: "YC", spoken: "Yellow cards"),
        "redCards": .init("Red Cards", short: "Reds", abbreviation: "RC", spoken: "Red cards"),
        "ownGoals": .init("Own Goals", short: "Own Goals", abbreviation: "OG", spoken: "Own goals"),
        "saves": .init("Saves", short: "Saves", abbreviation: "SV", spoken: "Saves"),
        "cleanSheet": .init("Clean Sheets", short: "Clean Sheets", abbreviation: "CS", spoken: "Clean sheets"),
        "goalsConceded": .init("Goals Conceded", short: "Conceded", abbreviation: "GA", spoken: "Goals conceded"),
        "goalsConcededOnPitch": .init(
            "Conceded on Pitch", short: "Conceded", abbreviation: "GA",
            spoken: "Goals conceded while on the pitch"
        ),
        "shotsFaced": .init("Shots Faced", short: "Shots Faced", abbreviation: "SF", spoken: "Shots faced"),
        "savePct": .init("Save Percentage", short: "Save %", abbreviation: "SV%", spoken: "Save percentage"),
        "savesPerGame": .init("Saves per Game", short: "Saves/Game", abbreviation: "SV/GM", spoken: "Saves per game"),
        "concededPerGame": .init(
            "Conceded per Game", short: "Conceded/Game", abbreviation: "GA/GM", spoken: "Goals conceded per game"
        ),
    ]

    /// Pitching, by the MLB splits' names (ERA W L SV SVOP GP GS CG IP H R
    /// ER HR BB K OBA); `winLoss` and `WHIP` are the sheet's own.
    private static let pitchingTable: [String: PlayerStatWording] = [
        "ERA": .init("Earned Run Avg.", short: "ERA", abbreviation: "ERA", spoken: "Earned run average"),
        "winLoss": .init("Win-Loss Record", short: "W-L", abbreviation: "W-L", spoken: "Win-loss record"),
        "WHIP": .init("WHIP", short: "WHIP", abbreviation: "WHIP", spoken: "Walks and hits per inning pitched"),
        "innings": .init("Innings Pitched", short: "IP", abbreviation: "IP", spoken: "Innings pitched"),
        "strikeouts": .init("Strikeouts", short: "K", abbreviation: "K", spoken: "Strikeouts"),
        "gamesPlayed": .init("Games Played", short: "Games", abbreviation: "GP", spoken: "Games pitched"),
        "gamesStarted": .init("Games Started", short: "Starts", abbreviation: "GS", spoken: "Games started"),
        "completeGames": .init("Complete Games", short: "CG", abbreviation: "CG", spoken: "Complete games"),
        "wins": .init("Wins", short: "W", abbreviation: "W", spoken: "Wins"),
        "losses": .init("Losses", short: "L", abbreviation: "L", spoken: "Losses"),
        "saves": .init("Saves", short: "SV", abbreviation: "SV", spoken: "Saves"),
        "saveOpportunities": .init("Save Opportunities", short: "SVOP", abbreviation: "SVOP", spoken: "Save opportunities"),
        "hits": .init("Hits Allowed", short: "H", abbreviation: "H", spoken: "Hits allowed"),
        "runs": .init("Runs Allowed", short: "R", abbreviation: "R", spoken: "Runs allowed"),
        "earnedRuns": .init("Earned Runs", short: "ER", abbreviation: "ER", spoken: "Earned runs"),
        "homeRuns": .init("Home Runs Allowed", short: "HR", abbreviation: "HR", spoken: "Home runs allowed"),
        "walks": .init("Walks", short: "BB", abbreviation: "BB", spoken: "Walks"),
        "opponentAvg": .init("Opponent Avg.", short: "OBA", abbreviation: "OBA", spoken: "Opponents' batting average"),
    ]
}

// MARK: - Rates

/// `total` a game over `games`, to two places ("0.88"); "N/A" without a
/// game. The soccer feeds carry no minutes played, so the sheet's rates
/// are per game rather than per 90.
func perGameRate(_ total: Int, games: Int) -> String {
    guard games > 0 else { return "N/A" }
    return String(format: "%.2f", Double(total) / Double(games))
}

/// A baseball rate as a box score prints it: ".281", losing the leading
/// zero under one; "1.000" keeps it.
func baseballRate(_ rate: Float) -> String {
    let text = String(format: "%.3f", rate)
    return text.hasPrefix("0.") ? String(text.dropFirst()) : text
}

/// Innings as the feed writes them, `76.1` for 76⅓ (the digit after the
/// point is outs), as a number of innings.
func baseballInnings(_ innings: Float) -> Double {
    let value = Double(innings)
    guard value > 0 else { return 0 }
    let whole = value.rounded(.down)
    let outs = min(((value - whole) * 10).rounded(), 2)
    return whole + outs / 3
}

/// Walks plus hits per inning pitched, to two places ("1.26"); "N/A"
/// without an inning.
func baseballWHIP(walks: Int, hits: Int, innings: Float) -> String {
    let pitched = baseballInnings(innings)
    guard pitched > 0 else { return "N/A" }
    return String(format: "%.2f", Double(walks + hits) / pitched)
}

// MARK: - Totals from the game log

/// The game-log columns that are counts, by the feeds' `names`, so a
/// season's games add up to its total. Rates, averages, longs, minutes and
/// made-attempted pairs don't.
let gameLogCountingStats: Set<String> = [
    // Football.
    "completions", "passingAttempts", "passingYards", "passingTouchdowns", "interceptions",
    "rushingAttempts", "rushingYards", "rushingTouchdowns",
    "receptions", "receivingTargets", "receivingYards", "receivingTouchdowns",
    "fumbles", "fumblesLost", "fumblesForced", "fumblesRecovered", "kicksBlocked",
    "totalTackles", "soloTackles", "assistTackles", "sacks", "passesDefended",
    "totalKickingPoints", "punts", "puntYards",
    // Basketball.
    "points", "totalRebounds", "offensiveRebounds", "defensiveRebounds",
    "assists", "blocks", "steals", "fouls", "turnovers",
    // Baseball.
    "atBats", "runs", "hits", "doubles", "triples", "homeRuns", "RBIs", "walks",
    "hitByPitch", "strikeouts", "stolenBases", "caughtStealing", "earnedRuns",
    "wins", "losses", "saves",
    // Hockey.
    "goals", "plusMinus", "penaltyMinutes", "shotsTotal", "powerPlayGoals",
    "powerPlayAssists", "shortHandedGoals", "gameWinningGoals",
    "goalsAgainst", "shotsAgainst", "shutouts",
    // Soccer.
    "totalGoals", "goalAssists", "totalShots", "shotsOnTarget", "foulsCommitted",
    "foulsSuffered", "offsides", "yellowCards", "redCards",
]

extension AthleteGameLog {
    /// Season totals summed from every logged game, for a season whose
    /// splits the feed hasn't published: the counting columns
    /// (`gameLogCountingStats`) only, the headline ones first under their
    /// short labels, then the rest in the log's order. A soccer column is
    /// labelled as the roster's totals are (`PlayerStatWording.soccer`, P7).
    /// A column no game gives a number for ("-") is left out; a figure with
    /// a fraction (half a sack) keeps one place.
    var summedTotals: [PlayerSeasonStat] {
        guard !rows.isEmpty else { return [] }
        var ordered = headlineColumns
        var seen = Set(ordered.map(\.id))
        for column in columns where seen.insert(column.id).inserted {
            ordered.append(column)
        }

        var totals: [PlayerSeasonStat] = []
        for column in ordered where gameLogCountingStats.contains(column.id) {
            var total = 0.0
            var counted = false
            var whole = true
            for row in rows {
                guard let raw = row.stats[column.id],
                      let value = Double(raw.trimmingCharacters(in: .whitespaces))
                else { continue }
                total += value
                counted = true
                if value.rounded() != value {
                    whole = false
                }
            }
            guard counted else { continue }
            let wording = PlayerStatWording.knownSoccer(column.id)
            totals.append(PlayerSeasonStat(
                id: column.id,
                label: wording?.title ?? column.displayName,
                abbreviation: wording?.abbreviation ?? column.label,
                display: whole ? String(Int(total)) : String(format: "%.1f", total)
            ))
        }
        return totals
    }
}

/// The game-log card's title, counting the games it shows (P7): "Last 4
/// Games", "Last Game"; "Recent Games" while they load (`nil`) or when
/// there are none.
func gameLogCardTitle(shown games: Int?) -> String {
    guard let games, games > 0 else { return "Recent Games" }
    return games == 1 ? "Last Game" : "Last \(games) Games"
}

/// The line over totals summed from the game log: "From the last 4
/// games", "From the last game".
func gameLogTotalsCaption(games: Int) -> String {
    games == 1 ? "From the last game" : "From the last \(games) games"
}

/// Whether a game-log chip is a scoring figure worth picking out: a goal,
/// a touchdown or a home run, once there is one.
func gameLogEmphasizes(columnID: String, value: String) -> Bool {
    guard gameLogScoringStats.contains(columnID),
          let number = Double(value.trimmingCharacters(in: .whitespaces))
    else { return false }
    return number > 0
}

/// The game-log columns that are a player's scoring.
private let gameLogScoringStats: Set<String> = [
    "totalGoals", "goals", "passingTouchdowns", "rushingTouchdowns",
    "receivingTouchdowns", "homeRuns",
]

// MARK: - About

/// The SF Symbol beside an About fact, by the fact's title.
func playerFactSymbol(_ title: String) -> String {
    switch title {
    case "Age": return "calendar"
    case "Height": return "ruler"
    case "Weight": return "scalemass"
    case "Hometown": return "house"
    case "Birth Country": return "globe"
    case "Citizenship": return "flag"
    case "College", "Class": return "graduationcap"
    case "Debut Year": return "star"
    case "Status": return "checkmark.seal"
    case "Batting Hand": return "figure.baseball"
    case "Throwing Hand": return "baseball"
    case "Shoots": return "hockey.puck"
    default: return "info.circle"
    }
}

/// The flag emoji for a country as the feeds name it ("Brazil", "USA",
/// "England"), or `nil` where the name doesn't map cleanly to one
/// ("Northern Ireland", which has no emoji flag, or "N/A").
func countryFlag(_ country: String) -> String? {
    let name = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !name.isEmpty else { return nil }
    if let flag = subdivisionFlags[name] { return flag }
    guard let code = countryCodeAliases[name] ?? englishRegionCodes[name] else { return nil }
    return regionalIndicatorFlag(code)
}

/// A two-letter region code's flag: its letters as regional indicators.
/// `nil` for anything but two ASCII letters.
func regionalIndicatorFlag(_ code: String) -> String? {
    let letters = Array(code.uppercased().unicodeScalars)
    guard letters.count == 2 else { return nil }
    var flag = ""
    for letter in letters {
        guard letter.value >= 65, letter.value <= 90,
              let indicator = Unicode.Scalar(0x1F1E6 + letter.value - 65)
        else { return nil }
        flag.unicodeScalars.append(indicator)
    }
    return flag
}

/// The home nations with an emoji flag of their own (tag sequences).
private let subdivisionFlags: [String: String] = [
    "england": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
    "scotland": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
    "wales": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}",
]

/// Country names the feeds use that differ from the system's English
/// region names, lowercased.
private let countryCodeAliases: [String: String] = [
    "usa": "US",
    "united states of america": "US",
    "great britain": "GB",
    "korea republic": "KR",
    "republic of korea": "KR",
    "korea dpr": "KP",
    "ivory coast": "CI",
    "cote d'ivoire": "CI",
    "côte d'ivoire": "CI",
    "czech republic": "CZ",
    "republic of ireland": "IE",
    "dr congo": "CD",
    "congo dr": "CD",
    "democratic republic of the congo": "CD",
    "congo": "CG",
    "turkey": "TR",
    "türkiye": "TR",
    "bosnia and herzegovina": "BA",
    "bosnia-herzegovina": "BA",
    "trinidad and tobago": "TT",
    "antigua and barbuda": "AG",
    "st. kitts and nevis": "KN",
    "saint kitts and nevis": "KN",
    "st. lucia": "LC",
    "st. vincent and the grenadines": "VC",
    "cape verde": "CV",
    "cape verde islands": "CV",
    "curacao": "CW",
    "curaçao": "CW",
    "north macedonia": "MK",
    "macedonia": "MK",
    "kosovo": "XK",
    "the gambia": "GM",
    "gambia": "GM",
    "chinese taipei": "TW",
    "hong kong": "HK",
    "macau": "MO",
    "palestine": "PS",
    "sao tome and principe": "ST",
    "swaziland": "SZ",
    "east timor": "TL",
    "vatican city": "VA",
    "u.s. virgin islands": "VI",
    "british virgin islands": "VG",
    "turks and caicos islands": "TC",
]

/// Every ISO region's English name, lowercased, to its two-letter code:
/// "brazil" → "BR".
private let englishRegionCodes: [String: String] = {
    let english = Locale(identifier: "en_US")
    var codes: [String: String] = [:]
    for region in Locale.Region.isoRegions {
        let code = region.identifier
        guard code.count == 2, code.allSatisfy(\.isLetter),
              let name = english.localizedString(forRegionCode: code)
        else { continue }
        codes[name.lowercased()] = code
    }
    return codes
}()
