//
//  WikidataHeadshotStoreTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing

@testable import myTeams

/// The Wikimedia Commons headshot fallback: the sport → property map, the
/// URLs, the parsers over captured Wikidata and Commons answers (see
/// FIXTURES.md, "Wikidata and Commons"), and the store's batching and cache.
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
        #expect(requests(to: "commons.wikimedia.org", in: transport).count == 1)
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

        // A hit keeps its attribution.
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
        let afterFirst = transport.requestCount

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
}
