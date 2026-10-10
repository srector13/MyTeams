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

/// The first-launch walkthrough (`OnboardingWalkthrough`): its pages, and
/// how the flow steps through them to the theme step that ends it.
@Suite("Onboarding walkthrough")
struct OnboardingWalkthroughTests {
    typealias Page = OnboardingWalkthrough.Page
    typealias Step = OnboardingWalkthrough.Step

    @Test("Roster, Schedule, Stats, numbered from one")
    func pages() {
        #expect(Page.allCases == [.roster, .schedule, .stats])
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
    }

    @Test("Only the last page offers Get Started")
    func lastPage() {
        #expect(Page.roster.next == .schedule)
        #expect(Page.schedule.next == .stats)
        #expect(Page.stats.next == nil)
        #expect(Page.allCases.filter(\.isLast) == [.stats])

        #expect(Page.roster.buttonIdentifier == "onboarding.walkthrough.next")
        #expect(Page.schedule.buttonTitle == "Next")
        #expect(Page.stats.buttonTitle == "Get Started")
        #expect(Page.stats.buttonIdentifier == "onboarding.walkthrough.getStarted")
    }

    @Test("Next steps through every page, then hands off to the theme step")
    func advancing() {
        #expect(Step.first == .walkthrough(.roster))

        var step = Step.first
        var visited: [Page] = []
        while let page = step.page {
            visited.append(page)
            step = step.advanced
        }
        #expect(visited == Page.allCases)
        #expect(step == .theme)
        // The theme step finishes the flow itself; advancing stays put.
        #expect(Step.theme.advanced == .theme)
        #expect(Step.theme.page == nil)
    }

    @Test("Skip goes straight to the theme step from any page")
    func skipping() {
        for page in Page.allCases {
            #expect(Step.walkthrough(page).skipped == .theme)
        }
        #expect(Step.theme.skipped == .theme)
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
