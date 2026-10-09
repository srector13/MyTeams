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
        /// Wins, draws and losses, always three parts: a soccer schedule's
        /// `"4-0-1"`, draws in the middle so it matches the table beside it.
        /// (The case keeps its old name; only the order it draws in changed.)
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
            "\(wins)-\(ties)-\(losses)"
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
    /// does not read like a basketball record, and puts it between wins and
    /// losses as its table does. Hockey splits overtime losses
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

// MARK: - Form

extension Record {
    /// How one decided game went for the followed team, as a form guide
    /// draws it: a capsule lettered W, D or L.
    enum Outcome: Hashable, Sendable {
        case win
        /// A level game: a soccer draw, an NFL tie (`Game.isDraw`).
        case draw
        /// Any game not won or drawn, in regulation or after it: a hockey
        /// overtime loss is an L here, as in a form guide.
        case loss

        /// The capsule's letter.
        var letter: String {
            switch self {
            case .win: "W"
            case .draw: "D"
            case .loss: "L"
            }
        }

        /// The outcome spoken in full, for VoiceOver.
        var spokenName: String {
            switch self {
            case .win: "won"
            case .draw: "drew"
            case .loss: "lost"
            }
        }
    }
}

/// The team's form guide: its last `last` decided league games, **oldest
/// first, most recent last**, so the capsules read left to right as the
/// season did (R-5).
///
/// The same walk as `scheduleRecord`, over the same games: only the
/// league's own games, exhibitions left out (`Game.countsTowardRecord`),
/// and "played" judged as `seasonRecord` judges it under the league's
/// `RecordRule` — under MLS's (`usesDateForNextGame`), a fixture whose
/// kickoff is more than four hours past counts as played even if its feed
/// never set `completed`. A won game
/// is a win; a played, level one a draw; any other played one a loss.
///
/// Games that were not decided are skipped rather than counted: fixtures
/// still to be played, live ones, and cancelled or postponed ones — even
/// under MLB's rule, which counts those in the record's losses column, a
/// game never played has no result to show.
///
/// Games are taken in date order (a stable sort, so games at the same time
/// keep the feed's order), since a merged soccer schedule need not arrive
/// sorted. Fewer than `last` decided games gives what there is; none gives
/// `[]`.
func scheduleForm(games: [Game], league: LeagueID, last: Int = 5, now: Date = Date()) -> [Record.Outcome] {
    guard last > 0 else { return [] }
    let pastDatesCountAsPlayed = league.descriptor.recordRule.usesDateForNextGame

    func played(_ game: Game) -> Bool {
        if game.completed { return true }
        return pastDatesCountAsPlayed
            && game.dateAsDate.addingTimeInterval(4 * 3600) < now
    }

    let decided: [(date: Date, outcome: Record.Outcome)] = games.compactMap { game in
        guard game.isLeagueGame(of: league), game.countsTowardRecord else { return nil }
        if game.gameWin { return (game.dateAsDate, .win) }
        guard !game.cancelled, !game.postponed, played(game) else { return nil }
        return (game.dateAsDate, game.isDraw ? .draw : .loss)
    }

    let ordered = decided.enumerated()
        .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
        .map(\.element.outcome)
    return Array(ordered.suffix(last))
}
