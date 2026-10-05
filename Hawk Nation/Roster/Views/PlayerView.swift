//
//  PlayerView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A player's card in a roster carousel: a round headshot with one line of
/// detail beneath it.
///
/// Which detail is shown follows the carousel's current sort, so ordering the
/// roster by number labels every card with its number.
struct PlayerCard<Player: RosterPlayer>: View {
    var player: Player
    var state: PlayerSort

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The headshot, which scales with the caption under or beside it
    /// (B-3).
    @ScaledMetric(relativeTo: .caption) private var headshotSize: CGFloat = 60

    /// The caption's width in the carousel: a little wider than the
    /// headshot, so a long name wraps rather than widening the card (B-17).
    @ScaledMetric(relativeTo: .caption2) private var captionWidth: CGFloat = 80

    var body: some View {
        // At accessibility text sizes the roster is a vertical list, so the
        // detail sits beside the headshot rather than under it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: 5))

        layout {
            RemoteImage(url: URL(string: player.photo)) {
                Image("blank")
                    .resizable()
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: headshotSize, height: headshotSize)
            .clipShape(.circle)

            switch state {
            case .name:
                caption(player.name)
            case .number:
                caption(player.number)
            case .position:
                caption(player.position)
            }
        }
    }

    /// The card's caption, in one style whatever the sort (B-17), falling
    /// back to "N/A" when the feed left the field out. In the carousel it
    /// keeps two lines' room, centred, so every card is the same height; in
    /// the accessibility-size list it wraps freely beside the headshot.
    @ViewBuilder
    private func caption(_ text: String) -> some View {
        let label = Text(text.isEmpty ? "N/A" : text)
            .font(.caption2)
            .foregroundStyle(.secondary)

        if dynamicTypeSize.isAccessibilitySize {
            label
        } else {
            label
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(width: captionWidth)
        }
    }
}

/// The placeholder card shown in a roster carousel before it has loaded.
struct LoadingPlayerView: View {
    /// The headshot it stands in for, scaled the same way.
    @ScaledMetric(relativeTo: .caption) private var headshotSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 5) {
            LoadingViewCircle()
                .frame(width: headshotSize, height: headshotSize)

            LoadingView()
                .frame(width: 70, height: 10)
        }
    }
}
