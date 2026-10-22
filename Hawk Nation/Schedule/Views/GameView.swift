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

/// Where a game's card is drawn, which decides how it names the game.
enum GameCardStyle: Equatable, Sendable {
    /// In a team's schedule: the page is the team's, so the card names the
    /// opponent alone ("@ Raiders", "vs Chargers") under its crest.
    case schedule
    /// On Home, among every favorite's games: the card says whose game it
    /// is ("Chiefs at Dolphins"), the followed team's crest first (H3).
    case home
}

/// A game's card in a schedule carousel, and in Home's This Week.
///
/// Over the team's colour: the status pill (the start, "Live" with the
/// period, or "Final"), the crests, the matchup, and one line reserved on
/// every card for the result ("W 30–27", team first, F5), the live score,
/// or the channel of a game to come, so a result's band and an upcoming
/// game's are the same height (T4). The start time is in the pill and
/// nowhere else. Beneath, on the inset surface, what the game is part of,
/// its date (in a schedule; Home's strip already says the day) and its
/// venue; a row the feed left blank is left out rather than drawn empty.
/// What the card says is worked out by `GameCardContent`, which the tests
/// drive.
///
/// The card is as tall as its content (F7). In a schedule carousel it takes
/// a slot at least `baseHeight` tall and sits at the top of it, so the row
/// doesn't change height as it scrolls. The card scales with Dynamic Type; at accessibility
/// sizes, where the schedule is a vertical list, it spans the list's width
/// and its text wraps instead (§5.3).
///
/// What differs by sport — what a level result is called, how a period is
/// named, and whether a live score marks the lead — comes from the
/// league's `LeagueDescriptor`.
struct GameView : View {

    /// A schedule card's width at the default text size, in points: room
    /// for the matchup, the result and a footer line like "Week 4 · Sun,
    /// Oct 4", with the next card peeking in beside it on an iPhone.
    static let baseWidth: CGFloat = 200
    /// The height a schedule card's slot in its carousel takes, at the
    /// default text size: a little over the tallest card (band and two
    /// footer lines), which sits at its top; a placeholder's height. The
    /// card itself is as tall as its content.
    static let baseHeight: CGFloat = 206

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

    /// A team page's schedule, or Home. On Home the card takes the width
    /// its row gives it.
    var style: GameCardStyle = .schedule

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardWidth = GameView.baseWidth
    @ScaledMetric(relativeTo: GameView.metricsTextStyle) private var cardHeight = GameView.baseHeight
    @ScaledMetric(relativeTo: .footnote) private var crestSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var liveDotSize: CGFloat = 6

    /// The card's fill: the team's colour, or the fallback its crest
    /// badge uses when the feed has none, so the ink is picked against
    /// what's actually drawn.
    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: team)) }

    /// Text and symbols on `teamColor`: white, black or the team's
    /// alternate colour, whichever reaches 4.5:1 (G-3, F2). Never the
    /// theme's accent.
    private var ink: Color { TeamColors.ink(on: team) }

    private var league: LeagueDescriptor { team.league.descriptor }

    /// At accessibility text sizes the card fills a list row and sizes to
    /// its text rather than keeping the carousel's width.
    private var fillsRow: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The card's own width: a schedule card's, scaled; `nil` where its row
    /// decides (Home, or a list at accessibility sizes).
    private var fixedWidth: CGFloat? {
        style == .schedule && !fillsRow ? cardWidth : nil
    }

    /// Whether the live score carries the lead marker (`LiveCardStyle`).
    private var marksLead: Bool {
        if case .scoreFirst = league.liveCardStyle { return true }
        return false
    }

    var body: some View {
        // Once a minute, so "In 12 min" counts down and a game that has
        // reached its start turns live without waiting for a refresh.
        TimelineView(.everyMinute) { context in
            card(GameCardContent(
                game: game,
                league: team.league,
                liveScore: liveScore,
                now: context.date,
                style: style,
                teamName: team.shortName
            ))
        }
    }

    private func card(_ content: GameCardContent) -> some View {
        VStack(spacing: 0) {
            header(content)
                .background { headerBackground }
                .clipped()

            if !content.footerLines.isEmpty {
                footer(content.footerLines)
            }
        }
        .frame(width: fixedWidth, alignment: .top)
        .frame(maxWidth: fixedWidth == nil ? CGFloat.infinity : nil)
        .background(Theme.Surface.insetCard)
        // Nested in the section's card (X-4).
        .clipShape(Theme.Radius.innerShape)
        // In a schedule carousel, a row as tall as the tallest card with
        // each card at its own height at the top of it, so the row keeps
        // its height as cards are realised while it scrolls (T4).
        .frame(minHeight: style == .schedule && !fillsRow ? cardHeight : nil, alignment: .top)
    }

    // MARK: Header

    /// The status pill, crests, matchup and the reserved result line, in
    /// the team's ink.
    private func header(_ content: GameCardContent) -> some View {
        VStack(spacing: Theme.Spacing.s - 2) {
            HStack(spacing: 0) {
                StatusPill(content: content, dotSize: liveDotSize)
                Spacer(minLength: 0)
            }

            crests(content)
                .accessibilityHidden(true)

            // One line in a carousel, so every band is the same height;
            // trimmed a little for a long name rather than cut off.
            Text(content.matchup)
                .font(style == .home ? Font.headline : Font.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(fillsRow ? nil : 1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)

            resultSlot(content)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
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

    /// The opponent's crest on a schedule card; on Home the followed
    /// team's first, "vs" or "at", then the opponent's. Both cut out on the
    /// team colour as the hero's are, the opponent's through the same
    /// lookup the hero uses (`HomeOpponentCrest`, H8), so a card never
    /// shows a grey shield where the hero has the real crest.
    @ViewBuilder
    private func crests(_ content: GameCardContent) -> some View {
        let onHex = TeamColors.fillHex(for: team)
        switch style {
        case .schedule:
            HomeOpponentCrest(game: game, league: team.league, size: crestSize, onHex: onHex)
        case .home:
            HStack(spacing: Theme.Spacing.s + 2) {
                CutoutCrest(team: team, size: crestSize, onHex: onHex)
                Text(content.connector)
                    .font(.caption.weight(.semibold))
                    .opacity(0.9)
                HomeOpponentCrest(game: game, league: team.league, size: crestSize, onHex: onHex)
            }
        }
    }

    /// The line every card keeps under the matchup (T4): the result, the
    /// live score, or the channel of a game to come; held empty at the same
    /// height where there's nothing to put in it.
    private func resultSlot(_ content: GameCardContent) -> some View {
        ZStack {
            // Holds the line's height on every card.
            scoreText(" ")
                .hidden()
                .accessibilityHidden(true)

            if content.phase == .live, let liveScore {
                liveScoreLine(liveScore)
            } else if let line = content.slotLine {
                if content.phase == .final {
                    scoreText(line)
                } else {
                    Text(line)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    /// The live score, team first (F5), its digits rolling as either side
    /// scores (G-5). Under `LiveCardStyle.scoreFirst`, a triangle beside it
    /// says whether the followed team leads or trails.
    private func liveScoreLine(_ liveScore: LiveGameScore) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            scoreText(ScoreLine.score(team: "\(liveScore.score)", opponent: "\(liveScore.opponentScore)"))
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

    // MARK: Footer

    /// What the game is part of and its date on one line, its venue on the
    /// next, in the metadata grey on the inset surface (F1).
    private func footer(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .lineLimit(fillsRow ? nil : 1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.metadata)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }
}

/// The card's status: the start ("Today 7:00 PM", "In 12 min"), "Live"
/// beside a dot and the period, "Final", or the cancellation. Primary text
/// on the inset surface, so it reads the same over every team's colour.
private struct StatusPill: View {
    let content: GameCardContent
    let dotSize: CGFloat

    /// "Live · 2nd Quarter · 14:14" while it's under way: the period rides
    /// in the pill, so the result line below holds the score.
    private var text: String {
        if content.phase == .live, let stage = content.liveStage {
            return "\(content.status) · \(stage)"
        }
        return content.status
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if content.phase == .live {
                // The word says it too: never colour alone (G-4).
                Circle()
                    .fill(.red)
                    .frame(width: dotSize, height: dotSize)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // The label colour itself, not `.primary`: that resolves to the
        // header's inherited ink (white on a dark team colour), unreadable
        // on the near-white inset surface in light mode.
        .foregroundStyle(Color.primary)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Surface.insetCard, in: Theme.Radius.chip)
    }
}

// MARK: - Content

/// What a game's card says about it at a moment, worked out from the
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

    /// A fact for the card's footer.
    struct Detail: Equatable {
        enum Kind: Hashable {
            /// A cup tie's competition, the week, or the season stage; on
            /// Home, else the league.
            case competition
            /// The day the game is (or was) played, in a schedule.
            case date
            /// The channel of a game under way; one to come has it in the
            /// result line.
            case broadcast
            case venue
        }

        var kind: Kind
        var text: String
    }

    /// How long before the start the pill counts down in minutes.
    static let countdownWindow: TimeInterval = 60 * 60

    var phase: Phase
    /// The pill's text: the start, with its time ("Sun 3:25 PM", "Oct 14
    /// · 3:25 PM"), "Live", "Final", or the cancellation. The only place
    /// the card gives the time (T4).
    var status: String
    /// "Home", "Away" or "Neutral".
    var side: String
    var opponent: String
    /// Under the crests: "@ Raiders" or "vs Chargers" in a schedule, the
    /// opponent alone; "Chiefs at Dolphins" or "Sporting vs Salt Lake" on
    /// Home, the followed team first (H3).
    var matchup: String
    /// "vs" at home or a neutral site, "at" away: between Home's crests.
    var connector: String
    var outcome: Outcome?
    /// "Win", "Loss", or the league's `drawLabel`.
    var outcomeLabel: String?
    /// The final score, the team's first (F5): "24–10" for a win, "10–24"
    /// for a loss.
    var finalScore: String?
    /// The result's letter and the score, team first: "W 24–10", "L 0–4",
    /// "T 20–20". Just the outcome's word where the feed gave no score.
    var resultLine: String?
    /// "2nd Quarter · 14:14", "Halftime", "5th Inning".
    var liveStage: String?
    /// The line reserved under the matchup on every card (T4): the result
    /// once it's final, the channel of a game to come; `nil` while it's
    /// live (the card draws the live score there) or where there's
    /// nothing to say, when the line is held empty.
    var slotLine: String?
    /// The footer's facts, in order.
    var details: [Detail]

    init(
        game: Game,
        league: LeagueID,
        liveScore: LiveGameScore? = nil,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        style: GameCardStyle = .schedule,
        teamName: String = ""
    ) {
        let descriptor = league.descriptor
        let phase = Self.phase(of: game, now: now, liveScore: liveScore)
        self.phase = phase
        side = Self.side(of: game)
        let opponent = game.opponent.isEmpty ? "TBD" : game.opponent
        self.opponent = opponent

        let isAway = !game.gameHome && !game.neutralSite
        let connector = isAway ? "at" : "vs"
        self.connector = connector
        let name = teamName.trimmingCharacters(in: .whitespaces)
        switch style {
        case .schedule:
            matchup = "\(isAway ? "@" : "vs") \(opponent)"
        case .home:
            matchup = name.isEmpty ? "\(connector) \(opponent)" : "\(name) \(connector) \(opponent)"
        }

        let outcome = Self.outcome(of: game)
        self.outcome = outcome
        outcomeLabel = outcome.map { outcome -> String in
            switch outcome {
            case .win: return "Win"
            case .loss: return "Loss"
            case .draw: return descriptor.drawLabel
            }
        }
        let finalScore = Self.finalScore(of: game, outcome: outcome)
        self.finalScore = finalScore
        let resultLine: String? = outcome.map { outcome -> String in
            let word: String
            let letter: String
            switch outcome {
            case .win:
                word = "Win"
                letter = "W"
            case .loss:
                word = "Loss"
                letter = "L"
            case .draw:
                word = descriptor.drawLabel
                letter = String(descriptor.drawLabel.prefix(1)).uppercased()
            }
            guard finalScore != nil else { return word }
            return ScoreLine.result(letter, team: game.score, opponent: game.opponentScore)
        }
        self.resultLine = resultLine
        liveStage = phase == .live ? Self.liveStage(of: game, league: descriptor) : nil

        let hasDate = !game.date.isEmpty
        let broadcast = Self.broadcast(of: game)
        switch phase {
        case .upcoming:
            status = hasDate ? Self.cardStartLabel(for: game.dateAsDate, now: now, calendar: calendar) : "TBD"
            slotLine = broadcast
        case .live:
            status = "Live"
            slotLine = nil
        case .final:
            status = "Final"
            slotLine = resultLine
        case .cancelled:
            status = "Cancelled"
            slotLine = nil
        case .postponed:
            status = "Postponed"
            slotLine = nil
        }

        var details: [Detail] = []
        let competition = Self.competitionLabel(of: game, league: league)
        switch style {
        case .schedule:
            if let competition {
                details.append(Detail(kind: .competition, text: competition))
            }
            // A schedule runs over months: each card says its day. A game
            // under way is today's.
            if hasDate, phase != .live {
                details.append(Detail(kind: .date, text: Self.fullDate(of: game.dateAsDate, now: now, calendar: calendar)))
            }
        case .home:
            // Home mixes the favorites' leagues, so a league game names
            // its league; the strip above already says the day.
            details.append(Detail(kind: .competition, text: competition ?? descriptor.displayName))
        }
        // Under way, the result line holds the score: the channel goes
        // here instead.
        if phase == .live, let broadcast {
            details.append(Detail(kind: .broadcast, text: broadcast))
        }
        if let venue = Self.venue(of: game) {
            details.append(Detail(kind: .venue, text: venue))
        }
        self.details = details
    }

    /// The footer as drawn: what the game is part of, its date and (while
    /// it's live) its channel on one line — "Week 4 · Sun, Oct 4" — and
    /// the venue on the next. No line where the feed gave nothing.
    var footerLines: [String] {
        let facts = details.filter { $0.kind != .venue }.map(\.text)
        var lines: [String] = []
        if !facts.isEmpty {
            lines.append(facts.joined(separator: " · "))
        }
        if let venue = details.first(where: { $0.kind == .venue }) {
            lines.append(venue.text)
        }
        return lines
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

    /// The final score with the team's figure first (F5): "24–10" for a
    /// win, "10–24" for a loss; `nil` before a result or without both
    /// figures.
    static func finalScore(of game: Game, outcome: Outcome?) -> String? {
        guard outcome != nil, !game.score.isEmpty, !game.opponentScore.isEmpty else { return nil }
        return ScoreLine.score(team: game.score, opponent: game.opponentScore)
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

    /// The card's pill for a game still to come: `startLabel`, with the
    /// start time added where that leaves it out ("Oct 14 · 3:25 PM"), so
    /// the time is always in the pill and only there (T4). The countdown
    /// inside the hour stands alone.
    static func cardStartLabel(for start: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let label = startLabel(for: start, now: now, calendar: calendar)
        let untilStart = start.timeIntervalSince(now)
        if untilStart > 0, untilStart < countdownWindow { return label }
        let time = timeLabel(of: start, calendar: calendar)
        return label.hasSuffix(time) ? label : "\(label) · \(time)"
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
