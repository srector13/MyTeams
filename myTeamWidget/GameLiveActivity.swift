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
import UIKit
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
            // hierarchical to match. A tap opens the game's sheet over the
            // followed team's page (R-3).
            GameActivityBanner(game: context.attributes.game, state: context.state, isStale: context.isStale)
                .widgetURL(context.attributes.game.gameLink)
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
            // The followed team's colour on the island's rim (DI-2): the
            // bundle's, else the one the app stored at the start (B-13),
            // else the system's own.
            .keylineTint(game.followedKeylineHex.map { Color(hexString: $0) })
            .widgetURL(game.gameLink)
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

    /// The followed team's crest, which scales with the names beside it.
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            // Whose game this is (LA-3), as the island's leading mark says
            // (DI-1). Only where the app has stored the crest: nothing is
            // fetched here, and nothing rides in the payload (§5.4).
            if let crest = game.followedCrest {
                Image(uiImage: crest)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: crestSize, height: crestSize)
                    .accessibilityHidden(true)
            }

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
                // Rolls the digits when this side scores, as the island
                // does (LA-3, DI-2); a cross-fade under Reduce Motion.
                .scoreTransition(value: Double(score))
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
/// The bundled catalog wins where it knows the team. Any other team is
/// marked with the abbreviation the app stored in the static attributes
/// when it started the activity (`GameActivityInfo.favoriteAbbreviation`,
/// B-13). Without either — an activity started before the team resolved,
/// or by an older build — the mark is its sport's symbol: the payload
/// doesn't say whether the followed team is home or away, and a guessed
/// name would be the opponent's half the time.
private struct FollowedTeamMark: View {
    var game: GameActivityInfo

    var body: some View {
        if let team = game.followedTeam, !team.abbreviation.isEmpty {
            abbreviation(team.abbreviation)
                .accessibilityLabel(team.displayName)
        } else if let stored = game.followedAbbreviation {
            // The stored mark names no team in full; the matchup does.
            abbreviation(stored)
                .accessibilityLabel(game.matchup)
        } else {
            Image(systemName: game.sportSymbol)
                .font(.caption.weight(.semibold))
                .accessibilityLabel(game.matchup)
        }
    }

    private func abbreviation(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

extension GameActivityInfo {
    /// The followed team, if the bundled catalog has it. Read from
    /// `favoriteID`, checked against `teamID`; an activity started before
    /// `favoriteID` was kept falls back to the board's league, which is the
    /// team's own outside cup ties.
    fileprivate var followedTeam: TeamRef? {
        followedTeamID.flatMap(TeamCatalog.team(id:))
    }

    /// The abbreviation the app stored for the followed team, if any and
    /// not blank. Only read where the bundle doesn't know the team.
    fileprivate var followedAbbreviation: String? {
        guard let stored = favoriteAbbreviation?.trimmingCharacters(in: .whitespaces),
              !stored.isEmpty
        else { return nil }
        return stored
    }

    /// The island's keyline colour, as hex: the bundled team's fill, else
    /// the colour the app stored at the start when it reads as one, else
    /// `nil` for the system's own.
    fileprivate var followedKeylineHex: String? {
        if let team = followedTeam {
            return TeamColors.fillHex(for: team)
        }
        guard let stored = favoriteColorHex,
              TeamColors.relativeLuminance(hex: stored) != nil
        else { return nil }
        return stored
    }

    /// The followed team's `TeamRef.id`: `favoriteID`, or else the board's
    /// league, as long as it names `teamID`.
    private var followedTeamID: TeamRef.ID? {
        let id = favoriteID ?? LeagueID(path: league).map { TeamRef.id(league: $0, espnID: teamID) }
        guard let id, let parsed = TeamRef.parse(id: id), parsed.espnID == teamID else { return nil }
        return id
    }

    /// The followed team's crest, if `LogoStore` has it: the app stores
    /// its favorites' crests in the app group, which this extension
    /// shares. Read from disk only, so the payload stays within its size
    /// budget (§5.4) and the banner never waits on the network (LA-3).
    fileprivate var followedCrest: UIImage? {
        guard let id = followedTeamID, let parsed = TeamRef.parse(id: id) else { return nil }
        // `LogoStore` files a crest under its league and ESPN id alone,
        // so a team the bundle doesn't know needs only those.
        let team = TeamCatalog.team(id: id) ?? TeamRef(
            league: parsed.league, espnID: parsed.espnID,
            displayName: "", shortName: "",
            abbreviation: "", location: "",
            colorHex: "", alternateColorHex: "",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        return LogoStore.image(for: team, variant: .default)
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

    /// A followed team the bundle doesn't know (Arsenal), marked by the
    /// abbreviation and colour the app stored at the start (B-13).
    fileprivate static let storedIdentityPreview = GameActivityAttributes(game: GameActivityInfo(
        gameID: "401915423", teamID: "359", league: "soccer/uefa.champions",
        homeName: "Napoli", awayName: "Arsenal", matchup: "Arsenal at Napoli",
        kickoff: nil, favoriteID: "soccer/eng.1:359",
        favoriteAbbreviation: "ARS", favoriteColorHex: "E20520"
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

#Preview("Dynamic Island · compact, stored identity", as: .dynamicIsland(.compact), using: GameActivityAttributes.storedIdentityPreview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 1, awayScore: 2, period: 3, clock: "97'", phase: .live, periodLabel: "Extra Time")
}

#Preview("Dynamic Island · minimal", as: .dynamicIsland(.minimal), using: GameActivityAttributes.preview) {
    GameLiveActivity()
} contentStates: {
    GameActivityState(homeScore: 23, awayScore: 26, period: 4, clock: "0:48", phase: .live)
}

private extension GameActivityInfo {
    /// The `myteams://game/` link to the game's sheet over the followed
    /// team's page (R-3); the team's page alone if the league is not a
    /// path; nothing without the team.
    var gameLink: URL? {
        guard let favoriteID else { return nil }
        return LeagueID(path: league)
            .flatMap { WidgetDeepLink.url(forGame: gameID, league: $0, teamID: favoriteID) }
            ?? deepLink
    }
}
#endif
