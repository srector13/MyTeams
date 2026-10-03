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
            .frame(width: 60, height: 60)
            .clipShape(.circle)

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
    }

    /// A bold caption, falling back to "N/A" when the feed left the field out.
    private func caption(_ text: String, font: Font) -> some View {
        Text(text.isEmpty ? "N/A" : text)
            .font(font.bold())
            .foregroundStyle(.secondary)
    }
}

/// The placeholder card shown in a roster carousel before it has loaded.
struct LoadingPlayerView: View {
    var body: some View {
        VStack(spacing: 5) {
            LoadingViewCircle()
                .frame(width: 60, height: 60)

            LoadingView()
                .frame(width: 70, height: 10)
        }
    }
}
