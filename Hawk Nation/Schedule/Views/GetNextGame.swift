//
//  GetNextGame.swift
//  myTeams
//
//  Created by Stephen Rector on 6/24/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

func getNextGame(schedule: [Game]) -> Int {
    //var currentDate = Date()
    //currentDate.addTimeInterval(TimeInterval(90.0 * 60.0))

    var nextGamePointer = 0
    
    for game in schedule {
        if(game.completed || game.cancelled || game.postponed) {
            nextGamePointer += 1
        } else {
            break
        }
        
        /*let gameDate = game.dateAsDate
        if(gameDate <= currentDate) {
            nextGamePointer += 1
        } else {
            break
        }*/
    }
    
    if nextGamePointer > schedule.count-1 {
        return schedule.count - 1
    }
    
    return nextGamePointer
}

func getNextSportingGame(schedule: [Game]) -> Int {
    var currentDate = Date()
    currentDate.addTimeInterval(TimeInterval(90.0 * 60.0))

    var nextGamePointer = 0

    
    for pointer in (0...schedule.count-1).reversed() {
        let gameDate = schedule[pointer].dateAsDate
        if(gameDate >= currentDate) {
            nextGamePointer = pointer
        }
    }
    
    return nextGamePointer
}

func hasPassed(game: Game) -> Bool {
    var currentDate = Date()
    currentDate.addTimeInterval(TimeInterval(90.0 * 60.0))

    if(game.dateAsDate <= currentDate) {
        return false
    }
    
    return true
}
