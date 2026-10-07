//
//  WikidataHeadshotStoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// The Wikimedia Commons headshot fallback: the sport → property map, the
/// URLs, the parsers over captured Wikidata and Commons answers (see
/// FIXTURES.md, "Wikidata and Commons"), the store's batching, roster
/// prefetch, lazy licences and cache, and the image loader's de-dupe.
/// No test reaches the network.
@Suite("Wikidata headshots", .serialized)
@MainActor
struct WikidataHeadshotStoreTests {
    /// The Royals' 28 roster ids (`royals_roster.json`) and one no athlete
    /// has, in the order the partial-miss fixture asked for them.
    private static let royalsIDs = [
        "5136077", "4417208", "35432", "42214", "36618", "38958", "31048", "41461", "40976", "34873",
        "41227", "39646", "4987667", "32640", "4917812", "33271", "4905884", "4109223", "4109109", "40718",
        "4151063", "42403", "4926296", "42959", "41263", "42486", "4418140", "31127", "99999999",
    ]

    private static let shaqTitle = "Shaquille%20O%27Neal%20October%202017%20%28cropped%29.jpg"

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "WikidataHeadshotStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// Answers Wikidata with `sparql` and Commons with `commons`.
    private func makeTransport(sparql: String, commons: String) -> RecordingTransport {
        RecordingTransport { url, _ in
            let name = url.host() == "query.wikidata.org" ? sparql : commons
            return (try? RecordingTransport.Reply.fixture(name)) ?? .status(404)
        }
    }

    private func makeStore(_ transport: RecordingTransport, directory: URL) -> WikidataHeadshotStore {
        WikidataHeadshotStore(
            client: HTTPClient(transport: transport),
            directory: directory,
            debounce: .milliseconds(20),
            enabled: true
        )
    }

    private func requests(to host: String, in transport: RecordingTransport) -> [URL] {
        transport.urls.filter { $0.host() == host }
    }

    // MARK: Property map

    @Test("Each sport maps to the Wikidata property holding ESPN's athlete id")
    func propertyMap() {
        #expect(WikidataHeadshots.property(for: .mlb) == "P3571")
        #expect(WikidataHeadshots.property(for: .nfl) == "P3686")
        #expect(WikidataHeadshots.property(for: .nba) == "P3685")
        #expect(WikidataHeadshots.property(for: .nhl) == "P3687")
        // Every soccer competition shares ESPN FC's ids.
        for league in [LeagueID.mls, .premierLeague, .laLiga, .nwsl, .wsl, .premiereLigue, .championsLeague] {
            #expect(WikidataHeadshots.property(for: league) == "P3681")
        }
        // Wired, though it holds ESPN's legacy college ids.
        #expect(WikidataHeadshots.property(for: .collegeFootball) == "P7262")
        // No property: the monogram stays.
        #expect(WikidataHeadshots.property(for: .wnba) == nil)
        #expect(WikidataHeadshots.property(for: .mensCollegeBasketball) == nil)
        #expect(WikidataHeadshots.property(for: .womensCollegeBasketball) == nil)
    }

    // MARK: URLs

    @Test("A P18 title goes into Special:FilePath encoded exactly once")
    func imageURLKeepsEncoding() throws {
        let head = try Fixture.json("commons_filepath_head")
        let url = try #require(WikidataHeadshots.imageURL(fileTitle: Self.shaqTitle))

        // The URL that answered 302 to the thumbnail, not the 404 one.
        #expect(url.absoluteString == head["request"].stringValue)
        #expect(url.absoluteString != head["doubleEncoded"]["request"].stringValue)
        #expect(head["status"].intValue == 302)
        #expect(head["doubleEncoded"]["status"].intValue == 404)
        #expect(!url.absoluteString.contains("%25"))
        #expect(url.absoluteString.contains("O%27Neal%20October"))

        let raya = try #require(WikidataHeadshots.imageURL(fileTitle: "David%20Raya.jpg"))
        #expect(raya.absoluteString == "https://commons.wikimedia.org/wiki/Special:FilePath/David%20Raya.jpg?width=250")
        #expect(
            WikidataHeadshots.descriptionPage(fileTitle: Self.shaqTitle)
                == "https://commons.wikimedia.org/wiki/File:\(Self.shaqTitle)"
        )
    }

    @Test("A P18 value yields its file title still encoded")
    func fileTitleFromP18() {
        #expect(
            WikidataHeadshots.fileTitle(fromP18: "http://commons.wikimedia.org/wiki/Special:FilePath/\(Self.shaqTitle)")
                == Self.shaqTitle
        )
        #expect(WikidataHeadshots.fileTitle(fromP18: "") == nil)
        #expect(WikidataHeadshots.fileTitle(fromP18: "http://commons.wikimedia.org/wiki/Special:FilePath/") == nil)
    }

    @Test("The SPARQL query names the property and every id, and its URL asks for JSON with maxlag")
    func sparqlURL() throws {
        let query = WikidataHeadshots.sparqlQuery(ids: ["196176", "265921"], property: "P3681")
        #expect(query.contains("VALUES ?espnId { \"196176\" \"265921\" }"))
        #expect(query.contains("?item wdt:P3681 ?espnId"))
        #expect(query.contains("OPTIONAL { ?item wdt:P18 ?image . }"))

        let url = try #require(WikidataHeadshots.sparqlURL(ids: ["196176", "265921"], property: "P3681"))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "query.wikidata.org")
        #expect(parts.path == "/sparql")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["query"] == query)
        #expect(items["format"] == "json")
        #expect(items["maxlag"] == "5")
    }

    @Test("The Commons request asks for decoded File: titles")
    func commonsURL() throws {
        let url = try #require(WikidataHeadshots.commonsInfoURL(fileTitles: [Self.shaqTitle, "Dyson%20Daniels.png"]))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "commons.wikimedia.org")
        let titles = parts.queryItems?.first { $0.name == "titles" }?.value
        #expect(titles == "File:Shaquille O'Neal October 2017 (cropped).jpg|File:Dyson Daniels.png")
    }

    // MARK: Parsing

    @Test("A soccer batch matches every id to its item and photo")
    func parseSoccerHit() throws {
        let matches = WikidataHeadshots.parseMatches(try Fixture.json("wikidata_p3681_soccer_hit"))
        #expect(matches.count == 3)
        #expect(matches["196176"]?.qid == "Q19665907")
        #expect(matches["265921"]?.qid == "Q56249966")
        #expect(matches["69450"]?.qid == "Q1910")
        #expect(matches["69450"]?.fileTitle == "Yohan%20Cabaye.JPG")
        #expect(matches["196176"]?.fileTitle == "David%20Raya%20Argentina%20v%20Spain%2019%20July%202026-003%20%28cropped%29.jpg")
    }

    @Test("A partial miss leaves unknown ids out and image-less items without a title")
    func parseRoyalsPartial() throws {
        let matches = WikidataHeadshots.parseMatches(try Fixture.json("wikidata_p3571_royals_partial"))
        #expect(matches.count == 21)
        #expect(matches.values.filter { $0.fileTitle != nil }.count == 19)
        #expect(matches["99999999"] == nil)
        #expect(matches["5136077"] == nil)
        #expect(matches["40718"]?.qid == "Q66459263")
        #expect(matches["40718"]?.fileTitle == nil)
        #expect(matches["34873"]?.fileTitle == "Seth%20Lugo%20on%20July%2016%2C%202016.jpg")
    }

    @Test("Apostrophes in P18 titles stay encoded")
    func parseApostrophes() throws {
        let matches = WikidataHeadshots.parseMatches(try Fixture.json("wikidata_p3685_nba_apostrophe"))
        #expect(matches["614"]?.fileTitle == Self.shaqTitle)
        #expect(matches["4282"]?.fileTitle == "Hamady%20N%27Diaye%20in%202011.jpg")
        #expect(matches["4869342"]?.qid == "Q107308380")
    }

    @Test("Commons licences are matched back to the encoded titles asked for")
    func parseLicenses() throws {
        let matches = WikidataHeadshots.parseMatches(try Fixture.json("wikidata_p3571_royals_partial"))
        let titles = matches.values.compactMap(\.fileTitle)
        let licenses = WikidataHeadshots.parseLicenses(try Fixture.json("commons_imageinfo_royals"), requested: titles)
        #expect(licenses.count == 19)
        #expect(licenses["Seth%20Lugo%20on%20July%2016%2C%202016.jpg"] == CommonsLicense(shortName: "CC0", artist: "D. Benjamin Miller"))

        let soccer = WikidataHeadshots.parseLicenses(
            try Fixture.json("commons_imageinfo_soccer"),
            requested: ["Yohan%20Cabaye.JPG", "David%20Raya%20Argentina%20v%20Spain%2019%20July%202026-003%20%28cropped%29.jpg"]
        )
        #expect(soccer["Yohan%20Cabaye.JPG"] == CommonsLicense(shortName: "CC BY-SA 3.0", artist: "Stanislav Vedmid"))
        #expect(soccer.values.contains(CommonsLicense(shortName: "CC BY-SA 4.0", artist: "Bryan Berlin")))

        let nba = WikidataHeadshots.parseLicenses(try Fixture.json("commons_imageinfo_nba"), requested: [Self.shaqTitle])
        #expect(nba[Self.shaqTitle] == CommonsLicense(shortName: "CC BY-SA 2.0", artist: "MarkScottAustinTX"))
    }

    @Test("Artist HTML reads as plain text")
    func plainText() {
        #expect(WikidataHeadshots.plainText("<a href=\"//x\">Tom &amp; Jerry</a>\n") == "Tom & Jerry")
        #expect(WikidataHeadshots.plainText("") == "")
        #expect(WikidataHeadshots.plainText(String(repeating: "a", count: 300)).count == 120)
    }

    // MARK: Store

    /// The store's records for `property`'s photos, as the credits would ask.
    private func photos(_ store: WikidataHeadshotStore, property: String) -> [CommonsPhoto] {
        (store.records[property] ?? [:]).values.compactMap(\.photo)
    }

    @Test("Misses requested together go out as one query, and every id is cached")
    func batchesAndCaches() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = makeTransport(sparql: "wikidata_p3571_royals_partial", commons: "commons_imageinfo_royals")
        let store = makeStore(transport, directory: directory)

        for id in Self.royalsIDs {
            store.request(espnID: id, league: .mlb)
        }
        await store.settle()

        let sparql = requests(to: "query.wikidata.org", in: transport)
        #expect(sparql.count == 1)
        // Licences wait until a credit is looked at.
        #expect(requests(to: "commons.wikimedia.org", in: transport).isEmpty)
        let sparqlURL = try #require(sparql.first)
        let parts = try #require(URLComponents(url: sparqlURL, resolvingAgainstBaseURL: false))
        let query = try #require(parts.queryItems?.first { $0.name == "query" }?.value)
        #expect(query.contains("wdt:P3571"))
        for id in Self.royalsIDs {
            #expect(query.contains("\"\(id)\""))
            // Hit or miss, every id is answered.
            #expect(store.record(espnID: id, league: .mlb) != nil)
        }

        // A miss and an image-less item cache as "no photo".
        #expect(store.record(espnID: "5136077", league: .mlb)?.photo == nil)
        #expect(store.record(espnID: "40718", league: .mlb)?.photo == nil)

        // Looking at the credits fetches every photo's licence in one
        // request, and a hit keeps its attribution.
        store.requestLicenses(for: photos(store, property: "P3571"))
        await store.settle()
        #expect(requests(to: "commons.wikimedia.org", in: transport).count == 1)
        let lugo = try #require(store.photo(espnID: "34873", league: .mlb))
        #expect(lugo.qid == "Q16605329")
        #expect(lugo.licenseShortName == "CC0")
        #expect(lugo.artist == "D. Benjamin Miller")
        #expect(lugo.descriptionPage == "https://commons.wikimedia.org/wiki/File:Seth%20Lugo%20on%20July%2016%2C%202016.jpg")
        #expect(lugo.creditLine == "Photo: D. Benjamin Miller, CC0, via Wikimedia Commons")

        // The same ids in another sport are another question.
        #expect(store.record(espnID: "34873", league: .nfl) == nil)
    }

    @Test("A cached athlete is never queried again, in this launch or the next")
    func noRequery() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = makeTransport(sparql: "wikidata_p3571_royals_partial", commons: "commons_imageinfo_royals")
        let first = makeStore(transport, directory: directory)
        for id in Self.royalsIDs {
            first.request(espnID: id, league: .mlb)
        }
        await first.settle()
        first.requestLicenses(for: photos(first, property: "P3571"))
        await first.settle()
        let afterFirst = transport.requestCount

        // Known licences are not asked for again.
        first.requestLicenses(for: photos(first, property: "P3571"))
        await first.settle()
        #expect(transport.requestCount == afterFirst)

        for id in Self.royalsIDs {
            first.request(espnID: id, league: .mlb)
        }
        await first.settle()
        #expect(transport.requestCount == afterFirst)

        // A new store reads the cache from disk.
        let relaunched = makeStore(transport, directory: directory)
        #expect(relaunched.photo(espnID: "34873", league: .mlb)?.licenseShortName == "CC0")
        #expect(relaunched.record(espnID: "99999999", league: .mlb)?.photo == nil)
        #expect(relaunched.record(espnID: "99999999", league: .mlb) != nil)
        for id in Self.royalsIDs {
            relaunched.request(espnID: id, league: .mlb)
        }
        await relaunched.settle()
        #expect(transport.requestCount == afterFirst)
    }

    @Test("More than 200 misses split into 200-id queries")
    func batchLimit() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = RecordingTransport(always: .init(body: Data(#"{"results":{"bindings":[]}}"#.utf8)))
        let store = makeStore(empty, directory: directory)

        for id in 1...250 {
            store.request(espnID: String(id), league: .nhl)
        }
        await store.settle()

        #expect(empty.requestCount == 2)
        #expect(store.record(espnID: "250", league: .nhl)?.photo == nil)
        // No photos found: Commons is never asked.
        #expect(requests(to: "commons.wikimedia.org", in: empty).isEmpty)
    }

    @Test("A failed query caches nothing and backs off silently")
    func failureIsSilent() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = RecordingTransport(always: .status(500))
        let store = makeStore(failing, directory: directory)

        store.request(espnID: "34873", league: .mlb)
        await store.settle()
        #expect(failing.requestCount == 1)
        #expect(store.record(espnID: "34873", league: .mlb) == nil)

        // Within the back-off, a request is dropped without a query.
        store.request(espnID: "34873", league: .mlb)
        await store.settle()
        #expect(failing.requestCount == 1)

        // So is a prefetch: the rows that come back on screen ask again.
        store.prefetch(espnIDs: ["34873"], league: .mlb)
        await store.settle()
        #expect(failing.requestCount == 1)
        #expect(store.record(espnID: "34873", league: .mlb) == nil)
    }

    @Test("Ids that cannot be ESPN's, and leagues with no property, are never queried")
    func ignoredRequests() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: .status(500))
        let store = makeStore(transport, directory: directory)

        store.request(espnID: "Bobby Witt Jr.#7", league: .mlb)
        store.request(espnID: "", league: .mlb)
        store.request(espnID: "3058901", league: .wnba)
        await store.settle()
        #expect(transport.requestCount == 0)

        let disabled = WikidataHeadshotStore(
            client: HTTPClient(transport: transport),
            directory: directory,
            debounce: .milliseconds(20),
            enabled: false
        )
        disabled.request(espnID: "34873", league: .mlb)
        await disabled.settle()
        #expect(transport.requestCount == 0)
    }

    @Test("Photos shown are listed once each for the credits")
    func creditsList() {
        let store = makeStore(RecordingTransport(always: .status(500)), directory: scratchDirectory())
        let photo = CommonsPhoto(
            qid: "Q169452",
            fileTitle: Self.shaqTitle,
            licenseShortName: "CC BY-SA 2.0",
            artist: "MarkScottAustinTX",
            descriptionPage: WikidataHeadshots.descriptionPage(fileTitle: Self.shaqTitle)
        )
        store.noteShown(photo)
        store.noteShown(photo)
        #expect(store.shownThisSession == [photo])
        #expect(photo.displayTitle == "Shaquille O'Neal October 2017 (cropped).jpg")
        #expect(photo.creditLine == "Photo: MarkScottAustinTX, CC BY-SA 2.0, via Wikimedia Commons")
        #expect(photo.imageURL == WikidataHeadshots.imageURL(fileTitle: Self.shaqTitle))

        var anonymous = photo
        anonymous.artist = ""
        anonymous.licenseShortName = ""
        #expect(anonymous.creditLine == "Photo via Wikimedia Commons")
    }
    // MARK: Roster prefetch

    @Test("A roster that lands is asked about at once in one query, without the debounce")
    func prefetchSendsAtOnce() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = makeTransport(sparql: "wikidata_p3571_royals_partial", commons: "commons_imageinfo_royals")
        // A debounce no prefetch could sit out within the test's bound.
        let store = WikidataHeadshotStore(
            client: HTTPClient(transport: transport),
            directory: directory,
            debounce: .seconds(30),
            enabled: true
        )

        let clock = ContinuousClock()
        let started = clock.now
        // Name#number ids are skipped, not sent.
        store.prefetch(espnIDs: Self.royalsIDs + ["Bobby Witt Jr.#7"], league: .mlb)
        await store.settle()
        #expect(clock.now - started < WikidataHeadshotStore.maxWait)

        let sparql = requests(to: "query.wikidata.org", in: transport)
        #expect(sparql.count == 1)
        let sparqlURL = try #require(sparql.first)
        let parts = try #require(URLComponents(url: sparqlURL, resolvingAgainstBaseURL: false))
        let query = try #require(parts.queryItems?.first { $0.name == "query" }?.value)
        for id in Self.royalsIDs {
            #expect(query.contains("\"\(id)\""))
            #expect(store.record(espnID: id, league: .mlb) != nil)
        }
        #expect(!query.contains("Witt"))
        #expect(requests(to: "commons.wikimedia.org", in: transport).isEmpty)

        // The cards drawn afterwards find every answer cached and ask nothing,
        // and neither does the same roster loading again.
        for id in Self.royalsIDs {
            store.request(espnID: id, league: .mlb)
        }
        store.prefetch(espnIDs: Self.royalsIDs, league: .mlb)
        await store.settle()
        #expect(transport.requestCount == 1)
    }

    @Test("Render-time misses still debounce, by about 0.3 s by default")
    func renderTimeDebounce() async {
        #expect(WikidataHeadshotStore.defaultDebounce == .milliseconds(300))

        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = makeTransport(sparql: "wikidata_p3571_royals_partial", commons: "commons_imageinfo_royals")
        let store = makeStore(transport, directory: directory)

        // A prefetch and the rows a game sheet draws meanwhile share one query.
        store.prefetch(espnIDs: Array(Self.royalsIDs.prefix(10)), league: .mlb)
        for id in Self.royalsIDs.dropFirst(10) {
            store.request(espnID: id, league: .mlb)
        }
        await store.settle()
        #expect(requests(to: "query.wikidata.org", in: transport).count == 1)
        for id in Self.royalsIDs {
            #expect(store.record(espnID: id, league: .mlb) != nil)
        }
    }

    // MARK: Lazy licences

    @Test("A photo is displayable as soon as Wikidata answers, with no licence fetched")
    func displayableWithoutLicense() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Commons's API would fail: the photo must not depend on it.
        let transport = RecordingTransport { url, _ in
            guard url.host() == "query.wikidata.org" else { return .status(500) }
            return (try? RecordingTransport.Reply.fixture("wikidata_p3571_royals_partial")) ?? .status(404)
        }
        let store = makeStore(transport, directory: directory)

        store.prefetch(espnIDs: Self.royalsIDs, league: .mlb)
        await store.settle()

        let lugo = try #require(store.photo(espnID: "34873", league: .mlb))
        #expect(!lugo.hasLicense)
        #expect(lugo.licenseShortName == nil)
        #expect(lugo.artist == nil)
        #expect(lugo.qid == "Q16605329")
        #expect(lugo.fileTitle == "Seth%20Lugo%20on%20July%2016%2C%202016.jpg")
        // All a headshot view needs to draw it.
        #expect(lugo.imageURL == WikidataHeadshots.imageURL(fileTitle: lugo.fileTitle))
        #expect(lugo.descriptionPage == "https://commons.wikimedia.org/wiki/File:Seth%20Lugo%20on%20July%2016%2C%202016.jpg")
        #expect(lugo.creditLine == "Photo via Wikimedia Commons")
        #expect(photos(store, property: "P3571").count == 19)
        #expect(requests(to: "commons.wikimedia.org", in: transport).isEmpty)

        // Cached without a licence, it still draws after a relaunch.
        let relaunched = makeStore(transport, directory: directory)
        #expect(relaunched.photo(espnID: "34873", league: .mlb)?.imageURL == lugo.imageURL)

        // A failed licence fetch is silent: the photo stays, credit generic.
        store.requestLicenses(for: [lugo])
        await store.settle()
        #expect(requests(to: "commons.wikimedia.org", in: transport).count == 1)
        #expect(store.photo(espnID: "34873", league: .mlb) == lugo)
    }

    @Test("A credit looked at fetches only its own licence, merged into the cache and the credits")
    func licenseFetchedOnInteraction() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = makeTransport(sparql: "wikidata_p3571_royals_partial", commons: "commons_imageinfo_royals")
        let store = makeStore(transport, directory: directory)

        store.prefetch(espnIDs: Self.royalsIDs, league: .mlb)
        await store.settle()
        let lugo = try #require(store.photo(espnID: "34873", league: .mlb))
        store.noteShown(lugo)
        #expect(store.shownThisSession.first?.hasLicense == false)

        // A long-press on Lugo's photo.
        store.requestLicenses(for: [lugo])
        store.requestLicenses(for: [lugo])
        await store.settle()

        let commons = requests(to: "commons.wikimedia.org", in: transport)
        #expect(commons.count == 1)
        let commonsURL = try #require(commons.first)
        let parts = try #require(URLComponents(url: commonsURL, resolvingAgainstBaseURL: false))
        let titles = try #require(parts.queryItems?.first { $0.name == "titles" }?.value)
        // Only the photo looked at, not the roster's other 18.
        #expect(titles == "File:Seth Lugo on July 16, 2016.jpg")

        let merged = try #require(store.photo(espnID: "34873", league: .mlb))
        #expect(merged.hasLicense)
        #expect(merged.licenseShortName == "CC0")
        #expect(merged.artist == "D. Benjamin Miller")
        #expect(merged.creditLine == "Photo: D. Benjamin Miller, CC0, via Wikimedia Commons")
        #expect(merged.qid == lugo.qid && merged.fileTitle == lugo.fileTitle)
        // The credits list shows it once, now with its licence.
        #expect(store.shownThisSession == [merged])
        store.noteShown(lugo)
        #expect(store.shownThisSession == [merged])
        // The others were never interacted with, and stay without one.
        #expect(photos(store, property: "P3571").filter(\.hasLicense).count == 1)

        // The merged licence is on disk.
        let relaunched = makeStore(transport, directory: directory)
        #expect(relaunched.photo(espnID: "34873", league: .mlb)?.licenseShortName == "CC0")
        #expect(relaunched.photo(espnID: "40976", league: .mlb).map(\.hasLicense) != true)
    }

    @Test("Cached entries from before lazy licences keep their licence")
    func legacyCacheDecodes() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = """
        {"614":{"checked":0,"photo":{"qid":"Q169452","fileTitle":"\(Self.shaqTitle)",\
        "licenseShortName":"CC BY-SA 2.0","artist":"MarkScottAustinTX",\
        "descriptionPage":"https://commons.wikimedia.org/wiki/File:\(Self.shaqTitle)"}}}
        """
        try Data(legacy.utf8).write(to: directory.appending(path: "P3685.json"))

        let store = makeStore(RecordingTransport(always: .status(500)), directory: directory)
        let shaq = try #require(store.photo(espnID: "614", league: .nba))
        #expect(shaq.hasLicense)
        #expect(shaq.creditLine == "Photo: MarkScottAustinTX, CC BY-SA 2.0, via Wikimedia Commons")
    }

    // MARK: Images

    @Test("A thumbnail asked for twice while downloading is downloaded once")
    func imageDownloadDeduped() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let transport = SlowTransport(body: png, delay: .milliseconds(200))
        let loader = CommonsImageLoader(transport: transport, enabled: true)
        let url = try #require(WikidataHeadshots.imageURL(fileTitle: Self.shaqTitle))

        async let card = loader.image(for: url)
        async let sheet = loader.image(for: url)
        let (first, second) = await (card, sheet)
        #expect(first != nil)
        #expect(second != nil)
        #expect(transport.requestCount == 1)

        // Once loaded it is served from memory.
        #expect(await loader.image(for: url) != nil)
        #expect(transport.requestCount == 1)

        // Another photo is its own download.
        let other = try #require(WikidataHeadshots.imageURL(fileTitle: "David%20Raya.jpg"))
        #expect(await loader.image(for: other) != nil)
        #expect(transport.requestCount == 2)
    }

    @Test("A failed thumbnail is nil, so the monogram stays, and is not cached")
    func imageFailureIsSilent() async throws {
        let failing = RecordingTransport(always: .status(404))
        let loader = CommonsImageLoader(transport: failing, enabled: true)
        let url = try #require(WikidataHeadshots.imageURL(fileTitle: Self.shaqTitle))
        #expect(await loader.image(for: url) == nil)
        #expect(await loader.image(for: url) == nil)
        #expect(failing.requestCount == 2)

        let disabled = CommonsImageLoader(transport: failing, enabled: false)
        #expect(await disabled.image(for: url) == nil)
        #expect(failing.requestCount == 2)
    }
}

/// Answers every request with `body` after `delay`, counting them: long
/// enough for a second caller to arrive while the first is in flight.
private final class SlowTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let body: Data
    private let delay: Duration

    init(body: Data, delay: Duration) {
        self.body = body
        self.delay = delay
    }

    var requestCount: Int { lock.withLock { count } }

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        lock.withLock { count += 1 }
        try await Task.sleep(for: delay)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }
}
