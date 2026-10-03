//
//  GameDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The band at the top of a game sheet left to the system grabber and the
/// close button floating over it: the button's 44 pt and its inset.
private let closeButtonClearance: CGFloat = 44 + Theme.Spacing.m

/// The sheet a schedule card opens: the venue, the scoreline and the box
/// score, refreshed while the game is live.
///
/// The box score comes through `LeagueDescriptor.downloadGameSheet`, which
/// reduces each sport's statistics to the same `BoxScore` rows, with a
/// linescore sized from the summary's format beneath the scoreline and, for
/// hockey and soccer, the sport's own player tables below. Each refresh
/// is one summary request, whose document fills the box score and the venue
/// alike; only a game with its clock running refreshes every ten seconds.
struct GameDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The venue header's height at the default text size; it grows with
    /// the text over it.
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 200

    /// The scoreboard's crests, which scale with the team names under them
    /// (B-3).
    @ScaledMetric(relativeTo: .subheadline) private var crestSize: CGFloat = 50

    let game: Game
    let team: TeamRef

    @State private var boxScore: BoxScore?
    @State private var linescore: Linescore?
    @State private var hockey: HockeyBoxScore?
    @State private var soccerLineups: SoccerLineups?
    @State private var gameInfo = GameInfo.empty
    @State private var loading = true

    /// Paces refreshes that produced no sheet: 30 seconds, doubling while
    /// ESPN throttles. See `PollBackoff`.
    @State private var backoff = PollBackoff(base: GameSheet.retryInterval)

    private var league: LeagueDescriptor { team.league.descriptor }

    /// The followed team's name beside its crest: the schedule feed's name
    /// for it, from the same field as the opponent's name opposite, or the
    /// catalog's short name when the feed gave none.
    private var teamLabel: String {
        game.team.isEmpty ? team.shortName : game.team
    }

    var body: some View {
        ScrollView(.vertical) {
            if loading {
                // The real header and scoreboard over placeholder data,
                // redacted (D-7): the placeholder can't drift from the
                // layout it stands in for.
                VStack {
                    header
                    card {
                        scoreboard(score: Self.placeholderScore)
                    }
                }
                .loadingPlaceholder()
            } else {
                VStack {
                    header

                    card {
                        if(game.cancelled) {
                            message("This game has been canceled.")
                        } else if (game.postponed) {
                            message("This game has been postponed.")
                        } else if game.dateAsDate <= Date(), let boxScore {
                            scoreboard(score: "\(boxScore.homeScore) - \(boxScore.awayScore)")

                            if let linescore {
                                LinescoreView(linescore: linescore)
                            }

                            ForEach(boxScore.rows) { row in
                                StatRowView(title: row.title, homeStat: row.home, awayStat: row.away)
                            }

                            // The sport's own tables, beneath the
                            // comparison rows every sport shares.
                            if let hockey {
                                HockeyBoxScoreView(boxScore: hockey)
                            }
                            if let soccerLineups {
                                SoccerLineupsView(lineups: soccerLineups)
                            }
                        } else {
                            message("No game statistics at this time. Please check back later.")
                        }
                    }
                }
            }

            Spacer()
        }
        .scrollIndicators(.hidden)
        // No background of its own: the system sheet draws the surface
        // (glass at the medium detent), and the venue header runs under the
        // grabber to the sheet's top edge.
        .overlay(alignment: .topTrailing) {
            SheetCloseButton()
                // Pinned to its 44 pt circle, as the crest picker's "+" is.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("gameDetail.close")
                .padding(Theme.Spacing.m)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .pollingTask {
            let load = await league.downloadGameSheet(
                gameID: game.gameID,
                team: team,
                followedIsHome: game.gameHome,
                competition: game.competition
            )
            guard let sheet = load.sheet else {
                // A cancelled request means the sheet closed: stop quietly.
                if case .failure(.cancelled) = load.response.result { return nil }
                // Keep the last good box score through a failed refresh.
                // With nothing loaded yet, show the "no statistics" message
                // rather than a blank sheet while retrying.
                if loading {
                    boxScore = nil
                    loading = false
                }
                return backoff.delay(after: load.response)
            }

            boxScore = sheet.boxScore
            linescore = sheet.linescore
            hockey = sheet.hockey
            soccerLineups = sheet.soccerLineups
            gameInfo = sheet.info
            loading = false
            backoff.reset()
            // A summary that stays fresh longer than the phase's interval is
            // not asked for again before it goes stale, within the backoff's
            // cap, so a long max-age cannot freeze a live sheet.
            return sheet.refreshInterval.map { interval in
                max(interval, min(load.response.maxAge ?? .zero, backoff.cap))
            }
        }
    }

    // MARK: - Header

    /// The venue behind the competition, kick-off, channel and location.
    ///
    /// At least `headerHeight` tall, and taller when the text needs it: the
    /// venue and its wash sit behind the text rather than fixing its height.
    /// The text starts below the grabber and close button; the venue runs
    /// on under them, and the sheet's own corners round it.
    private var header: some View {
        VStack(spacing: 0) {
            Text(game.competitionName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.top, closeButtonClearance)

            Spacer(minLength: Theme.Spacing.m)

            headerLine(game.time)
            headerLine(game.date)
            headerLine(game.channel)

            Spacer(minLength: Theme.Spacing.m)

            headerLine(venueLine)
        }
        .padding(.horizontal, 15)
        // Takes up the sheet's full width.
        .frame(maxWidth: .infinity, minHeight: headerHeight)
        .background {
            ZStack {
                if let backdrop = league.venueBackdropAsset {
                    Image(backdrop)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RemoteImage(url: URL(string: gameInfo.venueImage))
                        .id(gameInfo.venueImage)
                }

                scrim
            }
            // The fill image overflows the header: clip it to the header's
            // frame, then mirror what's left into any safe area beside it
            // (landscape), where `ignoresSafeArea` used to stretch it.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .backgroundExtensionEffect()
        }
    }

    /// The game's colour (black until the summary gives one) over the
    /// venue, weighted to the foot (D-5): the old flat 60% through the top
    /// third, deepening to 85% where the venue line sits over the busiest
    /// part of a stadium photo. Nowhere lighter than it was. Denser under
    /// Increase Contrast and opaque under Reduce Transparency (X-5), since
    /// the white header text sits on it.
    ///
    /// No radius of its own: the header runs to the sheet's top edge, whose
    /// corners round it concentric with the device, and its foot is
    /// full-bleed above the inset card (X-4's 10-inside-20 is gone).
    private var scrim: some View {
        ZStack {
            Color.black
            Color(hexString: gameInfo.gameColor)
        }
        .adaptiveGradientScrim([
            .init(opacity: 0.6, location: 0),
            .init(opacity: 0.6, location: 0.35),
            .init(opacity: 0.85, location: 1),
        ])
    }

    /// The venue, then its city and state where the league's summaries give
    /// them cleanly. See `LeagueDescriptor.venueBackdropAsset`.
    private var venueLine: String {
        league.venueBackdropAsset == nil
            ? "\(game.location) | \(gameInfo.city), \(gameInfo.state)"
            : game.location
    }

    private func headerLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.bottom, 10)
    }

    // MARK: - Card

    /// The rounded card under the header. Sized to its content (D-3): long
    /// hockey and soccer tables, and larger text, grow the card rather than
    /// overflowing a fixed one.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: 15) {
            content()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground), in: Theme.Radius.cardShape)
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: - Scoreboard

    /// The scoreline the loading placeholder lays out, redacted: two-digit
    /// scores, about the width of most.
    private static let placeholderScore = "00 - 00"

    /// Both crests and the scoreline (`score`, home first), home team on
    /// the left. At accessibility text sizes the scoreline sits above the
    /// two sides, so none of the three is squeezed into a third of the
    /// width.
    @ViewBuilder
    private func scoreboard(score: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.m) {
                scoreline(score)

                HStack(alignment: .top) {
                    side(followed: game.gameHome, alignment: .leading)
                    side(followed: !game.gameHome, alignment: .trailing)
                }
            }
        } else {
            HStack(alignment: .top) {
                HStack() {
                    side(followed: game.gameHome, alignment: .leading)

                    scoreline(score)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                    side(followed: !game.gameHome, alignment: .trailing)
                }
            }
        }
    }

    private func scoreline(_ score: String) -> some View {
        VStack(alignment: .center) {
            Text(score)
                .font(.title.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            status
        }
    }

    /// One team's crest over its name.
    private func side(followed: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            if followed {
                TeamLogo(team: team, size: crestSize)
            } else {
                RemoteImage(url: URL(string: game.opponentLogo)) {
                    Image("blankTeam")
                        .resizable()
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: crestSize, height: crestSize)
            }

            Text(followed ? teamLabel : game.opponent)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    /// "Final", "Halftime", or the period and clock beneath the scoreline.
    @ViewBuilder
    private var status: some View {
        if(game.completed) {
            statusLine("Final")
        } else if(game.gameHalftime) {
            statusLine("Halftime")
        } else {
            statusLine(league.liveCardPeriodLabel(game.gamePeriod))
            statusLine(game.gameClock)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
    }
}
