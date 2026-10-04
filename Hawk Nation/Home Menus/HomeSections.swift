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
                .foregroundStyle(.secondary)

            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(.secondary)

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

/// Marks the followed team's row (a standings row, a leaderboard row) by
/// shape, so it doesn't rest on bold type and a faint team-colour wash
/// alone (T-7, LL-2). Silent to VoiceOver: the row carries the
/// `isSelected` trait instead.
struct FollowedMarker: View {
    var body: some View {
        Image(systemName: "star.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .imageScale(.small)
            .accessibilityHidden(true)
    }
}

/// A menu in a section header, drawn as a standard glass circle button at
/// least 44 pt across (T-1). A header's menus go in one
/// `GlassEffectContainer(spacing: Theme.Spacing.s)` so they read as a
/// cluster and share a sampling pass (§5.2).
struct SectionHeaderMenu<Content: View>: View {
    /// What the menu does, for VoiceOver ("Sort roster").
    let title: String
    let systemImage: String
    let identifier: String
    @ViewBuilder var content: Content

    /// Grows with the header's text, never below the 44 pt minimum.
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .glassChrome(in: Circle(), interactive: true)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
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
                .foregroundStyle(.secondary)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPlayer: Player?

    /// Where a player's sheet zooms from: their card (X-13).
    @Namespace private var cardZoom

    /// At accessibility text sizes the carousel becomes a vertical list.
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "person.fill", title: "Roster") {
                GlassEffectContainer(spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        SectionHeaderMenu(
                            title: "Filter roster",
                            systemImage: "line.3.horizontal.decrease",
                            identifier: "roster.filter"
                        ) {
                            filterMenu
                        }

                        SectionHeaderMenu(
                            title: "Sort roster",
                            systemImage: "arrow.up.arrow.down",
                            identifier: "roster.sort"
                        ) {
                            Button("Name") { model.sort(by: .name) }
                            Button("Number") { model.sort(by: .number) }
                            Button("Position") { model.sort(by: .position) }
                        }
                    }
                }
            }
            .padding([.leading, .top, .trailing])

            if usesStackedLayout && !model.players.isEmpty {
                StackedCarousel(items: model.players) { player in
                    playerButton(player) {
                        card(player)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                }
            } else {
                rosterCarousel
            }
        }
        .contentCard()
        .sheet(item: $selectedPlayer) { player in
            detail(player)
                .zoomTransition(sourceID: player.id, in: cardZoom)
        }
    }

    private var rosterCarousel: some View {
        ScrollView(.horizontal) {
            // Lazy so off-screen cards are never realized — and so an
            // unrealized card can never start work of its own.
            LazyHStack(spacing: Theme.Spacing.m) {
                if model.players.isEmpty {
                    switch model.rosterState {
                    case .loading:
                        // Five placeholder cards, so the carousel occupies
                        // its final height while the roster loads.
                        ForEach(0..<5, id: \.self) { _ in
                            LoadingPlayerView()
                        }
                    case .loaded:
                        // Either the feed listed nobody, or the filter
                        // matches nobody.
                        SectionStatusView(message: "No players to show")
                            .containerRelativeFrame(.horizontal)
                    case .failed:
                        SectionStatusView(message: "Couldn't load the roster") {
                            Task { await model.reloadRoster() }
                        }
                        .containerRelativeFrame(.horizontal)
                    }
                } else {
                    ForEach(model.players) { player in
                        playerButton(player) {
                            card(player)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, Theme.Spacing.l)
        }
        // The margins inset the first and last cards in line with the
        // header, and the cards still scroll out to the card's edges (T-4).
        .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
        // A flick comes to rest on a card's leading edge, not mid-card (T-8).
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    /// A player's card as a button that opens their sheet (T-3), so it has a
    /// pressed state, focus, and VoiceOver's button trait. No glass: it's
    /// content in a scrolling carousel (§5.2).
    private func playerButton<CardLabel: View>(_ player: Player, @ViewBuilder label: () -> CardLabel) -> some View {
        Button {
            selectedPlayer = player
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .zoomSource(id: player.id, in: cardZoom)
        .accessibilityLabel(accessibilityLabel(for: player))
        .accessibilityIdentifier("roster.player.\(player.id)")
    }

    /// "Jane Doe, number 23, Guard", skipping whatever the feed left blank.
    private func accessibilityLabel(for player: Player) -> String {
        [
            player.name,
            player.number.isEmpty ? "" : "number \(player.number)",
            player.position,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
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

    /// Where a game's sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

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
                    .foregroundStyle(.secondary)
            }
            .padding([.leading, .top, .trailing])

            if usesStackedLayout && !model.games.isEmpty {
                // Opens on the last result, as the carousel does.
                StackedCarousel(items: model.games, start: model.nextGame - 1) { game in
                    gameButton(game)
                }
            } else {
                scheduleCarousel
            }
        }
        .contentCard()
        .sheet(item: $selectedGame) { game in
            detail(game)
                .zoomTransition(sourceID: game.id, in: cardZoom)
        }
    }

    private var scheduleCarousel: some View {
        ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                // Realised on demand: every schedule card mounted eagerly
                // was the reason a quiet Home screen still made hundreds
                // of requests a minute.
                LazyHStack(spacing: Theme.Spacing.m) {
                    if model.games.isEmpty {
                        switch model.scheduleState {
                        case .loading:
                            ForEach(0..<5, id: \.self) { _ in
                                LoadingGameView()
                            }
                        case .loaded:
                            SectionStatusView(message: "Nothing scheduled")
                                .containerRelativeFrame(.horizontal)
                        case .failed:
                            SectionStatusView(message: "Couldn't load the schedule") {
                                Task { await model.reloadSchedule() }
                            }
                            .containerRelativeFrame(.horizontal)
                        }
                    } else {
                        ForEach(model.games) { game in
                            gameButton(game)
                                .id(game.pointer)
                        }
                    }
                }
                .scrollTargetLayout()
                .frame(height: cardHeight)
                .padding(.bottom, Theme.Spacing.l)
                // Open on the last result rather than the next fixture, so
                // the most recent score is the first thing in view.
                .onChange(of: model.nextGame, initial: true) { _, nextGame in
                    guard !model.games.isEmpty else { return }
                    scrollView.scrollTo(max(nextGame - 1, 0), anchor: .leading)
                }
            }
        }
        .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
        // A flick comes to rest on a card's leading edge, not mid-card (T-8).
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    /// A game's card as a button that opens its sheet (T-3). No glass: it's
    /// content in a scrolling carousel (§5.2).
    private func gameButton(_ game: Game) -> some View {
        Button {
            selectedGame = game
        } label: {
            card(game)
        }
        .buttonStyle(.plain)
        .zoomSource(id: game.id, in: cardZoom)
        .accessibilityLabel(
            game.accessibilitySummary(
                drawLabel: model.team.league.descriptor.drawLabel,
                liveScore: model.liveScores[game.gameID]
            )
        )
        .accessibilityIdentifier("schedule.game.\(game.id)")
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
                    GlassEffectContainer(spacing: Theme.Spacing.s) {
                        SectionHeaderMenu(
                            title: "Select standings group",
                            systemImage: "rectangle.stack",
                            identifier: "standings.group"
                        ) {
                            ForEach(standings.groups) { group in
                                Button(group.name) { selectedGroupID = group.id }
                            }
                        }
                    }
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
        .contentCard()
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

    @Environment(\.colorSchemeContrast) private var contrast

    /// A row's crest, which scales with the footnote team name beside it
    /// (B-3).
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 20

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
                .foregroundStyle(.secondary)

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
            .foregroundStyle(.secondary)

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                let followed = entry.teamID == followedID
                GridRow {
                    Text("\(entry.rank ?? position + 1)")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TeamLogo(team: crestTeam(for: entry), size: crestSize)
                        Text(entry.shortName.isEmpty ? entry.name : entry.shortName)
                            .lineLimit(1)
                        // After the name, so the names stay in one column.
                        if followed {
                            FollowedMarker()
                        }
                        if !entry.clincher.isEmpty {
                            Text(entry.clincher)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(followed ? .isSelected : [])
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index].value(entry))
                            .monospacedDigit()
                    }
                }
                .font(.footnote)
                .fontWeight(followed ? .bold : .regular)
                .padding(.vertical, 2)
                .background(followed ? teamColor.opacity(Theme.selectionWashOpacity(contrast: contrast)) : Color.clear)
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

    @State private var selectedArticle: News?

    /// Where an article's sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

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
                        .zoomSource(id: article.id, in: cardZoom)
                        .accessibilityIdentifier("news.article")
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
        // Nothing to clear the crest picker with: the picker is a safe-area
        // bar, so the page's scroll view insets its content and scrolls it
        // under the picker's edge effect (T-5).
        .contentCard()
        .sheet(item: $selectedArticle) { article in
            NewsDetailView(article: article, color: teamColor)
                .zoomTransition(sourceID: article.id, in: cardZoom)
        }
    }
}

/// What a team page's header says under the team's name: the record, the
/// team's place in its table, and the next game. Each is `nil` until its
/// feed has something to say.
struct TeamHeaderSummary: Equatable, Sendable {
    /// The season record so far, `"10-6"`, in its sport's shape.
    var record: String?
    /// The team's place in its table, `"3rd in AFC West"`, or its poll
    /// rank, `"No. 5 in AP Top 25"`.
    var standing: String?
    /// The next game still to be played, `"vs Raiders · Sun, Oct 12"`.
    var nextGame: String?

    init(record: String? = nil, standing: String? = nil, nextGame: String? = nil) {
        self.record = record
        self.standing = standing
        self.nextGame = nextGame
    }

    /// The summary from a team page's model: `record` as the schedule
    /// section counts it, the team's row in `standings`, and
    /// `games[nextGame]` if it's still to be played.
    init(team: TeamRef, games: [Game], nextGame: Int, record: Record, standings: Standings?) {
        self.record = games.isEmpty ? nil : record.summary
        self.standing = standings.flatMap { Self.standing(of: team.espnID, in: $0) }
        self.nextGame = Self.upcoming(games: games, nextGame: nextGame)
    }

    /// The record and standing on one line, `"10-6 · 3rd in AFC West"`.
    var recordLine: String? {
        let parts = [record, standing].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The team's place in the table that holds it, or `nil` where the
    /// feed ranks nobody yet.
    static func standing(of teamID: String, in standings: Standings) -> String? {
        guard let group = standings.group(containing: teamID),
              let rank = group.entries.first(where: { $0.teamID == teamID })?.rank,
              rank > 0
        else { return nil }
        switch standings.kind {
        case .rankings:
            return "No. \(rank) in \(group.name)"
        case .pointsTable, .records:
            return "\(ScoreSnapshot.ordinal(rank)) in \(group.name)"
        }
    }

    /// `"vs Raiders · Sun, Oct 12"` (`"at"` away from home) for the game at
    /// `nextGame`, or `nil` once the season's last game is played.
    static func upcoming(games: [Game], nextGame: Int) -> String? {
        guard games.indices.contains(nextGame) else { return nil }
        let game = games[nextGame]
        guard !game.completed, !game.cancelled, !game.postponed, !game.opponent.isEmpty else { return nil }
        let date = game.dateAsDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(game.gameHome ? "vs" : "at") \(game.opponent) · \(date)"
    }
}

/// The top of a team page, over the team colour: the team's crest — the
/// page's only one — its name, and its record, standing and next game.
/// Text and crest are drawn for the team colour (`teamInk(on:)`,
/// `TeamColors.logoVariant`). At accessibility text sizes the crest sits
/// above the name rather than beside it.
struct TeamPageHeader: View {
    let team: TeamRef
    let summary: TeamHeaderSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .largeTitle) private var crestSize: CGFloat = 64

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.l))

        layout {
            TeamLogo(
                team: team,
                // Capped: past this the crest crowds out the name.
                size: min(crestSize, 112),
                forceVariant: TeamColors.logoVariant(for: team, onBackground: TeamColors.fillHex(for: team))
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(team.displayName)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                if let recordLine = summary.recordLine {
                    Text(recordLine)
                        .font(.headline)
                        .monospacedDigit()
                }

                if let nextGame = summary.nextGame {
                    Label(nextGame, systemImage: "calendar")
                        .font(Theme.Typography.footnote.weight(.semibold))
                }
            }
            .teamInk(on: team)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("teamPage.header")
    }
}

/// The body of every team page: its header over the team colour, then the
/// sections as inset rounded cards on the grouped background, which rounds
/// its top corners where it meets the team-colour hero (T-4). No glass:
/// this is scrolling content (B1).
///
/// Lays the page out only. The page scrolls in `TeamPage`'s scroll view,
/// which draws the team colour behind the header and carries the bottom
/// edge effect under the tab bar. As the page scrolls, the cards slide up
/// over the header, which recedes beneath them (`recedingHeader(below:)`),
/// and the page tells `TeamPage` once they reach the navigation bar
/// (`TeamPageChrome`).
struct TeamHomeLayout<Header: View, Content: View>: View {
    let content: Content
    let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    @Environment(\.containerSize) private var containerSize
    @Environment(TeamPageChrome.self) private var chrome: TeamPageChrome?

    var body: some View {
        let barBottom = chrome?.barBottom ?? 0

        VStack(spacing: 0) {
            header
                .recedingHeader(below: barBottom)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    chrome?.headerHeight = height
                }

            VStack(spacing: Theme.Spacing.m) {
                content
            }
            .padding(Theme.Spacing.m)
            // At least a screen tall, so a page still loading covers the hero
            // rather than leaving it showing beneath a short page.
            .frame(maxWidth: .infinity, minHeight: containerSize.height, alignment: .top)
            .background(Theme.Surface.content, in: Theme.Radius.pageShape)
            // Drawn after the header, so over it as it recedes.
            .zIndex(1)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.frame(in: .global).minY < barBottom
            } action: { covered in
                chrome?.cardsUnderBar = covered
            }
        }
    }
}
