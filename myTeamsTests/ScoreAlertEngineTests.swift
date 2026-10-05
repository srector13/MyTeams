//
//  ScoreAlertEngineTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
#if canImport(UserNotifications)
import UserNotifications
#endif

@testable import myTeams

// The engine end to end: captured scoreboards served by a
// `RecordingTransport`, parsed and fanned out by a real
// `LeagueScoreboardCenter`, watched by the engine, and posted to a recorder
// standing in for `UNUserNotificationCenter`.

/// A team known only by league and id, as a favorite the catalog has not
/// named yet.
private func team(_ league: LeagueID, _ espnID: String) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: espnID, shortName: espnID, abbreviation: "", location: "",
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

private let nflDay = "20260927"
private let uclDay = "20260909"
private let championsLeague = LeagueID.soccer("uefa.champions")

/// nfl_scoreboard_20260927: Rams (14, away) 26 at Broncos (7, home) 23, in
/// the 4th.
private let broncosGame = "401872962"
/// The same board: Chiefs (12, away) 24 at Dolphins (15) 10, final.
private let chiefsGame = "401872952"
/// ucl_scoreboard_20260909: Arsenal (359, away) at Napoli (114).
private let arsenalGame = "401915423"
/// The same board: Feyenoord (142) at Barcelona (83).
private let barcelonaGame = "401915424"
/// The same board: Viking FK (510) at Stuttgart (134).
private let stuttgartGame = "401915448"

private let broncos = team(.nfl, "7")
private let chiefs = team(.nfl, "12")
/// ESPN id 7 as well, in another league.
private let royals = team(.mlb, "7")
private let arsenal = team(.premierLeague, "359")
private let barcelona = team(.laLiga, "83")
/// An MLS favorite with Stuttgart's ESPN id: MLS does not play the
/// Champions League.
private let mlsNamesake = team(.mls, "134")

/// `board` with game `gameID` rewritten to `state`, `period` and the given
/// score — a real fixture with one game moved on, rather than a synthetic
/// document.
private func moving(
    _ gameID: String,
    in board: JSON,
    to state: String,
    completed: Bool = false,
    period: Int,
    home: Int,
    away: Int
) throws -> JSON {
    let match = board["events"].enumerated().first { $0.element.1["competitions", 0, "id"].stringValue == gameID }
    let eventIndex = try #require(match?.offset)
    let competition: [JSON.Index] = ["events", .index(eventIndex), "competitions", 0]
    var moved = board
        .setting(competition + ["status", "type", "state"], to: .string(state))
        .setting(competition + ["status", "type", "completed"], to: .bool(completed))
        .setting(competition + ["status", "period"], to: .number(Double(period)))
    for (offset, competitor) in board[competition + ["competitors"]].enumerated() {
        let score = competitor.1["homeAway"].stringValue == "home" ? home : away
        moved = moved.setting(competition + ["competitors", JSON.Index.index(offset), "score"], to: .string(String(score)))
    }
    return moved
}

/// `board` with game `gameID` not yet started: 0–0, before the 1st.
private func pregame(_ gameID: String, in board: JSON) throws -> JSON {
    try moving(gameID, in: board, to: "pre", period: 0, home: 0, away: 0)
}

/// `board` without game `gameID`, as a board that has dropped it.
private func removing(_ gameID: String, from board: JSON) -> JSON {
    guard case .array(let events) = board["events"] else { return board }
    let kept = events.filter { $0["competitions", 0, "id"].stringValue != gameID }
    return board.setting(["events"], to: .array(kept))
}

/// Answers each scoreboard URL with the document the test last put there,
/// and anything else with a 404.
private final class ScriptedBoards: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String: Data] = [:]

    func serve(_ board: JSON, at url: String) throws {
        let body = try board.serialized()
        lock.withLock { bodies[url] = body }
    }

    func reply(to url: URL) -> RecordingTransport.Reply {
        guard let body = lock.withLock({ bodies[url.absoluteString] }) else { return .status(404) }
        return RecordingTransport.Reply(body: body)
    }
}

/// Everything the engine does that a test can see, in order: each look at
/// the games (a read of the favorites), each permission check, and each
/// alert posted.
private final class AlertRecorder: @unchecked Sendable {
    enum Step: Equatable, Sendable {
        case looked
        case authorizationChecked(granted: Bool)
        case delivered(ScoreEvent)
    }

    let steps: AsyncStream<Step>
    private let continuation: AsyncStream<Step>.Continuation
    private let lock = NSLock()
    private var granted: Bool
    /// The favorite each game's latest alert was posted for, by game id.
    private var teams: [String: TeamRef.ID?] = [:]
    /// How loud each game's latest alert was, by game id.
    private var deliveries: [String: ScoreAlertDelivery] = [:]

    init(granted: Bool = true) {
        (steps, continuation) = AsyncStream.makeStream(of: Step.self)
        self.granted = granted
    }

    func grant(_ granted: Bool) {
        lock.withLock { self.granted = granted }
    }

    func look() {
        continuation.yield(.looked)
    }

    func isAuthorized() async -> Bool {
        let granted = lock.withLock { self.granted }
        continuation.yield(.authorizationChecked(granted: granted))
        return granted
    }

    func deliver(_ event: ScoreEvent, teamID: TeamRef.ID?, delivery: ScoreAlertDelivery) async {
        lock.withLock {
            teams[event.gameID] = .some(teamID)
            deliveries[event.gameID] = delivery
        }
        continuation.yield(.delivered(event))
    }

    /// The favorite game `gameID`'s latest alert was posted for: `nil`
    /// before any, `.some(nil)` for one posted without a team.
    func team(for gameID: String) -> TeamRef.ID?? {
        lock.withLock { teams[gameID] }
    }

    /// How loud game `gameID`'s latest alert was; `nil` before any.
    func delivery(for gameID: String) -> ScoreAlertDelivery? {
        lock.withLock { deliveries[gameID] }
    }
}

/// The next `count` steps the recorder saw. Runs on the caller's actor, so
/// the (non-Sendable) iterator never crosses one.
private func nextSteps(
    _ count: Int,
    from iterator: inout AsyncStream<AlertRecorder.Step>.Iterator,
    isolation: isolated (any Actor)? = #isolation
) async -> [AlertRecorder.Step] {
    var steps: [AlertRecorder.Step] = []
    for _ in 0..<count {
        guard let step = await iterator.next(isolation: isolation) else { break }
        steps.append(step)
    }
    return steps
}

/// Stands in for the engine's wait until a held event's window ends: each
/// wait asked for is announced on `requests`, and returns only when the
/// test rings.
private final class Alarm: @unchecked Sendable {
    let requests: AsyncStream<Duration>
    private let continuation: AsyncStream<Duration>.Continuation
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {
        (requests, continuation) = AsyncStream.makeStream(of: Duration.self)
    }

    func sleep(_ duration: Duration) async throws {
        await withCheckedContinuation { waiter in
            lock.withLock { waiters.append(waiter) }
            continuation.yield(duration)
        }
    }

    /// Ends every wait asked for so far.
    func ring() {
        let woken = lock.withLock {
            let woken = waiters
            waiters = []
            return woken
        }
        for waiter in woken {
            waiter.resume()
        }
    }
}

/// The engine's inputs a test changes as it goes: the favorites, the clock
/// the debounce reads, and the reader's alert preferences.
@MainActor
private final class Inputs {
    var favorites: [FavoriteTeam]
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    var preferences = AlertPreferences()

    init(favorites: [FavoriteTeam]) {
        self.favorites = favorites
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    func setNotify(_ notify: Bool, for teamID: TeamRef.ID) {
        for index in favorites.indices where favorites[index].teamID == teamID {
            favorites[index].notify = notify
        }
    }
}

@Suite("Score alert engine, end to end", .timeLimit(.minutes(1)))
struct ScoreAlertEngineTests {
    /// A center over `boards` whose pollers refresh once and then wait;
    /// tests drive later refreshes by hand.
    @MainActor
    private func makeCenter(_ boards: ScriptedBoards) -> LeagueScoreboardCenter {
        LeagueScoreboardCenter(
            client: HTTPClient(transport: RecordingTransport { url, _ in boards.reply(to: url) }),
            favoriteIDs: { [] },
            sleep: { _ in try await Task.sleep(for: .seconds(24 * 60 * 60)) }
        )
    }

    /// An engine over `center`, posting to `recorder`. Its wait for a held
    /// event's window (`sleep`) never ends unless a test supplies one.
    @MainActor
    private func makeEngine(
        _ center: LeagueScoreboardCenter,
        _ recorder: AlertRecorder,
        _ inputs: Inputs,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(24 * 60 * 60)) }
    ) -> ScoreAlertEngine {
        ScoreAlertEngine(
            center: center,
            favorites: {
                recorder.look()
                return inputs.favorites
            },
            now: { inputs.now },
            preferences: { inputs.preferences },
            isAuthorized: { await recorder.isAuthorized() },
            deliver: { await recorder.deliver($0, teamID: $1, delivery: $2) },
            sleep: sleep
        )
    }

    /// The Broncos game as the engine sees it on the captured board, its
    /// periods named as the NFL names them.
    private func broncosSnapshot(home: Int = 23, away: Int = 26, state: ScoreSnapshot.State = .inProgress) -> ScoreSnapshot {
        ScoreSnapshot(
            homeName: "Broncos", awayName: "Rams", homeScore: home, awayScore: away, period: 4, state: state,
            periodNaming: PeriodNaming(league: .nfl)
        )
    }

    @Test("A followed game's start, score and final each post, the observation re-arming after every change")
    @MainActor
    func startScoreFinal() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: LeagueID.nfl.scoreboardURL(day: nflDay))
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)

        // Nothing polled yet: the first look finds no games.
        engine.start()
        let first = await nextSteps(1, from: &steps)
        #expect(first == [.looked])
        // Starting again does not observe twice.
        engine.start()

        // The Broncos page mounts; the poller's first refresh lists the game
        // before its start, which seeds the engine without an alert.
        let subscription = center.subscribe(broncos, days: [nflDay])
        let pregameLook = await nextSteps(1, from: &steps)
        #expect(pregameLook == [.looked])

        // Kickoff: the game under way is news.
        inputs.advance(300)
        try boards.serve(board, at: LeagueID.nfl.scoreboardURL(day: nflDay))
        await center.refresh(.nfl)
        let kickoff = await nextSteps(3, from: &steps)
        #expect(kickoff == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.gameStart(gameID: broncosGame, snapshot: broncosSnapshot())),
        ])
        // Posted for the Broncos favorite: a tap opens their page.
        #expect(recorder.team(for: broncosGame) == .some(broncos.id))

        // Five minutes on, the Broncos score.
        inputs.advance(300)
        try boards.serve(
            moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26),
            at: LeagueID.nfl.scoreboardURL(day: nflDay)
        )
        await center.refresh(.nfl)
        let touchdown = await nextSteps(3, from: &steps)
        #expect(touchdown == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])

        // And the game goes final.
        inputs.advance(300)
        try boards.serve(
            moving(broncosGame, in: board, to: "post", completed: true, period: 4, home: 30, away: 26),
            at: LeagueID.nfl.scoreboardURL(day: nflDay)
        )
        await center.refresh(.nfl)
        let fullTime = await nextSteps(3, from: &steps)
        #expect(fullTime == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.final(gameID: broncosGame, snapshot: broncosSnapshot(home: 30, state: .final))),
        ])

        center.unsubscribe(subscription)
    }

    @Test("Inside the two-minute window a score is held back, but the final always goes")
    @MainActor
    func debouncedThroughTheEngine() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        // Seen before its start, then under way.
        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let kickoff = await nextSteps(3, from: &steps)
        #expect(kickoff.last == .delivered(.gameStart(gameID: broncosGame, snapshot: broncosSnapshot())))

        // A minute later: seen, but nothing posted, so nothing asked either.
        inputs.advance(60)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let held = await nextSteps(1, from: &steps)
        #expect(held == [.looked])

        // Seconds later still, the final: posted, with the score held back
        // already in it. The step after the held look is this one's look,
        // so the held score never went out.
        inputs.advance(5)
        try boards.serve(
            moving(broncosGame, in: board, to: "post", completed: true, period: 4, home: 30, away: 26),
            at: url
        )
        await center.refresh(.nfl)
        let fullTime = await nextSteps(3, from: &steps)
        #expect(fullTime == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.final(gameID: broncosGame, snapshot: broncosSnapshot(home: 30, state: .final))),
        ])

        center.unsubscribe(subscription)
    }

    @Test("A game that drops off the board and comes back keeps its last look: no second start")
    @MainActor
    func droppedGameKeepsItsSnapshot() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        // Seen before its start, then under way.
        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let kickoff = await nextSteps(3, from: &steps)
        #expect(kickoff.last == .delivered(.gameStart(gameID: broncosGame, snapshot: broncosSnapshot())))

        // The game drops off the board: nothing to say.
        inputs.advance(300)
        try boards.serve(removing(broncosGame, from: board), at: url)
        await center.refresh(.nfl)
        let gone = await nextSteps(1, from: &steps)
        #expect(gone == [.looked])

        // It comes back as it was: not taken for a new game.
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let back = await nextSteps(1, from: &steps)
        #expect(back == [.looked])

        // A score now reads against the look kept from before it dropped.
        inputs.advance(300)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 23, away: 33), at: url)
        await center.refresh(.nfl)
        let score = await nextSteps(3, from: &steps)
        #expect(score == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(away: 33)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("Only favorites that want alerts, and only in their own league: an ESPN id shared across leagues is not a match")
    @MainActor
    func followedFavoritesOnly() async throws {
        // The Broncos' and the Chiefs' games both before their start.
        let fixture = try Fixture.json("nfl_scoreboard_20260927")
        var board = try pregame(chiefsGame, in: pregame(broncosGame, in: fixture))
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(board, at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        // The Royals are ESPN team 7, as the Broncos are; the Broncos
        // themselves are followed with alerts off.
        let inputs = Inputs(favorites: [
            FavoriteTeam(teamID: royals.id),
            FavoriteTeam(teamID: broncos.id, notify: false),
            FavoriteTeam(teamID: chiefs.id),
        ])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(chiefs, days: [nflDay])
        let seeded = await nextSteps(1, from: &steps)
        #expect(seeded == [.looked])

        // Both games kick off; only the Chiefs' is news.
        inputs.advance(300)
        board = try moving(chiefsGame, in: board, to: "in", period: 3, home: 10, away: 17)
        board = try moving(broncosGame, in: board, to: "in", period: 4, home: 23, away: 26)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let chiefsLive = ScoreSnapshot(
            homeName: "Dolphins", awayName: "Chiefs", homeScore: 10, awayScore: 17, period: 3, state: .inProgress,
            periodNaming: PeriodNaming(league: .nfl)
        )
        let first = await nextSteps(3, from: &steps)
        #expect(first == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.gameStart(gameID: chiefsGame, snapshot: chiefsLive)),
        ])

        // Favorites are read afresh at each look: with the Broncos' alerts
        // turned on, their game is followed from the next change. Its first
        // look seeds quietly — it was under way before it was followed — and
        // the step after the first batch is this look, so the Broncos' game
        // was not posted before.
        inputs.setNotify(true, for: broncos.id)
        inputs.advance(300)
        board = try moving(broncosGame, in: board, to: "in", period: 4, home: 23, away: 29)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let followed = await nextSteps(1, from: &steps)
        #expect(followed == [.looked])

        // From then on its changes are news.
        inputs.advance(300)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 23, away: 33), at: url)
        await center.refresh(.nfl)
        let second = await nextSteps(3, from: &steps)
        #expect(second == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(away: 29),
                snapshot: broncosSnapshot(away: 33)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("A cup tie alerts for a favorite whose league plays the cup, and for no one else on the cup's board")
    @MainActor
    func cupCompetitions() async throws {
        // ucl_scoreboard_20260909 with three ties rewound to before kickoff.
        var board = try Fixture.json("ucl_scoreboard_20260909")
        for game in [arsenalGame, barcelonaGame, stuttgartGame] {
            board = try pregame(game, in: board)
        }
        let url = championsLeague.scoreboardURL(day: uclDay)
        let boards = ScriptedBoards()
        try boards.serve(board, at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [
            FavoriteTeam(teamID: arsenal.id),
            FavoriteTeam(teamID: barcelona.id, notify: false),
            FavoriteTeam(teamID: mlsNamesake.id),
        ])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(arsenal, competition: championsLeague, days: [uclDay])
        let seeded = await nextSteps(1, from: &steps)
        #expect(seeded == [.looked])

        // All three under way, into the second half. Stuttgart's tie stays
        // quiet — the MLS favorite sharing its id is in a league that does
        // not play the Champions League — and Barcelona's alerts are off.
        inputs.advance(300)
        board = try moving(arsenalGame, in: board, to: "in", period: 2, home: 0, away: 1)
        board = try moving(barcelonaGame, in: board, to: "in", period: 2, home: 3, away: 1)
        board = try moving(stuttgartGame, in: board, to: "in", period: 2, home: 2, away: 1)
        try boards.serve(board, at: url)
        await center.refresh(championsLeague)
        let first = await nextSteps(3, from: &steps)
        #expect(first == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.gameStart(
                gameID: arsenalGame,
                snapshot: ScoreSnapshot(
                    homeName: "Napoli", awayName: "Arsenal", homeScore: 0, awayScore: 1, period: 2, state: .inProgress,
                    periodNaming: PeriodNaming(league: championsLeague)
                )
            )),
        ])
        // The cup tie's alert opens Arsenal's page, in the Premier League.
        #expect(recorder.team(for: arsenalGame) == .some(arsenal.id))
        #expect(arsenal.id == "soccer/eng.1:359")

        // Barcelona's alerts on: La Liga plays the Champions League too. Its
        // tie, first followed under way, seeds quietly; its next goal alerts.
        inputs.setNotify(true, for: barcelona.id)
        inputs.advance(300)
        board = try moving(barcelonaGame, in: board, to: "in", period: 2, home: 4, away: 1)
        board = try moving(stuttgartGame, in: board, to: "in", period: 2, home: 3, away: 1)
        try boards.serve(board, at: url)
        await center.refresh(championsLeague)
        let followed = await nextSteps(1, from: &steps)
        #expect(followed == [.looked])

        inputs.advance(300)
        board = try moving(barcelonaGame, in: board, to: "in", period: 2, home: 5, away: 1)
        try boards.serve(board, at: url)
        await center.refresh(championsLeague)
        let second = await nextSteps(3, from: &steps)
        #expect(second == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: barcelonaGame,
                previous: ScoreSnapshot(
                    homeName: "Barcelona", awayName: "Feyenoord", homeScore: 4, awayScore: 1, period: 2, state: .inProgress,
                    periodNaming: PeriodNaming(league: championsLeague)
                ),
                snapshot: ScoreSnapshot(
                    homeName: "Barcelona", awayName: "Feyenoord", homeScore: 5, awayScore: 1, period: 2, state: .inProgress,
                    periodNaming: PeriodNaming(league: championsLeague)
                )
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("Relaunched mid-game: the first look at a game under way posts nothing; its next score does")
    @MainActor
    func relaunchMidGame() async throws {
        // A fresh engine, as after a relaunch, and the Broncos already in the
        // 4th on the first board it sees.
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(board, at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(broncos, days: [nflDay])
        let seeded = await nextSteps(1, from: &steps)
        #expect(seeded == [.looked])

        // The step after the seed is the next look: no "Game started" went
        // out, and the score reads against the seed.
        inputs.advance(300)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let touchdown = await nextSteps(3, from: &steps)
        #expect(touchdown == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("Permission is checked before posting: denied, nothing goes out; granted later, alerts resume")
    @MainActor
    func permissionGate() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder(granted: false)
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        // Seen before its start, then under way.
        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let denied = await nextSteps(2, from: &steps)
        #expect(denied == [.looked, .authorizationChecked(granted: false)])

        // Allowed now. The next step is the next look, not the start held
        // back above: a denied batch is dropped, not queued.
        recorder.grant(true)
        inputs.advance(300)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let granted = await nextSteps(3, from: &steps)
        #expect(granted == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("A score held back by the window goes out on the first look past it, with the latest score")
    @MainActor
    func heldScoreFollowsUp() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        // Seen before its start, then under way.
        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let kickoff = await nextSteps(3, from: &steps)
        #expect(kickoff.last == .delivered(.gameStart(gameID: broncosGame, snapshot: broncosSnapshot())))

        // A minute later the Broncos score: inside the window, held.
        inputs.advance(60)
        let scored = try moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26)
        try boards.serve(scored, at: url)
        await center.refresh(.nfl)
        let held = await nextSteps(1, from: &steps)
        #expect(held == [.looked])

        // Past the window, a look with no news for the Broncos (only
        // another game on the board moved) posts the held score.
        inputs.advance(70)
        try boards.serve(
            moving(chiefsGame, in: scored, to: "post", completed: true, period: 4, home: 10, away: 31),
            at: url
        )
        await center.refresh(.nfl)
        let followUp = await nextSteps(3, from: &steps)
        #expect(followUp == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("With no look after it, a held score goes out when its window ends")
    @MainActor
    func heldScoreReleasedOnTime() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let alarm = Alarm()
        var waits = alarm.requests.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs, sleep: { try await alarm.sleep($0) })
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        _ = await nextSteps(3, from: &steps)

        // A minute later the Broncos score: held, and a wake set for the
        // window's end, a minute on.
        inputs.advance(60)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let held = await nextSteps(1, from: &steps)
        #expect(held == [.looked])
        let wait = await waits.next(isolation: #isolation)
        #expect(wait == .seconds(61))

        // The board sits unchanged through a break; the wake posts the
        // score without a look.
        inputs.advance(61)
        alarm.ring()
        let released = await nextSteps(2, from: &steps)
        #expect(released == [
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])

        center.unsubscribe(subscription)
    }

    @Test("A kind turned off is never posted, and doesn't take the game's window")
    @MainActor
    func kindsTurnedOff() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        inputs.preferences.sendsStarts = false
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)

        // Kickoff, with starts off: looked at, nothing posted or asked.
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let kickoff = await nextSteps(1, from: &steps)
        #expect(kickoff == [.looked])

        // Thirty seconds on, a score: the start took no window, so it goes.
        inputs.advance(30)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let touchdown = await nextSteps(3, from: &steps)
        #expect(touchdown == [
            .looked,
            .authorizationChecked(granted: true),
            .delivered(.scoreChange(
                gameID: broncosGame,
                previous: broncosSnapshot(),
                snapshot: broncosSnapshot(home: 30)
            )),
        ])
        #expect(recorder.delivery(for: broncosGame) == .standard)

        center.unsubscribe(subscription)
    }

    @Test("During quiet hours alerts are delivered quietly, not dropped")
    @MainActor
    func quietHours() async throws {
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let url = LeagueID.nfl.scoreboardURL(day: nflDay)
        let boards = ScriptedBoards()
        try boards.serve(pregame(broncosGame, in: board), at: url)
        let recorder = AlertRecorder()
        var steps = recorder.steps.makeAsyncIterator()
        let inputs = Inputs(favorites: [FavoriteTeam(teamID: broncos.id)])
        // An hour of quiet from the test's own "now", on the engine's clock
        // (`Calendar.current`), whatever the machine's time zone.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: inputs.now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        inputs.preferences.quietHoursEnabled = true
        inputs.preferences.quietStart = minute
        inputs.preferences.quietEnd = AlertPreferences.normalized(minute + 60)
        let center = makeCenter(boards)
        let engine = makeEngine(center, recorder, inputs)
        engine.start()
        _ = await nextSteps(1, from: &steps)

        let subscription = center.subscribe(broncos, days: [nflDay])
        _ = await nextSteps(1, from: &steps)

        // Five minutes into the quiet hour, the game starts.
        inputs.advance(300)
        try boards.serve(board, at: url)
        await center.refresh(.nfl)
        let kickoff = await nextSteps(3, from: &steps)
        #expect(kickoff.last == .delivered(.gameStart(gameID: broncosGame, snapshot: broncosSnapshot())))
        #expect(recorder.delivery(for: broncosGame) == .quiet)

        // Past the quiet hour, a score is delivered as usual.
        inputs.advance(60 * 60)
        try boards.serve(moving(broncosGame, in: board, to: "in", period: 4, home: 30, away: 26), at: url)
        await center.refresh(.nfl)
        let touchdown = await nextSteps(3, from: &steps)
        #expect(touchdown.count == 3)
        #expect(recorder.delivery(for: broncosGame) == .standard)

        center.unsubscribe(subscription)
    }
}

@Suite("Score alert engine: snapshots and notification content")
struct ScoreAlertContentTests {
    @Test("Scoreboard games read as snapshots: live, final, called off, and not two-sided")
    func snapshots() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let live = try #require(nfl.games.first { $0.gameID == broncosGame })
        #expect(ScoreAlertEngine.snapshot(of: live) == ScoreSnapshot(
            homeName: "Broncos", awayName: "Rams", homeScore: 23, awayScore: 26, period: 4, state: .inProgress
        ))
        let over = try #require(nfl.games.first { $0.gameID == chiefsGame })
        #expect(ScoreAlertEngine.snapshot(of: over)?.state == .final)

        // mlb_scoreboard_20260927 id 401817103: cancelled, "post" but not
        // completed — reads as never started, so it can never go final.
        let mlb = parseScoreboard(from: try Fixture.json("mlb_scoreboard_20260927"))
        let cancelled = try #require(mlb.games.first { $0.gameID == "401817103" })
        #expect(ScoreAlertEngine.snapshot(of: cancelled)?.state == .scheduled)

        var oneSided = live
        oneSided.competitors.removeLast()
        #expect(ScoreAlertEngine.snapshot(of: oneSided) == nil)
    }

    @Test("A team the board names blank, or not at all, reads as Home or Away")
    func unnamedTeams() throws {
        // The Broncos game with its home side's shortDisplayName gone and
        // its away side's left empty.
        let board = try Fixture.json("nfl_scoreboard_20260927")
        let match = board["events"].enumerated().first { $0.element.1["competitions", 0, "id"].stringValue == broncosGame }
        let eventIndex = try #require(match?.offset)
        let competitors: [JSON.Index] = ["events", .index(eventIndex), "competitions", 0, "competitors"]
        var unnamed = board
        for (offset, competitor) in board[competitors].enumerated() {
            let name: JSON = competitor.1["homeAway"].stringValue == "home" ? .null : .string(" ")
            unnamed = unnamed.setting(competitors + [JSON.Index.index(offset), "team", "shortDisplayName"], to: name)
        }

        let game = try #require(parseScoreboard(from: unnamed).games.first { $0.gameID == broncosGame })
        #expect(game.teamNames.isEmpty)
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: game))
        #expect(snapshot.homeName == "Home")
        #expect(snapshot.awayName == "Away")
        #expect(snapshot.summary == "Away 26 – Home 23 (4th)")
    }

    #if canImport(UserNotifications)
    @Test("An alert's title, body and sound come from the event; its thread is the game")
    func notificationContent() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let live = try #require(nfl.games.first { $0.gameID == broncosGame })
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: live))
        let event = ScoreEvent.periodEnd(gameID: broncosGame, period: 3, snapshot: snapshot)

        let request = ScoreAlertEngine.request(for: event)
        #expect(request.content.title == "End of 3rd")
        #expect(request.content.body == "Rams 26 – Broncos 23 (4th)")
        #expect(request.content.threadIdentifier == broncosGame)
        #expect(request.content.sound != nil)
        #expect(request.trigger == nil)
        let identifiesGame = request.identifier.hasPrefix("\(broncosGame).")
        #expect(identifiesGame)

        // Every alert is its own request, threaded with the game's others.
        let fullTime = ScoreEvent.final(gameID: broncosGame, snapshot: snapshot)
        let another = ScoreAlertEngine.request(for: fullTime)
        #expect(another.identifier != request.identifier)
        #expect(another.content.threadIdentifier == request.content.threadIdentifier)
        #expect(another.content.title == "Final")
    }

    @Test("Read with its league, an alert names the period as the league does")
    func leagueStageInAlert() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let live = try #require(nfl.games.first { $0.gameID == broncosGame })
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: live, league: .nfl))
        #expect(snapshot.stageLabel == "4th Quarter")

        let request = ScoreAlertEngine.request(for: .periodEnd(gameID: broncosGame, period: 3, snapshot: snapshot))
        #expect(request.content.title == "End of 3rd Quarter")
        #expect(request.content.body == "Rams 26 – Broncos 23 (4th Quarter)")

        // Into overtime.
        var overtime = live
        overtime.period = 5
        let afterRegulation = try #require(ScoreAlertEngine.snapshot(of: overtime, league: .nfl))
        let endOfFourth = ScoreAlertEngine.request(for: .periodEnd(gameID: broncosGame, period: 4, snapshot: afterRegulation))
        #expect(endOfFourth.content.title == "End of 4th Quarter")
        #expect(endOfFourth.content.body == "Rams 26 – Broncos 23 (OT)")
    }

    @Test("A quiet alert is passive and silent; a standard one sounds")
    func quietRequest() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let live = try #require(nfl.games.first { $0.gameID == broncosGame })
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: live, league: .nfl))
        let event = ScoreEvent.final(gameID: broncosGame, snapshot: snapshot)

        let quiet = ScoreAlertEngine.request(for: event, teamID: broncos.id, delivery: .quiet)
        #expect(quiet.content.sound == nil)
        #expect(quiet.content.interruptionLevel == .passive)
        #expect(quiet.content.title == "Final")

        let standard = ScoreAlertEngine.request(for: event, teamID: broncos.id)
        #expect(standard.content.sound != nil)
        #expect(standard.content.interruptionLevel != .passive)
    }

    @Test("In the foreground: no banner for the team on screen, nor for a quiet alert")
    func foregroundPresentation() throws {
        let nfl = parseScoreboard(from: try Fixture.json("nfl_scoreboard_20260927"))
        let live = try #require(nfl.games.first { $0.gameID == broncosGame })
        let snapshot = try #require(ScoreAlertEngine.snapshot(of: live, league: .nfl))
        let event = ScoreEvent.scoreChange(gameID: broncosGame, previous: snapshot, snapshot: snapshot)
        let broncosAlert = ScoreAlertEngine.request(for: event, teamID: broncos.id).content

        // The Broncos' page is foremost: the alert goes to the list only.
        #expect(ScoreAlertEngine.presentationOptions(for: broncosAlert, foregroundTeamID: broncos.id) == [.list])
        // Another team's page, or none: a banner with sound.
        #expect(ScoreAlertEngine.presentationOptions(for: broncosAlert, foregroundTeamID: chiefs.id) == [.banner, .list, .sound])
        #expect(ScoreAlertEngine.presentationOptions(for: broncosAlert, foregroundTeamID: nil) == [.banner, .list, .sound])
        // An alert linked to no team shows as before.
        let unlinked = ScoreAlertEngine.request(for: event).content
        #expect(ScoreAlertEngine.presentationOptions(for: unlinked, foregroundTeamID: broncos.id) == [.banner, .list, .sound])

        // A quiet alert never banners.
        let quiet = ScoreAlertEngine.request(for: event, teamID: broncos.id, delivery: .quiet).content
        #expect(ScoreAlertEngine.presentationOptions(for: quiet, foregroundTeamID: nil) == [.list])
    }
    #endif

    @Test("The foreground team hook reads back what was set, from any thread")
    func foregroundHook() async {
        let hook = ScoreAlertForeground()
        #expect(hook.teamID == nil)
        hook.teamID = broncos.id
        let read = await Task.detached { hook.teamID }.value
        #expect(read == broncos.id)
        hook.teamID = nil
        #expect(hook.teamID == nil)
    }
}
