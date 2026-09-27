//
//  TeamHomeView.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// One team's page: its roster, schedule and news.
///
/// Everything that differs between teams comes from the `TeamRef` and its
/// league's `LeagueDescriptor`. The only branch is on the league's sport,
/// which decides the roster feed's shape and so the player type the page is
/// built around.
struct TeamHomeView: View {
    let team: TeamRef

    var body: some View {
        switch team.league.descriptor.kind {
        case .basketball: TeamHomeContent(team: team, loadRoster: downloadBasketballRoster(team:))
        case .football: TeamHomeContent(team: team, loadRoster: downloadFootballRoster(team:))
        case .baseball: TeamHomeContent(team: team, loadRoster: downloadBaseballRoster(team:))
        case .soccer: TeamHomeContent(team: team, loadRoster: downloadSoccerRoster(team:))
        case .other: EmptyView()
        }
    }
}

/// A team page for one sport's player type.
private struct TeamHomeContent<Player: PlayerSheetDescribing>: View {
    let team: TeamRef

    @State private var model: TeamModel<Player>

    init(
        team: TeamRef,
        loadRoster: @escaping @Sendable (TeamRef) async -> Result<[Player], NetworkError>
    ) {
        self.team = team
        _model = State(initialValue: TeamModel(
            team: team,
            newsURL: NewsFeed.url(for: team),
            loadRoster: loadRoster
        ))
    }

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                PlayerCard(player: player, state: model.sort)
            } detail: { player in
                PlayerDetailView(player: player, team: team)
            } filterMenu: {
                RosterFilterMenu(model: model, entries: team.league.descriptor.rosterFilters)
            }
            .padding(.top, 5)

            // The league's `RecordRule` decides how abandoned and unflagged
            // fixtures count in the record.
            ScheduleSection(model: model) { game in
                GameView(
                    game: game,
                    team: team,
                    liveScore: model.liveScores[game.gameID]
                )
            } detail: { game in
                GameDetailView(game: game, team: team)
            }

            NewsSection(model: model, teamColor: team.color)
        }
        .task { await model.load() }
    }
}

/// The roster's filter menu: "All", then the league's filters.
private struct RosterFilterMenu<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let entries: [RosterFilterEntry]

    var body: some View {
        Button("All") { model.filter() }

        ForEach(entries, id: \.self) { entry in
            switch entry {
            case .filter(let filter):
                button(filter)
            case .menu(let title, let filters):
                Menu(title) {
                    ForEach(filters, id: \.self) { filter in
                        button(filter)
                    }
                }
            }
        }
    }

    private func button(_ filter: RosterFilter) -> some View {
        Button(filter.label) {
            let unit = filter.unit
            let position = filter.position
            model.filter { player in
                (unit == nil || player.unit == unit)
                    && (position == nil || player.position == position)
            }
        }
    }
}

#Preview {
    TeamHomeView(team: TeamCatalog.seeded(league: .nfl, espnID: "12"))
}
