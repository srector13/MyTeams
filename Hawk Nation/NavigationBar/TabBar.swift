//
//  TabBar.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

// The teams on this screen are the reader's favorites (`FavoritesStore`),
// resolved through `RemoteTeamCatalog` and shown in favorites order.

/// The app's root screen: the system tab bar, Home first — every
/// favorite's live games, the week's upcoming games and results, and
/// headlines together (`HomeView`, t_0b94af11) — then one tab per favorite
/// team, each showing that team's scrolling page. The app opens on Home.
/// Teams are added from Settings (t_fa6748f4), or from Home's empty state.
///
/// A standard `TabView`, so the platform draws the bar: its Liquid Glass,
/// selection indicator and animation, the large content viewer, minimizing
/// on scroll, and the "More" tab that takes the favorites past what the bar
/// holds.
struct Home: View {
    /// A team to switch to, set when a widget link opens the app. Cleared
    /// once handled; a team that is not a favorite is ignored.
    @Binding var deepLinkedTeamID: TeamRef.ID?

    /// A game a link asked for, with `deepLinkedTeamID` its team: its
    /// sheet opens over the team's page (R-3). Cleared with the team link.
    @Binding var deepLinkedGame: WidgetDeepLink.GameTarget?

    /// A game link whose team is selected, until its game is found in the
    /// team's schedule (`HomeRouting.State.openGame`).
    @State private var openGame: WidgetDeepLink.GameTarget?

    /// The linked game's sheet.
    @State private var linkedGame: LinkedGame?

    /// The favorites as teams. Starts with those the bundled catalog knows,
    /// so the first frame has any bundled teams followed, then fills in from
    /// the catalog.
    @State private var teams: [TeamRef] = FavoritesStore.shared.teamIDs.compactMap(TeamCatalog.team(id:))

    /// Home at every launch (`HomeTabs.homeID`): there is no memory of the
    /// last tab. A widget link still opens its team's tab.
    @State private var selection: TeamRef.ID = HomeTabs.homeID

    @State private var showsBrowser = false

    /// Settings, opened from a team page's gear. Here rather than on the
    /// page, which is mounted only while its team is selected: removing
    /// that team in Settings → Manage Teams, or a widget link arriving,
    /// moves the selection and unmounts the page, and Settings with it
    /// (A-5).
    @State private var showsSettings = false

    /// Each team's model and scroll offset, kept while its page is not
    /// mounted.
    @State private var pages = TeamPages()

    /// Other teams' pages opened over each favorite's page, by tab
    /// (`HomeRouting.teamOpened`).
    @State private var visits: [TeamRef.ID: [TeamVisit]] = [:]

    /// How a page asks for another team's page, or for a player's sheet
    /// on one (t_8d15e070).
    @State private var navigator = TeamNavigator()

    /// Bumped when a favorite's crest lands in `LogoStore`, so the tab items
    /// read it again (`TabCrest`).
    @State private var crestRevision = 0

    @Bindable private var store = FavoritesStore.shared

    /// VoiceOver and Switch Control keep the bar at full size: a minimized
    /// bar hides the other teams' tabs from them.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    // Spelled out: the private state makes the memberwise init private.
    init(deepLinkedTeamID: Binding<TeamRef.ID?>, deepLinkedGame: Binding<WidgetDeepLink.GameTarget?> = .constant(nil)) {
        self._deepLinkedTeamID = deepLinkedTeamID
        self._deepLinkedGame = deepLinkedGame
    }

    private var routing: HomeRouting.State {
        HomeRouting.State(
            selection: selection,
            pendingLink: deepLinkedTeamID,
            showsSettings: showsSettings,
            visits: visits,
            pendingGame: deepLinkedGame,
            openGame: openGame
        )
    }

    private func apply(_ routed: HomeRouting.State) {
        if selection != routed.selection {
            selection = routed.selection
        }
        if deepLinkedTeamID != routed.pendingLink {
            deepLinkedTeamID = routed.pendingLink
        }
        if showsSettings != routed.showsSettings {
            showsSettings = routed.showsSettings
        }
        if visits != routed.visits {
            visits = routed.visits
        }
        if deepLinkedGame != routed.pendingGame {
            deepLinkedGame = routed.pendingGame
        }
        if openGame != routed.openGame {
            openGame = routed.openGame
        }
    }

    /// Finds the linked game in its team's schedule and opens its sheet,
    /// then forgets the link. A game the schedule does not list opens
    /// nothing; the team's page is already on screen.
    private func presentOpenGame() async {
        guard let target = openGame else { return }
        // Unless a newer link has replaced it meanwhile.
        defer { if openGame == target { openGame = nil } }
        guard let team = teams.first(where: { $0.id == target.teamID }),
              case .success(let games) = await downloadScheduleData(team: team),
              !Task.isCancelled,
              let game = games.first(where: { $0.gameID == target.eventID })
        else { return }
        linkedGame = LinkedGame(game: game, team: team)
    }

    /// The other teams' pages pushed over `teamID`'s page.
    private func visitPath(for teamID: TeamRef.ID) -> Binding<[TeamVisit]> {
        Binding {
            visits[teamID] ?? []
        } set: { path in
            visits[teamID] = path.isEmpty ? nil : path
        }
    }

    /// The teams whose pages are open as visits, whose models `pages`
    /// keeps alongside the favorites'.
    private var visitedIDs: [TeamRef.ID] {
        visits.values.flatMap { $0.map(\.team.id) }
    }

    /// The tab view's selection: a tap on a team's tab chooses that team,
    /// as a pick from the "More" list does (`teamPage`).
    private var tabSelection: Binding<TeamRef.ID> {
        Binding {
            selection
        } set: { tab in
            choose(tab)
        }
    }

    /// The reader chose `team`, from its tab in the bar or from "More".
    private func choose(_ team: TeamRef.ID) {
        apply(HomeRouting.teamChosen(routing, team: team, teams: teams.map(\.id)))
    }

    /// Restarts the crest prefetch when the favorites or the colour scheme
    /// (and with it the crest variant) change.
    private var crestTaskID: String {
        teams.map(\.id).joined(separator: ",") + (colorScheme == .dark ? "|dark" : "|light")
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if teams.isEmpty && !store.teamIDs.isEmpty {
                    // Favorites still resolving at launch: not the empty
                    // state, which would flash "Add Teams" at a reader who
                    // follows teams.
                    Theme.Surface.content
                        .ignoresSafeArea()
                } else {
                    // With no favorites — a fresh install, or every team
                    // unfollowed — the bar holds Home alone, and Home's
                    // empty state is the way in rather than a sheet at
                    // launch (t_afe5c297).
                    tabs
                }
            }
            .environment(\.containerSize, proxy.size)
        }
        .environment(navigator)
        .task(id: store.teamIDs) {
            pages.retain(store.teamIDs + visitedIDs)
            teams = await store.teamRefs()
            apply(HomeRouting.favoritesResolved(routing, teams: teams.map(\.id)))
        }
        // A page asked for a team's page: a favorite's tab, or the team's
        // page pushed over the one on screen (t_8d15e070).
        .onChange(of: navigator.request) { _, _ in
            guard let team = navigator.takeRequest() else { return }
            apply(HomeRouting.teamOpened(routing, team: team, teams: teams.map(\.id)))
        }
        .onChange(of: deepLinkedTeamID, initial: true) { _, _ in
            apply(HomeRouting.linkChanged(routing, teams: teams.map(\.id), favoriteIDs: store.teamIDs))
        }
        // A game link's team is selected: its sheet, once the schedule
        // names the game (R-3).
        .task(id: openGame) {
            await presentOpenGame()
        }
        .sheet(item: $linkedGame) { linked in
            GameDetailView(game: linked.game, team: linked.team)
        }
        // A tab item takes a finished image, not a view that loads one, so
        // the crests are fetched here and the items redrawn as each lands.
        .task(id: crestTaskID) {
            let dark = colorScheme == .dark
            for team in teams {
                if await TabCrest.prefetch(team, dark: dark) {
                    crestRevision += 1
                }
            }
        }
        .sheet(isPresented: $showsBrowser) {
            TeamBrowserView(title: "Add Teams")
        }
        // Outlives any one team's page (A-5).
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // A key saved, or the toggle turned on, in that sheet: the team
        // page under it has its roster already and asks nothing more, so
        // the API-Football store sweeps what it has seen (t_1fa9b665).
        .onChange(of: ApiFootballSettings.shared.isActive) { _, isActive in
            if isActive { ApiFootballHeadshotStore.shared.resume() }
        }
    }

    /// Home's tab, then the favorites' tabs: those past the bar's room
    /// under the system's "More" (`HomeTabs.barCount`). Teams are added
    /// from Settings (t_fa6748f4).
    @ViewBuilder
    private var tabs: some View {
        let _ = crestRevision
        let barCount = HomeTabs.barCount(
            teamCount: teams.count,
            // Home always holds the bar's first slot.
            barCapacity: sizeClass == .compact ? HomeTabs.compactCapacity - HomeTabs.fixedTabCount : nil
        )
        TabView(selection: tabSelection) {
            homeTab

            ForEach(Array(teams.prefix(barCount))) { team in
                teamTab(team, inMore: false)
            }

            ForEach(Array(teams.dropFirst(barCount))) { team in
                teamTab(team, inMore: true)
            }
        }
        // The bar shrinks to the selected tab as the page scrolls down and
        // comes back on scrolling up or a tap, as the system's apps do.
        .tabBarMinimizeBehavior(voiceOver || switchControl ? .never : .onScrollDown)
        .modifier(HomeSidebar(isRegularWidth: sizeClass == .regular))
        // A tick as the team changes (C-4).
        .sensoryFeedback(.selection, trigger: selection)
        // The alerts presenter skips the banner for the team on screen
        // (C-8); Home is every team's, so no banner is skipped there.
        .onChange(of: selection, initial: true) { _, tab in
            ScoreAlertForeground.shared.teamID = tab == HomeTabs.homeID ? nil : tab
        }
    }

    /// Home: the favorites' live games, the week's upcoming games and
    /// results, and headlines (`HomeView`). First in the bar, and where the app opens.
    private var homeTab: some TabContent<TeamRef.ID> {
        Tab(value: HomeTabs.homeID) {
            HomeView(
                teams: teams,
                addTeams: { showsBrowser = true },
                showSettings: { showsSettings = true }
            )
        } label: {
            Label("Home", systemImage: "house")
        }
        .accessibilityIdentifier("teamPicker.home")
    }

    /// A favorite's tab: its crest over its short name. `inMore` for a tab
    /// past the bar's room, listed under "More".
    private func teamTab(_ team: TeamRef, inMore: Bool) -> some TabContent<TeamRef.ID> {
        Tab(value: team.id) {
            teamPage(team, inMore: inMore)
        } label: {
            Label {
                Text(team.shortName)
            } icon: {
                Image(uiImage: TabCrest.image(for: team, dark: colorScheme == .dark, scale: displayScale))
                    .renderingMode(.original)
            }
        }
        .accessibilityLabel(Text(team.displayName))
        .accessibilityIdentifier("teamPicker.team.\(team.id)")
    }

    /// Only the selected team's page is mounted, so only it loads and polls:
    /// leaving the page cancels its task. Every page used to stay mounted,
    /// each polling on its own. `pages` keeps each team's loaded data and
    /// scroll offset for when the reader comes back.
    ///
    /// Except under "More" (`inMore`). Picking a team from the More list
    /// pushes its tab on UIKit's More navigation controller without the
    /// tab view's selection ever hearing of it, so a page gated on the
    /// selection stayed the blank placeholder and never loaded
    /// (t_fa6748f4). A More tab's page is always mounted instead — its
    /// task still runs only while it's on screen — and coming on screen
    /// chooses its team, the same change a tap on a bar tab makes
    /// (`HomeRouting.teamChosen`).
    @ViewBuilder
    private func teamPage(_ team: TeamRef, inMore: Bool) -> some View {
        if inMore || team.id == selection {
            TeamPage(
                team: team,
                pages: pages,
                path: visitPath(for: team.id),
                showSettings: { showsSettings = true }
            )
            .id(team.id)
            .onAppear { choose(team.id) }
        } else {
            Theme.Surface.content
                .ignoresSafeArea()
        }
    }
}

/// Which team `Home` shows, and what becomes of a widget link, as plain
/// values: the view feeds it its state and applies the answer.
enum HomeRouting {
    struct State: Equatable, Sendable {
        /// The selected tab: a team's id, or `HomeTabs.homeID`.
        var selection: TeamRef.ID
        /// A widget link not yet handled (`Home.deepLinkedTeamID`).
        var pendingLink: TeamRef.ID?
        /// Whether Settings is open (`Home.showsSettings`). Nothing here
        /// closes it: not the selection moving off a removed team, not a
        /// link (A-5).
        var showsSettings = false
        /// Other teams' pages pushed over each favorite's page, by the
        /// favorite's id (`teamOpened`); none for most.
        var visits: [TeamRef.ID: [TeamVisit]] = [:]
        /// A game link's game, waiting on `pendingLink`, its team
        /// (`Home.deepLinkedGame`, R-3). Handled and cleared with it.
        var pendingGame: WidgetDeepLink.GameTarget? = nil
        /// The game whose sheet `Home` opens over its team's page, now
        /// selected (`Home.openGame`).
        var openGame: WidgetDeepLink.GameTarget? = nil
    }

    /// The link's team has been selected (`selected`), or dropped: a game
    /// waiting on it is to open over the team's page, or is dropped too.
    private static func linkHandled(_ state: inout State, selected: Bool) {
        if selected, let game = state.pendingGame, game.teamID == state.selection {
            state.openGame = game
        }
        state.pendingGame = nil
    }

    /// The favorites have been resolved to `teams`, in order. Home stays
    /// selected; a team no longer among them falls back to the first, or to
    /// Home with none left. A link that arrived while the favorites were
    /// loading is handled now, selecting its team if it resolved and
    /// dropped either way.
    static func favoritesResolved(_ state: State, teams: [TeamRef.ID]) -> State {
        var next = state
        if next.selection != HomeTabs.homeID, !teams.contains(next.selection) {
            next.selection = teams.first ?? HomeTabs.homeID
        }
        // A tab that's gone takes the pages pushed over it along.
        next.visits = next.visits.filter { teams.contains($0.key) }
        if let id = next.pendingLink {
            next.pendingLink = nil
            if teams.contains(id) {
                next.selection = id
            }
            linkHandled(&next, selected: teams.contains(id))
        }
        return next
    }

    /// The reader chose `team`: tapped its tab in the bar, or picked it
    /// from the bar's "More" list, whose page coming on screen reports it
    /// (`Home.teamPage`). Either way the same change: the team is selected
    /// if it's one of `teams`, as Home's tab always is. Settings and a
    /// pending link are left alone.
    static func teamChosen(_ state: State, team: TeamRef.ID, teams: [TeamRef.ID]) -> State {
        guard team == HomeTabs.homeID || teams.contains(team) else { return state }
        var next = state
        next.selection = team
        return next
    }

    /// Something on a page asked for `team`'s page (`TeamNavigator`), such
    /// as a leader tapped on a leaderboard.
    ///
    /// A favorite is selected, as a tap on its tab would, and shown at its
    /// own page: anything pushed over it is popped, so a player sheet asked
    /// for with it opens on the page on screen. Any other team's page is
    /// pushed over the selected tab's page, unless it's the one on top
    /// already; Home has no page stack, so from Home nothing happens.
    /// Settings and a pending link are left alone.
    static func teamOpened(_ state: State, team: TeamRef, teams: [TeamRef.ID]) -> State {
        var next = state
        if teams.contains(team.id) {
            next.selection = team.id
            next.visits[team.id] = nil
            return next
        }
        // No tab to push it over.
        guard teams.contains(next.selection) else { return state }
        var path = next.visits[next.selection] ?? []
        if path.last?.team.id != team.id {
            path.append(TeamVisit(team: team))
        }
        next.visits[next.selection] = path
        return next
    }

    /// A widget link arrived (or `Home` appeared with one). A resolved
    /// team is selected at once and a team that is not a favorite is
    /// dropped; a favorite still resolving stays pending for
    /// `favoritesResolved`.
    /// A game waiting on the link opens with its team, or goes with it.
    static func linkChanged(_ state: State, teams: [TeamRef.ID], favoriteIDs: [TeamRef.ID]) -> State {
        guard let id = state.pendingLink else { return state }
        var next = state
        if teams.contains(id) {
            next.selection = id
            next.pendingLink = nil
            linkHandled(&next, selected: true)
        } else if !favoriteIDs.contains(id) {
            next.pendingLink = nil
            linkHandled(&next, selected: false)
        }
        return next
    }
}

/// A game a link opened, with the favorite whose page its sheet is over
/// (`Home.linkedGame`, R-3).
struct LinkedGame: Identifiable {
    let game: Game
    let team: TeamRef

    var id: String { game.gameID }
}

/// Another team's page pushed over a favorite's (`HomeRouting.teamOpened`):
/// a team that isn't followed, opened from something on a page.
struct TeamVisit: Hashable, Sendable {
    let team: TeamRef
}

/// A player whose sheet a team page is to open once it's on screen: asked
/// for with the team's page (`TeamNavigator.open`), as when a leader is
/// tapped on a leaderboard (t_8d15e070).
struct PendingPlayer: Equatable, Sendable {
    let teamID: TeamRef.ID
    /// The player's `id` on the team's roster: the ESPN athlete id.
    let playerID: String

    enum Outcome: Equatable, Sendable {
        /// Not for this page, or its roster is still loading: keep it.
        case wait
        /// Open this player's sheet, and forget the request.
        case present(String)
        /// The roster has answered without the player: forget it.
        case drop
    }

    /// What `teamID`'s page, its roster holding `rosterIDs` and in
    /// `rosterState`, does with the request.
    func outcome(teamID: TeamRef.ID, rosterIDs: [String], rosterState: SectionLoadState) -> Outcome {
        guard teamID == self.teamID else { return .wait }
        if rosterIDs.contains(playerID) { return .present(playerID) }
        return rosterState == .loading ? .wait : .drop
    }
}

/// How anything on a team page opens another team's page, and a player's
/// sheet on it (t_8d15e070). `Home` puts one in the environment, handles
/// each `request` (`HomeRouting.teamOpened`), and the team page on screen
/// takes the `pendingPlayer` meant for it.
@MainActor
@Observable
final class TeamNavigator {
    /// A team's page asked for and not yet handled by `Home`.
    private(set) var request: TeamRef?

    /// A player sheet asked for with `request`, until the team's page has
    /// opened it (`takePlayer`), so it opens once.
    private(set) var pendingPlayer: PendingPlayer?

    /// The lookup behind `open(teamID:playerID:)`, so a later tap wins.
    @ObservationIgnored private var resolving: Task<Void, Never>?

    /// Opens `team`'s page — its tab if it's a favorite, else pushed over
    /// the page on screen — and then, given `playerID`, that player's
    /// sheet on it. A request without a player clears any earlier one.
    func open(_ team: TeamRef, playerID: String? = nil) {
        resolving?.cancel()
        resolving = nil
        pendingPlayer = playerID.map { PendingPlayer(teamID: team.id, playerID: $0) }
        request = team
    }

    /// `open(_:playerID:)` for a team known only by its id, such as a
    /// leader's: looked up in the catalog first, else its placeholder.
    func open(teamID: TeamRef.ID, playerID: String? = nil) {
        resolving?.cancel()
        resolving = Task {
            let found = await FavoritesStore.resolve(teamID, within: .seconds(2))
            guard !Task.isCancelled, let team = found ?? TeamRef.placeholder(id: teamID) else { return }
            open(team, playerID: playerID)
        }
    }

    /// The request, handed to `Home` once.
    func takeRequest() -> TeamRef? {
        defer { request = nil }
        return request
    }

    /// The player whose sheet `teamID`'s page opens now, if any: the
    /// pending one when the page's roster lists them. Cleared once taken,
    /// or once the roster has answered without them, so it never opens
    /// twice.
    func takePlayer(for teamID: TeamRef.ID, rosterIDs: [String], rosterState: SectionLoadState) -> String? {
        guard let pending = pendingPlayer else { return nil }
        switch pending.outcome(teamID: teamID, rosterIDs: rosterIDs, rosterState: rosterState) {
        case .wait:
            return nil
        case .present(let id):
            pendingPlayer = nil
            return id
        case .drop:
            pendingPlayer = nil
            return nil
        }
    }
}

/// What a team page's scrolling content tells the page around it
/// (`TeamPage`): how tall the summary at the top of the page is. Set only
/// as that changes, never per scrolled frame.
@MainActor
@Observable
final class TeamPageChrome {
    /// The summary's height (`TeamPageHeader`), which the team colour
    /// behind it must cover.
    var headerHeight: CGFloat = 0

    /// What pulling the page down does: set by the content, which owns the
    /// team's model (`TeamModel.refreshAll()`, C-1). Not drawn, so not
    /// observed.
    @ObservationIgnored var refresh: (@MainActor @Sendable () async -> Void)?
}

/// One team's scrolling page: the team's crest and name pinned in the
/// navigation bar over the team colour, and below it the page — the
/// record and next game over the team colour, then the page of cards
/// (UI-1, t_5478d64e).
///
/// Layered back to front, so the bar's content is never drawn under or
/// over the cards by construction: the team colour; the scroll view; an
/// opaque team-colour layer exactly covering the status bar and the
/// navigation bar (`barBackdrop`), which the page scrolls beneath; then the
/// system bar with the crest and name (`TeamBarTitle`). Nothing in the bar
/// depends on the scroll offset, so it's the same at rest, scrolled and
/// pulled past the top. The crest is drawn once, in the bar.
///
/// A favorite's tab holds its page in a navigation stack, over which
/// other teams' pages are pushed (`TeamVisit`, t_8d15e070): each the same
/// page (`TeamPageBody`), with a back button and the follow button.
private struct TeamPage: View {
    let team: TeamRef
    let pages: TeamPages
    /// The other teams' pages pushed over this one.
    @Binding var path: [TeamVisit]
    /// Opens Settings, which `Home` presents so that it outlives the page
    /// (A-5).
    let showSettings: @MainActor () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            TeamPageBody(team: team, pages: pages, isVisit: false, showSettings: showSettings)
                .navigationDestination(for: TeamVisit.self) { visit in
                    TeamPageBody(team: visit.team, pages: pages, isVisit: true, showSettings: showSettings)
                }
        }
    }
}

/// The page is mounted only while it's on screen, so it reports its scroll
/// offset to `pages` as it moves and opens where it was left through a
/// `ScrollPosition`.
private struct TeamPageBody: View {
    let team: TeamRef
    /// Keeps the team's model and scroll offset while the page is not
    /// mounted.
    let pages: TeamPages
    /// Pushed over a favorite's page for a team that wasn't followed
    /// (`TeamVisit`): the bar has the follow button and a back button
    /// where the app's mark sits.
    let isVisit: Bool
    let showSettings: @MainActor () -> Void

    @State private var position = ScrollPosition(edge: .top)

    @State private var chrome = TeamPageChrome()

    @Environment(\.containerSize) private var containerSize

    /// The team colour, or the fallback its badge takes when the feed has
    /// none, so the bar's ink and crest variant are picked against what is
    /// drawn.
    private var heroHex: String { TeamColors.fillHex(for: team) }

    /// The bar's colour scheme over the team colour (H-6): dark, for a white
    /// status bar and controls, when white reads better on it than black.
    private var heroBarScheme: ColorScheme {
        TeamColors.inkHex(on: heroHex) == "FFFFFF" ? .dark : .light
    }

    /// Tall enough to sit behind the summary and the page's rounded top
    /// with room to spare for pulling the page down, on any device and at
    /// any text size.
    private var heroHeight: CGFloat {
        max(containerSize.height / 2, chrome.headerHeight + containerSize.height / 4)
    }

    /// The team colour behind the status bar and the navigation bar, and
    /// only there: a zero-height view at the top of the safe area whose
    /// background takes the top safe area, which is exactly the two bars.
    /// Opaque and above the scroll view, so the page scrolls under it and
    /// never shows behind the bar's crest and name.
    private var barBackdrop: some View {
        Color.clear
            .frame(height: 0)
            .background(alignment: .bottom) {
                Color(hexString: heroHex)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The team colour. It never scrolls: the cards cover it. It
            // extends under the navigation bar, the status bar and any
            // landscape side insets (H-5, B5). Flat, so it meets
            // `barBackdrop` without a seam.
            Rectangle()
                .fill(Color(hexString: heroHex))
                .frame(height: heroHeight)
                .backgroundExtensionEffect()
                .accessibilityHidden(true)

            // Not ignoring the top safe area: the scroll view starts its
            // content — the summary, then the cards — below the navigation
            // bar and scrolls it under `barBackdrop`. Full width:
            // `TeamHomeLayout` insets its own section cards on the grouped
            // background (T-4).
            ScrollView(.vertical) {
                TeamHomeView(team: team, pages: pages)
            }
            .scrollIndicators(.hidden)
            // Pull to refresh every feed, whatever its age (C-1). The
            // content sets what that does; the spinner shows until every
            // feed has answered.
            .refreshable { [chrome] in
                await chrome.refresh?()
            }
            // The page scrolls under the tab bar; the soft edge fades it
            // there, so neither the tabs nor the cards fight for legibility
            // (T-5, B5).
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // The bar is opaque team colour: nothing to soften there.
            .scrollEdgeEffectHidden(true, for: .top)
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                pages.setScrollOffset(max(offset, 0), for: team.id)
            }
            .onAppear {
                // The team's model outlives the page, so its content is
                // already laid out at full height here.
                let savedOffset = pages.scrollOffset(for: team.id)
                if savedOffset > 0 {
                    position.scrollTo(point: CGPoint(x: 0, y: savedOffset))
                }
            }

            // Drawn after the scroll view, so over the page.
            barBackdrop
        }
        // The grouped page behind the hero, showing past the foot of the
        // page and under the tab bar, the colour of the page.
        .background(Theme.Surface.content)
        .environment(chrome)
        .navigationTitle(team.displayName)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // The crest and name, always: pinned in the bar, at every
            // scroll offset (H-3).
            ToolbarItem(placement: .principal) {
                TeamBarTitle(team: team, backgroundHex: heroHex)
            }
            // A title, not a button: no glass behind it.
            .sharedBackgroundVisibility(.hidden)

            // The app's mark, small, in the bar's ink: the white silhouette
            // as a template, so it reads on any team colour. A visit has its
            // back button there instead.
            if !isVisit {
                ToolbarItem(placement: .topBarLeading) {
                    BrandBarLogo(backgroundHex: heroHex)
                }
                // A mark, not a button: no glass behind it.
                .sharedBackgroundVisibility(.hidden)
            }

            // Beside the gear on a team that wasn't followed when its page
            // opened; never on a favorite's own page (t_8d15e070).
            if isVisit {
                ToolbarItem(placement: .topBarTrailing) {
                    FollowTeamButton(team: team)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home.settings")
            }
        }
        // The system bar in the team colour too, and the scheme that reads
        // on it whatever is scrolled beneath.
        .toolbarBackground(Color(hexString: heroHex), for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(heroBarScheme, for: .navigationBar)
    }
}

/// The follow button in a visited team's bar (`TeamVisit`, t_8d15e070): a
/// plus that follows the team (`FavoritesStore.toggle`, which adds it), so
/// its tab joins the bar.
///
/// Undo is the same button: once followed it stays in the bar as a filled
/// checkmark, and a second tap unfollows the team and turns it back into
/// the plus. A toggle rather than a timed "Added — Undo" banner, so undoing
/// is never a race against a timer and reads the same to VoiceOver. A
/// favorite's own page has no button: it's followed already, and Settings
/// is where teams are unfollowed.
private struct FollowTeamButton: View {
    let team: TeamRef

    private var store: FavoritesStore { .shared }

    var body: some View {
        let followed = store.isFavorite(team.id)
        Button {
            store.toggle(team)
        } label: {
            Label(
                followed ? "Following" : "Follow",
                systemImage: followed ? "checkmark.circle.fill" : "plus.circle"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(followed ? "Following \(team.displayName)" : "Follow \(team.displayName)")
        .accessibilityHint(followed ? "Unfollows the team." : "Adds the team to your teams.")
        .accessibilityAddTraits(followed ? .isSelected : [])
        .accessibilityIdentifier("teamPage.follow")
        .sensoryFeedback(.selection, trigger: followed)
    }
}

/// A team page's bar title: the team's crest — the page's only one — and
/// its name, in the ink and crest variant for the team colour behind the
/// bar (`teamInk(onHex:)`, `TeamColors.logoVariant`).
private struct TeamBarTitle: View {
    let team: TeamRef
    let backgroundHex: String

    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 28

    var body: some View {
        // Capped: the bar doesn't grow with the text.
        let size = min(crestSize, 36)
        let variant = TeamColors.logoVariant(for: team, onBackground: backgroundHex)
        // A crest that would vanish into the bar is traced in the bar's
        // ink, at full size and with nothing behind it (B-4, t_fa6748f4).
        let outlined = BarCrest.needsOutline(team: team, variant: variant, onHex: backgroundHex)
        HStack(spacing: Theme.Spacing.s) {
            TeamLogo(team: team, size: size, forceVariant: variant)
                .frame(width: size, height: size)
                .modifier(CrestOutline(isOn: outlined, inkHex: TeamColors.inkHex(on: backgroundHex)))
                .accessibilityHidden(true)

            Text(team.displayName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .teamInk(onHex: backgroundHex)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("teamPage.header")
    }
}

/// A bar crest that would blend into the bar (`BarCrest.needsOutline`),
/// set off from it without a shape behind it: a hairline in the bar's ink
/// traced around the crest's own silhouette — its alpha shadowed a point
/// each way, so the line follows the artwork's edge — and a soft shadow in
/// the same ink beneath. The ink is white or black against the team colour,
/// whatever the app's appearance, so the crest reads in light and dark.
private struct CrestOutline: ViewModifier {
    let isOn: Bool
    let inkHex: String

    private var ink: Color { Color(hexString: inkHex) }

    func body(content: Content) -> some View {
        if isOn {
            content
                // One layer, so the outline traces the whole crest rather
                // than each piece of it.
                .compositingGroup()
                .shadow(color: ink, radius: 0, x: BarCrest.outlineWidth, y: 0)
                .shadow(color: ink, radius: 0, x: -BarCrest.outlineWidth, y: 0)
                .shadow(color: ink, radius: 0, x: 0, y: BarCrest.outlineWidth)
                .shadow(color: ink, radius: 0, x: 0, y: -BarCrest.outlineWidth)
                .shadow(color: ink.opacity(0.35), radius: 2, x: 0, y: 1)
        } else {
            content
        }
    }
}

/// The myTeams mark in a team page's bar: the mono-white logo drawn as a
/// template in the bar's ink (`teamInk(onHex:)`), white or black, so it
/// reads on whatever the team colour is, like the title beside it.
private struct BrandBarLogo: View {
    let backgroundHex: String

    var body: some View {
        Image("myTeamsLogoMonoWhite")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            // Fixed: brand presence, not a control that grows with text.
            .frame(height: BrandLogo.bar)
            .teamInk(onHex: backgroundHex)
            .accessibilityLabel("myTeams")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("home.brandLogo")
    }
}

/// How Home's tab and the favorites' tabs fit the system tab bar: adding
/// teams is in Settings (t_fa6748f4).
enum HomeTabs {
    /// The most items a compact-width tab bar shows. With more tabs it
    /// shows one fewer and a "More" item listing the rest.
    static let compactCapacity = 5

    /// Home's tab value (`Home.selection`). Not a `TeamRef.ID`, which is
    /// always `"sport/league:id"`, so it never names a team.
    static let homeID: TeamRef.ID = "home"

    /// The tabs before the favorites': Home's. The favorites get the rest
    /// of the bar's room.
    static let fixedTabCount = 1

    /// How many of `teamCount` favorites' tabs the bar itself shows, in
    /// order, for a bar of `barCapacity` (no limit for `nil`): all of them
    /// while they fit, otherwise one fewer than the capacity, the last slot
    /// going to "More". The rest are listed under "More".
    static func barCount(teamCount: Int, barCapacity: Int?) -> Int {
        guard let barCapacity, teamCount > barCapacity else { return teamCount }
        return max(0, barCapacity - 1)
    }
}

/// A favorite's crest as a tab item's image.
///
/// A tab item is a `UITabBarItem` underneath: SwiftUI takes one finished
/// image from its label, and a view that loads one later (`TeamLogo`,
/// `RemoteImage`) never reaches the bar. So the image is drawn here from
/// what is on hand: the crest stored in `LogoStore` (for the scheme's
/// variant, else the default one), the bundled asset, or the team's
/// `MonogramTeam` badge, with the sport's symbol as a last resort. `Home`
/// fetches missing crests into `LogoStore` (`prefetch`) and redraws the items
/// as they land.
///
/// Drawn at a fixed tab-icon size and kept in full colour
/// (`.alwaysOriginal`): a template-rendered crest would be a flat
/// silhouette.
@MainActor
enum TabCrest {
    /// About a standard tab bar icon.
    static let size: CGFloat = 28

    /// Crests already drawn, by team, scale and source (`sourceKey`). An
    /// `NSCache`, so it gives memory back under pressure (A-17).
    private static let drawn: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    /// The variant for the colour scheme, as `TeamLogo` picks it.
    static func variant(for team: TeamRef, dark: Bool) -> LogoVariant {
        dark && LogoStore.sourceURL(for: team, variant: .dark) != nil ? .dark : .default
    }

    static func image(for team: TeamRef, dark: Bool, scale: CGFloat) -> UIImage {
        let source = source(for: team, dark: dark)
        let key = "\(team.id)|\(scale)|\(source.key)" as NSString
        if let image = drawn.object(forKey: key) {
            return image
        }
        let image = draw(source.image ?? monogram(team, scale: scale), scale: scale)
        drawn.setObject(image, forKey: key)
        return image
    }

    /// A key for a stored crest that changes whenever the file does: its
    /// path and modification date. Never the decoded image's identity,
    /// which `LogoStore`'s cache may evict and reallocate at the same
    /// address for another crest (A-17).
    nonisolated static func sourceKey(path: String, modified: Date?) -> String {
        "file:\(path)@\(modified?.timeIntervalSinceReferenceDate ?? 0)"
    }

    /// The stored crest's `sourceKey`.
    static func sourceKey(of file: URL) -> String {
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return sourceKey(path: file.path(percentEncoded: false), modified: modified)
    }

    /// What the tab item is drawn from — the stored crest for the scheme's
    /// variant, else the default one, else the bundled asset — and a key
    /// naming it. `nil` with `"monogram"` when there's none.
    private static func source(for team: TeamRef, dark: Bool) -> (image: UIImage?, key: String) {
        let wanted = variant(for: team, dark: dark)
        for candidate in [wanted, LogoVariant.default] {
            if let file = LogoStore.url(for: team, variant: candidate),
               let image = LogoStore.image(for: team, variant: candidate) {
                return (image, sourceKey(of: file))
            }
        }
        if let asset = team.logoAsset, let image = UIImage(named: asset) {
            return (image, "asset:\(asset)")
        }
        return (nil, "monogram")
    }

    /// Fetches the team's crest into `LogoStore` if it isn't there.
    /// Whether one newly arrived.
    static func prefetch(_ team: TeamRef, dark: Bool) async -> Bool {
        let variant = variant(for: team, dark: dark)
        guard LogoStore.url(for: team, variant: variant) == nil else { return false }
        return await LogoStore.prefetched(team, variant: variant)
    }

    /// The crest fitted into the icon's square, centred.
    private static func draw(_ source: UIImage?, scale: CGFloat) -> UIImage {
        let canvas = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            guard let source, source.size.width > 0, source.size.height > 0 else { return }
            let ratio = min(canvas.width / source.size.width, canvas.height / source.size.height)
            let fitted = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
            source.draw(in: CGRect(
                x: (canvas.width - fitted.width) / 2,
                y: (canvas.height - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            ))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// The badge `TeamLogo` draws for a team with no crest, else the
    /// sport's symbol.
    private static func monogram(_ team: TeamRef, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: MonogramTeam(team: team, size: size))
        renderer.scale = scale
        return renderer.uiImage
            ?? UIImage(systemName: TeamColors.symbolName(for: team.league.descriptor.kind))
    }
}

/// The crest in a team page's bar against the opaque team colour behind it
/// (B-4). `logoVariant` swaps in the dark crest on a dark bar only when the
/// feed has one, so a crest in the team's own colour, or a light crest on a
/// light bar, can blend into the bar. Such a crest is outlined in the bar's
/// ink (`CrestOutline`); it used to sit on a disc, which read as a badge
/// rather than the team's crest (t_fa6748f4).
@MainActor
enum BarCrest {
    /// Below this contrast between the crest's dominant colour and the bar,
    /// the crest gets its outline. Low on purpose: a crest is artwork with
    /// edges and detail of its own, not text, so only a near match fails.
    nonisolated static let minimumContrast = 2.0

    /// The outline's width, in points: a hairline, enough to draw the
    /// crest's edge without becoming a border.
    static let outlineWidth: CGFloat = 1

    /// Dominant luminances measured so far, by `TabCrest.sourceKey`, so a
    /// changed file is measured again.
    private static let measured: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 100
        return cache
    }()

    /// Whether a crest whose dominant colour has `dominantLuminance` (WCAG
    /// relative luminance, 0 to 1) is too close to the bar's `heroHex` to
    /// read on it. Never for a colour that isn't a hex colour.
    nonisolated static func crestNeedsOutline(dominantLuminance: Double, heroHex: String) -> Bool {
        guard let bar = TeamColors.relativeLuminance(hex: heroHex) else { return false }
        let ratio = (max(dominantLuminance, bar) + 0.05) / (min(dominantLuminance, bar) + 0.05)
        return ratio < minimumContrast
    }

    /// Whether the stored crest `TeamLogo` draws for `team` in `variant`
    /// needs the outline on `heroHex`. No for a crest not stored yet: the
    /// monogram it falls back to is a badge already.
    static func needsOutline(team: TeamRef, variant: LogoVariant, onHex heroHex: String) -> Bool {
        guard let file = LogoStore.url(for: team, variant: variant) else { return false }
        let key = TabCrest.sourceKey(of: file) as NSString
        let luminance: Double
        if let cached = measured.object(forKey: key) {
            luminance = cached.doubleValue
        } else {
            guard let image = LogoStore.image(for: team, variant: variant),
                  let dominant = dominantLuminance(of: image)
            else { return false }
            measured.setObject(NSNumber(value: dominant), forKey: key)
            luminance = dominant
        }
        return crestNeedsOutline(dominantLuminance: luminance, heroHex: heroHex)
    }

    /// The relative luminance of the image's most common shade: its opaque
    /// pixels, sampled on a small grid, sorted into luminance bands, and
    /// the busiest band's mean. `nil` for an image with no opaque pixels.
    nonisolated static func dominantLuminance(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bands = 8
        var counts = [Int](repeating: 0, count: bands)
        var sums = [Double](repeating: 0, count: bands)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            // Edges and shadows are mostly transparent: only the crest.
            guard alpha >= 0.5 else { continue }
            func channel(_ value: UInt8) -> Double {
                // Un-premultiplied, then linearized as WCAG does.
                let c = min(Double(value) / 255 / alpha, 1)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * channel(pixels[offset])
                + 0.7152 * channel(pixels[offset + 1])
                + 0.0722 * channel(pixels[offset + 2])
            let band = min(Int(luminance * Double(bands)), bands - 1)
            counts[band] += 1
            sums[band] += luminance
        }
        guard let busiest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[busiest] > 0 else {
            return nil
        }
        return sums[busiest] / Double(counts[busiest])
    }
}

/// iPad (B-14): on regular width the tab bar can become a sidebar, which
/// lists Home and every favorite rather than a stretched phone bar. Compact width
/// keeps the plain tab bar and its "More" item. Like the bar, it lists
/// teams only: adding teams is in Settings (t_fa6748f4).
private struct HomeSidebar: ViewModifier {
    let isRegularWidth: Bool

    func body(content: Content) -> some View {
        if isRegularWidth {
            content
                .tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

#Preview {
    Home(deepLinkedTeamID: .constant(nil))
}
