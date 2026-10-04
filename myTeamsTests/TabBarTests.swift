//
//  TabBarTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import CoreGraphics
import Testing

@testable import myTeams

/// The tab bar's collapse, which follows the page's scrolling, and the
/// accent its selected tab's label takes.
@Suite("Tab bar")
struct TabBarTests {
    /// A page 2,000 pt tall in an 800 pt window.
    private func at(_ offset: CGFloat, maxOffset: CGFloat = 1200) -> TabBarCollapse.Position {
        TabBarCollapse.Position(offset: offset, maxOffset: maxOffset)
    }

    @Test("Scrolling down collapses the bar once past the threshold")
    func scrollDownCollapses() {
        let tracker = TabBarCollapse()
        #expect(tracker.scrolled(to: at(100), byUser: true) == nil)
        #expect(tracker.scrolled(to: at(105), byUser: true) == nil)
        #expect(tracker.scrolled(to: at(100 + TabBarCollapse.threshold + 1), byUser: true) == true)
    }

    @Test("Scrolling back up brings the bar back")
    func scrollUpReveals() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(100), byUser: true)
        #expect(tracker.scrolled(to: at(200), byUser: true) == true)
        // The turn starts a new run: a small move back leaves the bar.
        #expect(tracker.scrolled(to: at(195), byUser: true) == nil)
        #expect(tracker.scrolled(to: at(180), byUser: true) == false)
    }

    @Test("Pulling past the top brings the bar back")
    func pullAtTopReveals() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(0), byUser: true)
        #expect(tracker.scrolled(to: at(-30), byUser: true) == false)
    }

    @Test("Reaching the foot of the page brings the bar back, and keeps it")
    func footReveals() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(1000), byUser: true)
        #expect(tracker.scrolled(to: at(1100), byUser: true) == true)
        #expect(tracker.scrolled(to: at(1195), byUser: true) == false)
        // Overscroll at the foot doesn't send it away again.
        #expect(tracker.scrolled(to: at(1240), byUser: true) == false)
    }

    @Test("A page restoring its offset moves the baseline only")
    func programmaticScrollIsIgnored() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(0), byUser: true)
        #expect(tracker.scrolled(to: at(600), byUser: false) == nil)
        // Measured from 600, not 0.
        #expect(tracker.scrolled(to: at(605), byUser: true) == nil)
    }

    @Test("After a reset the next position is only a baseline")
    func resetForgetsThePage() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(0), byUser: true)
        tracker.reset()
        #expect(tracker.scrolled(to: at(400), byUser: true) == nil)
        #expect(tracker.scrolled(to: at(405), byUser: true) == nil)
    }

    @Test("A bar brought back by hand starts a new run")
    func revealRestartsTheRun() {
        let tracker = TabBarCollapse()
        _ = tracker.scrolled(to: at(100), byUser: true)
        _ = tracker.scrolled(to: at(108), byUser: true)
        tracker.revealed()
        #expect(tracker.scrolled(to: at(116), byUser: true) == nil)
    }

    @Test("The selected tab's label takes the team colour where it reads on the bar")
    func accentPrefersTheTeamColour() {
        var team = TeamRef.jayhawks
        team.colorHex = "0051BA"
        team.alternateColorHex = "E8000D"
        #expect(TabBarStyle.accentHex(for: team, dark: false) == "0051BA")
        // Navy is too dark on the dark bar; the red reads.
        #expect(TabBarStyle.accentHex(for: team, dark: true) == "E8000D")
    }

    @Test("A label falls back to the primary colour when neither team colour reads")
    func accentFallsBack() {
        var team = TeamRef.jayhawks
        team.colorHex = "FFFFFF"
        team.alternateColorHex = "FAFAFA"
        #expect(TabBarStyle.accentHex(for: team, dark: false) == nil)
        team.colorHex = "000000"
        team.alternateColorHex = "111111"
        #expect(TabBarStyle.accentHex(for: team, dark: true) == nil)
    }
}
