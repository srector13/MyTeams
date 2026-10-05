//
//  PlayerView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The team whose roster the cards below belong to, for the colour
    /// behind their headshots. `RosterSection` sets it; a card without one
    /// (a preview) draws on the inset surface instead.
    @Entry var rosterTeam: TeamRef? = nil
}

/// How a roster card is sized and how its caption wraps, worked out apart
/// from the view so the tests can drive it (as `GameCardContent` is for a
/// schedule card).
///
/// In the carousel the card has a fixed width, scaled with its text, and
/// the caption wraps to two lines rather than being cut off mid-word
/// ("Andrew Armstr"). At accessibility sizes, where the roster is a
/// vertical list, the card spans the row and its text takes as many lines
/// as it needs.
enum PlayerCardLayout {
    /// The caption's width at the default text size, in points: room for a
    /// long surname ("Christensen", "Anudike-Uzomah") on a line of its own.
    /// The card is `Theme.Spacing.s` wider on each side.
    static let baseWidth: CGFloat = 96

    /// The headshot's diameter at the default text size, in points.
    static let baseHeadshotSize: CGFloat = 60

    /// The largest the headshot grows beside the text in a list row; past
    /// this it crowds the name into breaking mid-word.
    static let maxRowHeadshotSize: CGFloat = 88

    /// The text style the card's size scales with: the caption's. Caption 2
    /// grows faster than caption, so scaled by caption's ratio the name
    /// outgrew the card.
    static let metricsTextStyle: Font.TextStyle = .caption2

    /// `metricsTextStyle`, for measuring with UIKit.
    static var metricsUITextStyle: UIFont.TextStyle { .caption2 }

    /// The caption's style, one for every sort (B-17).
    static let captionFont: Font = .caption2

    /// Lines the caption may take: two in the carousel, as many as it needs
    /// in a list row.
    static func lineLimit(fillsRow: Bool) -> Int? {
        fillsRow ? nil : 2
    }

    /// How small a word too long for a line of its own may be drawn before
    /// it's cut off: a last resort, after wrapping.
    static let minimumScaleFactor: CGFloat = 0.8

    /// The caption's width: `scaledWidth` in the carousel, none in a list
    /// row, which spans the row instead.
    static func width(scaledWidth: CGFloat, fillsRow: Bool) -> CGFloat? {
        fillsRow ? nil : scaledWidth
    }

    /// The headshot's diameter: `scaled` in the carousel, capped in a list
    /// row so the text beside it keeps room for a whole word per line.
    static func headshotSize(scaled: CGFloat, fillsRow: Bool) -> CGFloat {
        fillsRow ? min(scaled, maxRowHeadshotSize) : scaled
    }

    /// The caption's width at `category`, as `@ScaledMetric` scales it.
    @MainActor
    static func scaledWidth(for category: UIContentSizeCategory) -> CGFloat {
        UIFontMetrics(forTextStyle: metricsUITextStyle)
            .scaledValue(for: baseWidth, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    /// The caption for `text`, or "N/A" where the feed left the field out.
    static func caption(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "N/A" : trimmed
    }

    /// The initials drawn where a player has no headshot: the first and
    /// last names' first letters ("FA" for "Felix Anudike-Uzomah"), one for
    /// a single name, none for no name.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return "\(first)\(last)".uppercased()
    }
}

/// A player's card in a roster carousel: their headshot over the team's
/// colour, and a line or two of detail beneath it on the inset surface, as
/// a schedule card is laid out (X-4).
///
/// Which detail is shown follows the carousel's current sort, so ordering
/// the roster by number labels every card with its number. Sizing and
/// wrapping are `PlayerCardLayout`'s. At accessibility sizes, where the
/// roster is a vertical list, the card spans the row with the detail beside
/// the headshot (§5.3).
struct PlayerCard<Player: RosterPlayer>: View {
    var player: Player
    var state: PlayerSort

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.rosterTeam) private var team

    /// The caption and the headshot, which scale with the caption under or
    /// beside it (B-3).
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var captionWidth = PlayerCardLayout.baseWidth
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var headshotSize = PlayerCardLayout.baseHeadshotSize

    /// At accessibility text sizes the roster is a vertical list: the card
    /// fills a list row and sizes to its text.
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // In a list row the detail sits beside the headshot rather than
        // under it.
        let layout = fillsRow
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            headshotPlate
            caption
        }
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil)
        // In a list row, so the team's colour runs the row's full height
        // however many lines the caption takes.
        .fixedSize(horizontal: false, vertical: fillsRow)
        .background(Theme.Surface.insetCard)
        // Nested in the roster section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
    }

    /// The headshot on the team's colour, as a schedule card's header is
    /// (G-3).
    private var headshotPlate: some View {
        let size = PlayerCardLayout.headshotSize(scaled: headshotSize, fillsRow: fillsRow)
        return PlayerHeadshot(url: player.photo, name: player.name, team: team, size: size)
            .padding(Theme.Spacing.s)
            .frame(maxWidth: fillsRow ? nil : CGFloat.infinity, maxHeight: fillsRow ? CGFloat.infinity : nil)
            .background {
                if let team {
                    Rectangle()
                        .foregroundStyle(team.color)
                }
            }
    }

    /// The card's detail, in one style whatever the sort (B-17). In the
    /// carousel it keeps two lines' room, centred, so every card is the
    /// same height and the headshots line up; in the accessibility-size
    /// list it wraps freely beside the headshot.
    private var caption: some View {
        Text(PlayerCardLayout.caption(detail))
            .font(PlayerCardLayout.captionFont)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(fillsRow ? .leading : .center)
            .modifier(CaptionLines(fillsRow: fillsRow))
            .minimumScaleFactor(PlayerCardLayout.minimumScaleFactor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: PlayerCardLayout.width(scaledWidth: captionWidth, fillsRow: fillsRow))
            .frame(maxWidth: fillsRow ? CGFloat.infinity : nil, alignment: .leading)
            .padding(Theme.Spacing.s)
    }

    private var detail: String {
        switch state {
        case .name: player.name
        case .number: player.number
        case .position: player.position
        }
    }
}

/// Two lines in the carousel, kept even when the text needs one; unlimited
/// in a list row.
private struct CaptionLines: ViewModifier {
    let fillsRow: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let limit = PlayerCardLayout.lineLimit(fillsRow: fillsRow) {
            content.lineLimit(limit, reservesSpace: true)
        } else {
            content.lineLimit(nil)
        }
    }
}

/// A player's headshot in a circle, through `RemoteImage`'s cache. While it
/// loads, or where the feed has none, their initials stand in, in the ink
/// that reads on the team's colour (G-3).
private struct PlayerHeadshot: View {
    let url: String
    let name: String
    let team: TeamRef?
    let size: CGFloat

    var body: some View {
        RemoteImage(url: URL(string: url), showsProgress: false) {
            monogram
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        ZStack {
            Circle()
                .fill(.fill)
            // Proportional to the headshot, not to Dynamic Type: the
            // headshot already scales with the caption (B-3), as a crest's
            // monogram does.
            Text(PlayerCardLayout.initials(of: name))
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(size * 0.12)
                .modifier(MonogramInk(team: team))
        }
    }
}

/// The team's ink on its colour, or secondary text on the inset surface
/// where there's no team.
private struct MonogramInk: ViewModifier {
    let team: TeamRef?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let team {
            content.teamInk(on: team)
        } else {
            content.foregroundStyle(.secondary)
        }
    }
}

/// The placeholder card shown in a roster carousel before it has loaded:
/// the card's shape, its headshot and caption pulsing.
struct LoadingPlayerView: View {
    /// The card it stands in for, scaled the same way.
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var captionWidth = PlayerCardLayout.baseWidth
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var headshotSize = PlayerCardLayout.baseHeadshotSize

    var body: some View {
        VStack(spacing: 0) {
            LoadingViewCircle()
                .frame(width: headshotSize, height: headshotSize)
                .padding(Theme.Spacing.s)

            // Two caption lines' room, as the card keeps.
            Text(verbatim: "Placeholder")
                .font(PlayerCardLayout.captionFont)
                .lineLimit(2, reservesSpace: true)
                .hidden()
                .frame(width: captionWidth)
                .overlay(alignment: .top) {
                    LoadingView()
                        .frame(width: captionWidth * 0.8)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.s)
        }
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
    }
}
