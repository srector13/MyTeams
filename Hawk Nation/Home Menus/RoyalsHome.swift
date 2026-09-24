//
//  RoyalsHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct RoyalsHome: View {
    @State private var model = TeamModel<BaseballPlayer>(
        scheduleURL: "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/7/schedule",
        teamName: "Royals",
        teamNameField: .shortDisplayName,
        newsURL: NewsFeed.royals,
        sport: .royals,
        loadRoster: downloadBaseballRoster
    )

    private let teamColor = Team.royals.color

    private let positions = [
        "Catcher", "Center Fielder", "First Baseman", "Relief Pitcher",
        "Second Baseman", "Shortstop", "Starting Pitcher", "Third Baseman",
    ]

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                BaseballPlayerView(player: player, state: model.sort)
            } detail: { player in
                BaseballPlayerDetailView(player: player, teamColor: teamColor)
            } filterMenu: {
                Button("All") { model.filter() }

                ForEach(positions, id: \.self) { position in
                    Button(position) {
                        model.filter { $0.position == position }
                    }
                }
            }
            .padding(.top, 5)

            // The other three tabs exclude cancelled and postponed fixtures
            // from the losses column; this one never has. Kept as-is rather
            // than quietly changing a displayed record.
            ScheduleSection(model: model, countsAbandonedGamesAsLosses: true) { game in
                GameView(
                    game: game,
                    teamColor: teamColor,
                    teamLogo: Team.royals.logo,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                BaseballGameDetailView(
                    game: game,
                    teamColor: teamColor,
                    teamLogo: Team.royals.logo
                )
            }

            NewsSection(model: model, teamColor: teamColor)
        }
        .task { await model.load() }
    }
}

#Preview {
    RoyalsHome()
}
