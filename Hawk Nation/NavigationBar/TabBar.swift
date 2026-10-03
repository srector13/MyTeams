//
//  TabBar.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

// The teams on this screen are the reader's favorites (`FavoritesStore`),
// resolved through `RemoteTeamCatalog` and shown in favorites order.

/// The app's root screen: one scrolling team page at a time, with a crest
/// picker floating at the bottom.
struct Home: View {
    /// A team to switch to, set when a widget link opens the app. Cleared
    /// once handled; a team that is not a favorite is ignored.
    @Binding var deepLinkedTeamID: TeamRef.ID?

    /// The favorites as teams. Starts with those the bundled catalog knows,
    /// so the first frame has the seed teams, then fills in from the catalog.
    @State private var teams: [TeamRef] = FavoritesStore.shared.teamIDs.compactMap(TeamCatalog.team(id:))

    @State private var selection: TeamRef.ID = FavoritesStore.shared.teamIDs.first ?? ""

    @State private var showsBrowser = false

    /// Each team's model and scroll offset, kept while its page is not
    /// mounted.
    @State private var pages = TeamPages()

    @Bindable private var store = FavoritesStore.shared

    private var selectedTeam: TeamRef? {
        teams.first { $0.id == selection }
    }

    private var routing: HomeRouting.State {
        HomeRouting.State(selection: selection, pendingLink: deepLinkedTeamID)
    }

    private func apply(_ routed: HomeRouting.State) {
        if selection != routed.selection {
            selection = routed.selection
        }
        if deepLinkedTeamID != routed.pendingLink {
            deepLinkedTeamID = routed.pendingLink
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Only the selected team's page is mounted, so only it loads
                // and polls: its task is keyed on the selection, and leaving
                // the page cancels it. Every page used to stay mounted, each
                // polling on its own. `pages` keeps each team's loaded data
                // and scroll offset for when the reader comes back.
                if let team = selectedTeam {
                    TeamPage(
                        team: team,
                        savedOffset: pages.scrollOffset(for: team.id),
                        saveOffset: { pages.setScrollOffset($0, for: team.id) }
                    ) {
                        TeamHomeView(team: team, pages: pages)
                    }
                    .id(team.id)
                }

                if teams.isEmpty {
                    ContentUnavailableView {
                        Label("No Teams", systemImage: "star")
                    } description: {
                        Text("Follow a team to see its schedule, roster and news.")
                    } actions: {
                        Button("Pick Your Teams") { showsBrowser = true }
                    }
                }
            }
            // Attaching the picker as a safe-area bar lets SwiftUI sit it
            // above the home indicator and inset the page's content by its
            // height, which the original did by hand from the window's
            // insets. As a bar, rather than a plain inset, it takes part in
            // the page's scroll-edge effect, which keeps the crests legible
            // over the content scrolling under them (T-5).
            .safeAreaBar(edge: .bottom, spacing: 0) {
                TeamPicker(teams: teams, selection: $selection) {
                    showsBrowser = true
                }
            }
            .environment(\.containerSize, proxy.size)
        }
        .task(id: store.teamIDs) {
            pages.retain(store.teamIDs)
            teams = await store.teamRefs()
            apply(HomeRouting.favoritesResolved(routing, teams: teams.map(\.id)))
        }
        .onChange(of: deepLinkedTeamID, initial: true) { _, _ in
            apply(HomeRouting.linkChanged(routing, teams: teams.map(\.id), favoriteIDs: store.teamIDs))
        }
        .sheet(isPresented: $showsBrowser) {
            TeamBrowserView()
        }
        // A fresh install opens on "Pick your teams", the seed teams already
        // checked. Dismissing it, however, finishes onboarding.
        .sheet(isPresented: $store.needsOnboarding, onDismiss: { store.completeOnboarding() }) {
            TeamBrowserView(title: "Pick Your Teams")
        }
    }
}

/// Which team `Home` shows, and what becomes of a widget link, as plain
/// values: the view feeds it its state and applies the answer.
enum HomeRouting {
    struct State: Equatable, Sendable {
        /// The selected team's id; `""` with no teams.
        var selection: TeamRef.ID
        /// A widget link not yet handled (`Home.deepLinkedTeamID`).
        var pendingLink: TeamRef.ID?
    }

    /// The favorites have been resolved to `teams`, in order. A selection
    /// no longer among them falls back to the first; a link that arrived
    /// while the favorites were loading is handled now, selecting its team
    /// if it resolved and dropped either way.
    static func favoritesResolved(_ state: State, teams: [TeamRef.ID]) -> State {
        var next = state
        if !teams.contains(next.selection) {
            next.selection = teams.first ?? ""
        }
        if let id = next.pendingLink {
            next.pendingLink = nil
            if teams.contains(id) {
                next.selection = id
            }
        }
        return next
    }

    /// A widget link arrived (or `Home` appeared with one). A resolved
    /// team is selected at once and a team that is not a favorite is
    /// dropped; a favorite still resolving stays pending for
    /// `favoritesResolved`.
    static func linkChanged(_ state: State, teams: [TeamRef.ID], favoriteIDs: [TeamRef.ID]) -> State {
        guard let id = state.pendingLink else { return state }
        var next = state
        if teams.contains(id) {
            next.selection = id
            next.pendingLink = nil
        } else if !favoriteIDs.contains(id) {
            next.pendingLink = nil
        }
        return next
    }
}

/// One team's scrolling page: the crest scrolls away under the system
/// navigation bar, which carries the team's name and a small crest and
/// floats over the page (H-3).
///
/// The page is mounted only while its team is selected, so it reports its
/// scroll offset as it moves (`saveOffset`) and opens where it was left
/// (`savedOffset`) through a `ScrollPosition`.
private struct TeamPage<Content: View>: View {
    let team: TeamRef
    /// How far down the reader last left this team's page, in points.
    let savedOffset: CGFloat
    let saveOffset: @MainActor (CGFloat) -> Void
    @ViewBuilder var content: Content

    @State private var position = ScrollPosition(edge: .top)

    /// The bottom of the navigation bar, in global coordinates.
    @State private var barBottom: CGFloat = 0

    /// Whether the page's content, rather than the team colour, is behind
    /// the navigation bar.
    @State private var contentUnderBar = false

    @Environment(\.containerSize) private var containerSize

    /// The bar's colour scheme over the team colour (H-6): dark, for a white
    /// title and status bar, when white reads better on it than black.
    private var heroBarScheme: ColorScheme {
        TeamColors.inkHex(on: team.colorHex) == "FFFFFF" ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // The team-colour hero, sized from the screen rather than a
                // fixed 500 pt: deep enough to sit behind the crest and the
                // page's rounded top on any device. It starts at the safe
                // area and extends under the navigation bar, the status bar
                // and any landscape side insets (H-5, B5).
                Rectangle()
                    .foregroundStyle(team.color)
                    .frame(height: containerSize.height / 2)
                    .backgroundExtensionEffect()

                // Not ignoring the top safe area: the scroll view starts its
                // content below the navigation bar and scrolls it under.
                ScrollView(.vertical) {
                    VStack {
                        // Drawn over the team colour, so a dark background takes
                        // the dark crest where the feed has one.
                        TeamLogo(
                            team: team,
                            size: max(containerSize.width - 50, 0),
                            forceVariant: TeamColors.logoVariant(for: team, onBackground: team.colorHex)
                        )
                        // Dimmed into the team colour; stronger under
                        // Increase Contrast, solid under Reduce
                        // Transparency (X-5).
                        .adaptiveScrim(0.5)
                        .offset(x: 50)
                        // The crest deliberately overflows its slot: only the
                        // top sliver shows until the page is scrolled.
                        .frame(height: containerSize.height / 14)

                        // Full width: `TeamHomeLayout` insets its own
                        // section cards on the grouped background (T-4).
                        content
                            .padding(.top)
                            .onGeometryChange(for: Bool.self) { proxy in
                                proxy.frame(in: .global).minY < barBottom
                            } action: { covered in
                                contentUnderBar = covered
                            }
                    }
                }
                .scrollIndicators(.hidden)
                // The page scrolls under the floating crest picker; the soft
                // edge fades it there, so neither the crests nor the cards
                // fight for legibility (T-5, B5).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    saveOffset(max(offset, 0))
                }
                .onAppear {
                    // The team's model outlives the page, so its content is
                    // already laid out at full height here.
                    if savedOffset > 0 {
                        position.scrollTo(point: CGPoint(x: 0, y: savedOffset))
                    }
                }
            }
            // The grouped page behind the hero, showing past the foot of
            // the page and under the crest picker, the colour of the page.
            .background(Theme.Surface.content)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY + proxy.safeAreaInsets.top
            } action: { bottom in
                barBottom = bottom
            }
            .navigationTitle(team.displayName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    TeamLogo(team: team, size: 30)
                }
                // A crest, not a button: no glass behind it.
                .sharedBackgroundVisibility(.hidden)
            }
            // Over the team colour the bar takes the scheme that reads on
            // it; once the page's content is behind it, the system's.
            .toolbarColorScheme(contentUnderBar ? nil : heroBarScheme, for: .navigationBar)
        }
    }
}

/// The crest row floating above the bottom of the screen. The selected team's
/// crest grows a label in a glass pill tinted the team's colour. Scrolls
/// sideways once the favorites outgrow the width, and ends in a button that
/// opens the team picker.
///
/// The pill and the button are the row's only glass, in one container so
/// they share a sampling pass and the pill morphs between crests (H-1, H-2).
private struct TeamPicker: View {
    let teams: [TeamRef]
    @Binding var selection: TeamRef.ID
    let editTeams: () -> Void

    @Namespace private var glass

    /// Reduce Motion, for the scroll to the selected crest (H-7).
    private var settings = AdaptiveSettings()

    /// A crest, which scales with the selected team's name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 25

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(teams) { team in
                            crest(team)
                        }

                        Button(action: editTeams) {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                // The circle matches the crest pills at the
                                // default text size, so the symbol stops
                                // growing where it would outgrow the circle.
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .frame(width: 44, height: 44)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassChrome(in: Circle(), interactive: true)
                        .padding(.leading, 6)
                        .accessibilityLabel("Add or Edit Teams")
                        .accessibilityIdentifier("teamPicker.edit")
                    }
                    // Room for the interactive glass to swell inside the
                    // scroll view's clip.
                    .padding(.vertical, Theme.Spacing.s)
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
            .onChange(of: selection) { _, selected in
                withAnimation(Theme.Motion.animation(Theme.Motion.selection, reduceMotion: settings.reduceMotion)) {
                    reader.scrollTo(selected)
                }
            }
        }
        // The pill morphs to the new crest, or moves at once under Reduce
        // Motion; the haptic plays either way (H-7).
        .motionAnimation(Theme.Motion.selection, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func crest(_ team: TeamRef) -> some View {
        let selected = selection == team.id
        let fillHex = TeamColors.fillHex(for: team)
        return Button {
            selection = team.id
        } label: {
            HStack(spacing: 6) {
                TeamLogo(team: team, size: crestSize)

                if selected {
                    Text(team.shortName)
                        .teamInk(onHex: fillHex)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .contentShape(.capsule)
            .background {
                // One pill, handed from crest to crest by its glass ID. Only
                // a marker, so it takes no touches: interactive glass tracks
                // touches itself, and in a label it competes with the
                // crests' buttons for the tap that moves the selection.
                if selected {
                    Color.clear
                        .glassChrome(tint: Color(hexString: fillHex))
                        .glassEffectID("selection", in: glass)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(team.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("teamPicker.team.\(team.id)")
        .id(team.id)
    }
}

#Preview {
    Home(deepLinkedTeamID: .constant(nil))
}
