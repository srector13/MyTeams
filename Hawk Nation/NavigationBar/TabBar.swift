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
/// picker pinned to the bottom.
struct Home: View {
    /// The favorites as teams. Starts with those the bundled catalog knows,
    /// so the first frame has the seed teams, then fills in from the catalog.
    @State private var teams: [TeamRef] = FavoritesStore.shared.teamIDs.compactMap(TeamCatalog.team(id:))

    @State private var selection: TeamRef.ID = FavoritesStore.shared.teamIDs.first ?? ""

    @State private var showsBrowser = false

    @Bindable private var store = FavoritesStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Every page stays mounted and is shown by opacity, so each
                // keeps its scroll position and its loaded data when the
                // reader moves between teams.
                ForEach(teams) { team in
                    TeamPage(team: team) { TeamHomeView(team: team) }
                        .opacity(selection == team.id ? 1 : 0)
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
            // Attaching the picker as a safe area inset lets SwiftUI sit it
            // above the home indicator and extend its material behind it,
            // which the original did by hand from the window's insets.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TeamPicker(teams: teams, selection: $selection) {
                    showsBrowser = true
                }
            }
            .environment(\.containerSize, proxy.size)
        }
        .task(id: store.teamIDs) {
            teams = await store.teamRefs()
            if !teams.contains(where: { $0.id == selection }) {
                selection = teams.first?.id ?? ""
            }
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

/// One team's scrolling page: the crest scrolls away under a title bar that
/// takes its place at the top.
private struct TeamPage<Content: View>: View {
    let team: TeamRef
    @ViewBuilder var content: Content

    /// Whether the crest has scrolled far enough to hand off to the sticky bar.
    @State private var showsStickyHeader = false

    @Environment(\.containerSize) private var containerSize

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .foregroundStyle(team.color)
                .frame(height: 500)
                .ignoresSafeArea(edges: .top)

            ScrollView(.vertical) {
                VStack {
                    // Drawn over the team colour, so a dark background takes
                    // the dark crest where the feed has one.
                    TeamLogo(
                        team: team,
                        size: max(containerSize.width - 50, 0),
                        forceVariant: TeamColors.logoVariant(for: team, onBackground: team.colorHex)
                    )
                    .opacity(0.5)
                    .offset(x: 50)
                    // The crest deliberately overflows its slot: only the
                    // top sliver shows until the page is scrolled.
                    .frame(height: containerSize.height / 14)

                    VStack {
                        HStack(alignment: .bottom) {
                            Text(team.displayName)
                                .fontWeight(.bold)
                                .font(.system(size: 35))
                                .foregroundStyle(.white)
                                .padding(.leading, 15)
                            Spacer()
                        }
                        .ignoresSafeArea()

                        content
                    }
                    .padding([.top, .horizontal])
                }
                .background {
                    // Reports how far the page has scrolled, in place of the
                    // 0.1-second timer the original polled the offset with.
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: proxy.frame(in: .scrollView).minY
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                let scrolledPast = -offset > (containerSize.height / 4) - 50
                guard scrolledPast != showsStickyHeader else { return }
                withAnimation {
                    showsStickyHeader = scrolledPast
                }
            }

            if showsStickyHeader {
                TopView(team: team)
                    .transition(.opacity)
            }
        }
    }
}

/// How far the team page has scrolled, in points from its resting position.
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The crest row pinned to the bottom of the screen. The selected team's crest
/// grows a label and a coloured capsule. Scrolls sideways once the favorites
/// outgrow the width, and ends in a button that opens the team picker.
private struct TeamPicker: View {
    let teams: [TeamRef]
    @Binding var selection: TeamRef.ID
    let editTeams: () -> Void

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(teams) { team in
                        Button {
                            selection = team.id
                        } label: {
                            HStack(spacing: 6) {
                                TeamLogo(team: team, size: 25)

                                if selection == team.id {
                                    Text(team.shortName)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal)
                            .background(selection == team.id ? team.color : .clear)
                            .clipShape(.capsule)
                        }
                        .accessibilityLabel(team.displayName)
                        .id(team.id)
                    }

                    Button(action: editTeams) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 35, height: 35)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(.circle)
                    }
                    .padding(.leading, 6)
                    .accessibilityLabel("Add or Edit Teams")
                }
                .padding(.horizontal, 25)
            }
            .onChange(of: selection) { _, selected in
                withAnimation {
                    reader.scrollTo(selected)
                }
            }
        }
        .animation(.default, value: selection)
        .padding(.top)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

/// The title bar that slides in once a team's crest has scrolled away.
struct TopView: View {
    var team: TeamRef

    var body: some View {
        HStack(alignment: .center) {
            TeamLogo(team: team, size: 40)
                .padding(.leading)

            Text(team.displayName)
                .font(.title)
                .fontWeight(.bold)
            Spacer(minLength: 0)
        }
        .padding(.top, 5)
        .padding(.horizontal)
        .padding(.bottom)
        .background {
            // The bar sits below the status bar but its material runs up
            // behind it, so the crest scrolls away under frosted glass.
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .top)
        }
    }
}

#Preview {
    Home()
}
