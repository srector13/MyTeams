//
//  LogoStoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// Runs against the real store directories: the App Group's (or, in a host
/// signed without the group, its own Application Support and Caches). Every
/// test files its crests under an ESPN id no real team has, then deletes
/// them.
@Suite("Logo store", .serialized)
struct LogoStoreTests {
    /// A made-up team in a made-up league, so nothing collides with real
    /// crests.
    private func scratchTeam(logoAsset: String? = nil) -> TeamRef {
        TeamRef(
            league: LeagueID(sport: "football", league: "test-league"),
            espnID: "test-\(UUID().uuidString)",
            displayName: "Test Team",
            shortName: "Test",
            abbreviation: "TST",
            location: "Test",
            colorHex: "123456",
            alternateColorHex: "FFFFFF",
            logoURL: nil,
            logoDarkURL: nil,
            logoAsset: logoAsset
        )
    }

    private func removeFiles(for team: TeamRef) {
        for variant in LogoVariant.allCases {
            for favorite in [true, false] {
                try? FileManager.default.removeItem(at: LogoStore.fileURL(for: team, variant: variant, favorite: favorite))
            }
        }
    }

    /// A 1024 × 1024 PNG: a red disc on a transparent square.
    private func largePNG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        return try #require(image.pngData())
    }

    @Test("Files are named league_id.variant.png, favorites apart from the cache")
    func paths() {
        #expect(LogoStore.fileName(for: .chiefs, variant: .default) == "football.nfl_12.default.png")
        #expect(LogoStore.fileName(for: .sporting, variant: .dark) == "soccer.usa.1_186.dark.png")

        let favorite = LogoStore.fileURL(for: .chiefs, variant: .default, favorite: true)
        let cached = LogoStore.fileURL(for: .chiefs, variant: .default, favorite: false)
        #expect(favorite.path().contains("/Logos/favorites/"))
        #expect(cached.path().contains("/Logos/catalog/"))
        #expect(favorite.path().contains("Application%20Support") || favorite.path().contains("Application Support"))
        #expect(cached.path().contains("/Caches/"))
        #expect(SharedPaths.teamCatalog.lastPathComponent == "TeamCatalog")
    }

    @Test("A stored crest reads back, downscaled to 256 px with its transparency")
    func storeRoundTrip() async throws {
        let team = scratchTeam()
        defer { removeFiles(for: team) }
        #expect(LogoStore.image(for: team, variant: .default) == nil)
        #expect(LogoStore.url(for: team, variant: .default) == nil)

        let big = try largePNG()
        #expect(UIImage(data: big)?.cgImage?.width == 1024)
        #expect(await LogoStore.store(big, for: team, variant: .default, favorite: false))

        let url = try #require(LogoStore.url(for: team, variant: .default))
        #expect(url == LogoStore.fileURL(for: team, variant: .default, favorite: false))
        let image = try #require(LogoStore.image(for: team, variant: .default))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) <= LogoStore.maxPixelSize)
        #expect(cgImage.width == 256)
        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        let hasAlpha = !opaque.contains(cgImage.alphaInfo)
        #expect(hasAlpha)

        // Nothing was stored for the dark variant.
        #expect(LogoStore.image(for: team, variant: .dark) == nil)
    }

    @Test("A favorite copy is found before the cached one, and promotion makes one")
    func favoritesFirst() async throws {
        let team = scratchTeam()
        defer { removeFiles(for: team) }
        let png = try largePNG()

        #expect(await LogoStore.store(png, for: team, variant: .default, favorite: false))
        #expect(LogoStore.url(for: team, variant: .default) == LogoStore.fileURL(for: team, variant: .default, favorite: false))

        await LogoStore.promoteToFavorites(team)
        #expect(LogoStore.url(for: team, variant: .default) == LogoStore.fileURL(for: team, variant: .default, favorite: true))
    }

    @Test("Data that is not an image stores nothing")
    func rejectsNonImages() async {
        let team = scratchTeam()
        defer { removeFiles(for: team) }
        #expect(await LogoStore.store(Data("not a png".utf8), for: team, variant: .default, favorite: false) == false)
        #expect(LogoStore.url(for: team, variant: .default) == nil)
    }

    @Test("A team with no crest URL fetches nothing")
    func prefetchWithoutURL() async {
        let team = scratchTeam()
        defer { removeFiles(for: team) }
        #expect(await LogoStore.prefetched(team, variant: .default) == false)
        #expect(await LogoStore.prefetched(team, variant: .dark) == false)
    }

    @Test("Only a separate dark URL counts as a dark crest")
    func darkSource() {
        #expect(LogoStore.sourceURL(for: .chiefs, variant: .dark)
            == URL(string: "https://a.espncdn.com/i/teamlogos/nfl/500-dark/kc.png"))
        var same = TeamRef.chiefs
        same.logoDarkURL = same.logoURL
        #expect(LogoStore.sourceURL(for: same, variant: .dark) == nil)
        #expect(LogoStore.sourceURL(for: scratchTeam(), variant: .default) == nil)
    }

    // MARK: Combiner

    @Test("Crest URLs are resized through ESPN's combiner, keeping 500 or 500-dark")
    func combiner() throws {
        #expect(LogoStore.combinerURL(.chiefs, size: 120, variant: .default)?.absoluteString
            == "https://a.espncdn.com/combiner/i?img=/i/teamlogos/nfl/500/kc.png&w=120&h=120")
        #expect(LogoStore.combinerURL(.chiefs, size: 120, variant: .dark)?.absoluteString
            == "https://a.espncdn.com/combiner/i?img=/i/teamlogos/nfl/500-dark/kc.png&w=120&h=120")
        #expect(LogoStore.combinerURL(.jayhawks, size: 75, variant: .default)?.absoluteString
            == "https://a.espncdn.com/combiner/i?img=/i/teamlogos/ncaa/500/2305.png&w=75&h=75")

        // Brand-service hrefs are not under /i/teamlogos/ and pass through.
        let guid = try #require(URL(string:
            "https://a.espncdn.com/guid/f68f2343-8ceb-7a02-740d-af6338be21d2/logos/secondary_logo_white.png"))
        #expect(LogoStore.combinerURL(for: guid, size: 120) == guid)
        let elsewhere = try #require(URL(string: "https://example.com/i/teamlogos/nfl/500/kc.png"))
        #expect(LogoStore.combinerURL(for: elsewhere, size: 120) == elsewhere)

        #expect(LogoStore.combinerURL(scratchTeam(), size: 120, variant: .default) == nil)
    }

    // MARK: Seeding

    @Test("Bundled crests are seeded into favorites once")
    func seedingIsIdempotent() async throws {
        let suite = "LogoStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seeded = scratchTeam(logoAsset: "chiefs")
        let unbundled = scratchTeam()
        defer {
            removeFiles(for: seeded)
            removeFiles(for: unbundled)
        }

        #expect(await LogoStore.seedBundledCrestsIfNeeded(teams: [seeded, unbundled], defaults: defaults))
        #expect(defaults.bool(forKey: LogoStore.seededDefaultsKey))
        let file = LogoStore.fileURL(for: seeded, variant: .default, favorite: true)
        #expect(LogoStore.url(for: seeded, variant: .default) == file)
        #expect(LogoStore.url(for: unbundled, variant: .default) == nil)

        // The second run finds the flag and leaves the files alone.
        try FileManager.default.removeItem(at: file)
        #expect(await LogoStore.seedBundledCrestsIfNeeded(teams: [seeded], defaults: defaults) == false)
        #expect(LogoStore.url(for: seeded, variant: .default) == nil)
    }
}
