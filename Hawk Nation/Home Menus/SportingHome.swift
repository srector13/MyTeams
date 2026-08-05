//
//  SportingHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct SportingHome: View {
    @State private var model = TeamModel<SoccerPlayer>(
        scheduleURL: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.1/teams/186/schedule",
        teamName: "Kansas City",
        teamNameField: .shortDisplayName,
        newsURL: NewsFeed.sporting,
        // MLS fixtures carry no completion flag, so the next game is found by
        // kick-off time instead.
        usesDateForNextGame: true,
        loadRoster: downloadSoccerRoster
    )

    private let teamColor = Team.sporting.color

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
                SoccerPlayerDetailView(player: player, teamColor: teamColor)
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
                GameView(game: game, teamColor: teamColor, teamLogo: Team.sporting.logo)
            } detail: { game in
                SoccerGameDetailView(
                    game: game,
                    teamColor: teamColor,
                    teamLogo: Team.sporting.logo
                )
            }

            NewsSection(model: model, teamColor: teamColor)
        }
        .task { await model.load() }
    }
}

#Preview {
    SportingHome()
}
