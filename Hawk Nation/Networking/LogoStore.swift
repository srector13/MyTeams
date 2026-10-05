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
/// Both targets carry the App Group entitlement, so these resolve to the
/// group container. A process without the group (a misconfigured signing
/// profile) gets `nil` from `containerURL(forSecurityApplicationGroupIdentifier:)`
/// and falls back to its own directories and `UserDefaults.standard`.
enum SharedPaths {
    static var appGroup: String { "group.PolarReailty.Hawk-Nation" }

    /// The App Group's `UserDefaults`, or `.standard` without the group.
    static var defaults: UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
              let shared = UserDefaults(suiteName: appGroup)
        else { return .standard }
        return shared
    }

    /// The favorites' `TeamRef.id`s, in order, as the app last saved them.
    /// Empty when none are stored. The widget reads favorites through this,
    /// not through the app's `FavoritesStore`.
    static func favoriteTeamIDs() -> [String] {
        FavoritesCodec.storedIDs(in: defaults) ?? []
    }

    /// The App Group container, or `fallback` while the process has no group.
    static func container(_ fallback: URL) -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) ?? fallback
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
