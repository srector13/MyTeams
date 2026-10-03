//
//  LeadersViews.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The team page's leaders: the team's best player on each of its sport's
/// boards, and the button into the whole league's (`LeagueLeadersView`).
///
/// Reads the leaders from `TeamModel`, which loads them with the rest of
/// the page and keeps them, so a page coming back does not refetch them.
struct LeadersSection<Player: RosterPlayer>: View {
    let model: TeamModel<Player>
    let team: TeamRef

    @State private var showingLeague = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The team's leaders, one card per board that has one.
    private var leaderCards: [TeamLeader] {
        model.leaders.compactMap { board in
            board.rows.first.map { TeamLeader(board: board, row: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            SectionHeader(systemImage: "trophy", title: "Leaders") {
                // A standard glass control, like the other sections' header
                // menus (T-1), rather than bare text in the team colour,
                // whose contrast depended on the team (T-6). The glass draws
                // the ink, so it reads whatever the team colour; the chevron
                // says it opens somewhere.
                Button {
                    showingLeague = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("\(team.league.badge) Leaders")
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("leaders.league")
            }
            .padding([.leading, .top, .trailing])

            if model.leaders.isEmpty {
                switch model.leadersState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                case .loaded:
                    SectionStatusView(message: "No team leaders yet")
                        .frame(maxWidth: .infinity)
                case .failed:
                    SectionStatusView(message: "Couldn't load the team leaders") {
                        Task { await model.reloadLeaders() }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                // At accessibility text sizes the carousel becomes a list.
                StackedCarousel(items: leaderCards) { leader in
                    TeamLeaderCard(board: leader.board, row: leader.row, teamColor: team.color)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(leaderCards) { leader in
                            TeamLeaderCard(board: leader.board, row: leader.row, teamColor: team.color)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.l)
                }
                .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
        .contentCard()
        .sheet(isPresented: $showingLeague) {
            LeagueLeadersView(league: team.league, followedTeamID: team.espnID, teamColor: team.color)
        }
    }
}

/// A board and its top row, as the team page shows them.
private struct TeamLeader: Identifiable {
    let board: LeaderBoard
    let row: LeaderBoardRow

    var id: LeaderBoard.ID { board.id }
}

/// One board's leader on the team page: the figure, the label, the player.
///
/// A fixed-width card in the carousel, scaled with the text; a full-width
/// row in the accessibility-size list.
private struct TeamLeaderCard: View {
    let board: LeaderBoard
    let row: LeaderBoardRow
    let teamColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 110

    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 4) {
            LeaderHeadshot(url: row.leader.headshotURL, size: 56)

            Text(row.value)
                .font(Theme.Typography.statFigure)
                .foregroundStyle(teamColor)

            Text(board.label)
                .font(Theme.Typography.statLabel)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(row.leader.shortName.isEmpty ? row.leader.name : row.leader.shortName)
                .font(.footnote)
                .lineLimit(fillsRow ? nil : 1)
                .multilineTextAlignment(.center)
        }
        .frame(width: fillsRow ? nil : cardWidth)
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil)
        .padding(.vertical, 10)
        // Nested in the leaders section's card: the inner radius (X-4, T-6)
        // on the nested surface rather than a fixed gray.
        .background(Theme.Surface.insetCard, in: Theme.Radius.innerShape)
    }
}

/// A leader's headshot in a circle, or a silhouette when the feed has none.
private struct LeaderHeadshot: View {
    let url: String
    let size: CGFloat

    var body: some View {
        RemoteImage(url: URL(string: url), showsProgress: false) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.tertiary)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A league's leaderboards, as a sheet: each of its sport's boards, ten
/// deep, with the followed team's players picked out in its colour.
struct LeagueLeadersView: View {
    let league: LeagueID
    /// The ESPN id of the team whose players are highlighted, if any.
    var followedTeamID: String?
    var teamColor: Color = .accentColor

    @Environment(\.dismiss) private var dismiss

    @State private var leaders: StatLeaders?
    @State private var state: SectionLoadState = .loading

    private var boards: [LeaderBoard] {
        leaders.map { leaderBoards(from: $0, kind: league.descriptor.kind, depth: 10) } ?? []
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("\(league.descriptor.displayName) Leaders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task(id: league) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        let shown = boards
        if shown.isEmpty {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                SectionStatusView(message: "No leaders yet this season")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                SectionStatusView(message: "Couldn't load the leaders") {
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List {
                if let leaders, !leaders.seasonName.isEmpty {
                    Text(Self.caption(leaders))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(shown) { board in
                    Section {
                        ForEach(board.rows) { row in
                            LeaderRow(
                                row: row,
                                label: board.label,
                                followed: row.leader.teamID == followedTeamID,
                                teamColor: teamColor
                            )
                        }
                    } header: {
                        Text(board.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// "2025-26 · Regular Season". A soccer feed names its season type
    /// after the season ("2026-27 English Premier League" twice), so a
    /// repeat is dropped.
    private static func caption(_ leaders: StatLeaders) -> String {
        var parts = [leaders.seasonName]
        if leaders.seasonType != leaders.seasonName { parts.append(leaders.seasonType) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func load() async {
        if state == .failed { state = .loading }
        switch await downloadStatLeaders(league: league, depth: 10) {
        case .success(let loaded):
            leaders = loaded
            state = .loaded
        case .failure(.cancelled):
            break
        case .failure:
            if leaders == nil { state = .failed }
        }
    }
}

/// One row of a league leaderboard.
private struct LeaderRow: View {
    let row: LeaderBoardRow
    let label: String
    let followed: Bool
    let teamColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast

    /// The rank column, wide enough for "10" at the current text size.
    @ScaledMetric(relativeTo: .subheadline) private var rankWidth: CGFloat = 22

    /// At accessibility text sizes the figure moves under the player, so
    /// the name keeps the row's width.
    private var stacksFigure: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = stacksFigure
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: 10))

        layout {
            HStack(spacing: 10) {
                Text("\(row.rank)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: rankWidth, alignment: .trailing)

                LeaderHeadshot(url: row.leader.headshotURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(row.leader.name)
                            .font(Theme.Typography.body)
                            .fontWeight(followed ? .bold : .regular)
                            .lineLimit(stacksFigure ? nil : 1)

                        if followed {
                            FollowedMarker()
                        }
                    }

                    Text([row.leader.teamAbbreviation, row.leader.position].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)

                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(stacksFigure ? nil : 2)
                    }
                }
            }

            if !stacksFigure {
                Spacer()
            }

            VStack(alignment: stacksFigure ? .leading : .trailing, spacing: 0) {
                Text(row.value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // One VoiceOver element per row, which says when it's the
        // followed team's player rather than leaving that to bold type and
        // a wash (LL-2).
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(followed ? .isSelected : [])
        .listRowBackground(
            followed
                ? teamColor.opacity(Theme.selectionWashOpacity(contrast: contrast))
                : Theme.Surface.contentCard
        )
    }
}

#Preview {
    LeagueLeadersView(league: .nhl)
}
