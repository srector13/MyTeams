//
//  Standings.swift
//  myTeams
//
//  Created by Stephen Rector on 9/28/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// What a league's standings rank teams by, which decides the columns the
/// Standings section draws.
enum StandingsKind: Sendable, Hashable {
    /// A soccer table: wins, draws and losses, ranked by points, with the
    /// goal difference beside them.
    case pointsTable
    /// A US-style table ranked by record: wins and losses (basketball,
    /// football), or wins, losses and overtime losses with points (hockey),
    /// with games behind the leader.
    case records
    /// A poll — the AP Top 25 — standing in for a college tree with no table
    /// yet: a rank and a record, nothing else.
    case rankings
}

/// One team's row in a standings table.
struct StandingsEntry: Identifiable, Hashable, Sendable {
    /// The team's ESPN id, which the followed team is matched on.
    let teamID: String
    /// The full name, e.g. `"Kansas Jayhawks"`.
    let name: String
    /// The name the table's narrow column shows, e.g. `"Kansas"`.
    let shortName: String
    let abbreviation: String
    let logoURL: URL?
    let record: Record
    /// The team's place in its table: a soccer table's position, the
    /// playoff seed, or the poll rank. `nil` when the feed ranks nobody yet
    /// (a preseason table lists every seed as 0).
    let rank: Int?
    /// Games behind the leader, as the feed writes it (`"-"` for the leader,
    /// `"2.5"`), or empty where the league keeps none (soccer).
    let gamesBehind: String
    /// The record against the team's own conference, `"8-10"`, or empty.
    let conferenceRecord: String
    /// Goal difference, signed as the feed writes it (`"+8"`), soccer only.
    let goalDifference: String
    /// The current run, `"W4"`, or empty.
    let streak: String
    /// What the team's place qualifies it for — `"Champions League"`,
    /// `"Relegation"` — as a soccer table annotates it, or empty.
    let note: String
    /// The feed's colour for `note`, six hex digits, or empty.
    let noteColorHex: String
    /// The playoff clincher mark, `"x"`, `"e"`, `"*"`, or empty.
    let clincher: String
    /// What the feed says `clincher` means, `"Clinched Playoff Berth"`, or
    /// empty where it says nothing. The standings legend's words for the
    /// mark (`StandingsClincher.legend(for:)`).
    var clincherNote: String = ""

    var id: String { teamID }
}

/// One table: a conference, a division, or a soccer league's whole table.
struct StandingsGroup: Identifiable, Hashable, Sendable {
    let id: String
    /// The table's name, e.g. `"Eastern Conference"`, `"Sun Belt - East"`,
    /// `"2026-27 English Premier League"`.
    let name: String
    let abbreviation: String
    /// The rows, first place first.
    let entries: [StandingsEntry]
    /// The feed's short name for the table, `"Big 12"` for `"Big 12
    /// Conference"`, or empty where it gives none. See `shortTitle`.
    var shortName: String = ""
}

/// A league's standings: every table in its tree, in feed order.
struct Standings: Hashable, Sendable {
    let kind: StandingsKind
    /// The season the tables are for, e.g. `"2026-27"` — which is not
    /// always the season asked for: college basketball's tree keeps last
    /// season's final tables until the new one tips off.
    let seasonDisplayName: String
    let groups: [StandingsGroup]

    /// Standings with no tables, or no rows in any.
    static let empty = Standings(kind: .records, seasonDisplayName: "", groups: [])

    var isEmpty: Bool { groups.allSatisfy(\.entries.isEmpty) }

    /// The table a team is in.
    func group(containing teamID: String) -> StandingsGroup? {
        groups.first { group in group.entries.contains { $0.teamID == teamID } }
    }

    /// A team's row, in whichever table holds it.
    func entry(for teamID: String) -> StandingsEntry? {
        group(containing: teamID)?.entries.first { $0.teamID == teamID }
    }

    /// The table a team page's Standings card shows: the team's own, else
    /// the first with rows — a poll the team is not ranked in, say.
    func teamPageGroup(for teamID: String) -> StandingsGroup? {
        group(containing: teamID) ?? groups.first { !$0.entries.isEmpty }
    }
}

// MARK: - A team page's snapshot

extension StandingsGroup {
    /// The most rows a team page's Standings card shows a table whole: a
    /// division (four NFL teams, five in an MLB or NHL division) or a
    /// small conference. A longer table shows `snapshotReach` places
    /// either side of the team instead (T5), and the rest is a tap away.
    static let wholeTableLimit = 8

    /// How many places either side of the team a long table shows.
    static let snapshotReach = 2

    /// The rows, by index into `entries`, a team page's Standings card
    /// shows: the whole table when it is no longer than `wholeTableLimit`;
    /// else `snapshotReach` places either side of `teamID`, slid to keep
    /// as many rows when the team is near the top or the foot; else, for
    /// a table without the team, its top rows.
    func snapshotRows(around teamID: String) -> Range<Int> {
        guard entries.count > Self.wholeTableLimit else { return entries.indices }
        let count = Self.snapshotReach * 2 + 1
        guard let index = entries.firstIndex(where: { $0.teamID == teamID }) else {
            return 0..<count
        }
        let upper = min(entries.count, max(index - Self.snapshotReach, 0) + count)
        return max(upper - count, 0)..<upper
    }

    /// Whether `snapshotRows(around:)` leaves rows out.
    func isSnapshot(around teamID: String) -> Bool {
        snapshotRows(around: teamID).count < entries.count
    }

    /// The table's name short enough for a team page's header line beside
    /// the record (T1): the league's own name for a soccer table (as
    /// `title(kind:leagueName:)`); the feed's short name where it gives
    /// one; else the name with the words leagues are known by shortened,
    /// `"American League"` to `"AL"`, `"Western Conference"` to `"West"`,
    /// `"Big 12 Conference"` to `"Big 12"`. A division keeps its name,
    /// `"AFC West"`.
    func shortTitle(kind: StandingsKind, leagueName: String?) -> String {
        if kind == .pointsTable { return title(kind: kind, leagueName: leagueName) }
        let short = shortName.trimmingCharacters(in: .whitespaces)
        if !short.isEmpty, short.count < name.count { return short }
        return Self.abbreviated(name)
    }

    /// The names leagues and conferences go by, and their short forms.
    private static let knownShortNames: [String: String] = [
        "American League": "AL",
        "National League": "NL",
        "American Football Conference": "AFC",
        "National Football Conference": "NFC",
        "Eastern Conference": "East",
        "Western Conference": "West",
    ]

    /// `name` as `shortTitle` shortens it without a short name from the
    /// feed: a known name, a division of one (`"American League East"` to
    /// `"AL East"`), or a conference without the word.
    static func abbreviated(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let known = knownShortNames[trimmed] { return known }
        for (long, short) in knownShortNames where trimmed.hasPrefix(long + " ") {
            return short + trimmed.dropFirst(long.count)
        }
        let suffix = " Conference"
        if trimmed.hasSuffix(suffix), trimmed.count > suffix.count {
            return String(trimmed.dropLast(suffix.count))
        }
        return trimmed
    }

    /// Whether `shortTitle` names a division of a league's conference,
    /// `"AFC West"` or `"AL Central"`: the conference's letters and a point
    /// of the compass. The header line reads `"1st AFC West"` for one, and
    /// `"13th in AL"` or `"4th in Mountain West"` for anything else.
    static func isDivisionTitle(_ title: String) -> Bool {
        let words = title.split(separator: " ").map(String.init)
        guard words.count == 2 else { return false }
        return ["AFC", "NFC", "AL", "NL"].contains(words[0])
            && ["East", "West", "North", "South", "Central"].contains(words[1])
    }
}

/// The clincher marks in a standings table (`StandingsEntry.clincher`) and
/// the legend beneath it that says what they mean (T5).
enum StandingsClincher {
    /// The words for the marks every league in the feed uses alike, for a
    /// row whose feed doesn't say (`StandingsEntry.clincherNote`). Any other
    /// mark means different things in different leagues, so it is left
    /// out of the legend rather than guessed.
    static let commonNotes: [String: String] = [
        "x": "Clinched Playoff Berth",
        "e": "Eliminated From Playoffs",
    ]

    /// `"x Clinched Playoff Berth"`, one per mark in `entries`, in the order
    /// the rows first show it; marks with no words for them are skipped.
    static func legend(for entries: some Sequence<StandingsEntry>) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for entry in entries where !entry.clincher.isEmpty {
            guard seen.insert(entry.clincher).inserted else { continue }
            let note = entry.clincherNote.isEmpty ? commonNotes[entry.clincher] : entry.clincherNote
            if let note, !note.isEmpty {
                lines.append("\(entry.clincher) \(note)")
            }
        }
        return lines
    }
}

// MARK: - Parsing

/// Reads a standings document from the `/apis/v2` standings endpoint
/// (`LeagueID.standingsURL`), or — when it holds no table — a rankings
/// document (`parseRankings`).
///
/// The document is a tree: the root is the league or college division and
/// holds no table of its own; its `children` are conferences, each with a
/// `standings.entries` table, or with `children` of their own (college
/// football's Sun Belt splits into East and West). Every node with a table
/// becomes one `StandingsGroup`, walked depth first so tables keep the
/// feed's order. See FIXTURES.md, "Standings tree shape".
///
/// Each row's stats are read by name, never by position; their order
/// differs by league. The row's record takes the league's sport's shape
/// (`SportKind.standingsRecordFormat`).
func parseStandings(from json: JSON, league: LeagueID) -> Standings {
    let format = league.descriptor.kind.standingsRecordFormat
    var groups: [StandingsGroup] = []
    var seasonDisplayName = ""

    func walk(_ node: JSON) {
        let table = node["standings"]
        if table["entries"].array != nil {
            if seasonDisplayName.isEmpty {
                seasonDisplayName = table["seasonDisplayName"].stringValue
            }
            let entries = table["entries"].arrayValue.compactMap { parseStandingsEntry($0, format: format) }
            let id = node["id"].stringValue
            groups.append(StandingsGroup(
                id: id.isEmpty ? node["name"].stringValue : id,
                name: node["name"].stringValue,
                abbreviation: node["abbreviation"].stringValue,
                entries: rankedInOrder(entries),
                shortName: node["shortName"].stringValue
            ))
        }
        for (_, child) in node["children"] {
            walk(child)
        }
    }
    walk(json)

    let standings = Standings(
        kind: format == .winDrawLossPoints ? .pointsTable : .records,
        seasonDisplayName: seasonDisplayName.isEmpty ? json["season"]["displayName"].stringValue : seasonDisplayName,
        groups: groups
    )
    if standings.isEmpty, json["rankings"].array != nil {
        return parseRankings(from: json, league: league)
    }
    return standings
}

/// Reads one row of a standings table. `nil` for a row that names no team.
private func parseStandingsEntry(_ entry: JSON, format: Record.Format) -> StandingsEntry? {
    let team = entry["team"]
    let teamID = team["id"].stringValue
    guard !teamID.isEmpty else { return nil }

    let stats = StandingsStats(entry["stats"])

    // The overall record as a summary string: "4-0" (college football),
    // "5-0-0" (a soccer table's W-D-L), "0-0-0, 0 PTS" (hockey's W-L-OTL).
    // College football has no `losses` stat, so its losses come from here.
    let summary = parseRecordSummary(stats.display("total"))
    func column(_ index: Int) -> Int? {
        summary.indices.contains(index) ? summary[index] : nil
    }

    let wins = stats.int("wins") ?? column(0) ?? 0
    let record: Record = switch format {
    case .winDrawLossPoints:
        Record(
            wins: wins,
            losses: stats.int("losses") ?? column(2) ?? 0,
            ties: stats.int("ties") ?? column(1) ?? 0,
            points: stats.int("points"),
            format: format
        )
    case .winLossOvertimeLoss:
        Record(
            wins: wins,
            losses: stats.int("losses") ?? column(1) ?? 0,
            // Both names carry the same count; `otlosses` is the one the
            // table's OTL column is drawn from.
            overtimeLosses: stats.int("otlosses") ?? stats.int("overtimelosses") ?? column(2) ?? 0,
            points: stats.int("points"),
            format: format
        )
    case .winLoss, .winLossTie:
        // `points` here is not a points total (the WNBA's is games over
        // .500), so it is left out.
        Record(
            wins: wins,
            losses: stats.int("losses") ?? column(1) ?? 0,
            ties: stats.int("ties") ?? column(2) ?? 0,
            format: format
        )
    }

    // Soccer ranks by table position; everyone else by playoff seed. A
    // preseason table seeds every team 0, which is no rank at all.
    let rank = (stats.int("rank") ?? stats.int("playoffseed")).flatMap { $0 > 0 ? $0 : nil }

    let note = entry["note"]
    return StandingsEntry(
        teamID: teamID,
        name: team["displayName"].stringValue,
        shortName: team["shortDisplayName"].stringValue,
        abbreviation: team["abbreviation"].stringValue,
        logoURL: ESPNLogos.select(team["logos"]).default,
        record: record,
        rank: rank,
        gamesBehind: format == .winDrawLossPoints ? "" : stats.display("gamesbehind"),
        conferenceRecord: stats.display("vsconf"),
        goalDifference: format == .winDrawLossPoints ? stats.display("pointdifferential") : "",
        streak: stats.display("streak"),
        note: note["description"].stringValue,
        noteColorHex: note["color"].stringValue.replacingOccurrences(of: "#", with: ""),
        clincher: stats.display("clincher"),
        clincherNote: stats.description("clincher")
    )
}

/// Rows in rank order when every row has a rank, else in the feed's order.
///
/// The feeds do not agree on order: soccer tables and professional
/// conferences come first place first, but college basketball's conference
/// tables come in reverse seed order. A preseason table ranks nobody and
/// lists teams alphabetically, which is kept.
private func rankedInOrder(_ entries: [StandingsEntry]) -> [StandingsEntry] {
    guard !entries.isEmpty, entries.allSatisfy({ $0.rank != nil }) else { return entries }
    return entries.enumerated()
        .sorted { ($0.element.rank ?? 0, $0.offset) < ($1.element.rank ?? 0, $1.offset) }
        .map(\.element)
}

/// A standings row's `stats`, looked up by name.
///
/// Each stat is keyed by its `type`, which is unique within a row. `name`
/// is not: college rows repeat `wins`, `gamesBehind` and the rest once per
/// split (home, away, conference), with the split only in the `type`
/// (`homerecord_wins`). A lookup falls back to the first stat so named.
private struct StandingsStats {
    private var byType: [String: JSON] = [:]
    private var byName: [String: JSON] = [:]

    init(_ stats: JSON) {
        for (_, stat) in stats {
            let type = stat["type"].stringValue.lowercased()
            if !type.isEmpty, byType[type] == nil { byType[type] = stat }
            let name = stat["name"].stringValue.lowercased()
            if !name.isEmpty, byName[name] == nil { byName[name] = stat }
        }
    }

    private func stat(_ key: String) -> JSON? {
        byType[key] ?? byName[key]
    }

    /// The stat as a whole number: its numeric `value`, else its
    /// `displayValue` read leniently (`"+8"` is 8). A `value` outside `Int`'s
    /// range is passed over rather than converted, which would trap.
    func int(_ key: String) -> Int? {
        guard let stat = stat(key) else { return nil }
        if case .number(let value) = stat["value"], value.isFinite,
           let int = Int(exactly: value.rounded(.towardZero)) {
            return int
        }
        return Int(stat["displayValue"].stringValue.replacingOccurrences(of: "+", with: ""))
    }

    /// The stat as the feed displays it, or empty.
    func display(_ key: String) -> String {
        stat(key)?["displayValue"].stringValue ?? ""
    }

    /// What the feed says the stat's value means, or empty.
    func description(_ key: String) -> String {
        stat(key)?["description"].stringValue ?? ""
    }
}

/// The numbers of a record summary, in order: `"4-0"` is `[4, 0]`,
/// `"0-0-0, 0 PTS"` is `[0, 0, 0]`. Anything after a comma is dropped; an
/// unreadable summary is `[]`.
func parseRecordSummary(_ summary: String) -> [Int] {
    let record = summary.split(separator: ",", maxSplits: 1).first ?? ""
    let parts = record.split(separator: "-").map { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return [] }
    return parts.compactMap { $0 }
}

/// Reads a rankings document (`LeagueID.rankingsURL`) as standings of one
/// group: the AP poll if the document has one, else its first poll with any
/// teams. Each rank carries `current`, a `team` and a `recordSummary`.
///
/// The fallback for a college standings tree with no table in it, and the
/// source of the poll ranks college team names are prefixed with
/// (`PollRanks`). Tested against the live FBS and women's captures
/// (`ncaaf_rankings`, `ncaaw_rankings`; FIXTURES.md).
func parseRankings(from json: JSON, league: LeagueID) -> Standings {
    let polls = json["rankings"].arrayValue.filter { !$0["ranks"].arrayValue.isEmpty }
    guard let poll = polls.first(where: { $0["type"].stringValue == "ap" }) ?? polls.first else {
        return .empty
    }
    let format = league.descriptor.kind.scheduleRecordFormat

    let entries: [StandingsEntry] = poll["ranks"].arrayValue.compactMap { rank in
        let team = rank["team"]
        let teamID = team["id"].stringValue
        guard !teamID.isEmpty else { return nil }
        let location = team["location"].stringValue
        let summary = parseRecordSummary(rank["recordSummary"].stringValue)
        let current = rank["current"].intValue
        return StandingsEntry(
            teamID: teamID,
            name: [location, team["name"].stringValue].filter { !$0.isEmpty }.joined(separator: " "),
            shortName: team["nickname"].string ?? location,
            abbreviation: team["abbreviation"].stringValue,
            logoURL: ESPNLogos.select(team["logos"]).default ?? URL(string: team["logo"].stringValue),
            record: Record(
                wins: summary.first ?? 0,
                losses: summary.count > 1 ? summary[1] : 0,
                ties: summary.count > 2 ? summary[2] : 0,
                format: format
            ),
            rank: current > 0 ? current : nil,
            gamesBehind: "",
            conferenceRecord: "",
            goalDifference: "",
            streak: "",
            note: "",
            noteColorHex: "",
            clincher: ""
        )
    }

    let name = poll["name"].stringValue
    return Standings(
        kind: .rankings,
        seasonDisplayName: poll["season"]["displayName"].stringValue,
        groups: [StandingsGroup(
            id: poll["id"].stringValue.isEmpty ? name : poll["id"].stringValue,
            name: name,
            abbreviation: poll["shortName"].stringValue,
            entries: rankedInOrder(entries)
        )]
    )
}

// MARK: - Poll ranks

/// A college league's poll, as the ranks its teams' names are prefixed
/// with: `"#7 Kansas"` on the team page's header and in the standings rows
/// (R-5).
///
/// Read from the rankings document by `parseRankings`, so it is the same
/// poll the standings fall back to: the AP poll, else the first poll with
/// any teams.
struct PollRanks: Hashable, Sendable {
    /// The poll's name, `"AP Top 25"`, or empty.
    let pollName: String
    /// Each ranked team's place, by ESPN team id.
    let ranks: [String: Int]

    /// No poll: no team ranked.
    static let empty = PollRanks(pollName: "", ranks: [:])

    init(pollName: String, ranks: [String: Int]) {
        self.pollName = pollName
        self.ranks = ranks
    }

    /// The ranks in a poll `parseRankings` read. Standings of any other kind
    /// rank by table, not poll, and give none.
    init(_ standings: Standings) {
        let poll = standings.kind == .rankings ? standings.groups.first : nil
        var ranks: [String: Int] = [:]
        for entry in poll?.entries ?? [] {
            if let rank = entry.rank, ranks[entry.teamID] == nil {
                ranks[entry.teamID] = rank
            }
        }
        self.init(pollName: poll?.name ?? "", ranks: ranks)
    }

    /// Reads a rankings document (`LeagueID.rankingsURL`).
    static func parse(from json: JSON, league: LeagueID) -> PollRanks {
        PollRanks(parseRankings(from: json, league: league))
    }

    var isEmpty: Bool { ranks.isEmpty }

    /// The team's place in the poll, or `nil` when it is unranked.
    func rank(of teamID: String) -> Int? {
        ranks[teamID]
    }

    /// `name` with the team's poll rank before it, `"#7 Kansas"`, or
    /// `name` unchanged for an unranked team.
    func prefixed(_ name: String, teamID: String) -> String {
        Self.prefixed(name, rank: rank(of: teamID))
    }

    /// `"#7 Kansas"` for a rank, else `name`.
    static func prefixed(_ name: String, rank: Int?) -> String {
        guard let badge = badge(rank: rank) else { return name }
        return "\(badge) \(name)"
    }

    /// `"#7"`, or `nil` for no rank (or a feed's 0, which ranks no one).
    static func badge(rank: Int?) -> String? {
        guard let rank, rank > 0 else { return nil }
        return "#\(rank)"
    }
}

/// Each college league's poll ranks, fetched once and kept for an hour —
/// polls change weekly — and shared by every view that prefixes a name.
///
/// A league that is not a college one is never asked for: it has no polls,
/// so its ranks are `.empty` without a request. A failed fetch is `.empty`
/// too, and is retried on the next ask rather than kept.
actor PollRankStore {
    static let shared = PollRankStore()

    /// How long a league's poll is served without asking again.
    static let timeToLive: TimeInterval = 60 * 60

    private let client: HTTPClient
    private let now: @Sendable () -> Date

    private var cached: [LeagueID: (fetchedAt: Date, ranks: PollRanks)] = [:]
    /// Loads in flight, so concurrent callers share one request.
    private var loads: [LeagueID: Task<PollRanks?, Never>] = [:]

    init(client: HTTPClient = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    /// The league's poll ranks, from the last hour's fetch or a new one.
    func ranks(for league: LeagueID) async -> PollRanks {
        guard league.isCollege else { return .empty }
        if let entry = cached[league], now().timeIntervalSince(entry.fetchedAt) < Self.timeToLive {
            return entry.ranks
        }
        if let existing = loads[league] {
            return await existing.value ?? .empty
        }
        let client = client
        let task = Task<PollRanks?, Never> {
            guard let document = await client.fetch(league.rankingsURL).document else { return nil }
            return PollRanks.parse(from: document, league: league)
        }
        loads[league] = task
        let ranks = await task.value
        loads[league] = nil
        if let ranks {
            cached[league] = (now(), ranks)
        }
        return ranks ?? .empty
    }
}

/// Each league's standings, fetched once and kept for an hour, shared by
/// every view that shows a team's place without its whole page loaded:
/// Home's team cards and standings snapshot. Concurrent callers share one
/// load; a failed one is retried on the next ask rather than kept.
actor StandingsStore {
    static let shared = StandingsStore()

    /// How long a league's standings are served without asking again.
    static let timeToLive: TimeInterval = 60 * 60

    private let load: @Sendable (LeagueID) async -> Standings?
    private let now: @Sendable () -> Date

    private var cached: [LeagueID: (fetchedAt: Date, standings: Standings)] = [:]
    /// Loads in flight, so concurrent callers share one request.
    private var loads: [LeagueID: Task<Standings?, Never>] = [:]

    init(
        load: @escaping @Sendable (LeagueID) async -> Standings? = { league in
            if case .success(let standings) = await downloadStandings(league: league) { return standings }
            return nil
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.load = load
        self.now = now
    }

    /// The league's standings, from the last hour's fetch or a new one;
    /// `nil` when the feed couldn't be read.
    func standings(for league: LeagueID) async -> Standings? {
        if let entry = cached[league], now().timeIntervalSince(entry.fetchedAt) < Self.timeToLive {
            return entry.standings
        }
        if let existing = loads[league] {
            return await existing.value
        }
        let load = load
        let task = Task<Standings?, Never> { await load(league) }
        loads[league] = task
        let standings = await task.value
        loads[league] = nil
        if let standings {
            cached[league] = (now(), standings)
        }
        return standings
    }
}

// MARK: - Loading

extension LeagueDescriptor {
    /// The season to ask the standings for at `date`, or `nil` to take the
    /// feed's own current season. See `SeasonNaming`.
    func standingsSeason(at date: Date) -> Int? {
        seasonNaming?.season(at: date)
    }
}

/// Loads a league's standings.
///
/// Asks for the season in progress by the league's `SeasonNaming`. Between
/// seasons that can be a season with no table yet, so an empty answer is
/// retried without a season, which gets whatever the feed calls current —
/// for college basketball in the autumn, last season's final tables. A
/// college league with still no table falls back to its polls
/// (`rankingsURL`, `parseRankings`).
///
/// Only the first request's failure is reported; the fallbacks are best
/// effort, and an empty result is `.success(.empty)`.
func downloadStandings(league: LeagueID, now: Date = Date()) async -> Result<Standings, NetworkError> {
    let client = HTTPClient.shared
    let season = league.descriptor.standingsSeason(at: now)

    let first = await client.fetch(league.standingsURL(season: season)).map(empty: Standings.empty) { json in
        parseStandings(from: json, league: league)
    }
    guard case .success(let standings) = first, standings.isEmpty else { return first }

    if season != nil,
       case .success(let current) = await client.fetch(league.standingsURL()).map(empty: Standings.empty, {
           parseStandings(from: $0, league: league)
       }),
       !current.isEmpty {
        return .success(current)
    }

    if league.isCollege,
       case .success(let polls) = await client.fetch(league.rankingsURL).map(empty: Standings.empty, {
           parseRankings(from: $0, league: league)
       }),
       !polls.isEmpty {
        return .success(polls)
    }
    return .success(.empty)
}
