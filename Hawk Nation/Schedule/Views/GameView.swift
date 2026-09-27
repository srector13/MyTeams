//
//  GameView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/26/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct LoadingGameView : View {
    var body: some View {
        LoadingView()
            .frame(width: 120, height: 160)
    }
}

/// A game's card in a schedule carousel: the opponent and kick-off, overlaid
/// with the result, the live state, or a cancellation.
///
/// What differs by sport — what a level result is called, and how a game in
/// progress is drawn — comes from the league's `LeagueDescriptor`.
struct GameView : View {

    var game: Game
    var team: TeamRef

    /// The in-progress score the team model polls for this game, if any.
    /// Past and future fixtures carry no live score; they render from the
    /// schedule feed's own fields.
    var liveScore: LiveGameScore?

    private var teamColor: Color { team.color }

    private var league: LeagueDescriptor { team.league.descriptor }

    var body: some View {
        VStack(spacing: 0) {
            ZStack() {
                Rectangle()
                    .foregroundStyle(teamColor)

                TeamLogo(team: team, size: 200, forceVariant: .default)
                    .opacity(0.1)
                    .saturation(0.1)
                    .contrast(0.5)
                    .offset(x: 40, y: 50)
                if(game.cancelled || game.postponed) {
                    Group {
                        ZStack {
                            GameCardDetails(game: game, dimmed: false)

                            tint

                            if(game.cancelled) {
                                Text("Cancelled")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
                            } else if (game.postponed) {
                                Text("Postponed")
                                    .font(.system(size: 20))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
                            }
                        }
                    }
                } else {
                    if(game.completed) {
                        Group {
                            ZStack {
                                GameCardDetails(game: game, dimmed: true)

                                tint

                                if (game.gameWin) {
                                    result("Win", score: game.score + " - " + game.opponentScore)
                                } else if (game.isDraw) {
                                    result(league.drawLabel, score: game.score + " - " + game.opponentScore)
                                } else {
                                    result("Loss", score: game.opponentScore + " - " + game.score)
                                }
                            }
                        }
                    } else {
                        if(game.dateAsDate < Date()) {
                            Group {
                                ZStack {
                                    GameCardDetails(game: game, dimmed: true)

                                    tint

                                    switch league.liveCardStyle {
                                    case .periodFirst:
                                        periodFirstLiveState
                                    case .scoreFirst:
                                        scoreFirstLiveState
                                    }
                                }
                            }
                        } else {
                            Group {
                                GameCardDetails(game: game, dimmed: false)
                            }
                        }
                    }
                }


            }.frame(height: 120)
            ZStack() {
                Rectangle()
                    .foregroundStyle(Color(uiColor: .systemGray4))

                Group() {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: 80, height: 25)
                        .foregroundStyle(teamColor)

                    Text("Info")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }

            }.frame(height: 40)

        }.background(Color(uiColor: .systemBackground))
            .frame(width: 120, height: 160)
            .clipShape(.rect(cornerRadius: 10))
    }

    /// The team-coloured wash laid over the details beneath a status.
    private var tint: some View {
        Rectangle()
            .foregroundStyle(teamColor)
            .opacity(0.5)
    }

    /// A finished game's outcome over its final score.
    private func result(_ outcome: String, score: String) -> some View {
        VStack {
            Text(outcome)
                .font(.system(size: 24))
                .fontWeight(.bold)
                .foregroundStyle(Color.white)

            Text(score)
                .font(.system(size: 20))
                .fontWeight(.heavy)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color.white)
        }
    }

    /// A game in progress as `LiveCardStyle.periodFirst` draws it.
    private var periodFirstLiveState: some View {
        VStack {
            if(game.gameHalftime) {
                liveLine("Halftime", size: 15)
            } else {
                liveLine(team.periodName(game.gamePeriod), size: 15)
                liveLine(game.gameClock, size: 15)
            }

            if let liveScore {
                liveScoreText(liveScore)
            }
        }
    }

    /// A game in progress as `LiveCardStyle.scoreFirst` draws it: an arrow
    /// beside the score says whether the followed team leads or trails. With
    /// no live score yet, only the tinted details show.
    @ViewBuilder
    private var scoreFirstLiveState: some View {
        if let liveScore, liveScore.score > liveScore.opponentScore {
            VStack {
                HStack() {
                    liveScoreText(liveScore)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green)
                }

                liveLine(team.periodName(game.gamePeriod), size: 15)
                liveLine(game.gameClock, size: 15)
            }
        } else if let liveScore, liveScore.score == liveScore.opponentScore {
            VStack {
                liveScoreText(liveScore)

                liveLine(team.periodName(game.gamePeriod), size: 15)
                liveLine(game.gameClock, size: 15)
            }
        } else if let liveScore {
            VStack {
                HStack() {
                    liveScoreText(liveScore)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.red)
                }

                liveLine(team.periodName(game.gamePeriod), size: 12)
                liveLine(game.gameClock, size: 12)
            }
        }
    }

    private func liveScoreText(_ liveScore: LiveGameScore) -> some View {
        Text("\(liveScore.score) - \(liveScore.opponentScore)")
            .font(.system(size: 24))
            .fontWeight(.heavy)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color.white)
    }

    private func liveLine(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size))
            .fontWeight(.bold)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color.white)
    }
}

/// The opponent, its crest, and the date, time and channel on a game card.
///
/// Dimmed beneath a result or live state; full strength on a fixture still to
/// come, or beneath a cancellation.
private struct GameCardDetails: View {
    var game: Game
    var dimmed: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(game.opponent)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundStyle(Color.white)

            if dimmed {
                RemoteImage(url: URL(string: game.opponentLogo)) {
                    Image("blankTeam")
                        .resizable()
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .opacity(0.5)
            } else if(game.opponentLogo == "") {
                Image("blankTeam")
                    .resizable()
                    .frame(width: 60, height: 60)
            } else {
                RemoteImage(url: URL(string: game.opponentLogo))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
            }

            line(game.date)
            line(game.time)
            line(game.channel)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .fontWeight(.medium)
            .foregroundStyle(Color.white)
            .opacity(dimmed ? 0.5 : 1)
    }
}
