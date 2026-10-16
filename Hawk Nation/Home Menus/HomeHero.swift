//
//  HomeHero.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The colours Home's hero, and the bar over it, are drawn in: the
/// featured game's team colour, as a team page's hero is, or a neutral
/// brand band with no game to feature.
struct HomeHeroStyle {
    /// The flat colour behind the status bar, the navigation bar and the
    /// top of the hero, so the three meet without a seam.
    let fill: Color
    /// The colour the hero deepens to at its foot: `fill` again for a
    /// team; a darker brand tint for the neutral band.
    let footFill: Color
    /// Text and symbols on `fill`: the team's ink (G-3), or white.
    let ink: Color
    /// The bar's controls, in white or black for `fill` (H-6), as a team
    /// page's gear is.
    let barInk: Color
    /// The bar's scheme, so its title and status bar read on `fill`.
    let barScheme: ColorScheme

    /// The near-black every brand theme's dark icon sits on, which the
    /// neutral band mixes the theme's accent into.
    static let neutralBaseHex = "0E1016"

    /// How much of the accent the neutral band takes at its top and its
    /// foot. Never more than half: white ink reads at 4.5:1 or better on
    /// any accent mixed that far into the near-black base.
    static let neutralAccentShare = 0.45
    static let neutralFootAccentShare = 0.2

    init(featured: HomeFeaturedGame?, accent: Color) {
        if let team = featured?.team {
            let hex = TeamColors.fillHex(for: team)
            let barHex = TeamColors.inkHex(on: hex)
            fill = Color(hexString: hex)
            footFill = fill
            ink = TeamColors.ink(on: team)
            barInk = Color(hexString: barHex)
            barScheme = barHex == "FFFFFF" ? .dark : .light
        } else {
            let base = Color(hexString: Self.neutralBaseHex)
            fill = base.mix(with: accent, by: Self.neutralAccentShare)
            footFill = base.mix(with: accent, by: Self.neutralFootAccentShare)
            ink = .white
            barInk = .white
            barScheme = .dark
        }
    }
}

/// The top of Home, over the hero colour, under the bar's title and date
/// (`HomeHeroStyle`): the game that matters most right now
/// (`HomeFeed.featured`) — the one under way, the next one, or one just
/// played. Its kicker, the matchup away side first with each crest on a
/// white disc, the countdown, live score or final score between them, the
/// start and channel beneath, and the way into the game's sheet.
///
/// Plain scrolling content, as a team page's summary (`TeamPageHeader`)
/// is: it scrolls under the bar with the page, never over it.
struct HomeHero: View {
    let featured: HomeFeaturedGame?
    let style: HomeHeroStyle
    /// The favorites, whose crests the hero shows with no game to feature.
    let teams: [TeamRef]
    /// Whether the seasons are still loading, so a missing game is not yet
    /// "no games".
    let isLoading: Bool
    /// Home's clock (`HomeViewModel.now`), which a UI test may pin.
    let now: Date
    /// Where the game sheet zooms from (X-13).
    let zoomNamespace: Namespace.ID
    /// Opens the featured game's sheet, under `sourceID(for:)`.
    let openGame: @MainActor (HomeFeaturedGame) -> Void

    @ScaledMetric(relativeTo: .title3) private var crestSize: CGFloat = 56
    @ScaledMetric(relativeTo: .caption2) private var liveDotSize: CGFloat = 6

    /// How far Home's clock is from the device's: nothing, unless a UI test
    /// pinned Home's well away from it (`HomeViewModel.launchNowKey`), when
    /// the countdown runs from Home's moment rather than the device's. Home's
    /// own clock trails the device's by up to a minute, which isn't skew.
    private var clockSkew: TimeInterval {
        let skew = now.timeIntervalSinceNow
        return abs(skew) > 120 ? skew : 0
    }

    /// The zoom source a featured game's sheet opens from.
    static func sourceID(for featured: HomeFeaturedGame) -> String {
        "hero|\(featured.id)"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            if let featured {
                featuredContent(featured)
            } else if isLoading {
                loadingContent
            } else {
                quietContent
            }
        }
        .foregroundStyle(style.ink)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.hero")
    }

    // MARK: Featured

    private func featuredContent(_ featured: HomeFeaturedGame) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            kicker(featured)

            matchup(featured)

            if let meta = metaLine(featured) {
                Text(meta)
                    .font(Theme.Typography.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .opacity(0.9)
            }

            Button {
                openGame(featured)
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Game Details")
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // In the hero's ink, not the app's accent, which can vanish
            // into a team colour (H-6).
            .tint(style.ink)
            .zoomSource(id: Self.sourceID(for: featured), in: zoomNamespace)
            .accessibilityHint("Opens the game.")
            .accessibilityIdentifier("home.hero.details")
        }
    }

    /// "Next up", "Live" beside its pill, or "Final", with what the game is
    /// part of where the league alone doesn't say ("Week 7", "FA Cup").
    @ViewBuilder
    private func kicker(_ featured: HomeFeaturedGame) -> some View {
        let competition = GameCardContent.competitionLabel(of: featured.game, league: featured.team.league)
        HStack(spacing: Theme.Spacing.s) {
            switch featured.phase {
            case .live:
                LivePill(dotSize: liveDotSize)
            case .upcoming:
                Text("Next up")
                    .textCase(.uppercase)
            case .final:
                Text("Final")
                    .textCase(.uppercase)
            }
            if let competition {
                Text(competition)
                    .opacity(0.85)
            }
        }
        .font(.caption.weight(.heavy))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Away on the left, home on the right, as every matchup in the app
    /// reads; between them the countdown, or the score and its stage.
    private func matchup(_ featured: HomeFeaturedGame) -> some View {
        let favoriteIsHome = featured.favoriteIsHome
        return HStack(alignment: .center, spacing: Theme.Spacing.s) {
            side(featured, isFavorite: !favoriteIsHome)
            centre(featured)
                .layoutPriority(1)
            side(featured, isFavorite: favoriteIsHome)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenMatchup(featured))
    }

    /// One side: its crest on a white disc, so it reads on any team colour,
    /// over its short name.
    private func side(_ featured: HomeFeaturedGame, isFavorite: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            if isFavorite {
                HomeCrestDisc(team: featured.team, size: crestSize)
            } else {
                HomeOpponentCrest(game: featured.game, league: featured.team.league, size: crestSize)
            }
            Text(isFavorite ? featured.team.shortName : opponentName(featured.game))
                .font(.subheadline.weight(isFavorite ? .bold : .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func centre(_ featured: HomeFeaturedGame) -> some View {
        switch featured.phase {
        case .upcoming:
            // Ticks with the device every minute, from Home's moment.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HomeCountdown(start: featured.game.dateAsDate, now: context.date.addingTimeInterval(clockSkew))
            }
        case .live:
            VStack(spacing: Theme.Spacing.xs) {
                if let live = featured.live {
                    Text("\(live.state.awayScore) – \(live.state.homeScore)")
                        .font(.largeTitle.weight(.black).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .scoreTransition(value: Double(live.state.awayScore + live.state.homeScore))
                    Text(live.state.stage)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        case .final:
            VStack(spacing: Theme.Spacing.xs) {
                if let score = finalScore(featured) {
                    Text(score)
                        .font(.largeTitle.weight(.black).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let outcome = GameCardContent(game: featured.game, league: featured.team.league, now: now).outcomeLabel {
                    Text(outcome)
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                }
            }
        }
    }

    /// "Sun, Oct 18 · 8:25 PM · CBS" for a game to come; the channel and
    /// venue while it's live; the date and venue once it's over.
    private func metaLine(_ featured: HomeFeaturedGame) -> String? {
        let game = featured.game
        var parts: [String] = []
        switch featured.phase {
        case .upcoming:
            if !game.date.isEmpty {
                parts.append(GameCardContent.fullStart(of: game.dateAsDate, now: now))
            }
            if let broadcast = GameCardContent.broadcast(of: game) {
                parts.append(broadcast)
            }
        case .live:
            if let broadcast = GameCardContent.broadcast(of: game) {
                parts.append(broadcast)
            }
            if let venue = GameCardContent.venue(of: game) {
                parts.append(venue)
            }
        case .final:
            if !game.date.isEmpty {
                parts.append(GameCardContent.fullDate(of: game.dateAsDate, now: now))
            }
            if let venue = GameCardContent.venue(of: game) {
                parts.append(venue)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The final score away first, as the matchup reads: "17 – 24".
    private func finalScore(_ featured: HomeFeaturedGame) -> String? {
        let game = featured.game
        guard !game.score.isEmpty, !game.opponentScore.isEmpty else { return nil }
        return featured.favoriteIsHome
            ? "\(game.opponentScore) – \(game.score)"
            : "\(game.score) – \(game.opponentScore)"
    }

    private func opponentName(_ game: Game) -> String {
        game.opponent.isEmpty ? "TBD" : game.opponent
    }

    /// "Chiefs at Dolphins, Sun, Sep 27 · 12:00 PM, CBS"; "Rams 14,
    /// Broncos 21, 4th Quarter · 0:48" while it's live; "Final, Colts 10,
    /// Chiefs 24" once it's over.
    private func spokenMatchup(_ featured: HomeFeaturedGame) -> String {
        let favorite = featured.team.shortName
        let opponent = opponentName(featured.game)
        let away = featured.favoriteIsHome ? opponent : favorite
        let home = featured.favoriteIsHome ? favorite : opponent
        switch featured.phase {
        case .live:
            return featured.live?.accessibilityLabel ?? "\(away) at \(home), Live"
        case .upcoming:
            return (["\(away) at \(home)"] + [metaLine(featured)].compactMap { $0 }).joined(separator: ", ")
        case .final:
            let game = featured.game
            let awayScore = featured.favoriteIsHome ? game.opponentScore : game.score
            let homeScore = featured.favoriteIsHome ? game.score : game.opponentScore
            return "Final, \(away) \(awayScore), \(home) \(homeScore)"
        }
    }

    // MARK: Quiet and loading

    /// No game under way, to come, or just played: the favorites' crests
    /// and a line saying so.
    private var quietContent: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: -Theme.Spacing.s) {
                ForEach(Array(teams.prefix(5))) { team in
                    HomeCrestDisc(team: team, size: crestSize * 0.75)
                }
            }
            .accessibilityHidden(true)

            Text("No games coming up")
                .font(.headline)
            Text("Your teams' next game, live scores and results lead Home when there are some.")
                .font(Theme.Typography.footnote)
                .multilineTextAlignment(.center)
                .opacity(0.9)
        }
        .accessibilityElement(children: .combine)
    }

    /// The featured layout as a placeholder while the seasons load (D-7).
    private var loadingContent: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Next up")
                .font(.caption.weight(.heavy))
            HStack(spacing: Theme.Spacing.s) {
                Circle()
                    .frame(width: crestSize, height: crestSize)
                    .frame(maxWidth: .infinity)
                Text("0d 00h")
                    .font(Theme.Typography.statFigure)
                Circle()
                    .frame(width: crestSize, height: crestSize)
                    .frame(maxWidth: .infinity)
            }
            Text("Sun, Oct 18 · 8:25 PM · TV")
                .font(Theme.Typography.footnote)
        }
        .loadingPlaceholder()
    }
}

/// The time to a game's start as figures over their units — "1 DAY 4 HRS
/// 12 MIN", the days left off within a day — or "Starting" once it's
/// reached. One element to VoiceOver: "Starts in 1 day, 4 hours, 12
/// minutes".
private struct HomeCountdown: View {
    let start: Date
    let now: Date

    private struct Unit: Hashable {
        let value: Int
        let short: String
        let spoken: String
    }

    private var units: [Unit] {
        let remaining = max(0, Int(start.timeIntervalSince(now)))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let minute = Unit(value: minutes, short: "min", spoken: minutes == 1 ? "minute" : "minutes")
        let hour = Unit(value: hours, short: hours == 1 ? "hr" : "hrs", spoken: hours == 1 ? "hour" : "hours")
        guard days > 0 else { return [hour, minute] }
        let day = Unit(value: days, short: days == 1 ? "day" : "days", spoken: days == 1 ? "day" : "days")
        return [day, hour, minute]
    }

    var body: some View {
        if start <= now {
            Text("Starting")
                .font(.title3.weight(.heavy))
                .lineLimit(1)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                ForEach(units, id: \.self) { unit in
                    VStack(spacing: 0) {
                        Text("\(unit.value)")
                            .font(Theme.Typography.statFigure)
                            .lineLimit(1)
                        Text(unit.short)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                }
            }
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starts in " + units.map { "\($0.value) \($0.spoken)" }.joined(separator: ", "))
        }
    }
}

/// A favorite's crest on a white disc: legible on any team colour, light
/// or dark, whatever the crest's own colours.
struct HomeCrestDisc: View {
    let team: TeamRef
    let size: CGFloat

    var body: some View {
        TeamLogo(team: team, size: size * 0.7, forceVariant: .default)
            .frame(width: size, height: size)
            .background(Color.white, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// An opponent's crest on a white disc, from the schedule's logo, as a
/// schedule card draws it; a monogram where the feed gives none.
struct HomeOpponentCrest: View {
    let game: Game
    let league: LeagueID
    let size: CGFloat

    /// A stand-in team for the monogram: the opponent's name and an
    /// abbreviation from it, in a colour picked from its id.
    private var standIn: TeamRef {
        TeamRef(
            league: league, espnID: game.opponentID.isEmpty ? game.opponent : game.opponentID,
            displayName: game.opponent, shortName: game.opponent,
            abbreviation: String(game.opponent.prefix(3)).uppercased(), location: "",
            colorHex: "", alternateColorHex: "",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
    }

    var body: some View {
        let inner = size * 0.7
        Group {
            if game.opponentLogo.isEmpty {
                MonogramTeam(team: standIn, size: inner)
            } else {
                RemoteImage(url: URL(string: game.opponentLogo), showsProgress: false) {
                    MonogramTeam(team: standIn, size: inner)
                }
                .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: inner, height: inner)
        .frame(width: size, height: size)
        .background(Color.white, in: Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// "Live" beside a red dot, in primary text on the inset surface so it
/// reads the same over every team's colour, as a schedule card's status
/// pill does. The word says it too: never colour alone (G-4).
struct LivePill: View {
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(.red)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
            Text("Live")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        // The label colour itself, not `.primary`, which resolves to the
        // hero's inherited ink (white on a dark team colour), unreadable on
        // the near-white inset surface in light mode.
        .foregroundStyle(Color.primary)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Surface.insetCard, in: Theme.Radius.chip)
    }
}
