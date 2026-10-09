//
//  Theme.swift
//  myTeams
//
//  Created by Stephen Rector on 10/3/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - Tokens

/// The app's design tokens: one type ramp, one spacing scale, one radius set
/// and the rule for which surfaces are glass (docs/UI_AUDIT_IOS27_GLASSUI.md
/// §4 Phase 0).
///
/// Platform policy (§6): the deployment target stays iOS 26.0 and the app
/// builds with the iOS 27 SDK. Any iOS 27-only API goes behind
/// `if #available(iOS 27, *)` inside the primitives in this file and nowhere
/// else, so call sites never branch.
enum Theme {

    /// Named text styles. All are built on text styles, so they follow
    /// Dynamic Type up to AX5 and get SF Pro's optical sizes for free (X-1).
    /// Pair any adoption with the fixed-frame fixes so nothing clips (§5.3).
    enum Typography {
        /// A page section's heading ("Schedule", "Roster", "News").
        static let sectionTitle = Font.title3.bold()
        /// The title on a card or a sheet's header row.
        static let cardTitle = Font.headline
        /// Running text.
        static let body = Font.body
        /// A score or a big stat; fixed-width digits so live updates don't
        /// jiggle the layout.
        static let statFigure = Font.title2.weight(.black).monospacedDigit()
        /// The label under or beside a `statFigure`.
        static let statLabel = Font.caption.weight(.semibold)
        /// Secondary lines: dates, venues, bylines.
        static let footnote = Font.footnote
        /// The smallest text: badges, timestamps.
        static let caption = Font.caption
    }

    /// The spacing scale, in points. Paddings and stack spacings come from
    /// here rather than ad-hoc 5/10/15/25s.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    /// Corner radii (X-4). An inner shape sits `card - inner` (8 pt) inside
    /// its card so the corners stay concentric.
    enum Radius {
        /// Section cards and sheet hero panels.
        static let card: CGFloat = 20
        /// Shapes nested inside a card.
        static let inner: CGFloat = 12

        /// The top corners of a page of cards that sits over a hero: its
        /// cards are inset `Spacing.m` from its edges, so it's that much
        /// rounder than they are, and concentric with them.
        static let page: CGFloat = card + Spacing.m

        static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: card, style: .continuous) }
        static var innerShape: RoundedRectangle { RoundedRectangle(cornerRadius: inner, style: .continuous) }
        /// `page` on top, square at the foot, which runs off the screen.
        static var pageShape: UnevenRoundedRectangle {
            UnevenRoundedRectangle(topLeadingRadius: page, topTrailingRadius: page, style: .continuous)
        }
        /// League chips, pills and the crest picker: concentric with the
        /// container they sit in, and never squarer than `inner`.
        static var chip: ConcentricRectangle {
            ConcentricRectangle(corners: .concentric(minimum: .fixed(inner)), isUniform: true)
        }
    }

    /// Which layer is glass (principle B1): content sits on grouped
    /// backgrounds, chrome (bars, floating buttons, the crest picker) is
    /// glass. Never put glass on scrolling content cards, and never stack
    /// glass on glass.
    enum Surface {
        /// The page behind content cards.
        static let content = Color(uiColor: .systemGroupedBackground)
        /// A content card on `content`.
        static let contentCard = Color(uiColor: .secondarySystemGroupedBackground)
        /// A card nested in a `contentCard`: a leader card, a game card's
        /// foot, a skeleton.
        static let insetCard = Color(uiColor: .tertiarySystemGroupedBackground)
        /// Floating controls: see `View.glassChrome(in:tint:interactive:)`.
        static var chrome: Glass { .regular }
    }

    /// The opacity of the team-colour wash behind a followed row (a
    /// standings row, a leaderboard row): faint by default, twice as strong
    /// under Increase Contrast. The wash only backs up the row's star and
    /// `isSelected` trait, which carry the meaning without colour (T-7,
    /// LL-2); text sits on it, so it stays well short of a scrim.
    static func selectionWashOpacity(contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.3 : 0.15
    }

    /// The opacity to draw a scrim at, given the accessibility settings: a
    /// third of the way to opaque under Increase Contrast, and opaque under
    /// Reduce Transparency. Pure so it can be unit-tested.
    static func scrimOpacity(_ base: Double, contrast: ColorSchemeContrast, reduceTransparency: Bool) -> Double {
        if reduceTransparency { return 1 }
        let clamped = min(max(base, 0), 1)
        return contrast == .increased ? clamped + (1 - clamped) / 3 : clamped
    }

    /// One stop of a gradient scrim: its opacity at `location`, from 0 at
    /// the gradient's start to 1 at its end.
    struct ScrimStop: Equatable, Sendable {
        var opacity: Double
        var location: CGFloat
    }

    /// `scrimOpacity(_:contrast:reduceTransparency:)` at every stop of a
    /// gradient scrim: each stop raised a third of the way to opaque under
    /// Increase Contrast, and all of them opaque, one flat scrim, under
    /// Reduce Transparency. Pure so it can be unit-tested.
    static func scrimStops(_ stops: [ScrimStop], contrast: ColorSchemeContrast, reduceTransparency: Bool) -> [ScrimStop] {
        stops.map { stop in
            ScrimStop(
                opacity: scrimOpacity(stop.opacity, contrast: contrast, reduceTransparency: reduceTransparency),
                location: stop.location
            )
        }
    }

    /// Loading placeholders: the skeleton blocks and the redacted layouts
    /// that stand in for content until it loads (X-6, D-7).
    enum Placeholder {
        /// The pulse's floor. Placeholders draw in the system fill, which
        /// is already translucent, so they pulse between half and full
        /// strength.
        static let minOpacity: Double = 0.5
        /// The pulse's peak.
        static let maxOpacity: Double = 1
        /// Under Reduce Motion the placeholder holds still midway through
        /// the pulse, in the same tone.
        static let restingOpacity: Double = 0.75

        /// The pulse: two seconds up, two seconds down, for as long as the
        /// placeholder shows.
        static var pulse: Animation {
            .easeInOut(duration: 2).repeatForever(autoreverses: true)
        }

        /// The placeholder's opacity at either end of the pulse (`raised`),
        /// or at rest under Reduce Motion. Pure so it can be unit-tested.
        static func opacity(raised: Bool, reduceMotion: Bool) -> Double {
            if reduceMotion { return restingOpacity }
            return raised ? maxOpacity : minOpacity
        }
    }

    /// The app's few animations and transitions (Phase 3), each with its
    /// Reduce Motion fallback, so call sites name a role and never read the
    /// setting themselves. Applied through `View.motionAnimation(_:value:)`,
    /// `scoreTransition(value:)` and `zoomTransition(sourceID:in:)`.
    enum Motion {
        /// A selection moving between items: the crest picker's pill, a
        /// league chip (H-7, B-4).
        static let selection: Animation = .bouncy
        /// A control changing state in place: a follow toggle, a player
        /// sheet's tab (B-2, P-7).
        static let stateChange: Animation = .snappy
        /// A score's digits rolling to the new figure (G-5, X-12, LA-3).
        static let score: Animation = .snappy
        /// The cross-fade a score takes under Reduce Motion: no movement,
        /// only the old figure fading into the new.
        static let reducedFade: Animation = .easeInOut(duration: 0.2)

        /// `animation`, or none under Reduce Motion, so the change lands at
        /// once rather than moving. Pure so it can be unit-tested.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }

        /// How a score changes: its digits roll towards `value`, or, under
        /// Reduce Motion, the old figure cross-fades into the new. `value`
        /// should only rise as the game goes on (both sides' scores
        /// summed), so the digits roll one way. Pure so it can be
        /// unit-tested.
        static func scoreTransition(value: Double, reduceMotion: Bool) -> ContentTransition {
            reduceMotion ? .opacity : .numericText(value: value)
        }

        /// The animation a score's transition plays in.
        static func scoreAnimation(reduceMotion: Bool) -> Animation {
            reduceMotion ? reducedFade : score
        }
    }

    /// Accessibility settings asked for in the launch environment by the
    /// GlassUI screenshot pass (`GlassUIScreenshotTests`). XCUITest can't
    /// switch Increase Contrast, Reduce Transparency or Reduce Motion on
    /// in-process, so the app stands them in: Increase Contrast for every
    /// view below the root (`View.launchAccessibilityOverrides()`), Reduce
    /// Transparency and Reduce Motion for the primitives in this file, the
    /// only app code that adapts to them. All off unless a key is "1".
    struct LaunchAccessibility: Equatable, Sendable {
        static let increaseContrastKey = "GLASSUI_INCREASE_CONTRAST"
        static let reduceTransparencyKey = "GLASSUI_REDUCE_TRANSPARENCY"
        static let reduceMotionKey = "GLASSUI_REDUCE_MOTION"

        let increaseContrast: Bool
        let reduceTransparency: Bool
        let reduceMotion: Bool

        init(environment: [String: String]) {
            increaseContrast = environment[Self.increaseContrastKey] == "1"
            reduceTransparency = environment[Self.reduceTransparencyKey] == "1"
            reduceMotion = environment[Self.reduceMotionKey] == "1"
        }

        /// This launch's settings.
        static let current = LaunchAccessibility(environment: ProcessInfo.processInfo.environment)
    }
}

// MARK: - Glass primitives

extension View {
    /// Glass for a custom floating control (B3), in `shape`. `tint` carries
    /// meaning (the selected team, a primary action), not decoration;
    /// `interactive` makes it react to touch.
    ///
    /// Only for chrome. Content cards stay on `Theme.Surface`.
    func glassChrome(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        // The one place an iOS 27 refinement of `Glass` may branch:
        // `if #available(iOS 27, *) { … } else { … }`.
        var glass = Theme.Surface.chrome
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glassEffect(glass, in: shape)
    }

    /// `glassChrome(in:tint:interactive:)` in a `Radius.chip`.
    func glassChrome(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassChrome(in: Theme.Radius.chip, tint: tint, interactive: interactive)
    }

    /// A section's inset rounded card on the grouped page (T-4). Not glass:
    /// content cards scroll, and glass is for the chrome above them (B1).
    func contentCard() -> some View {
        background(Theme.Surface.contentCard, in: Theme.Radius.cardShape)
    }

    /// Draws a hand-rolled scrim layer (a team-colour wash, a dimmed crest)
    /// at `opacity`, raised under Increase Contrast and made opaque under
    /// Reduce Transparency (X-5). System glass adapts by itself; this is for
    /// the layers it doesn't cover. Use in place of `.opacity(_:)`.
    func adaptiveScrim(_ opacity: Double) -> some View {
        modifier(AdaptiveScrim(opacity: opacity))
    }

    /// `adaptiveScrim(_:)` for a scrim that deepens across the view: masks
    /// the view (a colour, usually) to a linear gradient through `stops`,
    /// each adapted the way a flat scrim is (X-5). Opaque throughout under
    /// Reduce Transparency.
    func adaptiveGradientScrim(
        _ stops: [Theme.ScrimStop],
        startPoint: UnitPoint = .top,
        endPoint: UnitPoint = .bottom
    ) -> some View {
        modifier(AdaptiveGradientScrim(stops: stops, startPoint: startPoint, endPoint: endPoint))
    }

    /// The loading pulse for a placeholder shape (X-6): between
    /// `Theme.Placeholder`'s floor and peak, or still under Reduce Motion.
    func placeholderPulse() -> some View {
        modifier(PlaceholderPulse())
    }

    /// The view as a placeholder for itself until its data loads (D-7):
    /// its real layout over placeholder data, redacted, pulsing as the
    /// skeleton blocks do. VoiceOver hears "Loading" rather than the
    /// placeholder data.
    func loadingPlaceholder() -> some View {
        redacted(reason: .placeholder)
            .placeholderPulse()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading"))
    }

    /// `.animation(animation, value:)`, or no animation under Reduce Motion
    /// (`Theme.Motion.animation(_:reduceMotion:)`). Use in place of
    /// `.animation(_:value:)` for anything that moves.
    func motionAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// A score `Text` whose digits roll when `value` changes, or cross-fade
    /// under Reduce Motion (G-5, X-12, LA-3). `value` is the score, or both
    /// sides' scores summed for a scoreline.
    func scoreTransition(value: Double) -> some View {
        modifier(ScoreTransition(value: value))
    }

    /// Marks a card as where the sheet it opens zooms from (X-13). Pair
    /// with `zoomTransition(sourceID:in:)` on the sheet's content.
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }

    /// A sheet that zooms out of the card marked `zoomSource(id:in:)` with
    /// `sourceID`, and back into it on close (X-13). The system's slide up
    /// under Reduce Motion.
    func zoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        modifier(ZoomTransition(sourceID: sourceID, namespace: namespace))
    }

    /// Stands `Theme.LaunchAccessibility.current`'s Increase Contrast in
    /// for the system's in the environment below. For the app's root view
    /// only; changes nothing unless a UI test set the launch key.
    func launchAccessibilityOverrides() -> some View {
        let increaseContrast = Theme.LaunchAccessibility.current.increaseContrast
        // `_colorSchemeContrast` is SwiftUI's own setter for the value,
        // the one previews use to show Increase Contrast.
        return transformEnvironment(\._colorSchemeContrast) { contrast in
            if increaseContrast { contrast = .increased }
        }
    }

    /// Text and symbols in the ink that reads on `team`'s colour: its
    /// alternate colour when that reaches 4.5:1, otherwise white or black,
    /// whichever contrasts more (G-3).
    func teamInk(on team: TeamRef) -> some View {
        foregroundStyle(TeamColors.ink(on: team))
    }

    /// Text and symbols in white or black, whichever reads on `backgroundHex`.
    func teamInk(onHex backgroundHex: String) -> some View {
        foregroundStyle(Color(hexString: TeamColors.inkHex(on: backgroundHex)))
    }
}

/// The accessibility settings the primitives here adapt to: the system's,
/// or the ones a UI test stood in at launch (`Theme.LaunchAccessibility`).
/// Outside this file only for `withAnimation` around imperative changes,
/// through `Theme.Motion.animation(_:reduceMotion:)`.
struct AdaptiveSettings: DynamicProperty {
    @Environment(\.colorSchemeContrast) var contrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var reduceTransparency: Bool {
        systemReduceTransparency || Theme.LaunchAccessibility.current.reduceTransparency
    }

    var reduceMotion: Bool {
        systemReduceMotion || Theme.LaunchAccessibility.current.reduceMotion
    }
}

private struct AdaptiveScrim: ViewModifier {
    let opacity: Double

    private var settings = AdaptiveSettings()

    init(opacity: Double) {
        self.opacity = opacity
    }

    func body(content: Content) -> some View {
        content
            .opacity(Theme.scrimOpacity(opacity, contrast: settings.contrast, reduceTransparency: settings.reduceTransparency))
    }
}

private struct AdaptiveGradientScrim: ViewModifier {
    let stops: [Theme.ScrimStop]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    private var settings = AdaptiveSettings()

    init(stops: [Theme.ScrimStop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.stops = stops
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    func body(content: Content) -> some View {
        let adapted = Theme.scrimStops(stops, contrast: settings.contrast, reduceTransparency: settings.reduceTransparency)
        return content
            .mask {
                LinearGradient(
                    stops: adapted.map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) },
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            }
    }
}

private struct PlaceholderPulse: ViewModifier {
    private var settings = AdaptiveSettings()

    @State private var raised = false

    func body(content: Content) -> some View {
        content
            .opacity(Theme.Placeholder.opacity(raised: raised, reduceMotion: settings.reduceMotion))
            .onAppear {
                // Still under Reduce Motion: nothing to animate.
                guard !settings.reduceMotion else { return }
                withAnimation(Theme.Placeholder.pulse) {
                    raised = true
                }
            }
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    private var settings = AdaptiveSettings()

    init(animation: Animation, value: Value) {
        self.animation = animation
        self.value = value
    }

    func body(content: Content) -> some View {
        content
            .animation(Theme.Motion.animation(animation, reduceMotion: settings.reduceMotion), value: value)
    }
}

private struct ScoreTransition: ViewModifier {
    let value: Double

    private var settings = AdaptiveSettings()

    init(value: Double) {
        self.value = value
    }

    func body(content: Content) -> some View {
        // The score changes outside any animation (a poll, a push), and a
        // content transition needs one to play.
        content
            .contentTransition(Theme.Motion.scoreTransition(value: value, reduceMotion: settings.reduceMotion))
            .animation(Theme.Motion.scoreAnimation(reduceMotion: settings.reduceMotion), value: value)
    }
}

private struct ZoomTransition<ID: Hashable>: ViewModifier {
    let sourceID: ID
    let namespace: Namespace.ID

    private var settings = AdaptiveSettings()

    init(sourceID: ID, namespace: Namespace.ID) {
        self.sourceID = sourceID
        self.namespace = namespace
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if settings.reduceMotion {
            content
                .navigationTransition(.automatic)
        } else {
            content
                .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}

extension TeamColors {
    /// WCAG AA for body text.
    static let minimumInkContrast = 4.5

    /// The ink for text on `backgroundHex`: `alternate` when it reaches
    /// `minimumInkContrast`, otherwise white or black, whichever contrasts
    /// more. One of white and black always clears 4.5:1, so the result does.
    static func inkHex(on backgroundHex: String, alternate: String? = nil) -> String {
        if let alternate, let ratio = contrastRatio(alternate, backgroundHex), ratio >= minimumInkContrast {
            return alternate
        }
        let white = contrastRatio("FFFFFF", backgroundHex) ?? 21
        let black = contrastRatio("000000", backgroundHex) ?? 1
        return white >= black ? "FFFFFF" : "000000"
    }

    /// The ink `View.teamInk(on:)` draws in, for views that hand it down or
    /// mix it with other styles: legible on `fillHex(for: team)`.
    static func ink(on team: TeamRef) -> Color {
        Color(hexString: inkHex(on: fillHex(for: team), alternate: team.alternateColorHex))
    }
}

// MARK: - Sheet close button

/// The glass `xmark` that closes a sheet (D-1, P-2), for a sheet's top
/// trailing overlay or a trailing toolbar item. Dismisses the presenting
/// sheet unless given an `action`. 44 pt square, labelled for VoiceOver.
struct SheetCloseButton: View {
    var action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassChrome(in: Circle(), interactive: true)
        .accessibilityLabel("Close")
    }
}

#Preview {
    let team = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")!
    VStack(spacing: Theme.Spacing.l) {
        Text("Section title").font(Theme.Typography.sectionTitle)
        Text("102").font(Theme.Typography.statFigure)
        Text(team.displayName)
            .font(Theme.Typography.cardTitle)
            .teamInk(on: team)
            .padding(Theme.Spacing.m)
            .background(team.color, in: Theme.Radius.innerShape)
        Text("Chrome")
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .glassChrome(tint: team.color, interactive: true)
        SheetCloseButton {}
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Surface.content)
}
