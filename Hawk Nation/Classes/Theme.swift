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
        // TODO(GlassUI): try `ConcentricRectangle` here once confirmed in the
        // SDK the CI image ships; a capsule is always correct meanwhile.
        /// League chips, pills and the crest picker.
        static var chip: Capsule { Capsule() }
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

    /// `glassChrome(in:tint:interactive:)` in a capsule.
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

private struct AdaptiveScrim: ViewModifier {
    let opacity: Double

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .opacity(Theme.scrimOpacity(opacity, contrast: contrast, reduceTransparency: reduceTransparency))
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
    let team = TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305")
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
