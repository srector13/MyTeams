//
//  OnboardingWalkthroughView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The first-launch walkthrough: a few pages that show what the app does,
/// before the theme step (`ThemeOnboarding`) that ends the flow.
///
/// It has no flag of its own. It is offered whenever the theme step is
/// (`ThemeOnboarding.isPending`), so an install that predates the flow, or
/// has finished it, sees neither.
enum OnboardingWalkthrough {
    /// A page of the walkthrough, in order.
    enum Page: Int, CaseIterable, Identifiable, Sendable {
        case roster
        case schedule
        case stats

        var id: Self { self }

        /// One-based, as the page indicator counts.
        var number: Int { rawValue + 1 }

        var headline: String {
            switch self {
            case .roster: "Know Your Roster"
            case .schedule: "Never Miss a Game"
            case .stats: "Follow the Numbers"
            }
        }

        var caption: String {
            switch self {
            case .roster: "Browse every player on your team, with numbers and positions."
            case .schedule: "Upcoming games and final scores, all at a glance."
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

    /// Where the flow is: a walkthrough page, or the theme step after them.
    enum Step: Hashable, Sendable {
        case walkthrough(Page)
        case theme

        /// Where the flow opens.
        static let first = Step.walkthrough(.roster)

        /// The page shown, or `nil` on the theme step.
        var page: Page? {
            if case .walkthrough(let page) = self { page } else { nil }
        }

        /// After Next or Get Started: the next page, or the theme step
        /// after the last. The theme step finishes the flow itself.
        var advanced: Step {
            switch self {
            case .walkthrough(let page): page.next.map(Step.walkthrough) ?? .theme
            case .theme: .theme
            }
        }

        /// After Skip: straight to the theme step, which can be skipped
        /// in its turn.
        var skipped: Step { .theme }
    }
}

/// The first-launch sheet: the walkthrough's pages, then the theme step
/// (`ThemeOnboardingView`), which marks the flow complete. Not dismissable
/// by a swipe, so leaving is always through the theme step.
struct OnboardingFlowView: View {
    /// Called once the theme step is finished or skipped.
    let onFinish: () -> Void

    @State private var step = OnboardingWalkthrough.Step.first
    private var settings = AdaptiveSettings()

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            if step.page != nil {
                OnboardingWalkthroughView(
                    page: Binding(
                        get: { step.page ?? .roster },
                        set: { step = .walkthrough($0) }
                    ),
                    onNext: { move(to: step.advanced) },
                    onSkip: { move(to: step.skipped) }
                )
                .transition(transition)
            } else {
                ThemeOnboardingView(onFinish: onFinish)
                    .transition(transition)
            }
        }
        .interactiveDismissDisabled()
    }

    /// The theme step slides in after the pages, as one more page would;
    /// under Reduce Motion it just takes their place.
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
            .tabViewStyle(.page(indexDisplayMode: .always))
            // The dots on a backing, so they show on light and dark alike.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Theme.Surface.content)
            .safeAreaInset(edge: .bottom) {
                Button(action: onNext) {
                    Text(page.buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(Theme.Spacing.l)
                .background(.bar)
                .accessibilityIdentifier(page.buttonIdentifier)
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

// MARK: - Page

/// One page: a sketch of the screen it's about over its headline and
/// caption. The sketch is decorative; the words say what it shows.
private struct WalkthroughPageView: View {
    let page: OnboardingWalkthrough.Page
    /// Whether the page is the one in view, which starts its sketch's
    /// motion.
    let isCurrent: Bool

    var body: some View {
        // Scrolls only when the text is too large to fit.
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                sketch
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: 380)
                    .contentCard()
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
            .padding(.top, Theme.Spacing.xl)
            // Clear of the page indicator.
            .padding(.bottom, Theme.Spacing.xl * 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(page.accessibilityIdentifier)
    }

    @ViewBuilder
    private var sketch: some View {
        switch page {
        case .roster: RosterSketch()
        case .schedule: ScheduleSketch()
        case .stats: StatsSketch(isCurrent: isCurrent)
        }
    }
}

// MARK: - Sketches

/// A sketch's heading, as a section's on a team's page.
private struct SketchHeader: View {
    let title: String
    let systemImage: String

    @Environment(\.brandTheme) private var brandTheme

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(brandTheme.accentColor)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.sectionTitle)
    }
}

/// The roster: a few player rows, number badge, name and position.
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
            SketchHeader(title: "Roster", systemImage: "person.3.fill")

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
                            .foregroundStyle(.secondary)
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

/// The schedule: three game cards, two results and the next game.
private struct ScheduleSketch: View {
    private struct Game: Identifiable {
        let status: String
        let opponent: String
        let abbreviation: String
        let color: Color
        let result: String
        let isFinal: Bool
        var id: String { opponent }
    }

    private static let games = [
        Game(status: "FINAL", opponent: "Wildcats", abbreviation: "WIL", color: .orange, result: "W 78–71", isFinal: true),
        Game(status: "FINAL", opponent: "@ Tigers", abbreviation: "TIG", color: .indigo, result: "L 64–70", isFinal: true),
        Game(status: "SAT", opponent: "Bears", abbreviation: "BEA", color: .green, result: "7:00 PM", isFinal: false),
    ]

    @Environment(\.brandTheme) private var brandTheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SketchHeader(title: "Schedule", systemImage: "calendar")

            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.games) { game in
                    VStack(spacing: Theme.Spacing.xs) {
                        Text(game.status)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(game.isFinal ? Color.secondary : brandTheme.accentColor)

                        Circle()
                            .fill(game.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(game.abbreviation)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(.white)
                            }

                        Text(game.opponent)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(game.result)
                            .font(Theme.Typography.statLabel.monospacedDigit())
                            .foregroundStyle(game.isFinal ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.m)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
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
            SketchHeader(title: "Stats", systemImage: "chart.bar.fill")

            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.figures) { figure in
                    VStack(spacing: 2) {
                        Text(figure.value)
                            .font(Theme.Typography.statFigure)
                            .foregroundStyle(brandTheme.accentColor)
                        Text(figure.label)
                            .font(Theme.Typography.statLabel)
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
