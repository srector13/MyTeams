//
//  WidgetSharedDataTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// A `UserDefaults` suite of its own, standing in for the App Group's, so
/// tests never touch the real group or the process's own defaults.
private func scratchDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "WidgetSharedDataTests.\(UUID().uuidString)"))
}

/// How the widgets degrade when the App Group is unreachable, as under a
/// re-signed (Feather, ad-hoc) install whose profile leaves the group out:
/// the shared-container seam (`SharedContainer`), the content plan
/// (`WidgetContent`) and the widget's own last-good store, driven with an
/// injected container rather than the OS.
@Suite("Widget shared data")
struct WidgetSharedDataTests {
    /// Tuesday, Oct 6, 2026, 16:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_302_400)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")!

    private func game(id: String, start: Date) -> Game {
        Game(
            team: "Chiefs", opponent: "Bills", opponentID: "2", score: "",
            opponentScore: "", time: "", date: "Oct 06, 2026", dateAsDate: start,
            opponentLogo: "", channel: "", location: "", gameHome: true, gameID: id, pointer: 0,
            gameWin: false, completed: false, competitionName: "", cancelled: false,
            postponed: false, gameClock: "", gamePeriod: "", gameHalftime: false
        )
    }

    private func snapshot(_ gameID: String) -> WidgetScoreboardSnapshot {
        WidgetScoreboardSnapshot(
            gameID: gameID, league: chiefs.league.path, teamID: chiefs.id,
            homeTeamID: chiefs.espnID, awayTeamID: "2", homeName: chiefs.shortName, awayName: "Bills",
            homeScore: 21, awayScore: 17, state: .inProgress, clock: "7:20", period: 3,
            gameDate: nil, updated: Self.now.addingTimeInterval(-60)
        )
    }

    private var cachedGame: WidgetCachedGame {
        WidgetCachedGame(
            teamName: "Bills", gameDate: "Live · 7:20", gameTime: "21–17",
            gameChannel: "CBS", message: nil, inline: "KC 21–17 Q3"
        )
    }

    // MARK: Shared container

    @Test func unavailableContainerReportsItself() {
        let container = SharedContainer.unavailable
        #expect(!container.isReachable)
        #expect(container.status == .unavailable)
        #expect(!container.status.isAvailable)
    }

    @Test func snapshotsAreNeverReadWithoutTheGroup() {
        // Not the process's own defaults: whatever they hold, the app did
        // not share it.
        #expect(SharedContainer.unavailable.scoreboardSnapshots().isEmpty)
    }

    @Test func reachableContainerReadsWhatTheAppShared() throws {
        let defaults = try scratchDefaults()
        let container = SharedContainer(groupDefaults: defaults)
        #expect(container.isReachable)
        #expect(container.status == .available(lastShared: nil))

        let written = Self.now.addingTimeInterval(-120)
        WidgetScoreboardCodec.write([snapshot("c1")], to: defaults, at: written)
        FavoritesCodec.save([FavoriteTeam(teamID: chiefs.id, addedAt: Self.now)], defaults: defaults, cloud: nil)

        #expect(container.scoreboardSnapshots() == [snapshot("c1")])
        #expect(container.favoriteTeamIDs() == [chiefs.id])
        #expect(container.status == .available(lastShared: written))
    }

    // MARK: Status lines

    @Test func statusCaptions() {
        #expect(SharedDataStatus.unavailable.caption(now: Self.now, calendar: Self.calendar)
            == "Shared data unavailable — reinstall via app to repair")
        #expect(SharedDataStatus.available(lastShared: nil).caption(now: Self.now, calendar: Self.calendar)
            == "Shared data: OK")
        let caption = SharedDataStatus.available(lastShared: Self.now.addingTimeInterval(-60))
            .caption(now: Self.now, calendar: Self.calendar)
        #expect(caption.hasPrefix("Shared data: OK · "))
        #expect(SharedDataStatus.dataFrom(Self.now, now: Self.now, calendar: Self.calendar).hasPrefix("Data from "))
    }

    @Test func configurationSuggestionsSayWhenSharedDataIsUnavailable() {
        #expect(TeamEntityQuery.suggestionNote(.unavailable) == SharedDataStatus.unavailableCaption)
        #expect(TeamEntityQuery.suggestionNote(.available(lastShared: nil)) == nil)
        #expect(TeamEntity(team: chiefs, note: "x").note == "x")
        #expect(TeamEntity(team: chiefs).note == nil)
    }

    @Test func missingTeamIsNotAskedForWithoutTheGroup() {
        #expect(WidgetMissingTeam(shared: .unavailable) == .sharedUnavailable)
        #expect(WidgetMissingTeam(shared: .available(lastShared: nil)) == .noneFollowed)
    }

    // MARK: Content plan

    @Test func freshContentWinsAndIsNotedWithoutTheGroup() {
        let available = WidgetContent<WidgetCachedGame>.plan(
            fresh: cachedGame, lastGood: nil, shared: .available(lastShared: nil), now: Self.now
        )
        #expect(available.source == .fresh)
        #expect(available.value == cachedGame)
        #expect(available.note == nil)

        let unavailable = WidgetContent<WidgetCachedGame>.plan(
            fresh: cachedGame, lastGood: nil, shared: .unavailable, now: Self.now
        )
        #expect(unavailable.source == .fresh)
        #expect(unavailable.note == SharedDataStatus.unavailableCaption)
    }

    @Test func failedLoadWithContainerMissingShowsTheLastGoodCopyDated() {
        let savedAt = Self.now.addingTimeInterval(-3600)
        let content = WidgetContent<WidgetCachedGame>.plan(
            fresh: nil,
            lastGood: WidgetLastGood(value: cachedGame, savedAt: savedAt),
            shared: .unavailable,
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(content.source == .cached(since: savedAt))
        #expect(content.value == cachedGame)
        #expect(content.note?.hasPrefix("Data from ") == true)
    }

    @Test func failedLoadWithContainerMissingAndNothingKeptIsALabelledPlaceholder() {
        let content = WidgetContent<WidgetCachedGame>.plan(
            fresh: nil, lastGood: nil, shared: .unavailable, now: Self.now
        )
        #expect(content.source == .placeholder)
        #expect(content.value == nil)
        // Never blank: the placeholder carries the reason.
        #expect(content.note == SharedDataStatus.unavailableCaption)
    }

    @Test func failedLoadWithTheGroupAndNothingKeptLeavesTheCallersNotice() {
        let content = WidgetContent<WidgetCachedGame>.plan(
            fresh: nil, lastGood: nil, shared: .available(lastShared: nil), now: Self.now
        )
        #expect(content.source == .placeholder)
        #expect(content.note == nil)
    }

    // MARK: Last good store

    @Test func lastGoodRoundTripsInTheWidgetsOwnDefaults() throws {
        let defaults = try scratchDefaults()
        let key = WidgetLastGoodStore.teamKey(chiefs.id)
        #expect(WidgetLastGoodStore.load(WidgetCachedGame.self, key: key, from: defaults) == nil)

        WidgetLastGoodStore.save(cachedGame, at: Self.now, key: key, in: defaults)
        let loaded = try #require(WidgetLastGoodStore.load(WidgetCachedGame.self, key: key, from: defaults))
        #expect(loaded.value == cachedGame)
        #expect(loaded.savedAt == Self.now)
    }

    @Test func unreadableLastGoodIsIgnored() throws {
        let defaults = try scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: WidgetLastGoodStore.dayKey)
        #expect(WidgetLastGoodStore.load([WidgetDayRow].self, key: WidgetLastGoodStore.dayKey, from: defaults) == nil)
    }

    // MARK: Timelines without the group

    @Test func dayRowsBuildWithoutTheGroupsSnapshots() {
        let builder = WidgetDayBuilder(
            calendar: Self.calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            abbreviation: { _, _ in nil }
        )
        let rows = builder.rows(
            teams: [chiefs],
            seasons: [chiefs.id: [game(id: "c1", start: Self.now.addingTimeInterval(2 * 3600))]],
            snapshots: SharedContainer.unavailable.scoreboardSnapshots(),
            now: Self.now
        )
        #expect(!rows.isEmpty)
        #expect(rows.first?.kind == .today)
    }

    @Test func dayTimelineFallsBackToKeptRowsWithoutTheGroup() throws {
        let defaults = try scratchDefaults()
        let builder = WidgetDayBuilder(
            calendar: Self.calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            abbreviation: { _, _ in nil }
        )
        let rows = builder.rows(
            teams: [chiefs],
            seasons: [chiefs.id: [game(id: "c1", start: Self.now.addingTimeInterval(2 * 3600))]],
            snapshots: [snapshot("c0")],
            now: Self.now
        )
        let savedAt = Self.now.addingTimeInterval(-600)
        WidgetLastGoodStore.save(rows, at: savedAt, key: WidgetLastGoodStore.dayKey, in: defaults)

        // The group is gone: nothing loads, and the kept rows are shown.
        let content = WidgetContent<[WidgetDayRow]>.plan(
            fresh: nil,
            lastGood: WidgetLastGoodStore.load([WidgetDayRow].self, key: WidgetLastGoodStore.dayKey, from: defaults),
            shared: SharedContainer.unavailable.status,
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(content.value == rows)
        #expect(content.value?.isEmpty == false)
        #expect(content.source == .cached(since: savedAt))
        #expect(content.note?.hasPrefix("Data from ") == true)
    }

    // MARK: Stores degrade without a crash

    @Test @MainActor func favoritesWorkWithoutICloud() throws {
        // A re-signed install's iCloud container is another team's, or none:
        // the store keeps to its own defaults, and the widget's read sees it.
        let defaults = try scratchDefaults()
        let store = FavoritesStore(defaults: defaults, cloud: nil, reloadWidgets: {})
        store.add(chiefs)
        #expect(store.isFavorite(chiefs.id))
        #expect(SharedContainer(groupDefaults: defaults).favoriteTeamIDs() == [chiefs.id])

        let relaunched = FavoritesStore(defaults: defaults, cloud: nil, reloadWidgets: {})
        #expect(relaunched.teamIDs == [chiefs.id])
    }

    @Test func logoStoreReadsNothingRatherThanFailing() {
        // Without the group the paths fall back to the process's own
        // directories; a crest never stored there reads as none.
        let unknown = TeamRef(
            league: .nfl, espnID: "WidgetSharedDataTests-none", displayName: "None", shortName: "None",
            abbreviation: "", location: "", colorHex: "", alternateColorHex: ""
        )
        #expect(LogoStore.url(for: unknown, variant: .default) == nil)
        #expect(LogoStore.favoritesDirectory.lastPathComponent == "favorites")
    }
}
