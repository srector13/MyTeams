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
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // The title with today's date under it, as Leaders puts
                // its season there, both in the bar's ink over the hero
                // colour (H1, F2): the system subtitle took a translucent
                // grey that turned pink on a red team, at 1.5:1.
                ToolbarItem(placement: .principal) {
                    HomeBarTitle(date: model.now, ink: barInk)
                }
                // A title, not a button: no glass behind it.
                .sharedBackgroundVisibility(.hidden)

                // The way to Settings and its alerts from where the app
                // opens, as a team page has it (A-5).
                ToolbarItem(placement: .topBarTrailing) {
                    HomeSettingsButton(ink: barInk, action: showSettings)
                }
                // Over the hero colour the button draws its own circle in
                // the ink, so the system glass can't wash the gear into
                // the team colour; on the plain bar, the standard glass.
                .sharedBackgroundVisibility(barInk == nil ? .automatic : .hidden)
            }
        }
        // Mounted only while Home's tab is on screen, so it refreshes only
        // then; a change of favorites starts it over.
        .task(id: teams.map(\.id)) { await model.run(teams: teams) }
    }
}

/// Home's title in the bar, today's date beneath it: in the bar's ink over
/// the hero colour (H1), or the label and metadata colours on the plain
/// bar of the empty state. One element to VoiceOver.
private struct HomeBarTitle: View {
    let date: Date
    /// White or black for the hero colour (`HomeHeroStyle.barInk`); `nil`
    /// on the plain bar.
    let ink: Color?

    var body: some View {
        VStack(spacing: 1) {
            Text("Home")
                .font(.headline)
                .foregroundStyle(ink ?? Color.primary)
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.footnote.weight(.medium))
                .foregroundStyle(ink.map { AnyShapeStyle($0.opacity(0.92)) } ?? AnyShapeStyle(Theme.Palette.metadata))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The gear to Settings. Over the hero colour: the gear in the bar's ink
/// on a faint circle of it, ringed in it, 44 pt across (H1, T-1), never
/// the theme's accent. On the plain bar: the standard bar button.
private struct HomeSettingsButton: View {
    let ink: Color?
    let action: @MainActor () -> Void

    var body: some View {
        if let ink {
            Button {
                action()
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(ink.opacity(0.16), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(ink.opacity(0.35), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        } else {
            Button {
                action()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        }
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
/// iPad) two balanced ones, My Teams and This Week on the left, Standings
/// and Top Performers on the right, each in the reader's order, with the
/// news full width beneath them (H10), centred no wider than
/// `regularMaxWidth`.
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
    /// Whether the news section runs on past its few fresh stories
    /// (`HomeFeed.homeNews`) into the rest: "More News".
    @State private var showsAllNews = false

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
    /// column or, on an iPad, two balanced ones — the teams and their week
    /// on the left, the tables on the right — with the news full width
    /// beneath both (H10); then More News and Customize Home.
    private func page(_ layout: HomeSectionLayout) -> some View {
        let visible = layout.visible
        let leading = visible.filter { $0.regularColumn == .leading }
        let trailing = visible.filter { $0.regularColumn == .trailing }
        let below = visible.filter { $0.regularColumn == .fullWidth }
        return VStack(spacing: Theme.Spacing.m) {
            if isRegular && !leading.isEmpty && !trailing.isEmpty {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    // Each column at its own height: offered the taller
                    // one's, a horizontal carousel stretched to fill it.
                    column(leading)
                        .fixedSize(horizontal: false, vertical: true)
                    column(trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !below.isEmpty {
                    column(below)
                }
            } else {
                column(visible)
            }

            footButtons(showsNews: visible.contains(.news))
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

    /// The page's foot: "More News (N)" while the news holds stories back,
    /// and "Customize Home", in one button style (H6). Stacked on an
    /// iPhone, side by side on an iPad.
    private func footButtons(showsNews: Bool) -> some View {
        let news = newsSelection
        let showsMore = showsNews && !news.selection.more.isEmpty
        let layout = isRegular && !usesStackedLayout
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
        return layout {
            if showsMore {
                Button {
                    withAnimation(Theme.Motion.animation(Theme.Motion.stateChange, reduceMotion: settings.reduceMotion)) {
                        showsAllNews.toggle()
                    }
                } label: {
                    Text(showsAllNews ? "Show Fewer Stories" : "More News (\(news.selection.more.count))")
                }
                .buttonStyle(HomeFootButtonStyle())
                .frame(maxWidth: isRegular ? Self.footButtonWidth : nil)
                .accessibilityIdentifier("home.news.more")
            }

            Button {
                showsCustomize = true
            } label: {
                Text("Customize Home")
            }
            .buttonStyle(HomeFootButtonStyle())
            .frame(maxWidth: isRegular ? Self.footButtonWidth : nil)
            .accessibilityHint("Show, hide and reorder Home's sections.")
            .accessibilityIdentifier("home.customize")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xs)
    }

    /// The width of each foot button side by side on an iPad.
    private static let footButtonWidth: CGFloat = 300

    // MARK: My Teams

    /// A card per favorite (`HomeTeamCard`), opening its tab: a carousel
    /// with the next card peeking and page dots on an iPhone (H2), two
    /// columns with nothing to scroll on an iPad (H10).
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
            } else if isRegular {
                cardGrid(summaries) { summary in
                    teamButton(summary)
                }
            } else {
                HomeCarousel(items: summaries, share: Self.wideCardShare) { summary in
                    teamButton(summary)
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
    /// `HomeFeed.weekDaysAhead` on, and the picked day's games as cards
    /// that say whose game each is (H3); one line when the week has none.
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

    /// The picked day's games as Home's game cards (`GameView` in its
    /// `.home` style), each opening its sheet and as tall as its content:
    /// a carousel with the next card peeking on an iPhone, two columns on
    /// an iPad; placeholders while the seasons load; one line on a quiet
    /// day.
    @ViewBuilder
    private func dayGames(_ day: HomeWeekDay?) -> some View {
        if let day, !day.games.isEmpty {
            if usesStackedLayout {
                StackedCarousel(items: day.games) { entry in
                    weekGameButton(entry)
                }
            } else if isRegular {
                cardGrid(day.games, matchesHeights: false) { entry in
                    weekGameButton(entry)
                }
            } else {
                HomeCarousel(items: day.games, share: Self.wideCardShare, matchesHeights: false, showsDots: false) { entry in
                    weekGameButton(entry)
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

    /// A game's card, under the identifier of what it is: a result
    /// (`home.result.<id>`), a game under way (`home.live.<id>`), or one to
    /// come (`home.upcoming.<id>`).
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
            GameView(game: entry.game, team: entry.team, liveScore: liveScore, style: .home)
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
    /// tab: a carousel with the next card peeking and page dots on an
    /// iPhone (H4), stacked in the column on an iPad; skeletons while the
    /// tables load; nothing once they have, if no table holds a favorite.
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
                } else if isRegular {
                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(slices) { slice in
                            standingsButton(slice)
                        }
                    }
                    .padding([.horizontal, .bottom])
                } else {
                    HomeCarousel(items: slices, share: Self.wideCardShare) { slice in
                        standingsButton(slice)
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
    /// leader cards do: a carousel with page dots on an iPhone (H4), a
    /// grid on an iPad; skeletons while the leaders load.
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
                } else if isRegular {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Self.performerGridMinimum), spacing: Theme.Spacing.m, alignment: .top)],
                        spacing: Theme.Spacing.m
                    ) {
                        ForEach(performers) { performer in
                            performerButton(performer)
                        }
                    }
                    .padding([.horizontal, .bottom])
                } else {
                    // The leader cards keep their own width; the row
                    // still shows a sliver of the next.
                    HomeCarousel(items: performers, share: nil) { performer in
                        performerButton(performer)
                    }
                }
            }
        }
    }

    /// The narrowest a performer's column runs in the iPad's grid: a
    /// leader card's width.
    private static let performerGridMinimum: CGFloat = 120

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

    /// The news as the section draws it: the filter's team, if one is
    /// picked, and the stories shown and held back (`HomeFeed.homeNews`).
    private var newsSelection: (filterTeam: TeamRef?, feed: [HomeHeadline], selection: HomeNewsSelection) {
        let all = model.headlines
        let filterTeam = newsFilter.flatMap { id in model.teams.first { $0.id == id } }
        let feed = filterTeam.map { HomeFeed.headlines(all, about: $0) } ?? all
        return (filterTeam: filterTeam, feed: feed, selection: HomeFeed.homeNews(feed, now: model.now))
    }

    /// The favorites' news in a section card like the others (H5): with
    /// more than one favorite, a chip for each to narrow it, the row
    /// running to the card's edge; then up to five stories from the last
    /// three days, dealt in turn across the favorites, the first large.
    /// The rest wait behind More News at the page's foot, and show here
    /// once it's tapped.
    private var newsSection: some View {
        let news = newsSelection
        let shown = news.selection.shown
        return section(systemImage: HomeSectionKind.news.systemImage, title: "News", identifier: "home.section.news") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if model.teams.count > 1 && !model.headlines.isEmpty {
                    newsFilters(selected: news.filterTeam)
                }

                if !news.feed.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, headline in
                            if index > 0 {
                                Divider()
                            }
                            newsButton(headline) {
                                if index == 0 {
                                    HomeNewsLeadCard(headline: headline)
                                } else {
                                    HomeNewsRow(headline: headline)
                                }
                            }
                        }

                        if showsAllNews {
                            LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                                ForEach(news.selection.more) { headline in
                                    Divider()
                                    newsButton(headline) {
                                        HomeNewsRow(headline: headline)
                                    }
                                }
                            }
                        } else if news.selection.holdsOlderStories {
                            Text(shown.isEmpty
                                ? "Nothing new in the last three days. Older stories are in More News."
                                : "Older stories are in More News.")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Palette.metadata)
                                .accessibilityIdentifier("home.news.older")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } else if let filterTeam = news.filterTeam {
                    compactLine("No stories about the \(filterTeam.shortName) right now.", identifier: "home.news.filterEmpty")
                } else {
                    newsStatus
                }
            }
        }
    }

    /// "All", then a chip per favorite, the picked one filled: in line with
    /// the stories, scrolling to the card's edge (H5).
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
        .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
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
            VStack(spacing: Theme.Spacing.m) {
                ForEach(0..<3, id: \.self) { _ in
                    LoadingNewsView()
                }
            }
            .padding([.horizontal, .bottom])
        case .loaded:
            SectionStatusView(message: "No news right now.")
                .frame(maxWidth: .infinity)
        case .failed:
            SectionStatusView(message: "Couldn't load the news") {
                Task { [model] in
                    await model.reloadNews()
                }
            }
            .frame(maxWidth: .infinity)
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

    /// The share of a carousel's width a wide card takes on an iPhone:
    /// four fifths, so the next card's edge shows beside it (F7).
    private static let wideCardShare = HomeCarouselShare(count: 5, span: 4)

    /// Cards in two columns, nothing to scroll sideways (H10): an iPad's
    /// My Teams and This Week. With `matchesHeights`, each card fills its
    /// row's height, so the feet of a row's team cards line up.
    private func cardGrid<Item: Identifiable, Card: View>(
        _ items: [Item],
        matchesHeights: Bool = true,
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.m) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(items[start..<min(start + 2, items.count)]) { item in
                        card(item)
                            .frame(maxHeight: matchesHeights ? CGFloat.infinity : nil, alignment: .top)
                    }
                    if start + 1 >= items.count {
                        // An odd card out keeps its column's width.
                        Color.clear
                            .gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
        .padding([.horizontal, .bottom])
    }

    /// A row of placeholders, side by side and inset in line with the
    /// header, while a section loads.
    private func carousel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let content = content()
        return ScrollView(.horizontal) {
            content
                .padding(.bottom, Theme.Spacing.l)
        }
        .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    /// One line of metadata text in a section with nothing to show.
    private func compactLine(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.metadata)
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

// MARK: - Carousel

/// How much of a carousel's width each card takes, as
/// `containerRelativeFrame`'s `count` and `span`: `span` of `count` equal
/// columns.
private struct HomeCarouselShare {
    let count: Int
    let span: Int
}

/// A section's cards side by side, scrolling sideways, as a team page's
/// carousels do: inset in line with the header, coming to rest on a
/// card's leading edge (T-4, T-8), the next card always peeking in (F7),
/// and page dots beneath that follow the scroll (H4). No glass: it's
/// content (§5.2).
private struct HomeCarousel<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Each card's share of the row's width; `nil` keeps each card's own.
    let share: HomeCarouselShare?
    /// Whether every card is drawn as tall as the tallest, so the feet of
    /// a row of cards line up; otherwise each is as tall as its content.
    var matchesHeights = true
    var showsDots = true
    @ViewBuilder let card: (Item) -> Card

    /// The card at the row's leading edge.
    @State private var position: Item.ID?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(items) { item in
                        sized(card(item))
                    }
                }
                // Each card at the row's height when they match (their
                // stretch fills it), else at its own.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $position, anchor: .leading)

            if showsDots && items.count > 1 {
                HomePageDots(count: items.count, current: currentIndex)
            }
        }
        .padding(.bottom, Theme.Spacing.l)
    }

    @ViewBuilder
    private func sized(_ card: Card) -> some View {
        let stretched = card
            .frame(maxHeight: matchesHeights ? CGFloat.infinity : nil, alignment: .top)
        if let share {
            stretched
                .containerRelativeFrame(.horizontal, count: share.count, span: share.span, spacing: Theme.Spacing.m)
        } else {
            stretched
        }
    }

    private var currentIndex: Int {
        guard let position, let index = items.firstIndex(where: { $0.id == position }) else { return 0 }
        return index
    }
}

/// A carousel's page dots: one per card, the one at the row's leading
/// edge dark. Decoration: VoiceOver reads the cards themselves.
private struct HomePageDots: View {
    let count: Int
    let current: Int

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 7

    var body: some View {
        HStack(spacing: size - 1) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
                    .frame(width: size, height: size)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// The page's foot buttons, More News and Customize Home, in one style
/// (H6): full width (300 pt side by side on an iPad), semibold text in
/// the app's tint on a capsule of the section cards' surface, at least
/// 50 pt tall.
private struct HomeFootButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.Surface.contentCard, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
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

/// The news section's first story, large: its picture across the section,
/// the favorite it came from as a chip, the headline, the summary, and the
/// outlet and age. On the section's card itself (H5). No glass: the page
/// scrolls (§5.2).
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
                    .foregroundStyle(Theme.Palette.metadata)
                    .lineLimit(3)
            }

            HomeNewsByline(article: article)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// A story after the first in Home's news section, compact: a small
/// thumbnail beside the favorite's chip, the headline and the byline, on
/// the section's card between dividers. At accessibility sizes the
/// thumbnail goes above.
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// "ESPN · 2 hours ago": the outlet and the story's age.
private struct HomeNewsByline: View {
    let article: News

    var body: some View {
        Text("\(article.source) · \(article.publishedAt.formatted(.relative(presentation: .named)))")
            .font(.caption)
            .foregroundStyle(Theme.Palette.metadata)
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
