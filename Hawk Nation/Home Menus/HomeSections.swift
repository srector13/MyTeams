//
//  HomeSections.swift
//  myTeams
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The heading above each section of a team page: an icon, a title, and
/// whatever controls or figures belong on the right.
struct SectionHeader<Accessory: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(Color(uiColor: .systemGray))

            Text(title)
                .font(.system(size: 20))
                .fontWeight(.bold)
                .foregroundStyle(Color(uiColor: .systemGray))

            Spacer()

            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(systemImage: String, title: String) {
        self.init(systemImage: systemImage, title: title) { EmptyView() }
    }
}

/// The roster carousel, with the filter and sort menus that drive it.
///
/// `card` draws one player; `detail` is the sheet a tap opens. `filterMenu`
/// is supplied per sport, since the positions worth filtering by differ.
struct RosterSection<Player: RosterPlayer, Card: View, Detail: View, FilterMenu: View>: View {
    let model: TeamModel<Player>
    @ViewBuilder let card: (Player) -> Card
    @ViewBuilder let detail: (Player) -> Detail
    @ViewBuilder let filterMenu: FilterMenu

    @State private var selectedPlayer: Player?

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "person.fill", title: "Roster") {
                Menu {
                    filterMenu
                } label: {
                    Image(systemName: "line.horizontal.3.decrease.circle")
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 5)

                Menu {
                    Button("Name") { model.sort(by: .name) }
                    Button("Number") { model.sort(by: .number) }
                    Button("Position") { model.sort(by: .position) }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 5)
            }
            .padding([.leading, .top, .trailing])

            ScrollView(.horizontal) {
                HStack {
                    if model.players.isEmpty {
                        // Five placeholder cards, so the carousel occupies its
                        // final height while the roster loads.
                        ForEach(0..<5, id: \.self) { _ in
                            LoadingPlayerView()
                                .padding(.leading, 10)
                                .padding(.bottom, 15)
                        }
                    } else {
                        ForEach(model.players) { player in
                            card(player)
                                .padding(.leading, 10)
                                .padding(.bottom, 15)
                                .onTapGesture { selectedPlayer = player }
                        }
                    }

                    // Trailing breathing room past the last card.
                    Color(uiColor: .systemBackground)
                        .frame(width: 10)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedPlayer, content: detail)
    }
}

/// The schedule carousel, opened scrolled to the next game still to be played.
///
/// `card` draws one game; `detail` is the sheet a tap opens.
struct ScheduleSection<Player: RosterPlayer, Card: View, Detail: View>: View {
    let model: TeamModel<Player>

    /// Whether cancelled and postponed fixtures are excluded from the losses
    /// half of the record. Only the baseball tab counts them in.
    var countsAbandonedGamesAsLosses = false

    @ViewBuilder let card: (Game) -> Card
    @ViewBuilder let detail: (Game) -> Detail

    @State private var selectedGame: Game?

    private var record: String {
        let losses = countsAbandonedGamesAsLosses
            ? model.games.count { !$0.gameWin && $0.pointer < model.nextGame }
            : model.record.losses
        return "\(model.record.wins)-\(losses)"
    }

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "calendar", title: "Schedule") {
                Text(record)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .systemGray))
            }
            .padding([.leading, .top, .trailing])

            ScrollView(.horizontal) {
                ScrollViewReader { scrollView in
                    HStack {
                        if model.games.isEmpty {
                            ForEach(0..<5, id: \.self) { _ in
                                LoadingGameView()
                                    .padding(.leading, 10)
                            }
                        } else {
                            ForEach(model.games) { game in
                                card(game)
                                    .padding(.leading, 10)
                                    .id(game.pointer)
                                    .onTapGesture { selectedGame = game }
                            }
                        }

                        Color(uiColor: .systemBackground)
                            .frame(width: 10)
                    }
                    .frame(height: 160)
                    .padding([.leading, .bottom], 10)
                    // Open on the last result rather than the next fixture, so
                    // the most recent score is the first thing in view.
                    .onChange(of: model.nextGame, initial: true) { _, nextGame in
                        guard !model.games.isEmpty else { return }
                        scrollView.scrollTo(max(nextGame - 1, 0), anchor: .leading)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedGame, content: detail)
    }
}

/// The news feed at the foot of a team page.
struct NewsSection<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let teamColor: Color

    @Environment(\.containerSize) private var containerSize

    @State private var selectedArticle: News?

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "book", title: "News")
                .padding([.leading, .top])

            VStack(alignment: .center, spacing: 10) {
                if model.articles.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        LoadingNewsView()
                    }
                } else {
                    ForEach(model.articles) { article in
                        Button {
                            selectedArticle = article
                        } label: {
                            NewsView(article: article)
                                .padding(.top)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading)

            // Clears the crest picker pinned to the bottom of the screen.
            Color(uiColor: .systemBackground)
                .frame(width: containerSize.width, height: 40)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedArticle) { article in
            NewsDetailView(article: article, color: teamColor)
        }
    }
}

/// The scrolling body shared by all four team pages.
struct TeamHomeLayout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                content
            }
            .frame(alignment: .leading)
            .background(Color(uiColor: .systemGray5))
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGray5))
    }
}
