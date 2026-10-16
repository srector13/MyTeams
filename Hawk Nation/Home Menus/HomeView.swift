//
//  HomeView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The Home tab, first in the bar and where the app opens (t_0b94af11):
/// every favorite at once, in a team page's language. A hero in the
/// colour of the game that matters most right now (`HomeHero`), under the
/// bar's title and date in that colour too; then, on the rounded grouped
/// page over it, the reader's sections in the reader's order
/// (`HomeSectionLayout`): My Teams, This Week, the standings, the top
/// performers and the news.
///
/// Reads what the app already loads (`HomeViewModel`): the scoreboards the
/// app polls for every favorite, the seasons it loaded to know which, the
/// shared standings, poll and leaders stores, and each favorite's news
/// feed. No page of its own to poll.
///
/// Glass is the chrome's alone (§5.2): the navigation bar with its gear,
/// and the tab bar. The sections are content cards on the grouped page, as
/// a team page's are (B1).
struct HomeView: View {
    /// The favorites, resolved, in favorites order.
    let teams: [TeamRef]
    /// Opens the team browser, which `Home` presents.
    let addTeams: @MainActor () -> Void
    /// Opens Settings, which `Home` presents so that it outlives the tab.
    let showSettings: @MainActor () -> Void

    @State private var model = HomeViewModel()

    @Environment(\.brandTheme) private var theme

    var body: some View {
        let style = HomeHeroStyle(featured: model.featured, accent: theme.accentColor)
        // With no favorites the page is the empty state, under the plain
        // bar; with any, the bar takes the hero's colour.
        let barInk: Color? = teams.isEmpty ? nil : style.barInk
        NavigationStack {
            Group {
                if teams.isEmpty {
                    HomeEmptyState(addTeams: addTeams)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Surface.content)
                } else {
                    HomeDashboard(model: model, style: style, addTeams: addTeams)
                }
            }
            .navigationTitle("Home")
            // Today's date under the title, as Leaders puts its season there.
            .navigationSubtitle(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // The way to Settings and its alerts from where the app
                // opens, as a team page has it (A-5).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings()
                    } label: {
                        if let barInk {
                            Label("Settings", systemImage: "gearshape")
                                .foregroundStyle(barInk)
                        } else {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    // In the bar's ink over the hero colour, not the app's
                    // accent (H-6).
                    .tint(barInk)
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("home.settings")
                }
            }
        }
        // Mounted only while Home's tab is on screen, so it refreshes only
        // then; a change of favorites starts it over.
        .task(id: teams.map(\.id)) { await model.run(teams: teams) }
    }
}

/// Home with no favorites: a fresh install, or every team unfollowed. The
/// way in is here rather than a sheet at launch (t_afe5c297).
private struct HomeEmptyState: View {
    let addTeams: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Teams Yet")
            } icon: {
                // The brand theme's art, for the scheme on screen.
                BrandLogoMark()
                    .frame(width: BrandLogo.hero)
                    .accessibilityHidden(true)
            }
        } description: {
            Text("Add the teams you follow to see their live games, schedules, scores and news.")
        } actions: {
            Button {
                addTeams()
            } label: {
                Label("Add your first team", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Find a team by sport, league or name, and follow it.")
            .accessibilityIdentifier("home.addTeams")
        }
        // No identifier on the view itself: on a container that isn't an
        // accessibility element, SwiftUI hands it down to every element
        // inside, replacing the button's "home.addTeams".
    }
}

/// A game Home opens a sheet for, and the card it zooms from (X-13): the
/// same game can be in the hero and This Week, each its own source.
private struct HomeGameSelection: Identifiable {
    let entry: HomeGame
    let sourceID: String

    var id: String { sourceID }
}

/// Home with favorites, laid out as a team page is (`TeamPage`): the hero
/// colour fixed behind everything, the hero scrolling over it, then the
/// grouped page with its rounded top and the sections as cards on it. The
/// same colour is opaque behind the status bar and the navigation bar
/// (`barBackdrop`), so the page scrolls under the bar's title and gear
/// rather than showing through them.
///
/// On an iPhone the sections are one readable column; at regular width (an
/// iPad) two, My Teams and This Week on the left and the rest on the right,
/// each in the reader's order, centred no wider than `regularMaxWidth`.
private struct HomeDashboard: View {
    let model: HomeViewModel
    let style: HomeHeroStyle
    let addTeams: @MainActor () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.containerSize) private var containerSize
    /// Opens a favorite's tab, and a player's sheet on it; absent in
    /// previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    @AppStorage(HomeSectionLayout.storageKey) private var layoutStorage = ""

    @State private var selectedGame: HomeGameSelection?
    @State private var selectedArticle: HomeHeadline?
    @State private var showsCustomize = false
    /// This Week's day, once the reader has picked one; until then the
    /// day it opens on (`HomeFeed.defaultDay`).
    @State private var selectedDay: Date?
    /// The news feed's team, or `nil` for every favorite's stories.
    @State private var newsFilter: TeamRef.ID?
    /// The hero's height, which the colour behind it must cover.
    @State private var heroHeight: CGFloat = 0

    /// Where a sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

    private var settings = AdaptiveSettings()

    init(model: HomeViewModel, style: HomeHeroStyle, addTeams: @escaping @MainActor () -> Void) {
        self.model = model
        self.style = style
        self.addTeams = addTeams
    }

    /// The widest the page's two columns run on an iPad.
    static let regularMaxWidth: CGFloat = 1100

    /// The tallest the hero colour is drawn at regular width, as a team
    /// page caps its own (`TeamPageBody.maxRegularHeroHeight`).
    static let maxRegularHeroHeight: CGFloat = 320

    /// At accessibility text sizes the carousels become vertical lists, as
    /// a team page's do (§5.3).
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    private var isRegular: Bool { sizeClass == .regular }

    private var columnWidth: CGFloat { isRegular ? Self.regularMaxWidth : Theme.readableWidth }

    /// Tall enough to sit behind the hero and the page's rounded top, with
    /// room to pull the page down; capped at regular width.
    private var heroBackdropHeight: CGFloat {
        let height = max(containerSize.height / 2, heroHeight + containerSize.height / 4)
        guard isRegular else { return height }
        return min(height, max(Self.maxRegularHeroHeight, heroHeight + Theme.Radius.page * 4))
    }

    var body: some View {
        let layout = HomeSectionLayout(storage: layoutStorage)
        let featured = model.featured
        ZStack(alignment: .top) {
            // The hero colour. It never scrolls: the page covers it.
            Rectangle()
                .fill(LinearGradient(colors: [style.fill, style.footFill], startPoint: .top, endPoint: .bottom))
                .frame(height: heroBackdropHeight)
                .backgroundExtensionEffect()
                .accessibilityHidden(true)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HomeHero(
                        featured: featured,
                        style: style,
                        teams: model.teams,
                        isLoading: model.seasonsLoading,
                        now: model.now,
                        zoomNamespace: cardZoom
                    ) { featured in
                        selectedGame = HomeGameSelection(entry: featured.entry, sourceID: HomeHero.sourceID(for: featured))
                    }
                    .frame(maxWidth: columnWidth)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        heroHeight = height
                    }

                    page(layout)
                }
            }
            .scrollIndicators(.hidden)
            // Pull to refresh: the news, whatever its age, any season that
            // failed, and the tables (C-1).
            .refreshable { [model] in
                await model.refreshAll()
            }
            // The page scrolls under the tab bar, softened there (T-5, B5).
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // The bar is opaque hero colour: nothing to soften there.
            .scrollEdgeEffectHidden(true, for: .top)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("home.page")

            // Drawn after the scroll view, so over the page.
            barBackdrop
        }
        // The grouped page behind the hero, showing past the foot of the
        // page and under the tab bar.
        .background(Theme.Surface.content)
        // The system bar in the hero colour too, and the scheme that reads
        // on it whatever is scrolled beneath, as on a team page.
        .toolbarBackground(style.fill, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(style.barScheme, for: .navigationBar)
        .sheet(item: $selectedGame) { selection in
            GameDetailView(game: selection.entry.game, team: selection.entry.team)
                .zoomTransition(sourceID: selection.sourceID, in: cardZoom)
        }
        .sheet(item: $selectedArticle) { headline in
            NewsDetailView(article: headline.article, color: headline.team.color)
                .zoomTransition(sourceID: headline.id, in: cardZoom)
        }
        .sheet(isPresented: $showsCustomize) {
            HomeCustomizeSheet()
        }
    }

    /// The hero colour behind the status bar and the navigation bar, and
    /// only there: a zero-height view at the top of the safe area whose
    /// background takes the top safe area, which is exactly the two bars.
    /// Opaque and above the scroll view, so the page scrolls under it.
    private var barBackdrop: some View {
        Color.clear
            .frame(height: 0)
            .background(alignment: .bottom) {
                style.fill
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Page

    /// The grouped page under the hero: the reader's sections, in one
    /// column or two, then the way to customize them.
    private func page(_ layout: HomeSectionLayout) -> some View {
        let visible = layout.visible
        let leading = visible.filter(\.isLeadingColumn)
        let trailing = visible.filter { !$0.isLeadingColumn }
        return VStack(spacing: Theme.Spacing.m) {
            if isRegular && !leading.isEmpty && !trailing.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    column(leading)
                    column(trailing)
                }
            } else {
                column(visible)
            }

            customizeButton
        }
        .padding(Theme.Spacing.m)
        // A readable column on an iPhone's width and an iPad's, centred on
        // the grouped page, which stays full-bleed (B-14).
        .readableContentWidth(columnWidth)
        // At least a screen tall, so a page still loading covers the hero
        // colour rather than leaving it showing beneath a short page.
        .frame(maxWidth: .infinity, minHeight: containerSize.height, alignment: .top)
        .background(Theme.Surface.content, in: Theme.Radius.pageShape)
    }

    private func column(_ kinds: [HomeSectionKind]) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(kinds) { kind in
                sectionView(kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func sectionView(_ kind: HomeSectionKind) -> some View {
        switch kind {
        case .myTeams: myTeamsSection
        case .week: weekSection
        case .standings: standingsSection
        case .performers: performersSection
        case .news: newsSection
        }
    }

    /// "Customize Home", at the foot of the page.
    private var customizeButton: some View {
        Button {
            showsCustomize = true
        } label: {
            Label("Customize Home", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.s)
        .accessibilityHint("Show, hide and reorder Home's sections.")
        .accessibilityIdentifier("home.customize")
    }

    // MARK: My Teams

    /// A card per favorite (`HomeTeamCard`), opening its tab.
    private var myTeamsSection: some View {
        let summaries = model.teamSummaries
        return accessorySection(systemImage: HomeSectionKind.myTeams.systemImage, title: "My Teams", identifier: "home.section.myTeams") {
            // A standard glass control, as the team page's Leaders header
            // has (T-1): the browser, to follow or unfollow teams.
            Button("Edit") {
                addTeams()
            }
            .font(.subheadline)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Edit teams")
            .accessibilityIdentifier("home.myTeams.edit")
        } content: {
            if usesStackedLayout {
                StackedCarousel(items: summaries) { summary in
                    teamButton(summary)
                }
            } else {
                carousel {
                    // Not lazy: a card per favorite, laid out together so
                    // each is as tall as the tallest.
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(summaries) { summary in
                            teamButton(summary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func teamButton(_ summary: HomeTeamSummary) -> some View {
        Button {
            navigator?.open(summary.team)
        } label: {
            HomeTeamCard(summary: summary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityHint("Opens the team's page.")
        .accessibilityIdentifier("home.myTeams.\(summary.team.id)")
    }

    // MARK: This Week

    /// The strip of days from `HomeFeed.weekDaysBack` ago to
    /// `HomeFeed.weekDaysAhead` on, and the picked day's games as schedule
    /// cards; one line when the week has none.
    private var weekSection: some View {
        let week = model.week
        let hasGames = week.contains { !$0.games.isEmpty }
        let opening = HomeFeed.defaultDay(in: week, now: model.now)
        let picked = selectedDay.flatMap { day in week.first { $0.date == day } }
        let shown = picked ?? week.first { $0.date == opening }
        return section(systemImage: HomeSectionKind.week.systemImage, title: "This Week", identifier: "home.section.week") {
            if !hasGames && !model.seasonsLoading {
                // A line, not a carousel's height of nothing: a team
                // between seasons has nothing this week.
                compactLine("No games this week", identifier: "home.week.empty")
            } else {
                dayStrip(week, shown: shown?.date)
                dayGames(shown)
            }
        }
    }

    /// The days, the picked one ringed, opened scrolled to it.
    private func dayStrip(_ week: [HomeWeekDay], shown: Date?) -> some View {
        let today = Calendar.autoupdatingCurrent.startOfDay(for: model.now)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(week) { day in
                        HomeWeekDayButton(day: day, isToday: day.date == today, isSelected: day.date == shown) {
                            withAnimation(Theme.Motion.animation(Theme.Motion.selection, reduceMotion: settings.reduceMotion)) {
                                selectedDay = day.date
                            }
                        }
                        .id(day.date)
                        .accessibilityIdentifier("home.week.day.\(HomeFeed.dayKey(day.date))")
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onAppear {
                if let shown {
                    proxy.scrollTo(shown, anchor: .center)
                }
            }
            // The seasons landing, or the day turning over, can move the
            // day it opens on.
            .onChange(of: shown) { _, day in
                if let day {
                    proxy.scrollTo(day, anchor: .center)
                }
            }
        }
    }

    /// The picked day's games as the team page's schedule cards
    /// (`GameView`), each opening its sheet; placeholders while the
    /// seasons load; one line on a quiet day.
    @ViewBuilder
    private func dayGames(_ day: HomeWeekDay?) -> some View {
        if let day, !day.games.isEmpty {
            if usesStackedLayout {
                StackedCarousel(items: day.games) { entry in
                    weekGameButton(entry)
                }
            } else {
                carousel {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(day.games) { entry in
                            weekGameButton(entry)
                        }
                    }
                }
            }
        } else if model.seasonsLoading {
            carousel {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(0..<2, id: \.self) { _ in
                        LoadingGameView()
                    }
                }
            }
            .scrollDisabled(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading"))
        } else {
            compactLine(
                day.map { "No games \($0.date.formatted(.dateTime.weekday(.wide)))" } ?? "No games",
                identifier: "home.week.dayEmpty"
            )
        }
    }

    /// A game's schedule card, under the identifier of what it is: a
    /// result (`home.result.<id>`), a game under way (`home.live.<id>`),
    /// or one to come (`home.upcoming.<id>`).
    private func weekGameButton(_ entry: HomeGame) -> some View {
        let liveScore = model.liveScore(for: entry.game, team: entry.team)
        let identifier: String
        if entry.game.completed {
            identifier = "home.result.\(entry.id)"
        } else if GameCardContent.phase(of: entry.game, now: model.now, liveScore: liveScore) == .live {
            identifier = "home.live.\(entry.id)"
        } else {
            identifier = "home.upcoming.\(entry.id)"
        }
        return gameButton(entry, source: "week", identifier: identifier) {
            GameView(game: entry.game, team: entry.team, liveScore: liveScore)
        }
        .accessibilityLabel(
            "\(entry.team.shortName): "
                + entry.game.accessibilitySummary(
                    drawLabel: entry.team.league.descriptor.drawLabel,
                    liveScore: liveScore,
                    league: entry.team.league.descriptor
                )
        )
    }

    // MARK: Standings

    /// Each favorite's slice of its table (`HomeStandingsCard`), opening its
    /// tab; skeletons while the tables load; nothing once they have, if no
    /// table holds a favorite.
    @ViewBuilder
    private var standingsSection: some View {
        let slices = model.standingsSlices
        if !slices.isEmpty || model.tablesState == .loading {
            section(systemImage: HomeSectionKind.standings.systemImage, title: "Standings", identifier: "home.section.standings") {
                if slices.isEmpty {
                    carousel {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(0..<2, id: \.self) { _ in
                                HomeStandingsCardPlaceholder()
                            }
                        }
                    }
                    .scrollDisabled(true)
                } else if usesStackedLayout {
                    StackedCarousel(items: slices) { slice in
                        standingsButton(slice)
                    }
                } else {
                    carousel {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ForEach(slices) { slice in
                                standingsButton(slice)
                            }
                        }
                    }
                }
            }
        }
    }

    private func standingsButton(_ slice: HomeStandingsSlice) -> some View {
        Button {
            navigator?.open(slice.team)
        } label: {
            HomeStandingsCard(slice: slice)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slice.accessibilityLabel)
        .accessibilityHint("Opens the team's page.")
        .accessibilityIdentifier("home.standings.\(slice.team.id)")
    }

    // MARK: Top Performers

    /// Each favorite's leader on its first board (`HomePerformerCard`),
    /// opening their player sheet on the favorite's page, as a team page's
    /// leader cards do; skeletons while the leaders load.
    @ViewBuilder
    private var performersSection: some View {
        let performers = model.performers
        if !performers.isEmpty || model.tablesState == .loading {
            section(systemImage: HomeSectionKind.performers.systemImage, title: "Top Performers", identifier: "home.section.performers") {
                if performers.isEmpty {
                    carousel {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(0..<3, id: \.self) { _ in
                                LoadingLeaderCard()
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Loading"))
                } else if usesStackedLayout {
                    StackedCarousel(items: performers) { performer in
                        performerButton(performer)
                    }
                } else {
                    carousel {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ForEach(performers) { performer in
                                performerButton(performer)
                            }
                        }
                    }
                }
            }
        }
    }

    private func performerButton(_ performer: HomePerformer) -> some View {
        Button {
            let athleteID = performer.row.leader.athleteID
            navigator?.open(performer.team, playerID: athleteID.isEmpty ? nil : athleteID)
        } label: {
            HomePerformerCard(performer: performer)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(performer.accessibilityLabel)
        .accessibilityHint("Shows the player.")
        .accessibilityIdentifier("home.performers.\(performer.team.id)")
    }

    // MARK: News

    /// The favorites' stories, dealt in turn across them
    /// (`HomeFeed.headlines`), uncapped: with more than one favorite, a
    /// chip for each to narrow it to theirs; the first story large, the
    /// rest as compact rows, drawn as they scroll in.
    @ViewBuilder
    private var newsSection: some View {
        let all = model.headlines
        let filterTeam = newsFilter.flatMap { id in model.teams.first { $0.id == id } }
        let shown = filterTeam.map { HomeFeed.headlines(all, about: $0) } ?? all
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(systemImage: HomeSectionKind.news.systemImage, title: "News")
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.section.news")

            if model.teams.count > 1 && !all.isEmpty {
                newsFilters(selected: filterTeam)
            }

            if let lead = shown.first {
                newsButton(lead) {
                    HomeNewsLeadCard(headline: lead)
                }

                LazyVStack(spacing: Theme.Spacing.s) {
                    ForEach(shown.dropFirst()) { headline in
                        newsButton(headline) {
                            HomeNewsRow(headline: headline)
                        }
                    }
                }
            } else if let filterTeam {
                compactLine("No stories about the \(filterTeam.shortName) right now.", identifier: "home.news.filterEmpty")
                    .contentCard()
            } else {
                newsStatus
            }
        }
    }

    /// "All", then a chip per favorite, the picked one filled.
    private func newsFilters(selected: TeamRef?) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                HomeNewsFilterChip(title: "All", team: nil, isSelected: selected == nil) {
                    newsFilter = nil
                }
                .accessibilityIdentifier("home.news.filter.all")

                ForEach(model.teams) { team in
                    HomeNewsFilterChip(title: team.shortName, team: team, isSelected: selected?.id == team.id) {
                        newsFilter = team.id
                    }
                    .accessibilityIdentifier("home.news.filter.\(team.id)")
                }
            }
        }
        .contentMargins(.horizontal, Theme.Spacing.xs, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    /// A story as a button that opens its sheet, the teams it's about a
    /// long press away, as on a team page's news (t_8d15e070).
    private func newsButton<Card: View>(_ headline: HomeHeadline, @ViewBuilder label: () -> Card) -> some View {
        let card = label()
        return Button {
            selectedArticle = headline
        } label: {
            card
        }
        .buttonStyle(.plain)
        .zoomSource(id: headline.id, in: cardZoom)
        .accessibilityIdentifier("home.news.row")
        .contextMenu {
            if let navigator {
                ForEach(headline.article.teams) { team in
                    Button {
                        navigator.open(teamID: TeamRef.id(league: headline.team.league, espnID: team.espnID))
                    } label: {
                        Label(team.name, systemImage: "person.3")
                    }
                }
            }
        }
    }

    /// What an empty feed shows, as a team page's news does (P1's
    /// `SectionLoadState`): placeholder rows while the feeds load, one
    /// line once they have answered with nothing, or an error with a retry.
    @ViewBuilder
    private var newsStatus: some View {
        switch model.headlinesState {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in
                LoadingNewsView()
                    .padding(Theme.Spacing.m)
                    .contentCard()
            }
        case .loaded:
            SectionStatusView(message: "No news right now.")
                .frame(maxWidth: .infinity)
                .contentCard()
        case .failed:
            SectionStatusView(message: "Couldn't load the news") {
                Task { [model] in
                    await model.reloadNews()
                }
            }
            .frame(maxWidth: .infinity)
            .contentCard()
        }
    }

    // MARK: Pieces

    /// A section's card: its header, then `content`. A container to
    /// VoiceOver and the UI tests, under `identifier`.
    private func section<Content: View>(
        systemImage: String,
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        accessorySection(systemImage: systemImage, title: title, identifier: identifier) {
            EmptyView()
        } content: {
            content()
        }
    }

    /// `section` with a control at its header's trailing end.
    private func accessorySection<Accessory: View, Content: View>(
        systemImage: String,
        title: String,
        identifier: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let accessory = accessory()
        let content = content()
        return VStack(alignment: .leading) {
            SectionHeader(systemImage: systemImage, title: title) {
                accessory
            }
            .padding([.leading, .top, .trailing])
            .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// A section's cards side by side, scrolling sideways, as a team page's
    /// carousels do: inset in line with the header, coming to rest on a
    /// card's leading edge (T-4, T-8). No glass: it's content (§5.2).
    private func carousel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return ScrollView(.horizontal) {
            content
                .scrollTargetLayout()
                .padding(.bottom, Theme.Spacing.l)
        }
        .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    /// One line of secondary text in a section with nothing to show.
    private func compactLine(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .bottom])
            .padding(.top, Theme.Spacing.xs)
            .accessibilityIdentifier(identifier)
    }

    /// A card as a button that opens its game's sheet (T-3). No glass:
    /// it's content (§5.2).
    private func gameButton<Card: View>(
        _ entry: HomeGame,
        source: String,
        identifier: String,
        @ViewBuilder label: () -> Card
    ) -> some View {
        let sourceID = "\(source)|\(entry.id)"
        let card = label()
        return Button {
            selectedGame = HomeGameSelection(entry: entry, sourceID: sourceID)
        } label: {
            card
        }
        .buttonStyle(.plain)
        .zoomSource(id: sourceID, in: cardZoom)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Live

extension HomeLiveGame {
    /// "Rams 14, Broncos 21, 4th Quarter · 0:48": away first, as the hero
    /// and the matchup read.
    var accessibilityLabel: String {
        "\(info.awayName) \(state.awayScore), \(info.homeName) \(state.homeScore), \(state.stage)"
    }
}

// MARK: - News

/// The news feed's first story, large: its picture across the card, the
/// favorite it came from as a chip, the headline, the summary, and the
/// outlet and age. No glass: the feed scrolls (§5.2).
private struct HomeNewsLeadCard: View {
    let headline: HomeHeadline

    private var article: News { headline.article }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // A clear frame carries the picture's shape, so a filled image
            // can't widen the card; the image is drawn over it.
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImage(url: article.urlToImage) {
                        RemoteImagePlaceholder()
                    }
                    .scaledToFill()
                }
                // Nested in the story's card (X-4).
                .clipShape(Theme.Radius.innerShape)
                .accessibilityHidden(true)

            TeamTagChip(team: headline.team)

            Text(article.title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = article.articleDescription, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HomeNewsByline(article: article)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .contentShape(Theme.Radius.cardShape)
    }
}

/// A story after the first in Home's news feed, compact: a small
/// thumbnail beside the favorite's chip, the headline and the byline, on a
/// plain content card. At accessibility sizes the thumbnail goes above.
private struct HomeNewsRow: View {
    let headline: HomeHeadline

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 72

    private var stacksThumbnail: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = stacksThumbnail
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))

        layout {
            Color.clear
                .frame(width: stacksThumbnail ? nil : thumbnailSize, height: thumbnailSize)
                .frame(maxWidth: stacksThumbnail ? CGFloat.infinity : nil)
                .overlay {
                    RemoteImage(url: headline.article.urlToImage) {
                        RemoteImagePlaceholder()
                    }
                    .scaledToFill()
                }
                .clipShape(Theme.Radius.innerShape)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TeamTagChip(team: headline.team)
                Text(headline.article.title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(stacksThumbnail ? nil : 3)
                HomeNewsByline(article: headline.article)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .contentShape(Theme.Radius.cardShape)
    }
}

/// "ESPN · 2 hours ago": the outlet and the story's age.
private struct HomeNewsByline: View {
    let article: News

    var body: some View {
        Text("\(article.source) · \(article.publishedAt.formatted(.relative(presentation: .named)))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The favorite a story came from: its short name in the ink that reads
/// on its colour (G-3), on that colour. The name says it, not the colour
/// alone (G-4).
private struct TeamTagChip: View {
    let team: TeamRef

    var body: some View {
        Text(team.shortName)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(TeamColors.ink(on: team))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color(hexString: TeamColors.fillHex(for: team)), in: Theme.Radius.chip)
    }
}

/// A chip that narrows the news to one favorite, or "All": filled in the
/// team's colour with its ink when picked ("All" in the label colour),
/// plain otherwise, and 44 pt tall to tap (T-1). The picked chip says so
/// to VoiceOver, not by its fill alone (G-4).
private struct HomeNewsFilterChip: View {
    let title: String
    let team: TeamRef?
    let isSelected: Bool
    let action: @MainActor () -> Void

    private var fill: Color {
        guard isSelected else { return Theme.Surface.contentCard }
        guard let team else { return Color.primary }
        return Color(hexString: TeamColors.fillHex(for: team))
    }

    private var ink: Color {
        guard isSelected else { return Color.primary }
        guard let team else { return Theme.Surface.content }
        return TeamColors.ink(on: team)
    }

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ink)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(fill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("No teams") {
    HomeView(teams: [], addTeams: {}, showSettings: {})
}

#Preview("Bundled teams") {
    HomeView(
        teams: [
            TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")!,
            TeamCatalog.seeded(league: .nfl, espnID: "12")!,
        ],
        addTeams: {},
        showSettings: {}
    )
}
