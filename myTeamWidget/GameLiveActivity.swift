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
                        .islandTextSize()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GameActivityTeamScore(name: game.homeName, score: state.homeScore, alignment: .trailing)
                        .islandTextSize()
                }
                // The Dynamic Island's regions are sized by the system, so
                // their text stays at the default size (`islandTextSize()`);
                // VoiceOver gets labels instead.
                DynamicIslandExpandedRegion(.center) {
                    Text(state.stage)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .islandTextSize()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(game.matchup)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .islandTextSize()
                }
            } compactLeading: {
                // Whose game this is (DI-1). The stage no longer fits
                // beside the score in the compact width, so it shows only
                // when expanded; the trailing label speaks it.
                FollowedTeamMark(game: game)
                    .islandTextSize()
            } compactTrailing: {
                Text("\(state.awayScore)–\(state.homeScore)")
                    .font(.footnote.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText(value: state.scoreTotal))
                    .islandTextSize()
                    .accessibilityLabel(state.spokenScore(game) + ", " + state.stage)
            } minimal: {
                // The minimal presentation has no stage beside it, so its
                // label carries the stage too.
                Text("\(state.awayScore)–\(state.homeScore)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText(value: state.scoreTotal))
                    .minimumScaleFactor(0.5)
                    .islandTextSize()
                    .accessibilityLabel(state.spokenScore(game) + ", " + state.stage)
            }
            // The followed team's colour on the island's rim (DI-2), or the
            // system's own where the bundle doesn't know the team.
            .keylineTint(game.followedTeam.map { Color(hexString: TeamColors.fillHex(for: $0)) })
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

    /// Set on the Always-On Lock Screen (LA-2), where only the scores stay
    /// bright: the names and stage step down to secondary, and the stale
    /// caption, an invitation to act on a dimmed screen, goes.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

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
                    .foregroundStyle(nonScoreInk)
                if state.phase == .pending, let kickoff = game.kickoff {
                    Text(kickoff, style: .time)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                } else if isStale && state.phase == .live && !isLuminanceReduced {
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

    /// The ink for everything but the scores: primary, or secondary while
    /// the Always-On display dims the screen (LA-2).
    private var nonScoreInk: HierarchicalShapeStyle {
        isLuminanceReduced ? .secondary : .primary
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
                .foregroundStyle(nonScoreInk)
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
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.title.bold())
                .monospacedDigit()
                // Rolls the digits when a side scores (DI-2).
                .contentTransition(.numericText(value: Double(score)))
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + " " + String(score))
    }
}

/// The compact island's leading mark: the followed team's abbreviation
/// (DI-1), so the island says whose game it is, as the HIG asks of the
/// leading side.
///
/// The payload carries no abbreviation or colour (it stays within the Live
/// Activity's size budget, §5.4), so the team is looked up in the bundled
/// catalog. A team the bundle doesn't know gets its sport's symbol instead:
/// the payload doesn't say whether the followed team is home or away, and
/// a guessed name would be the opponent's half the time.
private struct FollowedTeamMark: View {
    var game: GameActivityInfo

    var body: some View {
        if let team = game.followedTeam, !team.abbreviation.isEmpty {
            Text(team.abbreviation)
                .font(.caption.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(team.displayName)
        } else {
            Image(systemName: game.sportSymbol)
                .font(.caption.weight(.semibold))
                .accessibilityLabel(game.matchup)
        }
    }
}

extension GameActivityInfo {
    /// The followed team, if the bundled catalog has it. Read from
    /// `favoriteID`, checked against `teamID`; an activity started before
    /// `favoriteID` was kept falls back to the board's league, which is the
    /// team's own outside cup ties.
    fileprivate var followedTeam: TeamRef? {
        let id = favoriteID ?? LeagueID(path: league).map { TeamRef.id(league: $0, espnID: teamID) }
        guard let id, let parsed = TeamRef.parse(id: id), parsed.espnID == teamID else { return nil }
        return TeamCatalog.team(id: id)
    }

    /// An SF Symbol for the game's sport, for a followed team the bundle
    /// can't name.
    fileprivate var sportSymbol: String {
        switch LeagueID(path: league)?.sport ?? "" {
        case "football": return "football.fill"
        case "basketball": return "basketball.fill"
        case "baseball": return "baseball.fill"
        case "hockey": return "hockey.puck.fill"
        case "soccer": return "soccerball"
        default: return "sportscourt.fill"
        }
    }
}

extension View {
    /// Holds Dynamic Island text at the default text size. The island's
    /// regions are sized by the system and don't grow with Dynamic Type, so
    /// the text styles there name a role, not a size that may scale (§5.3).
    fileprivate func islandTextSize() -> some View {
        dynamicTypeSize(.large)
    }
}

extension GameActivityState {
    /// The scoreline as VoiceOver reads it, e.g. "Rams 26, Broncos 23":
    /// each side's name with its score, away first, as the "26–23" it
    /// stands for is drawn.
    fileprivate func spokenScore(_ game: GameActivityInfo) -> String {
        "\(game.awayName) \(awayScore), \(game.homeName) \(homeScore)"
    }

    /// Both scores together, which only rises: the value the "26–23"
    /// scoreline's numeric transition rolls towards (DI-2).
    fileprivate var scoreTotal: Double {
        Double(awayScore + homeScore)
    }
}

extension GameActivityAttributes {
    fileprivate static let preview = GameActivityAttributes(game: GameActivityInfo(
        gameID: "401872962", teamID: "7", league: "football/nfl",
        homeName: "Broncos", awayName: "Rams", matchup: "Rams at Broncos",
        kickoff: nil, favoriteID: "football/nfl:7"
    ))

    /// A followed team the bundle knows (the Chiefs), so the compact island
    /// shows its abbreviation and keyline rather than the sport's symbol.
    fileprivate static let seedPreview = GameActivityAttributes(game: GameActivityInfo(
        gameID: "401872963", teamID: "12", league: "football/nfl",
        homeName: "Broncos", awayName: "Chiefs", matchup: "Chiefs at Broncos",
        kickoff: nil, favoriteID: "football/nfl:12"
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

#Preview("Dynamic Island · compact, catalogued team", as: .dynamicIsland(.compact), using: GameActivityAttributes.seedPreview) {
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
