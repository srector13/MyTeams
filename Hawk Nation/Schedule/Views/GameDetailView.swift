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
/// hockey and soccer, the sport's own player tables below. The game's
/// story (`GameStoryView`: timeline, win probability, injuries) sits
/// between the linescore and the rows. Each refresh
/// is one summary request, whose document fills the box score and the venue
/// alike; only a game with its clock running refreshes every ten seconds.
struct GameDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

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
    /// The timeline, win probability and injuries (R-2).
    @State private var story = GameStory.empty
    @State private var gameInfo = GameInfo.empty
    /// The last status a summary gave; `nil` until one has (A-2).
    @State private var refreshedStatus: GameStatus?
    @State private var loading = true
    /// The lineup or box-score player whose sheet is open (C-6).
    @State private var sheetPlayer: GameSheetPlayer?
    /// The scoreboard as an image, for Share (R-3); `nil` until the game
    /// has a score.
    @State private var shareImage: Image?

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
                            scoreboard(
                                score: "\(boxScore.homeScore) - \(boxScore.awayScore)",
                                total: boxScore.homeScore + boxScore.awayScore
                            )

                            if let linescore {
                                LinescoreView(linescore: linescore)
                            }

                            // How the game went, before the figures.
                            storyView

                            ForEach(boxScore.rows) { row in
                                StatRowView(title: row.title, homeStat: row.home, awayStat: row.away)
                            }

                            // The sport's own tables, beneath the
                            // comparison rows every sport shares.
                            if let hockey {
                                HockeyBoxScoreView(boxScore: hockey, onPlayer: { sheetPlayer = $0 })
                            }
                            if let soccerLineups {
                                SoccerLineupsView(lineups: soccerLineups, onPlayer: { sheetPlayer = $0 })
                            }
                        } else {
                            message("No game statistics at this time. Please check back later.")
                            // A pre-game summary still carries injuries.
                            storyView
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
        .overlay(alignment: .topLeading) {
            if !loading {
                shareButton
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(Theme.Spacing.m)
            }
        }
        // Drawn again as the score or status changes.
        .onChange(of: shareLine, initial: true) {
            shareImage = renderShareImage()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The roster's player sheet, over this one. Its colours and the
        // league its statistics load from are the followed team's: both
        // sides of a game play in that league, and a summary names the
        // opponent by ESPN id only, with no `TeamRef` to draw it in.
        .sheet(item: $sheetPlayer) { player in
            switch player {
            case .soccer(let player):
                PlayerDetailView(player: player, team: team)
            case .hockey(let player):
                PlayerDetailView(player: player, team: team)
            }
        }
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
            story = sheet.story
            gameInfo = sheet.info
            // A summary with no status keeps the one already shown.
            if let status = sheet.status {
                refreshedStatus = status
            }
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

    // MARK: - Story

    /// The timeline, win probability and injuries, when the summary has any.
    /// A timeline row's player opens the sheet the lineup or box-score row
    /// for the same athlete id would (C-6).
    @ViewBuilder
    private var storyView: some View {
        if !story.isEmpty {
            GameStoryView(
                story: story,
                league: league,
                player: { [soccerLineups, hockey] athleteID in
                    GameSheetPlayer(athleteID: athleteID, soccerLineups: soccerLineups, hockey: hockey)
                },
                onPlayer: { sheetPlayer = $0 }
            )
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
            // No line for the parser's "TBD" (A-19), as on the cards.
            if let broadcast = GameCardContent.broadcast(of: game) {
                headerLine(broadcast)
            }

            Spacer(minLength: Theme.Spacing.m)

            if !venueLine.isEmpty {
                headerLine(venueLine)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
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

    /// How much of the game's colour tints the black scrim (B-2): a blend,
    /// not a replacement. Even a white host blends to #737373 at most,
    /// 4.7:1 under the white header text; at half, it would be 4.0:1.
    nonisolated static let teamWashOpacity = 0.45

    /// The game's colour, blended into black (B-2), over the venue,
    /// weighted to the foot (D-5): the old flat 60% through the top third,
    /// deepening to 85% where the venue line sits over the busiest part of
    /// a stadium photo. Nowhere lighter than it was. Denser under Increase
    /// Contrast and opaque under Reduce Transparency (X-5), since the white
    /// header text sits on it.
    ///
    /// No radius of its own: the header runs to the sheet's top edge, whose
    /// corners round it concentric with the device, and its foot is
    /// full-bleed above the inset card (X-4's 10-inside-20 is gone).
    private var scrim: some View {
        ZStack {
            Color.black
            Color(hexString: gameInfo.gameColor)
                .opacity(Self.teamWashOpacity)
        }
        .adaptiveGradientScrim([
            .init(opacity: 0.6, location: 0),
            .init(opacity: 0.6, location: 0.35),
            .init(opacity: 0.85, location: 1),
        ])
    }

    /// The venue, then its city and state where the league's summaries give
    /// them cleanly. See `LeagueDescriptor.venueBackdropAsset`. A finished
    /// game adds its attendance where the summary gives one.
    private var venueLine: String {
        let line = Self.formatVenueLine(
            location: game.location,
            city: gameInfo.city,
            state: gameInfo.state,
            showsAddress: league.venueBackdropAsset == nil
        )
        guard GameStatus.shown(refreshed: refreshedStatus, tapped: game).completed,
              let attendance = Self.formatAttendance(gameInfo.attendance) else { return line }
        return line.isEmpty ? attendance : "\(line) | \(attendance)"
    }

    /// "Att. 73,421" from the summary's attendance; `nil` when it is
    /// missing, zero or not a number.
    nonisolated static func formatAttendance(_ attendance: String, locale: Locale = .current) -> String? {
        guard let count = Int(attendance.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return nil }
        return "Att. \(count.formatted(.number.locale(locale)))"
    }

    /// "Venue | City, State" from the parts that aren't empty (A-19), so a
    /// summary that failed or gave no address leaves no "Venue | , ".
    /// Empty when there are none. `showsAddress` false gives the venue only.
    nonisolated static func formatVenueLine(location: String, city: String, state: String, showsAddress: Bool) -> String {
        func nonEmpty(_ parts: [String]) -> [String] {
            parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let address = showsAddress ? nonEmpty([city, state]).joined(separator: ", ") : ""
        return nonEmpty([location, address]).joined(separator: " | ")
    }

    private func headerLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.bottom, Theme.Spacing.s)
    }

    // MARK: - Card

    /// The rounded card under the header. Sized to its content (D-3): long
    /// hockey and soccer tables, and larger text, grow the card rather than
    /// overflowing a fixed one.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: Theme.Spacing.l) {
            content()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .contentCard()
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: - Scoreboard

    /// The scoreline the loading placeholder lays out, redacted: two-digit
    /// scores, about the width of most.
    private static let placeholderScore = "00 - 00"

    /// Both crests and the scoreline (`score`, home first), home team on
    /// the left. At accessibility text sizes the scoreline sits above the
    /// two sides, so none of the three is squeezed into a third of the
    /// width. `total`, both scores summed, rolls the scoreline's digits as
    /// a live game refreshes (X-12).
    @ViewBuilder
    private func scoreboard(score: String, total: Int = 0) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.m) {
                scoreline(score, total: total)

                HStack(alignment: .top) {
                    side(followed: game.gameHome, alignment: .leading)
                    side(followed: !game.gameHome, alignment: .trailing)
                }
            }
        } else {
            HStack(alignment: .top) {
                HStack() {
                    side(followed: game.gameHome, alignment: .leading)

                    scoreline(score, total: total)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                    side(followed: !game.gameHome, alignment: .trailing)
                }
            }
        }
    }

    private func scoreline(_ score: String, total: Int) -> some View {
        VStack(alignment: .center) {
            Text(score)
                .font(.title.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .scoreTransition(value: Double(total))

            status
        }
    }

    /// One team's crest over its name.
    private func side(followed: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Theme.Spacing.xs) {
            if followed {
                TeamLogo(team: team, size: crestSize)
            } else {
                // Fitted to its square, as `TeamLogo` and the schedule card
                // fit theirs: a filled wide crest spilled over the
                // scoreline (B-10).
                RemoteImage(url: URL(string: game.opponentLogo)) {
                    Image("blankTeam")
                        .resizable()
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: crestSize, height: crestSize)
            }

            Text(followed ? teamLabel : game.opponent)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    /// "Final", "Halftime", or the period and clock beneath the scoreline,
    /// from the refreshed summary, or the tapped game's until one loads
    /// (A-2).
    @ViewBuilder
    private var status: some View {
        let shown = GameStatus.shown(refreshed: refreshedStatus, tapped: game)
        if shown.completed {
            statusLine("Final")
        } else if shown.halftime {
            statusLine("Halftime")
        } else {
            statusLine(league.liveCardPeriodLabel(shown.period))
            statusLine(shown.clock)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .multilineTextAlignment(.center)
    }

    // MARK: - Share

    /// "Chiefs 27–24 Bills · Final": the scoreline as the card reads it,
    /// home side first, and its status; before a score, the matchup and
    /// date.
    private var shareLine: String {
        let left = game.gameHome ? teamLabel : game.opponent
        let right = game.gameHome ? game.opponent : teamLabel
        guard let boxScore, !game.cancelled, !game.postponed else {
            return "\(left) vs \(right) · \(game.date)"
        }
        let shown = GameStatus.shown(refreshed: refreshedStatus, tapped: game)
        let status: String
        if shown.completed {
            status = "Final"
        } else if shown.halftime {
            status = "Halftime"
        } else {
            status = [league.liveCardPeriodLabel(shown.period), shown.clock]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return "\(left) \(boxScore.homeScore)–\(boxScore.awayScore) \(right)" + (status.isEmpty ? "" : " · \(status)")
    }

    /// Shares the scoreboard image, the score line and the game's ESPN page:
    /// not a `myteams://` link, which means nothing without the app.
    @ViewBuilder
    private var shareButton: some View {
        let webURL = (game.competition ?? team.league).gameWebURL(gameID: game.gameID)
        let message = Text([shareLine, webURL?.absoluteString].compactMap { $0 }.joined(separator: "\n"))
        Group {
            if let shareImage {
                ShareLink(item: shareImage, message: message, preview: SharePreview(shareLine, image: shareImage)) {
                    shareLabel
                }
            } else if let webURL {
                ShareLink(item: webURL, message: message, preview: SharePreview(shareLine)) {
                    shareLabel
                }
            }
        }
        .buttonStyle(.plain)
        .glassChrome(in: Circle(), interactive: true)
        .accessibilityLabel("Share")
        .accessibilityIdentifier("gameDetail.share")
    }

    private var shareLabel: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
    }

    /// The scoreboard on a plain card, light, at the screen's scale.
    private func renderShareImage() -> Image? {
        guard let boxScore, !game.cancelled, !game.postponed else { return nil }
        let renderer = ImageRenderer(content:
            scoreboard(score: "\(boxScore.homeScore) - \(boxScore.awayScore)")
                .padding(Theme.Spacing.xl)
                .frame(width: 360)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = displayScale
        return renderer.cgImage.map { Image(decorative: $0, scale: displayScale) }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, 40)
    }
}
