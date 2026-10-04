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

    /// Whether the tab bar has slid off the bottom (`TabBarCollapse`).
    @State private var barCollapsed = false
    /// Follows the page's scrolling for the bar; not observed.
    @State private var barTracker = TabBarCollapse()
    /// Bumped by each tab tap, restarting the wait before the bar goes.
    @State private var tabTaps = 0

    /// VoiceOver and Switch Control can't find a bar that has gone, so it
    /// stays up under either.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    private var settings = AdaptiveSettings()

    // Spelled out: the private `settings` makes the memberwise init private.
    init(deepLinkedTeamID: Binding<TeamRef.ID?>) {
        self._deepLinkedTeamID = deepLinkedTeamID
    }

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

    /// Slides the tab bar out or back, or fades it under Reduce Motion. Never
    /// out under VoiceOver or Switch Control, nor with no teams to show.
    private func setBarCollapsed(_ collapsed: Bool) {
        let collapse = collapsed && !voiceOver && !switchControl && !teams.isEmpty
        guard collapse != barCollapsed else { return }
        let animation = settings.reduceMotion ? Theme.Motion.reducedFade : TabBarCollapse.animation
        withAnimation(animation) {
            barCollapsed = collapse
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
                        saveOffset: { pages.setScrollOffset($0, for: team.id) },
                        barCollapsed: barCollapsed,
                        scrolled: { position, byUser in
                            if let collapse = barTracker.scrolled(to: position, byUser: byUser) {
                                setBarCollapsed(collapse)
                            }
                        }
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
            // over the content scrolling under them (T-5). A collapse only
            // moves the bar, so the page keeps its inset and never jumps.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                TeamPicker(
                    teams: teams,
                    selection: $selection,
                    collapsed: barCollapsed,
                    tabTapped: { tabTaps += 1 },
                    reveal: {
                        barTracker.revealed()
                        setBarCollapsed(false)
                    },
                    editTeams: { showsBrowser = true }
                )
            }
            .environment(\.containerSize, proxy.size)
        }
        // A tapped tab registers, then the bar slides away; another tap
        // restarts the wait.
        .task(id: tabTaps) {
            guard tabTaps > 0 else { return }
            try? await Task.sleep(for: TabBarCollapse.hideDelay)
            guard !Task.isCancelled else { return }
            setBarCollapsed(true)
        }
        // The new team's page reports its own offsets.
        .onChange(of: selection) {
            barTracker.reset()
        }
        .onChange(of: voiceOver || switchControl) { _, assistive in
            if assistive {
                setBarCollapsed(false)
            }
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
    /// Whether the tab bar is down, so the page drops its foot's edge
    /// effect with it.
    let barCollapsed: Bool
    /// Every move of the page, and whether the reader made it, for the tab
    /// bar's collapse (`TabBarCollapse`).
    let scrolled: @MainActor (TabBarCollapse.Position, _ byUser: Bool) -> Void
    @ViewBuilder var content: Content

    @State private var position = ScrollPosition(edge: .top)

    /// Whether the reader is scrolling the page, rather than it restoring
    /// its offset or standing still.
    @State private var userScrolling = false

    /// The bottom of the navigation bar, in global coordinates.
    @State private var barBottom: CGFloat = 0

    /// The status bar and navigation bar together: the team-colour header's
    /// height, about 44 pt plus the top safe area.
    @State private var barHeight: CGFloat = 0

    /// Whether the page's content, rather than the team colour, is behind
    /// the navigation bar.
    @State private var contentUnderBar = false

    @Environment(\.containerSize) private var containerSize

    /// The bar's colour scheme over the team colour (H-6): dark, for a white
    /// title and status bar, when white reads better on it than black.
    private var heroBarScheme: ColorScheme {
        TeamColors.inkHex(on: team.colorHex) == "FFFFFF" ? .dark : .light
    }

    /// The team's crest, large and dimmed into the team colour, peeking in
    /// from the trailing edge behind the bar's title.
    private var barWatermark: some View {
        // Drawn over the team colour, so a dark background takes the dark
        // crest where the feed has one.
        TeamLogo(
            team: team,
            size: 160,
            forceVariant: TeamColors.logoVariant(for: team, onBackground: team.colorHex)
        )
        // Dimmed into the team colour; stronger under Increase Contrast,
        // solid under Reduce Transparency (X-5).
        .adaptiveScrim(0.5)
        .offset(x: 40)
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

                // The crest watermark, behind the navigation bar only. Its
                // frame is the bar's height — status bar plus the bar's
                // 44 pt — and it is clipped there, so the crest's own size
                // never sets how tall the team-colour header is. The stack
                // starts at the bar's bottom, so the offset lifts it into
                // the bar exactly.
                barWatermark
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: barHeight, alignment: .center)
                    .clipped()
                    .offset(y: -barHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // Not ignoring the top safe area: the scroll view starts its
                // content below the navigation bar and scrolls it under.
                // Full width: `TeamHomeLayout` insets its own section cards
                // on the grouped background (T-4). It starts right at the
                // bar, so the header is a standard bar's height; the hero
                // shows only in the page's rounded top corners.
                ScrollView(.vertical) {
                    content
                        .onGeometryChange(for: Bool.self) { proxy in
                            proxy.frame(in: .global).minY < barBottom
                        } action: { covered in
                            contentUnderBar = covered
                        }
                }
                .scrollIndicators(.hidden)
                // The page scrolls under the floating crest picker; the soft
                // edge fades it there, so neither the crests nor the cards
                // fight for legibility (T-5, B5).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                // With the bar down there is nothing at the foot to keep
                // legible.
                .scrollEdgeEffectHidden(barCollapsed, for: .bottom)
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    saveOffset(max(offset, 0))
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating
                }
                .onScrollGeometryChange(for: TabBarCollapse.Position.self) { geometry in
                    TabBarCollapse.Position(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        maxOffset: geometry.contentSize.height + geometry.contentInsets.top
                            + geometry.contentInsets.bottom - geometry.containerSize.height
                    )
                } action: { _, position in
                    scrolled(position, userScrolling)
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { height in
                barHeight = height
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

/// The tab bar: one tab per favorite team, its crest over its short name,
/// then a button that opens the team picker. Scrolls sideways once the
/// favorites outgrow the width.
///
/// A standard iOS bar: a frosted `.bar` material with a hairline along its
/// top, so content scrolling under it never muddies the crests or labels.
/// The selected tab sits on a neutral marker that moves between tabs and
/// takes a legible team accent on its label. The marker is a plain fill,
/// not glass: a glass pill tinted the team's own colour used to bury the
/// selected crest, leaving only the tint.
///
/// `collapsed` slides the bar off the bottom (`TabBarCollapse`); while it
/// is down, a strip along the bottom edge brings it back on a swipe up or
/// a tap.
private struct TeamPicker: View {
    let teams: [TeamRef]
    @Binding var selection: TeamRef.ID
    let collapsed: Bool
    /// A tab was tapped, whether or not it changed the selection.
    let tabTapped: () -> Void
    let reveal: () -> Void
    let editTeams: () -> Void

    @Namespace private var marker

    /// Reduce Motion, for the scroll to the selected tab (H-7).
    private var settings = AdaptiveSettings()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// A crest, scaled with the label under it (B-3).
    @ScaledMetric(relativeTo: .caption2) private var crestSize: CGFloat = 25

    /// The bar's width, to share it between the tabs while they fit.
    @State private var barWidth: CGFloat = 0
    /// The bar's height down to the screen's foot, so a collapse slides it
    /// all the way off.
    @State private var barDepth: CGFloat = 0

    // Spelled out: the private `settings` makes the memberwise init private.
    init(
        teams: [TeamRef],
        selection: Binding<TeamRef.ID>,
        collapsed: Bool,
        tabTapped: @escaping () -> Void,
        reveal: @escaping () -> Void,
        editTeams: @escaping () -> Void
    ) {
        self.teams = teams
        self._selection = selection
        self.collapsed = collapsed
        self.tabTapped = tabTapped
        self.reveal = reveal
        self.editTeams = editTeams
    }

    /// Each tab's width: an even share of the bar while the tabs fit, the
    /// standard minimum once they scroll.
    private var itemWidth: CGFloat {
        let count = CGFloat(teams.count + 1)
        return max(TabBarStyle.minimumItemWidth, barWidth / count)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bar
                .offset(y: collapsed && !settings.reduceMotion ? barDepth : 0)
                .opacity(collapsed ? 0 : 1)
                .allowsHitTesting(!collapsed)
                .accessibilityHidden(collapsed)

            if collapsed {
                revealStrip
            }
        }
    }

    private var bar: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(teams) { team in
                        tab(team)
                    }
                    editButton
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: selection) { _, selected in
                withAnimation(Theme.Motion.animation(Theme.Motion.selection, reduceMotion: settings.reduceMotion)) {
                    reader.scrollTo(selected)
                }
            }
        }
        // The marker moves to the new tab, or at once under Reduce Motion;
        // the haptic plays either way (H-7).
        .motionAnimation(Theme.Motion.selection, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, 2)
        // The standard tab bar's material, down under the home indicator,
        // a shade deeper in Dark Mode so bright content behind it stays
        // muted. Opaque by itself under Reduce Transparency.
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(Color.black.opacity(colorScheme == .dark ? TabBarStyle.darkDimming : 0))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1 / displayScale)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            CGSize(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom)
        } action: { size in
            barWidth = size.width
            barDepth = size.height
        }
    }

    private func tab(_ team: TeamRef) -> some View {
        let selected = selection == team.id
        let accent = TabBarStyle.accentHex(for: team, dark: colorScheme == .dark).map { Color(hexString: $0) }
        return Button {
            selection = team.id
            tabTapped()
        } label: {
            VStack(spacing: 2) {
                // Drawn the same, at full strength, selected or not: only the
                // marker and the label carry the selection.
                TeamLogo(team: team, size: crestSize)
                    .scaleEffect(selected ? 1.08 : 1)

                Text(team.shortName)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(accent ?? .primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(width: itemWidth)
            .background {
                if selected {
                    Theme.Radius.chip
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .matchedGeometryEffect(id: "selection", in: marker)
                        .padding(.horizontal, Theme.Spacing.xs)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Tab bar items keep their size and show the large content viewer
        // past the largest standard size, as the system's do.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel(team.displayName)
        // SwiftUI's AccessibilityTraits has no tab-bar-item trait (that's
        // UIKit's UIAccessibilityTraits.tabBar), so announce as a button.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("teamPicker.team.\(team.id)")
        .id(team.id)
    }

    private var editButton: some View {
        Button(action: editTeams) {
            VStack(spacing: 2) {
                Image(systemName: "plus.circle")
                    .font(.system(size: crestSize * 0.88))
                    .frame(width: crestSize, height: crestSize)
                Text("Teams")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(width: itemWidth)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel("Add or Edit Teams")
        .accessibilityIdentifier("teamPicker.edit")
    }

    /// Along the foot of the screen while the bar is down: a swipe up from
    /// the bottom edge, or a tap, brings the bar back.
    private var revealStrip: some View {
        Color.clear
            .frame(height: TabBarStyle.revealStripHeight)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { drag in
                        if drag.translation.height < -TabBarCollapse.threshold {
                            reveal()
                        }
                    }
            )
            .onTapGesture(perform: reveal)
            .accessibilityElement()
            .accessibilityLabel("Show Tab Bar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { reveal() }
            .accessibilityIdentifier("tabBar.reveal")
    }
}

/// The tab bar's metrics and its selected tab's accent.
enum TabBarStyle {
    /// The narrowest a tab gets before the bar scrolls.
    static let minimumItemWidth: CGFloat = 76
    /// How much darker the bar's material is in Dark Mode.
    static let darkDimming: Double = 0.12
    /// The strip along the bottom edge that brings a collapsed bar back.
    static let revealStripHeight: CGFloat = 24

    /// Roughly the `.bar` material's colour, in each scheme, for picking an
    /// accent that reads on it.
    static let lightBarHex = "F7F7F7"
    static let darkBarHex = "1C1C1E"

    /// WCAG's bar for large text and UI components: a tab label is short and
    /// bold, and the marker and the selected trait back it up.
    static let minimumAccentContrast = 3.0

    /// The selected tab's label colour: the team colour, else its alternate,
    /// whichever first reaches `minimumAccentContrast` on the bar; `nil`,
    /// for the primary label colour, when neither does. Pure so it can be
    /// unit-tested.
    static func accentHex(for team: TeamRef, dark: Bool) -> String? {
        let bar = dark ? darkBarHex : lightBarHex
        return [TeamColors.fillHex(for: team), team.alternateColorHex].first { hex in
            (TeamColors.contrastRatio(hex, bar) ?? 0) >= minimumAccentContrast
        }
    }
}

/// When the tab bar collapses and comes back, from the page's scroll
/// offset: down when the reader scrolls the page down, back when they
/// scroll up, pull past the top, or reach the foot of the page. Only the
/// reader's own scrolling counts; a page restoring its offset moves the
/// baseline and nothing else. `Home` also collapses the bar shortly after
/// a tab is tapped (`hideDelay`).
///
/// A class kept in `@State` and not observed, so following every scroll
/// frame redraws nothing; `Home` keeps the collapsed flag itself and sets it
/// only on a change.
final class TabBarCollapse {
    /// How far the page moves one way before the bar follows.
    static let threshold: CGFloat = 12
    /// The pause after a tab tap before the bar goes, so the tap shows.
    static let hideDelay: Duration = .milliseconds(600)
    /// The bar's slide out and back.
    static let animation: Animation = .easeInOut(duration: 0.35)

    /// Where the page is, in points from the top of its content, and the
    /// furthest it scrolls.
    struct Position: Equatable, Sendable {
        var offset: CGFloat
        var maxOffset: CGFloat
    }

    /// Where the current run in one direction started.
    private var anchor: CGFloat?
    private var last: CGFloat?

    /// Forgets the page: the next position is a new baseline.
    func reset() {
        anchor = nil
        last = nil
    }

    /// The bar came back some other way: the current run starts here.
    func revealed() {
        anchor = last
    }

    /// The page moved to `position`. `true` to collapse the bar, `false` to
    /// bring it back, `nil` to leave it.
    func scrolled(to position: Position, byUser: Bool) -> Bool? {
        let offset = position.offset
        defer { last = offset }
        guard byUser, let last, let start = anchor else {
            anchor = offset
            return nil
        }
        // A turn starts a new run from where the page turned.
        if (offset - last) * (last - start) < 0 {
            anchor = last
        }
        let travel = offset - (anchor ?? last)
        let atFoot = position.maxOffset > Self.threshold && offset >= position.maxOffset - Self.threshold
        if atFoot || travel < -Self.threshold {
            anchor = offset
            return false
        }
        if travel > Self.threshold && offset > 0 {
            anchor = offset
            return true
        }
        return nil
    }
}

#Preview {
    Home(deepLinkedTeamID: .constant(nil))
}
