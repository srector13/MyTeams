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

    /// The carousel's width, measured, from which each card's is worked
    /// out (`RosterPeek`); 0 until it's laid out.
    @State private var carouselWidth: CGFloat = 0

    /// The narrowest a card gets: a little over its headshot, which scales
    /// with the caption (`PlayerCard`).
    @ScaledMetric(relativeTo: .caption) private var minimumCardWidth: CGFloat = 64

    /// Where a player's sheet zooms from: their card (X-13).
    @Namespace private var cardZoom

    /// At accessibility text sizes the carousel becomes a vertical list.
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Each card's width, so the row shows whole cards and half of the
    /// next (T3); `nil` until the carousel has been measured.
    private var cardWidth: CGFloat? {
        guard carouselWidth > 0 else { return nil }
        return RosterPeek.cardWidth(
            visibleWidth: carouselWidth - Theme.Spacing.l,
            spacing: Theme.Spacing.m,
            minimum: minimumCardWidth
        )
    }

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
                                .frame(width: cardWidth)
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
                                .frame(width: cardWidth)
                                .environment(\.rosterCardWidth, cardWidth)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, Theme.Spacing.l)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            carouselWidth = width
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

extension EnvironmentValues {
    /// The width a roster carousel gives each card (`RosterPeek`), which a
    /// card's caption wraps to (`PlayerCard`); `nil` outside the carousel.
    @Entry var rosterCardWidth: CGFloat? = nil
}

/// How wide a roster carousel's cards are, so the row shows a run of whole
/// cards and half of the next, and reads as one that scrolls (T3, F7):
/// four and a half on an iPhone, more on an iPad.
enum RosterPeek {
    /// The card width that fits the most whole cards, each at least
    /// `minimum` wide, and half a card into `visibleWidth`, with `spacing`
    /// after each card: `n` cards, `n` gaps and half a card fill it.
    static func cardWidth(visibleWidth: CGFloat, spacing: CGFloat, minimum: CGFloat) -> CGFloat {
        guard visibleWidth > 0, minimum > 0 else { return max(minimum, 0) }
        let fits = ((visibleWidth - minimum / 2) / (minimum + spacing)).rounded(.down)
        let whole = max(fits, 1)
        return max(minimum, (visibleWidth - whole * spacing) / (whole + 0.5))
    }
}

/// The schedule carousel, opened scrolled to the next game still to be played.
///
/// `card` draws one game; `detail` is the sheet a tap opens. The header's
/// "See All" opens the whole schedule as a list (`FullScheduleSheet`, F6),
/// where the remaining games can go on the calendar. A season played out
/// says so with the record, rather than a carousel of old results (T8).
struct ScheduleSection<Player: RosterPlayer, Card: View, Detail: View>: View {
    let model: TeamModel<Player>

    @ViewBuilder let card: (Game) -> Card
    @ViewBuilder let detail: (Game) -> Detail

    @State private var selectedGame: Game?

    /// The card at the carousel's leading edge: the last result when the
    /// schedule lands, then wherever the reader scrolls.
    @State private var openingGame: Game.ID?

    /// The game whose new-event sheet is up, from its card's menu (R-7).
    @State private var calendarDraft: EventDraft?

    /// The whole schedule's sheet, from the header's "See All" (F6).
    @State private var showsFullSchedule = false

    /// Where a game's sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Opens the opponent's page (t_8d15e070); absent in previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    /// At accessibility text sizes the carousel becomes a vertical list.
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The season's record for a season played out: the schedule's, as
    /// the header counts it, or the standings row's for a schedule that is
    /// already empty (`TeamHeaderSummary.standingsRecord`).
    private var completedRecord: String? {
        if !model.games.isEmpty { return model.displayRecord().summary }
        return model.standings.flatMap { TeamHeaderSummary.standingsRecord(of: model.team.espnID, in: $0) }
    }

    /// Whether the season is over (T8): see `TeamHeaderSummary.seasonComplete`.
    private var seasonComplete: Bool {
        TeamHeaderSummary.seasonComplete(
            games: model.games,
            nextGame: model.nextGame,
            standingsRecord: completedRecord,
            scheduleLoaded: model.scheduleState == .loaded,
            now: Date()
        )
    }

    var body: some View {
        let complete = seasonComplete
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "calendar", title: "Schedule") {
                // The one way to more (F6): the whole schedule as a list.
                if !model.games.isEmpty {
                    SeeAllLink(identifier: "schedule.seeAll") {
                        showsFullSchedule = true
                    }
                }
            }
            .padding([.leading, .top, .trailing])

            if complete {
                seasonCompletePanel
            } else if model.games.isEmpty && model.scheduleState != .loading {
                // A line, not a carousel's height of empty card: a team
                // between seasons has nothing scheduled for months.
                scheduleStatus
            } else if usesStackedLayout && !model.games.isEmpty {
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
        .sheet(item: $calendarDraft) { draft in
            EventEditSheet(draft: draft) { calendarDraft = nil }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsFullSchedule) {
            FullScheduleSheet(
                team: model.team,
                games: model.games,
                openingIndex: max(model.nextGame - (complete ? 0 : 1), 0),
                card: card,
                detail: detail
            )
        }
    }

    /// A season played out (T8): its record, where next season's games
    /// will appear, and the way to the season just played, in place of a
    /// carousel of old results or "Nothing scheduled".
    private var seasonCompletePanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(completedRecord.map { "Season complete · \($0)" } ?? "Season complete")
                .font(Theme.Typography.cardTitle)
                .monospacedDigit()
            Text("Next season's schedule appears here when \(model.team.league.badge) releases it.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.metadata)
                .fixedSize(horizontal: false, vertical: true)
            if !model.games.isEmpty {
                SeeAllLink(title: "Full Schedule", identifier: "schedule.full") {
                    showsFullSchedule = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .padding([.horizontal, .bottom])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.seasonComplete")
    }

    /// What a schedule with no games says, compact: one line once the feed
    /// has answered with none, or the error and a retry.
    @ViewBuilder
    private var scheduleStatus: some View {
        if model.scheduleState == .failed {
            SectionStatusView(message: "Couldn't load the schedule") {
                Task { await model.reloadSchedule() }
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Nothing scheduled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom])
                .accessibilityIdentifier("schedule.empty")
        }
    }

    private var scheduleCarousel: some View {
        ScrollView(.horizontal) {
            // Realised on demand: every schedule card mounted eagerly
            // was the reason a quiet Home screen still made hundreds
            // of requests a minute. Each card sizes to its content (F7).
            LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                if model.games.isEmpty {
                    // Only while loading: a schedule that answered with
                    // no games, or failed, is `scheduleStatus`'s line.
                    ForEach(0..<5, id: \.self) { _ in
                        LoadingGameView()
                    }
                } else {
                    ForEach(model.games) { game in
                        gameButton(game)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, Theme.Spacing.l)
        }
        // Open on the last result rather than the next fixture, so the
        // most recent score is the first thing in view. Through the scroll
        // position, which the lazy stack lays out around in its first pass
        // with the cards, rather than `ScrollViewReader.scrollTo` after it:
        // that jump left the card peeking in ahead of the last result a
        // grey shell until it was scrolled off and back (t_c3f79052).
        .scrollPosition(id: $openingGame, anchor: .leading)
        .onChange(of: model.nextGame, initial: true) { _, nextGame in
            let opening = max(nextGame - 1, 0)
            guard model.games.indices.contains(opening) else { return }
            openingGame = model.games[opening].id
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
                liveScore: model.liveScores[game.gameID],
                league: model.team.league.descriptor
            )
        )
        .accessibilityIdentifier("schedule.game.\(game.id)")
        // A tap opens the game; the opponent's page is a long press away,
        // and a VoiceOver action through the menu (t_8d15e070).
        .contextMenu {
            if let navigator, !game.opponentID.isEmpty {
                Button {
                    navigator.open(teamID: TeamRef.id(league: model.team.league, espnID: game.opponentID))
                } label: {
                    Label(game.opponent.isEmpty ? "Opponent's Page" : game.opponent, systemImage: "person.3")
                }
                .accessibilityIdentifier("schedule.opponent.\(game.opponentID)")
            }
            // A game still to come can go on the calendar (R-7).
            if CalendarEventBuilder.isUpcoming(game) {
                Button {
                    calendarDraft = CalendarEventBuilder.draft(for: game, team: model.team)
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("schedule.calendar.\(game.id)")
            }
        }
    }
}

/// The whole schedule, as a sheet from the Schedule section's "See All"
/// (F6) or a finished season's "Full Schedule" (T8): every game's card in
/// a list, opened at the next game (or the last result), each opening its
/// game's sheet. The way to put the remaining games on the calendar (R-7),
/// which the section's header used to hold as an icon menu.
private struct FullScheduleSheet<Card: View, Detail: View>: View {
    let team: TeamRef
    let games: [Game]
    /// The game the list opens at.
    let openingIndex: Int
    let card: (Game) -> Card
    let detail: (Game) -> Detail

    @State private var selectedGame: Game?

    /// The game at the top of the list.
    @State private var position: Game.ID?

    /// What the last season sync did, or why it couldn't (R-7).
    @State private var calendarMessage: String?

    init(
        team: TeamRef,
        games: [Game],
        openingIndex: Int,
        @ViewBuilder card: @escaping (Game) -> Card,
        @ViewBuilder detail: @escaping (Game) -> Detail
    ) {
        self.team = team
        self.games = games
        self.openingIndex = openingIndex
        self.card = card
        self.detail = detail
        let opening = min(max(openingIndex, 0), max(games.count - 1, 0))
        self._position = State(initialValue: games.indices.contains(opening) ? games[opening].id : nil)
    }

    /// The games a season sync would write: those still to come with a
    /// real start time (`CalendarEventBuilder.seasonDrafts`).
    private var seasonDrafts: [EventDraft] {
        CalendarEventBuilder.seasonDrafts(for: games, team: team)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: Theme.Spacing.m) {
                    ForEach(games) { game in
                        Button {
                            selectedGame = game
                        } label: {
                            card(game)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("schedule.full.game.\(game.id)")
                    }
                }
                .scrollTargetLayout()
                .padding(Theme.Spacing.m)
                // A readable column on an iPad's page-sized sheet.
                .readableContentWidth(600)
            }
            .scrollPosition(id: $position, anchor: .top)
            .background(Theme.Surface.content)
            .navigationTitle("Schedule")
            .navigationSubtitle(team.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !seasonDrafts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            syncSeason()
                        } label: {
                            Label("Add Remaining Games", systemImage: "calendar.badge.plus")
                        }
                        .accessibilityIdentifier("schedule.calendar.season")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // One close button for every sheet (T6).
                    SheetCloseButton()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityIdentifier("schedule.full.close")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // Full height: a season is a long list (X-9).
        .presentationDetents([.large])
        .presentationSizing(.page)
        .sheet(item: $selectedGame) { game in
            detail(game)
        }
        .alert(
            "Calendar",
            isPresented: Binding(
                get: { calendarMessage != nil },
                set: { if !$0 { calendarMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarMessage ?? "")
        }
    }

    /// Adds the remaining games to the team's own calendar, or brings the
    /// ones added before up to date: a rescheduled game is moved, never
    /// added twice (R-7).
    private func syncSeason() {
        let drafts = seasonDrafts
        let title = CalendarEventBuilder.calendarTitle(for: team)
        Task {
            do {
                calendarMessage = try await CalendarWriter.syncSeason(drafts, calendarTitle: title).message
            } catch {
                calendarMessage = error.localizedDescription
            }
        }
    }
}

/// The league standings on a team page: the table the followed team plays
/// in, its row picked out in the team's accent (F3).
///
/// A division or other short table shows whole; a longer one shows two
/// places either side of the team (`StandingsGroup.snapshotRows`, T5), and
/// "See All" (F6) or "Full … Standings" opens every table in a sheet
/// (`FullStandingsSheet`), where a league of several tables offers the
/// others.
///
/// The columns follow the standings' kind: a soccer table's wins, draws,
/// losses, goal difference and points; hockey's wins, losses, overtime
/// losses and points; everyone else's wins and losses and games behind; a
/// poll's rank and record. A soccer table marks the zones its feed notes
/// (qualification, relegation) in their colours, and clincher marks are
/// spelled out, in legends beneath.
///
/// The table's caption names the season the tables are for (`"2026-27"`),
/// which is not always the one under way. A college league's rows prefix
/// ranked teams with their poll rank, `"#7 Kansas"` (`PollRanks`, R-5).
struct StandingsSection<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let team: TeamRef

    /// The league's poll, for a college league; empty otherwise.
    @State private var pollRanks = PollRanks.empty

    @State private var showsFullStandings = false

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "list.number", title: "Standings") {
                if let standings = model.standings, !standings.isEmpty {
                    SeeAllLink(identifier: "standings.seeAll") {
                        showsFullStandings = true
                    }
                }
            }
            .padding([.leading, .top, .trailing])

            if let standings = model.standings, let group = standings.teamPageGroup(for: team.espnID) {
                let rows = group.snapshotRows(around: team.espnID)
                let isSnapshot = rows.count < group.entries.count
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    StandingsTable(
                        kind: standings.kind,
                        group: group,
                        league: team.league,
                        followedID: team.espnID,
                        accent: TeamColors.accent(for: team),
                        pollRanks: pollRanks,
                        rows: rows,
                        season: standings.seasonLabel,
                        footnote: isSnapshot ? snapshotNote(group: group) : nil
                    )

                    if isSnapshot {
                        SeeAllLink(
                            title: "Full \(group.shortTitle(kind: standings.kind, leagueName: team.league.descriptor.displayName)) Standings",
                            identifier: "standings.full"
                        ) {
                            showsFullStandings = true
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            } else {
                switch model.standingsState {
                case .loading:
                    // Skeleton rows, as the other sections load (X-6).
                    StandingsSkeleton()
                        .padding([.horizontal, .bottom])
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
        .task(id: team.league) {
            pollRanks = await PollRankStore.shared.ranks(for: team.league)
        }
        .sheet(isPresented: $showsFullStandings) {
            if let standings = model.standings {
                FullStandingsSheet(standings: standings, team: team, pollRanks: pollRanks)
            }
        }
    }

    /// What a snapshot leaves out: "Showing 2 places either side of the
    /// Royals", or the top rows of a table without the team.
    private func snapshotNote(group: StandingsGroup) -> String {
        let shown = StandingsGroup.snapshotReach * 2 + 1
        guard group.entries.contains(where: { $0.teamID == team.espnID }) else {
            return "Showing the top \(shown)"
        }
        // "the Royals", but a club goes by its name alone: "Freiburg".
        let name = team.league.descriptor.kind == .soccer ? team.shortName : "the \(team.shortName)"
        return "Showing \(StandingsGroup.snapshotReach) places either side of \(name)"
    }
}

/// Every table in a league's standings, as a sheet from a team page's
/// Standings section (T5): the team's own table first on screen, the
/// others a pick away from the menu, each whole.
private struct FullStandingsSheet: View {
    let standings: Standings
    let team: TeamRef
    let pollRanks: PollRanks

    /// The table on show, when the reader has picked one other than the
    /// team's own.
    @State private var selectedGroupID: StandingsGroup.ID?

    /// The reader's pick, else the team's own table, else the first.
    private var shownGroup: StandingsGroup? {
        if let selectedGroupID, let picked = standings.groups.first(where: { $0.id == selectedGroupID }) {
            return picked
        }
        return standings.teamPageGroup(for: team.espnID)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                if let group = shownGroup {
                    StandingsTable(
                        kind: standings.kind,
                        group: group,
                        league: team.league,
                        followedID: team.espnID,
                        accent: TeamColors.accent(for: team),
                        pollRanks: pollRanks,
                        season: standings.seasonLabel
                    )
                    .padding(Theme.Spacing.l)
                    .contentCard()
                    .padding(Theme.Spacing.m)
                    .readableContentWidth(600)
                }
            }
            .background(Theme.Surface.content)
            .navigationTitle("Standings")
            .navigationSubtitle(standings.seasonLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Picks the table on show: filters in place, so an icon (F6).
                if standings.groups.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(standings.groups) { group in
                                Button(group.name) { selectedGroupID = group.id }
                            }
                        } label: {
                            Label("Select standings group", systemImage: "rectangle.stack")
                        }
                        .accessibilityIdentifier("standings.group")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // One close button for every sheet (T6).
                    SheetCloseButton()
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityIdentifier("standings.full.close")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
    }
}

/// One standings table, drawn in the columns its kind keeps: all its rows,
/// or the run of them `rows` names (a team page's snapshot, T5), each
/// ranked by its place in the whole table.
private struct StandingsTable: View {
    let kind: StandingsKind
    let group: StandingsGroup
    let league: LeagueID
    let followedID: String
    /// The followed team's accent (`TeamColors.accent(for:)`, F3), which
    /// tints and outlines its row so it stays visible in dark mode too.
    let accent: Color
    /// The league's poll, whose ranks prefix the team names (R-5). A poll
    /// table already ranks its rows in the # column, so it prefixes none.
    var pollRanks: PollRanks = .empty
    /// The rows shown, by index into `group.entries`; all of them when
    /// `nil`.
    var rows: Range<Int>? = nil
    /// The season the table is for, after its name in the caption.
    var season: String = ""
    /// A line under the legends, such as what a snapshot leaves out.
    var footnote: String? = nil

    /// The rows on show, each with its index in the whole table.
    private var shownEntries: [(offset: Int, element: StandingsEntry)] {
        let all = Array(group.entries.enumerated())
        guard let rows else { return all.map { (offset: $0.offset, element: $0.element) } }
        let clamped = rows.clamped(to: all.indices)
        return all[clamped].map { (offset: $0.offset, element: $0.element) }
    }

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Opens a row's team page (t_8d15e070); absent in previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    /// A row's crest, which scales with the footnote team name beside it
    /// (B-3).
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 20

    /// The followed team's row, in the table's coordinate space
    /// (`"standings.table"`), for the one band of team colour drawn
    /// behind it (`followedBand`).
    @State private var followedRowFrame: CGRect?

    /// A numeric column: its heading, how VoiceOver reads a value in it
    /// ("8 wins", "games behind 2.5"), and each row's value.
    private struct Column {
        let title: String
        let spoken: (String) -> String
        let value: (StandingsEntry) -> String
    }

    private var columns: [Column] {
        let wins = Column(title: "W", spoken: { "\($0) wins" }) { "\($0.record.wins)" }
        let losses = Column(title: "L", spoken: { "\($0) losses" }) { "\($0.record.losses)" }
        let points = Column(title: "Pts", spoken: { "\($0) points" }) { $0.record.points.map(String.init) ?? "" }

        switch kind {
        case .pointsTable:
            return [
                wins,
                Column(title: "D", spoken: { "\($0) draws" }) { "\($0.record.ties)" },
                losses,
                Column(title: "GD", spoken: { "goal difference \($0)" }) { $0.goalDifference },
                points,
            ]
        case .records where group.entries.first?.record.format == .winLossOvertimeLoss:
            let otl = Column(title: "OTL", spoken: { "\($0) overtime losses" }) { "\($0.record.overtimeLosses)" }
            return [wins, losses, otl, points] + extraColumns
        case .records:
            var columns = [wins, losses]
            // Ties only where someone has one (an NFL or college season).
            if group.entries.contains(where: { $0.record.ties > 0 }) {
                columns.append(Column(title: "T", spoken: { "\($0) ties" }) { "\($0.record.ties)" })
            }
            columns.append(Column(title: "GB", spoken: { "games behind \($0)" }) { $0.gamesBehind })
            return columns + extraColumns
        case .rankings:
            return [Column(title: "Record", spoken: { "record \($0)" }) { $0.record.summary }]
        }
    }

    /// The conference-record and streak columns, after the table's own,
    /// where the feed fills them in (R-5). See
    /// `StandingsGroup.extraColumns(kind:isAccessibilitySize:)`.
    private var extraColumns: [Column] {
        group.extraColumns(kind: kind, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize).map { extra -> Column in
            switch extra {
            case .conferenceRecord:
                return Column(title: "Conf", spoken: { "conference record \($0)" }) { $0.conferenceRecord }
            case .streak:
                return Column(title: "Strk", spoken: { "streak \($0)" }) { $0.streak }
            }
        }
    }

    /// `"AFC West · 2026"`: the table's name and the season it's for.
    private var caption: String {
        let title = group.title(kind: kind, leagueName: league.descriptor.displayName)
        let season = season.trimmingCharacters(in: .whitespaces)
        // A soccer table's season already leads its feed name.
        guard !season.isEmpty, !title.contains(season) else { return title }
        return "\(title) · \(season)"
    }

    var body: some View {
        let columns = columns
        let shown = shownEntries
        let zones = group.zones
        let clinchers = StandingsClincher.legend(for: shown.map(\.element))
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(caption)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.Palette.metadata)
                .accessibilityIdentifier("standings.season")

            // Too wide for the screen at accessibility sizes: it scrolls
            // sideways rather than squeezing the team names out.
            table(columns, rows: shown, zoned: !zones.isEmpty)
                .scrollsSidewaysAtAccessibilitySizes()

            if !zones.isEmpty {
                legend(zones)
            }

            // What the clincher marks mean, the marks on show only (T5).
            let notes = clinchers + [footnote].compactMap { $0 }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · "))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.metadata)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("standings.clinchers")
            }
        }
        // A table no wider than reads across (T10): on an iPad's page the
        // names and their figures drifted 600 pt apart.
        .frame(maxWidth: 600, alignment: .leading)
    }

    /// What each zone's bar means, one line per zone, top of the table
    /// first (C-2).
    private func legend(_ zones: [StandingsZone]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(zones, id: \.note) { zone in
                Text(zone.note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.metadata)
                    .padding(.leading, Theme.Spacing.s)
                    .overlay(alignment: .leading) {
                        ZoneBar(colorHex: zone.colorHex)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("standings.legend")
    }

    /// The table's `rows`. A `zoned` table insets the rank column, marked
    /// rows or not, to leave room for the zone bars and keep it in line.
    private func table(_ columns: [Column], rows: [(offset: Int, element: StandingsEntry)], zoned: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.xs) {
            GridRow {
                Text("#")
                    .padding(.leading, zoned ? Theme.Spacing.s : 0)
                Text("Team")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns.indices, id: \.self) { index in
                    Text(columns[index].title)
                        .gridColumnAlignment(.trailing)
                }
            }
            .font(Theme.Typography.statLabel)
            .foregroundStyle(Theme.Palette.metadata)
            // Each row says its own columns (`accessibilityLabel(for:)`).
            .accessibilityHidden(true)

            ForEach(rows, id: \.element.id) { position, entry in
                let followed = entry.teamID == followedID
                let rank = entry.rank ?? position + 1
                GridRow {
                    // The zone bar runs the row's full height: the cell is
                    // stretched to the row's tallest (the crest) first.
                    Text("\(rank)")
                        .foregroundStyle(Theme.Palette.metadata)
                        .padding(.leading, zoned ? Theme.Spacing.s : 0)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) {
                            if let zone = entry.zone {
                                ZoneBar(colorHex: zone.colorHex)
                            }
                        }
                        // As tall as the row, so its frame is the row's
                        // for the followed team's band.
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named("standings.table"))
                        } action: { frame in
                            if followed { followedRowFrame = frame }
                        }
                        .accessibilityHidden(true)
                    HStack(spacing: Theme.Spacing.s) {
                        TeamLogo(team: crestTeam(for: entry), size: crestSize)
                        Text(rowName(entry))
                            .lineLimit(1)
                        // After the name, so the names stay in one column.
                        if followed {
                            FollowedMarker()
                        }
                        // Spelled out in the legend beneath (T5); readable
                        // grey, not tertiary, as it carries information.
                        if !entry.clincher.isEmpty {
                            Text(entry.clincher)
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.metadata)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The whole row to VoiceOver, as one element: its rank,
                    // team and columns, "9th, Kansas, 0 wins, 0 losses",
                    // and a tap's action. A grid row can't be one element
                    // itself, so the team's cell speaks for it and the
                    // others are hidden.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: entry, rank: rank, columns: columns))
                    .accessibilityAddTraits(followed ? .isSelected : [])
                    .accessibilityAddTraits(opensPage(entry) ? .isButton : [])
                    // The zone the bar shows by colour alone.
                    .accessibilityValue(entry.zone?.note ?? "")
                    .accessibilityAction {
                        open(entry)
                    }
                    .accessibilityIdentifier("standings.team.\(entry.teamID)")
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index].value(entry))
                            .monospacedDigit()
                            .accessibilityHidden(true)
                    }
                }
                .font(.footnote)
                .fontWeight(followed ? .bold : .regular)
                .padding(.vertical, 2)
                // Another team's row opens its page (t_8d15e070).
                .contentShape(.rect)
                .onTapGesture {
                    open(entry)
                }
            }
        }
        .coordinateSpace(.named("standings.table"))
        // One band behind the followed team's whole row: a background on a
        // grid row is each cell's, which broke it into a rectangle per
        // cell with the column spacing between.
        .background(alignment: .topLeading) {
            followedBand
        }
    }

    /// The followed team's row picked out in a faint wash of its accent
    /// and an outline in it, the table's full width (F3: an accent that
    /// clears 3:1 on the card in dark mode as in light, where the Royals'
    /// own blue vanished); nothing when the rows on show don't hold the
    /// team.
    @ViewBuilder
    private var followedBand: some View {
        if let frame = followedRowFrame, shownEntries.contains(where: { $0.element.teamID == followedID }) {
            let shape = RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous)
            shape
                .fill(accent.opacity(Theme.selectionWashOpacity(contrast: contrast)))
                .overlay {
                    shape.strokeBorder(accent, lineWidth: 1)
                }
                // The row's 2 pt of padding above and below its cells, and
                // a little room either side of the text.
                .frame(height: frame.height + 4)
                .padding(.horizontal, -Theme.Spacing.xs)
                .offset(y: frame.minY - 2)
                .accessibilityHidden(true)
        }
    }

    /// "9th, #7 Kansas, 10 wins, 6 losses, games behind 2": a row's rank,
    /// team and columns, each value with its column's name, skipping the
    /// cells the feed left blank ("" or "-").
    private func accessibilityLabel(for entry: StandingsEntry, rank: Int, columns: [Column]) -> String {
        let values = columns.compactMap { column -> String? in
            let value = column.value(entry)
            guard !value.isEmpty, value != "-", value != "–", value != "—" else { return nil }
            return column.spoken(value)
        }
        return ([ordinalString(rank), rowName(entry)] + values).joined(separator: ", ")
    }

    /// The row's team name, `"#7 Kansas"` when the league's poll ranks it.
    /// A poll's own table shows the rank in its # column instead.
    private func rowName(_ entry: StandingsEntry) -> String {
        let name = entry.shortName.isEmpty ? entry.name : entry.shortName
        guard kind != .rankings else { return name }
        return pollRanks.prefixed(name, teamID: entry.teamID)
    }

    /// Whether a tap on the row opens its team's page: any team but the
    /// one whose page this is.
    private func opensPage(_ entry: StandingsEntry) -> Bool {
        navigator != nil && !entry.teamID.isEmpty && entry.teamID != followedID
    }

    private func open(_ entry: StandingsEntry) {
        guard opensPage(entry), let navigator else { return }
        navigator.open(teamID: TeamRef.id(league: league, espnID: entry.teamID))
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

/// The standings while they load: a table's worth of skeleton rows — rank,
/// crest, name, figures — in the pulse the other sections' placeholders
/// take (X-6), where a spinner sat alone. "Loading" to VoiceOver.
private struct StandingsSkeleton: View {
    /// As a row's crest (`StandingsTable.crestSize`).
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 20
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            LoadingView()
                .frame(width: 120, height: lineHeight)

            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: Theme.Spacing.m) {
                    LoadingView()
                        .frame(width: 14, height: lineHeight)
                    HStack(spacing: Theme.Spacing.s) {
                        LoadingViewCircle()
                            .frame(width: crestSize, height: crestSize)
                        LoadingView()
                            .frame(height: lineHeight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LoadingView()
                        .frame(width: 64, height: lineHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }
}

/// A zone's mark: a 3 pt bar in the feed's colour down the leading edge of
/// a table row or legend line, as tall as whatever it is laid over.
private struct ZoneBar: View {
    let colorHex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(hexString: colorHex))
            .frame(width: 3)
            .accessibilityHidden(true)
    }
}

/// A stretch of a soccer table the feed annotates — `"Champions League"`
/// at the top, `"Relegation"` at the foot — and the colour it marks it in.
struct StandingsZone: Hashable, Sendable {
    let note: String
    /// Six hex digits, as `StandingsEntry.noteColorHex` keeps them.
    let colorHex: String
}

extension StandingsEntry {
    /// The zone the row is in, or `nil` where the feed marks none (or gives
    /// no colour to mark it in).
    var zone: StandingsZone? {
        guard !note.isEmpty, !noteColorHex.isEmpty else { return nil }
        return StandingsZone(note: note, colorHex: noteColorHex)
    }
}

/// A standings column a table draws only where the feed fills it in (R-5).
enum StandingsExtraColumn: Hashable, Sendable {
    /// The record against the team's own conference, "Conf": `"8-10"`.
    case conferenceRecord
    /// The current run, "Strk": `"W4"`.
    case streak
}

extension StandingsGroup {
    /// The optional columns this table draws after its own, in order:
    /// conference record, then streak, each only when some row has a value
    /// for it. A record table only (basketball, football, hockey): a soccer
    /// table already fills the width with its five, and a poll keeps no
    /// such columns. None at accessibility text sizes, where the table
    /// keeps today's columns and already scrolls sideways.
    func extraColumns(kind: StandingsKind, isAccessibilitySize: Bool) -> [StandingsExtraColumn] {
        guard kind == .records, !isAccessibilitySize else { return [] }
        var columns: [StandingsExtraColumn] = []
        if entries.contains(where: { !$0.conferenceRecord.isEmpty }) {
            columns.append(.conferenceRecord)
        }
        if entries.contains(where: { !$0.streak.isEmpty }) {
            columns.append(.streak)
        }
        return columns
    }

    /// The table's zones for its legend: each note once, in the order the
    /// rows first reach it, top of the table first.
    var zones: [StandingsZone] {
        var seen = Set<String>()
        return entries.compactMap(\.zone).filter { seen.insert($0.note).inserted }
    }

    /// The table's name on screen. A soccer feed names its one table after
    /// the season (`"2026-27 German Bundesliga"`), so a points table goes
    /// by the league's own name (`"Bundesliga"`) where there is one; a
    /// conference, division or poll keeps the feed's name.
    func title(kind: StandingsKind, leagueName: String?) -> String {
        guard kind == .pointsTable, let leagueName, !leagueName.isEmpty else { return name }
        return leagueName
    }
}

/// Which of a team's stories its page lists, and in what order (T7).
enum TeamPageNews {
    /// The most stories the section lists before "More … News".
    static let shownCount = 4

    /// `articles` with the stories tagged with `teamID` first, each group
    /// in the feed's order: a league-wide preview mentions the team only
    /// in passing, where a story tagged with it is about it.
    static func ordered(_ articles: [News], teamID: String) -> [News] {
        let tagged = articles.filter { article in article.teams.contains { $0.espnID == teamID } }
        let untagged = articles.filter { article in !article.teams.contains { $0.espnID == teamID } }
        return tagged + untagged
    }
}

/// The news at the foot of a team page: up to `TeamPageNews.shownCount`
/// of the team's latest stories, those tagged with the team first, then
/// "More <Team> News" for the rest (T7).
struct NewsSection<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let teamColor: Color

    /// The most stories the section lists while collapsed. Computed: a
    /// generic type can't store a static.
    static var shownCount: Int { TeamPageNews.shownCount }

    @State private var selectedArticle: News?

    /// Whether the reader asked for the rest of the stories.
    @State private var showsAll = false

    /// Opens a team a story is about (t_8d15e070); absent in previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    private var settings = AdaptiveSettings()

    /// Where an article's sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

    init(model: TeamModel<Player>, teamColor: Color) {
        self.model = model
        self.teamColor = teamColor
    }

    private func setShowsAll(_ value: Bool) {
        withAnimation(Theme.Motion.animation(Theme.Motion.stateChange, reduceMotion: settings.reduceMotion)) {
            showsAll = value
        }
    }

    var body: some View {
        let ordered = TeamPageNews.ordered(model.articles, teamID: model.team.espnID)
        let hasMore = ordered.count > Self.shownCount
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "book", title: "News") {
                if hasMore && !showsAll {
                    SeeAllLink(identifier: "news.seeAll") { setShowsAll(true) }
                }
            }
            .padding([.horizontal, .top])

            VStack(alignment: .center, spacing: Theme.Spacing.m) {
                if model.articles.isEmpty {
                    switch model.newsState {
                    case .loading:
                        ForEach(0..<Self.shownCount, id: \.self) { _ in
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
                    ForEach(showsAll ? ordered : Array(ordered.prefix(Self.shownCount))) { article in
                        articleButton(article)
                    }

                    if hasMore {
                        Button(showsAll ? "Show Fewer Stories" : "More \(model.team.shortName) News") {
                            setShowsAll(!showsAll)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("news.more")
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

    private func articleButton(_ article: News) -> some View {
        Button {
            selectedArticle = article
        } label: {
            NewsView(article: article)
        }
        .buttonStyle(.plain)
        .zoomSource(id: article.id, in: cardZoom)
        .accessibilityIdentifier("news.article")
        // A tap opens the story; the teams it's about are a long press
        // away, and VoiceOver actions through the menu (t_8d15e070).
        .contextMenu {
            if let navigator {
                ForEach(article.teams) { team in
                    Button {
                        navigator.open(teamID: TeamRef.id(league: model.team.league, espnID: team.espnID))
                    } label: {
                        Label(team.name, systemImage: "person.3")
                    }
                }
            }
        }
    }
}

/// What a team page's header says under the team's name, on two lines in
/// one template for every team (T1): the record and the team's place in
/// its table, `"4-0 · 1st AFC West"`; then the last five results and the
/// next game, `"Next vs Chargers · Sun, Oct 18"`, or `"Season complete"`.
/// Each is `nil` until its feed has something to say.
struct TeamHeaderSummary: Equatable, Sendable {
    /// The season record so far, `"10-6"`, in its sport's shape.
    var record: String?
    /// The team's place in its table, short enough to sit beside the record
    /// on one line: `"1st AFC West"` in a division, `"13th in AL"`,
    /// `"15th in West"`, or its poll rank, `"No. 5 in AP Top 25"`.
    var standing: String?
    /// The next game still to be played, `"vs Raiders · Sun, Oct 12"`.
    var nextGame: String?
    /// The last five decided league games, oldest first, drawn as W/D/L
    /// capsules beside the next game (`scheduleForm`, R-5). Empty before any.
    var form: [Record.Outcome]
    /// Whether the season is over (`seasonComplete`, T8).
    var seasonComplete: Bool

    /// How long after a schedule's last game, every game played, the season
    /// counts as over: past a playoff team's wait for its next round, so a
    /// schedule whose postseason isn't listed yet doesn't read as done.
    static let settledInterval: TimeInterval = 14 * 24 * 60 * 60

    init(
        record: String? = nil,
        standing: String? = nil,
        nextGame: String? = nil,
        form: [Record.Outcome] = [],
        seasonComplete: Bool = false
    ) {
        self.record = record
        self.standing = standing
        self.nextGame = nextGame
        self.form = form
        self.seasonComplete = seasonComplete
    }

    /// The summary from a team page's model: `record` as the schedule
    /// section counts it, the team's row in `standings`, `games[nextGame]`
    /// if it's still to be played, and the form from the same games the
    /// record is counted from. `scheduleLoaded` is whether the schedule
    /// feed has answered, without which an empty schedule says nothing.
    init(
        team: TeamRef,
        games: [Game],
        nextGame: Int,
        record: Record,
        standings: Standings?,
        scheduleLoaded: Bool = true,
        now: Date = Date()
    ) {
        let standingsRecord = standings.flatMap { Self.standingsRecord(of: team.espnID, in: $0) }
        self.record = games.isEmpty ? standingsRecord : record.summary
        self.standing = standings.flatMap {
            Self.standing(of: team.espnID, in: $0, leagueName: team.league.descriptor.displayName)
        }
        self.nextGame = Self.upcoming(games: games, nextGame: nextGame)
        self.form = scheduleForm(games: games, league: team.league)
        self.seasonComplete = Self.seasonComplete(
            games: games,
            nextGame: nextGame,
            standingsRecord: standingsRecord,
            scheduleLoaded: scheduleLoaded,
            now: now
        )
    }

    /// `"Last 5: won, won, lost, drew, won"`, oldest first, for VoiceOver;
    /// `nil` with no form.
    var formAccessibilityLabel: String? {
        guard !form.isEmpty else { return nil }
        return "Last \(form.count): " + form.map(\.spokenName).joined(separator: ", ")
    }

    /// The header's first line, the record and standing, `"10-6 · 2nd AFC
    /// West"`.
    var recordLine: String? {
        let parts = [record, standing].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The words on the header's second line, after the form: `"Next vs
    /// Raiders · Sun, Oct 12"`, else `"Season complete"` once it is, else
    /// `nil`.
    var detailLine: String? {
        if let nextGame { return "Next \(nextGame)" }
        return seasonComplete ? "Season complete" : nil
    }

    /// The team's place in the table that holds it, or `nil` where the
    /// feed ranks nobody yet: `"1st AFC West"` in a division, `"13th in
    /// AL"` or `"3rd in Bundesliga"` in anything wider, by the table's
    /// short title (`StandingsGroup.shortTitle(kind:leagueName:)`), so the
    /// line fits beside the record without wrapping.
    static func standing(of teamID: String, in standings: Standings, leagueName: String? = nil) -> String? {
        guard let group = standings.group(containing: teamID),
              let rank = group.entries.first(where: { $0.teamID == teamID })?.rank,
              rank > 0
        else { return nil }
        let title = group.shortTitle(kind: standings.kind, leagueName: leagueName)
        switch standings.kind {
        case .rankings:
            return "No. \(rank) in \(title)"
        case .pointsTable, .records:
            return StandingsGroup.isDivisionTitle(title)
                ? "\(ordinalString(rank)) \(title)"
                : "\(ordinalString(rank)) in \(title)"
        }
    }

    /// The team's record as its standings row gives it, for a team whose
    /// schedule is empty (a season over: the Royals' 69-93 in October), or
    /// `nil` where the row has no games yet or the table is a poll.
    static func standingsRecord(of teamID: String, in standings: Standings) -> String? {
        guard standings.kind != .rankings,
              let record = standings.entry(for: teamID)?.record,
              record.gamesPlayed > 0
        else { return nil }
        return record.summary
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

    /// Whether the team's season is over (T8), once the schedule feed has
    /// answered (`scheduleLoaded`): a schedule already empty whose
    /// standings row has a record (`standingsRecord`, the Royals in
    /// October), or one with nothing left to play — every game played,
    /// called off or postponed — whose last game is `settledInterval` past.
    static func seasonComplete(
        games: [Game],
        nextGame: Int,
        standingsRecord: String?,
        scheduleLoaded: Bool,
        now: Date
    ) -> Bool {
        guard scheduleLoaded else { return false }
        if games.isEmpty { return standingsRecord != nil }
        guard upcoming(games: games, nextGame: nextGame) == nil,
              games.allSatisfy({ $0.completed || $0.cancelled || $0.postponed }),
              let last = games.filter(\.completed).map(\.dateAsDate).max()
        else { return false }
        return now.timeIntervalSince(last) >= settledInterval
    }
}

/// The top of a team page, over the team colour, under the bar's crest and
/// name (`TeamBarTitle`), in one template for every team (T1): the record
/// and standing on the first line, the last five results as W/D/L
/// capsules and the next game on the second. Drawn in the ink for the
/// team colour (`teamInk(on:)`, F2), the capsules too (`FormCapsule`, F4).
/// Plain scrolling content: it scrolls under the bar with the cards, never
/// over them. Centred at regular width (T10).
///
/// A college team in its league's poll leads the record with its rank,
/// `"#7"` (R-5). Where the second line can't hold the capsules and the
/// next game, the game goes beneath them.
struct TeamPageHeader: View {
    let team: TeamRef
    let summary: TeamHeaderSummary

    /// The league's poll, for a college team; empty otherwise.
    @State private var pollRanks = PollRanks.empty

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The team's poll rank, or `nil` unranked.
    private var pollRank: Int? {
        pollRanks.rank(of: team.espnID)
    }

    private var centred: Bool { sizeClass == .regular }

    private var horizontalAlignment: HorizontalAlignment { centred ? .center : .leading }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: Theme.Spacing.s) {
            rankAndRecord

            if !summary.form.isEmpty || summary.detailLine != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        formGuide
                        detail
                    }
                    VStack(alignment: horizontalAlignment, spacing: Theme.Spacing.xs) {
                        formGuide
                        detail
                    }
                }
            }
        }
        .multilineTextAlignment(centred ? .center : .leading)
        .teamInk(on: team)
        .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("teamPage.summary")
        .task(id: team.id) {
            pollRanks = await PollRankStore.shared.ranks(for: team.league)
        }
    }

    /// `"#7 4-0 · 16th in Big 12"`: the poll rank, where there is one,
    /// before the record line.
    @ViewBuilder
    private var rankAndRecord: some View {
        let recordLine = summary.recordLine
        if pollRank != nil || recordLine != nil {
            HStack(spacing: Theme.Spacing.xs) {
                if let pollRank {
                    Text(PollRanks.badge(rank: pollRank) ?? "")
                        .fontWeight(.heavy)
                        .accessibilityLabel(
                            pollRanks.pollName.isEmpty
                                ? "Ranked number \(pollRank)"
                                : "Ranked number \(pollRank) in \(pollRanks.pollName)"
                        )
                }
                if let recordLine {
                    Text(recordLine)
                }
            }
            .font(.headline)
            .monospacedDigit()
        }
    }

    /// The next game, or that the season is over.
    @ViewBuilder
    private var detail: some View {
        if let line = summary.detailLine {
            Text(line)
                .font(Theme.Typography.footnote.weight(.semibold))
        }
    }

    /// The last five results as capsules, oldest first. The letter carries
    /// the result; the fill only echoes it (a win solid, a draw faint, a
    /// loss outlined), in the header's ink with a win's letter cut out in
    /// the team colour, so it reads on any team colour (F4).
    @ViewBuilder
    private var formGuide: some View {
        if let label = summary.formAccessibilityLabel {
            let ink = TeamColors.ink(on: team)
            let fill = Color(hexString: TeamColors.fillHex(for: team))
            HStack(spacing: 3) {
                ForEach(Array(summary.form.enumerated()), id: \.offset) { _, outcome in
                    FormCapsule(outcome: outcome, ink: ink, fill: fill)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("teamPage.form")
        }
    }
}

/// One result in a form guide: its letter in a small capsule.
///
/// Given the colour it sits on (`ink` and `fill`), a win is a solid ink
/// pill with its letter cut out in the fill, a loss an ink outline and a
/// draw a faint ink wash, so the three read apart at a glance and the win's
/// letter clears 4.5:1 (the translucent capsules measured 3.3:1 on red).
/// Without them it keeps the older translucent look, in the inherited
/// foreground style.
struct FormCapsule: View {
    let outcome: Record.Outcome
    /// The header's text colour, which the pill is drawn in.
    var ink: Color?
    /// The colour behind the pill, which a win's letter is drawn in.
    var fill: Color?

    init(outcome: Record.Outcome, ink: Color? = nil, fill: Color? = nil) {
        self.outcome = outcome
        self.ink = ink
        self.fill = fill
    }

    var body: some View {
        if let ink, let fill {
            solid(ink: ink, fill: fill)
        } else {
            translucent
        }
    }

    /// A fixed circle a little over the letter's height, so a row of them
    /// lines up; it grows with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 20

    private func solid(ink: Color, fill: Color) -> some View {
        Text(outcome.letter)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(outcome == .win ? fill : ink)
            .frame(minWidth: diameter, minHeight: diameter)
            .background {
                switch outcome {
                case .win:
                    Capsule().fill(ink)
                case .draw:
                    Capsule().fill(ink.opacity(0.22))
                case .loss:
                    Capsule().strokeBorder(ink, lineWidth: 1.25)
                }
            }
    }

    private var translucent: some View {
        Text(outcome.letter)
            .font(.caption2.weight(.bold))
            .monospaced()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            // An unstyled shape takes the foreground style: the header's ink.
            .background {
                switch outcome {
                case .win:
                    Capsule().opacity(0.3)
                case .draw:
                    Capsule().opacity(0.12)
                case .loss:
                    Capsule().strokeBorder(lineWidth: 1).opacity(0.5)
                }
            }
    }
}

/// The body of every team page: its summary over the team colour, then the
/// sections as inset rounded cards on the grouped background, which rounds
/// its top corners where it meets the team-colour hero (T-4). No glass:
/// this is scrolling content (B1).
///
/// Lays the page out only. The page scrolls in `TeamPage`'s scroll view,
/// which draws the team colour behind the summary, pins the crest and name
/// in the bar, and carries the bottom edge effect under the tab bar. The
/// summary and the cards scroll together, one after the other, so neither
/// is ever drawn over the other.
struct TeamHomeLayout<Header: View, Content: View>: View {
    let content: Content
    let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    @Environment(\.containerSize) private var containerSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(TeamPageChrome.self) private var chrome: TeamPageChrome?

    /// The widest the page's column runs at regular width (an iPad), where
    /// its sections stand in two columns (T10); each table in them is
    /// capped narrower still.
    static var regularWidth: CGFloat { 1100 }

    /// The column's cap: two columns' worth at regular width, a readable
    /// line's on an iPhone (where it changes nothing).
    private var columnWidth: CGFloat {
        sizeClass == .regular ? Self.regularWidth : Theme.readableWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                // In line with the cards' column; the team colour behind
                // it is `TeamPage`'s, full-bleed.
                .readableContentWidth(columnWidth)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    chrome?.headerHeight = height
                }

            VStack(spacing: Theme.Spacing.m) {
                content
            }
            .padding(Theme.Spacing.m)
            // A column on an iPad, centred on the grouped page, which
            // stays full-bleed (B-14); the full width on an iPhone.
            .readableContentWidth(columnWidth)
            // At least a screen tall, so a page still loading covers the hero
            // rather than leaving it showing beneath a short page.
            .frame(maxWidth: .infinity, minHeight: containerSize.height, alignment: .top)
            .background(Theme.Surface.content, in: Theme.Radius.pageShape)
        }
    }
}

/// The one way a section header offers more (F6): a text button, "See All"
/// and a chevron, in the accent, trailing the title. At least 44 pt tall.
/// Icons stay for what filters or sorts a section in place.
struct SeeAllLink: View {
    var title: String = "See All"
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .imageScale(.small)
            }
            .font(.body)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
    }
}
