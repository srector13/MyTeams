//
//  NextGameIntent.swift
//  myTeams
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import AppIntents
import SwiftUI

/// "When do the Chiefs play next?" (R-12): Siri speaks the team's featured
/// game and shows it as a snippet, without opening the app.
///
/// The game is the one the widget features (`WidgetFeaturedGame`): a game
/// under way, else today's result, else the next fixture. All the work is in
/// `NextGameAnswer`, which tests drive without the intent machinery.
struct NextGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Game"
    static let description = IntentDescription("Tells you when a team plays next, and who against.")

    @Parameter(title: "Team")
    var team: TeamEntity

    init() {}

    init(team: TeamEntity) {
        self.team = team
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let answer = await NextGameAnswer.load(for: team.team)
        let speech: LocalizedStringResource = "\(answer.speech)"
        return .result(dialog: IntentDialog(speech), view: NextGameSnippet(answer: answer))
    }
}

/// A team's featured game, as Siri says it and the snippet shows it.
struct NextGameAnswer: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The next fixture, at `kickoff`.
        case next
        /// A game under way.
        case live
        /// A game finished today.
        case result
        /// The schedule loaded with nothing left to play.
        case seasonOver
        /// The schedule could not be loaded.
        case failed
    }

    let team: TeamRef
    let kind: Kind
    /// The opponent, as the schedule names it; empty without a game.
    var opponent = ""
    /// A fixture's start.
    var kickoff: Date?
    /// When a fixture starts, as said: "on Sunday at 4:20 PM". For a game
    /// under way or finished, its status ("Live · 67'", "Final").
    var when = ""
    /// A game under way or finished: the score, the followed team's first.
    var score = ""
    /// The channel, where the feed names one.
    var channel: String?
    /// The sentence Siri says and shows.
    var speech = ""

    // MARK: Loading

    /// Loads `team`'s featured game the way the widget does
    /// (`WidgetScheduleLoader.featuredGame`): the schedule
    /// (`downloadScheduleData`, served from its cache when fresh) and the
    /// app's scoreboard snapshots, picked by `WidgetFeaturedGame.pick`.
    /// Tests pass their own schedule and snapshots.
    static func load(
        for team: TeamRef,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        schedule: (TeamRef) async -> Result<[Game], NetworkError> = { await downloadScheduleData(team: $0) },
        snapshots: [WidgetScoreboardSnapshot]? = nil
    ) async -> NextGameAnswer {
        let games: [Game]?
        if case .success(let loaded) = await schedule(team) {
            games = loaded
        } else {
            games = nil
        }
        let featured = WidgetFeaturedGame.pick(
            teamID: team.id,
            snapshots: snapshots ?? WidgetScoreboardCodec.read(),
            schedule: games ?? [],
            now: now,
            calendar: calendar
        )
        return answer(for: team, featured: featured, schedule: games, now: now, calendar: calendar, locale: locale)
    }

    /// The answer for `featured`, naming the opponent as the schedule does
    /// when it has the game. `schedule` is `nil` when it failed to load.
    static func answer(
        for team: TeamRef,
        featured: WidgetFeaturedGame,
        schedule: [Game]?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> NextGameAnswer {
        let name = team.shortName
        switch featured {
        case .live(let snapshot), .result(let snapshot):
            let scheduled = schedule?.first { !$0.gameID.isEmpty && $0.gameID == snapshot.gameID }
            let isLive = snapshot.state == .inProgress
            var answer = NextGameAnswer(team: team, kind: isLive ? .live : .result)
            answer.opponent = scheduled?.opponent ?? snapshot.opponentName(of: team.espnID)
            answer.when = snapshot.statusText
            answer.score = snapshot.score(for: team.espnID)
            answer.channel = isLive ? scheduled.flatMap(GameCardContent.broadcast(of:)) : nil
            answer.speech = isLive
                ? "\(name) are playing \(answer.opponent) right now: \(answer.score), \(answer.when)."
                : "\(name) played \(answer.opponent) today: \(answer.when), \(answer.score)."
            return answer
        case .scheduleResult(let game):
            var answer = NextGameAnswer(team: team, kind: .result)
            answer.opponent = game.opponent
            answer.when = "Final"
            answer.score = "\(game.score)–\(game.opponentScore)"
            answer.speech = "\(name) played \(game.opponent) today: Final, \(answer.score)."
            return answer
        case .next(let game):
            var answer = NextGameAnswer(team: team, kind: .next)
            answer.opponent = game.opponent
            answer.kickoff = game.dateAsDate
            answer.when = spokenWhen(game.dateAsDate, now: now, calendar: calendar, locale: locale)
            answer.channel = GameCardContent.broadcast(of: game)
            answer.speech = "\(name) play next \(answer.when) against \(game.opponent)"
                + (answer.channel.map { ", on \($0)." } ?? ".")
            return answer
        case .none:
            guard schedule != nil else {
                var answer = NextGameAnswer(team: team, kind: .failed)
                answer.speech = "I couldn't load the schedule for \(name). Try again in a moment."
                return answer
            }
            var answer = NextGameAnswer(team: team, kind: .seasonOver)
            answer.speech = "\(name) have no games left on their schedule."
            return answer
        }
    }

    // MARK: Wording

    /// When a fixture starts, as said after "play next": "today at 7:30
    /// PM", "tomorrow at 1:00 PM", "on Sunday at 4:20 PM" within the week,
    /// "on Sunday, October 18 at 4:20 PM" beyond it. On the reader's own
    /// clock (A-13).
    static func spokenWhen(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let time = format(date, template: "jmm", calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return "today at \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? .max
        let day = format(date, template: days < 7 ? "EEEE" : "EEEEMMMMd", calendar: calendar, locale: locale)
        return "on \(day) at \(time)"
    }

    /// `date` in `template`'s fields, ordered for `locale`, in `calendar`'s
    /// time zone.
    static func format(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    // MARK: Snippet

    /// The snippet's lines under the team's name: the opponent, then when
    /// (or the score and status), then the channel.
    var snippetLines: [String] {
        switch kind {
        case .next:
            var lines = ["vs \(opponent)", when.prefix(1).uppercased() + String(when.dropFirst())]
            if let channel { lines.append(channel) }
            return lines
        case .live, .result:
            var lines = ["vs \(opponent)", "\(score) · \(when)"]
            if let channel { lines.append(channel) }
            return lines
        case .seasonOver:
            return ["No upcoming games"]
        case .failed:
            return ["Couldn't update"]
        }
    }
}

/// The snippet Siri shows under its answer: the team's name in its colour,
/// and the game.
struct NextGameSnippet: View {
    let answer: NextGameAnswer

    private var teamColor: Color { Color(hexString: TeamColors.fillHex(for: answer.team)) }

    var body: some View {
        HStack(spacing: 14) {
            Text(answer.team.abbreviation.isEmpty ? answer.team.shortName.prefix(3).uppercased() : answer.team.abbreviation)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 52, height: 52)
                .background(teamColor, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(answer.team.displayName)
                    .font(.headline)
                ForEach(Array(answer.snippetLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
