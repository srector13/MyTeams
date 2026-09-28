//
//  Sport.swift
//  myTeams
//
//  Created by Stephen Rector on 5/19/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The sport a league plays, which decides the roster, box score and player
/// statistics a team page reads.
enum SportKind: String, Codable, Sendable {
    case football
    case basketball
    case baseball
    case soccer
    /// Hockey: a team page with its roster, schedule cards named by period,
    /// a box score of skater and goalie tables (`HockeyBoxScore`), and each
    /// player's season line from the athlete splits (`SplitsSeasonLine`).
    case hockey
    /// A sport the app has no dedicated views for.
    case other
}

/// How a league's roster feed lists its athletes.
enum RosterShape: Sendable {
    /// `athletes` is a list of groups, each with its own `items` (NFL units,
    /// MLB position groups).
    case grouped
    /// `athletes` is one flat list (college basketball, MLS).
    case flat
}

/// How a league's schedule turns into a record and a next game.
struct RecordRule: Sendable, Hashable {
    /// Cancelled and postponed fixtures count in the losses column. MLB has
    /// always been shown this way; every other league treats an abandoned
    /// fixture as neither win nor loss. See `seasonRecord`.
    var countsAbandonedGamesAsLosses = false

    /// A past kick-off also counts as played, both for the record and for
    /// locating the next game. MLS completion flags lag or never arrive. See
    /// `getNextGame` and `seasonRecord(pastDatesCountAsPlayed:)`.
    var usesDateForNextGame = false
}

/// How ESPN numbers a league's seasons.
///
/// The feeds file a season under one year, and which year differs by league:
/// the 2026-27 NBA season is 2027, the 2026-27 Premier League season 2026.
/// See FIXTURES.md, "Seasons the feeds returned".
enum SeasonNaming: Sendable, Hashable {
    /// Played within one calendar year: MLB, MLS, the WNBA and NWSL.
    case calendarYear
    /// Filed under the year it starts. The new season begins in
    /// `rolloverMonth` (1–12): February for football, whose seasons end with
    /// the January bowls and playoffs, June for European soccer.
    case startingYear(rolloverMonth: Int)
    /// Filed under the year it ends: the NBA, NHL and college basketball,
    /// whose next season is named from `rolloverMonth` onwards.
    case endingYear(rolloverMonth: Int)

    /// The season in progress, or next to start, at `date`.
    func season(at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return switch self {
        case .calendarYear: year
        case .startingYear(let rolloverMonth): month >= rolloverMonth ? year : year - 1
        case .endingYear(let rolloverMonth): month >= rolloverMonth ? year + 1 : year
        }
    }
}

/// How a schedule card draws a game in progress.
enum LiveCardStyle: Sendable {
    /// The period and clock (or "Halftime"), with the live score beneath.
    case periodFirst
    /// The live score, with an arrow for whether the followed team leads or
    /// trails, above the period and clock.
    case scoreFirst
}

/// One button in a roster's filter menu: the players it keeps.
struct RosterFilter: Sendable, Hashable {
    var label: String
    /// The unit the roster feed files the player under (the NFL's
    /// `"offense"`, `"defense"`, `"specialTeam"`), or `nil` for any.
    var unit: String?
    /// The player's position as the feed names it, or `nil` for any.
    var position: String?

    init(label: String, unit: String? = nil, position: String? = nil) {
        self.label = label
        self.unit = unit
        self.position = position
    }

    /// A filter for each position, labelled as the feed names it unless
    /// `labels` renames it.
    static func positions(_ positions: [String], labels: [String: String] = [:]) -> [RosterFilter] {
        positions.map { RosterFilter(label: labels[$0] ?? $0, position: $0) }
    }

    /// A unit's filters: every player in it, then each position within it.
    static func unit(
        _ unit: String,
        positions: [String],
        labels: [String: String] = [:]
    ) -> [RosterFilter] {
        [RosterFilter(label: "All", unit: unit)]
            + positions.map { RosterFilter(label: labels[$0] ?? $0, unit: unit, position: $0) }
    }
}

/// An entry in a roster's filter menu, after its leading "All".
enum RosterFilterEntry: Sendable, Hashable {
    case filter(RosterFilter)
    /// A submenu, such as one NFL unit and its positions.
    case menu(title: String, filters: [RosterFilter])
}

/// Everything that differs by league rather than by team.
///
/// The retired `Team` enum carried these as per-team switches, and the views
/// carried the rest as per-team flags and name matching. They live here now,
/// keyed on the league, so any team in a known league gets them.
struct LeagueDescriptor: Sendable, Identifiable {
    /// How a league names its game periods.
    enum PeriodStyle: Sendable {
        case halves
        case quarters
        /// Hockey's three periods.
        case periods
        /// No period label (baseball innings are not named).
        case unnamed
    }

    let id: LeagueID
    let kind: SportKind
    let displayName: String
    let isCollege: Bool
    let rosterShape: RosterShape
    let recordRule: RecordRule

    /// The field of an ESPN competitor's `team` object that names it on the
    /// schedule cards. Display only — the followed team is found by id.
    let competitorNameField: TeamNameField

    let periodStyle: PeriodStyle

    /// What a schedule card calls a finished game that stands level.
    var drawLabel = "Draw"

    /// How a schedule card draws a game in progress.
    var liveCardStyle = LiveCardStyle.periodFirst

    /// The roster filter menu, after its leading "All". The positions worth
    /// filtering by, and how the feed groups them, differ by league.
    var rosterFilters: [RosterFilterEntry] = []

    /// A bundled image the game sheet draws in place of the venue's photo,
    /// for leagues whose summaries carry none. Such a sheet names the venue
    /// alone rather than appending the city and state: the MLS summaries
    /// fold the state into the city.
    var venueBackdropAsset: String?

    // MARK: Endpoint configuration

    /// The `group` a standings request names, or `nil` for the league's
    /// whole table. College standings are a tree of conferences under one
    /// division: `"80"` is FBS football (`"50"` there would be a single FCS
    /// conference), `"50"` Division I basketball. See `LeagueID.standingsURL`.
    var standingsGroup: String?

    /// How ESPN numbers the league's seasons, for asking for the current
    /// one explicitly (`season(at:)`); `nil` leaves it to the feed.
    var seasonNaming: SeasonNaming?

    /// The cups and continental competitions a team in this league may also
    /// play in, each an ESPN league of its own. A team's schedule fetches
    /// each alongside the league (`downloadScheduleData`); a team not in a
    /// cup gets an empty feed from it. Every path here was checked against
    /// a live team schedule on 2026-09-28.
    var cupCompetitions: [LeagueID] = []

    /// The `seasontype` a stat leaders request names, alongside the season
    /// `seasonNaming` gives (`leadersSeason(at:)`); `nil` leaves both to the
    /// feed. Soccer needs `"1"`: asked for nothing, its leaders feed answered
    /// a cup playoff round (Liga MX, NWSL), an all-star stub (MLS) or 404
    /// (Premier League, LALIGA) on 2026-09-28. The other leagues' feeds pick
    /// their latest regular season themselves. See `LeagueID.leadersURL`.
    var leadersSeasonType: String?

    /// The season a stat leaders request names at `date`, or `nil` to take
    /// the feed's own. Only leagues with a `leadersSeasonType` name one.
    func leadersSeason(at date: Date) -> Int? {
        guard leadersSeasonType != nil else { return nil }
        return seasonNaming?.season(at: date)
    }

    /// The leaderboards a leaders screen shows, in order. See
    /// `SportKind.leaderCategories`.
    var leaderCategories: [LeaderCategorySpec] { kind.leaderCategories }

    /// The label for a game period as the feeds number it (`status.period`).
    ///
    /// Only regulation periods are named; overtime and innings read as blank.
    func periodName(_ period: String) -> String {
        let names: [String: String] = switch periodStyle {
        case .halves: ["1": "1st Half", "2": "2nd Half"]
        case .quarters: ["1": "1st Quarter", "2": "2nd Quarter", "3": "3rd Quarter", "4": "4th Quarter"]
        case .periods: ["1": "1st Period", "2": "2nd Period", "3": "3rd Period"]
        case .unnamed: [:]
        }
        return names[period] ?? ""
    }

    // MARK: - Known leagues

    static let mensCollegeBasketball = LeagueDescriptor(
        id: .mensCollegeBasketball,
        kind: .basketball,
        displayName: "NCAA Men's Basketball",
        isCollege: true,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .halves,
        rosterFilters: [
            .filter(RosterFilter(label: "Forwards", position: "Forward")),
            .filter(RosterFilter(label: "Guards", position: "Guard")),
        ],
        standingsGroup: "50",
        seasonNaming: .endingYear(rolloverMonth: 7)
    )

    static let nfl = LeagueDescriptor(
        id: .nfl,
        kind: .football,
        displayName: "NFL",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .quarters,
        drawLabel: "Tie",
        liveCardStyle: .scoreFirst,
        // The grouped roster feed files each player under a unit.
        rosterFilters: [
            .menu(title: "Defense", filters: RosterFilter.unit(
                "defense",
                positions: [
                    "Cornerback", "Defensive End", "Defensive Tackle",
                    "Linebacker", "Safety",
                ]
            )),
            .menu(title: "Offense", filters: RosterFilter.unit(
                "offense",
                positions: [
                    "Center", "Fullback", "Guard", "Quarterback",
                    "Running Back", "Offensive Tackle", "Tight End",
                    "Wide Receiver",
                ],
                // The menu shortens this one; the feed does not.
                labels: ["Offensive Tackle": "Tackle"]
            )),
            .menu(title: "Special Teams", filters: RosterFilter.unit(
                "specialTeam",
                positions: ["Long Snapper", "Place Kicker", "Punter"]
            )),
        ],
        seasonNaming: .startingYear(rolloverMonth: 2)
    )

    static let mlb = LeagueDescriptor(
        id: .mlb,
        kind: .baseball,
        displayName: "MLB",
        isCollege: false,
        rosterShape: .grouped,
        recordRule: RecordRule(countsAbandonedGamesAsLosses: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .unnamed,
        rosterFilters: RosterFilter.positions([
            "Catcher", "Center Fielder", "First Baseman", "Relief Pitcher",
            "Second Baseman", "Shortstop", "Starting Pitcher", "Third Baseman",
        ]).map(RosterFilterEntry.filter),
        seasonNaming: .calendarYear
    )

    static let mls = LeagueDescriptor(
        id: .mls,
        kind: .soccer,
        displayName: "MLS",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(usesDateForNextGame: true),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        rosterFilters: soccerRosterFilters,
        venueBackdropAsset: "soccerField",
        seasonNaming: .calendarYear,
        cupCompetitions: [.soccer("usa.open"), .soccer("concacaf.leagues.cup"), .soccer("concacaf.champions")],
        leadersSeasonType: soccerLeadersSeasonType
    )

    /// The regular season's `seasontype` in every soccer leaders feed. See
    /// `leadersSeasonType`.
    private static let soccerLeadersSeasonType = "1"

    /// The positions a basketball roster feed names every player by.
    private static let basketballRosterFilters: [RosterFilterEntry] = RosterFilter.positions(
        ["Center", "Forward", "Guard"],
        labels: ["Center": "Centers", "Forward": "Forwards", "Guard": "Guards"]
    ).map(RosterFilterEntry.filter)

    /// The soccer menu MLS has always had, under the menu's own names for the
    /// playing positions. Every soccer feed captured names the same four.
    private static let soccerRosterFilters: [RosterFilterEntry] = RosterFilter.positions(
        ["Goalkeeper", "Defender", "Midfielder", "Forward"],
        labels: ["Defender": "Defense", "Midfielder": "Midfield", "Forward": "Attacker"]
    ).map(RosterFilterEntry.filter)

    static let nba = LeagueDescriptor(
        id: .nba,
        kind: .basketball,
        displayName: "NBA",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .quarters,
        rosterFilters: basketballRosterFilters,
        seasonNaming: .endingYear(rolloverMonth: 7)
    )

    static let wnba = LeagueDescriptor(
        id: .wnba,
        kind: .basketball,
        displayName: "WNBA",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .quarters,
        rosterFilters: basketballRosterFilters,
        seasonNaming: .calendarYear
    )

    static let womensCollegeBasketball = LeagueDescriptor(
        id: .womensCollegeBasketball,
        kind: .basketball,
        displayName: "NCAA Women's Basketball",
        isCollege: true,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        // Women's college basketball plays four quarters, not two halves.
        periodStyle: .quarters,
        rosterFilters: basketballRosterFilters,
        standingsGroup: "50",
        seasonNaming: .endingYear(rolloverMonth: 7)
    )

    static let nhl = LeagueDescriptor(
        id: .nhl,
        kind: .hockey,
        displayName: "NHL",
        isCollege: false,
        // Grouped by position ("Centers", "Defense", "Goalies"), not by unit.
        rosterShape: .grouped,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .periods,
        rosterFilters: RosterFilter.positions(
            ["Center", "Left Wing", "Right Wing", "Defense", "Goaltender"],
            labels: ["Center": "Centers", "Left Wing": "Left Wings", "Right Wing": "Right Wings", "Goaltender": "Goalies"]
        ).map(RosterFilterEntry.filter),
        seasonNaming: .endingYear(rolloverMonth: 7)
    )

    static let collegeFootball = LeagueDescriptor(
        id: .collegeFootball,
        kind: .football,
        displayName: "NCAA Football",
        isCollege: true,
        rosterShape: .grouped,
        recordRule: RecordRule(),
        competitorNameField: .nickname,
        periodStyle: .quarters,
        drawLabel: "Tie",
        liveCardStyle: .scoreFirst,
        // Units as in the NFL feed, but the line is one "Offensive Lineman".
        rosterFilters: [
            .menu(title: "Defense", filters: RosterFilter.unit(
                "defense",
                positions: ["Cornerback", "Defensive End", "Defensive Tackle", "Linebacker", "Safety"]
            )),
            .menu(title: "Offense", filters: RosterFilter.unit(
                "offense",
                positions: ["Offensive Lineman", "Quarterback", "Running Back", "Tight End", "Wide Receiver"],
                labels: ["Offensive Lineman": "Lineman"]
            )),
            .menu(title: "Special Teams", filters: RosterFilter.unit(
                "specialTeam",
                positions: ["Long Snapper", "Place Kicker", "Punter"]
            )),
        ],
        standingsGroup: "80",
        seasonNaming: .startingYear(rolloverMonth: 2)
    )

    static let premierLeague = LeagueDescriptor(
        id: .premierLeague,
        kind: .soccer,
        displayName: "Premier League",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        rosterFilters: soccerRosterFilters,
        venueBackdropAsset: "soccerField",
        seasonNaming: .startingYear(rolloverMonth: 6),
        cupCompetitions: [.soccer("eng.fa"), .soccer("eng.league_cup"), .soccer("uefa.champions")],
        leadersSeasonType: soccerLeadersSeasonType
    )

    static let laLiga = LeagueDescriptor(
        id: .laLiga,
        kind: .soccer,
        displayName: "LALIGA",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        rosterFilters: soccerRosterFilters,
        venueBackdropAsset: "soccerField",
        seasonNaming: .startingYear(rolloverMonth: 6),
        cupCompetitions: [.soccer("esp.copa_del_rey"), .soccer("uefa.champions")],
        leadersSeasonType: soccerLeadersSeasonType
    )

    static let ligaMX = LeagueDescriptor(
        id: .ligaMX,
        kind: .soccer,
        displayName: "Liga MX",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        rosterFilters: soccerRosterFilters,
        venueBackdropAsset: "soccerField",
        seasonNaming: .startingYear(rolloverMonth: 6),
        cupCompetitions: [.soccer("concacaf.champions"), .soccer("concacaf.leagues.cup")],
        leadersSeasonType: soccerLeadersSeasonType
    )

    static let nwsl = LeagueDescriptor(
        id: .nwsl,
        kind: .soccer,
        displayName: "NWSL",
        isCollege: false,
        rosterShape: .flat,
        recordRule: RecordRule(),
        competitorNameField: .shortDisplayName,
        periodStyle: .halves,
        rosterFilters: soccerRosterFilters,
        // Like MLS, the summaries fold the state into the city.
        venueBackdropAsset: "soccerField",
        // No cups: the Challenge Cup's team feed listed nothing when checked.
        seasonNaming: .calendarYear,
        leadersSeasonType: soccerLeadersSeasonType
    )

    /// Every known league's descriptor, keyed by id. `LeagueID.knownLeagues`
    /// lists the same leagues in order.
    static let known: [LeagueID: LeagueDescriptor] = Dictionary(
        uniqueKeysWithValues: [
            mensCollegeBasketball, nfl, mlb, mls,
            nba, wnba, womensCollegeBasketball, nhl, collegeFootball,
            premierLeague, laLiga, ligaMX, nwsl,
        ].map { ($0.id, $0) }
    )

    /// The descriptor for `id`: a known league's own, or a plain one derived
    /// from the sport path component.
    static func descriptor(for id: LeagueID) -> LeagueDescriptor {
        if let known = known[id] { return known }
        return LeagueDescriptor(
            id: id,
            kind: SportKind(rawValue: id.sport) ?? .other,
            displayName: id.path,
            isCollege: false,
            rosterShape: .flat,
            recordRule: RecordRule(),
            competitorNameField: .shortDisplayName,
            periodStyle: .unnamed
        )
    }
}

// MARK: - Stat leaders

/// How a leaderboard shows a leader's `value`.
///
/// The leaders feed's own `displayValue` cannot be shown as the figure: MLB
/// puts a whole stat line there (`"179-567, 42 HR, …"`), soccer's
/// `goalsLeaders` a sentence (`"Matches: 5, Goals: 5"`), and the NFL rounds
/// 3.5 sacks to `"4"`. So the number is formatted from `value`, and a
/// `displayValue` with words in it is kept as the row's detail line.
enum LeaderValueFormat: Sendable, Hashable {
    /// `53`
    case whole
    /// `3.5`, but `4` for a whole number — sacks.
    case wholeOrTenths
    /// `33.5`
    case tenths
    /// `2.02`
    case hundredths
    /// Three places with no leading zero, as batting averages and save
    /// percentages are written: `.316`, `.921`, `1.033`.
    case rate
    /// A sign on anything above zero: `+57`, `-2`, `0`.
    case signed
    /// The feed's `displayValue` as it stands.
    case feed

    func format(_ value: Double, displayValue: String) -> String {
        switch self {
        case .whole:
            return String(format: "%.0f", value)
        case .wholeOrTenths:
            return value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        case .tenths:
            return String(format: "%.1f", value)
        case .hundredths:
            return String(format: "%.2f", value)
        case .rate:
            let text = String(format: "%.3f", value)
            if text.hasPrefix("0.") { return String(text.dropFirst()) }
            if text.hasPrefix("-0.") { return "-" + String(text.dropFirst(2)) }
            return text
        case .signed:
            let text = String(format: "%.0f", value)
            return value.rounded() > 0 ? "+" + text : text
        case .feed:
            return displayValue
        }
    }
}

/// One leaderboard a leaders screen shows: the leaders feed's category
/// `name`, and how the screen labels and formats it.
struct LeaderCategorySpec: Sendable, Hashable {
    /// The feed's category `name`, e.g. `"pointsPerGame"`.
    var name: String
    /// The board's heading, e.g. `"Points"`.
    var title: String
    /// The short label beside each figure, e.g. `"PPG"`.
    var label: String
    var format: LeaderValueFormat

    init(_ name: String, _ title: String, _ label: String, _ format: LeaderValueFormat = .whole) {
        self.name = name
        self.title = title
        self.label = label
        self.format = format
    }
}

extension SportKind {
    /// The leaderboards a leaders screen shows for the sport, in order.
    ///
    /// Every league of a sport names its categories alike (checked against
    /// all 13 registered leagues' leaders feeds on 2026-09-28), so the choice
    /// is made per sport, not per league. A category a feed lacks is skipped.
    /// `.other` has none: its screen shows every category the feed lists,
    /// under the feed's own names. See `leaderBoards(from:kind:depth:)`.
    var leaderCategories: [LeaderCategorySpec] {
        switch self {
        case .basketball:
            [
                LeaderCategorySpec("pointsPerGame", "Points", "PPG", .tenths),
                LeaderCategorySpec("reboundsPerGame", "Rebounds", "RPG", .tenths),
                LeaderCategorySpec("assistsPerGame", "Assists", "APG", .tenths),
                LeaderCategorySpec("stealsPerGame", "Steals", "SPG", .tenths),
                LeaderCategorySpec("blocksPerGame", "Blocks", "BPG", .tenths),
                // A percentage out of 100 (`68.2`), unlike the feed's
                // `3PointPct`, which is a fraction and so not shown.
                LeaderCategorySpec("fieldGoalPercentage", "Field Goal %", "FG%", .tenths),
            ]
        case .hockey:
            [
                LeaderCategorySpec("goals", "Goals", "G"),
                LeaderCategorySpec("assists", "Assists", "A"),
                LeaderCategorySpec("points", "Points", "PTS"),
                LeaderCategorySpec("plusMinus", "Plus/Minus", "+/-", .signed),
                LeaderCategorySpec("wins", "Goalie Wins", "W"),
                LeaderCategorySpec("avgGoalsAgainst", "Goals Against Average", "GAA", .hundredths),
                LeaderCategorySpec("savePct", "Save Percentage", "SV%", .rate),
                LeaderCategorySpec("shutouts", "Shutouts", "SO"),
            ]
        case .football:
            [
                LeaderCategorySpec("passingYards", "Passing Yards", "PASS YDS"),
                LeaderCategorySpec("passingTouchdowns", "Passing Touchdowns", "PASS TD"),
                LeaderCategorySpec("rushingYards", "Rushing Yards", "RUSH YDS"),
                LeaderCategorySpec("receivingYards", "Receiving Yards", "REC YDS"),
                LeaderCategorySpec("receptions", "Receptions", "REC"),
                LeaderCategorySpec("totalTackles", "Tackles", "TCKL"),
                LeaderCategorySpec("sacks", "Sacks", "SACK", .wholeOrTenths),
                LeaderCategorySpec("interceptions", "Interceptions", "INT"),
            ]
        case .soccer:
            [
                // The `…Leaders` boards, not `goals`/`assists`: same values,
                // plus the matches played in their `displayValue`.
                LeaderCategorySpec("goalsLeaders", "Goals", "G"),
                LeaderCategorySpec("assistsLeaders", "Assists", "A"),
                LeaderCategorySpec("shotsOnTarget", "Shots on Target", "SOT"),
                LeaderCategorySpec("saves", "Saves", "SV"),
            ]
        case .baseball:
            [
                LeaderCategorySpec("avg", "Batting Average", "AVG", .rate),
                LeaderCategorySpec("homeRuns", "Home Runs", "HR"),
                LeaderCategorySpec("RBIs", "Runs Batted In", "RBI"),
                LeaderCategorySpec("stolenBases", "Stolen Bases", "SB"),
                LeaderCategorySpec("ERA", "Earned Run Average", "ERA", .hundredths),
                LeaderCategorySpec("wins", "Wins", "W"),
                LeaderCategorySpec("strikeouts", "Strikeouts", "K"),
                LeaderCategorySpec("saves", "Saves", "SV"),
            ]
        case .other:
            []
        }
    }
}
