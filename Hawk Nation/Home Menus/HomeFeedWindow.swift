//
//  HomeFeedWindow.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

// Home's ±7-day window over the favorites' games, and how it groups them:
// moved out of HomeViewModel.swift (R-9) so the widget's "My Day"
// (`WidgetDayBuilder`) reads the favorites' games exactly as Home does.
// UI-free; compiled into both targets, like `WidgetScoreboardSnapshot`. The
// rest of `HomeFeed` (the live boards, the news, the load states) stays with
// the app, in HomeViewModel.swift.

/// A favorite's game on Home: the game as its schedule lists it, and the
/// favorite whose schedule that is.
struct HomeGame: Identifiable, Hashable, Sendable {
    let team: TeamRef
    let game: Game

    /// The game's id, so two favorites playing each other are one game.
    var id: String { game.gameID.isEmpty ? "\(team.id)|\(game.id)" : game.gameID }
}

/// A day of the favorites' upcoming games, under its date header.
struct HomeDay: Identifiable, Equatable, Sendable {
    /// The day's start.
    let date: Date
    /// In start order.
    let games: [HomeGame]

    var id: Date { date }
}

/// What Home shows, worked out from the favorites' seasons, the league
/// scoreboards and the news feeds as plain values, so the tests can drive
/// it.
enum HomeFeed {
    /// How far ahead Upcoming reaches.
    static let upcomingWindow: TimeInterval = 7 * 24 * 60 * 60

    /// How far back Recent Results reaches.
    static let resultsWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Every favorite's games, in favorites order, each game once.
    static func games(teams: [TeamRef], seasons: [TeamRef.ID: [Game]]) -> [HomeGame] {
        var seen: Set<String> = []
        var result: [HomeGame] = []
        for team in teams {
            for game in seasons[team.id] ?? [] {
                let entry = HomeGame(team: team, game: game)
                if seen.insert(entry.id).inserted {
                    result.append(entry)
                }
            }
        }
        return result
    }

    /// The favorites' games still to start within the next
    /// `upcomingWindow`, by day, soonest first; none when there are none.
    /// Games without a date are left out, and a game under way is Live
    /// Now's.
    static func upcomingDays(_ games: [HomeGame], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [HomeDay] {
        let latest = now.addingTimeInterval(upcomingWindow)
        let upcoming = games
            .filter { entry in
                let game = entry.game
                return !game.completed && !game.date.isEmpty
                    && game.dateAsDate >= now && game.dateAsDate <= latest
            }
            .sorted { $0.game.dateAsDate < $1.game.dateAsDate }

        var days: [HomeDay] = []
        for entry in upcoming {
            let day = calendar.startOfDay(for: entry.game.dateAsDate)
            if let last = days.last, last.date == day {
                days[days.count - 1] = HomeDay(date: day, games: last.games + [entry])
            } else {
                days.append(HomeDay(date: day, games: [entry]))
            }
        }
        return days
    }

    /// The favorites' games played out in the last `resultsWindow`, newest
    /// first. A game called off is not a result.
    static func results(_ games: [HomeGame], now: Date) -> [HomeGame] {
        let earliest = now.addingTimeInterval(-resultsWindow)
        return games
            .filter { entry in
                let game = entry.game
                return game.completed && !game.cancelled && !game.postponed
                    && !game.date.isEmpty
                    && game.dateAsDate >= earliest && game.dateAsDate <= now
            }
            .sorted { $0.game.dateAsDate > $1.game.dateAsDate }
    }
}
