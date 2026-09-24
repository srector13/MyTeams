//
//  ChiefsHome.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct ChiefsHome: View {
    @State private var model = TeamModel<FootBallPlayer>(
        scheduleURL: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/12/schedule",
        teamName: "KC",
        newsURL: NewsFeed.chiefs,
        sport: .chiefs,
        loadRoster: downloadFootballRoster
    )

    private let teamColor = Team.chiefs.color

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                FootballPlayerView(player: player, state: model.sort)
            } detail: { player in
                FootballPlayerDetailView(player: player, teamColor: teamColor)
            } filterMenu: {
                Button("All") { model.filter() }

                Menu("Defense") {
                    unitButtons(
                        unit: "defense",
                        positions: [
                            "Cornerback", "Defensive End", "Defensive Tackle",
                            "Linebacker", "Safety",
                        ]
                    )
                }

                Menu("Offense") {
                    unitButtons(
                        unit: "offense",
                        positions: [
                            "Center", "Fullback", "Guard", "Quarterback",
                            "Running Back", "Offensive Tackle", "Tight End",
                            "Wide Receiver",
                        ],
                        // The menu shortens this one; the feed does not.
                        labels: ["Offensive Tackle": "Tackle"]
                    )
                }

                Menu("Special Teams") {
                    unitButtons(
                        unit: "specialTeam",
                        positions: ["Long Snapper", "Place Kicker", "Punter"]
                    )
                }
            }
            .padding(.top, 5)

            ScheduleSection(model: model) { game in
                FootballGameView(
                    game: game,
                    teamColor: teamColor,
                    teamLogo: Team.chiefs.logo,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                FootballGameDetailView(
                    game: game,
                    teamColor: teamColor,
                    teamLogo: Team.chiefs.logo
                )
            }

            NewsSection(model: model, teamColor: teamColor)
        }
        .task { await model.load() }
    }

    /// The filter entries for one unit of the roster: every player in it,
    /// then each position within it.
    @ViewBuilder
    private func unitButtons(
        unit: String,
        positions: [String],
        labels: [String: String] = [:]
    ) -> some View {
        Button("All") {
            model.filter { $0.team == unit }
        }

        ForEach(positions, id: \.self) { position in
            Button(labels[position] ?? position) {
                model.filter { $0.team == unit && $0.position == position }
            }
        }
    }
}

#Preview {
    ChiefsHome()
}
