//
//  HomeView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The Home tab, first in the bar and where the app opens (t_0b94af11):
/// every favorite at once, in four sections — the games under way, today's
/// games (tomorrow's on a day without any), the last two days' results,
/// and the newest headlines.
///
/// Reads what the app already loads (`HomeViewModel`): the scoreboards the
/// app polls for every favorite, the seasons it loaded to know which, and
/// each favorite's news feed. No page of its own to poll.
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
                // Asset-catalog appearances pick the light/dark art.
                Image("myTeamsLogo")
                    .resizable()
                    .scaledToFit()
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
/// same game can be in Live Now and Today, each its own source.
private struct HomeGameSelection: Identifiable {
    let entry: HomeGame
    let sourceID: String

    var id: String { sourceID }
}

/// Home's four sections, each an inset card on the grouped page that
/// scrolls under the bars (T-4, T-5).
private struct HomeSections: View {
    let model: HomeViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedGame: HomeGameSelection?
    @State private var selectedArticle: HomeHeadline?

    /// Where a sheet zooms from: its card (X-13).
    @Namespace private var cardZoom

    /// At accessibility text sizes the Live Now carousel becomes a vertical
    /// list, as a team page's carousels do (§5.3).
    private var usesStackedLayout: Bool { dynamicTypeSize.isAccessibilitySize }

    /// What a failed section retries.
    private enum Retry {
        case schedules
        case news
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: Theme.Spacing.m) {
                liveSection
                todaySection
                resultsSection
                headlinesSection
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

    private var liveSection: some View {
        let live = model.liveGames
        return section(systemImage: "dot.radiowaves.left.and.right", title: "Live Now", identifier: "home.section.live") {
            if live.isEmpty {
                status(
                    model.liveState,
                    empty: "No games live right now.",
                    failed: "Couldn't load your teams' games",
                    retry: .schedules
                )
            } else if usesStackedLayout {
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

    // MARK: Today

    private var todaySection: some View {
        section(systemImage: "calendar", title: "Today", identifier: "home.section.today") {
            if let day = model.today {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(dayTitle(day))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home.today.date")

                    ForEach(day.games) { entry in
                        gameRow(entry, source: "today", identifier: "home.today.\(entry.id)")
                    }
                }
                .padding([.horizontal, .bottom])
            } else {
                status(
                    model.scheduleState,
                    empty: "No games today.",
                    failed: "Couldn't load your teams' schedules",
                    retry: .schedules
                )
            }
        }
    }

    /// "Today · Tue, Oct 6", or "Tomorrow · Wed, Oct 7".
    private func dayTitle(_ day: HomeDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day.isToday ? "Today" : "Tomorrow") · \(date)"
    }

    // MARK: Results

    private var resultsSection: some View {
        let results = model.results
        return section(systemImage: "flag.checkered", title: "Results", identifier: "home.section.results") {
            if results.isEmpty {
                status(
                    model.scheduleState,
                    empty: "No results in the last two days.",
                    failed: "Couldn't load your teams' schedules",
                    retry: .schedules
                )
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(results) { entry in
                        gameRow(entry, source: "result", identifier: "home.result.\(entry.id)", tintsOutcome: true)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: Headlines

    private var headlinesSection: some View {
        let headlines = model.headlines
        return section(systemImage: "newspaper", title: "Headlines", identifier: "home.section.headlines") {
            if headlines.isEmpty {
                switch model.headlinesState {
                case .loading:
                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(0..<3, id: \.self) { _ in
                            LoadingNewsView()
                        }
                    }
                    .padding([.horizontal, .bottom])
                case .loaded, .failed:
                    status(
                        model.headlinesState,
                        empty: "No news right now.",
                        failed: "Couldn't load the news",
                        retry: .news
                    )
                }
            } else {
                VStack(spacing: Theme.Spacing.m) {
                    ForEach(headlines) { headline in
                        Button {
                            selectedArticle = headline
                        } label: {
                            NewsView(article: headline.article)
                        }
                        .buttonStyle(.plain)
                        .zoomSource(id: headline.id, in: cardZoom)
                        .accessibilityIdentifier("home.headline")
                    }
                }
                .padding([.horizontal, .bottom])
            }
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

    /// What an empty section says, as a team page's sections do (P1's
    /// `SectionLoadState`): a spinner while its feeds load, one line once
    /// they have answered with nothing, or an error with a retry.
    @ViewBuilder
    private func status(_ state: SectionLoadState, empty: String, failed: String, retry: Retry) -> some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        case .loaded:
            SectionStatusView(message: empty)
                .frame(maxWidth: .infinity)
        case .failed:
            SectionStatusView(message: failed) {
                Task { [model] in
                    switch retry {
                    case .schedules: await model.reloadSchedules()
                    case .news: await model.reloadNews()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A game's row in Today or Results, opening its sheet.
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

// MARK: - Game row

/// A favorite's game in Today or Results: its crest, the matchup and what
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
            TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305"),
            TeamCatalog.seeded(league: .nfl, espnID: "12"),
        ],
        addTeams: {},
        showSettings: {}
    )
}
