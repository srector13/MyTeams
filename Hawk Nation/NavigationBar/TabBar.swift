//
//  TabBar.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

// The teams on this screen are `FavoriteTeams.teams`, drawn from the bundled
// catalog (Networking/TeamRef.swift).

/// The app's root screen: one scrolling team page at a time, with a crest
/// picker pinned to the bottom.
struct Home: View {
    private let teams = FavoriteTeams.teams

    @State private var selection: TeamRef.ID = FavoriteTeams.teams.first?.id ?? ""

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
            }
            // Attaching the picker as a safe area inset lets SwiftUI sit it
            // above the home indicator and extend its material behind it,
            // which the original did by hand from the window's insets.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TeamPicker(teams: teams, selection: $selection)
            }
            .environment(\.containerSize, proxy.size)
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
/// grows a label and a coloured capsule.
private struct TeamPicker: View {
    let teams: [TeamRef]
    @Binding var selection: TeamRef.ID

    var body: some View {
        HStack {
            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
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

                if index < teams.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.default, value: selection)
        .padding(.horizontal, 25)
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
