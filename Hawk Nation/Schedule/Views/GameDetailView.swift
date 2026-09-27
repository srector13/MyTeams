//
//  GameDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 1/27/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The sheet a schedule card opens: the venue, the scoreline and the box
/// score, refreshed while the game is live.
///
/// The box score comes through `LeagueDescriptor.downloadGameSheet`, which
/// reduces each sport's statistics to the same `BoxScore` rows.
struct GameDetailView: View {
    @Environment(\.containerSize) private var containerSize

    let game: Game
    let team: TeamRef

    @State private var boxScore: BoxScore?
    @State private var gameInfo = GameInfo.empty
    @State private var loading = true

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
                GameDetailSkeleton()
            } else {
                VStack {
                    header

                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 20)
                                .frame(width: (containerSize.width - 25), height: 600)
                                .foregroundStyle(Color(uiColor: .systemBackground))

                            VStack(alignment: .center, spacing: 15) {
                                if(game.cancelled) {
                                    Spacer()

                                    message("This game has been canceled.")
                                } else if (game.postponed) {
                                    Spacer()

                                    message("This game has been postponed.")
                                } else if game.dateAsDate <= Date(), let boxScore {
                                    scoreboard(boxScore)

                                    ForEach(boxScore.rows) { row in
                                        StatRowView(title: row.title, homeStat: row.home, awayStat: row.away)
                                    }
                                } else {
                                    Spacer()

                                    message("No game statistics at this time. Please check back later.")
                                        .offset(y: -50)
                                }

                                Spacer()
                            }.padding([.all], 20)
                        }
                        .ignoresSafeArea(.top)
                        Spacer()
                    }
                }
            }

            Spacer()
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .pollingTask {
            guard let sheet = await league.downloadGameSheet(
                gameID: game.gameID,
                team: team,
                followedIsHome: game.gameHome
            ) else {
                // Keep the last good box score through a failed refresh.
                // With nothing loaded yet, show the "no statistics" message
                // rather than a blank sheet while retrying.
                if loading {
                    boxScore = nil
                    loading = false
                }
                return GameSheet.retryInterval
            }

            boxScore = sheet.boxScore
            gameInfo = sheet.info
            loading = false
            return sheet.refreshInterval
        }
    }

    // MARK: - Header

    /// The venue behind the competition, kick-off, channel and location.
    private var header: some View {
        ZStack(alignment: .top) {
            // Takes up the sheet's full width.
            HStack() {
                Spacer()
            }

            if let backdrop = league.venueBackdropAsset {
                Image(backdrop)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: 200)
                    .clipShape(.rect(cornerRadius: 10))
            } else {
                RemoteImage(url: URL(string: gameInfo.venueImage))
                    .id(gameInfo.venueImage)
                    .frame(width: containerSize.width, height: 200)
                    .clipShape(.rect(cornerRadius: 10))
            }

            Rectangle()
                .foregroundStyle(Color(hexString: gameInfo.gameColor))
                .background(Color(uiColor: .black))
                .opacity(0.6)
                .frame(width: containerSize.width, height: 200)
                .clipShape(.rect(cornerRadius: 10))

            VStack(spacing: 0) {
                GameDetailDismissHandle()

                Text(game.competitionName)
                    .fontWeight(.bold)
                    .font(.system(size: 25))
                    .minimumScaleFactor(0.2)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.top, 5)

                Spacer()

                headerLine(game.time)
                headerLine(game.date)
                headerLine(game.channel)

                Spacer()

                headerLine(venueLine)
            }.padding(.horizontal, 15)
        }.frame(height: 200)
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
            .fontWeight(.bold)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .padding(.bottom, 10)
            .minimumScaleFactor(0.2)
    }

    // MARK: - Scoreboard

    /// Both crests and the scoreline, home team on the left.
    private func scoreboard(_ boxScore: BoxScore) -> some View {
        HStack(alignment: .top) {
            HStack() {
                side(followed: game.gameHome, alignment: .leading)

                VStack(alignment: .center) {
                    Text("\(boxScore.homeScore) - \(boxScore.awayScore)")
                        .font(.system(size: 30))
                        .fontWeight(.bold)

                    status
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                side(followed: !game.gameHome, alignment: .trailing)
            }
        }.ignoresSafeArea()
    }

    /// One team's crest over its name.
    private func side(followed: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            if followed {
                TeamLogo(team: team, size: 50)
            } else {
                RemoteImage(url: URL(string: game.opponentLogo)) {
                    Image("blankTeam")
                        .resizable()
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
            }

            Text(followed ? teamLabel : game.opponent)
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .systemGray))
                .fontWeight(.bold)
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
            statusLine(team.periodName(game.gamePeriod))
            statusLine(game.gameClock)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .fontWeight(.bold)
            .minimumScaleFactor(0.5)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color(uiColor: .systemGray))
            .fontWeight(.bold)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
    }
}

/// The bar at the top of a game sheet that closes it.
private struct GameDetailDismissHandle: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: {
            dismiss()
        }) {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: 100, height: 5)
                .foregroundStyle(Color(uiColor: .white))
                .opacity(0.7)
        }.padding([.top, .trailing, .leading, .bottom], 10)
    }
}

/// The game sheet's placeholder until its first summary arrives, laid out
/// like the header and scoreboard it stands in for.
private struct GameDetailSkeleton: View {
    @Environment(\.containerSize) private var containerSize

    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                // Takes up the sheet's full width.
                HStack() {
                    Spacer()
                }

                LoadingView()
                    .frame(width: containerSize.width, height: 200)

                VStack(spacing: 5) {
                    GameDetailDismissHandle()

                    LoadingView()
                        .frame(width: containerSize.width-20, height: 25)

                    Spacer()

                    LoadingView()
                        .frame(width: 100, height: 15)

                    LoadingView()
                        .frame(width: 120, height: 15)

                    LoadingView()
                        .frame(width: 50, height: 15)

                    Spacer()

                    LoadingView()
                        .frame(width: 200, height: 15)
                        .padding(.bottom, 10)
                }.padding(.horizontal, 15)
            }.frame(height: 200)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(width: (containerSize.width - 25), height: 600)
                        .foregroundStyle(Color(uiColor: .systemBackground))

                    VStack(alignment: .center, spacing: 15) {
                        HStack() {
                            crest(alignment: .leading)

                            VStack(alignment: .center) {
                                LoadingView()
                                    .frame(width: 200, height: 30)

                                LoadingView()
                                    .frame(width: 50, height: 15)
                            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                            crest(alignment: .trailing)
                        }

                        Spacer()
                    }.padding([.all], 20)
                }
                .ignoresSafeArea(.top)
                Spacer()
            }
        }
    }

    private func crest(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            LoadingViewCircle()
                .frame(width: 50, height: 50)

            LoadingView()
                .frame(width: 75, height: 15)
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}
