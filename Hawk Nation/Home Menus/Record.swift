//
//  Record.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// A team's record, in the shape its sport keeps it.
///
/// The schedule header used to be a bare `(wins, losses, draws)` triple,
/// drawn as two parts or three depending on whether any draws had happened.
/// That was right for basketball and baseball and roughly right for MLS, but
/// the leagues added in Phase 3 keep their records differently: hockey counts
/// overtime and shootout losses in a column of their own, and a soccer table
/// orders its columns wins, draws, losses and ranks by points. `Record` holds
/// every column any of them needs, and `format` says which ones to draw.
struct Record: Hashable, Sendable {
    /// Which columns a record shows, and in what order.
    enum Format: Hashable, Sendable {
        /// Wins and losses, with ties appended only when there are some:
        /// `"10-6"`, or an NFL season with a tie, `"10-6-1"`.
        case winLoss
        /// Wins, losses and ties, always three parts: a soccer schedule's
        /// `"4-1-0"`, read the way MLS has always shown it.
        case winLossTie
        /// Hockey: wins, regulation losses, then overtime and shootout
        /// losses, `"40-30-12"`.
        case winLossOvertimeLoss
        /// A soccer table's row: wins, draws, losses, then points,
        /// `"5-0-0, 15 pts"`.
        case winDrawLossPoints
    }

    var wins: Int
    /// Losses in regulation. Under `.winLossOvertimeLoss` the overtime and
    /// shootout losses are counted in `overtimeLosses` instead, not here.
    var losses: Int
    /// Ties, or draws: the same column under the name each sport gives it.
    var ties: Int = 0
    var overtimeLosses: Int = 0
    /// The league's points, where it ranks by them (soccer, hockey), else
    /// `nil`.
    var points: Int?
    var format: Format

    init(
        wins: Int,
        losses: Int,
        ties: Int = 0,
        overtimeLosses: Int = 0,
        points: Int? = nil,
        format: Format
    ) {
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.overtimeLosses = overtimeLosses
        self.points = points
        self.format = format
    }

    /// Every game the record counts.
    var gamesPlayed: Int { wins + losses + ties + overtimeLosses }

    /// The record as a header or table cell shows it; see `Format` for each
    /// shape.
    var summary: String {
        switch format {
        case .winLoss:
            ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
        case .winLossTie:
            "\(wins)-\(losses)-\(ties)"
        case .winLossOvertimeLoss:
            "\(wins)-\(losses)-\(overtimeLosses)"
        case .winDrawLossPoints:
            if let pointsLabel {
                "\(wins)-\(ties)-\(losses), \(pointsLabel)"
            } else {
                "\(wins)-\(ties)-\(losses)"
            }
        }
    }

    /// `"15 pts"`, `"1 pt"`, or `nil` when the league keeps no points.
    var pointsLabel: String? {
        points.map { $0 == 1 ? "1 pt" : "\($0) pts" }
    }
}

extension SportKind {
    /// How a team's own schedule adds up into its record in the header.
    ///
    /// Soccer always shows its draws column, even at zero, so a 4–1 start
    /// does not read like a basketball record. Hockey splits overtime losses
    /// out, as the league's own tables do.
    var scheduleRecordFormat: Record.Format {
        switch self {
        case .soccer: .winLossTie
        case .hockey: .winLossOvertimeLoss
        case .football, .basketball, .baseball, .other: .winLoss
        }
    }

    /// How the league's standings show each team's record. Soccer tables
    /// switch to wins, draws, losses and points; everything else keeps its
    /// schedule shape.
    var standingsRecordFormat: Record.Format {
        switch self {
        case .soccer: .winDrawLossPoints
        default: scheduleRecordFormat
        }
    }
}

extension LeagueDescriptor {
    /// How many periods a game runs before overtime, for telling an
    /// overtime loss from a regulation one. `nil` where periods go unnamed
    /// (baseball's innings).
    var regulationPeriods: Int? {
        switch periodStyle {
        case .halves: 2
        case .quarters: 4
        case .periods: 3
        case .unnamed: nil
        }
    }
}

/// A team's record from its own schedule, in its sport's shape.
///
/// Only the league's own games count: a soccer team's cup ties are on its
/// schedule (`downloadScheduleData`), but the header's record is the league
/// record the standings table shows. Games from a feed that names no
/// competition count, which is every non-soccer feed.
///
/// Exhibitions do not count either (`Game.countsTowardRecord`): a hockey
/// team's September preseason once read 1-3-0 in the header beside the
/// standings' 0-0-0. Only games whose feed marks them preseason or all-star
/// are left out; an event with no season type counts.
///
/// The wins, losses and draws are `seasonRecord`'s, under the league's
/// `RecordRule`. Hockey then moves every loss decided after regulation — a
/// completed game whose final period is past the third — into the
/// overtime-loss column.
func scheduleRecord(games: [Game], league: LeagueID, now: Date = Date()) -> Record {
    let descriptor = league.descriptor
    let leagueGames = games.filter { $0.isLeagueGame(of: league) && $0.countsTowardRecord }
    let counted = seasonRecord(
        games: leagueGames,
        countingAbandonedAsLosses: descriptor.recordRule.countsAbandonedGamesAsLosses,
        pastDatesCountAsPlayed: descriptor.recordRule.usesDateForNextGame,
        now: now
    )

    let format = descriptor.kind.scheduleRecordFormat
    guard format == .winLossOvertimeLoss, let regulation = descriptor.regulationPeriods else {
        return Record(wins: counted.wins, losses: counted.losses, ties: counted.draws, format: format)
    }

    let overtimeLosses = leagueGames.count { game in
        game.completed && !game.gameWin && !game.isDraw
            && !game.cancelled && !game.postponed
            && (Int(game.gamePeriod) ?? 0) > regulation
    }
    return Record(
        wins: counted.wins,
        losses: counted.losses - overtimeLosses,
        ties: counted.draws,
        overtimeLosses: overtimeLosses,
        format: format
    )
}
