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

    private let jayhawks = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")
    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")

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

    // MARK: Today

    @Test("Today lists today's games in start order")
    func todayInStartOrder() {
        let late = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(4 * 3600)))
        let early = HomeGame(team: jayhawks, game: game(id: "2", start: Self.now.addingTimeInterval(3600)))
        let tomorrow = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(26 * 3600)))

        let day = HomeFeed.upcomingDay([late, tomorrow, early], now: Self.now, calendar: Self.calendar)
        #expect(day?.isToday == true)
        #expect(day?.games.map(\.id) == ["2", "1"])
    }

    @Test("A day without games shows tomorrow's, and neither day none")
    func tomorrowInstead() {
        let tomorrow = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(26 * 3600)))
        let nextWeek = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(7 * 86_400)))

        let day = HomeFeed.upcomingDay([nextWeek, tomorrow], now: Self.now, calendar: Self.calendar)
        #expect(day?.isToday == false)
        #expect(day?.games.map(\.id) == ["3"])

        #expect(HomeFeed.upcomingDay([nextWeek], now: Self.now, calendar: Self.calendar) == nil)
    }

    // MARK: Results

    @Test("Results are the last 48 hours' finished games, newest first")
    func resultsWindow() {
        let yesterday = HomeGame(team: chiefs, game: game(id: "1", start: Self.now.addingTimeInterval(-20 * 3600), completed: true, win: true))
        let lastNight = HomeGame(team: jayhawks, game: game(id: "2", start: Self.now.addingTimeInterval(-6 * 3600), completed: true))
        let lastWeek = HomeGame(team: chiefs, game: game(id: "3", start: Self.now.addingTimeInterval(-7 * 86_400), completed: true))
        let calledOff = HomeGame(team: chiefs, game: game(id: "4", start: Self.now.addingTimeInterval(-3 * 3600), completed: true, cancelled: true))
        let upcoming = HomeGame(team: chiefs, game: game(id: "5", start: Self.now.addingTimeInterval(3600)))

        let results = HomeFeed.results([yesterday, lastWeek, calledOff, upcoming, lastNight], now: Self.now)
        #expect(results.map(\.id) == ["2", "1"])
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

    @Test("Headlines are the newest five across the favorites, each story once")
    func headlinesMerged() {
        let shared = article("Shared story", hoursAgo: 1)
        let articles = [
            chiefs.id: [shared, article("Chiefs two", hoursAgo: 5), article("Chiefs three", hoursAgo: 9)],
            jayhawks.id: [article("Kansas one", hoursAgo: 2), shared, article("Kansas three", hoursAgo: 3), article("Kansas four", hoursAgo: 30)],
        ]
        let headlines = HomeFeed.headlines(teams: [chiefs, jayhawks], articles: articles)
        #expect(headlines.map(\.article.title) == ["Shared story", "Kansas one", "Kansas three", "Chiefs two", "Chiefs three"])
        #expect(headlines.first?.team == chiefs)
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
