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
                .font(Theme.Typography.sectionTitle)
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

/// Stands in for a section's cards when it has none to show: either the feed
/// answered with nothing, or it could not be reached and `retry` is offered.
struct SectionStatusView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(Color(uiColor: .systemGray))
                .multilineTextAlignment(.center)

            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

/// A carousel's cards as a vertical list, for accessibility text sizes,
/// where a horizontal strip of cards can't hold the text (§5.3). Shows
/// `collapsedCount` items from `start` until the reader asks for the rest,
/// so a long schedule or roster doesn't bury the sections beneath it.
struct StackedCarousel<Item: Identifiable, Row: View>: View {
    let items: [Item]
    /// The first item shown while collapsed, such as the last result.
    var start = 0
    var collapsedCount = 5
    @ViewBuilder let row: (Item) -> Row

    @State private var showsAll = false

    private var shown: ArraySlice<Item> {
        if showsAll || items.count <= collapsedCount {
            return items[...]
        }
        let first = min(max(start, 0), items.count - collapsedCount)
        return items[first..<(first + collapsedCount)]
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(shown) { item in
                row(item)
            }

            if items.count > collapsedCount {
                Button(showsAll ? "Show Fewer" : "Show All \(items.count)") {
                    showsAll.toggle()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, Theme.Spacing.l)
    }
}

extension View {
    /// Lets a table scroll sideways at accessibility text sizes, where it's
    /// wider than the screen, rather than squeezing its cells (§5.3).
    func scrollsSidewaysAtAccessibilitySizes() -> some View {
        modifier(ScrollsSidewaysAtAccessibilitySizes())
    }
}

private struct ScrollsSidewaysAtAccessibilitySizes: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal) {
                content
            }
        } else {
            content
        }
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

    @Environment(\.containerSize) private var containerSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPlayer: Player?

    /// At accessibility text sizes the carousel becomes a vertical list.
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "person.fill", title: "Roster") {
                Menu {
                    filterMenu
                } label: {
                    Image(systemName: "line.horizontal.3.decrease.circle")
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .font(.title3)
                }
                .padding(.horizontal, 5)

                Menu {
                    Button("Name") { model.sort(by: .name) }
                    Button("Number") { model.sort(by: .number) }
                    Button("Position") { model.sort(by: .position) }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .font(.title3)
                }
                .padding(.horizontal, 5)
            }
            .padding([.leading, .top, .trailing])

            if usesStackedLayout && !model.players.isEmpty {
                StackedCarousel(items: model.players) { player in
                    card(player)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onTapGesture { selectedPlayer = player }
                }
            } else {
                rosterCarousel
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedPlayer, content: detail)
    }

    private var rosterCarousel: some View {
        ScrollView(.horizontal) {
            // Lazy so off-screen cards are never realized — and so an
            // unrealized card can never start work of its own.
            LazyHStack {
                if model.players.isEmpty {
                    switch model.rosterState {
                    case .loading:
                        // Five placeholder cards, so the carousel occupies
                        // its final height while the roster loads.
                        ForEach(0..<5, id: \.self) { _ in
                            LoadingPlayerView()
                                .padding(.leading, 10)
                                .padding(.bottom, 15)
                        }
                    case .loaded:
                        // Either the feed listed nobody, or the filter
                        // matches nobody.
                        SectionStatusView(message: "No players to show")
                            .frame(width: max(containerSize.width - 20, 200))
                    case .failed:
                        SectionStatusView(message: "Couldn't load the roster") {
                            Task { await model.reloadRoster() }
                        }
                        .frame(width: max(containerSize.width - 20, 200))
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
}

/// The schedule carousel, opened scrolled to the next game still to be played.
///
/// `card` draws one game; `detail` is the sheet a tap opens.
struct ScheduleSection<Player: RosterPlayer, Card: View, Detail: View>: View {
    let model: TeamModel<Player>

    @ViewBuilder let card: (Game) -> Card
    @ViewBuilder let detail: (Game) -> Detail

    @State private var selectedGame: Game?

    @Environment(\.containerSize) private var containerSize
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The carousel's height: a game card's, scaled with the text in it.
    @ScaledMetric(relativeTo: .body) private var cardHeight = GameView.baseHeight

    /// At accessibility text sizes the carousel becomes a vertical list.
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var record: String {
        // The league's record rule decides how abandoned and unflagged
        // fixtures count (`RecordRule`); its sport decides the columns —
        // "10-6", soccer's "4-1-0", hockey's "40-30-12". See `Record.Format`.
        model.displayRecord().summary
    }

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "calendar", title: "Schedule") {
                Text(record)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .systemGray))
            }
            .padding([.leading, .top, .trailing])

            if usesStackedLayout && !model.games.isEmpty {
                // Opens on the last result, as the carousel does.
                StackedCarousel(items: model.games, start: model.nextGame - 1) { game in
                    card(game)
                        .onTapGesture { selectedGame = game }
                }
            } else {
                scheduleCarousel
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $selectedGame, content: detail)
    }

    private var scheduleCarousel: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                // Realised on demand: every schedule card mounted eagerly
                // was the reason a quiet Home screen still made hundreds
                // of requests a minute.
                LazyHStack {
                    if model.games.isEmpty {
                        switch model.scheduleState {
                        case .loading:
                            ForEach(0..<5, id: \.self) { _ in
                                LoadingGameView()
                                    .padding(.leading, 10)
                            }
                        case .loaded:
                            SectionStatusView(message: "Nothing scheduled")
                                .frame(width: max(containerSize.width - 30, 200))
                        case .failed:
                            SectionStatusView(message: "Couldn't load the schedule") {
                                Task { await model.reloadSchedule() }
                            }
                            .frame(width: max(containerSize.width - 30, 200))
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
                .frame(height: cardHeight)
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
}

/// The league standings: the table the followed team plays in, its row
/// picked out in the team's colour.
///
/// The columns follow the standings' kind: a soccer table's wins, draws,
/// losses, goal difference and points; hockey's wins, losses, overtime
/// losses and points; everyone else's wins and losses and games behind; a
/// poll's rank and record. A league of several tables (conferences, college
/// divisions) offers the others from the header's menu.
struct StandingsSection<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let team: TeamRef

    /// The table on show, when the reader has picked one other than the
    /// team's own.
    @State private var selectedGroupID: StandingsGroup.ID?

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "list.number", title: "Standings") {
                if let standings = model.standings, standings.groups.count > 1 {
                    Menu {
                        ForEach(standings.groups) { group in
                            Button(group.name) { selectedGroupID = group.id }
                        }
                    } label: {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(Color(uiColor: .systemGray))
                            .font(.title3)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .padding([.leading, .top, .trailing])

            if let standings = model.standings, let group = shownGroup(in: standings) {
                StandingsTable(
                    kind: standings.kind,
                    group: group,
                    league: team.league,
                    followedID: team.espnID,
                    teamColor: team.color
                )
                .padding([.horizontal, .bottom])
            } else {
                switch model.standingsState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                case .loaded:
                    SectionStatusView(message: "No standings yet")
                        .frame(maxWidth: .infinity)
                case .failed:
                    SectionStatusView(message: "Couldn't load the standings") {
                        Task { await model.reloadStandings() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    /// The reader's pick, else the team's own table, else the first — a
    /// poll the team is not ranked in, say.
    private func shownGroup(in standings: Standings) -> StandingsGroup? {
        if let selectedGroupID, let picked = standings.groups.first(where: { $0.id == selectedGroupID }) {
            return picked
        }
        return standings.group(containing: team.espnID) ?? standings.groups.first { !$0.entries.isEmpty }
    }
}

/// One standings table, drawn in the columns its kind keeps.
private struct StandingsTable: View {
    let kind: StandingsKind
    let group: StandingsGroup
    let league: LeagueID
    let followedID: String
    let teamColor: Color

    /// A numeric column: its heading, and each row's value.
    private struct Column {
        let title: String
        let value: (StandingsEntry) -> String
    }

    private var columns: [Column] {
        let wins = Column(title: "W") { "\($0.record.wins)" }
        let losses = Column(title: "L") { "\($0.record.losses)" }
        let points = Column(title: "Pts") { $0.record.points.map(String.init) ?? "" }

        switch kind {
        case .pointsTable:
            return [
                wins,
                Column(title: "D") { "\($0.record.ties)" },
                losses,
                Column(title: "GD") { $0.goalDifference },
                points,
            ]
        case .records where group.entries.first?.record.format == .winLossOvertimeLoss:
            return [wins, losses, Column(title: "OTL") { "\($0.record.overtimeLosses)" }, points]
        case .records:
            var columns = [wins, losses]
            // Ties only where someone has one (an NFL or college season).
            if group.entries.contains(where: { $0.record.ties > 0 }) {
                columns.append(Column(title: "T") { "\($0.record.ties)" })
            }
            columns.append(Column(title: "GB") { $0.gamesBehind })
            return columns
        case .rankings:
            return [Column(title: "Record") { $0.record.summary }]
        }
    }

    var body: some View {
        let columns = columns
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.subheadline.bold())
                .foregroundStyle(Color(uiColor: .systemGray))

            // Too wide for the screen at accessibility sizes: it scrolls
            // sideways rather than squeezing the team names out.
            table(columns)
                .scrollsSidewaysAtAccessibilitySizes()
        }
    }

    private func table(_ columns: [Column]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("#")
                Text("Team")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns.indices, id: \.self) { index in
                    Text(columns[index].title)
                        .gridColumnAlignment(.trailing)
                }
            }
            .font(Theme.Typography.statLabel)
            .foregroundStyle(Color(uiColor: .systemGray))

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                let followed = entry.teamID == followedID
                GridRow {
                    Text("\(entry.rank ?? position + 1)")
                        .foregroundStyle(Color(uiColor: .systemGray))
                    HStack(spacing: 6) {
                        TeamLogo(team: crestTeam(for: entry), size: 20)
                        Text(entry.shortName.isEmpty ? entry.name : entry.shortName)
                            .lineLimit(1)
                        if !entry.clincher.isEmpty {
                            Text(entry.clincher)
                                .font(.caption2)
                                .foregroundStyle(Color(uiColor: .systemGray))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index].value(entry))
                            .monospacedDigit()
                    }
                }
                .font(.footnote)
                .fontWeight(followed ? .bold : .regular)
                .padding(.vertical, 2)
                .background(followed ? teamColor.opacity(0.15) : Color.clear)
            }
        }
    }

    /// A stand-in `TeamRef` for drawing a row's crest through `TeamLogo`,
    /// which falls back to a monogram when the feed gives no crest.
    private func crestTeam(for entry: StandingsEntry) -> TeamRef {
        TeamRef(
            league: league, espnID: entry.teamID,
            displayName: entry.name, shortName: entry.shortName,
            abbreviation: entry.abbreviation, location: "",
            colorHex: "", alternateColorHex: "",
            logoURL: entry.logoURL, logoDarkURL: nil, logoAsset: nil
        )
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
                    switch model.newsState {
                    case .loading:
                        ForEach(0..<5, id: \.self) { _ in
                            LoadingNewsView()
                        }
                    case .loaded:
                        SectionStatusView(message: "No news right now")
                    case .failed:
                        SectionStatusView(message: "Couldn't load the news") {
                            Task { await model.reloadNews() }
                        }
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
            .padding(.horizontal)

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

/// The scrolling body of every team page.
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
