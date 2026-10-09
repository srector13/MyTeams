//
//  LogoStore.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import ImageIO
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "logos")

// MARK: - Shared paths

/// Where the app and the widget keep files and settings they both read.
///
/// Both resolve to the App Group the install was signed with
/// (`SharedStoreIdentity`): the project's, or a re-signed install's own. A
/// process without one gets `nil` from
/// `containerURL(forSecurityApplicationGroupIdentifier:)` and falls back to
/// its own directories and `UserDefaults.standard`; the widget asks
/// `SharedContainer` to tell that apart from "nothing shared yet".
enum SharedPaths {
    /// The App Group shared through; `nil` when the signature carries none.
    static var appGroup: String? { SharedStoreIdentity.current.appGroup }

    /// The App Group's `UserDefaults`, or `.standard` without the group.
    static var defaults: UserDefaults {
        SharedContainer.live.defaults
    }

    /// The favorites' `TeamRef.id`s, in order, as the app last saved them.
    /// Empty when none are stored. The widget reads favorites through this,
    /// not through the app's `FavoritesStore`.
    static func favoriteTeamIDs() -> [String] {
        SharedContainer.live.favoriteTeamIDs()
    }

    /// The App Group container, or `fallback` while the process has no group.
    static func container(_ fallback: URL) -> URL {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) } ?? fallback
    }

    /// Files the OS must not purge: favorite teams' crests.
    static var applicationSupport: URL {
        directory(.applicationSupportDirectory, inGroup: "Library/Application Support")
    }

    /// Files that can be fetched again: team catalogs, other teams' crests.
    static var caches: URL {
        directory(.cachesDirectory, inGroup: "Library/Caches")
    }

    /// The team catalog cache, one JSON file per league.
    static var teamCatalog: URL {
        caches.appending(path: "TeamCatalog", directoryHint: .isDirectory)
    }

    /// The team catalog cache of fixture launches (`HTTPClient.servesFixtures`),
    /// apart from the live one: the fixtures' trimmed leagues never reach a
    /// live launch, nor a live league a fixture launch.
    static var fixtureTeamCatalog: URL {
        caches.appending(path: "TeamCatalog-Fixtures", directoryHint: .isDirectory)
    }

    /// `subpath` inside the group container, or the process's own `directory`.
    private static func directory(_ directory: FileManager.SearchPathDirectory, inGroup subpath: String) -> URL {
        let local = FileManager.default.urls(for: directory, in: .userDomainMask)[0]
        let root = container(local)
        return root == local ? local : root.appending(path: subpath, directoryHint: .isDirectory)
    }
}

// MARK: - Shared container

/// The store this process shares with the other: the App Group's defaults
/// when the group is reachable, and the keychain item the app mirrors the
/// favorites to.
///
/// A re-signed install (Feather, or any ad-hoc profile) still launches when
/// its profile leaves the project's group out, but the group then is not
/// shared: `UserDefaults(suiteName:)` hands back a store in the process's
/// own container, and a container that resolves is no proof either. So a
/// group counts as shared only once the widget finds the app's writes in
/// it (`status`). Whatever must tell "nothing shared yet" from "nothing can
/// be shared" asks here; tests inject `unavailable`, or a scratch suite,
/// rather than the OS.
struct SharedContainer {
    /// The App Group's defaults; `nil` when the group is unreachable.
    let groupDefaults: UserDefaults?
    /// The group's identifier, for the status line.
    var groupID: String? = SharedStoreIdentity.canonicalGroup
    /// The keychain group both processes are signed with, if any.
    var keychain: (any SharedSecretStore)? = nil
    /// The process's own defaults, `.standard`; tests pass a scratch suite.
    var ownDefaults: UserDefaults = .standard

    var isReachable: Bool { groupDefaults != nil }

    /// The group's defaults, or the process's own without the group. In the
    /// app those still hold its own state; in the widget they hold nothing
    /// the app wrote.
    var defaults: UserDefaults { groupDefaults ?? ownDefaults }

    /// Asks the OS for the group the signature names (`SharedStoreIdentity`):
    /// it counts only when its container resolves.
    static var live: SharedContainer {
        let identity = SharedStoreIdentity.current
        let keychain: (any SharedSecretStore)? = identity.keychainGroup.map(SharedKeychain.init(accessGroup:))
        guard let group = identity.appGroup,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil,
              let shared = UserDefaults(suiteName: group)
        else { return SharedContainer(groupDefaults: nil, groupID: nil, keychain: keychain) }
        return SharedContainer(groupDefaults: shared, groupID: group, keychain: keychain)
    }

    /// No group, as a profile without it leaves the process.
    static var unavailable: SharedContainer { SharedContainer(groupDefaults: nil, groupID: nil) }

    /// The favorites' `TeamRef.id`s, in order: as stored in `defaults`,
    /// else as the app mirrored them (`favoritesMirror()`).
    func favoriteTeamIDs() -> [String] {
        FavoritesCodec.storedIDs(in: defaults) ?? favoritesMirror()?.ids ?? []
    }

    /// The app's copy of the favorites as teams: the group's, else the
    /// keychain's.
    func favoritesMirror() -> SharedFavoritesMirror? {
        if let groupDefaults, let mirror = SharedFavoritesMirror.decode(groupDefaults.data(forKey: SharedFavoritesMirror.defaultsKey)) {
            return mirror
        }
        return keychain.flatMap { SharedFavoritesMirror.decode($0.data(for: SharedFavoritesMirror.keychainAccount)) }
    }

    /// The app's scoreboard snapshots (`WidgetScoreboardCodec`); none
    /// without the group, rather than whatever the process's own defaults
    /// hold.
    func scoreboardSnapshots() -> [WidgetScoreboardSnapshot] {
        groupDefaults.map { WidgetScoreboardCodec.read(from: $0) } ?? []
    }

    /// Whether the widget can read what the app shares, through which
    /// store, and when the app last shared its scoreboard.
    var status: SharedDataStatus {
        if let groupDefaults, Self.appHasWritten(to: groupDefaults) {
            let lastShared = WidgetScoreboardCodec.writtenAt(in: groupDefaults)
            guard let groupID, groupID != SharedStoreIdentity.canonicalGroup else {
                return .available(lastShared: lastShared)
            }
            return .fallback(.appGroup(groupID), lastShared: lastShared)
        }
        if let keychain, let mirror = SharedFavoritesMirror.decode(keychain.data(for: SharedFavoritesMirror.keychainAccount)) {
            return .fallback(.keychain(keychain.accessGroup), lastShared: mirror.writtenAt)
        }
        if groupDefaults != nil {
            return .unshared(.appGroup(groupID ?? SharedStoreIdentity.canonicalGroup))
        }
        // A keychain group both processes hold, not yet written by the app:
        // nothing shared yet, not nothing shareable.
        if let keychain {
            return .unshared(.keychain(keychain.accessGroup))
        }
        return .unavailable
    }

    /// Whether the app has written to `defaults`: its favorites (or the
    /// mark that it loaded them), their mirror, or a scoreboard. The widget
    /// writes none of these.
    static func appHasWritten(to defaults: UserDefaults) -> Bool {
        defaults.object(forKey: FavoritesCodec.seededKey) != nil
            || defaults.data(forKey: FavoritesCodec.key) != nil
            || defaults.data(forKey: SharedFavoritesMirror.defaultsKey) != nil
            || WidgetScoreboardCodec.writtenAt(in: defaults) != nil
    }
}

/// A store the app and the widget can share through.
enum SharedStore: Hashable, Sendable {
    /// An App Group, by identifier.
    case appGroup(String)
    /// A keychain access group, by name.
    case keychain(String)

    /// "App Group", "re-signed App Group" or "Keychain": short enough for a
    /// tile's caption.
    var label: String {
        switch self {
        case .appGroup(let id):
            return id == SharedStoreIdentity.canonicalGroup ? "App Group" : "re-signed App Group"
        case .keychain:
            return "Keychain"
        }
    }

    /// The store and its identifier, for the larger layouts.
    var detail: String {
        switch self {
        case .appGroup(let id): return "App Group \(id)"
        case .keychain(let group): return "Keychain \(group)"
        }
    }
}

/// What the widgets tell the reader about the data the app shares with them.
enum SharedDataStatus: Hashable, Sendable {
    /// The project's App Group holds the app's data; the app last wrote its
    /// scoreboard at `lastShared`, `nil` before it ever has.
    case available(lastShared: Date?)
    /// The app's data reaches the widget through another store: a
    /// re-signed install's own App Group, or the keychain. `lastShared` is
    /// the group's last scoreboard, or the keychain copy's write.
    case fallback(SharedStore, lastShared: Date?)
    /// A store is reachable but holds nothing the app wrote: the app and
    /// the widget are not reading the same one, or the app has not been
    /// opened since it was installed.
    case unshared(SharedStore)
    /// No store is reachable: the install's signature carries no App Group,
    /// keychain group or application identifier, and only re-signing with
    /// a profile that has one repairs that. A team chosen in the widget's
    /// settings still shows (`WidgetConfigTeams`).
    case unavailable

    /// Whether the app's data reaches the widget.
    var isAvailable: Bool {
        switch self {
        case .available, .fallback: return true
        case .unshared, .unavailable: return false
        }
    }

    static let unavailableTitle = "Shared data unavailable"
    static let repairHint = "Choose a team in Edit Widget, or re-sign with an App Group."
    /// The one caption-sized line a widget or its settings show.
    static let unavailableCaption = "Shared data unavailable — signature has no App Group or keychain group"

    /// The caption-sized line a widget draws under its content: which store
    /// it reads and whether that works. `nil` while the project's group
    /// carries the app's data.
    var note: String? {
        switch self {
        case .available:
            return nil
        case .fallback(let store, _):
            return "Shared via \(store.label)"
        case .unshared(let store):
            return "\(store.label) has no data from the app — open myTeams"
        case .unavailable:
            return Self.unavailableCaption
        }
    }

    /// "Shared data: OK · 3:42 PM", or the status's `note`.
    func caption(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
        switch self {
        case .available(let lastShared?):
            return "Shared data: OK · \(Self.when(lastShared, now: now, calendar: calendar))"
        case .available(nil):
            return "Shared data: OK"
        case .fallback(let store, let lastShared?):
            return "Shared data: OK via \(store.label) · \(Self.when(lastShared, now: now, calendar: calendar))"
        case .fallback(let store, nil):
            return "Shared data: OK via \(store.label)"
        case .unshared, .unavailable:
            return note ?? Self.unavailableCaption
        }
    }

    /// "Data from 3:42 PM": what a widget showing a copy it kept says.
    static func dataFrom(_ date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        "Data from \(when(date, now: now, calendar: calendar))"
    }

    /// The time alone today, else with the date.
    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Logo store

/// Which of a team's crests: the one for light backgrounds or the one for dark.
enum LogoVariant: String, Codable, Sendable, CaseIterable {
    case `default`
    case dark
}

/// Team crests on disk, shared by the app and the widget.
///
/// Favorites' crests live under Application Support, so the OS cannot purge
/// what the widget needs; every other team's live under Caches. Files are
/// PNGs downscaled to at most 256 px on their long side, named
/// `{sport}.{league}_{espnID}.{variant}.png`.
///
/// Reads are synchronous and never touch the network, so widget views and
/// SwiftUI bodies can call them. Writes are `async`. There is no shared
/// mutable state beyond a decoded-image cache, so the widget process can use
/// this freely.
enum LogoStore {
    /// The longest side, in pixels, of a stored crest.
    static let maxPixelSize = 256

    /// How long a stored crest is trusted before it is revalidated. Crests
    /// change only on rebrands.
    static let revalidationInterval: TimeInterval = 7 * 24 * 60 * 60

    /// The `UserDefaults` key recording that the bundled crests were copied in.
    static let seededDefaultsKey = "LogoStore.seededBundledCrests"

    static var favoritesDirectory: URL {
        SharedPaths.applicationSupport.appending(path: "Logos/favorites", directoryHint: .isDirectory)
    }

    static var catalogDirectory: URL {
        SharedPaths.caches.appending(path: "Logos/catalog", directoryHint: .isDirectory)
    }

    /// Decoded crests, keyed by file path. Only ever touched through
    /// `NSCache`'s own thread-safe API.
    nonisolated(unsafe) private static let decoded: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    // MARK: Paths

    /// e.g. `football.nfl_12.default.png`.
    static func fileName(for team: TeamRef, variant: LogoVariant) -> String {
        let league = team.league.path.replacingOccurrences(of: "/", with: ".")
        return "\(league)_\(team.espnID).\(variant.rawValue).png"
    }

    /// Where a crest is (or would be) stored.
    static func fileURL(for team: TeamRef, variant: LogoVariant, favorite: Bool) -> URL {
        (favorite ? favoritesDirectory : catalogDirectory)
            .appending(path: fileName(for: team, variant: variant), directoryHint: .notDirectory)
    }

    /// The feed URL a variant is downloaded from. `nil` for a dark variant the
    /// feed does not supply separately.
    static func sourceURL(for team: TeamRef, variant: LogoVariant) -> URL? {
        switch variant {
        case .default:
            return team.logoURL
        case .dark:
            guard let dark = team.logoDarkURL, dark != team.logoURL else { return nil }
            return dark
        }
    }

    // MARK: Reading

    /// The stored crest's file, favorites first, if one exists and is readable.
    static func url(for team: TeamRef, variant: LogoVariant) -> URL? {
        let manager = FileManager.default
        return [true, false]
            .map { fileURL(for: team, variant: variant, favorite: $0) }
            .first { manager.isReadableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// The stored crest, read from disk. Never uses the network.
    static func image(for team: TeamRef, variant: LogoVariant) -> UIImage? {
        guard let url = url(for: team, variant: variant) else { return nil }
        let key = url.path(percentEncoded: false) as NSString
        if let cached = decoded.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: key as String) else { return nil }
        decoded.setObject(image, forKey: key)
        return image
    }

    // MARK: Writing

    /// Downscales `data` to at most `maxPixelSize` px and writes it as a PNG.
    ///
    /// Returns whether a file was written. Data that is not an image writes
    /// nothing.
    @discardableResult
    static func store(_ data: Data, for team: TeamRef, variant: LogoVariant, favorite: Bool) async -> Bool {
        guard let png = downscaledPNG(data) else {
            logger.error("Crest for \(team.id) is not a readable image")
            return false
        }
        return write(png, to: fileURL(for: team, variant: variant, favorite: favorite))
    }

    /// Re-encodes an image as a PNG no larger than `maxPixelSize` on its long
    /// side, keeping transparency. Smaller images keep their size.
    static func downscaledPNG(_ data: Data, maxPixelSize: Int = LogoStore.maxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Writes atomically, creating the directory first.
    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            decoded.removeObject(forKey: url.path(percentEncoded: false) as NSString)
            return true
        } catch {
            logger.error("Could not write \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Fetching

    /// The validators saved beside a crest, for its next conditional GET.
    private struct Validators: Codable {
        var etag: String?
        var lastModified: String?
    }

    private static func validatorsURL(for file: URL) -> URL {
        file.appendingPathExtension("validators")
    }

    /// Makes sure a crest is stored, downloading it if needed.
    ///
    /// A stored crest younger than `revalidationInterval` is trusted as is.
    /// An older one is revalidated with a conditional GET (`If-None-Match` /
    /// `If-Modified-Since`): a 304 just restarts its clock. A 403 or 404
    /// stores nothing, and the views draw a monogram instead. The file goes to
    /// the favorites directory when `favorite` is set or a favorite copy
    /// already exists, and to the catalog cache otherwise.
    ///
    /// Returns whether a crest is stored afterwards.
    @discardableResult
    static func prefetched(_ team: TeamRef, variant: LogoVariant, favorite: Bool = false) async -> Bool {
        // A fixture launch keeps the crests it has: the bundled ones.
        guard !HTTPClient.servesFixtures, let source = sourceURL(for: team, variant: variant) else {
            return url(for: team, variant: variant) != nil
        }
        let favoriteFile = fileURL(for: team, variant: variant, favorite: true)
        let toFavorites = favorite || FileManager.default.fileExists(atPath: favoriteFile.path(percentEncoded: false))
        let file = toFavorites ? favoriteFile : fileURL(for: team, variant: variant, favorite: false)
        let path = file.path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path)

        if exists, let modified = modificationDate(of: file),
           Date().timeIntervalSince(modified) < revalidationInterval {
            return true
        }

        var request = URLRequest(url: source)
        // Revalidate against ESPN, not against the session's own cache.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if exists, let validators = readValidators(for: file) {
            if let etag = validators.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = validators.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            let (body, urlResponse) = try await HTTPClient.defaultSession.data(for: request)
            guard let http = urlResponse as? HTTPURLResponse else { return exists }
            data = body
            response = http
        } catch {
            logger.debug("Crest download failed for \(team.id): \(error.localizedDescription)")
            return exists
        }

        switch response.statusCode {
        case 304 where exists:
            touch(file)
            return true
        case 200..<300:
            guard let png = downscaledPNG(data), write(png, to: file) else { return exists }
            writeValidators(
                Validators(
                    etag: response.value(forHTTPHeaderField: "ETag"),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified")
                ),
                for: file
            )
            return true
        default:
            // 403/404: ESPN has no crest for this team. Keep whatever is
            // already stored; store nothing new.
            logger.debug("Crest for \(team.id) answered HTTP \(response.statusCode)")
            return exists
        }
    }

    /// Fetches a team's default crest, and its dark one when the feed lists a
    /// separate dark URL.
    static func prefetchAllVariants(_ team: TeamRef, favorite: Bool = false) async {
        await prefetched(team, variant: .default, favorite: favorite)
        if sourceURL(for: team, variant: .dark) != nil {
            await prefetched(team, variant: .dark, favorite: favorite)
        }
    }

    /// Copies a team's cached crests into the favorites directory, so the OS
    /// cannot purge them. Fetches any the cache lacks. Call when a team is
    /// favorited.
    static func promoteToFavorites(_ team: TeamRef) async {
        let manager = FileManager.default
        for variant in LogoVariant.allCases {
            let cached = fileURL(for: team, variant: variant, favorite: false)
            let favorite = fileURL(for: team, variant: variant, favorite: true)
            if manager.fileExists(atPath: cached.path(percentEncoded: false)),
               let data = try? Data(contentsOf: cached),
               write(data, to: favorite) {
                if let validators = try? Data(contentsOf: validatorsURL(for: cached)) {
                    try? validators.write(to: validatorsURL(for: favorite), options: .atomic)
                }
            } else if variant == .default || sourceURL(for: team, variant: variant) != nil {
                await prefetched(team, variant: variant, favorite: true)
            }
        }
    }

    /// Copies the bundled crests of the teams that ship with one into the
    /// favorites directory, once (roadmap §4.5 step 2). Offline first runs and
    /// the widget then find them on disk.
    ///
    /// Returns whether it stored any crest; once one has, later calls find the
    /// flag set and do nothing.
    @discardableResult
    static func seedBundledCrestsIfNeeded(
        teams: [TeamRef] = TeamCatalog.all,
        defaults: UserDefaults = .standard
    ) async -> Bool {
        guard !defaults.bool(forKey: seededDefaultsKey) else { return false }
        var seededAny = false
        for team in teams {
            guard let asset = team.logoAsset,
                  let data = UIImage(named: asset)?.pngData()
            else { continue }
            if await store(data, for: team, variant: .default, favorite: true) {
                seededAny = true
            }
        }
        // A bundle without the crests (the widget's) leaves the flag unset,
        // so a later run from one that has them still seeds.
        if seededAny {
            defaults.set(true, forKey: seededDefaultsKey)
        }
        return seededAny
    }

    // MARK: Sized URLs

    /// The crest at `size` × `size` px through ESPN's image combiner, e.g.
    /// `https://a.espncdn.com/combiner/i?img=/i/teamlogos/nfl/500/kc.png&w=120&h=120`.
    ///
    /// Only `a.espncdn.com/i/teamlogos/…` hrefs can be resized this way; any
    /// other href comes back unchanged. `nil` when the team has no URL for
    /// the variant.
    static func combinerURL(_ team: TeamRef, size: Int, variant: LogoVariant) -> URL? {
        sourceURL(for: team, variant: variant).map { combinerURL(for: $0, size: size) }
    }

    /// `source` resized through the combiner, keeping its `500/` or
    /// `500-dark/` directory.
    static func combinerURL(for source: URL, size: Int) -> URL {
        guard let parts = URLComponents(url: source, resolvingAgainstBaseURL: false),
              parts.host == "a.espncdn.com",
              parts.path.hasPrefix("/i/teamlogos/")
        else { return source }

        var combiner = URLComponents()
        combiner.scheme = "https"
        combiner.host = "a.espncdn.com"
        combiner.path = "/combiner/i"
        combiner.queryItems = [
            URLQueryItem(name: "img", value: parts.path),
            URLQueryItem(name: "w", value: String(size)),
            URLQueryItem(name: "h", value: String(size)),
        ]
        return combiner.url ?? source
    }

    // MARK: File metadata

    private static func modificationDate(of file: URL) -> Date? {
        try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Restarts a crest's revalidation clock.
    private static func touch(_ file: URL) {
        var file = file
        var values = URLResourceValues()
        values.contentModificationDate = Date()
        try? file.setResourceValues(values)
    }

    private static func readValidators(for file: URL) -> Validators? {
        guard let data = try? Data(contentsOf: validatorsURL(for: file)) else { return nil }
        return try? JSONDecoder().decode(Validators.self, from: data)
    }

    private static func writeValidators(_ validators: Validators, for file: URL) {
        guard validators.etag != nil || validators.lastModified != nil,
              let data = try? JSONEncoder().encode(validators)
        else { return }
        try? data.write(to: validatorsURL(for: file), options: .atomic)
    }
}
