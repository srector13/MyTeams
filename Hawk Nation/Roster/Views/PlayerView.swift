//
//  PlayerView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A player's card in a roster carousel: a round headshot with one line of
/// detail beneath it. A player no source has a photo of shows a grey
/// silhouette.
///
/// Which detail is shown follows the carousel's current sort, so ordering the
/// roster by number labels every card with its number.
struct PlayerCard<Player: RosterPlayer>: View {
    var player: Player
    var state: PlayerSort
    /// The roster's league, for the Wikimedia Commons fallback when ESPN
    /// has no headshot (`AthleteHeadshot`). `nil` keeps the silhouette.
    var league: LeagueID? = nil
    /// The roster's team, for the soccer photo sources that look players
    /// up by club (`AthleteHeadshot`). `nil` never asks them.
    var team: TeamRef? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The width the roster carousel gives the card, so four and a half
    /// fit across (`RosterPeek`, T3); `nil` elsewhere.
    @Environment(\.rosterCardWidth) private var rosterCardWidth

    /// The headshot, which scales with the caption under or beside it
    /// (B-3).
    @ScaledMetric(relativeTo: .caption) private var headshotSize: CGFloat = 60

    /// The caption's width in the carousel when it doesn't set one: a
    /// little wider than the headshot, so a long name wraps rather than
    /// widening the card (B-17).
    @ScaledMetric(relativeTo: .caption2) private var captionWidth: CGFloat = 80

    /// The headshot's side: its scaled size, never wider than the card.
    private var photoSize: CGFloat {
        guard !dynamicTypeSize.isAccessibilitySize, let rosterCardWidth else { return headshotSize }
        return min(headshotSize, rosterCardWidth)
    }

    var body: some View {
        // At accessibility text sizes the roster is a vertical list, so the
        // detail sits beside the headshot rather than under it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: 5))

        layout {
            AthleteHeadshot(player, league: league, team: team) {
                Image("blank")
                    .resizable()
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: photoSize, height: photoSize)
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
    /// keeps two lines' room, centred, so every card is the same height, at
    /// the card's width; in the accessibility-size list it wraps freely
    /// beside the headshot. A name, so label ink rather than grey.
    @ViewBuilder
    private func caption(_ text: String) -> some View {
        let label = Text(text.isEmpty ? "N/A" : text)
            .font(.caption2)
            .foregroundStyle(.primary)

        if dynamicTypeSize.isAccessibilitySize {
            label
        } else {
            label
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(width: rosterCardWidth ?? captionWidth)
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
