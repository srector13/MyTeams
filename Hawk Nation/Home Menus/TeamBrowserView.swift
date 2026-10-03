//
//  TeamBrowserView.swift
//  myTeams
//
//  Created by Stephen Rector on 9/27/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

// MARK: - Remote search

/// ESPN's search, the fallback for queries no loaded catalog matches. Local
/// matching (`TeamSearch.matches`) lives beside `TeamRef`, shared with the
/// widget.
extension TeamSearch {
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
/// "Pick your teams" onboarding sheet. Leads to the Alerts settings
/// (`AlertsSettingsView`).
struct TeamBrowserView: View {
    var title = "Teams"

    @Environment(\.dismiss) private var dismiss

    @State private var league: LeagueID = LeagueID.browsable[0].league
    @State private var catalogs: [LeagueID: [TeamRef]] = [:]
    @State private var myTeams: [TeamRef] = []
    @State private var query = ""
    @State private var remoteHits: [TeamRef] = []
    @State private var isSearchingRemotely = false

    /// A row's crest, which scales with the team name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 24

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
                    Section {
                        NavigationLink {
                            AlertsSettingsView()
                        } label: {
                            Label("Alerts", systemImage: "bell.badge")
                        }
                        .accessibilityLabel("Alerts")
                        .accessibilityHint("Choose which teams send game alerts, and allow notifications.")
                        .accessibilityIdentifier("teamBrowser.alerts")
                    }

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
                            .onMove { moveMyTeams(from: $0, to: $1) }
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
            // A bar, not an inset: the list scrolls beneath the chips and
            // the scroll-edge effect runs under both them and the nav bar,
            // one chrome region rather than a second opaque strip (B-1).
            .safeAreaBar(edge: .top, spacing: 0) {
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
                    // Following applies as it's tapped, so this confirms
                    // the picks: the system's glass checkmark (X-8).
                    Button(role: .confirm) {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .accessibilityIdentifier("teamBrowser.done")
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
        // Full height, as the browser and as onboarding: a searchable list
        // of every league's teams has no useful partial height (X-9).
        .presentationDetents([.large])
    }

    // MARK: Pieces

    /// The league chips: glass buttons, the chosen league's prominent, in one
    /// container so they share a sampling pass (B-1, §5.2). They're the only
    /// glass in this strip.
    private var leagueChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(LeagueID.browsable) { item in
                        leagueChip(item)
                    }
                }
                // Room for the interactive glass to swell inside the scroll
                // view's clip.
                .padding(.horizontal)
                .padding(.vertical, Theme.Spacing.s)
            }
        }
    }

    @ViewBuilder
    private func leagueChip(_ item: BrowsableLeague) -> some View {
        let selected = league == item.league
        let chip = Button {
            league = item.league
        } label: {
            Text(item.label)
                .font(.subheadline.weight(.semibold))
        }
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("teamBrowser.league.\(item.label)")

        if selected {
            chip
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
        } else {
            chip
                .buttonStyle(.glass)
        }
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
            // New favorites want alerts (`FavoriteTeam.notify`), so the
            // first follow is where the reader is asked for them.
            if !followed {
                Task { await ScoreAlertsPermissions.requestIfNeeded() }
            }
        } label: {
            HStack(spacing: 12) {
                TeamLogo(team: team, size: crestSize)
                    .frame(width: crestSize, height: crestSize)

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

                // Hierarchical, and replaced rather than swapped, so
                // following reads as one symbol changing state (B-2).
                Image(systemName: followed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(followed ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    // The store changes outside any animation; the replace
                    // effect needs one to play.
                    .animation(.snappy, value: followed)
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
