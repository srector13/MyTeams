//
//  GetNextGame.swift
//  myTeams
//
//  Created by Stephen Rector on 6/24/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The index of the next game still to be played, for the schedule carousel.
///
/// Feeds list a season in chronological order, so normally that is the first
/// fixture not already marked done. Two feeds need a fallback: an in-progress
/// game keeps `completed: false` (the score is still moving), and the soccer
/// feed's flags lag or never arrive. There, a fixture whose start time is
/// more than four hours past is treated as played so the pointer walks over
/// it, while a live game keeps its slot.
///
/// Once nothing is left to play the result clamps to the final game — the
/// season's last result, not the opener. An empty schedule returns 0 as a
/// placeholder index; callers must only invoke this with a non-empty schedule
/// (see `TeamModel.apply(schedule:)`).
func getNextGame(
    schedule: [Game],
    pastDatesCountAsPlayed: Bool = false,
    now: Date = Date()
) -> Int {
    guard !schedule.isEmpty else { return 0 }

    var nextGamePointer = 0

    for game in schedule {
        if game.completed || game.cancelled || game.postponed {
            nextGamePointer += 1
        } else if pastDatesCountAsPlayed
                    && game.dateAsDate.addingTimeInterval(4 * 3600) < now {
            nextGamePointer += 1
        } else {
            break
        }
    }

    return min(nextGamePointer, schedule.count - 1)
}
