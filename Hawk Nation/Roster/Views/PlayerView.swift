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

    var body: some View {
        VStack(spacing: 5) {
            RemoteImage(url: player.photo) {
                Image("blank")
                    .resizable()
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 60, height: 60)
            .clipShape(.circle)

            switch state {
            case .name:
                Text(player.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(uiColor: .systemGray))
            case .number:
                caption(player.number, size: 12)
            case .position:
                caption(player.position, size: 10)
            }
        }
    }

    /// A bold caption, falling back to "N/A" when the feed left the field out.
    private func caption(_ text: String, size: CGFloat) -> some View {
        Text(text.isEmpty ? "N/A" : text)
            .font(.system(size: size))
            .fontWeight(.bold)
            .foregroundStyle(Color(uiColor: .systemGray))
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

typealias PlayerView = PlayerCard<BasketballPlayer>
typealias FootballPlayerView = PlayerCard<FootBallPlayer>
typealias BaseballPlayerView = PlayerCard<BaseballPlayer>
typealias SoccerPlayerView = PlayerCard<SoccerPlayer>
