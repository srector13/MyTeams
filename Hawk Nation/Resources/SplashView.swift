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
struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchscreenColor")
            // The imageset's light and dark variants match the colour's
            // white and black, as on the launch screen.
            Image("myTeamsLogo")
                .resizable()
                .scaledToFit()
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.55 }
                .padding()
                .accessibilityLabel("myTeams")
                .accessibilityIdentifier("splash.logo")
        }
        .ignoresSafeArea()
    }
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

    func dismiss(reduceMotion: Bool) {
        guard isVisible else { return }
        withAnimation(Theme.Motion.animation(Self.fade, reduceMotion: reduceMotion)) {
            isVisible = false
        }
    }
}

private struct SplashOverlay: ViewModifier {
    @State private var coordinator = SplashCoordinator()
    private var settings = AdaptiveSettings()

    func body(content: Content) -> some View {
        content
            .overlay {
                if coordinator.isVisible {
                    SplashView()
                        .transition(.opacity)
                        // Never in the way of a tap while it fades.
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
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
    func splashOverlay() -> some View {
        modifier(SplashOverlay())
    }
}
