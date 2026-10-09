//
//  WidgetSharedDataTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/9/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Security
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
        // Reachable is not shared: until the app's writes show up, the
        // group may be one the app never writes to (t_d9c89472).
        #expect(container.status == .unshared(.appGroup(SharedStoreIdentity.canonicalGroup)))

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
            == "Shared data unavailable — signature has no App Group or keychain group")
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

    // MARK: Signing entitlements (t_d9c89472)

    private static let featherGroup = "group.com.example.feather"

    private static func entitlementsPlist(groups: [String]?, keychain: [String]?) throws -> Data {
        var plist: [String: Any] = ["application-identifier": "ABCDE12345.PolarReailty.Hawk-Nation"]
        if let groups { plist["com.apple.security.application-groups"] = groups }
        if let keychain { plist["keychain-access-groups"] = keychain }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// A thin arm64 Mach-O whose code signature holds `entitlements`, as
    /// zsign writes it: a super blob with a code directory slot and the
    /// entitlements slot.
    private static func machO(entitlements: Data?, signed: Bool = true) -> Data {
        var data = Data()
        func le(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }

        let entitlementsBlob = entitlements.map { 8 + $0.count } ?? 0
        let slots: UInt32 = entitlements == nil ? 1 : 2
        let superBlobLength = 12 + Int(slots) * 8 + 8 + entitlementsBlob
        // Header.
        le(MachOSignature.magic64); le(MachOSignature.cpuTypeARM64); le(0); le(2)
        le(signed ? 2 : 1); le(signed ? 24 : 8); le(0); le(0)
        // A load command to skip, then the signature's.
        le(0x19); le(8)
        if signed {
            le(MachOSignature.loadCodeSignature); le(16); le(64); le(UInt32(superBlobLength))
        }
        while data.count < 64 { data.append(0) }
        guard signed else { return data }
        // The super blob: a code directory stand-in, then the entitlements.
        be(MachOSignature.superBlobMagic); be(UInt32(superBlobLength)); be(slots)
        let first = 12 + Int(slots) * 8
        be(0); be(UInt32(first))
        if entitlements != nil { be(MachOSignature.entitlementsSlot); be(UInt32(first + 8)) }
        be(0xFADE_0C02); be(8)
        if let entitlements {
            be(MachOSignature.entitlementsMagic); be(UInt32(8 + entitlements.count))
            data.append(entitlements)
        }
        return data
    }

    private static func reader(_ data: Data) -> MachOSignature.Reader {
        { offset, count in
            let start = Int(offset)
            guard start < data.count else { return nil }
            return data.subdata(in: start..<min(data.count, start + count))
        }
    }

    @Test func entitlementsAreReadFromTheCodeSignature() throws {
        let plist = try Self.entitlementsPlist(groups: [Self.featherGroup], keychain: ["ABCDE12345.*"])
        let found = try #require(MachOSignature.entitlements(read: Self.reader(Self.machO(entitlements: plist))))
        let signed = try #require(SigningEntitlements(plist: found))
        #expect(signed == SigningEntitlements(
            appGroups: [Self.featherGroup],
            keychainAccessGroups: ["ABCDE12345.*"],
            applicationIdentifier: "ABCDE12345.PolarReailty.Hawk-Nation"
        ))
    }

    @Test func entitlementsAreReadFromAUniversalBinarysARM64Slice() throws {
        let plist = try Self.entitlementsPlist(groups: [SharedStoreIdentity.canonicalGroup], keychain: nil)
        let thin = Self.machO(entitlements: plist)
        var fat = Data()
        func be(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { fat.append(contentsOf: $0) } }
        be(MachOSignature.fatMagic); be(2)
        // An x86_64 slice first, pointing at nothing readable, then arm64.
        be(0x0100_0007); be(3); be(8192); be(16); be(12)
        be(MachOSignature.cpuTypeARM64); be(0); be(4096); be(UInt32(thin.count)); be(12)
        while fat.count < 4096 { fat.append(0) }
        fat.append(thin)
        let found = try #require(MachOSignature.entitlements(read: Self.reader(fat)))
        #expect(SigningEntitlements(plist: found)?.appGroups == [SharedStoreIdentity.canonicalGroup])
    }

    @Test func unsignedOrMalformedExecutablesHaveNoEntitlements() {
        #expect(MachOSignature.entitlements(read: Self.reader(Self.machO(entitlements: nil, signed: false))) == nil)
        #expect(MachOSignature.entitlements(read: Self.reader(Self.machO(entitlements: nil))) == nil)
        #expect(MachOSignature.entitlements(read: Self.reader(Data("not a binary at all".utf8))) == nil)
        #expect(MachOSignature.entitlements(read: Self.reader(Data())) == nil)
        // Cut off inside the signature.
        let plist = try? Self.entitlementsPlist(groups: [], keychain: nil)
        let truncated = Self.machO(entitlements: plist).prefix(80)
        #expect(MachOSignature.entitlements(read: Self.reader(Data(truncated))) == nil)
        #expect(SigningEntitlements(plist: Data("<plist>".utf8)) == nil)
    }

    // MARK: Store identity

    @Test func storeIdentityFollowsTheSignature() {
        // Nothing readable: the project's group, as before.
        #expect(SharedStoreIdentity.resolve(nil) == SharedStoreIdentity(appGroup: SharedStoreIdentity.canonicalGroup, keychainGroup: nil))
        // Xcode-signed: the project's group.
        #expect(SharedStoreIdentity.resolve(SigningEntitlements(appGroups: ["group.other", SharedStoreIdentity.canonicalGroup])).appGroup
            == SharedStoreIdentity.canonicalGroup)
        // Feather with the profile's own group: that one, in both processes.
        #expect(SharedStoreIdentity.resolve(SigningEntitlements(appGroups: [Self.featherGroup, "group.z"])).appGroup == Self.featherGroup)
        // AltStore-style renaming: the one named for the app.
        #expect(SharedStoreIdentity.appGroup(in: ["group.z", "group.PolarReailty.Hawk-Nation.ABCDE12345"])
            == "group.PolarReailty.Hawk-Nation.ABCDE12345")
        // A wildcard profile: no group, and the keychain group exactly as
        // signed; securityd grants `TEAMID.*` literally, nothing under it
        // (t_684fd0fb).
        let wildcard = SharedStoreIdentity.resolve(SigningEntitlements(appGroups: [], keychainAccessGroups: ["ABCDE12345.*"]))
        #expect(wildcard == SharedStoreIdentity(appGroup: nil, keychainGroup: "ABCDE12345.*"))
        #expect(wildcard.summary.contains("No App Group"))
        #expect(SharedStoreIdentity.keychainGroup(in: ["ABCDE12345.com.example"]) == "ABCDE12345.com.example")
        #expect(SharedStoreIdentity.keychainGroup(in: []) == nil)
    }

    // MARK: Status: which store, and whether the app's data is in it

    @Test func reSignedGroupWithTheAppsWritesIsAFallbackNamedOnTheWidget() throws {
        let defaults = try scratchDefaults()
        FavoritesCodec.save([FavoriteTeam(teamID: chiefs.id, addedAt: Self.now)], defaults: defaults, cloud: nil)
        let container = SharedContainer(groupDefaults: defaults, groupID: Self.featherGroup)
        #expect(container.status == .fallback(.appGroup(Self.featherGroup), lastShared: nil))
        #expect(container.status.isAvailable)
        #expect(container.status.note == "Shared via re-signed App Group")
        #expect(container.favoriteTeamIDs() == [chiefs.id])
    }

    @Test func reachableGroupTheAppNeverWroteIsNotShared() throws {
        // What the Feather device showed: a group that resolves, empty in
        // the widget, so the favorites read as none (t_d9c89472).
        let status = SharedContainer(groupDefaults: try scratchDefaults()).status
        #expect(!status.isAvailable)
        #expect(status.note?.contains("App Group") == true)
        #expect(WidgetMissingTeam(shared: status) == .notShared(.appGroup(SharedStoreIdentity.canonicalGroup)))
    }

    @Test func theAppsSeedMarkCountsAsItsWrite() throws {
        let defaults = try scratchDefaults()
        _ = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: nil, seedIDs: [])
        #expect(SharedContainer(groupDefaults: defaults).status == .available(lastShared: nil))
    }

    // MARK: Favorites mirror

    private let blues = TeamRef(
        league: .nhl, espnID: "19", displayName: "St. Louis Blues", shortName: "Blues",
        abbreviation: "STL", location: "St. Louis", colorHex: "002F87", alternateColorHex: "FCB514"
    )

    @Test func mirrorCarriesTheFavoritesWhenTheGroupHasNoList() throws {
        let defaults = try scratchDefaults()
        #expect(SharedFavoritesMirror.publish(ids: [blues.id, chiefs.id], teams: [blues, chiefs], at: Self.now, defaults: defaults, keychain: nil))
        let container = SharedContainer(groupDefaults: defaults)
        #expect(container.favoriteTeamIDs() == [blues.id, chiefs.id])
        #expect(container.favoritesMirror()?.teams == [blues, chiefs])
        #expect(container.status == .available(lastShared: nil))
    }

    @Test func mirrorIsWrittenOnlyWhenItChangesAndNeverWithPlaceholders() throws {
        let defaults = try scratchDefaults()
        let placeholder = try #require(TeamRef.placeholder(id: "hockey/nhl:25"))
        #expect(SharedFavoritesMirror.publish(ids: [chiefs.id, placeholder.id], teams: [chiefs, placeholder], at: Self.now, defaults: defaults, keychain: nil))
        let written = try #require(SharedFavoritesMirror.decode(defaults.data(forKey: SharedFavoritesMirror.defaultsKey)))
        #expect(written.ids == [chiefs.id, placeholder.id])
        #expect(written.teams == [chiefs])
        #expect(!SharedFavoritesMirror.publish(ids: [chiefs.id, placeholder.id], teams: [chiefs, placeholder], defaults: defaults, keychain: nil))
        #expect(SharedFavoritesMirror.publish(ids: [chiefs.id], teams: [chiefs], defaults: defaults, keychain: nil))
    }

    @Test func favoritesMoveIntoTheStoreTheSignatureNames() throws {
        let old = try scratchDefaults()
        let new = try scratchDefaults()
        FavoritesCodec.save([FavoriteTeam(teamID: chiefs.id, addedAt: Self.now)], defaults: old, cloud: nil)
        #expect(SharedStoreMigration.moveFavorites(into: new, from: [new, old]))
        #expect(FavoritesCodec.storedIDs(in: new) == [chiefs.id])
        #expect(new.bool(forKey: FavoritesCodec.seededKey))

        // A store with its own list keeps it.
        FavoritesCodec.save([FavoriteTeam(teamID: blues.id, addedAt: Self.now)], defaults: old, cloud: nil)
        #expect(!SharedStoreMigration.moveFavorites(into: new, from: [old]))
        #expect(FavoritesCodec.storedIDs(in: new) == [chiefs.id])
    }

    // MARK: Configuration picker (TeamEntityQuery)

    @Test func pickerOffersTheAppsFavoritesWithoutTheCatalog() async throws {
        let defaults = try scratchDefaults()
        FavoritesCodec.save([blues, chiefs].map { FavoriteTeam(teamID: $0.id, addedAt: Self.now) }, defaults: defaults, cloud: nil)
        SharedFavoritesMirror.publish(ids: [blues.id, chiefs.id], teams: [blues, chiefs], at: Self.now, defaults: defaults, keychain: nil)
        var asked: [TeamRef.ID] = []
        let entities = await TeamEntityQuery.suggestions(in: SharedContainer(groupDefaults: defaults)) { id in
            asked.append(id)
            return nil
        }
        #expect(entities.map(\.id) == [blues.id, chiefs.id])
        #expect(entities.allSatisfy { $0.note == nil })
        #expect(asked.isEmpty)
    }

    @Test func pickerKeepsAFavoriteItCannotResolveRatherThanSwappingIt() async throws {
        let defaults = try scratchDefaults()
        FavoritesCodec.save([FavoriteTeam(teamID: blues.id, addedAt: Self.now)], defaults: defaults, cloud: nil)
        let entities = await TeamEntityQuery.suggestions(in: SharedContainer(groupDefaults: defaults)) { _ in nil }
        #expect(entities.map(\.id) == [blues.id])
    }

    @Test func pickerLabelsTheBundledTeamsAsSamplesWhenNoneAreFollowed() async throws {
        let defaults = try scratchDefaults()
        _ = FavoritesCodec.loadOrSeed(defaults: defaults, cloud: nil, seedIDs: [])
        let entities = await TeamEntityQuery.suggestions(in: SharedContainer(groupDefaults: defaults)) { _ in nil }
        #expect(entities.map(\.id) == FavoriteTeams.teams.map(\.id))
        #expect(entities.allSatisfy { $0.note == "Sample team · no favorites in myTeams" })
    }

    @Test func pickerSaysWhyWhenTheFavoritesAreUnreadable() async throws {
        let unreadable = SharedContainer(groupDefaults: nil, groupID: nil, ownDefaults: try scratchDefaults())
        #expect(unreadable.status == .unavailable)
        let entities = await TeamEntityQuery.suggestions(in: unreadable) { _ in nil }
        #expect(entities.map(\.id) == FavoriteTeams.teams.map(\.id))
        #expect(entities.allSatisfy { $0.note == "Sample team · \(SharedDataStatus.unavailableCaption)" })

        let unshared = await TeamEntityQuery.suggestions(in: SharedContainer(groupDefaults: try scratchDefaults())) { _ in nil }
        #expect(unshared.allSatisfy { $0.note?.hasPrefix("Sample team · App Group") == true })
    }

    // MARK: Placeholder or error: what a widget draws

    @Test func missingTeamViewSaysWhichStoreFailed() {
        let canonical = SharedStore.appGroup(SharedStoreIdentity.canonicalGroup)
        #expect(WidgetMissingTeam(shared: .fallback(.keychain("T.x"), lastShared: nil)) == .noneFollowed)
        #expect(WidgetMissingTeam(shared: .unshared(canonical)) == .notShared(canonical))
        #expect(WidgetMissingTeam.noneFollowed.title == "Add Teams")
        #expect(!WidgetMissingTeam.noneFollowed.isSharingProblem)
        #expect(WidgetMissingTeam.sharedUnavailable.title == SharedDataStatus.unavailableTitle)
        #expect(WidgetMissingTeam.notShared(canonical).title == "No data from myTeams")
        #expect(WidgetMissingTeam.notShared(.keychain("T.x")).detail.hasPrefix("Keychain"))
        #expect(WidgetMissingTeam.notShared(canonical).isSharingProblem)
    }

    @Test func contentFromAFallbackStoreNamesIt() {
        let fresh = WidgetContent<WidgetCachedGame>.plan(
            fresh: cachedGame, lastGood: nil, shared: .fallback(.keychain("T.x"), lastShared: nil), now: Self.now
        )
        #expect(fresh.source == .fresh)
        #expect(fresh.note == "Shared via Keychain")

        let nothing = WidgetContent<WidgetCachedGame>.plan(
            fresh: nil, lastGood: nil, shared: .unshared(.appGroup(Self.featherGroup)), now: Self.now
        )
        #expect(nothing.source == .placeholder)
        #expect(nothing.note == "re-signed App Group has no data from the app — open myTeams")
        #expect(SharedDataStatus.fallback(.appGroup(Self.featherGroup), lastShared: nil).caption(now: Self.now, calendar: Self.calendar)
            == "Shared data: OK via re-signed App Group")
    }
}

// MARK: - Feather re-signing (t_684fd0fb)

/// The keychain as securityd judges it: an item's access group must be one
/// of the client's entitlement strings exactly, or the client holds the
/// bare `"*"` (`SecServerAccessGroupsAllows`). Items are shared between the
/// "processes" that pass the same `items` box.
private final class FakeKeychainItems: @unchecked Sendable {
    var items: [String: Data] = [:]
}

private struct FakeKeychain: SharedSecretStore {
    let accessGroup: String
    /// The client's `keychain-access-groups` (and application identifier).
    let entitled: [String]
    let box: FakeKeychainItems

    private var allowed: Bool {
        entitled.contains(accessGroup) || entitled.contains("*")
    }

    func read(_ account: String) -> (data: Data?, status: OSStatus) {
        guard allowed else { return (nil, errSecMissingEntitlement) }
        guard let data = box.items["\(accessGroup)/\(account)"] else { return (nil, errSecItemNotFound) }
        return (data, errSecSuccess)
    }

    func write(_ data: Data, for account: String) -> OSStatus {
        guard allowed else { return errSecMissingEntitlement }
        box.items["\(accessGroup)/\(account)"] = data
        return errSecSuccess
    }
}

@Suite("Widget sharing under Feather")
struct WidgetFeatherSharingTests {
    static let now = Date(timeIntervalSince1970: 1_791_302_400)
    static let team = "ABCDE12345"
    static let canonical = SharedStoreIdentity.canonicalGroup

    private let chiefs = TeamCatalog.seeded(league: .nfl, espnID: "12")!
    private let blues = TeamRef(
        league: .nhl, espnID: "19", displayName: "St. Louis Blues", shortName: "Blues",
        abbreviation: "STL", location: "St. Louis", colorHex: "002F87", alternateColorHex: "FCB514"
    )

    private func scratch() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "WidgetFeatherSharingTests.\(UUID().uuidString)"))
    }

    // MARK: Store selection

    struct SelectionCase: CustomTestStringConvertible, Sendable {
        var name: String
        var signed: SigningEntitlements?
        var appGroup: String?
        var keychainGroup: String?
        var testDescription: String { name }
    }

    static let selectionCases: [SelectionCase] = [
        SelectionCase(name: "unsigned (Simulator)", signed: nil, appGroup: canonical, keychainGroup: nil),
        SelectionCase(
            name: "Xcode-signed",
            signed: SigningEntitlements(appGroups: [canonical], applicationIdentifier: "\(team).PolarReailty.Hawk-Nation"),
            appGroup: canonical, keychainGroup: "\(team).PolarReailty.Hawk-Nation"
        ),
        SelectionCase(
            name: "Feather, profile with its own group",
            signed: SigningEntitlements(appGroups: ["group.com.example.feather"], keychainAccessGroups: ["\(team).*"], applicationIdentifier: "\(team).*"),
            appGroup: "group.com.example.feather", keychainGroup: "\(team).*"
        ),
        SelectionCase(
            name: "group in the signature but not the profile",
            signed: SigningEntitlements(appGroups: [canonical], keychainAccessGroups: ["\(team).*"]),
            appGroup: canonical, keychainGroup: "\(team).*"
        ),
        SelectionCase(
            name: "Feather, wildcard profile: no App Group",
            signed: SigningEntitlements(keychainAccessGroups: ["\(team).*"], applicationIdentifier: "\(team).*"),
            appGroup: nil, keychainGroup: "\(team).*"
        ),
        SelectionCase(
            name: "Feather, merged entitlements: keychain only",
            signed: SigningEntitlements(keychainAccessGroups: ["\(team).com.feather.myteams"], applicationIdentifier: "\(team).com.feather.myteams"),
            appGroup: nil, keychainGroup: "\(team).com.feather.myteams"
        ),
        SelectionCase(
            name: "application identifier only",
            signed: SigningEntitlements(applicationIdentifier: "\(team).*"),
            appGroup: nil, keychainGroup: "\(team).*"
        ),
        SelectionCase(name: "nothing to share through", signed: SigningEntitlements(), appGroup: nil, keychainGroup: nil),
    ]

    @Test("The store each signature selects", arguments: selectionCases)
    func storeSelection(_ variant: SelectionCase) {
        let identity = SharedStoreIdentity.resolve(variant.signed)
        #expect(identity.appGroup == variant.appGroup)
        #expect(identity.keychainGroup == variant.keychainGroup)
    }

    @Test func groupNamesAreMatchedAsSigned() {
        // The project's group only by its exact name; another case is the
        // profile's own group, used as signed, never rewritten.
        #expect(SharedStoreIdentity.appGroup(in: ["group.polarreailty.hawk-nation"]) == "group.polarreailty.hawk-nation")
        #expect(SharedStoreIdentity.appGroup(in: ["group.a", "group.b"]) == "group.a")
        #expect(SharedStoreIdentity.keychainGroup(in: [], applicationIdentifier: "") == nil)
    }

    @Test func bothProcessesSelectTheSameStoreWhenSignedAlike() {
        // zsign signs the app and the widget with one entitlements blob.
        let signed = SigningEntitlements(keychainAccessGroups: ["\(Self.team).*"], applicationIdentifier: "\(Self.team).*")
        #expect(SharedStoreIdentity.resolve(signed) == SharedStoreIdentity.resolve(signed))
        // Xcode signs each with its own application identifier: the group
        // is what they share, not the keychain.
        let app = SharedStoreIdentity.resolve(SigningEntitlements(appGroups: [Self.canonical], applicationIdentifier: "\(Self.team).PolarReailty.Hawk-Nation"))
        let widget = SharedStoreIdentity.resolve(SigningEntitlements(appGroups: [Self.canonical], applicationIdentifier: "\(Self.team).PolarReailty.Hawk-Nation.myTeamWidget"))
        #expect(app.appGroup == widget.appGroup)
        #expect(app.keychainGroup != widget.keychainGroup)
    }

    // MARK: Publish, then read, per store

    @Test func wildcardKeychainRoundTripsAsSigned() throws {
        let box = FakeKeychainItems()
        let entitled = ["\(Self.team).*"]
        let group = try #require(SharedStoreIdentity.resolve(SigningEntitlements(keychainAccessGroups: entitled)).keychainGroup)
        let app = FakeKeychain(accessGroup: group, entitled: entitled, box: box)
        let widget = FakeKeychain(accessGroup: group, entitled: entitled, box: box)

        #expect(SharedFavoritesMirror.publish(ids: [blues.id, chiefs.id], teams: [blues, chiefs], at: Self.now, defaults: try scratch(), keychain: app))
        let container = SharedContainer(groupDefaults: nil, groupID: nil, keychain: widget, ownDefaults: try scratch())
        #expect(container.favoriteTeamIDs() == [blues.id, chiefs.id])
        #expect(container.favoritesMirror()?.teams == [blues, chiefs])
        #expect(container.status == .fallback(.keychain(group), lastShared: Self.now))
    }

    @Test func theDerivedKeychainGroupOf1016IsRefused() throws {
        // What 1.0.16 asked for under a wildcard profile: refused in both
        // processes, so the widget read nothing and said "unavailable".
        let box = FakeKeychainItems()
        let derived = FakeKeychain(accessGroup: "\(Self.team).PolarReailty.Hawk-Nation.shared", entitled: ["\(Self.team).*"], box: box)
        #expect(derived.write(Data("x".utf8), for: "a") == errSecMissingEntitlement)
        #expect(derived.read("a").status == errSecMissingEntitlement)
    }

    @Test func appGroupRoundTrip() throws {
        let group = try scratch()
        #expect(SharedFavoritesMirror.publish(ids: [chiefs.id], teams: [chiefs], at: Self.now, defaults: group, keychain: nil))
        let container = SharedContainer(groupDefaults: group, groupID: "group.com.example.feather")
        #expect(container.favoriteTeamIDs() == [chiefs.id])
        #expect(container.status == .fallback(.appGroup("group.com.example.feather"), lastShared: nil))
    }

    @Test func groupMissingFromTheProfileFallsToTheKeychain() throws {
        // The signature names a group the OS won't resolve: no group
        // defaults, and the keychain still carries the favorites.
        let box = FakeKeychainItems()
        let app = FakeKeychain(accessGroup: "\(Self.team).*", entitled: ["\(Self.team).*"], box: box)
        SharedFavoritesMirror.publish(ids: [chiefs.id], teams: [chiefs], at: Self.now, defaults: try scratch(), keychain: app)
        let widget = SharedContainer(groupDefaults: nil, groupID: nil, keychain: app, ownDefaults: try scratch())
        #expect(widget.favoriteTeamIDs() == [chiefs.id])
        #expect(widget.status.isAvailable)
    }

    @Test func aKeychainTheAppHasNotWrittenIsNotShared() throws {
        let keychain = FakeKeychain(accessGroup: "\(Self.team).*", entitled: ["\(Self.team).*"], box: FakeKeychainItems())
        let status = SharedContainer(groupDefaults: nil, groupID: nil, keychain: keychain, ownDefaults: try scratch()).status
        #expect(status == .unshared(.keychain("\(Self.team).*")))
        #expect(WidgetMissingTeam(shared: status) == .notShared(.keychain("\(Self.team).*")))
        // Only with neither store is it unavailable.
        #expect(SharedContainer(groupDefaults: nil, groupID: nil, ownDefaults: try scratch()).status == .unavailable)
    }

    // MARK: Widget configuration, with nothing shared

    @Test func aChosenTeamRoundTripsThroughTheWidgetsOwnDefaults() async throws {
        let own = try scratch()
        WidgetConfigTeams.remember([blues], in: own)
        var asked: [TeamRef.ID] = []
        let entities = await TeamEntityQuery.configured([blues.id], mirrored: [], remembered: own) { id in
            asked.append(id)
            return nil
        }
        #expect(entities.map(\.team) == [blues])
        #expect(asked.isEmpty)

        WidgetConfigTeams.markChosen(blues, in: own)
        #expect(WidgetConfigTeams.chosen(in: own) == [blues])
        #expect(WidgetConfigTeams.team(id: blues.id, in: own) == blues)
    }

    @Test func aChosenTeamIsNeverDropped() async throws {
        let own = try scratch()
        // Resolved once, then remembered.
        let resolved = await TeamEntityQuery.configured([blues.id], mirrored: [], remembered: own) { _ in blues }
        #expect(resolved.map(\.team) == [blues])
        #expect(WidgetConfigTeams.known(in: own) == [blues])
        // Unresolvable: its placeholder, keeping the id.
        let unknown = "hockey/nhl:999"
        let kept = await TeamEntityQuery.configured([unknown], mirrored: [], remembered: try scratch()) { _ in nil }
        #expect(kept.map(\.id) == [unknown])
    }

    @Test func rememberedTeamsAreBoundedAndMostRecentFirst() throws {
        let own = try scratch()
        WidgetConfigTeams.remember([chiefs], in: own)
        WidgetConfigTeams.remember([blues, chiefs], in: own)
        #expect(WidgetConfigTeams.known(in: own).map(\.id) == [blues.id, chiefs.id])
        let placeholder = try #require(TeamRef.placeholder(id: "hockey/nhl:25"))
        WidgetConfigTeams.remember([placeholder], in: own)
        #expect(WidgetConfigTeams.known(in: own).count == 2)
        let many = (0..<(WidgetConfigTeams.knownLimit + 5)).map {
            TeamRef(league: .nhl, espnID: "x\($0)", displayName: "T\($0)", shortName: "T", abbreviation: "T",
                    location: "", colorHex: "", alternateColorHex: "")
        }
        WidgetConfigTeams.remember(many, in: own)
        #expect(WidgetConfigTeams.known(in: own).count == WidgetConfigTeams.knownLimit)
    }

    // MARK: Degradation: samples only when labelled

    @Test func samplesAreTheLastResortAndAlwaysLabelled() async throws {
        let unreadable = SharedContainer(groupDefaults: nil, groupID: nil, ownDefaults: try scratch())
        let entities = await TeamEntityQuery.suggestions(in: unreadable, chosen: [blues]) { _ in nil }
        #expect(entities.first?.team == blues)
        #expect(entities.first?.note?.hasPrefix("Chosen before · ") == true)
        let samples = entities.dropFirst()
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.note?.hasPrefix("Sample team · ") == true })
        #expect(entities.allSatisfy { $0.note != nil })
    }

    @Test func favoritesReadFromTheKeychainMeanNoSamples() async throws {
        let box = FakeKeychainItems()
        let keychain = FakeKeychain(accessGroup: "\(Self.team).*", entitled: ["\(Self.team).*"], box: box)
        SharedFavoritesMirror.publish(ids: [blues.id], teams: [blues], at: Self.now, defaults: try scratch(), keychain: keychain)
        let widget = SharedContainer(groupDefaults: nil, groupID: nil, keychain: keychain, ownDefaults: try scratch())
        let entities = await TeamEntityQuery.suggestions(in: widget, chosen: [chiefs]) { _ in nil }
        #expect(entities.map(\.id) == [blues.id])
        #expect(entities.allSatisfy { $0.note == "Shared via Keychain" })
    }

    // MARK: Diagnostics

    @Test func diagnosticsNameTheSignatureStoreAndCount() {
        let diagnostics = SharedStoreDiagnostics(
            process: "widget",
            bundleID: "com.feather.myteams.myTeamWidget",
            signed: SigningEntitlements(keychainAccessGroups: ["\(Self.team).*"]),
            identity: SharedStoreIdentity(appGroup: nil, keychainGroup: "\(Self.team).*"),
            status: .fallback(.keychain("\(Self.team).*"), lastShared: nil),
            favoritesCount: 3,
            keychainRead: errSecSuccess
        )
        #expect(diagnostics.lines == [
            "widget com.feather.myteams.myTeamWidget",
            "groups: none",
            "keychain: \(Self.team).*",
            "store: Keychain \(Self.team).*",
            "favorites: 3",
            "keychain \(Self.team).* read 0",
        ])
        #expect(diagnostics.compact == "widget · Keychain \(Self.team).* · fav 3")
        #expect(SharedStoreDiagnostics.shown(diagnostics) == diagnostics)

        var healthy = diagnostics
        healthy.status = .available(lastShared: nil)
        #expect(SharedStoreDiagnostics.shown(healthy) == nil)
        healthy.signed = nil
        #expect(healthy.lines[1] == "groups: unsigned")
    }
}
