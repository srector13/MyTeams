//
//  Linescore.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// A game's score period by period, whatever the sport: one column per
/// period, then the total.
///
/// How many columns a game gets comes from the feed, never from the sport:
/// the summary's `format.regulation.periods` (4 NBA quarters, 3 NHL periods,
/// 2 halves, 9 innings) sets the regulation columns, and any period the
/// competitors have a score for beyond that adds one. Before the game, every
/// regulation column reads "-".
struct Linescore: Hashable, Sendable {
    /// One team's row.
    struct Line: Hashable, Sendable, Identifiable {
        /// `"home"` or `"away"`, as the feed labels the competitor.
        var homeAway: String
        /// The team's abbreviation, as the feed gives it.
        var abbreviation: String
        /// One entry per column of `Linescore.periodLabels`; "-" for a
        /// period with no score yet.
        var periods: [String]
        /// The team's score, or "-" before it has one.
        var total: String

        var id: String { homeAway.isEmpty ? abbreviation : homeAway }
    }

    /// The column headings: "1", "2", "3" … through regulation, then "OT",
    /// "2OT" … (or, for sports whose periods go unnamed, the next number:
    /// baseball's tenth inning is "10").
    var periodLabels: [String]
    var home: Line
    var away: Line

    /// How many period columns the game has.
    var periodCount: Int { periodLabels.count }
}

/// What the `overtime`th period past regulation is called: "OT", then
/// "2OT", "3OT" ….
func overtimeLabel(_ overtime: Int) -> String {
    overtime <= 1 ? "OT" : "\(overtime)OT"
}

extension Linescore {
    /// Reads the linescore from a game's summary document.
    ///
    /// Regulation length is the summary's `format.regulation.periods`,
    /// falling back to the league's `regulationPeriods` for a summary that
    /// has no format. Returns `nil` when the header does not list both a
    /// home and an away competitor, or when neither source says how many
    /// periods there are and none has been played.
    init?(summary json: JSON, league: LeagueDescriptor) {
        self.init(
            competitors: json["header", "competitions", 0, "competitors"],
            regulationPeriods: json["format", "regulation", "periods"].int ?? league.regulationPeriods,
            numbersExtraPeriods: league.periodStyle == .unnamed
        )
    }

    /// Reads the linescore from a competition's `competitors`, which the
    /// summary header and the league scoreboards shape alike: each with a
    /// `homeAway`, a `score`, and one `linescores` entry per period played.
    ///
    /// - Parameters:
    ///   - regulationPeriods: how many periods a game runs before
    ///     overtime; `nil` shows only the periods played.
    ///   - numbersExtraPeriods: numbers the periods past regulation, as
    ///     baseball does its extra innings, rather than calling them "OT".
    init?(competitors: JSON, regulationPeriods: Int?, numbersExtraPeriods: Bool = false) {
        var homeCompetitor: JSON?
        var awayCompetitor: JSON?
        for (_, competitor) in competitors {
            switch competitor["homeAway"].stringValue {
            case "home": homeCompetitor = competitor
            case "away": awayCompetitor = competitor
            default: break
            }
        }
        guard let homeCompetitor, let awayCompetitor else { return nil }

        /// Each period's score as the feed shows it. Scoreboards have been
        /// seen with only a numeric `value`.
        func periodScores(_ competitor: JSON) -> [String] {
            competitor["linescores"].map { (_, period) -> String in
                let display = period["displayValue"].stringValue
                return display.isEmpty ? period["value"].stringValue : display
            }
        }

        let homeScores = periodScores(homeCompetitor)
        let awayScores = periodScores(awayCompetitor)
        let columnCount = max(regulationPeriods ?? 0, homeScores.count, awayScores.count)
        guard columnCount > 0 else { return nil }

        periodLabels = (1 ... columnCount).map { (period: Int) -> String in
            guard let regulation = regulationPeriods, period > regulation, !numbersExtraPeriods else {
                return "\(period)"
            }
            return overtimeLabel(period - regulation)
        }

        func line(_ competitor: JSON, scores: [String]) -> Line {
            let padding = [String](repeating: "-", count: columnCount - scores.count)
            return Line(
                homeAway: competitor["homeAway"].stringValue,
                abbreviation: competitor["team", "abbreviation"].stringValue,
                periods: scores + padding,
                total: competitorScore(competitor).map { "\($0)" } ?? "-"
            )
        }

        home = line(homeCompetitor, scores: homeScores)
        away = line(awayCompetitor, scores: awayScores)
    }
}

extension LeagueDescriptor {
    /// The period line a schedule card draws for a game in progress: the
    /// regulation period's name (`periodName`: "3rd Period", "2nd Half"),
    /// or, past regulation, "OT", "2OT" …. Blank where periods go unnamed
    /// (baseball) or the feed gave no period.
    ///
    /// `periodName` itself still names regulation only; the golden tests
    /// pin that. This is the card's label, which needs overtime too.
    func liveCardPeriodLabel(_ period: String) -> String {
        let name = periodName(period)
        guard name.isEmpty,
              let number = Int(period),
              let regulation = regulationPeriods,
              number > regulation
        else { return name }
        return overtimeLabel(number - regulation)
    }
}
