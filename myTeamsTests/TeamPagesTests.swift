//
//  TeamPagesTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// `Home` mounts only the selected team's page; `TeamPages` is what lets a
/// page come back with its data and scroll position.
@Suite("Team pages")
struct TeamPagesTests {
    private let loadRoster: @Sendable (TeamRef) async -> Result<[BasketballPlayer], NetworkError> = { _ in
        .success([])
    }

    @Test("A team's model outlives its page, one per team")
    @MainActor
    func modelsOutliveThePage() {
        let pages = TeamPages()
        let jayhawks = pages.model(for: .jayhawks, loadRoster: loadRoster)

        // Remounting the page finds the same model, and so its loaded data.
        #expect(pages.model(for: .jayhawks, loadRoster: loadRoster) === jayhawks)
        #expect(pages.model(for: .chiefs, loadRoster: loadRoster) !== jayhawks)
        #expect(jayhawks.team == .jayhawks)
    }

    @Test("Scroll offsets are kept per team")
    @MainActor
    func scrollOffsets() {
        let pages = TeamPages()
        #expect(pages.scrollOffset(for: TeamRef.jayhawks.id) == 0)

        pages.setScrollOffset(420, for: TeamRef.jayhawks.id)
        pages.setScrollOffset(80, for: TeamRef.chiefs.id)
        #expect(pages.scrollOffset(for: TeamRef.jayhawks.id) == 420)
        #expect(pages.scrollOffset(for: TeamRef.chiefs.id) == 80)
    }

    @Test("An unfollowed team's model and offset are dropped")
    @MainActor
    func retainFavorites() {
        let pages = TeamPages()
        let jayhawks = pages.model(for: .jayhawks, loadRoster: loadRoster)
        let chiefs = pages.model(for: .chiefs, loadRoster: loadRoster)
        pages.setScrollOffset(420, for: TeamRef.jayhawks.id)

        pages.retain([TeamRef.chiefs.id])

        #expect(pages.model(for: .chiefs, loadRoster: loadRoster) === chiefs)
        #expect(pages.model(for: .jayhawks, loadRoster: loadRoster) !== jayhawks)
        #expect(pages.scrollOffset(for: TeamRef.jayhawks.id) == 0)
    }
}

// MARK: - Feed refresh (A-3, C-1)

/// Counts each feed's requests, answering every one with an empty success —
/// and the schedule with one game, finished once `finished` is set.
private actor TeamFeeds {
    private(set) var roster = 0
    private(set) var schedule = 0
    private(set) var news = 0
    private(set) var standings = 0
    private(set) var leaders = 0
    private var finished = false

    func setFinished(_ finished: Bool) {
        self.finished = finished
    }

    func fetchRoster() -> Result<[BasketballPlayer], NetworkError> {
        roster += 1
        return .success([])
    }

    func fetchSchedule() -> Result<[Game], NetworkError> {
        schedule += 1
        return .success([feedGame(completed: finished)])
    }

    func fetchNews() -> Result<[News], NetworkError> {
        news += 1
        return .success([])
    }

    func fetchStandings() -> Result<Standings, NetworkError> {
        standings += 1
        return .success(.empty)
    }

    func fetchLeaders() -> Result<StatLeaders, NetworkError> {
        leaders += 1
        return .success(.empty)
    }

    /// Requests so far, as (roster, schedule, news, standings, leaders).
    var counts: [Int] { [roster, schedule, news, standings, leaders] }
}

/// The schedule's one game, live or finished.
private func feedGame(completed: Bool) -> Game {
    Game(
        eventID: "401",
        team: "Kansas",
        opponent: "Duke",
        score: completed ? "80" : "40",
        opponentScore: completed ? "70" : "38",
        time: "",
        date: "",
        dateAsDate: Date(timeIntervalSince1970: 1_790_000_000),
        opponentLogo: "",
        channel: "",
        location: "",
        gameHome: true,
        gameID: "401",
        pointer: 0,
        gameWin: completed,
        completed: completed,
        competitionName: "",
        cancelled: false,
        postponed: false,
        gameClock: "",
        gamePeriod: "",
        gameHalftime: false
    )
}

/// A clock the test moves by hand.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_790_000_000)

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }
}

@Suite("Team pages: feed refresh")
@MainActor
struct TeamFeedRefreshTests {
    /// Every feed is a seam here, and so is the clock: nothing touches the
    /// network.
    private func makeModel(_ feeds: TeamFeeds, clock: TestClock) -> TeamModel<BasketballPlayer> {
        TeamModel(
            team: .jayhawks,
            newsURL: "",
            loadRoster: { _ in await feeds.fetchRoster() },
            loadStandings: { _ in await feeds.fetchStandings() },
            loadLeaders: { _ in await feeds.fetchLeaders() },
            loadNews: { _ in await feeds.fetchNews() },
            loadSchedule: { _ in await feeds.fetchSchedule() },
            now: { clock.now }
        )
    }

    @Test("A feed is due when unloaded, failed, stale or past its time-to-live")
    func ttlDecision() {
        let loadedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let ttl = TeamFeed.news.timeToLive
        #expect(ttl == 15 * 60)

        // Fresh: not refetched.
        #expect(!feedNeedsRefresh(state: .loaded, loadedAt: loadedAt, timeToLive: ttl, now: loadedAt))
        #expect(!feedNeedsRefresh(state: .loaded, loadedAt: loadedAt, timeToLive: ttl, now: loadedAt.addingTimeInterval(14 * 60)))
        // Past its time-to-live: refetched.
        #expect(feedNeedsRefresh(state: .loaded, loadedAt: loadedAt, timeToLive: ttl, now: loadedAt.addingTimeInterval(15 * 60)))
        #expect(feedNeedsRefresh(state: .loaded, loadedAt: loadedAt, timeToLive: ttl, now: loadedAt.addingTimeInterval(3 * 86_400)))
        // Marked stale, never loaded, or failed: refetched.
        #expect(feedNeedsRefresh(state: .loaded, loadedAt: nil, timeToLive: ttl, now: loadedAt))
        #expect(feedNeedsRefresh(state: .loading, loadedAt: nil, timeToLive: ttl, now: loadedAt))
        #expect(feedNeedsRefresh(state: .failed, loadedAt: loadedAt, timeToLive: ttl, now: loadedAt))
    }

    @Test("A game going final is a game that was unfinished and now is not")
    func wentFinal() {
        let live = feedGame(completed: false)
        let finished = feedGame(completed: true)
        #expect(gameWentFinal(from: [live], to: [finished]))
        #expect(!gameWentFinal(from: [live], to: [live]))
        #expect(!gameWentFinal(from: [finished], to: [finished]))
        // The first load has nothing to compare with.
        #expect(!gameWentFinal(from: [], to: [finished]))
    }

    @Test("A fresh feed is not refetched; one past its time-to-live is")
    func refetchesExpiredFeeds() async {
        let feeds = TeamFeeds()
        let clock = TestClock()
        let model = makeModel(feeds, clock: clock)

        await model.refreshExpiredFeeds()
        #expect(await feeds.counts == [1, 0, 1, 1, 1])
        #expect(TeamFeed.allCases.allSatisfy { !model.needsRefresh($0) })

        // The page comes back five minutes later: nothing is asked again.
        clock.advance(minutes: 5)
        await model.refreshExpiredFeeds()
        #expect(await feeds.counts == [1, 0, 1, 1, 1])
        await model.loadLeadersIfNeeded()
        #expect(await feeds.leaders == 1)

        // Sixteen minutes on, every feed has gone stale.
        clock.advance(minutes: 11)
        #expect(TeamFeed.allCases.allSatisfy { model.needsRefresh($0) })
        await model.refreshExpiredFeeds()
        #expect(await feeds.counts == [2, 0, 2, 2, 2])
    }

    @Test("A followed game going final refetches news, standings and leaders at once")
    func gameFinalInvalidates() async {
        let feeds = TeamFeeds()
        let clock = TestClock()
        let model = makeModel(feeds, clock: clock)

        await model.refreshExpiredFeeds()
        await model.reloadSchedule()
        #expect(await feeds.counts == [1, 1, 1, 1, 1])

        // The schedule refreshes a minute later with the game still on.
        clock.advance(minutes: 1)
        await model.reloadSchedule()
        #expect(await feeds.counts == [1, 2, 1, 1, 1])

        // Then it goes final, well inside the time-to-live: the feeds it
        // changes are refetched, the roster is not.
        clock.advance(minutes: 1)
        await feeds.setFinished(true)
        await model.reloadSchedule()
        #expect(await feeds.counts == [1, 3, 2, 2, 2])
        #expect(!model.needsRefresh(.news))
        #expect(!model.needsRefresh(.standings))
        #expect(!model.needsRefresh(.leaders))

        // A finished game stays finished: no further refetch.
        await model.reloadSchedule()
        #expect(await feeds.counts == [1, 4, 2, 2, 2])
    }

    @Test("refreshAll refetches every feed, however fresh")
    func refreshAllForcesEveryFeed() async {
        let feeds = TeamFeeds()
        let clock = TestClock()
        let model = makeModel(feeds, clock: clock)

        await model.refreshExpiredFeeds()
        await model.reloadSchedule()
        #expect(await feeds.counts == [1, 1, 1, 1, 1])

        await model.refreshAll()
        #expect(await feeds.counts == [2, 2, 2, 2, 2])
        await model.refreshAll()
        #expect(await feeds.counts == [3, 3, 3, 3, 3])

        #expect(model.rosterState == .loaded)
        #expect(model.scheduleState == .loaded)
        #expect(model.newsState == .loaded)
        #expect(model.standingsState == .loaded)
        #expect(model.leadersState == .loaded)
        #expect(model.games.count == 1)
    }
}

// MARK: - Roster name order (A-15)

@Suite("Team pages: roster name order")
@MainActor
struct RosterNameOrderTests {
    private func player(_ name: String, last: String, number: Int) -> BasketballPlayer {
        BasketballPlayer(
            playerID: "\(name)-\(number)",
            name: name,
            number: String(number),
            numberInt: number,
            height: "",
            weight: "",
            position: "",
            grade: "",
            hometown: "",
            photo: "",
            status: "",
            lastName: last
        )
    }

    @Test("Names sort as people read them, not by code point, with ties broken by name then number")
    func localizedOrder() async {
        let roster = [
            player("Oleksandr Zinchenko", last: "Zinchenko", number: 35),
            player("Virgil van Dijk", last: "van Dijk", number: 4),
            player("Martin Ødegaard", last: "Ødegaard", number: 8),
            player("Frenkie de Jong", last: "de Jong", number: 21),
            player("John Smith", last: "Smith", number: 10),
            player("John Smith", last: "Smith", number: 2),
            player("Adam Smith", last: "Smith", number: 30),
            player("Kai Havertz", last: "Havertz", number: 29),
        ]
        let model = TeamModel<BasketballPlayer>(
            team: .jayhawks,
            newsURL: "",
            loadRoster: { _ in .success(roster) }
        )
        await model.reloadRoster()
        model.sort(by: .name)

        #expect(model.players.map { "\($0.name) \($0.number)" } == [
            "Frenkie de Jong 21",
            "Kai Havertz 29",
            "Martin Ødegaard 8",
            "Adam Smith 30",
            "John Smith 2",
            "John Smith 10",
            "Virgil van Dijk 4",
            "Oleksandr Zinchenko 35",
        ])
    }
}
