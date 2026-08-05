//
//  TeamModel.swift
//  myTeams
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The roster fields every tab displays, sorts and filters on, whichever sport
/// it shows.
protocol RosterPlayer: Identifiable, Hashable, Sendable {
    var name: String { get }
    var lastName: String { get }
    var number: String { get }
    var numberInt: Int { get }
    var position: String { get }
    var photo: String { get }
}

extension BasketballPlayer: RosterPlayer {}
extension FootBallPlayer: RosterPlayer {}
extension BaseballPlayer: RosterPlayer {}
extension SoccerPlayer: RosterPlayer {}

/// How the roster carousel is ordered. The choice also decides which detail —
/// number, or position — each player card shows beneath the name.
enum PlayerSort: String, Sendable {
    case name
    case number
    case position
}

/// Everything one team tab displays, and the loading that fills it.
///
/// The four tabs differ only in which roster they fetch and which feeds they read,
/// so they share this model rather than each repeating the same state,
/// filtering, sorting and refresh logic.
@MainActor
@Observable
final class TeamModel<Player: RosterPlayer> {
    /// The roster as filtered and sorted for display.
    private(set) var players: [Player] = []

    /// The full roster, kept so that clearing a filter does not need a refetch.
    private(set) var allPlayers: [Player] = []

    private(set) var games: [Game] = []
    private(set) var articles: [News] = []

    /// The index in `games` of the next game still to be played. The schedule
    /// carousel opens scrolled to it.
    private(set) var nextGame = 0

    var sort: PlayerSort = .name

    /// The filter currently narrowing the roster, reapplied when the sort
    /// changes so the two do not clobber each other.
    private var activeFilter: (@Sendable (Player) -> Bool)?

    private let scheduleURL: String
    private let teamName: String
    private let teamNameField: TeamNameField
    private let newsURL: String
    private let loadRoster: @Sendable () async -> [Player]

    /// How the next game is located in the schedule. Soccer fixtures are
    /// listed with no completion flag, so that tab searches by date instead.
    private let usesDateForNextGame: Bool

    init(
        scheduleURL: String,
        teamName: String,
        teamNameField: TeamNameField = .nickname,
        newsURL: String,
        usesDateForNextGame: Bool = false,
        loadRoster: @escaping @Sendable () async -> [Player]
    ) {
        self.scheduleURL = scheduleURL
        self.teamName = teamName
        self.teamNameField = teamNameField
        self.newsURL = newsURL
        self.usesDateForNextGame = usesDateForNextGame
        self.loadRoster = loadRoster
    }

    /// The team's record so far this season, as wins and losses.
    ///
    /// Losses count only games already played that were neither cancelled nor
    /// postponed, so an abandoned fixture does not show up as a defeat.
    var record: (wins: Int, losses: Int) {
        let wins = games.count { $0.gameWin }
        let losses = games.count {
            !$0.gameWin && $0.pointer < nextGame && !$0.cancelled && !$0.postponed
        }
        return (wins, losses)
    }

    // MARK: - Loading

    /// Loads the roster, schedule and news feeds together, then keeps the
    /// schedule fresh for as long as the tab is on screen.
    ///
    /// Scores and clocks move during a game, so the schedule is refetched every
    /// minute; rosters and news do not, so they are fetched once.
    func load() async {
        async let roster = loadRoster()
        async let schedule = fetchSchedule()
        async let news = downloadNewsData(queryURL: newsURL)

        let (loadedRoster, loadedSchedule, loadedNews) = await (roster, schedule, news)

        allPlayers = loadedRoster
        applyFilterAndSort()
        apply(schedule: loadedSchedule)
        articles = loadedNews

        await refreshSchedulePeriodically()
    }

    /// Refetches the schedule once a minute until the surrounding task is
    /// cancelled, which SwiftUI does when the view goes away.
    private func refreshSchedulePeriodically() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            apply(schedule: await fetchSchedule())
        }
    }

    private func fetchSchedule() async -> [Game] {
        await downloadScheduleData(
            queryURL: scheduleURL,
            teamName: teamName,
            teamNameField: teamNameField
        )
    }

    private func apply(schedule: [Game]) {
        // A failed refresh returns nothing; keep what is already on screen
        // rather than blanking the carousel.
        guard !schedule.isEmpty else { return }

        games = schedule
        nextGame = usesDateForNextGame
            ? getNextSportingGame(schedule: schedule)
            : getNextGame(schedule: schedule)
    }

    // MARK: - Filtering and sorting

    /// Narrows the roster to the players matching `predicate`, or shows all of
    /// them when it is `nil`.
    func filter(_ predicate: (@Sendable (Player) -> Bool)? = nil) {
        activeFilter = predicate
        applyFilterAndSort()
    }

    func sort(by sort: PlayerSort) {
        self.sort = sort
        applyFilterAndSort()
    }

    private func applyFilterAndSort() {
        let filtered = activeFilter.map { allPlayers.filter($0) } ?? allPlayers

        players = switch sort {
        case .name: filtered.sorted { $0.lastName < $1.lastName }
        case .number: filtered.sorted { $0.numberInt < $1.numberInt }
        case .position: filtered.sorted { $0.position < $1.position }
        }
    }
}
