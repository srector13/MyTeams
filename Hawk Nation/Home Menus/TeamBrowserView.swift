//
//  TeamBrowserView.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

// MARK: - Leagues

/// A league offered in the picker's chip row.
struct BrowsableLeague: Identifiable, Hashable, Sendable {
    /// The chip and badge text, e.g. `"NCAAF"`.
    let label: String
    let league: LeagueID

    var id: LeagueID { league }
}

extension LeagueID {
    /// The leagues the picker lists, in chip order.
    static let browsable: [BrowsableLeague] = [
        BrowsableLeague(label: "NFL", league: .nfl),
        BrowsableLeague(label: "NBA", league: LeagueID(sport: "basketball", league: "nba")),
        BrowsableLeague(label: "MLB", league: .mlb),
        BrowsableLeague(label: "NHL", league: LeagueID(sport: "hockey", league: "nhl")),
        BrowsableLeague(label: "MLS", league: .mls),
        BrowsableLeague(label: "WNBA", league: LeagueID(sport: "basketball", league: "wnba")),
        BrowsableLeague(label: "NCAAF", league: LeagueID(sport: "football", league: "college-football")),
        BrowsableLeague(label: "NCAAM", league: .mensCollegeBasketball),
        BrowsableLeague(label: "NCAAW", league: LeagueID(sport: "basketball", league: "womens-college-basketball")),
        BrowsableLeague(label: "EPL", league: LeagueID(sport: "soccer", league: "eng.1")),
    ]

    /// The short label a team row's badge shows, e.g. `"NFL"`. Leagues the
    /// picker does not list show their league path component, uppercased.
    var badge: String {
        Self.browsable.first { $0.league == self }?.label ?? league.uppercased()
    }
}

// MARK: - Search

/// Matching teams against a search query, and ESPN's search as a fallback.
enum TeamSearch {
    /// `text` lowercased and without diacritics, so "malmo" finds "Malmö".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The names a team can be found by: display name, short name,
    /// abbreviation, location, and the nickname (the display name after its
    /// location — `TeamRef` keeps no separate nickname).
    static func searchableFields(of team: TeamRef) -> [String] {
        var fields = [team.displayName, team.shortName, team.abbreviation, team.location]
        if !team.location.isEmpty, team.displayName.hasPrefix(team.location) {
            let nickname = team.displayName.dropFirst(team.location.count).trimmingCharacters(in: .whitespaces)
            if !nickname.isEmpty { fields.append(nickname) }
        }
        return fields.filter { !$0.isEmpty }
    }

    /// Whether any of the team's names contains the query, ignoring case and
    /// diacritics. An empty query matches every team.
    static func matches(_ team: TeamRef, query: String) -> Bool {
        let folded = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty else { return true }
        return searchableFields(of: team).contains { fold($0).contains(folded) }
    }

    /// ESPN's site search, limited to ten results.
    static func searchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://site.web.api.espn.com/apis/search/v2")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "region", value: "us"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        return components?.url
    }

    /// Searches ESPN for teams. Returns `[]` on any failure.
    static func remoteTeams(matching query: String, client: HTTPClient = .shared) async -> [TeamRef] {
        guard let url = searchURL(query: query),
              let document = await client.fetch(url).document
        else { return [] }
        return parseSearchResults(document)
    }

    /// Reads the team hits out of an ESPN search document.
    ///
    /// The search API is undocumented and its shape has changed before
    /// (roadmap §5.2), so this reads defensively and drops anything it cannot
    /// place: hits are `results[].contents[]` of a result whose `type` is
    /// `"team"`; each needs a `sport`, a `defaultLeagueSlug` and a team id,
    /// taken from `uid` (`"s:20~l:28~t:12"`) or else `id`. A document of any
    /// other shape yields `[]`.
    static func parseSearchResults(_ document: JSON) -> [TeamRef] {
        var seen: Set<TeamRef.ID> = []
        var teams: [TeamRef] = []
        for result in document["results"].arrayValue where result["type"].stringValue == "team" {
            for hit in result["contents"].arrayValue {
                guard let team = parseSearchHit(hit), seen.insert(team.id).inserted else { continue }
                teams.append(team)
            }
        }
        return teams
    }

    private static func parseSearchHit(_ hit: JSON) -> TeamRef? {
        let sport = hit["sport"].stringValue
        let slug = hit["defaultLeagueSlug"].stringValue
        let uidTeam = hit["uid"].stringValue
            .split(separator: "~")
            .first { $0.hasPrefix("t:") }
            .map { String($0.dropFirst(2)) }
        let espnID = uidTeam ?? hit["id"].stringValue
        let name = hit["displayName"].stringValue
        guard !sport.isEmpty, !slug.isEmpty, !espnID.isEmpty, !name.isEmpty,
              espnID.allSatisfy(\.isNumber),
              let league = LeagueID(path: "\(sport)/\(slug)")
        else { return nil }

        let logo = hit["image", "default"].string.flatMap(URL.init(string:))
        return TeamRef(
            league: league,
            espnID: espnID,
            displayName: name,
            shortName: hit["shortDisplayName"].string ?? name,
            abbreviation: hit["abbreviation"].stringValue,
            location: hit["location"].stringValue,
            colorHex: "",
            alternateColorHex: "",
            logoURL: logo,
            logoDarkURL: nil,
            logoAsset: nil
        )
    }
}

// MARK: - Browser

/// The team picker: every team in a league, searchable, with the reader's
/// own teams pinned at the top for reordering and removal.
///
/// Opened from the crest bar's "+" button and, on a fresh install, as the
/// "Pick your teams" onboarding sheet.
struct TeamBrowserView: View {
    var title = "Teams"

    @Environment(\.dismiss) private var dismiss

    @State private var league: LeagueID = LeagueID.browsable[0].league
    @State private var catalogs: [LeagueID: [TeamRef]] = [:]
    @State private var myTeams: [TeamRef] = []
    @State private var query = ""
    @State private var remoteHits: [TeamRef] = []
    @State private var isSearchingRemotely = false

    private var store: FavoritesStore { .shared }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The chosen league's teams, alphabetical by location.
    private var leagueTeams: [TeamRef] {
        (catalogs[league] ?? []).sorted {
            ($0.location, $0.displayName) < ($1.location, $1.displayName)
        }
    }

    /// Every loaded league's teams that match the query, chosen league first.
    private var localMatches: [TeamRef] {
        let ordered = [league] + catalogs.keys.filter { $0 != league }.sorted { $0.path < $1.path }
        return ordered
            .flatMap { catalogs[$0] ?? [] }
            .filter { TeamSearch.matches($0, query: query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResults
                } else {
                    if !myTeams.isEmpty {
                        Section("My Teams") {
                            ForEach(myTeams) { team in
                                row(team)
                                    .swipeActions {
                                        Button("Remove", role: .destructive) {
                                            store.remove(team.id)
                                        }
                                    }
                            }
                            .onMove(perform: moveMyTeams)
                        }
                    }

                    // TODO(P3): conference sections for college leagues. The
                    // teams feed carries no group data and `TeamRef` keeps
                    // none, so college lists are one alphabetical section.
                    Section(league.badge) {
                        if catalogs[league] == nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(leagueTeams) { team in
                            row(team)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                leagueChips
            }
            .searchable(text: $query, prompt: "Search teams")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: league) {
                await load(league)
            }
            .task(id: store.teamIDs) {
                myTeams = await store.teamRefs()
            }
            .task(id: query) {
                await searchRemotelyIfNeeded()
            }
        }
    }

    // MARK: Pieces

    private var leagueChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LeagueID.browsable) { item in
                    Button {
                        league = item.league
                    } label: {
                        Text(item.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .foregroundStyle(league == item.league ? Color.white : Color.primary)
                            .background(league == item.league ? Color.accentColor : Color.secondary.opacity(0.15))
                            .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var searchResults: some View {
        let local = localMatches
        if !local.isEmpty {
            Section("Results") {
                ForEach(local) { team in
                    row(team)
                }
            }
        } else if !remoteHits.isEmpty {
            Section("From ESPN") {
                ForEach(remoteHits) { team in
                    row(team)
                }
            }
        } else if isSearchingRemotely {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private func row(_ team: TeamRef) -> some View {
        let followed = store.isFavorite(team.id)
        return Button {
            store.toggle(team)
        } label: {
            HStack(spacing: 12) {
                TeamLogo(team: team, size: 24)
                    .frame(width: 24, height: 24)

                Text(team.displayName)
                    .foregroundStyle(.primary)

                // Always shown: "Kansas City" is four teams in four leagues.
                Text(team.league.badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(.capsule)

                Spacer(minLength: 0)

                Image(systemName: followed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(followed ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
            }
        }
        .accessibilityLabel("\(team.displayName), \(team.league.badge)")
        .accessibilityAddTraits(followed ? .isSelected : [])
        .task {
            await RemoteTeamCatalog.shared.prefetchLogos(for: [team])
        }
    }

    // MARK: Actions

    private func load(_ league: LeagueID) async {
        guard catalogs[league] == nil else { return }
        let teams = await RemoteTeamCatalog.shared.teams(for: league)
        catalogs[league] = teams
    }

    /// Loads the pro leagues for search, then asks ESPN once the query has
    /// settled for 400 ms without matching anything loaded.
    private func searchRemotelyIfNeeded() async {
        remoteHits = []
        guard isSearching else { return }
        for item in LeagueID.browsable where !item.league.isCollege {
            await load(item.league)
        }
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }
        guard localMatches.isEmpty else { return }
        isSearchingRemotely = true
        defer { isSearchingRemotely = false }
        let hits = await TeamSearch.remoteTeams(matching: query)
        guard !Task.isCancelled else { return }
        remoteHits = hits
    }

    /// Applies a move in the My Teams section to the store. Favorites the
    /// catalog could not resolve are not shown, so rows are mapped to the
    /// store's positions by id.
    private func moveMyTeams(from source: IndexSet, to destination: Int) {
        let ids = store.teamIDs
        let storeSource = IndexSet(source.compactMap { ids.firstIndex(of: myTeams[$0].id) })
        let storeDestination = destination < myTeams.count
            ? ids.firstIndex(of: myTeams[destination].id) ?? ids.count
            : ids.count
        myTeams.move(fromOffsets: source, toOffset: destination)
        store.move(from: storeSource, to: storeDestination)
    }
}

#Preview {
    TeamBrowserView()
}
