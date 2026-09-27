//
//  SportingHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct SportingHome: View {
    let team: TeamRef

    // MLS completion flags lag or never arrive, so the next game also walks
    // past kick-off times (`RecordRule.usesDateForNextGame`).
    @State private var model: TeamModel<SoccerPlayer>

    init(team: TeamRef) {
        self.team = team
        _model = State(initialValue: TeamModel(
            team: team,
            newsURL: NewsFeed.sporting,
            loadRoster: downloadSoccerRoster(team:)
        ))
    }

    private var teamColor: Color { team.color }

    /// The menu labels the app uses for each playing position.
    private let positions: KeyValuePairs<String, String> = [
        "Goalkeeper": "Goalkeeper",
        "Defender": "Defense",
        "Midfielder": "Midfield",
        "Forward": "Attacker",
    ]

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                SoccerPlayerView(player: player, state: model.sort)
            } detail: { player in
                SoccerPlayerDetailView(player: player, teamColor: teamColor, team: team)
            } filterMenu: {
                Button("All") { model.filter() }

                ForEach(positions, id: \.key) { position, label in
                    Button(label) {
                        model.filter { $0.position == position }
                    }
                }
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
                SoccerGameDetailView(
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
    SportingHome(team: TeamCatalog.seeded(league: .mls, espnID: "186"))
}
