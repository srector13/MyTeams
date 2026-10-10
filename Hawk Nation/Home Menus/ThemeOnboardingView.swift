//
//  ThemeOnboardingView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/10/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The first-launch theme step: whether to offer it, decided once at launch
/// and stored under `completedKey`.
///
/// Offered once, on a fresh install. An install that predates the step (one
/// the app has already written its favorites or settings to) is marked
/// complete without being asked, and keeps `classic`. Finishing or skipping
/// the step marks it complete too; it is never offered again after that.
@MainActor
enum ThemeOnboarding {
    /// Set, true, once the step has been finished, skipped, or passed over
    /// for an install that predates it.
    static let completedKey = "onboarding.themeStep.completed"

    #if DEBUG
    /// The launch-environment key UI tests set to see the step: `"1"`
    /// offers it whatever is stored, anything else marks it complete. A UI
    /// test launch without it (one that sets
    /// `FavoritesStore.launchFavoritesKey`) never sees the step. Read only
    /// in Debug builds.
    static let launchKey = "MYTEAMS_ONBOARDING"
    #endif

    /// Whether the step is still to be offered.
    static func isPending(in defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedKey)
    }

    /// Marks the step complete, for good.
    static func complete(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }

    /// Whether the app has run on this install before the step existed: it
    /// has written its favorites (or the mark that it loaded them), or a
    /// setting. Read before `FavoritesStore` first loads, which writes that
    /// mark on a fresh install too.
    static func isExistingInstall(defaults: UserDefaults = .standard, sharedDefaults: UserDefaults) -> Bool {
        SharedContainer.appHasWritten(to: sharedDefaults)
            || SharedContainer.appHasWritten(to: defaults)
            || defaults.object(forKey: AppAppearance.storageKey) != nil
            || BrandTheme.retiredStorageKeys.contains { defaults.object(forKey: $0) != nil }
    }

    /// At launch, before anything reads the favorites: drops the retired
    /// brand settings, and marks the step complete for an install that
    /// predates it (and, in Debug, for UI-test launches that didn't ask
    /// for it).
    static func prepare(
        defaults: UserDefaults = .standard,
        isExistingInstall: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        BrandTheme.removeRetiredSettings(from: defaults)
        #if DEBUG
        if let value = environment[launchKey] {
            defaults.set(value != "1", forKey: completedKey)
            return
        }
        if environment[FavoritesStore.launchFavoritesKey] != nil {
            complete(in: defaults)
            return
        }
        #endif
        if isExistingInstall {
            complete(in: defaults)
        }
    }
}

/// The first-launch theme step: the logo, then the same palette grid as
/// Settings (`ThemePicker`), each tile with its logo, accent and app icon.
/// A tap applies the theme at once, the iOS app icon included
/// (`AppIconSwitcher`).
///
/// Two ways out, both final (`ThemeOnboarding.complete`): Continue keeps
/// the theme picked; Skip puts back `classic`. Not dismissable by a swipe,
/// so leaving is always one of the two.
struct ThemeOnboardingView: View {
    /// Called on Continue or Skip, after the choice is stored.
    let onFinish: () -> Void

    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic
    /// Whether iOS refused the last icon change.
    @State private var iconFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    BrandLogoMark()
                        .frame(width: BrandLogo.inline)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Pick Your Theme")
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose the colors for the app, the myTeams logo and your app icon. You can change it any time in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ThemePicker(selection: $theme, identifierPrefix: "onboarding.theme")

                    Text(ThemePicker.iconNote)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)

                    if iconFailed {
                        Label("The app icon couldn't change, so the classic icon stays.", systemImage: "exclamationmark.triangle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("onboarding.theme.iconFailed")
                    }
                }
                .padding(Theme.Spacing.l)
            }
            // Always reachable, however far the grid scrolls.
            .safeAreaInset(edge: .bottom) {
                Button {
                    finish()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(Theme.Spacing.l)
                .background(.bar)
                .accessibilityIdentifier("onboarding.theme.continue")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        theme = .classic
                        Task {
                            await AppIconSwitcher.apply(.classic)
                        }
                        finish()
                    }
                    .accessibilityIdentifier("onboarding.theme.skip")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .onChange(of: theme) { _, theme in
            Task {
                iconFailed = !(await AppIconSwitcher.apply(theme))
            }
        }
    }

    private func finish() {
        ThemeOnboarding.complete()
        onFinish()
    }
}

#Preview {
    ThemeOnboardingView {}
}
