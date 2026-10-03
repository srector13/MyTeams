//
//  GameLiveActivity.swift
//  myTeamWidget
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Draws a followed game's Live Activity (`GameActivityAttributes`), which
/// the app starts and keeps current (`LiveActivityManager`): the score,
/// period and clock on the Lock Screen and in the Dynamic Island.
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            // No background tint or action colour (LA-1): the system's own
            // platter follows the Lock Screen's light or dark appearance, as
            // the notifications around it do, and the banner's ink is
            // hierarchical to match. A tap opens the followed team's page,
            // as the widget's does.
            GameActivityBanner(game: context.attributes.game, state: context.state, isStale: context.isStale)
                .widgetURL(context.attributes.game.deepLink)
        } dynamicIsland: { context in
            let game = context.attributes.game
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GameActivityTeamScore(name: game.awayName, score: state.awayScore, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GameActivityTeamScore(name: game.homeName, score: state.homeScore, alignment: .trailing)
                }
                // The Dynamic Island's regions are sized by the system, so
                // their fonts stay fixed; VoiceOver gets labels instead.
                DynamicIslandExpandedRegion(.center) {
                    Text(state.stage)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(game.matchup)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(state.stage)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } compactTrailing: {
                Text("\(state.awayScore)–\(state.homeScore)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel(state.spokenScore(game))
            } minimal: {
                // The minimal presentation has no stage beside it, so its
                // label carries the stage too.
                Text("\(state.awayScore)–\(state.homeScore)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(state.spokenScore(game) + ", " + state.stage)
            }
            .widgetURL(game.deepLink)
        }
    }
}

/// The Lock Screen banner: each side's score, away over home as the
/// matchup reads, and the stage of the game.
private struct GameActivityBanner: View {
    var game: GameActivityInfo
    var state: GameActivityState
    var isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                row(game.awayName, state.awayScore, leads: state.awayScore > state.homeScore)
                row(game.homeName, state.homeScore, leads: state.homeScore > state.awayScore)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text(state.stage)
                    .font(Theme.Typography.cardTitle)
                    .monospacedDigit()
                if state.phase == .pending, let kickoff = game.kickoff {
                    Text(kickoff, style: .time)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                } else if isStale && state.phase == .live {
                    Text("Open myTeams to update")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        // Primary ink on the system platter, light or dark; the captions
        // above step down to secondary.
        .foregroundStyle(.primary)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    /// One side's name and score, heavier while it leads. Theme text styles,
    /// so both scale with Dynamic Type; the Dynamic Island keeps its fixed
    /// sizes, but this banner never does.
    private func row(_ name: String, _ score: Int, leads: Bool) -> some View {
        // The lead is drawn only in weight, so VoiceOver says it: "Rams 26,
        // leading", or "won" once the game is over.
        let spoken: String = leads
            ? "\(name) \(score), \(state.phase == .ended ? "won" : "leading")"
            : "\(name) \(score)"
        return HStack(spacing: Theme.Spacing.s) {
            Text(name)
                .font(Theme.Typography.body.weight(leads ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: Theme.Spacing.xs)
            // `statFigure` is black-weight with fixed-width digits; the side
            // that trails drops to regular.
            Text("\(score)")
                .font(leads ? Theme.Typography.statFigure : Theme.Typography.statFigure.weight(.regular))
        }
        .frame(maxWidth: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// One side in the expanded Dynamic Island: the name over the score.
private struct GameActivityTeamScore: View {
    var name: String
    var score: Int
    var alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + " " + String(score))
    }
}

extension GameActivityState {
    /// The scoreline as VoiceOver reads it, e.g. "Rams 26, Broncos 23":
    /// each side's name with its score, away first, as the "26–23" it
    /// stands for is drawn.
    fileprivate func spokenScore(_ game: GameActivityInfo) -> String {
        "\(game.awayName) \(awayScore), \(game.homeName) \(homeScore)"
    }
}

extension GameActivityAttributes {
    fileprivate static let preview = GameActivityAttributes(game: GameActivityInfo(
        gameID: "401872962", teamID: "7", league: "football/nfl",
        homeName: "Broncos", awayName: "Rams", matchup: "Rams at Broncos",
        kickoff: nil, favoriteID: "football/nfl:7"
    ))
}

// Previews (GlassUI step 0.7). Check the Lock Screen banner in the canvas's
// light and dark variants and at large Dynamic Type sizes: it sits on the
// system platter and scales; the Dynamic Island stays fixed.

#Preview("Lock Screen", as: .content, using: GameActivityAttributes.preview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 0, awayScore: 0, period: 0, clock: "", phase: .pending)
    GameActivityState(homeScore: 23, awayScore: 26, period: 4, clock: "0:48", phase: .live)
    GameActivityState(homeScore: 23, awayScore: 29, period: 4, clock: "", phase: .ended)
}

#Preview("Dynamic Island · expanded", as: .dynamicIsland(.expanded), using: GameActivityAttributes.preview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 23, awayScore: 26, period: 4, clock: "0:48", phase: .live)
}

#Preview("Dynamic Island · compact", as: .dynamicIsland(.compact), using: GameActivityAttributes.preview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 23, awayScore: 26, period: 4, clock: "0:48", phase: .live)
}

#Preview("Dynamic Island · minimal", as: .dynamicIsland(.minimal), using: GameActivityAttributes.preview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 23, awayScore: 26, period: 4, clock: "0:48", phase: .live)
}
#endif
