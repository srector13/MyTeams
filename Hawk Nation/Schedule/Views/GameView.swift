//
//  GameView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct LoadingGameView : View {
    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardWidth = GameView.baseWidth
    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardHeight = GameView.baseHeight

    var body: some View {
        LoadingView()
            .frame(width: cardWidth, height: cardHeight)
    }
}

/// A game's card in a schedule carousel.
///
/// Over the team's colour: a status pill (the start, "Live" or "Final"),
/// the opponent's crest, whether the team is home, away or at a neutral
/// site, the opponent's name, and then the result, the live score and
/// period, or the full date and time. Beneath, on the inset surface,
/// whichever of the competition, date, channel and venue the feed gave; a
/// row the feed left blank is left out rather than drawn empty. What the
/// card says is worked out by `GameCardContent`, which the tests drive.
///
/// The card scales with Dynamic Type; at accessibility sizes, where the
/// schedule is a vertical list, it spans the list's width and grows to fit
/// its text instead (§5.3).
///
/// What differs by sport — what a level result is called, how a period is
/// named, and how a game in progress is drawn — comes from the league's
/// `LeagueDescriptor`.
struct GameView : View {

    /// The card's size at the default text size, in points. Room for the
    /// opponent's name on two full lines and three detail rows: at 150 ×
    /// 160 the name and the channel were clipped by the card's edges.
    static let baseWidth: CGFloat = 172
    static let baseHeight: CGFloat = 228

    /// The text style the card's size scales with. The card is mostly
    /// footnote and caption text, which grows faster than body text, so it
    /// is scaled by footnote's ratio to keep up; scaled by body's, the text
    /// outgrew the card at XXXL. `ScheduleSection`'s carousel scales alike.
    static let metricsTextStyle: Font.TextStyle = .footnote

    var game: Game
    var team: TeamRef

    /// The in-progress score the team model polls for this game, if any.
    /// Past and future fixtures carry no live score; they render from the
    /// schedule feed's own fields.
    var liveScore: LiveGameScore?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardWidth = GameView.baseWidth
    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardHeight = GameView.baseHeight
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 32
    @ScaledMetric(relativeTo: .caption2) private var detailIconWidth: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var liveDotSize: CGFloat = 6

    /// The card's fill: the team's colour, or the fallback its crest
    /// badge uses when the feed has none, so the ink is picked against
    /// what's actually drawn.
    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    /// Text and symbols on `teamColor`: white, black or the team's
    /// alternate colour, whichever reaches 4.5:1 (G-3). White alone failed
    /// on light team colours.
    private var ink: Color { TeamColors.ink(on: team) }

    private var league: LeagueDescriptor { team.league.descriptor }

    /// At accessibility text sizes the card fills a list row and sizes to
    /// its text rather than keeping the carousel's fixed shape.
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // Once a minute, so "In 12 min" counts down and a game that has
        // reached its start turns live without waiting for a refresh.
        TimelineView(.everyMinute) { context in
            card(GameCardContent(game: game, league: team.league, liveScore: liveScore, now: context.date))
        }
    }

    private func card(_ content: GameCardContent) -> some View {
        VStack(spacing: 0) {
            header(content)
                // Never squeezed: the details give way first.
                .layoutPriority(1)
                // A sparse feed's card is all team colour, rather than an
                // empty inset strip.
                .frame(maxHeight: content.details.isEmpty && !fillsRow ? CGFloat.infinity : nil, alignment: .top)
                .background { headerBackground }
                .clipped()

            if !content.details.isEmpty {
                details(content.details)
            }
        }
        .frame(width: fillsRow ? nil : cardWidth, height: fillsRow ? nil : cardHeight, alignment: .top)
        .frame(maxWidth: fillsRow ? CGFloat.infinity : nil)
        .background(Theme.Surface.insetCard)
        // Nested in the schedule section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
    }

    // MARK: Header

    /// The status pill, crest, side, opponent and result, in the team's ink.
    private func header(_ content: GameCardContent) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                StatusPill(content: content, dotSize: liveDotSize)
                Spacer(minLength: 0)
            }

            crest
                .frame(width: crestSize, height: crestSize)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(content.side)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)

                // Two lines, then a little smaller, and never cut off
                // mid-word.
                Text(content.opponent)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(fillsRow ? nil : 2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }

            phaseLine(content)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.s)
        .padding(.vertical, fillsRow ? Theme.Spacing.xs : 0)
    }

    /// The team's colour, with its crest faint in the corner.
    private var headerBackground: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(teamColor)

            TeamLogo(team: team, size: 200, forceVariant: .default)
                .opacity(0.1)
                .saturation(0.1)
                .contrast(0.5)
                .offset(x: 50, y: 40)
        }
    }

    /// The opponent's crest, fitted to its square: a wide crest filled past
    /// its frame and spilled over the text beside it.
    @ViewBuilder
    private var crest: some View {
        if game.opponentLogo.isEmpty {
            Image("blankTeam")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RemoteImage(url: URL(string: game.opponentLogo)) {
                Image("blankTeam")
                    .resizable()
            }
            .aspectRatio(contentMode: .fit)
        }
    }

    /// Beneath the opponent: the result, the live state, or the full date
    /// and time.
    @ViewBuilder
    private func phaseLine(_ content: GameCardContent) -> some View {
        switch content.phase {
        case .final:
            if let outcome = content.outcomeLabel {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(outcome)
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                    if let score = content.finalScore {
                        scoreText(score)
                    }
                }
            }
        case .live:
            switch league.liveCardStyle {
            case .periodFirst:
                VStack(spacing: 2) {
                    liveStageText(content)
                    if let liveScore {
                        liveScoreLine(liveScore, marksLead: false)
                    }
                }
            case .scoreFirst:
                VStack(spacing: 2) {
                    if let liveScore {
                        liveScoreLine(liveScore, marksLead: true)
                    }
                    liveStageText(content)
                }
            }
        case .upcoming, .cancelled, .postponed:
            if let dateLine = content.dateLine {
                Text(dateLine)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(fillsRow ? nil : 2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    @ViewBuilder
    private func liveStageText(_ content: GameCardContent) -> some View {
        if let stage = content.liveStage {
            Text(stage)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .lineLimit(fillsRow ? nil : 1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The live score, its digits rolling as either side scores (G-5).
    /// Under `LiveCardStyle.scoreFirst`, a triangle beside it says whether
    /// the followed team leads or trails.
    private func liveScoreLine(_ liveScore: LiveGameScore, marksLead: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            scoreText("\(liveScore.score) – \(liveScore.opponentScore)")
                .scoreTransition(value: Double(liveScore.score + liveScore.opponentScore))

            if marksLead, liveScore.score != liveScore.opponentScore {
                leadMarker(leading: liveScore.score > liveScore.opponentScore)
            }
        }
    }

    /// Leading or trailing, told by the triangle's direction and a spoken
    /// label rather than green against red (G-4). Drawn in the card's ink,
    /// which reads on any team colour where green or red may not.
    private func leadMarker(leading: Bool) -> some View {
        Image(systemName: leading ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.caption2.bold())
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(leading ? "Leading" : "Trailing")
    }

    /// A score on one line, trimmed a little for the odd wide one and never
    /// below 0.8 (D-4).
    private func scoreText(_ score: String) -> some View {
        Text(score)
            .font(.headline.weight(.heavy).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: Details

    /// The competition, date, channel and venue rows, on the inset surface
    /// in secondary text.
    private func details(_ details: [GameCardContent.Detail]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(details, id: \.kind) { detail in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Image(systemName: detail.systemImage)
                        .frame(width: detailIconWidth)
                        .accessibilityHidden(true)
                    Text(detail.text)
                        .lineLimit(fillsRow ? nil : 1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: fillsRow ? nil : CGFloat.infinity, alignment: .topLeading)
        .padding(Theme.Spacing.s)
    }
}

/// The card's status: the start ("Today 7:00 PM", "In 12 min"), "Live"
/// beside a dot, "Final", or the cancellation. Primary text on the inset
/// surface, so it reads the same over every team's colour.
private struct StatusPill: View {
    let content: GameCardContent
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if content.phase == .live {
                // The word says it too: never colour alone (G-4).
                Circle()
                    .fill(.red)
                    .frame(width: dotSize, height: dotSize)
                    .accessibilityHidden(true)
            }
            Text(content.status)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Surface.insetCard, in: Theme.Radius.chip)
    }
}

// MARK: - Content

/// What a schedule card says about a game at a moment, worked out from the
/// schedule feed's fields alone so the tests can check it. Every optional
/// is `nil`, and every detail row left out, where the feed gave nothing to
/// show: the European soccer feeds often carry no channel, and some no
/// venue or period.
struct GameCardContent: Equatable {
    enum Phase: Equatable {
        case upcoming, live, final, cancelled, postponed
    }

    enum Outcome: Equatable {
        case win, loss, draw
    }

    /// A row beneath the card's header.
    struct Detail: Equatable {
        enum Kind: Hashable {
            /// A cup tie's competition, the week, or the season stage.
            case competition
            /// The day a finished game was played.
            case date
            case broadcast
            case venue
        }

        var kind: Kind
        var text: String

        var systemImage: String {
            switch kind {
            case .competition: return "trophy"
            case .date: return "calendar"
            case .broadcast: return "tv"
            case .venue: return "mappin.and.ellipse"
            }
        }
    }

    /// How long before the start the pill counts down in minutes.
    static let countdownWindow: TimeInterval = 60 * 60

    var phase: Phase
    /// The pill's text.
    var status: String
    /// "Home", "Away" or "Neutral".
    var side: String
    var opponent: String
    var outcome: Outcome?
    /// "Win", "Loss", or the league's `drawLabel`.
    var outcomeLabel: String?
    /// The final score, the winner's first: "31 – 10".
    var finalScore: String?
    /// "2nd Quarter · 14:14", "Halftime", "5th Inning".
    var liveStage: String?
    /// Under the opponent of a game not played: the full start of one to
    /// come ("Sun, Oct 12 · 3:25 PM"), the date of a cancelled one.
    var dateLine: String?
    var details: [Detail]

    init(
        game: Game,
        league: LeagueID,
        liveScore: LiveGameScore? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let descriptor = league.descriptor
        let phase = Self.phase(of: game, now: now, liveScore: liveScore)
        self.phase = phase
        side = Self.side(of: game)
        opponent = game.opponent.isEmpty ? "TBD" : game.opponent

        let outcome = Self.outcome(of: game)
        self.outcome = outcome
        outcomeLabel = outcome.map { outcome -> String in
            switch outcome {
            case .win: return "Win"
            case .loss: return "Loss"
            case .draw: return descriptor.drawLabel
            }
        }
        finalScore = Self.finalScore(of: game, outcome: outcome)
        liveStage = phase == .live ? Self.liveStage(of: game, league: descriptor) : nil

        let hasDate = !game.date.isEmpty
        switch phase {
        case .upcoming:
            status = hasDate ? Self.startLabel(for: game.dateAsDate, now: now, calendar: calendar) : "TBD"
            dateLine = hasDate ? Self.fullStart(of: game.dateAsDate, now: now, calendar: calendar) : nil
        case .live:
            status = "Live"
            dateLine = nil
        case .final:
            status = "Final"
            dateLine = nil
        case .cancelled:
            status = "Cancelled"
            dateLine = hasDate ? Self.fullDate(of: game.dateAsDate, now: now, calendar: calendar) : nil
        case .postponed:
            status = "Postponed"
            dateLine = hasDate ? Self.fullDate(of: game.dateAsDate, now: now, calendar: calendar) : nil
        }

        var details: [Detail] = []
        if let competition = Self.competitionLabel(of: game, league: league) {
            details.append(Detail(kind: .competition, text: competition))
        }
        // An upcoming or called-off game's date is in its header.
        if phase == .final, hasDate {
            details.append(Detail(kind: .date, text: Self.fullDate(of: game.dateAsDate, now: now, calendar: calendar)))
        }
        // The channel only matters while there's still a game to watch.
        if phase == .upcoming || phase == .live, let broadcast = Self.broadcast(of: game) {
            details.append(Detail(kind: .broadcast, text: broadcast))
        }
        if let venue = Self.venue(of: game) {
            details.append(Detail(kind: .venue, text: venue))
        }
        self.details = details
    }

    // MARK: Rules

    /// Where the game stands. A game past its start that isn't marked
    /// finished counts as live, as the schedule always has; so does one the
    /// team model is polling a live score for.
    static func phase(of game: Game, now: Date, liveScore: LiveGameScore? = nil) -> Phase {
        if game.cancelled { return .cancelled }
        if game.postponed { return .postponed }
        if game.completed { return .final }
        if liveScore != nil { return .live }
        // An unreadable date leaves `dateAsDate` at the moment of parsing,
        // which would otherwise read as live forever.
        if !game.date.isEmpty, game.dateAsDate <= now { return .live }
        return .upcoming
    }

    /// "Neutral" at a neutral site, else "Home" or "Away".
    static func side(of game: Game) -> String {
        if game.neutralSite { return "Neutral" }
        return game.gameHome ? "Home" : "Away"
    }

    /// Win, loss or draw for a finished game; `nil` before then, or when a
    /// finished game's feed has published no score (nothing says who won).
    static func outcome(of game: Game) -> Outcome? {
        guard game.completed, !game.cancelled, !game.postponed else { return nil }
        if game.gameWin { return .win }
        if game.isDraw { return .draw }
        guard !game.score.isEmpty, !game.opponentScore.isEmpty else { return nil }
        return .loss
    }

    /// The final score with the winner's figure first, as the card has
    /// always shown it ("31 – 10" both for a win and a loss); `nil` without
    /// both figures.
    static func finalScore(of game: Game, outcome: Outcome?) -> String? {
        guard let outcome, !game.score.isEmpty, !game.opponentScore.isEmpty else { return nil }
        return outcome == .loss
            ? "\(game.opponentScore) – \(game.score)"
            : "\(game.score) – \(game.opponentScore)"
    }

    /// The period and clock of a game in progress: "2nd Quarter · 14:14",
    /// "2nd Half · 67'", "OT · 3:12", "5th Inning", or "Halftime". `nil`
    /// when the feed gives no period, as before the first is under way.
    static func liveStage(of game: Game, league: LeagueDescriptor) -> String? {
        if game.gameHalftime { return "Halftime" }
        var period = league.liveCardPeriodLabel(game.gamePeriod)
        // Innings go unnamed in the linescore, but the card can say which.
        if period.isEmpty, league.kind == .baseball, let inning = Int(game.gamePeriod), inning > 0 {
            period = "\(ordinalString(inning)) Inning"
        }
        guard !period.isEmpty else { return nil }
        // Baseball keeps no clock; its feeds' "0:00" means nothing.
        let clock = league.kind == .baseball ? "" : game.gameClock
        return clock.isEmpty ? period : "\(period) · \(clock)"
    }

    /// The pill's start for a game still to come: "In 25 min" inside the
    /// hour, "Today 7:00 PM", "Tomorrow 1:00 PM", "Sun 3:25 PM" within the
    /// week, then "Oct 12". Times in `calendar`'s zone and locale.
    static func startLabel(for start: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let untilStart = start.timeIntervalSince(now)
        if untilStart > 0, untilStart < countdownWindow {
            let minutes = max(1, Int((untilStart / 60).rounded(.up)))
            return "In \(minutes) min"
        }

        let time = timeLabel(of: start, calendar: calendar)
        if calendar.isDate(start, inSameDayAs: now) {
            return "Today \(time)"
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)
        ).day ?? 0
        if days == 1 {
            return "Tomorrow \(time)"
        }
        let style = formatStyle(calendar)
        if days > 1, days < 7 {
            return "\(start.formatted(style.weekday(.abbreviated))) \(time)"
        }
        return start.formatted(style.month(.abbreviated).day())
    }

    /// The start time alone, "3:25 PM", in `calendar`'s zone and locale.
    static func timeLabel(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        date.formatted(formatStyle(calendar).hour().minute())
    }

    /// "Sun, Oct 12", with the year when it isn't `now`'s: "Sat, Jan 2, 2027".
    static func fullDate(of date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        var style = formatStyle(calendar).weekday(.abbreviated).month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// `fullDate` and the start time: "Sun, Oct 12 · 3:25 PM".
    static func fullStart(of date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        "\(fullDate(of: date, now: now, calendar: calendar)) · \(timeLabel(of: date, calendar: calendar))"
    }

    /// What the game is part of, where the team's league alone doesn't say:
    /// a cup tie's competition ("FA Cup", "Champions League"), a football
    /// week ("Week 3"), or a preseason or postseason game. `nil` for an
    /// ordinary league game, and never an ESPN path.
    static func competitionLabel(of game: Game, league: LeagueID) -> String? {
        if let competition = game.competition, competition != league {
            if let name = competition.cupDisplayName { return name }
            let named = game.leagueName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !named.isEmpty { return named }
            return LeagueDescriptor.known[competition]?.displayName
        }
        let kind = league.descriptor.kind
        if kind == .football {
            let week = game.weekText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !week.isEmpty { return week }
        }
        // The soccer feeds put their own season ids in `seasonType`.
        guard kind != .soccer else { return nil }
        switch game.seasonType {
        case 1: return "Preseason"
        case 3: return "Postseason"
        default: return nil
        }
    }

    /// The channel, or `nil` where the feed named none (the parser's "TBD").
    static func broadcast(of game: Game) -> String? {
        let channel = game.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        return channel.isEmpty || channel == "TBD" ? nil : channel
    }

    static func venue(of game: Game) -> String? {
        let venue = game.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return venue.isEmpty ? nil : venue
    }

    /// Dates in `calendar`'s zone and locale.
    private static func formatStyle(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = calendar.locale ?? .autoupdatingCurrent
        return style
    }
}

extension LeagueID {
    /// The short name a schedule card gives a cup in some league's
    /// `LeagueDescriptor.cupCompetitions`, or `nil` for any other league.
    var cupDisplayName: String? {
        guard sport == "soccer" else { return nil }
        switch league {
        case "usa.open": return "U.S. Open Cup"
        case "concacaf.leagues.cup": return "Leagues Cup"
        case "concacaf.champions": return "Champions Cup"
        case "eng.fa": return "FA Cup"
        case "eng.league_cup": return "EFL Cup"
        case "uefa.champions": return "Champions League"
        case "uefa.europa": return "Europa League"
        case "uefa.europa.conf": return "Conference League"
        case "esp.copa_del_rey": return "Copa del Rey"
        case "ger.dfb_pokal": return "DFB-Pokal"
        case "ita.coppa_italia": return "Coppa Italia"
        case "fra.coupe_de_france": return "Coupe de France"
        case "eng.w.fa": return "FA Cup"
        case "eng.w.league_cup": return "League Cup"
        case "uefa.wchampions": return "Champions League"
        default: return nil
        }
    }
}

extension Game {
    /// The card read as one line for VoiceOver: the opponent, home, away or
    /// neutral, the date, then the result (the team's score first), the
    /// live score and period, or the start time and channel. `drawLabel` is
    /// what the league calls a level result; `league`, when given, names
    /// the live period.
    func accessibilitySummary(drawLabel: String, liveScore: LiveGameScore?, league: LeagueDescriptor? = nil) -> String {
        var parts = [opponent, GameCardContent.side(of: self).lowercased(), date]
        if cancelled {
            parts.append("Cancelled")
        } else if postponed {
            parts.append("Postponed")
        } else if completed {
            let outcome = gameWin ? "Win" : isDraw ? drawLabel : "Loss"
            parts.append("\(outcome), \(score) to \(opponentScore)")
        } else if GameCardContent.phase(of: self, now: Date(), liveScore: liveScore) == .live {
            if let liveScore {
                // The card's lead marker, spoken (G-4): the card's label
                // replaces its children's, the marker's included.
                let standing = liveScore.score > liveScore.opponentScore ? "leading, "
                    : liveScore.score < liveScore.opponentScore ? "trailing, " : ""
                parts.append("Live, \(standing)\(liveScore.score) to \(liveScore.opponentScore)")
            } else {
                parts.append("Live")
            }
            if let league, let stage = GameCardContent.liveStage(of: self, league: league) {
                parts.append(stage)
            }
        } else {
            parts.append(time)
            parts.append(GameCardContent.broadcast(of: self) ?? "")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
