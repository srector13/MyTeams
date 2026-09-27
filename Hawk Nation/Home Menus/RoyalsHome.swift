//
//  RoyalsHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct RoyalsHome: View {
    let team: TeamRef

    @State private var model: TeamModel<BaseballPlayer>

    init(team: TeamRef) {
        self.team = team
        _model = State(initialValue: TeamModel(
            team: team,
            newsURL: NewsFeed.royals,
            loadRoster: downloadBaseballRoster(team:)
        ))
    }

    private var teamColor: Color { team.color }

    private let positions = [
        "Catcher", "Center Fielder", "First Baseman", "Relief Pitcher",
        "Second Baseman", "Shortstop", "Starting Pitcher", "Third Baseman",
    ]

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                BaseballPlayerView(player: player, state: model.sort)
            } detail: { player in
                BaseballPlayerDetailView(player: player, teamColor: teamColor, team: team)
            } filterMenu: {
                Button("All") { model.filter() }

                ForEach(positions, id: \.self) { position in
                    Button(position) {
                        model.filter { $0.position == position }
                    }
                }
            }
            .padding(.top, 5)

            // MLB counts cancelled and postponed fixtures in the losses
            // column (`RecordRule.countsAbandonedGamesAsLosses`); the other
            // leagues exclude them.
            ScheduleSection(model: model) { game in
                GameView(
                    game: game,
                    teamColor: teamColor,
                    team: team,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                BaseballGameDetailView(
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
    RoyalsHome(team: TeamCatalog.seeded(league: .mlb, espnID: "7"))
}
