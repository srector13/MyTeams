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

    /// Every catalog's teams that match the query, `current`'s first and the
    /// rest by league path, then grouped into clubs (`clubGroups(from:)`) so
    /// a club listed under its league and a cup is one result.
    static func localClubs(
        in catalogs: [LeagueID: [TeamRef]],
        query: String,
        current: LeagueID?
    ) -> [ClubGroup] {
        let rest = catalogs.keys.filter { $0 != current }.sorted { $0.path < $1.path }
        let ordered = (current.map { [$0] } ?? []) + rest
        let hits = ordered
            .flatMap { catalogs[$0] ?? [] }
            .filter { Self.matches($0, query: query) }
        return clubGroups(from: hits)
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

// MARK: - Recent searches

/// A team the reader followed from a search, and the query that found it.
/// The whole team is kept, so the row draws before any catalog loads.
struct RecentSearch: Codable, Hashable, Identifiable, Sendable {
    var query: String
    var team: TeamRef

    var id: TeamRef.ID { team.id }
}

/// The picker's recent searches (C-7): the last `limit` teams followed from
/// a search, newest first, each once, in this device's `UserDefaults`.
enum RecentSearches {
    static let key = "teamBrowser.recentSearches.v1"
    static let limit = 8

    /// The stored recent searches, newest first. Empty for none, or for
    /// unreadable data.
    static func load(from defaults: UserDefaults = .standard) -> [RecentSearch] {
        guard let data = defaults.data(forKey: key),
              let recents = try? JSONDecoder().decode([RecentSearch].self, from: data)
        else { return [] }
        return Array(recents.prefix(limit))
    }

    /// `recents` with `team`, found by `query`, moved or added to the front
    /// and the oldest past `limit` dropped. A blank query records nothing.
    static func recording(_ query: String, team: TeamRef, in recents: [RecentSearch]) -> [RecentSearch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recents }
        let rest = recents.filter { $0.id != team.id }
        return Array(([RecentSearch(query: trimmed, team: team)] + rest).prefix(limit))
    }

    /// Records a team followed from a search and returns the new list.
    @discardableResult
    static func record(_ query: String, team: TeamRef, defaults: UserDefaults = .standard) -> [RecentSearch] {
        let recents = recording(query, team: team, in: load(from: defaults))
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: key)
        }
        return recents
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Sports

/// How the picker names and draws a sport.
extension SportKind {
    /// The sport's name in the picker, e.g. `"Football"`.
    var browserTitle: String {
        switch self {
        case .football: "Football"
        case .basketball: "Basketball"
        case .baseball: "Baseball"
        case .soccer: "Soccer"
        case .hockey: "Hockey"
        case .other: "More Sports"
        }
    }

    /// The SF Symbol the picker draws beside the sport's name.
    var browserSymbol: String {
        switch self {
        case .football: "football.fill"
        case .basketball: "basketball.fill"
        case .baseball: "baseball.fill"
        case .soccer: "soccerball"
        case .hockey: "hockey.puck.fill"
        case .other: "sportscourt.fill"
        }
    }
}

/// One sport in the picker and the browsable leagues it plays, in catalog
/// order.
struct BrowsableSport: Identifiable, Hashable, Sendable {
    let kind: SportKind
    let leagues: [BrowsableLeague]

    var id: SportKind { kind }

    /// `LeagueID.browsable` grouped under each league's sport, sports in the
    /// order their first league is listed. A sport with no browsable league
    /// is not here.
    static let all: [BrowsableSport] = {
        var order: [SportKind] = []
        var leagues: [SportKind: [BrowsableLeague]] = [:]
        for item in LeagueID.browsable {
            let kind = item.league.descriptor.kind
            if leagues[kind] == nil { order.append(kind) }
            leagues[kind, default: []].append(item)
        }
        return order.map { BrowsableSport(kind: $0, leagues: leagues[$0] ?? []) }
    }()
}

// MARK: - Browser

/// The team picker: sports, then a sport's leagues, then every team in a
/// league, searchable throughout, with the reader's own teams pinned at the
/// top for reordering and removal.
///
/// Opened from Settings' "Add Teams" and "Manage Teams" rows (t_fa6748f4),
/// from the empty home screen's "Pick Your Teams", and, on a fresh install,
/// as the "Pick your teams" onboarding sheet. Alerts live in Settings (B-9).
///
/// With the search field focused and empty, the teams last followed from a
/// search are offered under "Recent" (`RecentSearches`, C-7).
struct TeamBrowserView: View {
    var title = "Teams"

    /// A screen pushed onto the picker's stack.
    enum Route: Hashable {
        case sport(SportKind)
        case league(LeagueID)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var path: [Route] = []
    @State private var catalogs: [LeagueID: [TeamRef]] = [:]
    @State private var myTeams: [TeamRef] = []
    @State private var query = ""
    @State private var remoteHits: [TeamRef] = []
    @State private var isSearchingRemotely = false
    /// Whether the search field is active, focused or not yet dismissed.
    @State private var isSearchPresented = false
    @State private var recents: [RecentSearch] = []

    /// A row's crest, which scales with the team name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 24

    /// The tile a sport or league row leads with, which scales with its
    /// title.
    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

    private var store: FavoritesStore { .shared }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The league on screen, if the reader has drilled down to one.
    private var currentLeague: LeagueID? {
        for route in path.reversed() {
            if case .league(let league) = route { return league }
        }
        return nil
    }

    /// `league`'s teams, alphabetical by location.
    private func teams(in league: LeagueID) -> [TeamRef] {
        (catalogs[league] ?? []).sorted {
            ($0.location, $0.displayName) < ($1.location, $1.displayName)
        }
    }

    /// Every loaded league's clubs that match the query, the league on
    /// screen first, each club once.
    private var localMatches: [ClubGroup] {
        TeamSearch.localClubs(in: catalogs, query: query, current: currentLeague)
    }

    var body: some View {
        NavigationStack(path: $path) {
            page(title, showsEditButton: true) {
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

                Section("Sports") {
                    ForEach(BrowsableSport.all) { sport in
                        NavigationLink(value: Route.sport(sport.kind)) {
                            sportRow(sport)
                        }
                        .accessibilityIdentifier("teamBrowser.sport.\(sport.kind.rawValue)")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sport(let kind):
                    leaguesPage(kind)
                case .league(let league):
                    teamsPage(league)
                }
            }
        }
        // On the stack rather than a page, so a search typed on any page,
        // and the reader's teams, outlive the push or pop that hides it.
        .task {
            recents = RecentSearches.load()
            // Every browsable league, for the rows' team counts and so
            // search finds teams in leagues not yet opened.
            for item in LeagueID.browsable {
                await load(item.league)
            }
        }
        // Again when a placeholder's team resolves late (A-4).
        .task(id: store.resolutionKey) {
            myTeams = await store.teamRefs()
        }
        .task(id: query) {
            await searchRemotelyIfNeeded()
        }
        // A search belongs to the page it was typed on.
        .onChange(of: path) {
            query = ""
        }
        // Full height, as the browser and as onboarding: a searchable list
        // of every league's teams has no useful partial height (X-9).
        .presentationDetents([.large])
    }

    // MARK: Pages

    /// One page of the picker: `content`, or the search results while there
    /// is a query, under the shared search field and Done button. With the
    /// field focused and still empty, recent searches come first.
    private func page<Content: View>(
        _ title: String,
        showsEditButton: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let rows = content()
        return List {
            if isSearching {
                searchResults
            } else {
                if isSearchPresented && !recents.isEmpty {
                    recentSearches
                }
                rows
            }
        }
        .searchable(text: $query, isPresented: $isSearchPresented, prompt: "Search all teams")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsEditButton {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
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
    }

    /// A sport's leagues.
    private func leaguesPage(_ kind: SportKind) -> some View {
        let leagues = BrowsableSport.all.first { $0.kind == kind }?.leagues ?? []
        return page(kind.browserTitle) {
            Section {
                ForEach(leagues) { item in
                    NavigationLink(value: Route.league(item.league)) {
                        leagueRow(item)
                    }
                    .accessibilityIdentifier("teamBrowser.league.\(item.label)")
                }
            } header: {
                Text("Leagues")
            } footer: {
                Text(leagues.count == 1 ? "1 league" : "\(leagues.count) leagues")
            }
        }
    }

    /// Every team in a league, to follow or unfollow.
    private func teamsPage(_ league: LeagueID) -> some View {
        let leagueTeams = teams(in: league)
        return page(league.descriptor.displayName) {
            // TODO(P3): conference sections for college leagues. The teams
            // feed carries no group data and `TeamRef` keeps none, so
            // college lists are one alphabetical section.
            Section {
                if catalogs[league] == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                ForEach(leagueTeams) { team in
                    row(team)
                }
            } header: {
                Text(league.badge)
            } footer: {
                if catalogs[league] != nil {
                    Text(teamCount(leagueTeams.count))
                }
            }
        }
        .task(id: league) {
            await load(league)
        }
    }

    // MARK: Rows

    /// A sport: its glyph, name, leagues, and how many of its teams the
    /// reader follows.
    private func sportRow(_ sport: BrowsableSport) -> some View {
        let leagueIDs = Set(sport.leagues.map(\.league))
        let followed = TeamSearch.clubCount(myTeams.filter { leagueIDs.contains($0.league) })
        let loaded = sport.leagues.compactMap { catalogs[$0.league]?.count }
        var detail = sport.leagues.count == 1 ? "1 league" : "\(sport.leagues.count) leagues"
        if loaded.count == sport.leagues.count {
            detail += " · " + teamCount(loaded.reduce(0, +))
        }

        return HStack(spacing: Theme.Spacing.m) {
            Image(systemName: sport.kind.browserSymbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: tileSize, height: tileSize)
                .background(Color.accentColor.opacity(0.15), in: Theme.Radius.innerShape)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(sport.kind.browserTitle)
                    .font(.headline)
                Text(sport.leagues.map(\.label).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            followedBadge(followed)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// A league: its badge, full name, team count, and how many of its
    /// teams the reader follows.
    private func leagueRow(_ item: BrowsableLeague) -> some View {
        let name = item.league.descriptor.displayName
        let followed = TeamSearch.clubCount(myTeams.filter { $0.league == item.league })
        return HStack(spacing: Theme.Spacing.m) {
            Text(item.label)
                .font(.caption.weight(.heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(minWidth: tileSize, minHeight: tileSize)
                .background(Color.accentColor.opacity(0.15), in: Theme.Radius.innerShape)
                .accessibilityHidden(name == item.label)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Group {
                    if let teams = catalogs[item.league] {
                        Text(teamCount(teams.count))
                    } else {
                        Text("Loading teams…")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            followedBadge(followed)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// How many of a sport's or league's teams the reader follows; nothing
    /// when none.
    @ViewBuilder
    private func followedBadge(_ count: Int) -> some View {
        if count > 0 {
            Label("\(count)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("\(count) followed")
        }
    }

    private func teamCount(_ count: Int) -> String {
        count == 1 ? "1 team" : "\(count) teams"
    }

    @ViewBuilder
    private var searchResults: some View {
        let local = localMatches
        if !local.isEmpty {
            Section("Results") {
                ForEach(local) { club in
                    row(club.canonical, club: club, fromSearch: true)
                }
            }
        } else if !remoteHits.isEmpty {
            Section("From ESPN") {
                ForEach(remoteHits) { team in
                    row(team, fromSearch: true)
                }
            }
        } else if isSearchingRemotely {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// The teams last followed from a search, newest first. A tap runs the
    /// search that found the team again.
    private var recentSearches: some View {
        Section {
            ForEach(recents) { recent in
                recentRow(recent)
            }
        } header: {
            HStack {
                Text("Recent")
                Spacer()
                Button("Clear") {
                    RecentSearches.clear()
                    recents = []
                }
                .font(.subheadline)
                .accessibilityLabel("Clear recent searches")
                .accessibilityIdentifier("teamBrowser.recent.clear")
            }
        }
    }

    private func recentRow(_ recent: RecentSearch) -> some View {
        Button {
            query = recent.query
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                TeamLogo(team: recent.team, size: crestSize)
                    .frame(width: crestSize, height: crestSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.team.displayName)
                        .foregroundStyle(.primary)
                    Text("“\(recent.query)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.left")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recent.team.displayName), searched \(recent.query)")
        .accessibilityHint("Searches again.")
        .accessibilityIdentifier("teamBrowser.recent.\(recent.team.id)")
    }

    /// A team to follow or unfollow. Given its `club`, as search results are,
    /// the row stands for the club in every league it was found in: it is
    /// followed under any of them, and the other leagues show as chips.
    /// Following one from a search records it in `recents`.
    private func row(_ team: TeamRef, club: ClubGroup? = nil, fromSearch: Bool = false) -> some View {
        let followed = club == nil ? store.isFavorite(team.id) : !store.followedClubIDs(of: team).isEmpty
        let otherBadges = club?.otherLeagues.map(\.badge) ?? []
        // One element per club: "Bayern Munich, Bundesliga, also in UCL".
        let spokenLabel = otherBadges.isEmpty
            ? "\(team.displayName), \(team.league.badge)"
            : "\(team.displayName), \(team.league.badge), also in \(otherBadges.joined(separator: ", "))"
        return Button {
            if club == nil {
                store.toggle(team)
            } else {
                store.toggleClub(team)
            }
            // New favorites want alerts (`FavoriteTeam.notify`), so the
            // first follow is where the reader is asked for them.
            if !followed {
                Task { await ScoreAlertsPermissions.requestIfNeeded() }
                if fromSearch {
                    recents = RecentSearches.record(query, team: team)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
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

                // The club's other leagues, cups last. Only labels: a tap
                // anywhere on the row follows the club.
                ForEach(otherBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .foregroundStyle(.tertiary)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
                }

                Spacer(minLength: 0)

                // Hierarchical, and replaced rather than swapped, so
                // following reads as one symbol changing state (B-2).
                Image(systemName: followed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(followed ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    // The store changes outside any animation; the replace
                    // effect needs one to play. None under Reduce Motion.
                    .motionAnimation(Theme.Motion.stateChange, value: followed)
            }
            .padding(.vertical, 2)
        }
        // A success tap on follow, a lighter one on unfollow (B-4, X-11).
        .sensoryFeedback(trigger: followed) { _, nowFollowed in
            nowFollowed ? .success : .impact(weight: .light)
        }
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(followed ? .isSelected : [])
        .accessibilityIdentifier("teamBrowser.team.\(team.id)")
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

    /// Applies a move in the My Teams section to the store. Rows are mapped
    /// to the store's positions by id, in case a favorite is not shown.
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

extension FavoritesStore {
    /// Follows or unfollows a club from search, where its row stands for it
    /// in every league (`followedClubIDs(of:)`). Unfollowed, it is followed
    /// as `team`; followed under any league, it is unfollowed under all.
    func toggleClub(_ team: TeamRef) {
        let followed = followedClubIDs(of: team)
        if followed.isEmpty {
            add(team)
        } else {
            for id in followed {
                remove(id)
            }
        }
    }
}

#Preview {
    TeamBrowserView()
}
