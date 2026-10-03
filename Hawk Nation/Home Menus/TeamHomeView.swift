//
//  TeamHomeView.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// One team's page: its roster, schedule, league standings, stat leaders
/// and news.
///
/// Everything that differs between teams comes from the `TeamRef` and its
/// league's `LeagueDescriptor`. The only branch is on the league's sport,
/// which decides the roster feed's shape and so the player type the page is
/// built around.
struct TeamHomeView: View {
    let team: TeamRef
    /// Keeps the page's model while the page is not mounted.
    let pages: TeamPages

    var body: some View {
        switch team.league.descriptor.kind {
        case .basketball: TeamHomeContent(team: team, model: pages.model(for: team, loadRoster: downloadBasketballRoster(team:)))
        case .football: TeamHomeContent(team: team, model: pages.model(for: team, loadRoster: downloadFootballRoster(team:)))
        case .baseball: TeamHomeContent(team: team, model: pages.model(for: team, loadRoster: downloadBaseballRoster(team:)))
        case .soccer: TeamHomeContent(team: team, model: pages.model(for: team, loadRoster: downloadSoccerRoster(team:)))
        case .hockey: TeamHomeContent(team: team, model: pages.model(for: team, loadRoster: downloadHockeyRoster(team:)))
        case .other: EmptyView()
        }
    }
}

/// The team pages' state that outlives the pages themselves.
///
/// `Home` mounts only the selected team's page. Each team's model is kept
/// here, so a page that comes back shows what it had loaded at once and
/// fetches only its schedule again; so is its scroll offset, which the page
/// restores. Deliberately not observable: nothing redraws when an entry is
/// added or a scroll offset is recorded.
@MainActor
final class TeamPages {
    private var models: [TeamRef.ID: AnyObject] = [:]
    private var scrollOffsets: [TeamRef.ID: CGFloat] = [:]

    /// The team's model, made on first use.
    func model<Player: RosterPlayer>(
        for team: TeamRef,
        loadRoster: @escaping @Sendable (TeamRef) async -> Result<[Player], NetworkError>
    ) -> TeamModel<Player> {
        if let model = models[team.id] as? TeamModel<Player> {
            return model
        }
        let model = TeamModel(team: team, newsURL: team.newsURL, loadRoster: loadRoster)
        models[team.id] = model
        return model
    }

    /// How far down the reader left the team's page, in points.
    func scrollOffset(for teamID: TeamRef.ID) -> CGFloat {
        scrollOffsets[teamID] ?? 0
    }

    func setScrollOffset(_ offset: CGFloat, for teamID: TeamRef.ID) {
        scrollOffsets[teamID] = offset
    }

    /// Forgets every team but `teamIDs`, such as one just unfollowed.
    func retain(_ teamIDs: [TeamRef.ID]) {
        let kept = Set(teamIDs)
        models = models.filter { kept.contains($0.key) }
        scrollOffsets = scrollOffsets.filter { kept.contains($0.key) }
    }
}

/// A team page for one sport's player type.
private struct TeamHomeContent<Player: PlayerSheetDescribing>: View {
    let team: TeamRef
    /// Owned by `TeamPages`, so it outlives this view.
    let model: TeamModel<Player>

    var body: some View {
        TeamHomeLayout {
            RosterSection(model: model) { player in
                PlayerCard(player: player, state: model.sort)
            } detail: { player in
                PlayerDetailView(player: player, team: team)
            } filterMenu: {
                RosterFilterMenu(model: model, entries: team.league.descriptor.rosterFilters)
            }

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

            StandingsSection(model: model, team: team)

            // The team's stat leaders, and the way into the league's.
            LeadersSection(model: model, team: team)

            NewsSection(model: model, teamColor: team.color)
        }
        // `Home` mounts only the selected team's page, so this runs — and
        // polls — only while the team is selected: a new selection is a new
        // page, and the old page's task is cancelled with it.
        .task(id: team.id) { await model.load() }
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
    TeamHomeView(team: TeamCatalog.seeded(league: .nfl, espnID: "12"), pages: TeamPages())
}
