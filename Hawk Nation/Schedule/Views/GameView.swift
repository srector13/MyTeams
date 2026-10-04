//
//  GameView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct LoadingGameView : View {
    @ScaledMetric(relativeTo: .body) private var cardWidth = GameView.baseWidth
    @ScaledMetric(relativeTo: .body) private var cardHeight = GameView.baseHeight

    var body: some View {
        LoadingView()
            .frame(width: cardWidth, height: cardHeight)
    }
}

/// A game's card in a schedule carousel: the opponent and kick-off, overlaid
/// with the result, the live state, or a cancellation.
///
/// The card scales with Dynamic Type; at accessibility sizes, where the
/// schedule is a vertical list, it spans the list's width and grows to fit
/// its text instead (§5.3).
///
/// What differs by sport — what a level result is called, and how a game in
/// progress is drawn — comes from the league's `LeagueDescriptor`.
struct GameView : View {

    /// The card's size at the default text size, in points. Wide enough for
    /// an opponent's name and the channel on one line; at 120 they ran into
    /// the card's rounded edges.
    static let baseWidth: CGFloat = 150
    static let baseHeight: CGFloat = 160

    var game: Game
    var team: TeamRef

    /// The in-progress score the team model polls for this game, if any.
    /// Past and future fixtures carry no live score; they render from the
    /// schedule feed's own fields.
    var liveScore: LiveGameScore?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var cardWidth = GameView.baseWidth
    @ScaledMetric(relativeTo: .body) private var cardHeight = GameView.baseHeight
    @ScaledMetric(relativeTo: .body) private var statusBarHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var statusPillHeight: CGFloat = 25

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
        VStack(spacing: 0) {
            status
                .frame(maxWidth: .infinity)
                .frame(height: fillsRow ? nil : cardHeight - statusBarHeight)
                .background {
                    ZStack {
                        Rectangle()
                            .foregroundStyle(teamColor)

                        TeamLogo(team: team, size: 200, forceVariant: .default)
                            .opacity(0.1)
                            .saturation(0.1)
                            .contrast(0.5)
                            .offset(x: 40, y: 50)
                    }
                }
                .clipped()

            // Where the game stands, as content: the whole card is the
            // button (T-3), so nothing here may look like one (G-2).
            Text(game.statusSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(minHeight: statusPillHeight)
                .background(.fill.tertiary, in: Theme.Radius.chip)
                .frame(maxWidth: .infinity)
                .frame(height: fillsRow ? nil : statusBarHeight)
                .padding(.vertical, fillsRow ? Theme.Spacing.s : 0)

        }.background(Theme.Surface.insetCard)
            .frame(width: fillsRow ? nil : cardWidth, height: fillsRow ? nil : cardHeight)
            .frame(maxWidth: fillsRow ? CGFloat.infinity : nil)
            // Nested in the schedule section's card (X-4).
            .clipShape(Theme.Radius.innerShape)
    }

    /// The details, with the result, live state or cancellation over them.
    @ViewBuilder
    private var status: some View {
        if(game.cancelled || game.postponed) {
            ZStack {
                washedDetails(dimmed: false)

                if(game.cancelled) {
                    Text("Cancelled")
                        .font(.title3.bold())
                        .foregroundStyle(ink)
                } else if (game.postponed) {
                    Text("Postponed")
                        .font(.title3.bold())
                        .foregroundStyle(ink)
                }
            }
        } else if(game.completed) {
            ZStack {
                washedDetails(dimmed: true)

                if (game.gameWin) {
                    result("Win", score: game.score + " - " + game.opponentScore)
                } else if (game.isDraw) {
                    result(league.drawLabel, score: game.score + " - " + game.opponentScore)
                } else {
                    result("Loss", score: game.opponentScore + " - " + game.score)
                }
            }
        } else if(game.dateAsDate < Date()) {
            ZStack {
                washedDetails(dimmed: true)

                switch league.liveCardStyle {
                case .periodFirst:
                    periodFirstLiveState
                case .scoreFirst:
                    scoreFirstLiveState
                }
            }
        } else {
            details(dimmed: false)
        }
    }

    private func details(dimmed: Bool) -> some View {
        GameCardDetails(game: game, ink: ink, dimmed: dimmed, wraps: fillsRow)
            .padding(.vertical, fillsRow ? Theme.Spacing.m : 0)
            // The same inset on both sides, clear of the rounded corners.
            .padding(.horizontal, Theme.Spacing.s)
    }

    /// The details beneath the team-coloured wash a status sits on. The wash
    /// is an overlay so it covers the details at whatever height they take.
    private func washedDetails(dimmed: Bool) -> some View {
        details(dimmed: dimmed)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { tint }
    }

    /// The team-coloured wash laid over the details beneath a status,
    /// denser under Increase Contrast so the status's ink stands clear of
    /// the details (G-3, X-5).
    private var tint: some View {
        Rectangle()
            .foregroundStyle(teamColor)
            .adaptiveScrim(0.5)
    }

    /// A finished game's outcome over its final score.
    private func result(_ outcome: String, score: String) -> some View {
        VStack {
            Text(outcome)
                .font(.title2.bold())
                .foregroundStyle(ink)

            scoreText(score, font: .title3.weight(.heavy))
        }
    }

    /// A game in progress as `LiveCardStyle.periodFirst` draws it.
    private var periodFirstLiveState: some View {
        VStack {
            if(game.gameHalftime) {
                liveLine("Halftime", font: .subheadline)
            } else {
                liveLine(league.liveCardPeriodLabel(game.gamePeriod), font: .subheadline)
                liveLine(game.gameClock, font: .subheadline)
            }

            if let liveScore {
                liveScoreText(liveScore)
            }
        }
    }

    /// A game in progress as `LiveCardStyle.scoreFirst` draws it: a
    /// triangle beside the score says whether the followed team leads or
    /// trails. With no live score yet, only the tinted details show.
    @ViewBuilder
    private var scoreFirstLiveState: some View {
        if let liveScore {
            VStack {
                HStack() {
                    liveScoreText(liveScore)

                    if liveScore.score != liveScore.opponentScore {
                        leadMarker(leading: liveScore.score > liveScore.opponentScore)
                    }
                }

                // One size whether leading, level or trailing (G-4).
                liveLine(league.liveCardPeriodLabel(game.gamePeriod), font: .subheadline)
                liveLine(game.gameClock, font: .subheadline)
            }
        }
    }

    /// Leading or trailing, told by the triangle's direction and a spoken
    /// label rather than green against red (G-4). Drawn in the card's ink,
    /// which reads on any team colour where green or red may not.
    private func leadMarker(leading: Bool) -> some View {
        Image(systemName: leading ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.caption.bold())
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(ink)
            .accessibilityLabel(leading ? "Leading" : "Trailing")
    }

    /// The live score, its digits rolling as either side scores (G-5).
    private func liveScoreText(_ liveScore: LiveGameScore) -> some View {
        scoreText("\(liveScore.score) - \(liveScore.opponentScore)", font: .title2.weight(.heavy))
            .scoreTransition(value: Double(liveScore.score + liveScore.opponentScore))
    }

    /// A score on one line. The card now grows with the text, so this only
    /// trims the odd wide score, and never below 0.8 (D-4).
    private func scoreText(_ score: String, font: Font) -> some View {
        Text(score)
            .font(font.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(ink)
    }

    private func liveLine(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font.bold())
            .multilineTextAlignment(.center)
            .lineLimit(fillsRow ? nil : 1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(ink)
            .padding(.horizontal, Theme.Spacing.s)
    }
}

/// The opponent, its crest, and the date, time and channel on a game card.
///
/// Dimmed beneath a result or live state; full strength on a fixture still to
/// come, or beneath a cancellation.
private struct GameCardDetails: View {
    var game: Game
    /// The card's contrast-picked ink (`GameView.ink`).
    var ink: Color
    var dimmed: Bool
    /// Whether the text may wrap: only where the card fills a list row at
    /// accessibility sizes. In the carousel's fixed-size card every line
    /// keeps to one line, so none runs past the card's edge or bottom.
    var wraps: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            fitted(Text(game.opponent))
                .font(.caption.bold())
                .foregroundStyle(ink)

            // Fitted, not filled: a wide crest filled past its 60 pt frame
            // and spilled over the text beside it.
            if dimmed {
                RemoteImage(url: URL(string: game.opponentLogo)) {
                    Image("blankTeam")
                        .resizable()
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .opacity(0.5)
            } else if(game.opponentLogo == "") {
                Image("blankTeam")
                    .resizable()
                    .frame(width: 60, height: 60)
            } else {
                RemoteImage(url: URL(string: game.opponentLogo))
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
            }

            line(game.date)
            line(game.time)
            line(game.channel)
        }
    }

    private func line(_ text: String) -> some View {
        fitted(Text(text))
            .font(.caption2.weight(.medium))
            .foregroundStyle(ink)
            .opacity(dimmed ? 0.5 : 1)
    }

    /// A line held to the card's width: one line, shrunk a little and then
    /// truncated rather than clipped at the card's edge.
    private func fitted(_ text: Text) -> some View {
        text
            .multilineTextAlignment(.center)
            .lineLimit(wraps ? nil : 1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

extension Game {
    /// Where the game stands in a word or two, for the foot of its card:
    /// "Final", "Live", "Cancelled", "Postponed", or else the start time.
    var statusSummary: String {
        if cancelled { return "Cancelled" }
        if postponed { return "Postponed" }
        if completed { return "Final" }
        if dateAsDate < Date() { return "Live" }
        return time.isEmpty ? date : time
    }

    /// The card read as one line for VoiceOver: the opponent, the date, then
    /// the result (the team's score first), the live score or the start
    /// time. `drawLabel` is what the league calls a level result.
    func accessibilitySummary(drawLabel: String, liveScore: LiveGameScore?) -> String {
        var parts = [opponent, date]
        if cancelled {
            parts.append("Cancelled")
        } else if postponed {
            parts.append("Postponed")
        } else if completed {
            let outcome = gameWin ? "Win" : isDraw ? drawLabel : "Loss"
            parts.append("\(outcome), \(score) to \(opponentScore)")
        } else if dateAsDate < Date() {
            if let liveScore {
                // The card's lead marker, spoken (G-4): the card's label
                // replaces its children's, the marker's included.
                let standing = liveScore.score > liveScore.opponentScore ? "leading, "
                    : liveScore.score < liveScore.opponentScore ? "trailing, " : ""
                parts.append("Live, \(standing)\(liveScore.score) to \(liveScore.opponentScore)")
            } else {
                parts.append("Live")
            }
        } else {
            parts.append(time)
            parts.append(channel)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
