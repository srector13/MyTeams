//
//  WidgetDeepLinkRoutingTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

// What `Home` does with a widget link, through `HomeRouting`: the view's
// `.onChange(of: deepLinkedTeamID)` and `.task(id: store.teamIDs)` feed it
// their state and apply its answer.

private let chiefs = "football/nfl:12"
private let royals = "baseball/mlb:7"
private let sporting = "soccer/usa.1:186"
/// A favorite the bundled catalog does not know: it shows only once the
/// remote catalog resolves it.
private let blues = "hockey/nhl:19"

/// `Home`'s routing state, driven as the view drives it: a link sets the
/// binding and fires `onChange`; resolving the favorites runs the task. A
/// write to the link fires `onChange` again, as the binding would.
private struct HomeDriver {
    var state: HomeRouting.State
    /// The favorites resolved so far (`Home.teams`).
    var teams: [TeamRef.ID]
    /// `FavoritesStore.teamIDs`.
    var favoriteIDs: [TeamRef.ID]

    init(selection: TeamRef.ID, teams: [TeamRef.ID], favoriteIDs: [TeamRef.ID]) {
        state = HomeRouting.State(selection: selection, pendingLink: nil)
        self.teams = teams
        self.favoriteIDs = favoriteIDs
    }

    /// `MyTeamsApp.open`: only a well-formed team link, or game link with
    /// a team, is passed on; a team link clears any game waiting.
    mutating func open(_ url: URL) {
        if let id = WidgetDeepLink.teamID(from: url) {
            state.pendingGame = nil
            setLink(id)
        } else if let game = WidgetDeepLink.game(from: url), let id = game.teamID {
            state.pendingGame = game
            setLink(id)
        }
    }

    mutating func setLink(_ id: TeamRef.ID?) {
        state.pendingLink = id
        linkChanged()
    }

    /// `.task(id: store.teamIDs)` once `teamRefs()` returns.
    mutating func resolve(_ teams: [TeamRef.ID]) {
        self.teams = teams
        apply(HomeRouting.favoritesResolved(state, teams: teams))
    }

    private mutating func linkChanged() {
        apply(HomeRouting.linkChanged(state, teams: teams, favoriteIDs: favoriteIDs))
    }

    private mutating func apply(_ next: HomeRouting.State) {
        let linkMoved = next.pendingLink != state.pendingLink
        state = next
        if linkMoved {
            linkChanged()
        }
    }
}

private func link(_ teamID: TeamRef.ID) throws -> URL {
    try #require(WidgetDeepLink.url(forTeamID: teamID))
}

/// A game link's target, and its URL, for `teamID`'s game `eventID`.
private func gameLink(_ eventID: String, _ teamID: TeamRef.ID) throws -> (WidgetDeepLink.GameTarget, URL) {
    let league = try #require(TeamRef.parse(id: teamID)).league
    let url = try #require(WidgetDeepLink.url(forGame: eventID, league: league, teamID: teamID))
    return (WidgetDeepLink.GameTarget(league: league, eventID: eventID, teamID: teamID), url)
}

@Suite("Widget deep links: routing in Home")
struct WidgetDeepLinkRoutingTests {
    @Test("A link to a loaded favorite selects its page at once and is consumed")
    func loadedFavorite() throws {
        let favorites = [chiefs, royals, sporting]
        var home = HomeDriver(selection: chiefs, teams: favorites, favoriteIDs: favorites)
        let url = try link(royals)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
    }

    @Test("A link to a team that is not a favorite is dropped, the page left as it was")
    func notAFavorite() throws {
        let favorites = [chiefs, royals]
        var home = HomeDriver(selection: royals, teams: favorites, favoriteIDs: favorites)
        let url = try link(sporting)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))

        // A malformed link never reaches Home at all.
        let malformed = try #require(URL(string: "myteams://team/not-a-team"))
        home.open(malformed)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
    }

    @Test("A link arriving while its favorite is still loading is held, then applied once it resolves")
    func heldWhileLoading() throws {
        // Launch shows the bundled teams; the Blues are still resolving.
        let favorites = [chiefs, royals, blues]
        var home = HomeDriver(selection: chiefs, teams: [chiefs, royals], favoriteIDs: favorites)
        let url = try link(blues)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: chiefs, pendingLink: blues))

        // Another look before they resolve changes nothing.
        home.setLink(blues)
        #expect(home.state.pendingLink == blues)

        home.resolve(favorites)
        #expect(home.state == HomeRouting.State(selection: blues, pendingLink: nil))
    }

    @Test("On a cold launch the held link beats the fall-back to the first team")
    func coldLaunch() throws {
        // Nothing resolved yet and nothing selected: the link came with the
        // launch, before the favorites loaded.
        let favorites = [chiefs, royals, blues]
        var home = HomeDriver(selection: "", teams: [], favoriteIDs: favorites)
        let url = try link(blues)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: "", pendingLink: blues))

        home.resolve(favorites)
        #expect(home.state == HomeRouting.State(selection: blues, pendingLink: nil))
    }

    @Test("A held link whose team never resolves is dropped; the selection stays")
    func heldLinkNeverResolves() throws {
        let favorites = [chiefs, royals, blues]
        var home = HomeDriver(selection: royals, teams: [chiefs, royals], favoriteIDs: favorites)
        let url = try link(blues)
        home.open(url)
        #expect(home.state.pendingLink == blues)

        // `teamRefs()` gave up on the Blues.
        home.resolve([chiefs, royals])
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))

        // So a later refresh has nothing left to apply.
        home.resolve(favorites)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
    }

    @Test("With no link, resolving keeps the selection, or falls back to the first team, or to none")
    func selectionFallback() {
        let kept = HomeRouting.favoritesResolved(
            HomeRouting.State(selection: royals, pendingLink: nil), teams: [chiefs, royals]
        )
        #expect(kept == HomeRouting.State(selection: royals, pendingLink: nil))

        // The selected team was unfollowed.
        let fellBack = HomeRouting.favoritesResolved(
            HomeRouting.State(selection: sporting, pendingLink: nil), teams: [chiefs, royals]
        )
        #expect(fellBack == HomeRouting.State(selection: chiefs, pendingLink: nil))

        let empty = HomeRouting.favoritesResolved(
            HomeRouting.State(selection: chiefs, pendingLink: nil), teams: []
        )
        #expect(empty == HomeRouting.State(selection: HomeTabs.homeID, pendingLink: nil))

        // And a cleared link is no link: nothing to do.
        let idle = HomeRouting.State(selection: royals, pendingLink: nil)
        let unchanged = HomeRouting.linkChanged(idle, teams: [chiefs, royals], favoriteIDs: [chiefs, royals])
        #expect(unchanged == idle)
    }

    // MARK: Game links (R-3)

    @Test("Foreground: a game link selects its team and opens the game's sheet")
    func gameLinkForeground() throws {
        let favorites = [chiefs, royals, sporting]
        var home = HomeDriver(selection: HomeTabs.homeID, teams: favorites, favoriteIDs: favorites)
        let (target, url) = try gameLink("401", royals)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil, openGame: target))
    }

    @Test("Cold launch: a game link waits for its team to resolve, then opens the game's sheet")
    func gameLinkColdLaunch() throws {
        let favorites = [chiefs, royals, blues]
        var home = HomeDriver(selection: "", teams: [], favoriteIDs: favorites)
        let (target, url) = try gameLink("401", blues)
        home.open(url)
        #expect(home.state == HomeRouting.State(selection: "", pendingLink: blues, pendingGame: target))

        home.resolve(favorites)
        #expect(home.state == HomeRouting.State(selection: blues, pendingLink: nil, openGame: target))
    }

    @Test("A cup tie's game link opens over the team's page in its home league")
    func gameLinkCupTie() throws {
        let arsenal = TeamRef.id(league: .premierLeague, espnID: "359")
        var home = HomeDriver(selection: chiefs, teams: [chiefs, arsenal], favoriteIDs: [chiefs, arsenal])
        let url = try #require(WidgetDeepLink.url(forGame: "401915423", league: .championsLeague, teamID: arsenal))
        home.open(url)
        #expect(home.state.selection == arsenal)
        #expect(home.state.openGame == WidgetDeepLink.GameTarget(league: .championsLeague, eventID: "401915423", teamID: arsenal))
    }

    @Test("A game link whose team is not a favorite, or never resolves, opens nothing")
    func gameLinkDropped() throws {
        let favorites = [chiefs, royals]
        var home = HomeDriver(selection: royals, teams: favorites, favoriteIDs: favorites)
        home.open(try gameLink("401", sporting).1)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))

        var loading = HomeDriver(selection: royals, teams: favorites, favoriteIDs: favorites + [blues])
        loading.open(try gameLink("402", blues).1)
        #expect(loading.state.pendingGame != nil)
        loading.resolve(favorites)
        #expect(loading.state == HomeRouting.State(selection: royals, pendingLink: nil))

        // No team named: nowhere to open it over.
        let teamless = try #require(WidgetDeepLink.url(forGame: "403", league: .nfl, teamID: nil))
        home.open(teamless)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
    }

    @Test("A team link after a held game link opens the team alone")
    func teamLinkReplacesGame() throws {
        let favorites = [chiefs, royals, blues]
        var home = HomeDriver(selection: chiefs, teams: [chiefs, royals], favoriteIDs: favorites)
        home.open(try gameLink("401", blues).1)
        #expect(home.state.pendingGame != nil)

        home.open(try link(royals))
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
        home.resolve(favorites)
        #expect(home.state == HomeRouting.State(selection: royals, pendingLink: nil))
    }

    @Test("Team links still route as before: no game opens")
    func teamLinkOpensNoGame() throws {
        let favorites = [chiefs, royals]
        var home = HomeDriver(selection: chiefs, teams: favorites, favoriteIDs: favorites)
        home.open(try link(royals))
        #expect(home.state.openGame == nil)
        #expect(home.state.pendingGame == nil)
        #expect(home.state.selection == royals)
    }
}
