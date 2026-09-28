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
