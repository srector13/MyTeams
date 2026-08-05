//
//  TabBar.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The four teams the app follows, in the order their tabs appear.
enum Team: String, CaseIterable, Identifiable {
    case jayhawks
    case chiefs
    case royals
    case sporting

    var id: Self { self }

    /// The full name shown in the header and the sticky title bar.
    var displayName: String {
        switch self {
        case .jayhawks: "Kansas Jayhawks"
        case .chiefs: "Kansas City Chiefs"
        case .royals: "Kansas City Royals"
        case .sporting: "Sporting Kansas City"
        }
    }

    /// The short name shown beside the crest on the selected tab.
    var shortName: String {
        switch self {
        case .jayhawks: "Jayhawks"
        case .chiefs: "Chiefs"
        case .royals: "Royals"
        case .sporting: "Sporting"
        }
    }

    /// The asset name of the team crest.
    var logo: String {
        switch self {
        case .jayhawks: "jayhawk"
        case .chiefs: "chiefs"
        case .royals: "royals"
        case .sporting: "sporting"
        }
    }

    var color: Color {
        switch self {
        case .jayhawks: Color(red: 0 / 255, green: 81 / 255, blue: 186 / 255)
        case .chiefs: Color(red: 227 / 255, green: 24 / 255, blue: 55 / 255)
        case .royals: Color(red: 0 / 255, green: 70 / 255, blue: 135 / 255)
        case .sporting: Color(red: 0 / 255, green: 42 / 255, blue: 92 / 255)
        }
    }
}

/// The app's root screen: one scrolling team page at a time, with a crest
/// picker pinned to the bottom.
struct Home: View {
    @State private var selection: Team = .jayhawks

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // All four pages stay mounted and are shown by opacity, so
                // each keeps its scroll position and its loaded data when the
                // reader moves between teams.
                TeamPage(team: .jayhawks) { JayhawksHome() }
                    .opacity(selection == .jayhawks ? 1 : 0)
                TeamPage(team: .chiefs) { ChiefsHome() }
                    .opacity(selection == .chiefs ? 1 : 0)
                TeamPage(team: .royals) { RoyalsHome() }
                    .opacity(selection == .royals ? 1 : 0)
                TeamPage(team: .sporting) { SportingHome() }
                    .opacity(selection == .sporting ? 1 : 0)
            }
            // Attaching the picker as a safe area inset lets SwiftUI sit it
            // above the home indicator and extend its material behind it,
            // which the original did by hand from the window's insets.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TeamPicker(selection: $selection)
            }
            .environment(\.containerSize, proxy.size)
        }
    }
}

/// One team's scrolling page: the crest scrolls away under a title bar that
/// takes its place at the top.
private struct TeamPage<Content: View>: View {
    let team: Team
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
                    Image(team.logo)
                        .resizable()
                        .opacity(0.5)
                        .frame(
                            width: containerSize.width - 50,
                            height: containerSize.width - 50
                        )
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
                TopView(logoName: team.logo, teamName: team.displayName)
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
    @Binding var selection: Team

    var body: some View {
        HStack {
            ForEach(Array(Team.allCases.enumerated()), id: \.element) { index, team in
                Button {
                    selection = team
                } label: {
                    HStack(spacing: 6) {
                        Image(team.logo)
                            .resizable()
                            .frame(width: 25, height: 25)

                        if selection == team {
                            Text(team.shortName)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .background(selection == team ? team.color : .clear)
                    .clipShape(.capsule)
                }
                .accessibilityLabel(team.displayName)

                if index < Team.allCases.count - 1 {
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
    var logoName: String
    var teamName: String

    var body: some View {
        HStack(alignment: .center) {
            Image(logoName)
                .resizable()
                .frame(width: 40, height: 40)
                .padding(.leading)

            Text(teamName)
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
