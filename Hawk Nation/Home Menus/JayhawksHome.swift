//
//  JayhawksHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct JayhawksHome: View {
    @State private var model = TeamModel<BasketballPlayer>(
        team: .jayhawks,
        newsURL: NewsFeed.jayhawks,
        loadRoster: downloadBasketballRoster
    )

    private let teamColor = Team.jayhawks.color

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                PlayerView(player: player, state: model.sort)
            } detail: { player in
                BasketballPlayerDetailView(player: player)
            } filterMenu: {
                Button("All") { model.filter() }
                Button("Forwards") { model.filter { $0.position == "Forward" } }
                Button("Guards") { model.filter { $0.position == "Guard" } }
            }
            .padding(.top, 5)

            ScheduleSection(model: model) { game in
                GameView(
                    game: game,
                    teamColor: teamColor,
                    team: .jayhawks,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                BasketballGameDetailView(
                    game: game,
                    teamColor: teamColor,
                    team: .jayhawks
                )
            }

            NewsSection(model: model, teamColor: teamColor)
        }
        .task { await model.load() }
    }
}

#Preview {
    JayhawksHome()
}
