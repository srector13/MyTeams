//
//  HomeFeedTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// What Home's sections show (`HomeFeed`, t_0b94af11): worked out from the
/// favorites' seasons, the league scoreboards and the news feeds the app
/// already loads.
@Suite("Home feed")
struct HomeFeedTests {
    /// Tuesday, Oct 6, 2026, 16:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_302_400)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let jayhawks = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")!
    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")!

    private func game(
        id: String,
        start: Date,
        opponent: String = "Raiders",
        opponentID: String = "13",
        completed: Bool = false,
        cancelled: Bool = false,
        win: Bool = false
    ) -> Game {
        Game(
            team: "Chiefs", opponent: opponent, opponentID: opponentID, score: completed ? "24" : "",
            opponentScore: completed ? "17" : "", time: "", date: "Oct 06, 2026", dateAsDate: start,
            opponentLogo: "", channel: "", location: "", gameHome: true, gameID: id, pointer: 0,
            gameWin: win, completed: completed, competitionName: "", cancelled: cancelled,
            postponed: false, gameClock: "", gamePeriod: "", gameHalftime: false
        )
    }

    private func article(_ title: String, hoursAgo: Double) -> News {
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return News(
            author: nil,
            title: title,
            articleDescription: nil,
            url: URL(string: "https://www.espn.com/" + slug)!,
            urlToImage: nil,
            publishedAt: Self.now.addingTimeInterval(-hoursAgo * 3600),
            content: nil,
            source: "ESPN"
        )
    }

    // MARK: Upcoming

    @Test("Upcoming groups the games still to start by day, each day in start order")
    func upcomingInStartOrder() {
        let late = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(4 * 3600)))
        let early = HomeGame(team: jayhawks, game: game(id: "2", start: Self.now.addingTimeInterval(3600)))
        let tomorrow = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(26 * 3600)))
        // Under way already: Live Now's, not Upcoming's.
        let started = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(-3600)))

        let days = HomeFeed.upcomingDays([late, tomorrow, started, early], now: Self.now, calendar: Self.calendar)
        #expect(days.map { $0.games.map(\.id) } == [["2", "1"], ["3"]])
        #expect(days.first?.date == Self.calendar.startOfDay(for: Self.now))
        #expect(days.last?.date == Self.calendar.startOfDay(for: Self.now.addingTimeInterval(86_400)))
    }

    @Test("A day without games starts Upcoming at tomorrow, seven days in and eight out")
    func upcomingWindow() {
        let tomorrow = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(26 * 3600)))
        let nextWeek = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(7 * 86_400)))
        let eightDays = HomeGame(team: chiefs, game: game(id: "5", start: Self.now.addingTimeInterval(8 * 86_400)))

        let days = HomeFeed.upcomingDays([eightDays, nextWeek, tomorrow], now: Self.now, calendar: Self.calendar)
        #expect(days.map { $0.games.map(\.id) } == [["3"], ["4"]])
        #expect(days.first?.date == Self.calendar.startOfDay(for: Self.now.addingTimeInterval(86_400)))

        #expect(HomeFeed.upcomingDays([eightDays], now: Self.now, calendar: Self.calendar).isEmpty)
    }

    // MARK: Results

    @Test("Recent Results are the last seven days' finished games, newest first")
    func resultsWindow() {
        let yesterday = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(-20 * 3600), completed: true, win: true))
        let lastNight = HomeGame(team: jayhawks, game: game(id: "2", start: Self.now.addingTimeInterval(-6 * 3600), completed: true))
        let lastWeek = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(-7 * 86_400), completed: true))
        let eightDays = HomeGame(team: chiefs, game: game(id: "6", start: Self.now.addingTimeInterval(-8 * 86_400), completed: true))
        let calledOff = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(-3 * 3600), completed: true, cancelled: true))
        let upcoming = HomeGame(team: chiefs, game: game(id: "5", start: Self.now.addingTimeInterval(3600)))

        let results = HomeFeed.results([yesterday, eightDays, lastWeek, calledOff, upcoming, lastNight], now: Self.now)
        #expect(results.map(\.id) == ["2", "1", "3"])
    }

    // MARK: Merging

    @Test("Two favorites playing each other are one game, the first favorite's")
    func sharedGameOnce() {
        let start = Self.now.addingTimeInterval(3600)
        let seasons = [
            chiefs.id: [game(id: "9", start: start)],
            jayhawks.id: [game(id: "9", start: start), game(id: "10", start: start)],
        ]
        let games = HomeFeed.games(teams: [chiefs, jayhawks], seasons: seasons)
        #expect(games.map(\.id) == ["9", "10"])
        #expect(games.first?.team == chiefs)
    }

    @Test("The news feed is every story across the favorites, dealt in turn, each once")
    func headlinesMerged() {
        let shared = article("Shared story", hoursAgo: 1)
        let articles = [
            chiefs.id: [shared, article("Chiefs two", hoursAgo: 5), article("Chiefs three", hoursAgo: 9)],
            jayhawks.id: [article("Kansas one", hoursAgo: 2), shared, article("Kansas three", hoursAgo: 3), article("Kansas four", hoursAgo: 30)],
        ]
        let headlines = HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles)
        // A round each: the shared story is the Chiefs' (first to list
        // it), each round newest first. Uncapped: the day-old "Kansas
        // four" is in too.
        #expect(headlines.map(\.article.title) == ["Shared story", "Kansas one", "Kansas three", "Chiefs two", "Chiefs three", "Kansas four"])
        #expect(headlines.first?.team == chiefs)
    }

    @Test("One busy feed doesn't fill the top of the news: the favorites take turns")
    func headlinesRoundRobin() {
        let articles = [
            // Out of order in the feed: each favorite's own stories still go
            // newest first.
            chiefs.id: [
                article("Chiefs two", hoursAgo: 2), article("Chiefs one", hoursAgo: 1),
                article("Chiefs three", hoursAgo: 3), article("Chiefs four", hoursAgo: 4),
            ],
            jayhawks.id: [article("Kansas one", hoursAgo: 10), article("Kansas two", hoursAgo: 20)],
        ]
        let headlines = HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles)
        #expect(headlines.map(\.article.title) == [
            "Chiefs one", "Kansas one",
            "Chiefs two", "Kansas two",
            "Chiefs three",
            "Chiefs four",
        ])
    }

    @Test("A round's stories at the same moment go in favorites order")
    func headlinesTieInFavoritesOrder() {
        let articles = [
            chiefs.id: [article("Chiefs one", hoursAgo: 1)],
            jayhawks.id: [article("Kansas one", hoursAgo: 1)],
        ]
        #expect(HomeFeed.headlines(teams: [jayhawks, chiefs], articles: articles).map(\.article.title) == ["Kansas one", "Chiefs one"])
        #expect(HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles).map(\.article.title) == ["Chiefs one", "Kansas one"])
    }

    @Test("Home's news shows five fresh stories in turn; older ones wait in More News")
    func homeNewsSelection() {
        let articles = [
            chiefs.id: [
                article("Chiefs one", hoursAgo: 1), article("Chiefs two", hoursAgo: 5),
                article("Chiefs three", hoursAgo: 30), article("Chiefs four", hoursAgo: 40),
                article("Chiefs old", hoursAgo: 80),
            ],
            jayhawks.id: [
                article("Kansas one", hoursAgo: 2), article("Kansas old", hoursAgo: 100),
                article("Kansas older", hoursAgo: 200),
            ],
        ]
        let feed = HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles)
        let news = HomeFeed.homeNews(feed, now: Self.now)

        // In turn across the favorites, the 100-hour-old Kansas story
        // skipped though it's dealt in the second round.
        #expect(news.shown.map(\.article.title) == ["Chiefs one", "Kansas one", "Chiefs two", "Chiefs three", "Chiefs four"])
        // Everything else, older stories included, in the feed's order.
        #expect(news.more.map(\.article.title) == ["Kansas old", "Kansas older", "Chiefs old"])
        #expect(news.holdsOlderStories)
        #expect(news.shown.count + news.more.count == feed.count)
    }

    @Test("Home's news shows nothing stale: a quiet week leaves every story in More News")
    func homeNewsAllOld() {
        let articles = [chiefs.id: [article("Chiefs old", hoursAgo: 73), article("Chiefs older", hoursAgo: 96)]]
        let news = HomeFeed.homeNews(HomeFeed.headlines(teams: [chiefs], articles: articles), now: Self.now)
        #expect(news.shown.isEmpty)
        #expect(news.more.map(\.article.title) == ["Chiefs old", "Chiefs older"])
        #expect(news.holdsOlderStories)

        // Three days to the hour is still fresh; fewer than five fresh
        // stories leave More News empty.
        let fresh = [chiefs.id: [article("Chiefs one", hoursAgo: 1), article("Chiefs edge", hoursAgo: 72)]]
        let few = HomeFeed.homeNews(HomeFeed.headlines(teams: [chiefs], articles: fresh), now: Self.now)
        #expect(few.shown.map(\.article.title) == ["Chiefs one", "Chiefs edge"])
        #expect(few.more.isEmpty)
        #expect(!few.holdsOlderStories)
    }

    // MARK: This Week

    @Test("This Week runs three days back to seven on, each day's games in start order")
    func weekStrip() {
        let late = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(4 * 3600)))
        let early = HomeGame(team: jayhawks, game: game(id: "2", start: Self.now.addingTimeInterval(-3 * 3600), completed: true))
        let threeBack = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(-3 * 86_400), completed: true))
        let fourBack = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(-4 * 86_400), completed: true))
        let sevenOn = HomeGame(team: chiefs, game: game(id: "5", start: Self.now.addingTimeInterval(7 * 86_400)))
        let eightOn = HomeGame(team: chiefs, game: game(id: "6", start: Self.now.addingTimeInterval(8 * 86_400)))

        let week = HomeFeed.week([late, eightOn, early, fourBack, sevenOn, threeBack], now: Self.now, calendar: Self.calendar)
        let today = Self.calendar.startOfDay(for: Self.now)
        #expect(week.count == 11)
        #expect(week.first?.date == today.addingTimeInterval(-3 * 86_400))
        #expect(week.last?.date == today.addingTimeInterval(7 * 86_400))
        #expect(week.first?.games.map(\.id) == ["3"])
        #expect(week.last?.games.map(\.id) == ["5"])
        // Played and to come alike, in start order.
        #expect(week.first(where: { $0.date == today })?.games.map(\.id) == ["2", "1"])
        #expect(!week.flatMap(\.games).contains(where: { $0.id == "4" || $0.id == "6" }))
    }

    @Test("This Week opens on today, else the next day with games, else the last one")
    func weekDefaultDay() {
        let today = Self.calendar.startOfDay(for: Self.now)
        let tomorrowGame = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(86_400)))
        let todayGame = HomeGame(team: chiefs, game: game(id: "2", start: Self.now.addingTimeInterval(3600)))
        let yesterdayGame = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(-86_400), completed: true))

        func opening(_ games: [HomeGame]) -> Date {
            HomeFeed.defaultDay(in: HomeFeed.week(games, now: Self.now, calendar: Self.calendar), now: Self.now, calendar: Self.calendar)
        }
        #expect(opening([tomorrowGame, todayGame, yesterdayGame]) == today)
        #expect(opening([tomorrowGame, yesterdayGame]) == today.addingTimeInterval(86_400))
        #expect(opening([yesterdayGame]) == today.addingTimeInterval(-86_400))
        #expect(opening([]) == today)
    }

    @Test("A day's key is its date in the calendar, zero-padded")
    func weekDayKey() {
        #expect(HomeFeed.dayKey(Self.now, calendar: Self.calendar) == "2026-10-06")
    }

    // MARK: Hero

    @Test("The hero features the soonest game to come, else a result from the last day")
    func featuredGame() {
        let soon = HomeGame(team: jayhawks, game: game(id: "1", start: Self.now.addingTimeInterval(3 * 3600)))
        let later = HomeGame(team: chiefs, game: game(id: "2", start: Self.now.addingTimeInterval(2 * 86_400)))
        let lastNight = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(-10 * 3600), completed: true, win: true))
        let lastWeek = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(-3 * 86_400), completed: true))

        let next = HomeFeed.featured(live: [], games: [later, lastNight, soon], now: Self.now)
        #expect(next?.id == "1")
        #expect(next?.phase == .upcoming)

        let result = HomeFeed.featured(live: [], games: [lastWeek, lastNight], now: Self.now)
        #expect(result?.id == "3")
        #expect(result?.phase == .final)

        #expect(HomeFeed.featured(live: [], games: [lastWeek], now: Self.now) == nil)
    }

    // MARK: My Teams

    @Test("A team's card says its next game, else its last result, else the season's state")
    func teamSummaryStatus() {
        let won = game(id: "1", start: Self.now.addingTimeInterval(-2 * 86_400), completed: true, win: true)
        let next = game(id: "2", start: Self.now.addingTimeInterval(26 * 3600), opponent: "Chargers")

        let midSeason = HomeFeed.teamSummary(team: chiefs, games: [won, next], live: nil, standings: nil, pollRanks: .empty, now: Self.now)
        guard case .next(let line) = midSeason.status else {
            Issue.record("Expected the next game, got \(midSeason.status)")
            return
        }
        #expect(line.hasPrefix("Next vs Chargers · "))
        #expect(midSeason.header.record == "1-0")
        #expect(midSeason.header.form == [.win])

        let over = HomeFeed.teamSummary(team: chiefs, games: [won], live: nil, standings: nil, pollRanks: .empty, now: Self.now)
        #expect(over.status == .last("Last W 24–17 vs Raiders"))

        let longOver = HomeFeed.teamSummary(
            team: chiefs, games: [won], live: nil, standings: nil, pollRanks: .empty,
            now: Self.now.addingTimeInterval(30 * 86_400)
        )
        #expect(longOver.status == .seasonOver)

        #expect(HomeFeed.teamSummary(team: chiefs, games: [], live: nil, standings: nil, pollRanks: .empty, now: Self.now).status == .preseason)
        #expect(HomeFeed.teamSummary(team: chiefs, games: nil, live: nil, standings: nil, pollRanks: .empty, now: Self.now).status == .loading)
    }

    @Test("A team's status shows once: with no record the header says it and the foot says what's next")
    func teamSummaryStatusOnce() {
        let preseason = HomeFeed.teamSummary(team: jayhawks, games: [], live: nil, standings: nil, pollRanks: .empty, now: Self.now)
        #expect(preseason.header.record == nil)
        #expect(preseason.headerStatusText == "Preseason")
        #expect(preseason.footText == HomeTeamSummary.nothingScheduledText)
        #expect(preseason.footText != preseason.headerStatusText)

        // With a record in the header, the foot keeps the season's state.
        let won = game(id: "1", start: Self.now.addingTimeInterval(-2 * 86_400), completed: true, win: true)
        let next = game(id: "2", start: Self.now.addingTimeInterval(26 * 3600), opponent: "Chargers")
        let midSeason = HomeFeed.teamSummary(team: chiefs, games: [won, next], live: nil, standings: nil, pollRanks: .empty, now: Self.now)
        #expect(midSeason.footText == midSeason.status.text)
        #expect(midSeason.footText.hasPrefix("Next vs Chargers"))
    }

    // MARK: Standings

    private func entry(_ id: String, rank: Int) -> StandingsEntry {
        StandingsEntry(
            teamID: id, name: "Team \(id)", shortName: "T\(id)", abbreviation: "T\(id)", logoURL: nil,
            record: Record(wins: 10 - rank, losses: rank, format: .winLoss),
            rank: rank, gamesBehind: "", conferenceRecord: "", goalDifference: "", streak: "W1",
            note: "", noteColorHex: "", clincher: ""
        )
    }

    @Test("A team's standings slice is its row and the rows either side, clamped at the ends")
    func standingsSlice() {
        let rows = ["1", "2", "3", "12", "5"].enumerated().map { entry($1, rank: $0 + 1) }
        let standings = Standings(
            kind: .records,
            seasonDisplayName: "2026",
            groups: [StandingsGroup(id: "afc-west", name: "AFC West", abbreviation: "AFCW", entries: rows)]
        )

        let middle = HomeFeed.standingsSlice(team: chiefs, standings: standings)
        #expect(middle?.rows.map(\.entry.teamID) == ["3", "12", "5"])
        #expect(middle?.rows.map(\.isFollowed) == [false, true, false])
        #expect(middle?.title == "AFC West")

        let leader = Standings(
            kind: .records,
            seasonDisplayName: "2026",
            groups: [StandingsGroup(id: "afc-west", name: "AFC West", abbreviation: "AFCW", entries: [entry("12", rank: 1)] + rows.prefix(3))]
        )
        #expect(HomeFeed.standingsSlice(team: chiefs, standings: leader)?.rows.map(\.entry.teamID) == ["12", "1", "2"])

        #expect(HomeFeed.standingsSlice(team: jayhawks, standings: standings) == nil)
    }

    // MARK: Layout

    @Test("Home's layout reads leniently: unknown values dropped, missing sections added shown")
    func sectionLayout() {
        #expect(HomeSectionLayout(storage: "") == .standard)
        #expect(HomeSectionLayout(storage: HomeSectionLayout.standard.storage) == .standard)

        // A section the string doesn't name goes in after the one it follows
        // by default (Top Performers after Standings, Around Your Leagues
        // after This Week), or last when that one isn't named either.
        let custom = HomeSectionLayout(storage: "news,-standings,bogus,week")
        #expect(custom.order == [.news, .standings, .performers, .week, .leagues, .myTeams])
        #expect(custom.hidden == [.standings])
        #expect(custom.visible == [.news, .performers, .week, .leagues, .myTeams])
        #expect(HomeSectionLayout(storage: custom.storage) == custom)

        let moved = HomeSectionLayout.standard.moving(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        #expect(moved.order.first == .news)
        #expect(HomeSectionLayout.standard.setting(.news, shown: false).visible.contains(.news) == false)
    }

    @Test("Around Your Leagues follows This Week by default and in a layout saved before it existed")
    func leaguesSectionPlacement() {
        #expect(HomeSectionLayout.standard.order == [.myTeams, .week, .leagues, .standings, .performers, .news])
        // A reader's reordered layout from before the section.
        let saved = HomeSectionLayout(storage: "week,myTeams,-standings,performers,news")
        #expect(saved.order == [.week, .leagues, .myTeams, .standings, .performers, .news])
        #expect(saved.visible.contains(.leagues))
        #expect(HomeSectionLayout(storage: "myTeams,-leagues,week").hidden == [.leagues])
        // Full width on an iPad, beneath the balanced columns.
        #expect(HomeSectionKind.leagues.regularColumn == .fullWidth)
        #expect(HomeSectionKind.leagues.title == "Around Your Leagues")
    }

    @Test("With no game live, upcoming or recent, Home is the news feed alone")
    func feedWithoutGames() {
        // A season wholly out of both windows, and no board under way.
        let seasons = [
            chiefs.id: [
                game(id: "1", start: Self.now.addingTimeInterval(-30 * 86_400), completed: true),
                game(id: "2", start: Self.now.addingTimeInterval(30 * 86_400)),
            ],
        ]
        let games = HomeFeed.games(teams: [chiefs, jayhawks], seasons: seasons)

        #expect(HomeFeed.liveGames(teams: [chiefs, jayhawks], boards: [:], seasons: seasons).isEmpty)
        #expect(HomeFeed.upcomingDays(games, now: Self.now, calendar: Self.calendar).isEmpty)
        #expect(HomeFeed.results(games, now: Self.now).isEmpty)

        let articles = [chiefs.id: [article("Chiefs one", hoursAgo: 1)], jayhawks.id: [article("Kansas one", hoursAgo: 2)]]
        let feed = HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles)
        #expect(feed.map(\.article.title) == ["Chiefs one", "Kansas one"])
    }

    // MARK: Live

    @Test("Live Now is the favorites' games under way on their boards, each once")
    func liveGamesFromBoards() {
        let live = ScoreboardGame(
            gameID: "77",
            state: "in",
            completed: false,
            competitors: [
                ScoreboardCompetitor(teamID: "2305", homeAway: "home", score: 41),
                ScoreboardCompetitor(teamID: "2306", homeAway: "away", score: 38),
            ],
            period: 2,
            teamNames: ["2305": "Kansas", "2306": "K-State"],
            clock: "4:12"
        )
        let over = ScoreboardGame(
            gameID: "78",
            state: "post",
            completed: true,
            competitors: [
                ScoreboardCompetitor(teamID: "2305", homeAway: "away", score: 70),
                ScoreboardCompetitor(teamID: "150", homeAway: "home", score: 66),
            ]
        )
        let scheduled = game(id: "77", start: Self.now.addingTimeInterval(-3600))
        let games = HomeFeed.liveGames(
            teams: [jayhawks, chiefs],
            boards: [.mensCollegeBasketball: [live, over]],
            seasons: [jayhawks.id: [scheduled]]
        )

        #expect(games.map(\.id) == ["77"])
        #expect(games.first?.favoriteIsHome == true)
        #expect(games.first?.state.homeScore == 41)
        #expect(games.first?.state.awayScore == 38)
        #expect(games.first?.state.phase == .live)
        #expect(games.first?.game == scheduled)
    }

    // MARK: Section state

    @Test("A section loads once any favorite's feed has answered, and fails only when all failed")
    func combinedState() {
        #expect(HomeFeed.combinedState([]) == .loaded)
        #expect(HomeFeed.combinedState([.loading, .failed]) == .loading)
        #expect(HomeFeed.combinedState([.failed, .loaded]) == .loaded)
        #expect(HomeFeed.combinedState([.failed, .failed]) == .failed)
    }
}

@Suite("Home iPad performer grid")
struct HomePerformerGridTests {
    @Test("Four performers make a 2 × 2, never 3 + 1; three or fewer sit in one row")
    func columns() {
        #expect(HomePerformerGrid.columns(for: 1) == 1)
        #expect(HomePerformerGrid.columns(for: 3) == 3)
        #expect(HomePerformerGrid.columns(for: 4) == 2)
        #expect(HomePerformerGrid.columns(for: 5) == 3)
        #expect(HomePerformerGrid.columns(for: 6) == 3)
    }
}

// MARK: - Around Your Leagues

/// Around Your Leagues (`HomeFeed.leagueGames` and the rest): which of a
/// league board's games a block lists, in what order, how many, how each
/// reads, and when a board is fetched again.
@Suite("Home Around Your Leagues")
struct HomeLeaguesTests {
    /// Tuesday, Oct 6, 2026, 16:00 UTC: noon in New York.
    static let now = Date(timeIntervalSince1970: 1_791_302_400)

    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")!
    private let jayhawks = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")!

    /// A two-team game on a board, `away` at `home`.
    private func board(
        _ id: String,
        state: String,
        start: TimeInterval?,
        away: (id: String, score: Int, rank: Int?) = ("1", 0, nil),
        home: (id: String, score: Int, rank: Int?) = ("2", 0, nil),
        completed: Bool? = nil,
        broadcast: String = ""
    ) -> ScoreboardGame {
        ScoreboardGame(
            gameID: id,
            state: state,
            completed: completed ?? (state == "post"),
            competitors: [
                ScoreboardCompetitor(teamID: home.id, homeAway: "home", score: home.score),
                ScoreboardCompetitor(teamID: away.id, homeAway: "away", score: away.score),
            ],
            startDate: start.map { Self.now.addingTimeInterval($0) },
            teams: [
                home.id: ScoreboardTeam(shortName: "Home \(home.id)", rank: home.rank, winner: home.score > away.score),
                away.id: ScoreboardTeam(shortName: "Away \(away.id)", rank: away.rank, winner: away.score > home.score),
            ],
            broadcast: broadcast
        )
    }

    private let hour: TimeInterval = 60 * 60

    @Test("Today asks for today's board; This Week for two days back to seven on, in Eastern days")
    func dates() {
        #expect(HomeFeed.leagueDates(scope: .today, now: Self.now) == "20261006")
        #expect(HomeFeed.leagueDates(scope: .week, now: Self.now) == "20261004-20261013")
        // 02:00 UTC is still the evening before in New York.
        let lateNight = Date(timeIntervalSince1970: 1_791_252_000)
        #expect(HomeFeed.leagueDates(scope: .today, now: lateNight) == "20261005")
        let site = "https://site.api.espn.com/apis/site/v2/sports"
        #expect(HomeFeed.leagueURL(.nfl, span: .week, settings: .standard, now: Self.now)
            == "\(site)/football/nfl/scoreboard?dates=20261004-20261013&limit=1000")
    }

    @Test("A block lists live games first, then those to come by start, then results newest first")
    func ordering() {
        let games = HomeFeed.leagueGames(
            [
                board("final-old", state: "post", start: -30 * hour),
                board("upcoming-late", state: "pre", start: 6 * hour),
                board("live-late", state: "in", start: -1 * hour),
                board("final-new", state: "post", start: -4 * hour),
                board("upcoming-soon", state: "pre", start: 2 * hour),
                board("live-early", state: "in", start: -2 * hour),
                board("upcoming-undated", state: "pre", start: nil),
                // Listed twice, as a range's day and today's board may.
                board("live-early", state: "in", start: -2 * hour),
            ],
            league: .nfl,
            favorites: [chiefs],
            settings: .standard
        )
        #expect(games.map(\.id) == [
            "live-early", "live-late", "upcoming-soon", "upcoming-late", "upcoming-undated", "final-new", "final-old",
        ])
        #expect(games.map(\.phase) == [.live, .live, .upcoming, .upcoming, .upcoming, .final, .final])
    }

    @Test("The favorites' own games are left out unless Include My Teams' Games is on, then marked")
    func favoritesGames() throws {
        let boards = [
            board("chiefs", state: "pre", start: hour, away: ("12", 0, nil), home: ("13", 0, nil)),
            board("other", state: "pre", start: 2 * hour),
        ]
        let without = HomeFeed.leagueGames(boards, league: .nfl, favorites: [chiefs], settings: .standard)
        #expect(without.map(\.id) == ["other"])
        #expect(without.first?.favorite == nil)

        var settings = HomeLeaguesSettings.standard
        settings.includesMyTeams = true
        let with = HomeFeed.leagueGames(boards, league: .nfl, favorites: [chiefs], settings: settings)
        #expect(with.map(\.id) == ["chiefs", "other"])
        let chiefsGame = try #require(with.first)
        #expect(chiefsGame.favorite == chiefs)
        // The favorite draws as itself, its opponent as the board names it.
        #expect(chiefsGame.awayTeam == chiefs)
        #expect(chiefsGame.homeTeam.shortName == "Home 13")
        #expect(chiefsGame.isFavorite(chiefsGame.away))
        #expect(!chiefsGame.isFavorite(chiefsGame.home))

        // A favorite in another league is no favorite here.
        let elsewhere = HomeFeed.leagueGames(boards, league: .nfl, favorites: [jayhawks], settings: .standard)
        #expect(elsewhere.map(\.id) == ["chiefs", "other"])
    }

    @Test("Top 25 only keeps a college game with a ranked side, and never filters a pro league")
    func rankedOnly() {
        let boards = [
            board("ranked-home", state: "pre", start: hour, home: ("2", 0, 7)),
            board("ranked-away", state: "pre", start: 2 * hour, away: ("1", 0, 25)),
            board("unranked", state: "pre", start: 3 * hour),
        ]
        let college = HomeFeed.leagueGames(boards, league: .collegeFootball, favorites: [], settings: .standard)
        #expect(college.map(\.id) == ["ranked-home", "ranked-away"])
        #expect(college.first?.rank(of: college[0].home) == 7)

        var everyone = HomeLeaguesSettings.standard
        everyone.rankedOnly = false
        #expect(HomeFeed.leagueGames(boards, league: .collegeFootball, favorites: [], settings: everyone).count == 3)
        #expect(HomeFeed.leagueGames(boards, league: .nfl, favorites: [], settings: .standard).count == 3)
    }

    @Test("A block shows its first few games until See All opens the rest")
    func capping() {
        let games = HomeFeed.leagueGames(
            (0..<7).map { board("g\($0)", state: "pre", start: TimeInterval($0 + 1) * hour) },
            league: .nfl,
            favorites: [],
            settings: .standard
        )
        let three = HomeFeed.cappedLeagueGames(games, limit: .three, expanded: false)
        #expect(three.shown.map(\.id) == ["g0", "g1", "g2"])
        #expect(three.hiddenCount == 4)
        #expect(HomeFeed.cappedLeagueGames(games, limit: .three, expanded: true).shown.count == 7)
        #expect(HomeFeed.cappedLeagueGames(games, limit: .all, expanded: false).hiddenCount == 0)
        #expect(HomeFeed.cappedLeagueGames(games, limit: .ten, expanded: false).shown.count == 7)
        #expect(HomeLeaguesGameLimit.all.count == nil)
        #expect(HomeLeaguesGameLimit.five.count == 5)
    }

    @Test("The section shows while a board loads, fails or has games, and goes when every one is empty")
    func sectionVisibility() {
        let game = HomeFeed.leagueGames([board("g", state: "pre", start: hour)], league: .nfl, favorites: [], settings: .standard)
        #expect(!HomeFeed.leaguesSectionShows([]))
        #expect(!HomeFeed.leaguesSectionShows([HomeLeagueBlock(league: .nfl, games: [], state: .loaded)]))
        #expect(HomeFeed.leaguesSectionShows([HomeLeagueBlock(league: .nfl, games: [], state: .loading)]))
        #expect(HomeFeed.leaguesSectionShows([HomeLeagueBlock(league: .nfl, games: [], state: .failed)]))
        #expect(HomeFeed.leaguesSectionShows([
            HomeLeagueBlock(league: .nfl, games: game, state: .loaded),
            HomeLeagueBlock(league: .mlb, games: [], state: .loaded),
        ]))
    }

    @Test("Leagues with no games fold into one closing line; loading and failed boards keep their blocks")
    func quietLeaguesFold() {
        let game = HomeFeed.leagueGames([board("g", state: "pre", start: hour)], league: .nfl, favorites: [], settings: .standard)
        let parts = HomeFeed.partitionLeagueBlocks([
            HomeLeagueBlock(league: .nfl, games: game, state: .loaded),
            HomeLeagueBlock(league: .mlb, games: [], state: .loaded),
            HomeLeagueBlock(league: .nba, games: [], state: .loading),
            HomeLeagueBlock(league: .nhl, games: [], state: .failed),
        ])
        #expect(parts.shown.map(\.league) == [.nfl, .nba, .nhl])
        #expect(parts.quiet.map(\.league) == [.mlb])
    }

    @Test("Today's board is polled each minute only while a game on it is live or about to start")
    func pollingCadence() {
        let quiet = [board("later", state: "pre", start: 3 * hour), board("done", state: "post", start: -5 * hour)]
        #expect(HomeFeed.todayBoardInterval(quiet, now: Self.now) == HomeFeed.leagueQuietInterval)
        #expect(HomeFeed.todayBoardInterval(quiet + [board("on", state: "in", start: -hour)], now: Self.now) == HomeFeed.leagueLiveInterval)
        #expect(HomeFeed.todayBoardInterval([board("soon", state: "pre", start: 10 * 60)], now: Self.now) == HomeFeed.leagueLiveInterval)
        // A start long past that never came is a stale listing, not a game.
        #expect(HomeFeed.todayBoardInterval([board("stale", state: "pre", start: -5 * hour)], now: Self.now) == HomeFeed.leagueQuietInterval)

        let url = "today"
        let fresh = HomeLeagueFetch(url: url, games: quiet, fetchedAt: Self.now.addingTimeInterval(-60))
        #expect(HomeFeed.leagueBoardIsDue(fetch: nil, url: url, span: .today, failedAt: nil, now: Self.now))
        #expect(!HomeFeed.leagueBoardIsDue(fetch: fresh, url: url, span: .today, failedAt: nil, now: Self.now))
        // A new day, or Top 25 switched, is another request.
        #expect(HomeFeed.leagueBoardIsDue(fetch: fresh, url: "tomorrow", span: .today, failedAt: nil, now: Self.now))
        #expect(HomeFeed.leagueBoardIsDue(
            fetch: fresh, url: url, span: .today, failedAt: nil,
            now: Self.now.addingTimeInterval(HomeFeed.leagueQuietInterval)
        ))
        // The week's span keeps half an hour.
        let week = HomeLeagueFetch(url: url, games: [], fetchedAt: Self.now.addingTimeInterval(-20 * 60))
        #expect(!HomeFeed.leagueBoardIsDue(fetch: week, url: url, span: .week, failedAt: nil, now: Self.now))
        // A failure waits before it's asked again.
        #expect(!HomeFeed.leagueBoardIsDue(fetch: nil, url: url, span: .today, failedAt: Self.now.addingTimeInterval(-30), now: Self.now))
        #expect(HomeFeed.leagueBoardIsDue(
            fetch: nil, url: url, span: .today,
            failedAt: Self.now.addingTimeInterval(-HomeFeed.leagueRetryInterval), now: Self.now
        ))
    }

    @Test("Today's board lays its live readings over the week's span, and adds what the span lacks")
    func overlay() {
        let week = [board("a", state: "pre", start: hour), board("b", state: "post", start: -30 * hour)]
        let today = [board("a", state: "in", start: hour, away: ("1", 7, nil)), board("c", state: "pre", start: 2 * hour)]
        let merged = HomeFeed.overlay(week, with: today, addingNew: true)
        #expect(merged.map(\.gameID) == ["a", "b", "c"])
        #expect(merged.first?.state == "in")
        #expect(HomeFeed.overlay(week, with: today, addingNew: false).map(\.gameID) == ["a", "b"])
        #expect(HomeFeed.overlay(week, with: [], addingNew: true) == week)
    }

    @Test("A row reads as the game stands: live with its stage, to come with its start, over as Final")
    func status() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        var settings = HomeLeaguesSettings.standard
        settings.includesMyTeams = true
        let games = HomeFeed.leagueGames(nfl.games, league: .nfl, favorites: [chiefs], settings: settings)
        // Live first, then the two finals, the later start first.
        #expect(games.map(\.id) == ["401872962", "401872961", "401872952"])

        let sunday = try #require(parseGameDate("2026-09-27T23:00Z"))
        let live = HomeFeed.leagueStatus(of: games[0], now: sunday)
        #expect(live == HomeLeagueStatus(primary: "Live", detail: "4th Quarter · 0:48", isLive: true))
        #expect(games[0].accessibilityLabel(now: sunday) == "Rams 26, Broncos 23, Live, 4th Quarter · 0:48")

        let result = HomeFeed.leagueStatus(of: games[2], now: sunday)
        #expect(result.primary == "Final")
        #expect(!result.isLive)
        #expect(games[2].isWinner(games[2].away))
        #expect(!games[2].isWinner(games[2].home))
        #expect(games[2].accessibilityLabel(now: sunday).hasPrefix("Chiefs 24, Dolphins 10, Final"))
        #expect(games[2].accessibilityLabel(now: sunday).hasSuffix("your team, Chiefs"))

        // Monday night's, the day before: its start and its networks.
        let monday = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260928"))
        let upcoming = try #require(HomeFeed.leagueGames(monday.games, league: .nfl, favorites: [], settings: .standard).first)
        let pregame = HomeFeed.leagueStatus(of: upcoming, now: sunday)
        #expect(pregame.detail == "ESPN/ABC")
        #expect(!pregame.isLive)
        #expect(upcoming.shownScore(upcoming.home) == nil)
        #expect(upcoming.accessibilityLabel(now: sunday).hasPrefix("Eagles at Bears, "))

        // A cancelled game reads as one, without its 0–0.
        let mlb = parseScoreboard(from: try Fixture.json("mlb_scoreboard_20260927"))
        let cancelled = try #require(HomeFeed.leagueGames(mlb.games, league: .mlb, favorites: [], settings: .standard).first { $0.id == "401817103" })
        #expect(HomeFeed.leagueStatus(of: cancelled, now: sunday).primary == "Canceled")
        #expect(cancelled.shownScore(cancelled.home) == nil)
    }

    @Test("A league row opens a game sheet from the favorite's side, else the home side's")
    func sheetEntry() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        var settings = HomeLeaguesSettings.standard
        settings.includesMyTeams = true
        let games = HomeFeed.leagueGames(nfl.games, league: .nfl, favorites: [chiefs], settings: settings)

        // Rams at Broncos, followed by neither: the Broncos' side.
        let neutral = HomeFeed.sheetEntry(for: try #require(games.first { $0.id == "401872962" }), now: Self.now)
        #expect(neutral.team.espnID == "7")
        #expect(neutral.team.shortName == "Broncos")
        #expect(neutral.team.colorHex == "0a2343")
        #expect(neutral.game.gameID == "401872962")
        #expect(neutral.game.opponent == "Rams")
        #expect(neutral.game.opponentID == "14")
        #expect(neutral.game.gameHome)
        #expect(neutral.game.score == "23")
        #expect(neutral.game.opponentScore == "26")
        #expect(!neutral.game.completed)
        #expect(neutral.game.channel == "NBC")
        #expect(neutral.game.location == "Empower Field at Mile High")
        #expect(neutral.game.competition == .nfl)
        #expect(!neutral.game.date.isEmpty)

        // The Chiefs' win at Miami: theirs.
        let followed = HomeFeed.sheetEntry(for: try #require(games.first { $0.id == "401872952" }), now: Self.now)
        #expect(followed.team == chiefs)
        #expect(!followed.game.gameHome)
        #expect(followed.game.score == "24")
        #expect(followed.game.opponentScore == "10")
        #expect(followed.game.gameWin)
        #expect(followed.game.completed)
    }
}
