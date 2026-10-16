//
//  HeadshotNameMatching.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.myTeams", category: "headshots")

// MARK: - Query

/// A soccer roster player as the photo sources beyond ESPN look them up:
/// by name, shirt number and club, never by ESPN id, which neither
/// TheSportsDB nor FotMob knows.
struct SoccerHeadshotQuery: Hashable, Sendable {
    /// ESPN's athlete id (`RosterPlayer.playerID`), or the roster's
    /// `"Name#23"` stand-in: only ever a cache key.
    var espnID: String
    /// ESPN's name for the player, e.g. `André Luiz`.
    var name: String
    /// The shirt number, when the roster gave one.
    var number: Int?
    /// The roster's club.
    var team: TeamRef

    init(espnID: String, name: String, number: String, team: TeamRef) {
        self.espnID = espnID
        self.name = name
        self.number = Int(number.trimmingCharacters(in: .whitespaces))
        self.team = team
    }

    /// The cache key: the club and the player, so a player who moves club
    /// is looked up again.
    var key: String { "\(team.id)#\(espnID.isEmpty ? name : espnID)" }

    /// Whether the club plays soccer: the only sport these sources serve.
    var isSoccer: Bool { team.league.sport == "soccer" }
}

// MARK: - Tiers

/// A source of athlete photos tried once ESPN has none.
enum HeadshotSource: String, Hashable, Sendable, CaseIterable {
    /// FotMob's squads, experimental (`FotMobHeadshotStore`).
    case fotMob
    /// API-Football, with the reader's own key (`ApiFootballHeadshotStore`).
    case apiFootball
    /// TheSportsDB's free API (`TheSportsDBHeadshotStore`).
    case theSportsDB
    /// Wikimedia Commons, found through Wikidata (`WikidataHeadshotStore`).
    case commons
}

/// What one source has said of an athlete, as the headshot view sees it.
enum HeadshotTierState: Hashable, Sendable {
    /// The source does not apply: its setting is off, it has no key, the
    /// sport is not one it serves, or the view lacks what it looks up by.
    case off
    /// It may yet answer: not asked, or not answered.
    case pending
    /// It has no photo of the athlete, or is not answering for now.
    case noPhoto
    /// Its photo of the athlete.
    case photo(URL)
}

/// The order the photo sources are tried in after ESPN, and which one a
/// headshot draws. Pure functions: `AthleteHeadshot` feeds them what the
/// stores know and draws what they choose.
enum HeadshotTiers {
    /// What a headshot draws in place of ESPN's.
    enum Choice: Hashable, Sendable {
        /// `source`'s photo at `url`.
        case photo(HeadshotSource, URL)
        /// Nothing yet: `source` may still answer, within the grace.
        case waiting(HeadshotSource)
        /// No source has a photo: the placeholder.
        case placeholder
    }

    /// How long a source that has not answered holds back the ones after it,
    /// counted from ESPN's failure: past it, its silence counts as no photo,
    /// though its photo is still drawn in place of a later tier's when it
    /// comes. As long as Wikidata's `WikidataHeadshotStore.maxWait`.
    static let grace: Duration = .seconds(2)

    /// The sources after ESPN for `league`: for soccer, FotMob, API-Football,
    /// TheSportsDB, then Wikimedia Commons; for every other sport (and no
    /// league), Commons alone.
    static func order(for league: LeagueID?) -> [HeadshotSource] {
        league?.sport == "soccer" ? [.fotMob, .apiFootball, .theSportsDB, .commons] : [.commons]
    }

    /// The first source in `order` with a photo, passing over those `.off`
    /// or `.noPhoto`. One `.pending` stops the walk — nothing is drawn yet —
    /// until `graceElapsed`, when it too is passed over.
    static func choose(
        order: [HeadshotSource],
        states: [HeadshotSource: HeadshotTierState],
        graceElapsed: Bool
    ) -> Choice {
        for source in order {
            switch states[source] ?? .off {
            case .photo(let url):
                return .photo(source, url)
            case .pending:
                if !graceElapsed { return .waiting(source) }
            case .noPhoto, .off:
                continue
            }
        }
        return .placeholder
    }

    /// The sources to ask about the athlete: in `order`, every one not
    /// `.off` up to and including the first with a photo, so none behind a
    /// photo is asked. Within the grace the walk also stops at the first
    /// `.pending` one, so the next is asked only once it has answered with
    /// none; past the grace, every one up to a photo is asked.
    static func sourcesToAsk(
        order: [HeadshotSource],
        states: [HeadshotSource: HeadshotTierState],
        graceElapsed: Bool
    ) -> [HeadshotSource] {
        var asked: [HeadshotSource] = []
        for source in order {
            switch states[source] ?? .off {
            case .off:
                continue
            case .photo:
                asked.append(source)
                return asked
            case .noPhoto:
                asked.append(source)
            case .pending:
                asked.append(source)
                if !graceElapsed { return asked }
            }
        }
        return asked
    }
}

// MARK: - Settings

/// Settings → Advanced → Soccer Photos: which of the extra soccer photo
/// sources the reader allows. Stored in `UserDefaults` under these keys,
/// which `@AppStorage` reads and writes, so a change applies to the next
/// headshot drawn without a relaunch.
enum SoccerPhotoSettings {
    /// TheSportsDB: on unless the reader turns it off.
    static let theSportsDBKey = "settings.thesportsdb.enabled"
    static let theSportsDBDefault = true
    /// FotMob, experimental: off unless the reader turns it on.
    static let fotMobKey = "settings.fotmob.enabled"
    static let fotMobDefault = false

    /// Whether TheSportsDB may be asked, as stored (on when never set).
    static func theSportsDBEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: theSportsDBKey) as? Bool ?? theSportsDBDefault
    }

    /// Whether FotMob may be asked, as stored (off when never set).
    static func fotMobEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: fotMobKey) as? Bool ?? fotMobDefault
    }
}

// MARK: - Matching

/// The name and club joins TheSportsDB and FotMob share. Pure functions.
///
/// Names compare as words (`ApiFootball.tokens`): lowercased, accents and
/// ligatures folded, apostrophes dropped. A join that finds two players,
/// or two clubs, it cannot tell apart finds none: a wrong face is worse
/// than the jersey avatar.
enum HeadshotNameMatching {
    /// `"Martin Ødegaard"` → `["martin", "odegaard"]`.
    static func words(_ text: String) -> [String] {
        ApiFootball.tokens(text)
    }

    /// Words a club's name carries that say nothing of which club it is,
    /// including the women's-side markers (`Arsenal (W)`, `Chelsea Women`).
    static let teamNoise: Set<String> = [
        "fc", "sc", "cf", "afc", "club", "the",
        "w", "wfc", "women", "womens", "ladies", "femenil", "femenino", "feminin", "feminine", "feminines",
    ]

    /// The leagues whose players are women: a men's row never joins them,
    /// nor theirs a men's roster.
    static let womensLeagues: Set<LeagueID> = [.wsl, .nwsl, .premiereLigue]

    static func isWomens(_ league: LeagueID) -> Bool {
        womensLeagues.contains(league) || league.league.contains("wchampions")
    }

    /// Whether a source's `gender` (`Male`, `female`, or nothing) fits a
    /// roster in a women's league or not. No gender fits either.
    static func genderFits(_ gender: String, womens: Bool) -> Bool {
        let gender = gender.trimmingCharacters(in: .whitespaces).lowercased()
        guard !gender.isEmpty else { return true }
        return womens ? gender == "female" : gender != "female"
    }

    /// A club's name without its noise: `"Sporting Kansas City FC"` →
    /// `["sporting", "kansas", "city"]`.
    static func teamWords(_ name: String) -> [String] {
        words(name).filter { !teamNoise.contains($0) }
    }

    /// Whether two names are the same club: either's words all in the
    /// other's — the same word, one beginning the other when both are 4+
    /// letters, or a short word that is the initials of consecutive words
    /// there (`KC` ↔ Kansas City, `LAFC` ↔ Los Angeles FC).
    static func teamNamesMatch(_ a: String, _ b: String) -> Bool {
        let rawA = words(a)
        let rawB = words(b)
        let wordsA = rawA.filter { !teamNoise.contains($0) }
        let wordsB = rawB.filter { !teamNoise.contains($0) }
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        return covers(wordsA, by: wordsB, raw: rawB) || covers(wordsB, by: wordsA, raw: rawA)
    }

    /// Whether `other` names ESPN's `team`: its full name, or a short name
    /// or location of two words or more (`Sporting KC`; never a lone
    /// `Sporting`, which half of Iberia shares), or initials that are its
    /// abbreviation (`SKC` ↔ Sporting Kansas City).
    static func teamMatches(_ team: TeamRef, _ other: String) -> Bool {
        if teamNamesMatch(team.displayName, other) { return true }
        for variant in [team.shortName, team.location]
        where variant != team.displayName && teamWords(variant).count >= 2 && teamNamesMatch(variant, other) {
            return true
        }
        let abbreviation = team.abbreviation.lowercased()
        let initials = String(teamWords(other).compactMap(\.first))
        return abbreviation.count >= 3 && initials == abbreviation
    }

    /// Whether every word of `small` is in `large`, or is the initials of
    /// consecutive words of `raw` (`large` with its noise).
    private static func covers(_ small: [String], by large: [String], raw: [String]) -> Bool {
        small.allSatisfy { word in
            large.contains { other in
                other == word
                    || (min(word.count, other.count) >= 4 && (other.hasPrefix(word) || word.hasPrefix(other)))
            } || isInitialism(word, of: raw)
        }
    }

    /// Club acronyms that spell out in full in another name's initials:
    /// `LAFC` ↔ Los Angeles FC.
    private static let spelledAcronyms: Set<String> = ["fc", "sc", "cf", "afc"]

    /// Whether `word` (2–5 letters) spells the initials of consecutive
    /// `words`, an acronym among them counting letter by letter.
    static func isInitialism(_ word: String, of words: [String]) -> Bool {
        let letters = Array(word)
        guard (2...5).contains(letters.count), letters.allSatisfy(\.isLetter) else { return false }
        let initials: [Character] = words.flatMap { part -> [Character] in
            if spelledAcronyms.contains(part) { return Array(part) }
            return part.first.map { [$0] } ?? []
        }
        guard initials.count >= letters.count else { return false }
        for start in 0...(initials.count - letters.count)
        where Array(initials[start..<(start + letters.count)]) == letters {
            return true
        }
        return false
    }

    /// The one of `candidates` who is ESPN's player `name`, wearing
    /// `number`:
    ///
    /// 1. the same words, in any order (`Dejan Joveljić` ↔ `Dejan Joveljic`);
    ///    of several, the one with the number;
    /// 2. failing any, and only with a number, the one wearing it whose
    ///    surname is the same or whose words hold the other's
    ///    (`Shapi Suleymanov` #93 ↔ `Magomed-Shapi Suleymanov` #93, a lone
    ///    `Capita` #7 ↔ `Capita` #7).
    ///
    /// `nil` when none fits, or several do.
    static func pick<Candidate>(
        name: String,
        number: Int?,
        among candidates: [Candidate],
        nameOf: (Candidate) -> String,
        numberOf: (Candidate) -> Int?
    ) -> Candidate? {
        let target = words(name)
        guard !target.isEmpty else { return nil }
        let sortedTarget = target.sorted()

        let exact = candidates.filter { words(nameOf($0)).sorted() == sortedTarget }
        if exact.count == 1 { return exact[0] }
        if !exact.isEmpty {
            guard let number else { return nil }
            let numbered = exact.filter { numberOf($0) == number }
            return numbered.count == 1 ? numbered[0] : nil
        }

        guard let number else { return nil }
        let loose = candidates.filter { candidate in
            numberOf(candidate) == number && looselyMatch(target, words(nameOf(candidate)))
        }
        return loose.count == 1 ? loose[0] : nil
    }

    /// The same surname, or one name's words all in the other's.
    static func looselyMatch(_ a: [String], _ b: [String]) -> Bool {
        guard let lastA = a.last, let lastB = b.last else { return false }
        if lastA == lastB { return true }
        let setA = Set(a)
        let setB = Set(b)
        return setA.isSubset(of: setB) || setB.isSubset(of: setA)
    }
}

// MARK: - Images

/// Loads FotMob and TheSportsDB photos, keeping them decoded in memory and
/// their bytes in a URL cache. Only `images.fotmob.com` and TheSportsDB's
/// hosts are fetched, over HTTPS. A photo the host has not got — FotMob's
/// 403, a 404, a body that is not an image — is `nil`, and is not asked for
/// again this launch; a failed download is `nil` and may be.
actor SoccerPhotoImageLoader {
    static let shared = SoccerPhotoImageLoader()

    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    /// A session with a disk cache, named as Safari on iOS: FotMob refuses
    /// a request without a User-Agent.
    nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": FotMob.userAgent]
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 48 * 1024 * 1024)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let transport: any HTTPTransport
    /// `false` keeps the loader off the network: fixture launches.
    private let enabled: Bool

    /// Downloads in progress, by URL, shared by every caller of that URL.
    private var loads: [URL: Task<(image: UIImage?, missing: Bool), Never>] = [:]
    /// Photos the host answered it has not got, this launch.
    private var missing: Set<URL> = []

    init(
        transport: any HTTPTransport = SoccerPhotoImageLoader.session,
        enabled: Bool = !HTTPClient.servesFixtures
    ) {
        self.transport = transport
        self.enabled = enabled
    }

    /// Whether `url` is one this loader fetches: HTTPS, on FotMob's image
    /// host or TheSportsDB's.
    nonisolated static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == FotMob.imageHost || TheSportsDB.isImageHost(host)
    }

    func image(for url: URL) async -> UIImage? {
        guard enabled, Self.allows(url), !missing.contains(url) else { return nil }
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let existing = loads[url] { return await existing.value.image }

        let task = Task<(image: UIImage?, missing: Bool), Never> { [transport] in
            do {
                let (data, response) = try await transport.load(url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return (nil, true)
                }
                guard let image = UIImage(data: data) else { return (nil, true) }
                return (image, false)
            } catch {
                logger.debug("Soccer photo failed: \(error.localizedDescription)")
                return (nil, false)
            }
        }
        loads[url] = task
        let outcome = await task.value
        if let image = outcome.image { memory.setObject(image, forKey: url as NSURL) }
        if outcome.missing { missing.insert(url) }
        loads[url] = nil
        return outcome.image
    }
}
