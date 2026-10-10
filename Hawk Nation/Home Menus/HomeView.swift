//
//  HomeView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The Home tab, first in the bar and where the app opens (t_0b94af11):
/// every favorite at once. The page is the favorites' news, merged newest
/// first; above it, only when they have games, the games under way, the
/// next seven days' games and the last seven days' results (t_191edd79).
///
/// Reads what the app already loads (`HomeViewModel`): the scoreboards the
/// app polls for every favorite, the seasons it loaded to know which, and
/// each favorite's news feed. No page of its own to poll.
///
/// Glass is the chrome's alone (§5.2): the navigation bar with its gear,
/// and the tab bar. The sections and the feed's stories are content cards
/// on the grouped page, as a team page's are (B1).
struct HomeView: View {
    /// The favorites, resolved, in favorites order.
    let teams: [TeamRef]
    /// Opens the team browser, which `Home` presents.
    let addTeams: @MainActor () -> Void
    /// Opens Settings, which `Home` presents so that it outlives the tab.
    let showSettings: @MainActor () -> Void

    @State private var model = HomeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if teams.isEmpty {
                    HomeEmptyState(addTeams: addTeams)
                } else {
                    HomeSections(model: model)
                }
            }
            .background(Theme.Surface.content)
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
                        Label("Settings", systemImage: "gearshape")
                    }
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
                // Asset-catalog appearances pick the light/dark art;
                // the arches take the brand accent.
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
/// same game can be in Live Now and Upcoming, each its own source.
private struct HomeGameSelection: Identifiable {
    let entry: HomeGame
    let sourceID: String

    var id: String { sourceID }
}

/// Home's page (t_191edd79): the game sections that have games — Live Now,
/// Upcoming, Recent Results, each an inset card, none drawn when it has
/// nothing — over the news feed, every favorite's stories newest first, a
/// card each. All of it scrolls under the bars (T-4, T-5).
private struct HomeSections: View {
    let model: HomeViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Opens a team a story is about; absent in previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    @State private var selectedGame: HomeGameSelection?
    @State private var selectedArticle: HomeHeadline?

    /// Where a sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

    /// At accessibility text sizes the Live Now carousel becomes a vertical
    /// list, as a team page's carousels do (§5.3).
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let live = model.liveGames
        let upcoming = model.upcoming
        let results = model.results

        ScrollView(.vertical) {
            // Lazy, so the feed's rows are drawn as they scroll in. No glass
            // on any of it: it's scrolling content (§5.2).
            LazyVStack(spacing: Theme.Spacing.m) {
                // A game section takes no room without games: with none,
                // the page is the news feed.
                if !live.isEmpty {
                    liveSection(live)
                }
                if !upcoming.isEmpty {
                    upcomingSection(upcoming)
                }
                if !results.isEmpty {
                    resultsSection(results)
                }
                newsFeed
            }
            .padding(Theme.Spacing.m)
        }
        .scrollIndicators(.hidden)
        // Pull to refresh: the news, whatever its age, and any season that
        // failed (C-1).
        .refreshable { [model] in
            await model.refreshAll()
        }
        // The page scrolls under the tab bar, softened there (T-5, B5).
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .accessibilityIdentifier("home.page")
        .sheet(item: $selectedGame) { selection in
            GameDetailView(game: selection.entry.game, team: selection.entry.team)
                .zoomTransition(sourceID: selection.sourceID, in: cardZoom)
        }
        .sheet(item: $selectedArticle) { headline in
            NewsDetailView(article: headline.article, color: headline.team.color)
                .zoomTransition(sourceID: headline.id, in: cardZoom)
        }
    }

    // MARK: Live Now

    private func liveSection(_ live: [HomeLiveGame]) -> some View {
        section(systemImage: "dot.radiowaves.left.and.right", title: "Live Now", identifier: "home.section.live") {
            if usesStackedLayout {
                StackedCarousel(items: live) { game in
                    liveButton(game)
                }
            } else {
                ScrollView(.horizontal) {
                    // Lazy, as the team page's carousels are; no glass on
                    // the tiles: they're scrolling content (§5.2).
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(live) { game in
                            liveButton(game)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, Theme.Spacing.l)
                }
                .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    /// A live game's tile, opening the game's sheet once the favorite's
    /// schedule has it.
    @ViewBuilder
    private func liveButton(_ live: HomeLiveGame) -> some View {
        if let game = live.game {
            gameButton(HomeGame(team: live.team, game: game), source: "live", identifier: "home.live.\(live.id)") {
                HomeLiveTile(live: live)
            }
            .accessibilityLabel(live.accessibilityLabel)
        } else {
            HomeLiveTile(live: live)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(live.accessibilityLabel)
                .accessibilityIdentifier("home.live.\(live.id)")
        }
    }

    // MARK: Upcoming

    /// The next seven days' games, under a header for each day.
    private func upcomingSection(_ days: [HomeDay]) -> some View {
        section(systemImage: "calendar", title: "Upcoming", identifier: "home.section.upcoming") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(dayTitle(day.date))
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home.upcoming.date")

                        ForEach(day.games) { entry in
                            gameRow(entry, source: "upcoming", identifier: "home.upcoming.\(entry.id)")
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    /// "Today · Tue, Oct 6", "Tomorrow · Wed, Oct 7", then "Thu, Oct 8".
    private func dayTitle(_ day: Date) -> String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(day, inSameDayAs: model.now) {
            return "Today · \(date)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: model.now),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow · \(date)"
        }
        return date
    }

    // MARK: Recent Results

    /// The last seven days' results, newest first.
    private func resultsSection(_ results: [HomeGame]) -> some View {
        section(systemImage: "flag.checkered", title: "Recent Results", identifier: "home.section.results") {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(results) { entry in
                    gameRow(entry, source: "result", identifier: "home.result.\(entry.id)", tintsOutcome: true)
                }
            }
            .padding([.horizontal, .bottom])
        }
    }

    // MARK: News

    /// The page's bottom layer: its header, then a card for each of the
    /// favorites' stories, newest first, uncapped. Children of the page's
    /// lazy stack, so a long feed costs only the rows on screen.
    @ViewBuilder
    private var newsFeed: some View {
        SectionHeader(systemImage: "newspaper", title: "News")
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("home.section.news")

        let headlines = model.headlines
        if headlines.isEmpty {
            newsStatus
        } else {
            ForEach(headlines) { headline in
                Button {
                    selectedArticle = headline
                } label: {
                    HomeNewsRow(headline: headline)
                }
                .buttonStyle(.plain)
                .zoomSource(id: headline.id, in: cardZoom)
                .accessibilityIdentifier("home.news.row")
                // The teams it's about, a long press away, as on a team
                // page's news (t_8d15e070).
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
        let content = content()
        return VStack(alignment: .leading) {
            SectionHeader(systemImage: systemImage, title: title)
                .padding([.leading, .top, .trailing])
                .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// A game's row in Upcoming or Recent Results, opening its sheet.
    private func gameRow(_ entry: HomeGame, source: String, identifier: String, tintsOutcome: Bool = false) -> some View {
        let liveScore = model.liveScore(for: entry.game, team: entry.team)
        return gameButton(entry, source: source, identifier: identifier) {
            HomeGameRow(entry: entry, liveScore: liveScore, now: model.now, tintsOutcome: tintsOutcome)
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

    /// A card or row as a button that opens its game's sheet (T-3). No
    /// glass: it's content (§5.2).
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

// MARK: - Live tile

extension HomeLiveGame {
    /// "Rams 14, Broncos 21, 4th Quarter · 0:48": away first, as the tile
    /// and the matchup read.
    var accessibilityLabel: String {
        "\(info.awayName) \(state.awayScore), \(info.homeName) \(state.homeScore), \(state.stage)"
    }
}

/// A live game's tile in Live Now, in the schedule card's and the Live
/// Activity's language: the favorite's colour behind it in the ink that
/// reads on it (G-3), a "Live" pill, the stage, then away over home as the
/// matchup reads, each with its crest and score.
///
/// Fixed width in the carousel, scaled with its text (`@ScaledMetric`); at
/// accessibility sizes, where Live Now is a vertical list, it spans the
/// list's width and grows to fit instead (§5.3).
private struct HomeLiveTile: View {
    let live: HomeLiveGame

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var tileWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .subheadline) private var crestSize: CGFloat = 28
    @ScaledMetric(relativeTo: .caption2) private var liveDotSize: CGFloat = 6

    private var team: TeamRef { live.team }

    /// The favorite's colour, or the fallback its badge takes when the feed
    /// has none, so the ink is picked against what's drawn.
    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                LivePill(dotSize: liveDotSize)
                Spacer(minLength: 0)
                Text(live.state.stage)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(fillsRow ? nil : 1)
                    .minimumScaleFactor(0.8)
            }

            side(name: live.info.awayName, score: live.state.awayScore, isFavorite: !live.favoriteIsHome)
            side(name: live.info.homeName, score: live.state.homeScore, isFavorite: live.favoriteIsHome)
        }
        .foregroundStyle(TeamColors.ink(on: team))
        .padding(Theme.Spacing.m)
        .frame(width: fillsRow ? nil : tileWidth, alignment: .leading)
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil, alignment: .leading)
        .background { wash }
        // Nested in the section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
        .contentShape(Theme.Radius.innerShape)
    }

    /// One side: its crest, its name, and its score rolling as it changes
    /// (G-5). The favorite's name in bold.
    private func side(name: String, score: Int, isFavorite: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            crest(isFavorite: isFavorite)
                .frame(width: crestSize, height: crestSize)
                .accessibilityHidden(true)

            Text(name)
                .font(.subheadline.weight(isFavorite ? .bold : .medium))
                .lineLimit(fillsRow ? nil : 1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: Theme.Spacing.s)

            Text("\(score)")
                .font(Theme.Typography.statFigure)
                .lineLimit(1)
                .scoreTransition(value: Double(score))
        }
    }

    /// The favorite's crest, or the opponent's from the schedule, as a
    /// schedule card draws it.
    @ViewBuilder
    private func crest(isFavorite: Bool) -> some View {
        if isFavorite {
            TeamLogo(team: team, size: crestSize, forceVariant: .default)
        } else if let logo = live.game?.opponentLogo, !logo.isEmpty {
            RemoteImage(url: URL(string: logo)) {
                Image("blankTeam")
                    .resizable()
            }
            .aspectRatio(contentMode: .fit)
        } else {
            Image("blankTeam")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    /// The team's colour with its crest faint in the corner, as a schedule
    /// card's header has it.
    private var wash: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(teamColor)

            TeamLogo(team: team, size: 160, forceVariant: .default)
                .opacity(0.1)
                .saturation(0.1)
                .contrast(0.5)
                .offset(x: 70, y: 30)
        }
    }
}

/// "Live" beside a red dot, in primary text on the inset surface so it
/// reads the same over every team's colour, as a schedule card's status
/// pill does. The word says it too: never colour alone (G-4).
private struct LivePill: View {
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(.red)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
            Text("Live")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Surface.insetCard, in: Theme.Radius.chip)
    }
}

// MARK: - News row

/// A story in Home's news feed: the favorite it came from as a chip, over
/// the team page's news row (`NewsView`) with its thumbnail, on a plain
/// content card. No glass: the feed scrolls (§5.2).
private struct HomeNewsRow: View {
    let headline: HomeHeadline

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TeamTagChip(team: headline.team)
            NewsView(article: headline.article)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .contentShape(Theme.Radius.cardShape)
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

// MARK: - Game row

/// A favorite's game in Upcoming or Recent Results: its crest, the matchup and what
/// the schedule card would say of it — the start, the live score and
/// stage, or the result. A result is tinted by its outcome, with the
/// outcome's word beside the score so it never rests on colour (G-4).
private struct HomeGameRow: View {
    let entry: HomeGame
    let liveScore: LiveGameScore?
    let now: Date
    var tintsOutcome = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 32

    private var game: Game { entry.game }

    var body: some View {
        let content = GameCardContent(game: game, league: entry.team.league, liveScore: liveScore, now: now)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))

        layout {
            HStack(spacing: Theme.Spacing.m) {
                TeamLogo(team: entry.team, size: crestSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(matchup(content))
                        .font(Theme.Typography.cardTitle)
                        .lineLimit(2)
                    if let competition = GameCardContent.competitionLabel(of: game, league: entry.team.league) {
                        Text(competition)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            trailing(content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s)
        .background(outcomeTint(content).opacity(Theme.selectionWashOpacity(contrast: contrast)), in: Theme.Radius.innerShape)
        .contentShape(Theme.Radius.innerShape)
    }

    /// "Chiefs vs Raiders", "Chiefs at Raiders".
    private func matchup(_ content: GameCardContent) -> String {
        let side = game.gameHome || game.neutralSite ? "vs" : "at"
        return "\(entry.team.shortName) \(side) \(content.opponent)"
    }

    /// The start, the live score and stage, or the outcome and score.
    @ViewBuilder
    private func trailing(_ content: GameCardContent) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            switch content.phase {
            case .final:
                if let finalScore = content.finalScore {
                    Text(finalScore)
                        .font(.headline.weight(.heavy).monospacedDigit())
                }
                if let outcome = content.outcomeLabel {
                    Text(outcome)
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(tintsOutcome ? outcomeTint(content) : Color.secondary)
                } else {
                    Text(content.status)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            case .live:
                if let liveScore {
                    Text("\(liveScore.score) – \(liveScore.opponentScore)")
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .scoreTransition(value: Double(liveScore.score + liveScore.opponentScore))
                }
                Text(content.liveStage ?? content.status)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            case .upcoming:
                Text(game.date.isEmpty ? content.status : GameCardContent.timeLabel(of: game.dateAsDate))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let broadcast = GameCardContent.broadcast(of: game) {
                    Text(broadcast)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .cancelled, .postponed:
                Text(content.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The wash behind a result: green for a win, red for a loss, none for
    /// a draw or anything not a result.
    private func outcomeTint(_ content: GameCardContent) -> Color {
        guard tintsOutcome else { return .clear }
        switch content.outcome {
        case .win: return .green
        case .loss: return .red
        case .draw, nil: return .clear
        }
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
