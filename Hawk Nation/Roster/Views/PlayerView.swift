//
//  PlayerView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

/// How a roster card is sized and how its detail line wraps, worked out
/// apart from the view so the tests can drive it (as `GameCardContent` is
/// for a schedule card).
///
/// In the carousel the card has a fixed width, scaled with its text, and
/// the detail wraps to two lines rather than being cut off mid-word ("Andrew
/// Armstr"). At accessibility sizes, where the roster is a vertical list,
/// the card spans the row and its text takes as many lines as it needs.
enum PlayerCardLayout {
    /// The card's width at the default text size, in points: room for a
    /// long surname ("Armstrong", "Christensen") on a line of its own.
    static let baseWidth: CGFloat = 88

    /// The headshot's diameter at the default text size, in points.
    static let baseHeadshotSize: CGFloat = 60

    /// The largest the headshot grows beside the text in a list row; past
    /// this it crowds the name into breaking mid-word.
    static let maxRowHeadshotSize: CGFloat = 88

    /// The text style the card's size scales with: the name's and the
    /// position's, the card's longest text. Caption 2 grows faster than
    /// caption, so scaled by caption's ratio the name outgrew the card.
    static let metricsTextStyle: Font.TextStyle = .caption2

    /// `metricsTextStyle`, for measuring with UIKit.
    static var metricsUITextStyle: UIFont.TextStyle { .caption2 }

    /// Lines the detail may take: two in the carousel, as many as it needs
    /// in a list row.
    static func lineLimit(fillsRow: Bool) -> Int? {
        fillsRow ? nil : 2
    }

    /// How small a word too long for a line of its own may be drawn before
    /// it's cut off: a last resort, after wrapping.
    static let minimumScaleFactor: CGFloat = 0.8

    /// The card's width: `scaledWidth` in the carousel, none in a list row,
    /// which spans the row instead.
    static func width(scaledWidth: CGFloat, fillsRow: Bool) -> CGFloat? {
        fillsRow ? nil : scaledWidth
    }

    /// The headshot's diameter: `scaled` in the carousel, capped in a list
    /// row so the text beside it keeps room for a whole word per line.
    static func headshotSize(scaled: CGFloat, fillsRow: Bool) -> CGFloat {
        fillsRow ? min(scaled, maxRowHeadshotSize) : scaled
    }

    /// The card's width at `category`, as `@ScaledMetric` scales it.
    @MainActor
    static func scaledWidth(for category: UIContentSizeCategory) -> CGFloat {
        UIFontMetrics(forTextStyle: metricsUITextStyle)
            .scaledValue(for: baseWidth, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }
}

/// A player's card in a roster carousel: a round headshot with a line or
/// two of detail beneath it.
///
/// Which detail is shown follows the carousel's current sort, so ordering the
/// roster by number labels every card with its number. Sizing and wrapping
/// are `PlayerCardLayout`'s.
struct PlayerCard<Player: RosterPlayer>: View {
    var player: Player
    var state: PlayerSort

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The card and its headshot, which scale with the caption under or
    /// beside it (B-3).
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var cardWidth = PlayerCardLayout.baseWidth
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var headshotSize = PlayerCardLayout.baseHeadshotSize

    /// At accessibility text sizes the roster is a vertical list: the card
    /// fills a list row and sizes to its text.
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // In a list row the detail sits beside the headshot rather than
        // under it.
        let layout = fillsRow
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: 5))
        let headshot = PlayerCardLayout.headshotSize(scaled: headshotSize, fillsRow: fillsRow)

        layout {
            RemoteImage(url: URL(string: player.photo)) {
                Image("blank")
                    .resizable()
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: headshot, height: headshot)
            .clipShape(.circle)

            detail
                .multilineTextAlignment(fillsRow ? .leading : .center)
                .modifier(DetailLines(fillsRow: fillsRow))
                .minimumScaleFactor(PlayerCardLayout.minimumScaleFactor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: fillsRow ? CGFloat.infinity : nil, alignment: .leading)
        }
        .frame(width: PlayerCardLayout.width(scaledWidth: cardWidth, fillsRow: fillsRow))
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .name:
            Text(player.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .number:
            caption(player.number, font: .caption)
        case .position:
            caption(player.position, font: .caption2)
        }
    }

    /// A bold caption, falling back to "N/A" when the feed left the field out.
    private func caption(_ text: String, font: Font) -> some View {
        Text(text.isEmpty ? "N/A" : text)
            .font(font.bold())
            .foregroundStyle(.secondary)
    }
}

/// Two lines in the carousel, kept even when the text needs one so every
/// card is the same height and the headshots line up; unlimited in a list
/// row.
private struct DetailLines: ViewModifier {
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

/// The placeholder card shown in a roster carousel before it has loaded.
struct LoadingPlayerView: View {
    /// The card it stands in for, scaled the same way.
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var cardWidth = PlayerCardLayout.baseWidth
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var headshotSize = PlayerCardLayout.baseHeadshotSize
    @ScaledMetric(relativeTo: PlayerCardLayout.metricsTextStyle) private var lineHeight: CGFloat = 10

    var body: some View {
        VStack(spacing: 5) {
            LoadingViewCircle()
                .frame(width: headshotSize, height: headshotSize)

            LoadingView()
                .frame(width: cardWidth * 0.8, height: lineHeight)
        }
        .frame(width: cardWidth)
    }
}
