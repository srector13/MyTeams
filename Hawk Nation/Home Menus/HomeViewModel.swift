//
//  HomeViewModel.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Observation

/// A favorite's game under way, as the league's scoreboard has it now: the
/// same reading of the board a Live Activity takes
/// (`LiveActivityStateMapper`), so Home and the Lock Screen agree.
struct HomeLiveGame: Identifiable, Hashable, Sendable {
    let team: TeamRef
    /// The matchup: each side's name, home and away.
    let info: GameActivityInfo
    /// The scores and the stage, "4th Quarter · 0:48".
    let state: GameActivityState
    /// Whether the favorite is the home side.
    let favoriteIsHome: Bool
    /// The game as the favorite's schedule lists it, for its sheet and the
    /// opponent's crest; `nil` while the schedule has not loaded.
    let game: Game?

    var id: String { info.gameID }
}

/// A story from a favorite's news feed, with the favorite it came from.
struct HomeHeadline: Identifiable, Hashable, Sendable {
    let team: TeamRef
    let article: News

    var id: String { article.id }
}

/// The game Home's hero leads with (`HomeHero`): a favorite's game under
/// way, else the soonest still to come, else one just played.
struct HomeFeaturedGame: Identifiable, Hashable, Sendable {
    enum Phase: Hashable, Sendable {
        case live
        case upcoming
        case final
    }

    let entry: HomeGame
    let phase: Phase
    /// The board's reading of a live game: its scores and stage.
    let live: HomeLiveGame?

    var id: String { entry.id }
    var team: TeamRef { entry.team }
    var game: Game { entry.game }

    /// Whether the favorite is the home side, as the board says while it's
    /// live and the schedule says otherwise. A neutral-site game keeps the
    /// schedule's listing, so the matchup still reads away first.
    var favoriteIsHome: Bool { live?.favoriteIsHome ?? entry.game.gameHome }
}

/// One day of This Week's strip (`HomeFeed.week`): its games, in start
/// order, none on a quiet day.
struct HomeWeekDay: Identifiable, Equatable, Sendable {
    /// The day's start.
    let date: Date
    let games: [HomeGame]

    var id: Date { date }
}

/// What a favorite's card in My Teams says (`HomeFeed.teamSummary`): the
/// team page header's record, standing and form, and where its season is.
struct HomeTeamSummary: Identifiable, Equatable, Sendable {
    /// Where the favorite's season stands, as the card's foot words it.
    enum Status: Equatable, Sendable {
        /// The season is still loading.
        case loading
        /// "Live vs Dolphins · 21–17", the favorite's score first.
        case live(String)
        /// "Next vs Chargers · Sun 3:25 PM".
        case next(String)
        /// "Last L 0–4 at Nashville", the favorite's score first.
        case last(String)
        case seasonOver
        case preseason

        /// The foot's line.
        var text: String {
            switch self {
            case .loading: "Loading"
            case .live(let text), .next(let text), .last(let text): text
            case .seasonOver: "Season over"
            case .preseason: "Preseason"
            }
        }

        /// The SF Symbol beside the line.
        var systemImage: String {
            switch self {
            case .loading, .next, .preseason: "calendar"
            case .live: "dot.radiowaves.left.and.right"
            case .last: "flag.checkered"
            case .seasonOver: "moon.zzz"
            }
        }
    }

    let team: TeamRef
    /// The record, standing and form, as the team page's header has them.
    let header: TeamHeaderSummary
    /// The team's place in its league's poll, for a college team.
    let pollRank: Int?
    let status: Status

    var id: TeamRef.ID { team.id }

    /// The foot's text for "nothing scheduled": a team with no record yet
    /// has its season's state in the header, so the foot says what's next
    /// instead of repeating it (H2).
    static let nothingScheduledText = "No games on the schedule yet"

    /// What the header shows in the record's place before there is one:
    /// "Preseason" or "Season over", the state the foot would otherwise
    /// repeat; "No record yet" for a season under way that the feeds
    /// haven't counted.
    var headerStatusText: String {
        switch status {
        case .loading, .preseason: Status.preseason.text
        case .seasonOver: Status.seasonOver.text
        case .live, .next, .last: "No record yet"
        }
    }

    /// The foot's line, so the team's status shows once (H2): where its
    /// season is — the game under way, the next game, the last result —
    /// unless the header already says it, when it says what's next:
    /// `nothingScheduledText`.
    var footText: String {
        guard header.record == nil else { return status.text }
        switch status {
        case .preseason, .seasonOver: return Self.nothingScheduledText
        case .loading, .live, .next, .last: return status.text
        }
    }
}

/// Home's news section (`HomeFeed.homeNews`, H5): the few fresh stories it
/// shows, and the rest, which wait behind "More News".
struct HomeNewsSelection: Equatable, Sendable {
    /// Up to `HomeFeed.homeNewsLimit` stories from the last
    /// `HomeFeed.homeNewsMaxAge`, dealt in turn across the favorites.
    let shown: [HomeHeadline]
    /// Every other story, in the feed's order, older ones included.
    let more: [HomeHeadline]
    /// Whether any story was held back for its age alone, so the section
    /// can say where the older ones went.
    let holdsOlderStories: Bool
}

/// A favorite's slice of its standings table for Home (`HomeFeed
/// .standingsSlice`): its own row and the rows either side of it.
struct HomeStandingsSlice: Identifiable, Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        /// The table's rank, or the row's place where the feed ranks none.
        let rank: Int
        let entry: StandingsEntry
        let isFollowed: Bool

        var id: String { entry.teamID }
    }

    let team: TeamRef
    let kind: StandingsKind
    /// The table's name, `"AFC West"`, `"Bundesliga"`.
    let title: String
    /// Three rows where the table has them, first place first.
    let rows: [Row]

    var id: TeamRef.ID { team.id }
}

/// A favorite's top performer for Home: the leader of the first of its
/// sport's boards (`TeamLeadersStore`).
struct HomePerformer: Identifiable, Equatable, Sendable {
    let team: TeamRef
    let board: LeaderBoard
    let row: LeaderBoardRow

    var id: TeamRef.ID { team.id }
}

/// A game on one of the favorites' league boards, for Around Your Leagues
/// (`HomeFeed.leagueGames`): the board's reading of it, its two sides — the
/// reader's favorite where they follow one, else a stand-in built from the
/// board's names, crest and colours — and where it stands.
struct HomeLeagueGame: Identifiable, Hashable, Sendable {
    /// Live first, then still to come, then over: the block's order.
    enum Phase: Int, Hashable, Sendable, Comparable {
        case live
        case upcoming
        case final

        static func < (lhs: Phase, rhs: Phase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let league: LeagueID
    let board: ScoreboardGame
    let away: ScoreboardCompetitor
    let home: ScoreboardCompetitor
    /// The away side to draw: the favorite, or the board's stand-in.
    let awayTeam: TeamRef
    let homeTeam: TeamRef
    /// The reader's favorite in the game, the home side's if both are.
    let favorite: TeamRef?
    let phase: Phase

    var id: String { board.gameID }

    /// Whether the board's scores mean anything yet: a game under way or
    /// played out. A game to come, or called off, reads 0–0 on the board.
    var hasScore: Bool {
        board.state == "in" || (board.state == "post" && board.completed)
    }

    /// `competitor`'s score as the row shows it, or `nil` without one.
    func shownScore(_ competitor: ScoreboardCompetitor) -> String? {
        guard hasScore, let score = competitor.score else { return nil }
        return "\(score)"
    }

    /// Whether `competitor` won: a played-out game's `winner` flag. Neither
    /// side of a draw.
    func isWinner(_ competitor: ScoreboardCompetitor) -> Bool {
        phase == .final && board.completed && (board.teams[competitor.teamID]?.winner ?? false)
    }

    /// `competitor`'s poll rank, for a college game.
    func rank(of competitor: ScoreboardCompetitor) -> Int? {
        board.teams[competitor.teamID]?.rank
    }

    /// Whether `competitor` is the reader's favorite.
    func isFavorite(_ competitor: ScoreboardCompetitor) -> Bool {
        favorite?.espnID == competitor.teamID
    }
}

/// What a league game's row says of its state (`HomeFeed.leagueStatus`):
/// "Live" over "4th Quarter · 0:48", "Sun 8:25 PM" over "CBS", "Final"
/// over the day it was played.
struct HomeLeagueStatus: Equatable, Sendable {
    let primary: String
    let detail: String?
    let isLive: Bool
}

/// One league's block in Around Your Leagues: every game it lists for the
/// scope, in order (`HomeFeed.leagueGames`) — the view caps them — and
/// whether its board has answered.
struct HomeLeagueBlock: Identifiable, Equatable, Sendable {
    let league: LeagueID
    let games: [HomeLeagueGame]
    let state: SectionLoadState

    var id: LeagueID { league }

    /// "Premier League", "NFL", "NCAA Football".
    var title: String { league.descriptor.displayName }
}

/// What Home's view tells its model about Around Your Leagues: the reader's
/// settings, and whether the section is in the layout at all — a hidden
/// section fetches nothing.
struct HomeLeaguesConfiguration: Equatable, Sendable {
    var settings: HomeLeaguesSettings
    var isShown: Bool

    /// Before the view has said: nothing fetched.
    static let unset = HomeLeaguesConfiguration(settings: .standard, isShown: false)
}

/// A league's board as Around Your Leagues last fetched it: the request it
/// answered, so a new day, a new scope or Top 25 switched reads as not
/// loaded, and when.
struct HomeLeagueFetch: Equatable, Sendable {
    let url: String
    let games: [ScoreboardGame]
    let fetchedAt: Date
}

/// Which of a league's two boards a request is for: today's, polled live,
/// or the week's span, fetched rarely.
enum HomeLeagueSpan: Hashable, Sendable {
    case today
    case week
}

// `HomeGame`, `HomeDay` and Home's ±7-day window (`upcomingWindow`,
// `games`, `upcomingDays`, `results`) live in HomeFeedWindow.swift, which
// the widget compiles too (R-9).
extension HomeFeed {
    /// The favorites' games under way on `boards`, in favorites order, each
    /// game once however many favorites play in it. A favorite's games are
    /// read from its league's board and its cups'.
    ///
    /// - Parameter seasons: each favorite's season by `TeamRef.ID`, for the
    ///   scheduled game a tile opens.
    static func liveGames(
        teams: [TeamRef],
        boards: [LeagueID: [ScoreboardGame]],
        seasons: [TeamRef.ID: [Game]]
    ) -> [HomeLiveGame] {
        var seen: Set<String> = []
        var result: [HomeLiveGame] = []
        for team in teams {
            for competition in [team.league] + team.league.descriptor.cupCompetitions {
                for board in boards[competition] ?? [] where board.state == "in" {
                    guard !seen.contains(board.gameID),
                          let side = board.competitors.first(where: { $0.teamID == team.espnID }),
                          let candidate = LiveActivityStateMapper.candidate(
                            for: board, teamID: team.espnID, homeLeague: team.league, league: competition
                          )
                    else { continue }
                    seen.insert(board.gameID)
                    result.append(HomeLiveGame(
                        team: team,
                        info: candidate.info,
                        state: candidate.state,
                        favoriteIsHome: side.homeAway == "home",
                        game: seasons[team.id]?.first { $0.gameID == board.gameID }
                    ))
                }
            }
        }
        return result
    }

    /// Every story across the favorites' feeds, each story once (a story
    /// tagged with two favorites is in both feeds), as the first favorite
    /// in `teams` to list it.
    ///
    /// Dealt round-robin across the favorites rather than merged newest
    /// first: one busy feed (an NFL team's mid-season) otherwise filled the
    /// first screen on its own. Each favorite's stories keep their own
    /// newest-first order; each round — every favorite's newest story not
    /// yet dealt — goes newest first, so the freshest story leads. No cap
    /// here: Home's section shows the first few fresh ones (`homeNews`) and
    /// the rest behind "More News".
    static func headlines(teams: [TeamRef], articles: [TeamRef.ID: [News]]) -> [HomeHeadline] {
        var seen: Set<String> = []
        var feeds: [[HomeHeadline]] = []
        for team in teams {
            let own = (articles[team.id] ?? [])
                .filter { seen.insert($0.id).inserted }
                .map { HomeHeadline(team: team, article: $0) }
                .sorted { $0.article.publishedAt > $1.article.publishedAt }
            if !own.isEmpty {
                feeds.append(own)
            }
        }

        var dealt: [HomeHeadline] = []
        let rounds = feeds.map(\.count).max() ?? 0
        for round in 0..<rounds {
            // Each favorite's story this round, by its place in `feeds`,
            // which breaks a tie in favorites order.
            let hand: [(order: Int, headline: HomeHeadline)] = feeds.indices.compactMap { order in
                feeds[order].indices.contains(round) ? (order: order, headline: feeds[order][round]) : nil
            }
            dealt += hand
                .sorted { first, second in
                    let a = first.headline.article.publishedAt
                    let b = second.headline.article.publishedAt
                    return a == b ? first.order < second.order : a > b
                }
                .map(\.headline)
        }
        return dealt
    }

    /// The most stories Home's news section shows before "More News".
    static let homeNewsLimit = 5

    /// How old a story can be and still be one of those (H5): older ones
    /// wait in More News.
    static let homeNewsMaxAge: TimeInterval = 3 * 24 * 60 * 60

    /// Home's news section from the dealt feed (`headlines`): its first
    /// `homeNewsLimit` stories no older than `homeNewsMaxAge` at `now`,
    /// still in turn across the favorites — each favorite's stories are
    /// newest first, so skipping the old ones keeps the deal — and the
    /// rest, in the feed's order, for More News.
    static func homeNews(_ headlines: [HomeHeadline], now: Date) -> HomeNewsSelection {
        let earliest = now.addingTimeInterval(-homeNewsMaxAge)
        var shown: [HomeHeadline] = []
        var more: [HomeHeadline] = []
        var holdsOlderStories = false
        for headline in headlines {
            let isFresh = headline.article.publishedAt >= earliest
            if isFresh && shown.count < homeNewsLimit {
                shown.append(headline)
            } else {
                more.append(headline)
                if !isFresh {
                    holdsOlderStories = true
                }
            }
        }
        return HomeNewsSelection(shown: shown, more: more, holdsOlderStories: holdsOlderStories)
    }

    /// The feed's stories about `team`, for the news filter's chip: those
    /// dealt as its own, and those another favorite listed first that are
    /// tagged with it too, so a story two favorites share is under both.
    static func headlines(_ headlines: [HomeHeadline], about team: TeamRef) -> [HomeHeadline] {
        headlines.filter { headline in
            headline.team.id == team.id
                || (headline.team.league == team.league
                    && headline.article.teams.contains { $0.espnID == team.espnID })
        }
    }

    /// One state for a section fed by every favorite's feed (P1's
    /// `SectionLoadState`): loaded once any feed has answered, failed only
    /// when every one failed, loading otherwise. Nothing to load is loaded.
    static func combinedState(_ states: [SectionLoadState]) -> SectionLoadState {
        if states.isEmpty || states.contains(.loaded) { return .loaded }
        if states.allSatisfy({ $0 == .failed }) { return .failed }
        return .loading
    }

    // MARK: This Week

    /// How many days back This Week's strip reaches: last weekend's results
    /// from midweek, without a fortnight of strip to scroll.
    static let weekDaysBack = 3

    /// How many days ahead the strip reaches, as Upcoming did.
    static let weekDaysAhead = 7

    /// The strip's days, `weekDaysBack` before `now`'s day to
    /// `weekDaysAhead` after it, each with the favorites' games that day in
    /// start order: played, under way and still to come alike. A day
    /// without games is in the strip too, empty. Games without a date are
    /// left out.
    static func week(_ games: [HomeGame], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [HomeWeekDay] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: [HomeGame]] = [:]
        for entry in games where !entry.game.date.isEmpty {
            byDay[calendar.startOfDay(for: entry.game.dateAsDate), default: []].append(entry)
        }
        return (-weekDaysBack...weekDaysAhead).compactMap { offset -> HomeWeekDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let day = calendar.startOfDay(for: date)
            let games = (byDay[day] ?? []).sorted { $0.game.dateAsDate < $1.game.dateAsDate }
            return HomeWeekDay(date: day, games: games)
        }
    }

    /// The day the strip opens on: today if it has games, else the next
    /// day that does, else the latest past day that does, else today.
    static func defaultDay(in week: [HomeWeekDay], now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let today = calendar.startOfDay(for: now)
        if week.contains(where: { $0.date == today && !$0.games.isEmpty }) {
            return today
        }
        if let next = week.first(where: { $0.date > today && !$0.games.isEmpty }) {
            return next.date
        }
        if let last = week.last(where: { $0.date < today && !$0.games.isEmpty }) {
            return last.date
        }
        return today
    }

    /// `"2026-09-27"`: a day's key in `calendar`, for its button's
    /// accessibility identifier (`home.week.day.<key>`).
    static func dayKey(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func padded(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(parts.year, 4))-\(padded(parts.month, 2))-\(padded(parts.day, 2))"
    }

    // MARK: Hero

    /// How long after it was played a result can still lead Home's hero.
    static let featuredResultWindow: TimeInterval = 24 * 60 * 60

    /// The game Home's hero features: the first favorite's game under way
    /// that its schedule lists, else the soonest game still to come across
    /// the favorites, else the latest result in the last
    /// `featuredResultWindow`; `nil` with none of those.
    static func featured(live: [HomeLiveGame], games: [HomeGame], now: Date) -> HomeFeaturedGame? {
        for game in live {
            if let scheduled = game.game {
                return HomeFeaturedGame(entry: HomeGame(team: game.team, game: scheduled), phase: .live, live: game)
            }
        }

        let next = games
            .filter { entry in
                let game = entry.game
                return !game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty && game.dateAsDate >= now
            }
            .min { $0.game.dateAsDate < $1.game.dateAsDate }
        if let next {
            return HomeFeaturedGame(entry: next, phase: .upcoming, live: nil)
        }

        let earliest = now.addingTimeInterval(-featuredResultWindow)
        let last = games
            .filter { entry in
                let game = entry.game
                return game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty
                    && game.dateAsDate >= earliest && game.dateAsDate <= now
            }
            .max { $0.game.dateAsDate < $1.game.dateAsDate }
        return last.map { HomeFeaturedGame(entry: $0, phase: .final, live: nil) }
    }

    // MARK: My Teams

    /// How long after its last game a team's card still shows that result
    /// rather than "Season over".
    static let lastResultWindow: TimeInterval = 14 * 24 * 60 * 60

    /// A favorite's card in My Teams: the team page header's record (from
    /// the standings row once the schedule is empty), standing and form,
    /// its poll rank, and its season's state — the game under way, the next
    /// game, the last result, or the season over or yet to start.
    ///
    /// - Parameter games: the favorite's season; `nil` while it loads.
    static func teamSummary(
        team: TeamRef,
        games: [Game]?,
        live: HomeLiveGame?,
        standings: Standings?,
        pollRanks: PollRanks,
        now: Date
    ) -> HomeTeamSummary {
        let season = games ?? []
        let rule = team.league.descriptor.recordRule
        let header = TeamHeaderSummary(
            team: team,
            games: season,
            nextGame: getNextGame(schedule: season, pastDatesCountAsPlayed: rule.usesDateForNextGame, now: now),
            record: scheduleRecord(games: season, league: team.league, now: now),
            standings: standings
        )
        return HomeTeamSummary(
            team: team,
            header: header,
            pollRank: pollRanks.rank(of: team.espnID),
            status: status(of: team, games: games, live: live, header: header, now: now)
        )
    }

    private static func status(
        of team: TeamRef,
        games: [Game]?,
        live: HomeLiveGame?,
        header: TeamHeaderSummary,
        now: Date
    ) -> HomeTeamSummary.Status {
        if let live {
            let own = live.favoriteIsHome ? live.state.homeScore : live.state.awayScore
            let other = live.favoriteIsHome ? live.state.awayScore : live.state.homeScore
            let opponent = live.favoriteIsHome ? live.info.awayName : live.info.homeName
            return .live("Live \(live.favoriteIsHome ? "vs" : "at") \(opponent) · \(own)–\(other)")
        }
        guard let games else { return .loading }

        let next = games
            .filter { game in
                !game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty && game.dateAsDate >= now
            }
            .min { $0.dateAsDate < $1.dateAsDate }
        if let next {
            let start = GameCardContent.startLabel(for: next.dateAsDate, now: now)
            return .next("Next \(side(of: next)) \(opponentName(next)) · \(start)")
        }

        let last = games
            .filter { game in
                game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty && game.dateAsDate <= now
            }
            .max { $0.dateAsDate < $1.dateAsDate }
        if let last, now.timeIntervalSince(last.dateAsDate) <= lastResultWindow {
            var parts = ["Last"]
            switch GameCardContent.outcome(of: last) {
            case .win: parts.append("W")
            case .loss: parts.append("L")
            case .draw: parts.append("D")
            case nil: break
            }
            if !last.score.isEmpty, !last.opponentScore.isEmpty {
                parts.append("\(last.score)–\(last.opponentScore)")
            }
            parts.append("\(side(of: last)) \(opponentName(last))")
            return .last(parts.joined(separator: " "))
        }
        if last != nil || header.record != nil {
            return .seasonOver
        }
        return .preseason
    }

    /// "vs" at home or at a neutral site, "at" away.
    private static func side(of game: Game) -> String {
        game.gameHome || game.neutralSite ? "vs" : "at"
    }

    private static func opponentName(_ game: Game) -> String {
        game.opponent.isEmpty ? "TBD" : game.opponent
    }

    // MARK: Standings

    /// How many rows a favorite's slice of its table holds.
    static let standingsSliceCount = 3

    /// The favorite's row in the table that holds it with the row above and
    /// the row below — the top three for the leader, the foot three for the
    /// last — or `nil` where no table holds it (a poll it isn't ranked in).
    static func standingsSlice(team: TeamRef, standings: Standings) -> HomeStandingsSlice? {
        guard let group = standings.group(containing: team.espnID),
              let index = group.entries.firstIndex(where: { $0.teamID == team.espnID })
        else { return nil }
        let count = group.entries.count
        let lower = max(0, min(index - 1, count - standingsSliceCount))
        let upper = min(count, lower + standingsSliceCount)
        let rows = (lower..<upper).map { position -> HomeStandingsSlice.Row in
            let entry = group.entries[position]
            return HomeStandingsSlice.Row(
                rank: entry.rank ?? position + 1,
                entry: entry,
                isFollowed: entry.teamID == team.espnID
            )
        }
        return HomeStandingsSlice(
            team: team,
            kind: standings.kind,
            title: group.title(kind: standings.kind, leagueName: team.league.descriptor.displayName),
            rows: rows
        )
    }

    // MARK: Top performers

    /// Each favorite's leader on the first of its boards that lists one, in
    /// favorites order; none for a favorite with no leaders yet.
    static func performers(teams: [TeamRef], leaders: [TeamRef.ID: [LeaderBoard]]) -> [HomePerformer] {
        teams.compactMap { team -> HomePerformer? in
            for board in leaders[team.id] ?? [] {
                if let row = board.rows.first {
                    return HomePerformer(team: team, board: board, row: row)
                }
            }
            return nil
        }
    }
}

// MARK: - Around Your Leagues

extension HomeFeed {
    /// How many days of results This Week reaches back.
    static let leagueDaysBack = 2

    /// How many days ahead This Week reaches, as This Week's strip does.
    static let leagueDaysAhead = 7

    /// How often today's board is fetched while a game on it is under way
    /// or about to start: the scoreboards' own minute.
    static let leagueLiveInterval: TimeInterval = 60

    /// How often today's board is fetched while nothing on it is live, for
    /// fixtures moved or added.
    static let leagueQuietInterval: TimeInterval = 10 * 60

    /// How long the week's span is trusted: today's board, laid over it,
    /// carries the live scores.
    static let leagueWeekInterval: TimeInterval = 30 * 60

    /// How long after a failed request the same one is tried again.
    static let leagueRetryInterval: TimeInterval = 2 * 60

    /// How soon before its start a game makes today's board live.
    static let leagueStartWindow: TimeInterval = 15 * 60

    /// How long after its start a game that never left "pre" keeps the
    /// board live: past that, the board's listing is stale, not late.
    static let leagueOverdueWindow: TimeInterval = 4 * 60 * 60

    /// The days of US Eastern time ESPN files the boards under.
    private static let easternCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    /// The scoreboard days `span` covers at `now`: today's
    /// (`scoreboardDay(for:)`), or each from `leagueDaysBack` before it to
    /// `leagueDaysAhead` after.
    static func leagueDays(span: HomeLeagueSpan, now: Date) -> [String] {
        guard span == .week else { return [scoreboardDay(for: now)] }
        let calendar = easternCalendar
        return (-leagueDaysBack...leagueDaysAhead).map { offset in
            scoreboardDay(for: calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        }
    }

    /// The requests for `league`'s board over `span`, one a day. ESPN's
    /// range form (`dates=20261023-20261101`) answers 400 for every league,
    /// and its month form comes back short or empty for college boards, so
    /// This Week asks a day at a time, as every other board in the app does.
    static func leagueURLs(_ league: LeagueID, span: HomeLeagueSpan, settings: HomeLeaguesSettings, now: Date) -> [String] {
        leagueDays(span: span, now: now).map { day in
            league.roundupScoreboardURL(dates: day, rankedOnly: settings.ranksOnly(league))
        }
    }

    /// The key `league`'s board over `span` is filed under, fetched and
    /// failed by: today's one request, or the week's together.
    static func leagueURL(_ league: LeagueID, span: HomeLeagueSpan, settings: HomeLeaguesSettings, now: Date) -> String {
        leagueURLs(league, span: span, settings: settings, now: now).joined(separator: " ")
    }

    /// `urls`' boards as one, all asked for at once: each game once, in
    /// `urls`' order. Any request failing fails the lot, so the last board
    /// stays on screen and the whole span is tried again.
    static func loadBoards(
        _ urls: [String],
        policy: FeedCachePolicy,
        load: @escaping @Sendable (String, FeedCachePolicy) async -> Result<[ScoreboardGame], NetworkError>
    ) async -> Result<[ScoreboardGame], NetworkError> {
        if urls.count == 1 { return await load(urls[0], policy) }
        let answers = await withTaskGroup(
            of: (Int, Result<[ScoreboardGame], NetworkError>).self,
            returning: [Result<[ScoreboardGame], NetworkError>?].self
        ) { group in
            for (index, url) in urls.enumerated() {
                group.addTask { (index, await load(url, policy)) }
            }
            var answers = [Result<[ScoreboardGame], NetworkError>?](repeating: nil, count: urls.count)
            for await (index, answer) in group {
                answers[index] = answer
            }
            return answers
        }
        var seen: Set<String> = []
        var games: [ScoreboardGame] = []
        for answer in answers {
            switch answer {
            case .success(let day)?:
                for game in day where seen.insert(game.gameID).inserted {
                    games.append(game)
                }
            case .failure(let error)?:
                return .failure(error)
            case nil:
                return .failure(.cancelled)
            }
        }
        return .success(games)
    }

    /// How long today's board stays fresh: `leagueLiveInterval` while a game
    /// on it is under way, or due to start within `leagueStartWindow` (or
    /// late starting, up to `leagueOverdueWindow`); `leagueQuietInterval`
    /// otherwise.
    static func todayBoardInterval(_ games: [ScoreboardGame], now: Date) -> TimeInterval {
        let busy = games.contains { game in
            if game.state == "in" { return true }
            guard game.state == "pre", let start = game.startDate else { return false }
            let untilStart = start.timeIntervalSince(now)
            return untilStart <= leagueStartWindow && untilStart >= -leagueOverdueWindow
        }
        return busy ? leagueLiveInterval : leagueQuietInterval
    }

    /// Whether `span`'s board, last fetched as `fetch`, is due: never
    /// fetched for `url`, or older than its interval. A request that failed
    /// waits `leagueRetryInterval` before it is tried again.
    static func leagueBoardIsDue(
        fetch: HomeLeagueFetch?,
        url: String,
        span: HomeLeagueSpan,
        failedAt: Date?,
        now: Date
    ) -> Bool {
        if let failedAt, now.timeIntervalSince(failedAt) < leagueRetryInterval { return false }
        guard let fetch, fetch.url == url else { return true }
        let interval = span == .today ? todayBoardInterval(fetch.games, now: now) : leagueWeekInterval
        return now.timeIntervalSince(fetch.fetchedAt) >= interval
    }

    /// `base` with each game `fresher` also lists replaced by its reading
    /// there, and, with `addingNew`, `fresher`'s other games added after.
    static func overlay(_ base: [ScoreboardGame], with fresher: [ScoreboardGame], addingNew: Bool) -> [ScoreboardGame] {
        guard !fresher.isEmpty else { return base }
        var byID: [String: ScoreboardGame] = [:]
        for game in fresher where byID[game.gameID] == nil {
            byID[game.gameID] = game
        }
        var seen: Set<String> = []
        var merged = base.map { game -> ScoreboardGame in
            seen.insert(game.gameID)
            return byID[game.gameID] ?? game
        }
        if addingNew {
            for game in fresher where seen.insert(game.gameID).inserted {
                merged.append(game)
            }
        }
        return merged
    }

    /// `league`'s games on `boards` as its block lists them, each once:
    /// only two-team games; the favorites' own only with
    /// `includesMyTeams`; only those with a ranked side where Top 25 only
    /// applies (`ranksOnly`). Live first by start, then those to come by
    /// start, then the rest newest first — results and games called off.
    static func leagueGames(
        _ boards: [ScoreboardGame],
        league: LeagueID,
        favorites: [TeamRef],
        settings: HomeLeaguesSettings
    ) -> [HomeLeagueGame] {
        let followed = favorites.filter { $0.league == league }
        var seen: Set<String> = []
        var games: [HomeLeagueGame] = []
        for board in boards where !board.gameID.isEmpty {
            guard let sides = board.awayAndHome, seen.insert(board.gameID).inserted else { continue }
            let homeFavorite = followed.first { $0.espnID == sides.home.teamID }
            let awayFavorite = followed.first { $0.espnID == sides.away.teamID }
            let favorite = homeFavorite ?? awayFavorite
            if favorite != nil && !settings.includesMyTeams { continue }
            if settings.ranksOnly(league) {
                let ranked = board.teams[sides.home.teamID]?.rank != nil || board.teams[sides.away.teamID]?.rank != nil
                guard ranked else { continue }
            }
            let phase: HomeLeagueGame.Phase = switch board.state {
            case "in": .live
            case "post": .final
            default: .upcoming
            }
            games.append(HomeLeagueGame(
                league: league,
                board: board,
                away: sides.away,
                home: sides.home,
                awayTeam: awayFavorite ?? standIn(sides.away.teamID, on: board, league: league),
                homeTeam: homeFavorite ?? standIn(sides.home.teamID, on: board, league: league),
                favorite: favorite,
                phase: phase
            ))
        }
        return games.sorted(by: leagueOrder)
    }

    /// The block's order: by phase; live and upcoming soonest first, the
    /// rest newest first; a game with no start after those with one; then
    /// by id, so a refresh never reshuffles a tie.
    private static func leagueOrder(_ a: HomeLeagueGame, _ b: HomeLeagueGame) -> Bool {
        if a.phase != b.phase { return a.phase < b.phase }
        switch (a.board.startDate, b.board.startDate) {
        case let (first?, second?) where first != second:
            return a.phase == .final ? first > second : first < second
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return a.id < b.id
        }
    }

    /// A team the reader doesn't follow, as the board names it, for its
    /// crest (`TeamLogo`, which falls back to a monogram) and the game
    /// sheet's colours.
    static func standIn(_ teamID: String, on board: ScoreboardGame, league: LeagueID) -> TeamRef {
        let team = board.teams[teamID] ?? ScoreboardTeam()
        let short = team.rowName.isEmpty ? (board.teamNames[teamID] ?? "") : team.rowName
        return TeamRef(
            league: league,
            espnID: teamID,
            displayName: team.displayName.isEmpty ? short : team.displayName,
            shortName: short,
            abbreviation: team.abbreviation,
            location: team.location,
            colorHex: team.colorHex,
            alternateColorHex: team.alternateColorHex,
            logoURL: team.logoURL,
            logoDarkURL: nil,
            logoAsset: nil
        )
    }

    /// The games a block shows: the first `limit`, unless the reader has
    /// expanded it, and how many wait behind its "See all" row.
    static func cappedLeagueGames(
        _ games: [HomeLeagueGame],
        limit: HomeLeaguesGameLimit,
        expanded: Bool
    ) -> (shown: [HomeLeagueGame], hiddenCount: Int) {
        guard !expanded, let count = limit.count, games.count > count else { return (games, 0) }
        return (Array(games.prefix(count)), games.count - count)
    }

    /// Whether Around Your Leagues shows at all: while any block loads or
    /// has failed, or once any has a game. Every board answered with
    /// nothing hides it, rather than a card of empty lines.
    static func leaguesSectionShows(_ blocks: [HomeLeagueBlock]) -> Bool {
        blocks.contains { $0.state != .loaded || !$0.games.isEmpty }
    }

    /// The blocks Around Your Leagues draws as blocks, and the leagues it
    /// only names on one closing line ("No games today: MLB · NCAA Men's
    /// Basketball") because their boards answered with nothing. A league
    /// still loading, or whose board failed, keeps its block, for its
    /// placeholder or its Retry.
    static func partitionLeagueBlocks(_ blocks: [HomeLeagueBlock]) -> (shown: [HomeLeagueBlock], quiet: [HomeLeagueBlock]) {
        let quiet = blocks.filter { $0.state == .loaded && $0.games.isEmpty }
        let shown = blocks.filter { !($0.state == .loaded && $0.games.isEmpty) }
        return (shown, quiet)
    }

    /// What `entry`'s row says of its state at `now`.
    ///
    /// - Live: "Live", over the stage as the hero and the alerts read it
    ///   ("4th Quarter · 0:48", `LiveActivityStateMapper`), else the board's
    ///   own words.
    /// - To come: its start ("Today 7:00 PM", "Sun 8:25 PM",
    ///   `GameCardContent.startLabel`), over the broadcast.
    /// - Over: "Final" (or the board's "Final/OT"), or "Canceled" or
    ///   "Postponed", over its day when that wasn't today.
    static func leagueStatus(of entry: HomeLeagueGame, now: Date, calendar: Calendar = .autoupdatingCurrent) -> HomeLeagueStatus {
        let board = entry.board
        let detail = board.statusDetail.trimmingCharacters(in: .whitespaces)
        switch entry.phase {
        case .live:
            let stage: String
            if board.halftime {
                stage = "Halftime"
            } else if let state = LiveActivityStateMapper.state(of: board, league: entry.league), state.phase == .live {
                stage = state.stage
            } else {
                stage = detail
            }
            return HomeLeagueStatus(primary: "Live", detail: stage.isEmpty ? nil : stage, isLive: true)
        case .upcoming:
            let broadcast = board.broadcast.isEmpty ? nil : board.broadcast
            guard let start = board.startDate else {
                return HomeLeagueStatus(primary: detail.isEmpty ? "Scheduled" : detail, detail: broadcast, isLive: false)
            }
            return HomeLeagueStatus(
                primary: GameCardContent.startLabel(for: start, now: now, calendar: calendar),
                detail: broadcast,
                isLive: false
            )
        case .final:
            let primary: String
            if board.postponed {
                primary = "Postponed"
            } else if board.cancelled || !board.completed {
                primary = "Canceled"
            } else if detail.hasPrefix("Final") {
                primary = detail
            } else {
                primary = "Final"
            }
            var day: String?
            if let start = board.startDate, !calendar.isDate(start, inSameDayAs: now) {
                day = start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
            }
            return HomeLeagueStatus(primary: primary, detail: day, isLive: false)
        }
    }

    /// The game a league row opens, as its sheet (`GameDetailView`) takes
    /// one: from the favorite's side where the reader follows a team in
    /// it, else the home side's, built from the board — the sheet loads
    /// the rest from the game's summary. A favorite's game its season lists
    /// opens that listing instead (`HomeViewModel.sheetEntry(for:)`).
    static func sheetEntry(for entry: HomeLeagueGame, now: Date) -> HomeGame {
        let board = entry.board
        let followsAway = entry.favorite != nil && entry.favorite?.espnID == entry.away.teamID
        let side = followsAway ? entry.away : entry.home
        let other = followsAway ? entry.home : entry.away
        let team = followsAway ? entry.awayTeam : entry.homeTeam
        let opponent = followsAway ? entry.homeTeam : entry.awayTeam
        let start = board.startDate
        let game = Game(
            eventID: board.gameID,
            team: team.shortName,
            opponent: opponent.shortName,
            opponentID: other.teamID,
            score: entry.shownScore(side) ?? "",
            opponentScore: entry.shownScore(other) ?? "",
            time: start.map { $0.formatted(date: .omitted, time: .shortened) } ?? "",
            date: start.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "",
            dateAsDate: start ?? now,
            opponentLogo: opponent.logoURL?.absoluteString ?? "",
            channel: board.broadcast.isEmpty ? "TBD" : board.broadcast,
            location: board.venue,
            gameHome: side.homeAway == "home",
            gameID: board.gameID,
            pointer: 0,
            gameWin: board.completed && (board.teams[side.teamID]?.winner ?? false),
            completed: board.completed,
            competitionName: board.name,
            cancelled: board.cancelled,
            postponed: board.postponed,
            gameClock: board.clock,
            gamePeriod: "\(board.period)",
            gameHalftime: board.halftime,
            competition: entry.league,
            neutralSite: board.neutralSite
        )
        return HomeGame(team: team, game: game)
    }
}

extension HomeLeagueGame {
    /// "Arsenal 2, Chelsea 1, Final": away first, as the row reads; "Eagles
    /// at Bears, Mon 8:15 PM, ESPN" before a score; ranks spoken, and the
    /// reader's own team said.
    func accessibilityLabel(now: Date) -> String {
        func side(_ competitor: ScoreboardCompetitor, _ team: TeamRef) -> String {
            var name = team.shortName
            if let rank = rank(of: competitor) {
                name = "number \(rank) \(name)"
            }
            if let score = shownScore(competitor) {
                name += " \(score)"
            }
            return name
        }
        let status = HomeFeed.leagueStatus(of: self, now: now)
        var parts = hasScore
            ? [side(away, awayTeam), side(home, homeTeam)]
            : ["\(side(away, awayTeam)) at \(side(home, homeTeam))"]
        parts.append(status.primary)
        if let detail = status.detail {
            parts.append(detail)
        }
        if let favorite {
            parts.append("your team, \(favorite.shortName)")
        }
        return parts.joined(separator: ", ")
    }
}

/// One answer from the tables Home loads per favorite (`HomeViewModel
/// .loadTables()`).
private enum HomeTableAnswer: Sendable {
    case standings(LeagueID, Standings?)
    case leaders(TeamRef.ID, [LeaderBoard])
    case pollRanks(LeagueID, PollRanks)
}

/// Everything Home shows, gathered from what the app already loads and a
/// few shared stores: no feed of its own but the favorites' news feeds,
/// which the team pages read too.
///
/// - The hero's live game reads the league scoreboards
///   `LeagueScoreboardCenter` polls for every favorite while the app is in
///   the foreground — the same app-owned feed score alerts and Live
///   Activities read.
/// - The hero, My Teams' records and form, and This Week read the
///   favorites' seasons the center loaded to know which boards to poll
///   (`followedSeason(of:)`).
/// - Standings, poll ranks and top performers come from the hour-long
///   shared stores (`StandingsStore`, `PollRankStore`, `TeamLeadersStore`),
///   asked once when the favorites change and again on pull to refresh: no
///   poll of their own.
/// - The news feed merges each favorite's ESPN news feed
///   (`downloadNewsData`, up to the 25 stories `TeamRef.newsURL` asks
///   for), fetched again once `TeamFeed.news.timeToLive` has run out, as a
///   team page's is.
/// - Around Your Leagues reads each favorite league's ESPN scoreboard:
///   today's, fetched each minute only while a game on it is live or about
///   to start and every ten minutes otherwise, and for This Week one
///   request for the whole span (`?dates=YYYYMMDD-YYYYMMDD`) every half
///   hour, kept in the `FeedCache`. Only while Home is on screen with the
///   section shown; the center's own polling is left as it was.
///
/// One cadence (`refreshInterval`, the center's): the clock moves on for
/// the hero and This Week, and any news feed past its time-to-live is
/// fetched. The scoreboards redraw Home whenever the center's polls change
/// them.
@MainActor
@Observable
final class HomeViewModel {
    /// How often Home looks again at the clock and its news feeds: the
    /// scoreboards' own once a minute.
    static let refreshInterval: Duration = .seconds(60)

    /// The favorites, in favorites order.
    private(set) var teams: [TeamRef] = []

    /// The moment the hero and This Week are worked out against, moved on
    /// each `refreshInterval`.
    private(set) var now: Date

    private var articles: [TeamRef.ID: [News]] = [:]
    private var newsStates: [TeamRef.ID: SectionLoadState] = [:]
    @ObservationIgnored private var newsLoadedAt: [TeamRef.ID: Date] = [:]
    /// When each favorite's news on screen was fetched, for the feeds served
    /// from the `FeedCache` (R-4).
    private var newsCachedAt: [TeamRef.ID: Date] = [:]

    /// Each favorite league's standings, from `StandingsStore`.
    private var standingsByLeague: [LeagueID: Standings] = [:]
    /// Each favorite's leader boards, one leader deep, from
    /// `TeamLeadersStore`.
    private var leadersByTeam: [TeamRef.ID: [LeaderBoard]] = [:]
    /// Each favorite college league's poll, from `PollRankStore`.
    private var pollRanksByLeague: [LeagueID: PollRanks] = [:]

    /// Whether the standings, polls and leaders have answered since the
    /// favorites last changed: their sections' placeholders until then.
    private(set) var tablesState: SectionLoadState = .loading

    /// Around Your Leagues' settings and whether it shows, as Home's view
    /// last passed them (`configureLeagues(_:)`). Until then nothing is
    /// fetched for it.
    private(set) var leaguesConfiguration = HomeLeaguesConfiguration.unset
    /// Each favorite league's board for today, polled live while Home is on
    /// screen (`HomeFeed.todayBoardInterval`).
    private var leagueToday: [LeagueID: HomeLeagueFetch] = [:]
    /// Each favorite league's board for the week's span, while the scope is
    /// This Week.
    private var leagueWeek: [LeagueID: HomeLeagueFetch] = [:]
    /// When each league request last failed, by URL: its block's error
    /// until it answers, and its retry's pacing.
    private var leagueFailures: [String: Date] = [:]
    /// The league requests under way, so the minute's refresh and a change
    /// of settings never ask twice.
    @ObservationIgnored private var leagueLoadsInFlight: Set<String> = []

    private let scoreboards: LeagueScoreboardCenter
    private let loadNews: @Sendable (String) async -> Result<[News], NetworkError>
    private let loadStandings: @Sendable (LeagueID) async -> Standings?
    private let loadLeaders: @Sendable (TeamRef) async -> [LeaderBoard]
    private let loadPollRanks: @Sendable (LeagueID) async -> PollRanks
    private let loadLeagueBoard: @Sendable (String, FeedCachePolicy) async -> Result<[ScoreboardGame], NetworkError>
    private let clock: @MainActor () -> Date

    init(
        scoreboards: LeagueScoreboardCenter = .shared,
        loadNews: @escaping @Sendable (String) async -> Result<[News], NetworkError> = { await downloadNewsData(queryURL: $0) },
        loadStandings: @escaping @Sendable (LeagueID) async -> Standings? = { await StandingsStore.shared.standings(for: $0) },
        loadLeaders: @escaping @Sendable (TeamRef) async -> [LeaderBoard] = { await TeamLeadersStore.shared.leaders(for: $0) },
        loadPollRanks: @escaping @Sendable (LeagueID) async -> PollRanks = { await PollRankStore.shared.ranks(for: $0) },
        loadLeagueBoard: @escaping @Sendable (String, FeedCachePolicy) async -> Result<[ScoreboardGame], NetworkError> = { url, policy in
            await HTTPClient.shared.fetch(url, cache: policy).map(empty: []) { parseScoreboard(from: $0).games }
        },
        now: @escaping @MainActor () -> Date = { HomeViewModel.launchNow() }
    ) {
        self.scoreboards = scoreboards
        self.loadNews = loadNews
        self.loadStandings = loadStandings
        self.loadLeaders = loadLeaders
        self.loadPollRanks = loadPollRanks
        self.loadLeagueBoard = loadLeagueBoard
        self.clock = now
        self.now = now()
    }

    /// The launch-environment key a UI test pins Home's clock with, in
    /// seconds since 1970, so This Week reads the same against the fixtures
    /// (`MYTEAMS_FIXTURES_DIR`) whenever the tests run. Read by Debug
    /// builds only.
    static let launchNowKey = "MYTEAMS_HOME_NOW"

    /// The time, or in a Debug build the moment `launchNowKey` pins.
    static func launchNow() -> Date {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[launchNowKey], let seconds = TimeInterval(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        #endif
        return Date()
    }

    // MARK: Sections

    /// Each favorite's season, where the center has loaded it.
    private var seasons: [TeamRef.ID: [Game]] {
        var seasons: [TeamRef.ID: [Game]] = [:]
        for team in teams {
            if case .loaded(let games) = scoreboards.followedSeason(of: team.id) {
                seasons[team.id] = games
            }
        }
        return seasons
    }

    /// Whether any favorite's season is still on its first load: the hero
    /// and This Week hold placeholders rather than saying there are no
    /// games.
    var seasonsLoading: Bool {
        teams.contains { scoreboards.followedSeason(of: $0.id) == .loading }
    }

    /// Every favorite's games, each once.
    private var allGames: [HomeGame] {
        HomeFeed.games(teams: teams, seasons: seasons)
    }

    var liveGames: [HomeLiveGame] {
        HomeFeed.liveGames(teams: teams, boards: scoreboards.games, seasons: seasons)
    }

    /// The hero's game (`HomeFeed.featured`).
    var featured: HomeFeaturedGame? {
        let seasons = seasons
        return HomeFeed.featured(
            live: HomeFeed.liveGames(teams: teams, boards: scoreboards.games, seasons: seasons),
            games: HomeFeed.games(teams: teams, seasons: seasons),
            now: now
        )
    }

    /// This Week's days (`HomeFeed.week`).
    var week: [HomeWeekDay] {
        HomeFeed.week(allGames, now: now)
    }

    /// My Teams' cards, one per favorite, in favorites order.
    var teamSummaries: [HomeTeamSummary] {
        let seasons = seasons
        let live = HomeFeed.liveGames(teams: teams, boards: scoreboards.games, seasons: seasons)
        return teams.map { team -> HomeTeamSummary in
            // A season that failed to load reads as an empty one: the
            // card falls back to the standings' record.
            let games: [Game]?
            switch scoreboards.followedSeason(of: team.id) {
            case .loaded(let loaded): games = loaded
            case .failed: games = []
            case .loading: games = nil
            }
            return HomeFeed.teamSummary(
                team: team,
                games: games,
                live: live.first { $0.team.id == team.id },
                standings: standingsByLeague[team.league],
                pollRanks: pollRanksByLeague[team.league] ?? .empty,
                now: now
            )
        }
    }

    /// The standings snapshot's slices, one per favorite a table holds.
    var standingsSlices: [HomeStandingsSlice] {
        teams.compactMap { team -> HomeStandingsSlice? in
            standingsByLeague[team.league].flatMap { HomeFeed.standingsSlice(team: team, standings: $0) }
        }
    }

    /// Top Performers' cards (`HomeFeed.performers`).
    var performers: [HomePerformer] {
        HomeFeed.performers(teams: teams, leaders: leadersByTeam)
    }

    var headlines: [HomeHeadline] {
        HomeFeed.headlines(teams: teams, articles: articles)
    }

    var headlinesState: SectionLoadState {
        HomeFeed.combinedState(teams.map { newsStates[$0.id] ?? .loading })
    }

    /// When the oldest news feed on screen was fetched, when any came from
    /// the `FeedCache` because the network could not be reached; `nil` when
    /// every one is the network's own. For an `UpdatedCaption`.
    var headlinesCachedAt: Date? {
        teams.compactMap { newsCachedAt[$0.id] }.min()
    }

    // MARK: Around Your Leagues

    /// The favorites' leagues, each once, in favorites order.
    var leagues: [LeagueID] {
        HomeLeaguesSettings.favoriteLeagues(teamIDs: teams.map(\.id))
    }

    /// Around Your Leagues' blocks: one per favorite league the reader
    /// hasn't switched off, its games for the scope. This Week's span has
    /// today's board laid over it, for the live scores; and where the
    /// center is polling a league for a favorite's game, its reading of the
    /// games both list, so a row and the hero never disagree. None while
    /// the section is hidden.
    var leagueBlocks: [HomeLeagueBlock] {
        let configuration = leaguesConfiguration
        guard configuration.isShown else { return [] }
        let settings = configuration.settings
        let current = now
        let polling = scoreboards.pollingLeagues
        return leagues.filter { settings.shows($0) }.map { league -> HomeLeagueBlock in
            let todayURL = HomeFeed.leagueURL(league, span: .today, settings: settings, now: current)
            let today = leagueToday[league].flatMap { $0.url == todayURL ? $0 : nil }
            var boards: [ScoreboardGame] = []
            let state: SectionLoadState
            switch settings.scope {
            case .today:
                boards = today?.games ?? []
                state = today != nil ? .loaded : (leagueFailures[todayURL] != nil ? .failed : .loading)
            case .week:
                let weekURL = HomeFeed.leagueURL(league, span: .week, settings: settings, now: current)
                let week = leagueWeek[league].flatMap { $0.url == weekURL ? $0 : nil }
                boards = HomeFeed.overlay(week?.games ?? [], with: today?.games ?? [], addingNew: true)
                if week != nil {
                    state = .loaded
                } else if leagueFailures[weekURL] != nil {
                    // Today's games at least, where today's board answered.
                    state = today != nil ? .loaded : .failed
                } else {
                    state = .loading
                }
            }
            if polling.contains(league) {
                boards = HomeFeed.overlay(boards, with: scoreboards.games[league] ?? [], addingNew: false)
            }
            return HomeLeagueBlock(
                league: league,
                games: HomeFeed.leagueGames(boards, league: league, favorites: teams, settings: settings),
                state: state
            )
        }
    }

    /// The game a league row opens: the favorite's listing where its season
    /// has the game, so the sheet reads as This Week's does; else the game
    /// as the board has it (`HomeFeed.sheetEntry(for:now:)`).
    func sheetEntry(for entry: HomeLeagueGame) -> HomeGame {
        if let favorite = entry.favorite,
           let scheduled = seasons[favorite.id]?.first(where: { $0.gameID == entry.id }) {
            return HomeGame(team: favorite, game: scheduled)
        }
        return HomeFeed.sheetEntry(for: entry, now: now)
    }

    /// Takes the view's settings for Around Your Leagues and fetches what
    /// they newly call for: a scope switched to This Week, a league
    /// switched on. Called whenever they change, and as Home appears.
    func configureLeagues(_ configuration: HomeLeaguesConfiguration) async {
        leaguesConfiguration = configuration
        await refreshLeagueBoards(force: false)
    }

    /// A block's Retry: every failed league request again, at once.
    func retryLeagueBoards() async {
        leagueFailures = [:]
        await refreshLeagueBoards(force: false)
    }

    /// Fetches the league boards that are due (`HomeFeed.leagueBoardIsDue`)
    /// — every one when `force`d — for the leagues shown: today's for each,
    /// and the week's span too while the scope is This Week, a request a
    /// day. Every request at once. Nothing while the section is
    /// hidden, and nothing once Home is off screen: only `run`'s minute and
    /// the view's changes call this.
    private func refreshLeagueBoards(force: Bool) async {
        let configuration = leaguesConfiguration
        guard configuration.isShown else { return }
        let settings = configuration.settings
        let current = now
        // Boards of leagues no longer followed go.
        let followed = Set(leagues)
        if leagueToday.keys.contains(where: { !followed.contains($0) }) {
            leagueToday = leagueToday.filter { followed.contains($0.key) }
        }
        if leagueWeek.keys.contains(where: { !followed.contains($0) }) {
            leagueWeek = leagueWeek.filter { followed.contains($0.key) }
        }

        let spans: [HomeLeagueSpan] = settings.scope == .week ? [.today, .week] : [.today]
        var wanted: Set<String> = []
        var pending: [(league: LeagueID, span: HomeLeagueSpan, url: String, urls: [String], policy: FeedCachePolicy)] = []
        for league in leagues where settings.shows(league) {
            for span in spans {
                let urls = HomeFeed.leagueURLs(league, span: span, settings: settings, now: current)
                let url = urls.joined(separator: " ")
                wanted.insert(url)
                let fetch = span == .today ? leagueToday[league] : leagueWeek[league]
                guard !leagueLoadsInFlight.contains(url),
                      force || HomeFeed.leagueBoardIsDue(
                        fetch: fetch, url: url, span: span, failedAt: leagueFailures[url], now: current
                      )
                else { continue }
                // Today's is asked of the network each time, the cache only
                // standing in offline; the week's span is read from the
                // cache while it is fresh, unless the reader pulled.
                let policy: FeedCachePolicy = span == .week && !force
                    ? .preferCache(maxAge: HomeFeed.leagueWeekInterval)
                    : .persist
                pending.append((league: league, span: span, url: url, urls: urls, policy: policy))
            }
        }
        // Failures of requests no longer made (yesterday's, another scope's)
        // are forgotten.
        if leagueFailures.keys.contains(where: { !wanted.contains($0) }) {
            leagueFailures = leagueFailures.filter { wanted.contains($0.key) }
        }
        let requests = pending
        guard !requests.isEmpty else { return }
        for request in requests {
            leagueLoadsInFlight.insert(request.url)
        }

        let load = loadLeagueBoard
        let answers = await withTaskGroup(
            of: (Int, Result<[ScoreboardGame], NetworkError>).self,
            returning: [(Int, Result<[ScoreboardGame], NetworkError>)].self
        ) { group in
            for (index, request) in requests.enumerated() {
                let urls = request.urls
                let policy = request.policy
                group.addTask {
                    (index, await HomeFeed.loadBoards(urls, policy: policy, load: load))
                }
            }
            var answers: [(Int, Result<[ScoreboardGame], NetworkError>)] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }

        for (index, result) in answers {
            let request = requests[index]
            leagueLoadsInFlight.remove(request.url)
            switch result {
            case .success(let games):
                let fetch = HomeLeagueFetch(url: request.url, games: games, fetchedAt: clock())
                switch request.span {
                case .today: leagueToday[request.league] = fetch
                case .week: leagueWeek[request.league] = fetch
                }
                if leagueFailures[request.url] != nil {
                    leagueFailures[request.url] = nil
                }
            case .failure(let error):
                // Home went away mid-load: nothing to report.
                if case .cancelled = error { continue }
                // A failure keeps the last board on screen.
                leagueFailures[request.url] = clock()
            }
        }
    }

    /// `game`'s live score for `team` on the scoreboard, for a game that
    /// has got under way since the last `refreshInterval`.
    func liveScore(for game: Game, team: TeamRef) -> LiveGameScore? {
        shouldPollLiveScore(game: game, now: now) ? scoreboards.liveScore(for: game, team: team) : nil
    }

    // MARK: Loading

    /// Shows `teams`, then keeps Home current for as long as it is on
    /// screen: SwiftUI cancels the task when it goes. The tables are asked
    /// for once, alongside the first news load.
    func run(teams: [TeamRef]) async {
        self.teams = teams
        let ids = Set(teams.map(\.id))
        let leagues = Set(teams.map(\.league))
        articles = articles.filter { ids.contains($0.key) }
        newsStates = newsStates.filter { ids.contains($0.key) }
        newsLoadedAt = newsLoadedAt.filter { ids.contains($0.key) }
        newsCachedAt = newsCachedAt.filter { ids.contains($0.key) }
        standingsByLeague = standingsByLeague.filter { leagues.contains($0.key) }
        pollRanksByLeague = pollRanksByLeague.filter { leagues.contains($0.key) }
        leadersByTeam = leadersByTeam.filter { ids.contains($0.key) }
        // A favorite just followed shows its sections' placeholders until
        // its tables answer.
        if teams.contains(where: { leadersByTeam[$0.id] == nil }) {
            tablesState = .loading
        }

        async let tables: Void = loadTables()
        await keepCurrent()
        await tables
    }

    /// Moves the clock on and fetches the news feeds that are due, each
    /// `refreshInterval`, until cancelled.
    private func keepCurrent() async {
        while !Task.isCancelled {
            now = clock()
            async let leagues: Void = refreshLeagueBoards(force: false)
            await refreshNews(force: false)
            await leagues
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                return
            }
        }
    }

    /// Pull to refresh: every favorite's news again, whatever its age, any
    /// season that failed, and the tables (which the stores serve from the
    /// last hour's fetch). What is on screen stays until each answer
    /// arrives. The scoreboards keep their own minute.
    func refreshAll() async {
        now = clock()
        async let news: Void = refreshNews(force: true)
        async let schedules: Void = scoreboards.retryFailedSchedules()
        async let tables: Void = loadTables()
        async let leagues: Void = refreshLeagueBoards(force: true)
        _ = await (news, schedules, tables, leagues)
    }

    /// Retries the news feeds that failed.
    func reloadNews() async {
        await refreshNews(force: false)
    }

    /// Asks the shared stores for each favorite league's standings and
    /// poll, and each favorite's leaders, all at once. An answer that came
    /// back empty keeps what is already on screen.
    private func loadTables() async {
        let teams = teams
        guard !teams.isEmpty else {
            tablesState = .loaded
            return
        }
        var leagues: [LeagueID] = []
        for team in teams where !leagues.contains(team.league) {
            leagues.append(team.league)
        }

        let loadStandings = loadStandings
        let loadLeaders = loadLeaders
        let loadPollRanks = loadPollRanks
        let answers = await withTaskGroup(
            of: HomeTableAnswer.self,
            returning: [HomeTableAnswer].self
        ) { group in
            for league in leagues {
                group.addTask {
                    let standings = await loadStandings(league)
                    return HomeTableAnswer.standings(league, standings)
                }
                if league.isCollege {
                    group.addTask {
                        let ranks = await loadPollRanks(league)
                        return HomeTableAnswer.pollRanks(league, ranks)
                    }
                }
            }
            for team in teams {
                let id = team.id
                group.addTask {
                    let boards = await loadLeaders(team)
                    return HomeTableAnswer.leaders(id, boards)
                }
            }
            var answers: [HomeTableAnswer] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }

        for answer in answers {
            switch answer {
            case .standings(let league, let standings):
                if let standings {
                    standingsByLeague[league] = standings
                }
            case .leaders(let id, let boards):
                if !boards.isEmpty || leadersByTeam[id] == nil {
                    leadersByTeam[id] = boards
                }
            case .pollRanks(let league, let ranks):
                if !ranks.isEmpty || pollRanksByLeague[league] == nil {
                    pollRanksByLeague[league] = ranks
                }
            }
        }
        tablesState = .loaded
    }

    /// Fetches the favorites' news feeds that are due (`feedNeedsRefresh`):
    /// not loaded, failed, or past `TeamFeed.news.timeToLive`; all of them
    /// when `force`d.
    private func refreshNews(force: Bool) async {
        let current = clock()
        let due = teams.filter { team in
            force || feedNeedsRefresh(
                state: newsStates[team.id] ?? .loading,
                loadedAt: newsLoadedAt[team.id],
                timeToLive: TeamFeed.news.timeToLive,
                now: current
            )
        }
        guard !due.isEmpty else { return }

        // A feed that failed shows its placeholder again while it retries.
        for team in due where newsStates[team.id] == .failed {
            newsStates[team.id] = .loading
        }

        let load = loadNews
        let answers = await withTaskGroup(
            of: (TeamRef.ID, Result<[News], NetworkError>, Date?).self,
            returning: [(TeamRef.ID, Result<[News], NetworkError>, Date?)].self
        ) { group in
            for team in due {
                let id = team.id
                let url = team.newsURL
                group.addTask {
                    // Stored as it loads, and read back offline (R-4).
                    let (result, cachedAt) = await HTTPClient.withFeedCache(.persist) { await load(url) }
                    return (id, result, cachedAt)
                }
            }
            var answers: [(TeamRef.ID, Result<[News], NetworkError>, Date?)] = []
            for await answer in group {
                answers.append(answer)
            }
            return answers
        }

        for (id, result, cachedAt) in answers {
            apply(news: result, cachedAt: cachedAt, for: id)
        }
    }

    /// Publishes a news fetch. A failure keeps what is already on screen,
    /// and a cancelled fetch (Home went away mid-load) changes nothing, as
    /// on a team page (`TeamModel`). News served from the cache is shown but
    /// not counted as loaded, so the next `refreshInterval` asks again.
    private func apply(news result: Result<[News], NetworkError>, cachedAt: Date?, for id: TeamRef.ID) {
        switch result {
        case .success(let loaded):
            newsStates[id] = .loaded
            newsLoadedAt[id] = cachedAt == nil ? clock() : nil
            newsCachedAt[id] = cachedAt
            articles[id] = loaded
        case .failure(let error):
            if case .cancelled = error { return }
            if (articles[id] ?? []).isEmpty {
                newsStates[id] = .failed
            }
        }
    }
}
