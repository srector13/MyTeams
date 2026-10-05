//
//  GameCardContentTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// What a schedule card says about a game (`GameCardContent`): its status
/// pill, outcome, live period and detail rows, and the rows it leaves out
/// for a sparse feed.
@Suite("Schedule game card")
struct GameCardContentTests {
    /// Fixed so the labels don't depend on the machine running the tests.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Sunday, Oct 4, 2026, 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_115_200)

    private var calendar: Calendar { Self.calendar }
    private var now: Date { Self.now }

    private func game(
        opponent: String = "Raiders",
        score: String = "",
        opponentScore: String = "",
        start: Date = GameCardContentTests.now.addingTimeInterval(3 * 86_400),
        date: String = "Oct 07, 2026",
        channel: String = "ESPN",
        location: String = "Arrowhead Stadium",
        home: Bool = true,
        win: Bool = false,
        completed: Bool = false,
        cancelled: Bool = false,
        postponed: Bool = false,
        clock: String = "",
        period: String = "",
        halftime: Bool = false,
        competition: LeagueID? = nil,
        seasonType: Int? = nil,
        neutralSite: Bool = false,
        leagueName: String = "",
        weekText: String = ""
    ) -> Game {
        Game(
            team: "Chiefs", opponent: opponent, score: score, opponentScore: opponentScore,
            time: "", date: date, dateAsDate: start, opponentLogo: "", channel: channel,
            location: location, gameHome: home, gameID: "1", pointer: 0,
            gameWin: win, completed: completed, competitionName: "",
            cancelled: cancelled, postponed: postponed, gameClock: clock,
            gamePeriod: period, gameHalftime: halftime, competition: competition,
            seasonType: seasonType, neutralSite: neutralSite, leagueName: leagueName, weekText: weekText
        )
    }

    private func content(_ game: Game, league: LeagueID = .nfl, liveScore: LiveGameScore? = nil) -> GameCardContent {
        GameCardContent(game: game, league: league, liveScore: liveScore, now: now, calendar: calendar)
    }

    private func time(_ date: Date) -> String {
        GameCardContent.timeLabel(of: date, calendar: calendar)
    }

    // MARK: Relative start

    @Test("Inside the hour the pill counts down in whole minutes")
    func countdown() {
        let label = { (offset: TimeInterval) in
            GameCardContent.startLabel(for: self.now.addingTimeInterval(offset), now: self.now, calendar: self.calendar)
        }
        #expect(label(25 * 60) == "In 25 min")
        #expect(label(24 * 60 + 10) == "In 25 min")
        #expect(label(30) == "In 1 min")
        // The hour itself is "Today", not a 60-minute countdown.
        let hour = now.addingTimeInterval(3_600)
        #expect(label(3_600) == "Today \(time(hour))")
    }

    @Test("Later today, tomorrow, this week and beyond")
    func relativeDays() {
        let later = now.addingTimeInterval(3 * 3_600)
        #expect(GameCardContent.startLabel(for: later, now: now, calendar: calendar) == "Today \(time(later))")
        #expect(time(later).contains("3:00"))

        let tomorrow = now.addingTimeInterval(86_400)
        #expect(GameCardContent.startLabel(for: tomorrow, now: now, calendar: calendar) == "Tomorrow \(time(tomorrow))")

        // Wednesday, three days on.
        let wednesday = now.addingTimeInterval(3 * 86_400)
        #expect(GameCardContent.startLabel(for: wednesday, now: now, calendar: calendar) == "Wed \(time(wednesday))")

        let farOff = now.addingTimeInterval(10 * 86_400)
        #expect(GameCardContent.startLabel(for: farOff, now: now, calendar: calendar) == "Oct 14")
    }

    @Test("The full date names the year only when it isn't this one")
    func fullDate() {
        let wednesday = now.addingTimeInterval(3 * 86_400)
        #expect(GameCardContent.fullDate(of: wednesday, now: now, calendar: calendar) == "Wed, Oct 7")
        #expect(GameCardContent.fullStart(of: wednesday, now: now, calendar: calendar)
            == "Wed, Oct 7 · \(time(wednesday))")

        let nextYear = now.addingTimeInterval(90 * 86_400)
        #expect(GameCardContent.fullDate(of: nextYear, now: now, calendar: calendar).contains("2027"))
    }

    // MARK: Phase and status

    @Test("Status pill for each phase")
    func phases() {
        #expect(content(game(cancelled: true)).status == "Cancelled")
        #expect(content(game(postponed: true)).phase == .postponed)
        #expect(content(game(completed: true)).status == "Final")

        let started = content(game(start: now.addingTimeInterval(-600)))
        #expect(started.phase == .live)
        #expect(started.status == "Live")

        let upcoming = content(game())
        #expect(upcoming.phase == .upcoming)
        #expect(upcoming.status == "Wed \(time(now.addingTimeInterval(3 * 86_400)))")
    }

    @Test("A polled live score makes a game live; an unreadable date never does")
    func livenessEdges() {
        let early = game(start: now.addingTimeInterval(600))
        #expect(content(early, liveScore: LiveGameScore(score: 0, opponentScore: 0)).phase == .live)

        // The parser leaves `date` empty and `dateAsDate` at parse time.
        let unreadable = content(game(start: now.addingTimeInterval(-86_400), date: ""))
        #expect(unreadable.phase == .upcoming)
        #expect(unreadable.status == "TBD")
        #expect(unreadable.dateLine == nil)
    }

    // MARK: Outcome

    @Test("A win and a loss show the winner's score first")
    func winAndLoss() {
        let win = content(game(score: "24", opponentScore: "10", win: true, completed: true))
        #expect(win.outcome == .win)
        #expect(win.outcomeLabel == "Win")
        #expect(win.finalScore == "24 – 10")

        let loss = content(game(score: "10", opponentScore: "24", completed: true))
        #expect(loss.outcome == .loss)
        #expect(loss.outcomeLabel == "Loss")
        #expect(loss.finalScore == "24 – 10")
    }

    @Test("A level result takes the league's word for it")
    func draw() {
        let level = game(score: "1", opponentScore: "1", completed: true)
        #expect(content(level, league: .mls).outcomeLabel == "Draw")
        #expect(content(level, league: .nfl).outcomeLabel == "Tie")
        #expect(content(level).outcome == .draw)
    }

    @Test("A finished game with no score published says Final and nothing more")
    func finalWithoutScore() {
        let bare = content(game(completed: true))
        #expect(bare.status == "Final")
        #expect(bare.outcome == nil)
        #expect(bare.outcomeLabel == nil)
        #expect(bare.finalScore == nil)
    }

    // MARK: Live stage

    @Test("Live period and clock by sport")
    func liveStage() {
        let nfl = LeagueID.nfl.descriptor
        #expect(GameCardContent.liveStage(of: game(clock: "14:14", period: "2"), league: nfl) == "2nd Quarter · 14:14")
        #expect(GameCardContent.liveStage(of: game(clock: "3:12", period: "5"), league: nfl) == "OT · 3:12")
        #expect(GameCardContent.liveStage(of: game(clock: "0:00", period: "2", halftime: true), league: nfl) == "Halftime")
        #expect(GameCardContent.liveStage(of: game(clock: "15:00", period: ""), league: nfl) == nil)

        // Innings are named on the card, without baseball's empty clock.
        let mlb = LeagueID.mlb.descriptor
        #expect(GameCardContent.liveStage(of: game(clock: "0:00", period: "5"), league: mlb) == "5th Inning")

        let soccer = LeagueID.bundesliga.descriptor
        #expect(GameCardContent.liveStage(of: game(clock: "67'", period: "2"), league: soccer) == "2nd Half · 67'")
    }

    @Test("Only a live card carries a stage")
    func stageOnlyWhenLive() {
        #expect(content(game(clock: "14:14", period: "2")).liveStage == nil)
        let live = content(game(start: now.addingTimeInterval(-600), clock: "14:14", period: "2"))
        #expect(live.liveStage == "2nd Quarter · 14:14")
    }

    // MARK: Side and opponent

    @Test("Home, away, or neutral whatever the home flag says")
    func side() {
        #expect(content(game(home: true)).side == "Home")
        #expect(content(game(home: false)).side == "Away")
        #expect(content(game(home: true, neutralSite: true)).side == "Neutral")
    }

    @Test("An unnamed opponent reads TBD, not blank")
    func unnamedOpponent() {
        #expect(content(game(opponent: "")).opponent == "TBD")
        #expect(content(game(opponent: "Borussia Mönchengladbach")).opponent == "Borussia Mönchengladbach")
    }

    // MARK: Details

    @Test("An upcoming game: week, channel and venue; its date is in the header")
    func upcomingDetails() {
        let card = content(game(weekText: "Week 5"))
        #expect(card.details == [
            GameCardContent.Detail(kind: .competition, text: "Week 5"),
            GameCardContent.Detail(kind: .broadcast, text: "ESPN"),
            GameCardContent.Detail(kind: .venue, text: "Arrowhead Stadium"),
        ])
        #expect(card.dateLine == "Wed, Oct 7 · \(time(now.addingTimeInterval(3 * 86_400)))")
    }

    @Test("A finished game: its date replaces the channel")
    func finalDetails() {
        let played = game(score: "24", opponentScore: "10", start: now.addingTimeInterval(-7 * 86_400),
                          date: "Sep 27, 2026", win: true, completed: true)
        #expect(content(played).details.map(\.kind) == [.date, .venue])
        #expect(content(played).details.first?.text == "Sun, Sep 27")
        #expect(content(played).dateLine == nil)
    }

    @Test("A sparse soccer fixture leaves out every row it has nothing for")
    func sparseFeed() {
        // A Bundesliga league game with no channel (the parser's "TBD"),
        // no venue, no period.
        let sparse = game(
            opponent: "Augsburg", channel: "TBD", location: "  ",
            competition: .bundesliga, seasonType: 14358, leagueName: "Bundesliga"
        )
        let card = content(sparse, league: .bundesliga)
        #expect(card.details.isEmpty)
        #expect(card.liveStage == nil)
        #expect(card.outcomeLabel == nil)

        // Nor does a live sparse game make up a period.
        let live = content(game(start: now.addingTimeInterval(-600), channel: "", location: "",
                                competition: .bundesliga), league: .bundesliga)
        #expect(live.status == "Live")
        #expect(live.liveStage == nil)
        #expect(live.details.isEmpty)
    }

    @Test("No row ever reads nil, TBD or blank")
    func noPlaceholderText() {
        let cases = [
            game(channel: "TBD", location: ""),
            game(channel: "", location: "", completed: true),
            game(start: now.addingTimeInterval(-600), channel: " ", location: ""),
            game(cancelled: true),
        ]
        for card in cases.map({ content($0) }) {
            for detail in card.details {
                #expect(!detail.text.trimmingCharacters(in: .whitespaces).isEmpty)
                #expect(detail.text != "TBD")
                #expect(!detail.text.contains("nil"))
            }
        }
    }

    // MARK: Competition

    @Test("A cup tie names its cup; a league game names nothing")
    func competitionLabels() {
        let arsenalLeague = LeagueID.premierLeague
        #expect(GameCardContent.competitionLabel(of: game(competition: .soccer("eng.fa")), league: arsenalLeague) == "FA Cup")
        #expect(GameCardContent.competitionLabel(
            of: game(competition: .championsLeague, leagueName: "UEFA Champions League"), league: arsenalLeague
        ) == "Champions League")
        #expect(GameCardContent.competitionLabel(
            of: game(competition: .soccer("uefa.europa.conf"), leagueName: "UEFA Conference League"), league: arsenalLeague
        ) == "Conference League")
        #expect(GameCardContent.competitionLabel(of: game(competition: .premierLeague), league: arsenalLeague) == nil)

        // An unknown cup: the feed's name, else nothing, never the path.
        let unknown = LeagueID.soccer("eng.charity")
        #expect(GameCardContent.competitionLabel(
            of: game(competition: unknown, leagueName: "Community Shield"), league: arsenalLeague
        ) == "Community Shield")
        #expect(GameCardContent.competitionLabel(of: game(competition: unknown), league: arsenalLeague) == nil)
    }

    @Test("Season stage outside soccer, whose season ids mean nothing here")
    func seasonStage() {
        #expect(GameCardContent.competitionLabel(of: game(seasonType: 3), league: .mlb) == "Postseason")
        #expect(GameCardContent.competitionLabel(of: game(seasonType: 1), league: .nba) == "Preseason")
        #expect(GameCardContent.competitionLabel(of: game(seasonType: 2), league: .nba) == nil)
        #expect(GameCardContent.competitionLabel(of: game(seasonType: 3), league: .mls) == nil)
        // Football's week wins over its season stage.
        #expect(GameCardContent.competitionLabel(of: game(seasonType: 3, weekText: "Wild Card"), league: .nfl) == "Wild Card")
    }

    // MARK: VoiceOver

    @Test("The spoken card skips a TBD channel and names the live period")
    func accessibility() {
        // Relative to the real clock, which the summary reads.
        let upcoming = game(start: Date().addingTimeInterval(3 * 86_400), channel: "TBD", home: false)
        let spoken = upcoming.accessibilitySummary(drawLabel: "Tie", liveScore: LiveGameScore?.none)
        #expect(spoken.hasPrefix("Raiders, away, Oct 07, 2026"))
        #expect(!spoken.contains("TBD"))

        let live = game(start: Date().addingTimeInterval(-600), clock: "14:14", period: "2")
        let liveSpoken = live.accessibilitySummary(
            drawLabel: "Tie", liveScore: LiveGameScore(score: 7, opponentScore: 3), league: LeagueID.nfl.descriptor
        )
        #expect(liveSpoken.hasSuffix("Live, leading, 7 to 3, 2nd Quarter · 14:14"))
    }

    // MARK: Feeds

    @Test("Captured feeds: week, competition name and neutral site parse")
    func capturedFeeds() throws {
        let chiefs = try Fixture.json("chiefs_schedule")
        let (week1, pointer) = try Fixture.event("401872931", in: chiefs)
        let opener = parseGame(from: week1, team: .chiefs, pointer: pointer)
        #expect(opener.weekText == "Week 1")  // week.text
        #expect(opener.leagueName == "")  // no league object on NFL events
        #expect(!opener.neutralSite)

        // bundes_schedule_fixtures.json 401884777: at Augsburg, WWK Arena,
        // no broadcasts.
        let bayern = TeamRef(
            league: .bundesliga, espnID: "132",
            displayName: "Bayern Munich", shortName: "Bayern", abbreviation: "MUN", location: "Munich",
            colorHex: "", alternateColorHex: "",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        let fixtures = try Fixture.json("bundes_schedule_fixtures")
        let (event, index) = try Fixture.event("401884777", in: fixtures)
        let augsburg = parseGame(from: event, team: bayern, pointer: index)
        #expect(augsburg.leagueName == "Bundesliga")  // league.shortName
        #expect(augsburg.weekText == "")
        let card = GameCardContent(game: augsburg, league: .bundesliga, now: now, calendar: calendar)
        #expect(card.side == "Away")
        #expect(card.details == [GameCardContent.Detail(kind: .venue, text: "WWK Arena")])

        // ncaaf_schedule.json 401856812: Arizona State v Kansas, Week 3,
        // at a neutral site though Kansas is listed at home.
        let kansas = TeamRef(
            league: .collegeFootball, espnID: "2305",
            displayName: "Kansas Jayhawks", shortName: "Kansas", abbreviation: "KU", location: "Kansas",
            colorHex: "", alternateColorHex: "",
            logoURL: nil, logoDarkURL: nil, logoAsset: nil
        )
        let ncaaf = try Fixture.json("ncaaf_schedule")
        let (neutralEvent, neutralIndex) = try Fixture.event("401856812", in: ncaaf)
        let neutral = parseGame(from: neutralEvent, team: kansas, pointer: neutralIndex)
        #expect(neutral.neutralSite)
        #expect(neutral.gameHome)
        let neutralCard = GameCardContent(game: neutral, league: .collegeFootball, now: now, calendar: calendar)
        #expect(neutralCard.side == "Neutral")
        #expect(neutralCard.details.first == GameCardContent.Detail(kind: .competition, text: "Week 3"))
    }
}
