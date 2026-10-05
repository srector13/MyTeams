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

    /// A leader tapped on the league's boards, whose team's page opens
    /// once the boards' sheet is down (t_8d15e070).
    @State private var pickedLeader: StatLeader?

    /// Opens a leader's team page and their sheet on it; absent in
    /// previews.
    @Environment(TeamNavigator.self) private var navigator: TeamNavigator?

    /// The team colour as a fill, with a fallback for a team the feed gave
    /// no colour, which would otherwise draw clear (B-3).
    private var teamFill: Color { Color(hexString: TeamColors.fillHex(for: team)) }

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
                    leaderButton(leader)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(leaderCards) { leader in
                            leaderButton(leader)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, Theme.Spacing.l)
                }
                .contentMargins(.horizontal, Theme.Spacing.l, for: .scrollContent)
                // Comes to rest on a card's leading edge, as the roster and
                // schedule carousels do (T-8).
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
        .contentCard()
        // A leader picked on the boards opens once the sheet is down, so
        // their player sheet never races this one's dismissal.
        .sheet(isPresented: $showingLeague, onDismiss: { openPickedLeader() }) {
            LeagueLeadersView(
                league: team.league,
                followedTeamID: team.espnID,
                teamColor: teamFill,
                onPick: { pickedLeader = $0 }
            )
        }
    }

    /// A team leader's card, which opens their player sheet on this page
    /// (`TeamNavigator`).
    @ViewBuilder
    private func leaderButton(_ leader: TeamLeader) -> some View {
        let card = TeamLeaderCard(board: leader.board, row: leader.row, teamColor: teamFill)
        if let navigator, !leader.row.leader.athleteID.isEmpty {
            Button {
                navigator.open(team, playerID: leader.row.leader.athleteID)
            } label: {
                card.contentShape(Theme.Radius.innerShape)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the player.")
            .accessibilityIdentifier("leaders.card.\(leader.row.leader.athleteID)")
        } else {
            card
        }
    }

    /// Opens the team page of the leader picked on the league's boards,
    /// with their player sheet on it: this page for one of this team's
    /// players, a favorite's tab, or the team's page pushed over this one.
    private func openPickedLeader() {
        guard let leader = pickedLeader, let navigator else { return }
        pickedLeader = nil
        if leader.teamID == team.espnID {
            navigator.open(team, playerID: leader.athleteID)
        } else {
            navigator.open(
                teamID: TeamRef.id(league: team.league, espnID: leader.teamID),
                playerID: leader.athleteID
            )
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

    /// The headshot, scaled with the card and its text (B-3).
    @ScaledMetric(relativeTo: .body) private var headshotSize: CGFloat = 56

    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 4) {
            LeaderHeadshot(url: row.leader.headshotURL, size: headshotSize)

            // Label ink on the inset card, the team colour as an accent
            // bar beside it: a navy or gold figure vanished in one
            // appearance or the other (B-3).
            HStack(spacing: Theme.Spacing.s) {
                TeamAccentBar(color: teamColor)
                Text(row.value)
                    .font(Theme.Typography.statFigure)
            }
            .fixedSize(horizontal: false, vertical: true)

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

/// The team colour beside a figure or title drawn in label ink: a thin
/// capsule as tall as the text, for the leader cards and the player
/// sheet's section titles (B-3). Put it in an `HStack` sized to its text
/// (`fixedSize(horizontal: false, vertical: true)`). Decorative, so
/// VoiceOver skips it.
struct TeamAccentBar: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: Theme.Spacing.xs)
            .accessibilityHidden(true)
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
    /// Given, a row is a button that hands its leader here and closes the
    /// sheet, so the presenter can open their team's page (t_8d15e070).
    var onPick: ((StatLeader) -> Void)? = nil

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
                // The season under the title, rather than in a bare first
                // row of the list (LL-3).
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // Read-only: nothing to confirm, so it closes, as
                        // the system's glass xmark (X-8).
                        Button(role: .close) {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .accessibilityIdentifier("leagueLeaders.close")
                    }
                }
        }
        // Full height: ten-deep boards are a long list (X-9).
        .presentationDetents([.large])
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
                ForEach(shown) { board in
                    Section {
                        ForEach(board.rows) { row in
                            leaderRow(row, label: board.label)
                        }
                    } header: {
                        Text(board.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// A board's row: a button to the leader's team page and their player
    /// sheet on it (`onPick`), for a leader the feed gave a team.
    private func leaderRow(_ row: LeaderBoardRow, label: String) -> some View {
        let followed = row.leader.teamID == followedTeamID
        let content = LeaderRow(row: row, label: label, followed: followed)
        return Group {
            if let onPick, Self.canPick(row.leader) {
                Button {
                    onPick(row.leader)
                    dismiss()
                } label: {
                    content.contentShape(.rect)
                }
                // Label ink, not the tint: it reads as the row it was.
                .buttonStyle(.plain)
                .accessibilityHint("Opens the player on their team's page.")
                .accessibilityIdentifier("leagueLeaders.row.\(row.leader.athleteID)")
            } else {
                content
            }
        }
        .modifier(LeaderRowBackground(followed: followed, teamColor: teamColor))
    }

    /// Whether a leader names both themself and their team, which opening
    /// their team's page and player sheet needs.
    static func canPick(_ leader: StatLeader) -> Bool {
        !leader.athleteID.isEmpty && !leader.teamID.isEmpty
    }

    /// The season caption, once the leaders have loaded; empty until then,
    /// which shows no subtitle.
    private var subtitle: String {
        guard let leaders, !leaders.seasonName.isEmpty else { return "" }
        return Self.caption(leaders)
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

/// One row of a league leaderboard. Its background is the row's
/// (`LeaderRowBackground`).
private struct LeaderRow: View {
    let row: LeaderBoardRow
    let label: String
    let followed: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The rank column, wide enough for "10" at the current text size.
    @ScaledMetric(relativeTo: .subheadline) private var rankWidth: CGFloat = 22

    /// The headshot, which scales with the player's name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var headshotSize: CGFloat = 36

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

                LeaderHeadshot(url: row.leader.headshotURL, size: headshotSize)

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
    }
}

/// A leaderboard row's background: the followed team's players picked out
/// in its colour. On the row itself, which may be a button around a
/// `LeaderRow` (`LeagueLeadersView.leaderRow`), where the list reads it.
private struct LeaderRowBackground: ViewModifier {
    let followed: Bool
    let teamColor: Color

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.listRowBackground(
            followed
                ? teamColor.opacity(Theme.selectionWashOpacity(contrast: contrast))
                : Theme.Surface.contentCard
        )
    }
}

#Preview {
    LeagueLeadersView(league: .nhl)
}
