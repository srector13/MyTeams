//
//  OnboardingWalkthroughView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The first-launch walkthrough: a few pages that show what the app does,
/// before the theme step (`ThemeOnboarding`) and, for a reader who follows
/// no team yet, the teams step (`OnboardingTeamsStep`) that end the flow.
///
/// It has no flag of its own. It is offered whenever the theme step is
/// (`ThemeOnboarding.isPending`), so an install that predates the flow, or
/// has finished it, sees neither.
enum OnboardingWalkthrough {
    /// A page of the walkthrough, in order. The game page leads: it shows
    /// Home's Next Up hero as the reader will see it (O1).
    enum Page: Int, CaseIterable, Identifiable, Sendable {
        case schedule
        case roster
        case stats

        var id: Self { self }

        /// One-based, as the page indicator counts.
        var number: Int { rawValue + 1 }

        var headline: String {
            switch self {
            case .schedule: "Never Miss a Game"
            case .roster: "Know Your Roster"
            case .stats: "Follow the Numbers"
            }
        }

        var caption: String {
            switch self {
            case .schedule: "A countdown to your team's next game, live scores while it's on, and the final when it ends."
            case .roster: "Browse every player on your team, with numbers and positions."
            case .stats: "Player and team stats, from leaders to box scores."
            }
        }

        var accessibilityIdentifier: String { "onboarding.walkthrough.page.\(number)" }

        /// The page after this one; `nil` on the last.
        var next: Page? { Page(rawValue: rawValue + 1) }

        var isLast: Bool { next == nil }

        /// The button below the page: Next, or Get Started on the last
        /// page, which hands off to the theme step.
        var buttonTitle: String { isLast ? "Get Started" : "Next" }

        var buttonIdentifier: String {
            isLast ? "onboarding.walkthrough.getStarted" : "onboarding.walkthrough.next"
        }
    }

    /// Where the flow is: a walkthrough page, the theme step after them,
    /// or the teams step after that.
    enum Step: Hashable, Sendable {
        case walkthrough(Page)
        case theme
        case teams

        /// Where the flow opens.
        static let first = Step.walkthrough(.schedule)

        /// The page shown, or `nil` on the theme and teams steps.
        var page: Page? {
            if case .walkthrough(let page) = self { page } else { nil }
        }

        /// After Next or Get Started: the next page, or the theme step
        /// after the last; after the theme step, the teams step, which the
        /// flow offers only to a reader following no team
        /// (`needsTeamsStep(followedCount:)`). The teams step finishes the
        /// flow itself.
        var advanced: Step {
            switch self {
            case .walkthrough(let page): page.next.map(Step.walkthrough) ?? .theme
            case .theme, .teams: .teams
            }
        }

        /// After Skip: from the pages, straight to the theme step, which
        /// can be skipped in its turn, on to the teams step.
        var skipped: Step {
            switch self {
            case .walkthrough: .theme
            case .theme, .teams: .teams
            }
        }
    }

    /// Whether the flow goes on to the teams step after the theme step:
    /// only with no team followed. Favorites restored from iCloud, or set
    /// by a UI test's launch (`FavoritesStore.launchFavoritesKey`), end the
    /// flow at the theme step, as before the teams step existed.
    static func needsTeamsStep(followedCount: Int) -> Bool {
        followedCount == 0
    }
}

/// Onboarding's last step, "Pick Your Teams" (O5): the team picker
/// (`TeamBrowserView`, given its `onboarding`), whose Done stays disabled
/// until a team is picked. What the step says, and that rule.
enum OnboardingTeamsStep {
    static let title = "Pick Your Teams"
    static let caption = "Choose at least one. Each gets its own tab with its schedule, roster, standings and news."
    /// Under Done while it's disabled.
    static let disabledNote = "Done stays greyed out until you pick a team."

    /// Whether Done can finish onboarding: one team picked at least.
    static func canFinish(pickedCount: Int) -> Bool {
        pickedCount >= 1
    }

    /// "Done", then "Done · 1 team", "Done · 2 teams" as teams are picked.
    static func doneTitle(pickedCount: Int) -> String {
        switch pickedCount {
        case ..<1: "Done"
        case 1: "Done · 1 team"
        default: "Done · \(pickedCount) teams"
        }
    }
}

/// The first-launch sheet: the walkthrough's pages, then the theme step
/// (`ThemeOnboardingView`), then, with no team followed yet, the teams
/// step (`TeamBrowserView` in onboarding), after which it marks the flow
/// complete and Home shows the picks. Not dismissable by a swipe, so
/// leaving is always through the last step.
///
/// Tinted in the theme as it's chosen, so its buttons and checks are never
/// the system's blue (O3).
struct OnboardingFlowView: View {
    /// Called once the flow is finished or skipped, after it is marked
    /// complete (`ThemeOnboarding.complete`).
    let onFinish: () -> Void

    @State private var step = OnboardingWalkthrough.Step.first
    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic
    private var settings = AdaptiveSettings()

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            switch step {
            case .walkthrough:
                OnboardingWalkthroughView(
                    page: Binding(
                        get: { step.page ?? .schedule },
                        set: { step = .walkthrough($0) }
                    ),
                    onNext: { move(to: step.advanced) },
                    onSkip: { move(to: step.skipped) }
                )
                .transition(transition)
            case .theme:
                ThemeOnboardingView(onFinish: { finishTheme() })
                    .transition(transition)
            case .teams:
                TeamBrowserView(onboarding: TeamBrowserView.OnboardingTeams(
                    onDone: { finish() },
                    onSkip: { finish() }
                ))
                .transition(transition)
            }
        }
        .interactiveDismissDisabled()
        .tint(theme.swatchColor)
        .environment(\.brandTheme, theme)
    }

    /// Each step slides in after the last, as one more page would; under
    /// Reduce Motion it just takes its place.
    private var transition: AnyTransition {
        settings.reduceMotion
            ? .identity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    private func move(to next: OnboardingWalkthrough.Step) {
        withAnimation(Theme.Motion.animation(Theme.Motion.stateChange, reduceMotion: settings.reduceMotion)) {
            step = next
        }
    }

    /// After the theme's Continue or Skip: the teams step for a reader
    /// following none, the end of the flow otherwise.
    private func finishTheme() {
        if OnboardingWalkthrough.needsTeamsStep(followedCount: FavoritesStore.shared.teamIDs.count) {
            move(to: .teams)
        } else {
            finish()
        }
    }

    /// Marks the flow complete for good, which closes the sheet.
    private func finish() {
        ThemeOnboarding.complete()
        onFinish()
    }
}

/// The walkthrough's pages: swiped through, or stepped with Next; Get
/// Started on the last, and Skip throughout, move on to the theme step.
struct OnboardingWalkthroughView: View {
    @Binding var page: OnboardingWalkthrough.Page
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(OnboardingWalkthrough.Page.allCases) { page in
                    WalkthroughPageView(page: page, isCurrent: page == self.page)
                        .tag(page)
                }
            }
            // The page dots are drawn below (`WalkthroughPageDots`): the
            // system's current dot vanished on the light page (O2).
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Theme.Surface.content)
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: Theme.Spacing.l) {
                    WalkthroughPageDots(current: page)

                    Button(action: onNext) {
                        Text(page.buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier(page.buttonIdentifier)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                        .accessibilityIdentifier("onboarding.walkthrough.skip")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The walkthrough's page indicator: the current page a dark capsule, the
/// others grey dots, legible on the light page and the dark alike (O2).
/// One element to VoiceOver, "Page 1 of 3"; the pages swipe as before.
private struct WalkthroughPageDots: View {
    let current: OnboardingWalkthrough.Page

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(OnboardingWalkthrough.Page.allCases) { page in
                Capsule()
                    .fill(page == current ? Color.primary : Color(uiColor: .systemGray2))
                    .frame(width: page == current ? 22 : 8, height: 8)
            }
        }
        .motionAnimation(Theme.Motion.stateChange, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current.number) of \(OnboardingWalkthrough.Page.allCases.count)")
    }
}

// MARK: - Page

/// One page: a sketch of the screen it's about over its headline and
/// caption. The sketch is decorative; the words say what it shows.
private struct WalkthroughPageView: View {
    let page: OnboardingWalkthrough.Page
    /// Whether the page is the one in view, which starts its sketch's
    /// motion.
    let isCurrent: Bool

    var body: some View {
        // Scrolls only when the text is too large to fit; otherwise the
        // sketch and words sit centred in the page rather than at its top.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    sketch
                        .frame(maxWidth: 380)
                        // A picture of the app: it keeps its proportions at
                        // the largest text sizes, where the words still grow.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityHidden(true)

                    VStack(spacing: Theme.Spacing.s) {
                        Text(page.headline)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(page.caption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(page.accessibilityIdentifier)
    }

    /// The game page's hero on its own team colour, as Home draws it; the
    /// others' sketches on a content card, as a team page's sections are.
    @ViewBuilder
    private var sketch: some View {
        switch page {
        case .schedule:
            NextUpSketch()
        case .roster:
            RosterSketch()
                .padding(Theme.Spacing.l)
                .contentCard()
        case .stats:
            StatsSketch(isCurrent: isCurrent)
                .padding(Theme.Spacing.l)
                .contentCard()
        }
    }
}

// MARK: - Sketches

/// The teams the sketches show: the app's own catalog (`TeamCatalog`), so
/// their crests draw from the bundle, offline, as the reader's will.
private enum SketchTeams {
    /// The Next Up hero's team.
    static let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")
    /// The roster's and stats' team.
    static let jayhawks = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")
    /// The hero's opponent, as ESPN lists it: its crest loads, and is
    /// kept, as any opponent's does (`TeamLogo`).
    static let chargers = TeamRef(
        league: .nfl,
        espnID: "24",
        displayName: "Los Angeles Chargers",
        shortName: "Chargers",
        abbreviation: "LAC",
        location: "Los Angeles",
        colorHex: "0080C6",
        alternateColorHex: "FFC20E",
        logoURL: URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500/lac.png"),
        logoDarkURL: nil,
        logoAsset: nil
    )
}

/// Home's Next Up hero as it looks (O1): the team's colour, both crests cut
/// out on it (`CutoutCrest`), the countdown between them, the start and
/// channel beneath. Every word in the colour's ink, never the accent (F2).
private struct NextUpSketch: View {
    private struct Unit: Identifiable, Sendable {
        let value: String
        let label: String
        var id: String { label }
    }

    private static let countdown = [
        Unit(value: "2", label: "DAYS"),
        Unit(value: "4", label: "HRS"),
        Unit(value: "18", label: "MIN"),
    ]

    @ScaledMetric(relativeTo: .title3) private var crestSize: CGFloat = 52

    var body: some View {
        if let team = SketchTeams.chiefs {
            let fillHex = TeamColors.fillHex(for: team)
            VStack(spacing: Theme.Spacing.m) {
                Text("Next up")
                    .textCase(.uppercase)
                    .font(.caption.weight(.heavy))

                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    side(team, onHex: fillHex, isFavorite: true)
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(Self.countdown) { unit in
                            VStack(spacing: 0) {
                                Text(unit.value)
                                    .font(.title2.weight(.heavy).monospacedDigit())
                                Text(unit.label)
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                    .lineLimit(1)
                    .layoutPriority(1)
                    side(SketchTeams.chargers, onHex: fillHex, isFavorite: false)
                }

                Text("Sun · 8:25 PM · CBS")
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(TeamColors.ink(on: team))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.l)
            .padding(.horizontal, Theme.Spacing.m)
            .background(team.color, in: Theme.Radius.cardShape)
        }
    }

    private func side(_ team: TeamRef, onHex: String, isFavorite: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            CutoutCrest(team: team, size: crestSize, onHex: onHex)
            Text(team.shortName)
                .font(.subheadline.weight(isFavorite ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A sketch's heading, as a section's on a team's page: the team's crest,
/// where it has one, or the section's symbol.
private struct SketchHeader: View {
    let title: String
    let systemImage: String
    var team: TeamRef?

    @Environment(\.brandTheme) private var brandTheme
    @ScaledMetric(relativeTo: .title3) private var crestSize: CGFloat = 24

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let team {
                TeamLogo(team: team, size: crestSize)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(brandTheme.accentColor)
            }
            Text(title)
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.sectionTitle)
    }
}

/// The roster: a few player rows under the team's crest, number badge,
/// name and position.
private struct RosterSketch: View {
    private struct Player: Identifiable {
        let number: String
        let name: String
        let position: String
        var id: String { number }
    }

    private static let players = [
        Player(number: "3", name: "Jordan Carter", position: "Guard"),
        Player(number: "11", name: "Malik Brooks", position: "Forward"),
        Player(number: "24", name: "Eli Thompson", position: "Center"),
        Player(number: "32", name: "Ty Reynolds", position: "Guard"),
    ]

    @Environment(\.brandTheme) private var brandTheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SketchHeader(title: "Roster", systemImage: "person.3.fill", team: SketchTeams.jayhawks)

            ForEach(Self.players) { player in
                HStack(spacing: Theme.Spacing.m) {
                    Text(player.number)
                        .font(Theme.Typography.statLabel.monospacedDigit())
                        .foregroundStyle(brandTheme.accentColor)
                        .frame(width: 36, height: 36)
                        .background(brandTheme.accentColor.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(Theme.Typography.cardTitle)
                        Text(player.position)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                    .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Stats: a player's line over team bars that fill in as the page comes
/// into view, or are full at once under Reduce Motion.
private struct StatsSketch: View {
    let isCurrent: Bool

    private struct Figure: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    private struct Bar: Identifiable {
        let label: String
        let value: String
        let fraction: CGFloat
        var id: String { label }
    }

    private static let figures = [
        Figure(value: "18.4", label: "PTS"),
        Figure(value: "7.2", label: "REB"),
        Figure(value: "4.1", label: "AST"),
    ]

    private static let bars = [
        Bar(label: "Field Goal %", value: "48.2%", fraction: 0.48),
        Bar(label: "3-Point %", value: "37.5%", fraction: 0.375),
        Bar(label: "Free Throw %", value: "76.9%", fraction: 0.77),
    ]

    @Environment(\.brandTheme) private var brandTheme
    private var settings = AdaptiveSettings()
    /// Whether the bars have filled in.
    @State private var revealed = false

    init(isCurrent: Bool) {
        self.isCurrent = isCurrent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SketchHeader(title: "Stats", systemImage: "chart.bar.fill", team: SketchTeams.jayhawks)

            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.figures) { figure in
                    VStack(spacing: 2) {
                        Text(figure.value)
                            .font(Theme.Typography.statFigure)
                            .foregroundStyle(brandTheme.accentColor)
                        Text(figure.label)
                            .font(Theme.Typography.statLabel)
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
                }
            }

            ForEach(Self.bars) { bar in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(bar.label)
                            .font(Theme.Typography.footnote)
                        Spacer(minLength: Theme.Spacing.s)
                        Text(bar.value)
                            .font(Theme.Typography.statLabel.monospacedDigit())
                            .foregroundStyle(Theme.Palette.metadata)
                    }
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 8)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(brandTheme.accentColor)
                                    .frame(width: proxy.size.width * (revealed ? bar.fraction : 0))
                            }
                        }
                }
            }
        }
        .onChange(of: isCurrent, initial: true) { _, isCurrent in
            guard isCurrent || settings.reduceMotion, !revealed else { return }
            withAnimation(Theme.Motion.animation(.snappy.delay(0.15), reduceMotion: settings.reduceMotion)) {
                revealed = true
            }
        }
    }
}

#Preview {
    OnboardingFlowView {}
}
