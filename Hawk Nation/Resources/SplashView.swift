//
//  SplashView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The brand logo on the launch screen's colour: what the system draws
/// from Info.plist's `UILaunchScreen` before the app runs, redrawn by
/// SwiftUI so the hand-off from the launch screen to the app is seamless.
/// `View.splashOverlay()` lays it over the root view until that view's
/// first frame is up, then fades it away.
///
/// The logo is the reader's brand theme's (`BrandTheme`). The launch
/// screen before it can't be: iOS draws `UILaunchScreen` from the bundle
/// before any of the app's code runs, so it is always the shipped art, and
/// with another theme the logo changes colour as the splash takes over.
/// `LaunchscreenColor` stays, and every theme's art is drawn at the launch
/// screen's size, so only the mark's colours change.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchscreenColor")
            // The imageset's light and dark variants match the colour's
            // white and black, as on the launch screen.
            // At the size the launch screen draws it, its natural point
            // width, so the hand-off doesn't shrink it (B-5).
            BrandLogoMark()
                .frame(width: BrandLogo.launch)
                .accessibilityLabel("myTeams")
                .accessibilityIdentifier("splash.logo")
        }
        .ignoresSafeArea()
    }
}

/// The brand logo's sizes, one set for every place it appears (B-12): the
/// team page's bar, the splash, the "No Teams" screen, the article error
/// and Settings' About footer.
enum BrandLogo {
    /// In a navigation bar, by height: brand presence, not a control that
    /// grows with text.
    static let bar: CGFloat = 20
    /// Beside a message (an error, a footer), by width.
    static let inline: CGFloat = 120
    /// A screen's centrepiece, such as the empty state, by width.
    static let hero: CGFloat = 160
    /// On the splash, by width: the point size of `myTeamsLogo` (798 px
    /// wide at @3x), which the system launch screen draws it at and the
    /// splash has to match (B-5). Set by the asset, not a free choice.
    static let launch: CGFloat = 266
}

/// Whether the splash is still up. It goes once, for good, when the root
/// view under it has drawn (`dismiss(reduceMotion:)`).
@MainActor
@Observable
final class SplashCoordinator {
    private(set) var isVisible = true

    /// How long the splash takes to fade out; it goes at once under
    /// Reduce Motion.
    static let fade: Animation = .easeOut(duration: 0.3)

    /// The scheme to ask of the window: none, so the system's, while the
    /// splash is up, then the reader's choice (B-6).
    nonisolated static func colorScheme(preferred: ColorScheme?, splashVisible: Bool) -> ColorScheme? {
        splashVisible ? nil : preferred
    }

    func dismiss(reduceMotion: Bool) {
        guard isVisible else { return }
        withAnimation(Theme.Motion.animation(Self.fade, reduceMotion: reduceMotion)) {
            isVisible = false
        }
    }
}

private struct SplashOverlay: ViewModifier {
    /// The reader's appearance (`AppAppearance`), `nil` for the system's.
    let preferredColorScheme: ColorScheme?

    @State private var coordinator = SplashCoordinator()
    /// The system's scheme at launch, which the launch screen was drawn
    /// in. The splash keeps it while it fades.
    @State private var launchColorScheme: ColorScheme?
    @Environment(\.colorScheme) private var colorScheme
    private var settings = AdaptiveSettings()

    init(preferredColorScheme: ColorScheme?) {
        self.preferredColorScheme = preferredColorScheme
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if coordinator.isVisible {
                    SplashView()
                        .environment(\.colorScheme, launchColorScheme ?? colorScheme)
                        .transition(.opacity)
                        // Never in the way of a tap while it fades.
                        .allowsHitTesting(false)
                }
            }
            // The launch screen follows the system's appearance, so the
            // splash does too. The reader's choice is a preference on the
            // whole window, so it waits until the splash goes and the fade
            // carries the change (B-6); the splash itself keeps the launch
            // screen's scheme throughout.
            .preferredColorScheme(SplashCoordinator.colorScheme(
                preferred: preferredColorScheme,
                splashVisible: coordinator.isVisible
            ))
            .onAppear {
                launchColorScheme = colorScheme
                // `onAppear` runs once the content's first render pass is
                // laid out; one more turn of the main run loop and that
                // frame is committed under the splash. No timer: the
                // splash lasts exactly as long as the first frame takes.
                Task { @MainActor in
                    coordinator.dismiss(reduceMotion: settings.reduceMotion)
                }
            }
    }
}

extension View {
    /// Covers the view with `SplashView` until its first frame is drawn,
    /// then fades it out (removes it outright under Reduce Motion). For
    /// the app's root view only.
    ///
    /// Applies `preferredColorScheme` itself, once the splash has gone:
    /// the splash matches the launch screen, which the system draws in its
    /// own appearance whatever the reader picked (B-6).
    func splashOverlay(preferredColorScheme: ColorScheme?) -> some View {
        modifier(SplashOverlay(preferredColorScheme: preferredColorScheme))
    }
}
