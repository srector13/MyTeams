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

    /// The grid's sections less the `featured` cells, less any quiet cell
    /// with nothing in it (`hidesWhenEmpty`: no one needs "Own Goals 0"),
    /// and less any section those leave empty.
    func remainingSections(excluding featured: [PlayerSheetFeaturedCell]) -> [Section] {
        var lifted = Set(featured.map { Self.cellKey(section: $0.section, title: $0.cell.title) })
        var remaining: [Section] = []
        for (index, section) in sections.enumerated() {
            var rows: [[PlayerSheetCell]] = []
            for row in section.rows {
                var kept: [PlayerSheetCell] = []
                for cell in row {
                    if lifted.remove(Self.cellKey(section: index, title: cell.title)) != nil { continue }
                    if cell.hidesWhenEmpty && cell.isEmptyFigure { continue }
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

/// A small mark drawn beside a stat row's label.
enum PlayerStatGlyph: Sendable {
    case yellowCard
    case redCard
}

extension PlayerSheetCell {
    /// Titles of stats that say little at zero, shown only once they don't.
    static let quietTitles: Set<String> = ["Own Goals", "Offsides"]

    /// Whether the cell is left out while it's zero or missing.
    var hidesWhenEmpty: Bool { Self.quietTitles.contains(title) }

    /// The card a soccer discipline row is drawn with.
    var glyph: PlayerStatGlyph? {
        switch title {
        case "Yellow Cards": return .yellowCard
        case "Red Cards": return .redCard
        default: return nil
        }
    }

    /// The figure as a tile or row shows it: the feed's text, "N/A" for
    /// none, a rate as a whole percentage.
    var displayValue: String {
        switch self {
        case .fact(_, let info), .stat(_, let info):
            return info.isEmpty ? "N/A" : info
        case .percentage(_, let progress):
            return progress.isFinite
                ? progress.formatted(.percent.precision(.fractionLength(0)))
                : "N/A"
        }
    }

    /// A rate's share of its bar, clamped to 0–1; `nil` for a figure that
    /// isn't a rate or a rate over no attempts.
    var barFraction: Double? {
        guard case .percentage(_, let progress) = self, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }
}

// MARK: - Positions

/// Whether a soccer position is the goalkeeper's: ESPN's "Goalkeeper", in
/// any case.
func isSoccerGoalkeeper(_ position: String) -> Bool {
    position.lowercased().contains("goalkeeper")
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
    /// short labels, then the rest in the log's order. A column no game
    /// gives a number for ("-") is left out; a figure with a fraction (half
    /// a sack) keeps one place.
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
            totals.append(PlayerSeasonStat(
                id: column.id,
                label: column.displayName,
                abbreviation: column.label,
                display: whole ? String(Int(total)) : String(format: "%.1f", total)
            ))
        }
        return totals
    }
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
