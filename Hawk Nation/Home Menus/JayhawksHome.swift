//
//  JayhawksHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct JayhawksHome: View {
    let team: TeamRef

    @State private var model: TeamModel<BasketballPlayer>

    init(team: TeamRef) {
        self.team = team
        _model = State(initialValue: TeamModel(
            team: team,
            newsURL: NewsFeed.jayhawks,
            loadRoster: downloadBasketballRoster(team:)
        ))
    }

    private var teamColor: Color { team.color }

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                PlayerView(player: player, state: model.sort)
            } detail: { player in
                BasketballPlayerDetailView(player: player, team: team)
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
                    team: team,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                BasketballGameDetailView(
                    game: game,
                    teamColor: teamColor,
                    team: team
                )
            }

            NewsSection(model: model, teamColor: teamColor)
        }
        .task { await model.load() }
    }
}

#Preview {
    JayhawksHome(team: TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305"))
}
