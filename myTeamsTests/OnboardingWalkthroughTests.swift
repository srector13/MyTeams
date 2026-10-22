//
//  OnboardingWalkthroughTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The first-launch walkthrough (`OnboardingWalkthrough`): its pages, how
/// the flow steps through them to the theme step and on to the teams step
/// that ends it, and the teams step's Done rule (`OnboardingTeamsStep`).
@Suite("Onboarding walkthrough")
struct OnboardingWalkthroughTests {
    typealias Page = OnboardingWalkthrough.Page
    typealias Step = OnboardingWalkthrough.Step

    @Test("Schedule, Roster, Stats, numbered from one")
    func pages() {
        #expect(Page.allCases == [.schedule, .roster, .stats])
        #expect(Page.allCases.map(\.number) == [1, 2, 3])
        #expect(Page.allCases.map(\.accessibilityIdentifier) == [
            "onboarding.walkthrough.page.1",
            "onboarding.walkthrough.page.2",
            "onboarding.walkthrough.page.3",
        ])
        for page in Page.allCases {
            #expect(!page.headline.isEmpty)
            #expect(!page.caption.isEmpty)
        }
        #expect(Set(Page.allCases.map(\.headline)).count == Page.allCases.count)
        // The game page, with Home's Next Up hero, leads (O1).
        #expect(Page.schedule.headline == "Never Miss a Game")
    }

    @Test("Only the last page offers Get Started")
    func lastPage() {
        #expect(Page.schedule.next == .roster)
        #expect(Page.roster.next == .stats)
        #expect(Page.stats.next == nil)
        #expect(Page.allCases.filter(\.isLast) == [.stats])

        #expect(Page.schedule.buttonIdentifier == "onboarding.walkthrough.next")
        #expect(Page.roster.buttonTitle == "Next")
        #expect(Page.stats.buttonTitle == "Get Started")
        #expect(Page.stats.buttonIdentifier == "onboarding.walkthrough.getStarted")
    }

    @Test("Next steps through every page to the theme step, then the teams step")
    func advancing() {
        #expect(Step.first == .walkthrough(.schedule))

        var step = Step.first
        var visited: [Page] = []
        while let page = step.page {
            visited.append(page)
            step = step.advanced
        }
        #expect(visited == Page.allCases)
        #expect(step == .theme)
        #expect(Step.theme.advanced == .teams)
        #expect(Step.theme.page == nil)
        // The teams step finishes the flow itself; advancing stays put.
        #expect(Step.teams.advanced == .teams)
        #expect(Step.teams.page == nil)
    }

    @Test("Skip goes straight to the theme step from any page, and on from there")
    func skipping() {
        for page in Page.allCases {
            #expect(Step.walkthrough(page).skipped == .theme)
        }
        #expect(Step.theme.skipped == .teams)
        #expect(Step.teams.skipped == .teams)
    }

    @Test("The teams step follows the theme step only for a reader following no team")
    func teamsStepOnlyWithoutTeams() {
        #expect(OnboardingWalkthrough.needsTeamsStep(followedCount: 0))
        // Favorites restored from iCloud, or a UI test's, end the flow at
        // the theme step, as before.
        #expect(!OnboardingWalkthrough.needsTeamsStep(followedCount: 1))
        #expect(!OnboardingWalkthrough.needsTeamsStep(followedCount: 4))
    }

    @Test("Done is disabled until a team is picked, then counts the picks")
    func doneRule() {
        #expect(!OnboardingTeamsStep.canFinish(pickedCount: 0))
        #expect(OnboardingTeamsStep.canFinish(pickedCount: 1))
        #expect(OnboardingTeamsStep.canFinish(pickedCount: 5))

        #expect(OnboardingTeamsStep.doneTitle(pickedCount: 0) == "Done")
        #expect(OnboardingTeamsStep.doneTitle(pickedCount: 1) == "Done · 1 team")
        #expect(OnboardingTeamsStep.doneTitle(pickedCount: 2) == "Done · 2 teams")
        #expect(OnboardingTeamsStep.title == "Pick Your Teams")
    }

    @MainActor
    @Test("The walkthrough shares the theme step's one completion flag")
    func oneFlag() throws {
        let suite = "OnboardingWalkthroughTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        // A fresh install sees the flow; an earlier one sees none of it.
        ThemeOnboarding.prepare(defaults: defaults, isExistingInstall: false, environment: [:])
        #expect(ThemeOnboarding.isPending(in: defaults))
        let existing = try #require(UserDefaults(suiteName: suite + ".existing"))
        existing.removePersistentDomain(forName: suite + ".existing")
        ThemeOnboarding.prepare(defaults: existing, isExistingInstall: true, environment: [:])
        #expect(!ThemeOnboarding.isPending(in: existing))

        // Finishing writes the theme step's key and nothing else.
        ThemeOnboarding.complete(in: defaults)
        let keys = defaults.persistentDomain(forName: suite)?.keys.filter { $0.hasPrefix("onboarding.") }
        #expect(keys == [ThemeOnboarding.completedKey])
    }
}
