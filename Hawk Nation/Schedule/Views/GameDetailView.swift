//
//  GameDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The band at the top of a game sheet left to the system grabber and the
/// share and close buttons floating over the venue: a button's 44 pt and
/// its inset.
private let sheetButtonClearance: CGFloat = 44 + Theme.Spacing.m

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The venue header's height at the default text size, the buttons'
    /// band included; it grows with the text over it. Short enough that the
    /// medium detent shows the scoreboard and linescore beneath it.
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 196

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
    /// Whether the venue header has scrolled up under the buttons, which
    /// then take a bar of their own so the figures pass behind it.
    @State private var scrolledPastHeader = false
    /// The header text's height, which its dark ground is sized to (G1).
    @State private var headerTextHeight: CGFloat = 0

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

    /// The opponent's side in the summary's header: its abbreviation and
    /// colours. `nil` until a summary lists it.
    private var opponentSide: GameStory.Side? {
        story.side(homeAway: game.gameHome ? "away" : "home")
    }

    /// The followed team's column heading over the comparison rows: the
    /// feed's abbreviation where the summary gave one, else its name.
    private var teamColumnLabel: String {
        let line = linescore.map { game.gameHome ? $0.home : $0.away }
        let abbreviation = game.gameHome ? story.homeAbbreviation : story.awayAbbreviation
        return [line?.abbreviation ?? "", abbreviation].first { !$0.isEmpty } ?? teamLabel
    }

    /// The opponent's column heading, as `teamColumnLabel`.
    private var opponentColumnLabel: String {
        let line = linescore.map { game.gameHome ? $0.away : $0.home }
        return [line?.abbreviation ?? "", opponentSide?.abbreviation ?? ""].first { !$0.isEmpty } ?? game.opponent
    }

    /// The followed team's accent for marks on the card (F3): the paired
    /// stat bars and the win-probability line.
    private var teamAccent: Color { TeamColors.accent(for: team) }

    /// The opponent's accent, from the colours the summary's header gives
    /// it; a neutral grey when it gives none, rather than a made-up colour.
    private var opponentAccent: Color {
        guard let side = opponentSide, !side.color.isEmpty else { return Color(uiColor: .systemGray3) }
        let standIn = TeamRef(
            league: team.league,
            espnID: game.opponentID.isEmpty ? game.opponent : game.opponentID,
            displayName: game.opponent, shortName: game.opponent,
            abbreviation: side.abbreviation, location: "",
            colorHex: side.color, alternateColorHex: side.alternateColor,
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        return TeamColors.accent(for: standIn)
    }

    /// Whether the game is over, by the refreshed status or the tapped one.
    private var isFinal: Bool {
        GameStatus.shown(refreshed: refreshedStatus, tapped: game).completed
    }

    /// The box score's two scores, the followed team's first (F5).
    private func scores(_ boxScore: BoxScore) -> (team: Int, opponent: Int) {
        game.gameHome
            ? (boxScore.homeScore, boxScore.awayScore)
            : (boxScore.awayScore, boxScore.homeScore)
    }

    /// Medium and large on iPhone; large alone in regular width, where the
    /// medium detent left a small form sheet showing only the scoreboard.
    /// An iPad form sheet can report a compact width to its content, so
    /// the idiom decides there too.
    private var detents: Set<PresentationDetent> {
        if horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad {
            return [.large]
        }
        return [.medium, .large]
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
                        scoreboard(team: Self.placeholderScore, opponent: Self.placeholderScore)
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
                            let score = scores(boxScore)
                            scoreboard(team: "\(score.team)", opponent: "\(score.opponent)")

                            if let linescore {
                                LinescoreView(linescore: linescore, followedIsHome: game.gameHome)
                            }

                            // How the game went, before the figures.
                            storyView

                            if !boxScore.rows.isEmpty {
                                teamStats(boxScore.rows)
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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > headerHeight - sheetButtonClearance
        } action: { _, past in
            scrolledPastHeader = past
        }
        // No background of its own: the system sheet draws the surface
        // (glass at the medium detent), and the venue runs under the
        // grabber and the buttons to the sheet's top edge. Once the venue
        // has scrolled away, the buttons take a bar, so the figures pass
        // behind it rather than under bare glass.
        .overlay(alignment: .top) {
            HStack(alignment: .top) {
                if !loading {
                    shareButton
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                Spacer(minLength: 0)
                SheetCloseButton()
                    // Pinned to its 44 pt circle, as the crest picker's "+" is.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("gameDetail.close")
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xs)
            .background {
                if scrolledPastHeader {
                    Rectangle()
                        .fill(.bar)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: scrolledPastHeader)
        }
        // Drawn again as the score or status changes.
        .onChange(of: shareLine, initial: true) {
            shareImage = renderShareImage()
        }
        .presentationDetents(detents)
        // A page-sized sheet on iPad, not the small form sheet.
        .presentationSizing(.page)
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
                followedIsHome: game.gameHome,
                accent: teamAccent,
                player: { [soccerLineups, hockey] athleteID in
                    GameSheetPlayer(athleteID: athleteID, soccerLineups: soccerLineups, hockey: hockey)
                },
                onPlayer: { sheetPlayer = $0 }
            )
        }
    }

    // MARK: - Header

    /// "Chiefs @ Raiders" away, "Chiefs vs Chargers" at home or at a neutral
    /// site (G1): the short names, the followed team's first, which fit on
    /// a line where the event's full names ("Kansas City Chiefs at Las
    /// Vegas Raiders") wrapped. One name alone when the other is missing;
    /// empty when both are.
    nonisolated static func formatTitle(team: String, opponent: String, followedIsHome: Bool, neutralSite: Bool) -> String {
        let team = team.trimmingCharacters(in: .whitespacesAndNewlines)
        let opponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !team.isEmpty, !opponent.isEmpty else { return team.isEmpty ? opponent : team }
        let joiner = followedIsHome || neutralSite ? "vs" : "@"
        return "\(team) \(joiner) \(opponent)"
    }

    /// The header's title: `formatTitle`, or the event's own name when the
    /// feed named neither side.
    private var title: String {
        let title = Self.formatTitle(
            team: teamLabel,
            opponent: game.opponent,
            followedIsHome: game.gameHome,
            neutralSite: game.neutralSite
        )
        return title.isEmpty ? game.competitionName : title
    }

    /// "Sun, Oct 4 · 8:25 PM · CBS": the sheet's one date style (the
    /// schedule's `GameCardContent.fullDate`, with the year only when it
    /// isn't this one), the start time and the channel on one line (G1).
    /// No date for a game the feed gave none; no channel for the parser's
    /// "TBD" (A-19).
    private var whenLine: String {
        var parts: [String] = []
        if !game.date.isEmpty {
            parts.append(GameCardContent.fullStart(of: game.dateAsDate, now: .now))
        }
        if let broadcast = GameCardContent.broadcast(of: game) {
            parts.append(broadcast)
        }
        return parts.joined(separator: " · ")
    }

    /// How far the text's dark ground fades in above the text.
    private static let textScrimFade: CGFloat = 48

    /// The dark ground's strength where the text begins, held or deepened
    /// beneath it. White text over a white stadium photo under black at
    /// this strength reads at 4.7:1, so the header reads on any photo (G1).
    nonisolated static let textScrimOpacity = 0.55

    /// The ground's strength at the header's foot, under the venue line.
    nonisolated static let textScrimFootOpacity = 0.8

    /// The text's dark ground (G1), `textHeight` tall plus `fade` above it:
    /// clear at its top, `textScrimOpacity` where the text starts, and
    /// `textScrimFootOpacity` at the foot. Drawn through
    /// `adaptiveGradientScrim`, so Increase Contrast deepens it and Reduce
    /// Transparency makes it opaque (X-5).
    nonisolated static func textScrimStops(textHeight: CGFloat, fade: CGFloat) -> [Theme.ScrimStop] {
        let total = max(textHeight, 0) + max(fade, 0)
        let textTop = total > 0 ? min(max(fade / total, 0), 1) : 0
        return [
            Theme.ScrimStop(opacity: 0, location: 0),
            Theme.ScrimStop(opacity: textScrimOpacity, location: textTop),
            Theme.ScrimStop(opacity: textScrimFootOpacity, location: 1),
        ]
    }

    /// A light shade under the grabber and the floating buttons, which
    /// are glass of their own; the photo shows clear between it and the
    /// text's ground.
    private static let topScrimStops = [
        Theme.ScrimStop(opacity: 0.3, location: 0),
        Theme.ScrimStop(opacity: 0, location: 1),
    ]

    /// The venue behind the matchup, the start and channel, and the venue's
    /// name and place (G1).
    ///
    /// At least `headerHeight` tall, and taller when the text needs it: the
    /// venue and its scrims sit behind the text rather than fixing its
    /// height. The venue runs to the sheet's top edge, under the grabber and
    /// the buttons; the text sits at its foot, left-aligned, on a dark
    /// ground that fades in above it.
    private var header: some View {
        VStack(spacing: 0) {
            // Below the grabber and the buttons; the venue runs on under
            // them.
            Spacer(minLength: sheetButtonClearance)

            headerText
        }
        // Takes up the sheet's full width; the text sits at the foot.
        .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .bottom)
        .background {
            ZStack(alignment: .bottom) {
                venueImage
                    // The fill image overflows the header: clip it to the
                    // header's frame.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                Color.black
                    .adaptiveGradientScrim(Self.topScrimStops)
                    .frame(height: sheetButtonClearance + Theme.Spacing.l)
                    .frame(maxHeight: .infinity, alignment: .top)

                Color.black
                    .adaptiveGradientScrim(Self.textScrimStops(textHeight: headerTextHeight, fade: Self.textScrimFade))
                    .frame(height: headerTextHeight + Self.textScrimFade)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Mirrors what's left into any safe area beside the header
            // (landscape), where `ignoresSafeArea` used to stretch it.
            .backgroundExtensionEffect()
        }
    }

    /// The title, the start and channel, and the venue line, white on the
    /// text's ground. No radius of its own: the header runs to the sheet's
    /// top edge, whose corners round it concentric with the device.
    private var headerText: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.title.weight(.heavy))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            if !whenLine.isEmpty {
                Text(whenLine)
                    .font(.subheadline.weight(.semibold))
            }

            if !venueLine.isEmpty {
                Text(venueLine)
                    .font(Theme.Typography.footnote)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
        // The text's ground is sized to it.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            headerTextHeight = height
        }
    }

    /// The league's bundled backdrop, or the summary's venue photo.
    @ViewBuilder
    private var venueImage: some View {
        if let backdrop = league.venueBackdropAsset {
            Image(backdrop)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RemoteImage(url: URL(string: gameInfo.venueImage))
                .id(gameInfo.venueImage)
        }
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
        guard isFinal, let attendance = Self.formatAttendance(gameInfo.attendance) else { return line }
        return line.isEmpty ? attendance : "\(line) · \(attendance)"
    }

    /// "Att. 73,421" from the summary's attendance; `nil` when it is
    /// missing, zero or not a number.
    nonisolated static func formatAttendance(_ attendance: String, locale: Locale = .current) -> String? {
        guard let count = Int(attendance.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return nil }
        return "Att. \(count.formatted(.number.locale(locale)))"
    }

    /// "Venue · City, State" from the parts that aren't empty (A-19), so a
    /// summary that failed or gave no address leaves no "Venue · , ".
    /// Empty when there are none. `showsAddress` false gives the venue only.
    nonisolated static func formatVenueLine(location: String, city: String, state: String, showsAddress: Bool) -> String {
        func nonEmpty(_ parts: [String]) -> [String] {
            parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let address = showsAddress ? nonEmpty([city, state]).joined(separator: ", ") : ""
        return nonEmpty([location, address]).joined(separator: " · ")
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

    /// The score the loading placeholder lays out, redacted: two digits,
    /// about the width of most.
    private static let placeholderScore = "00"

    /// Which of the two figures stand out (G2): once the game is over, the
    /// winner's alone; both while it's on, before a score, or level.
    nonisolated static func scoreEmphasis(team: String, opponent: String, completed: Bool) -> GameScoreEmphasis {
        guard completed, let teamScore = Int(team), let opponentScore = Int(opponent), teamScore != opponentScore else {
            return GameScoreEmphasis(team: true, opponent: true)
        }
        return GameScoreEmphasis(team: teamScore > opponentScore, opponent: opponentScore > teamScore)
    }

    /// Both crests and the scoreline, the followed team on the left and
    /// its score first (F5), as every score in the app reads. The winner's
    /// figure and name are bold; the loser's dimmed (G2). At accessibility
    /// text sizes the scoreline sits above the two sides, so none of the
    /// three is squeezed into a third of the width.
    @ViewBuilder
    private func scoreboard(team teamScore: String, opponent opponentScore: String) -> some View {
        let emphasis = Self.scoreEmphasis(team: teamScore, opponent: opponentScore, completed: isFinal)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.Spacing.m) {
                scoreline(team: teamScore, opponent: opponentScore, emphasis: emphasis)

                HStack(alignment: .top) {
                    side(followed: true, emphasized: emphasis.team, alignment: .leading)
                    side(followed: false, emphasized: emphasis.opponent, alignment: .trailing)
                }
            }
        } else {
            HStack(alignment: .top) {
                side(followed: true, emphasized: emphasis.team, alignment: .leading)

                scoreline(team: teamScore, opponent: opponentScore, emphasis: emphasis)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                side(followed: false, emphasized: emphasis.opponent, alignment: .trailing)
            }
        }
    }

    /// The two figures with an en dash between, and the status beneath.
    /// Each figure rolls its digits as a live game refreshes (X-12).
    private func scoreline(team teamScore: String, opponent opponentScore: String, emphasis: GameScoreEmphasis) -> some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                scoreFigure(teamScore, emphasized: emphasis.team)
                Text(ScoreLine.separator)
                    .font(.title2)
                    .foregroundStyle(Theme.Palette.metadata)
                scoreFigure(opponentScore, emphasized: emphasis.opponent)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // "Chiefs 30, Raiders 27", not three loose figures.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(teamLabel) \(teamScore), \(game.opponent) \(opponentScore)")

            status
        }
    }

    /// One side's score: bold and primary, or dimmed and lighter for the
    /// loser of a finished game.
    private func scoreFigure(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.largeTitle.weight(emphasized ? .heavy : .medium).monospacedDigit())
            .foregroundStyle(emphasized ? Color.primary : Theme.Palette.metadata)
            .scoreTransition(value: Double(Int(text) ?? 0))
    }

    /// One team's crest over its name, the name dimmed with its score.
    private func side(followed: Bool, emphasized: Bool, alignment: HorizontalAlignment) -> some View {
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
                .font(.subheadline.weight(emphasized ? .bold : .medium))
                .foregroundStyle(emphasized ? Color.primary : Theme.Palette.metadata)
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

    // MARK: - Team stats

    /// The comparison rows, the followed team's figure on the left (F5),
    /// each over a pair of bars in the two teams' accents sized to the two
    /// figures (G5). A row whose figures aren't numbers has no bars.
    private func teamStats(_ rows: [BoxScore.Row]) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            // Which colour is whose; hidden from VoiceOver, since each row
            // names both sides itself.
            HStack(alignment: .firstTextBaseline) {
                legendLabel(teamColumnLabel, color: teamAccent, alignment: .leading)
                legendLabel(opponentColumnLabel, color: opponentAccent, alignment: .trailing)
            }
            .accessibilityHidden(true)

            ForEach(rows) { row in
                let teamStat = game.gameHome ? row.home : row.away
                let opponentStat = game.gameHome ? row.away : row.home
                VStack(spacing: Theme.Spacing.xs) {
                    // `StatRowView` draws its "away" figure on the left: the
                    // followed team's goes there, whichever side it is.
                    StatRowView(
                        title: row.title,
                        homeStat: opponentStat,
                        awayStat: teamStat,
                        homeName: game.opponent,
                        awayName: teamLabel
                    )
                    if let split = StatBarSplit(team: teamStat, opponent: opponentStat) {
                        StatBarPair(split: split, teamColor: teamAccent, opponentColor: opponentAccent)
                    }
                }
            }
        }
    }

    /// A column's heading beside a dot in its team's accent.
    private func legendLabel(_ text: String, color: Color, alignment: Alignment) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Theme.Typography.caption.bold())
                .foregroundStyle(Theme.Palette.metadata)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - Share

    /// "Chiefs 30–27 Raiders · Final": the scoreline as the scoreboard reads
    /// it, the followed team first (F5), and its status; before a score,
    /// the matchup and date.
    private var shareLine: String {
        guard let boxScore, !game.cancelled, !game.postponed else {
            let date = game.date.isEmpty ? "" : GameCardContent.fullDate(of: game.dateAsDate, now: .now)
            return date.isEmpty ? title : "\(title) · \(date)"
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
        let score = scores(boxScore)
        let line = "\(teamLabel) \(ScoreLine.score(team: "\(score.team)", opponent: "\(score.opponent)")) \(game.opponent)"
        return line + (status.isEmpty ? "" : " · \(status)")
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
        let score = scores(boxScore)
        let renderer = ImageRenderer(content:
            scoreboard(team: "\(score.team)", opponent: "\(score.opponent)")
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

/// Which of a scoreboard's two figures stand out (G2). See
/// `GameDetailView.scoreEmphasis(team:opponent:completed:)`.
struct GameScoreEmphasis: Equatable, Sendable {
    var team: Bool
    var opponent: Bool
}

/// The two sides' shares of one statistic, for the pair of bars under its
/// row (G5): each figure over their sum, the followed team's first. Pure,
/// so the tests drive it.
struct StatBarSplit: Equatable, Sendable {
    /// From 0 to 1; the two add up to 1.
    var team: Double
    var opponent: Double

    /// `nil` when either figure isn't a number `value(_:)` reads, either is
    /// negative, or both are zero: no bars beat a misleading pair.
    init?(team: String, opponent: String) {
        guard let teamValue = Self.value(team), let opponentValue = Self.value(opponent),
              teamValue >= 0, opponentValue >= 0
        else { return nil }
        let sum = teamValue + opponentValue
        guard sum > 0, sum.isFinite else { return nil }
        self.team = teamValue / sum
        self.opponent = opponentValue / sum
    }

    /// A box-score figure as a number: "399"; "45%" without its sign;
    /// a clock, "24:18", in seconds; and "15/30" or "15-30" by its first
    /// number (made, of attempted). `nil` for anything else.
    static func value(_ text: String) -> Double? {
        var figure = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if figure.hasSuffix("%") { figure.removeLast() }
        if let colon = figure.firstIndex(of: ":") {
            guard let minutes = Int(figure[..<colon]),
                  let seconds = Int(figure[figure.index(after: colon)...]),
                  minutes >= 0, (0 ..< 60).contains(seconds)
            else { return nil }
            return Double(minutes * 60 + seconds)
        }
        if let separator = figure.firstIndex(where: { $0 == "/" || $0 == "-" }), separator != figure.startIndex {
            figure = String(figure[..<separator])
        }
        guard let value = Double(figure), value.isFinite else { return nil }
        return value
    }
}

/// A statistic's pair of bars (G5): the followed team's share in its
/// accent, then the opponent's in theirs, side by side across the row.
/// Decorative: the row's figures and its VoiceOver label carry the values.
private struct StatBarPair: View {
    let split: StatBarSplit
    let teamColor: Color
    let opponentColor: Color

    /// The gap between the two bars.
    private static let gap: CGFloat = 3

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - Self.gap, 0)
            HStack(spacing: Self.gap) {
                Capsule()
                    .fill(teamColor)
                    .frame(width: usable * split.team)
                Capsule()
                    .fill(opponentColor)
                    .frame(width: usable * split.opponent)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
