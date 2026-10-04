//
//  TabBarTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Testing

@testable import myTeams

/// Where the "Teams" tab sits among the favorites' tabs in the system tab
/// bar (`HomeTabs.editIndex`).
@Suite("Tab bar")
struct TabBarTests {
    @Test("The Teams tab comes last while every tab fits the bar")
    func editLastWhileTheBarHoldsAll() {
        #expect(HomeTabs.editIndex(teamCount: 0, barCapacity: HomeTabs.compactCapacity) == 0)
        #expect(HomeTabs.editIndex(teamCount: 1, barCapacity: HomeTabs.compactCapacity) == 1)
        #expect(HomeTabs.editIndex(teamCount: 4, barCapacity: HomeTabs.compactCapacity) == 4)
    }

    @Test("Past the bar's capacity the Teams tab takes the last slot before More")
    func editBeforeMoreOnceTheyOverflow() {
        // Five favorites and Teams make six: the bar shows four and More.
        #expect(HomeTabs.editIndex(teamCount: 5, barCapacity: HomeTabs.compactCapacity) == 3)
        #expect(HomeTabs.editIndex(teamCount: 12, barCapacity: HomeTabs.compactCapacity) == 3)
    }

    @Test("With no limit on the bar the Teams tab comes last")
    func editLastWithoutALimit() {
        #expect(HomeTabs.editIndex(teamCount: 12, barCapacity: nil) == 12)
    }

    @Test("The Teams tab's value can't be a team's")
    func editValueIsNotATeamID() {
        // A team's id is "<leaguePath>:<espnID>".
        #expect(!HomeTabs.edit.contains(":"))
        #expect(HomeTabs.edit == "teamPicker.edit")
    }
}
