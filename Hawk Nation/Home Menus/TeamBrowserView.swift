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

/// The teams last opened from the search tab (`TeamBrowserView.SearchTab`),
/// offered under "Recently Viewed" before anything is typed: their ids,
/// newest first, each once, at most `limit`. Stored as one comma-separated
/// string, which `@AppStorage` keeps as it is; a team id
/// (`"sport/league:id"`) never holds a comma.
enum RecentTeams {
    static let key = "search.recentTeams.v1"
    static let limit = 8

    /// The ids in `stored`, newest first: only well-formed team ids, each
    /// once, at most `limit`. Empty for none.
    static func ids(from stored: String) -> [TeamRef.ID] {
        var seen: Set<TeamRef.ID> = []
        var ids: [TeamRef.ID] = []
        for part in stored.split(separator: ",") {
            let id = String(part)
            guard TeamRef.parse(id: id) != nil, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return Array(ids.prefix(limit))
    }

    /// `stored` with `id` moved or added to the front and the oldest past
    /// `limit` dropped. Anything that isn't a team id changes nothing.
    static func recording(_ id: TeamRef.ID, in stored: String) -> String {
        guard TeamRef.parse(id: id) != nil, !id.contains(",") else { return stored }
        let rest = ids(from: stored).filter { $0 != id }
        return ([id] + rest).prefix(limit).joined(separator: ",")
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

    /// `labels` as one line, "NBA · WNBA · NCAAM", that wraps only after a
    /// separator, never before one or inside a league's name: each name
    /// and the dot after it are held together by no-break spaces, so no
    /// line starts with "·" (S4).
    static func leagueList(_ labels: [String]) -> String {
        labels
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }

    /// This sport's leagues as `leagueList(_:)` writes them.
    var leagueLine: String {
        Self.leagueList(leagues.map(\.label))
    }
}

// MARK: - Conference sections

/// One section of a college league's team list: the teams of one
/// conference, or of none (R-5).
struct ConferenceSection: Identifiable, Hashable, Sendable {
    /// The conference's name, or `nil` for the teams the standings list in
    /// none (a college catalog spans every division; the standings only the
    /// descriptor's).
    let conference: String?
    /// The conference's teams, in the order they were given.
    let teams: [TeamRef]

    var id: String { conference ?? "" }

    /// `teams` grouped by conference: the conference-less teams first, then
    /// each conference alphabetically by name, each section keeping the
    /// order `teams` came in (the browser's alphabetical list). `[]` when not
    /// one team has a conference, for the caller to keep its single section.
    static func sections(_ teams: [TeamRef]) -> [ConferenceSection] {
        guard teams.contains(where: { $0.conference != nil }) else { return [] }
        var byConference: [String: [TeamRef]] = [:]
        var unaffiliated: [TeamRef] = []
        for team in teams {
            if let conference = team.conference {
                byConference[conference, default: []].append(team)
            } else {
                unaffiliated.append(team)
            }
        }
        let named = byConference.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ConferenceSection(conference: $0, teams: byConference[$0] ?? []) }
        return (unaffiliated.isEmpty ? [] : [ConferenceSection(conference: nil, teams: unaffiliated)]) + named
    }
}

// MARK: - Browser

/// The team picker: sports, then a sport's leagues, then every team in a
/// league, searchable throughout, with the reader's own teams pinned at the
/// top for reordering and removal.
///
/// Opened from Settings' "Add Teams" and "Edit My Teams" rows (t_fa6748f4)
/// and from the empty home screen's "Add Teams", where a fresh install
/// starts (t_afe5c297). Alerts live in Settings (B-9).
///
/// With the search field focused and empty, the teams last followed from a
/// search are offered under "Recent" (`RecentSearches`, C-7).
///
/// Also onboarding's last step, "Pick Your Teams" (O5), given `onboarding`:
/// the same sports, search and rows, the picks under "Picked", and in place
/// of the Done checkmark a Skip, and a Done below that stays disabled until
/// a team is picked (`OnboardingTeamsStep`).
///
/// And the search tab's root, given `searchTab`: the same search over
/// every catalog and the same sports-to-teams drill-down ("Browse by
/// Sport"), but a team's row opens its full page on the tab's stack, with
/// a follow button at its trailing end that follows without leaving; the
/// teams last opened come first, under "Recently Viewed" (`RecentTeams`).
struct TeamBrowserView: View {
    var title = "Teams"
    /// Set when the picker is onboarding's last step; `nil` everywhere else.
    var onboarding: OnboardingTeams? = nil
    /// Set when the picker is the search tab's root (`Home`); `nil`
    /// everywhere else.
    var searchTab: SearchTab? = nil

    /// What the picker needs from `Home` as the search tab's root.
    struct SearchTab {
        /// The tab's stack, which `Home` owns so that a team page on it can
        /// push another team's page (`HomeRouting.searchPath`).
        let path: Binding<[Route]>
        /// Whether the search tab is selected. A team's page on its stack
        /// is mounted only then, as a favorite's is only while its tab is
        /// selected, so it polls only on screen.
        let isOnScreen: Bool
        /// A team's full page, as a favorite's tab shows it, with the
        /// follow button in its bar (`TeamPageBody`, `isVisit`).
        let teamPage: @MainActor (TeamRef) -> AnyView
    }

    /// What onboarding's teams step does when it's left.
    struct OnboardingTeams {
        /// Done, with at least one team picked: the picks are already
        /// followed, as everywhere in the picker.
        let onDone: @MainActor () -> Void
        /// Skip: leaves for Home with whatever is followed, maybe nothing.
        let onSkip: @MainActor () -> Void
    }

    /// A screen pushed onto the picker's stack.
    enum Route: Hashable {
        case sport(SportKind)
        case league(LeagueID)
        /// A team's page, on the search tab's stack only (`SearchTab`).
        case team(TeamRef)

        /// The team whose page this is, for `.team`.
        var pushedTeam: TeamRef? {
            if case .team(let team) = self { return team }
            return nil
        }

        /// Whether moving the stack from `old` to `new` leaves the page a
        /// search was typed on, which clears the search: a sport or league
        /// pushed or popped. A team's page pushed over the results, or
        /// popped back to them, keeps it, so back returns to the results.
        static func leavesSearchPage(from old: [Route], to new: [Route]) -> Bool {
            old.filter { $0.pushedTeam == nil } != new.filter { $0.pushedTeam == nil }
        }
    }

    @Environment(\.dismiss) private var dismiss

    /// The brand theme, whose accent tints the picker however it's
    /// presented, never the system's blue (O3).
    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic

    @State private var path: [Route] = []
    @State private var catalogs: [LeagueID: [TeamRef]] = [:]
    @State private var myTeams: [TeamRef] = []
    @State private var query = ""
    @State private var remoteHits: [TeamRef] = []
    @State private var isSearchingRemotely = false
    /// Whether the search field is active, focused or not yet dismissed.
    @State private var isSearchPresented = false
    @State private var recents: [RecentSearch] = []

    /// The search tab's recently opened teams, as `RecentTeams` stores them.
    @AppStorage(RecentTeams.key) private var recentTeamIDs: String = ""
    /// Recently opened teams looked up so far, by id: those opened this
    /// session, and those `RemoteTeamCatalog` has found since.
    @State private var resolvedRecents: [TeamRef.ID: TeamRef] = [:]

    /// A row's crest, which scales with the team name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 24

    /// The tile a sport or league row leads with, which scales with its
    /// title.
    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

    private var store: FavoritesStore { .shared }

    /// The picker's stack: the search tab's, which `Home` owns, or its own.
    private var stackPath: Binding<[Route]> {
        searchTab?.path ?? $path
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The league on screen, if the reader has drilled down to one.
    private var currentLeague: LeagueID? {
        for route in stackPath.wrappedValue.reversed() {
            if case .league(let league) = route { return league }
        }
        return nil
    }

    /// The reader's teams' header: "Picked" in onboarding (O5).
    private var myTeamsHeader: String {
        onboarding == nil ? "My Teams" : "Picked"
    }

    /// The sports' header: "Browse by Sport" in onboarding (O5) and on
    /// the search tab.
    private var sportsHeader: String {
        onboarding == nil && searchTab == nil ? "Sports" : "Browse by Sport"
    }

    /// The search tab's recently opened teams, newest first: those looked
    /// up so far, from this session, the loaded catalogs or the bundle.
    /// One not found yet is left out rather than drawn as a stand-in.
    private var recentTeams: [TeamRef] {
        RecentTeams.ids(from: recentTeamIDs).compactMap { id in
            resolvedRecents[id] ?? catalogTeam(id) ?? TeamCatalog.team(id: id)
        }
    }

    /// The team with `id` in its league's loaded catalog, if loaded.
    private func catalogTeam(_ id: TeamRef.ID) -> TeamRef? {
        guard let league = TeamRef.parse(id: id)?.league else { return nil }
        return catalogs[league]?.first { $0.id == id }
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
        NavigationStack(path: stackPath) {
            // Edit only once there's an order to change or a team to remove
            // in bulk: an empty list has nothing to edit. Onboarding's picks
            // are a short list, removed with a tap or a swipe. The search
            // tab's teams are edited in Settings.
            page(
                onboarding == nil ? title : OnboardingTeamsStep.title,
                showsEditButton: onboarding == nil && searchTab == nil && myTeams.count > 1,
                isRoot: true
            ) {
                if searchTab != nil {
                    searchTabRoot
                } else {
                    if onboarding != nil {
                        Section {
                            Text(OnboardingTeamsStep.caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("onboarding.teams")
                    }

                    if !myTeams.isEmpty {
                        Section(myTeamsHeader) {
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

                    sportsSection
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sport(let kind):
                    leaguesPage(kind)
                case .league(let league):
                    teamsPage(league)
                case .team(let team):
                    teamPage(team)
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
        // The search tab's recently opened teams that no loaded catalog
        // or the bundle knows, such as an ESPN search hit's.
        .task(id: recentTeamIDs) {
            guard searchTab != nil else { return }
            for id in RecentTeams.ids(from: recentTeamIDs) where resolvedRecents[id] == nil {
                if let team = await FavoritesStore.resolve(id, within: .seconds(5)) {
                    resolvedRecents[id] = team
                }
            }
        }
        // A search belongs to the page it was typed on; a team's page
        // pushed over its results keeps it (`Route.leavesSearchPage`).
        .onChange(of: stackPath.wrappedValue) { old, new in
            if Route.leavesSearchPage(from: old, to: new) {
                query = ""
            }
        }
        // Full height, however it was opened: a searchable list
        // of every league's teams has no useful partial height (X-9).
        .presentationDetents([.large])
        .tint(theme.swatchColor)
    }

    // MARK: Pages

    /// One page of the picker: `content`, or the search results while there
    /// is a query, under the shared search field and Done button. With the
    /// field focused and still empty, recent searches come first.
    /// In onboarding (`onboarding`) the search field stays in view under
    /// the title, Skip leads the first page in place of the checkmark, and
    /// Done sits below every page.
    private func page<Content: View>(
        _ title: String,
        showsEditButton: Bool = false,
        isRoot: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let rows = content()
        return withOnboardingDoneBar(List {
            if isSearching {
                searchResults
            } else {
                // The search tab offers its recently opened teams instead,
                // on its first page (`searchTabRoot`).
                if isSearchPresented && !recents.isEmpty && searchTab == nil {
                    recentSearches
                }
                rows
            }
        }
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            placement: onboarding == nil ? .automatic : .navigationBarDrawer(displayMode: .always),
            prompt: "Search all teams"
        )
        .navigationTitle(title)
        // The search tab's first page is a tab's root, titled large as
        // Home's is; the rest are the picker's pages.
        .navigationBarTitleDisplayMode(isRoot && searchTab != nil ? .large : .inline)
        .toolbar {
            if showsEditButton {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            if let onboarding, isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onboarding.onSkip()
                    }
                    .accessibilityHint("Goes to Home without picking a team. You can add teams there.")
                    .accessibilityIdentifier("onboarding.teams.skip")
                }
            }
            // Onboarding finishes with its own Done, below the list; the
            // search tab is a tab, with nothing to dismiss.
            if onboarding == nil && searchTab == nil {
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
        })
    }

    /// `page` with onboarding's Done below it; `page` alone otherwise.
    @ViewBuilder
    private func withOnboardingDoneBar(_ page: some View) -> some View {
        if let onboarding {
            page.safeAreaBar(edge: .bottom) {
                onboardingDoneBar(onboarding)
            }
        } else {
            page
        }
    }

    /// Onboarding's Done, always in reach: disabled until a team is
    /// picked, then counting the picks (`OnboardingTeamsStep`).
    private func onboardingDoneBar(_ onboarding: OnboardingTeams) -> some View {
        let picked = store.teamIDs.count
        let canFinish = OnboardingTeamsStep.canFinish(pickedCount: picked)
        return VStack(spacing: Theme.Spacing.xs) {
            Button {
                onboarding.onDone()
            } label: {
                Text(OnboardingTeamsStep.doneTitle(pickedCount: picked))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!canFinish)
            .accessibilityHint(canFinish ? "Goes to Home with your teams." : "Pick a team first.")
            .accessibilityIdentifier("onboarding.teams.done")

            if !canFinish {
                Text(OnboardingTeamsStep.disabledNote)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.metadata)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    /// The sports, each opening its leagues.
    private var sportsSection: some View {
        Section(sportsHeader) {
            ForEach(BrowsableSport.all) { sport in
                NavigationLink(value: Route.sport(sport.kind)) {
                    sportRow(sport)
                }
                .accessibilityIdentifier("teamBrowser.sport.\(sport.kind.rawValue)")
            }
        }
    }

    /// The search tab's first page before anything is typed: the teams
    /// last opened from it, then the sports to browse.
    @ViewBuilder
    private var searchTabRoot: some View {
        let recent = recentTeams
        if !recent.isEmpty {
            Section {
                ForEach(recent) { team in
                    searchRow(team, identifier: "search.recent")
                }
            } header: {
                HStack {
                    Text("Recently Viewed")
                    Spacer()
                    Button("Clear") {
                        recentTeamIDs = ""
                    }
                    .font(.subheadline)
                    .accessibilityLabel("Clear recently viewed teams")
                    .accessibilityIdentifier("search.recent.clear")
                }
            }
        }

        sportsSection
    }

    /// A team's full page on the search tab's stack, mounted only while the
    /// tab is selected (`SearchTab.isOnScreen`).
    @ViewBuilder
    private func teamPage(_ team: TeamRef) -> some View {
        if let searchTab, searchTab.isOnScreen {
            searchTab.teamPage(team)
        } else {
            Theme.Surface.content
                .ignoresSafeArea()
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
    ///
    /// A college league whose catalog names conferences (`TeamRef.conference`,
    /// read from the standings by `RemoteTeamCatalog`) is one section per
    /// conference (`ConferenceSection.sections`); any other list is one
    /// alphabetical section.
    private func teamsPage(_ league: LeagueID) -> some View {
        let leagueTeams = teams(in: league)
        let conferences = league.isCollege ? ConferenceSection.sections(leagueTeams) : []
        return page(league.descriptor.displayName) {
            if conferences.isEmpty {
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
            } else {
                ForEach(conferences) { section in
                    Section {
                        ForEach(section.teams) { team in
                            row(team)
                        }
                    } header: {
                        // Teams in no listed conference (other divisions)
                        // go under the league's badge, as the one section did.
                        Text(section.conference ?? league.badge)
                    } footer: {
                        // The league's count once, under its last section.
                        if section.id == conferences.last?.id {
                            Text(teamCount(leagueTeams.count))
                        }
                    }
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
                .foregroundStyle(.tint)
                .frame(width: tileSize, height: tileSize)
                .background(.tint.opacity(0.15), in: Theme.Radius.innerShape)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(sport.kind.browserTitle)
                    .font(.headline)
                // Wraps between leagues only, never before a "·" (S4).
                Text(sport.leagueLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Information, so the readable grey, not tertiary (F1, S4).
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.metadata)
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
                .foregroundStyle(.tint)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(minWidth: tileSize, minHeight: tileSize)
                .background(.tint.opacity(0.15), in: Theme.Radius.innerShape)
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
                .foregroundStyle(.tint)
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
                        .foregroundStyle(Color.primary)
                    Text("“\(recent.query)”")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.metadata)
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

    /// Whether the row's team is followed: given its `club`, under any of
    /// the club's leagues.
    private func isFollowed(_ team: TeamRef, club: ClubGroup?) -> Bool {
        club == nil ? store.isFavorite(team.id) : !store.followedClubIDs(of: team).isEmpty
    }

    /// What VoiceOver reads for a team's row, one element per club:
    /// "Bayern Munich, Bundesliga, also in UCL".
    private func spokenName(_ team: TeamRef, otherBadges: [String]) -> String {
        otherBadges.isEmpty
            ? "\(team.displayName), \(team.league.badge)"
            : "\(team.displayName), \(team.league.badge), also in \(otherBadges.joined(separator: ", "))"
    }

    /// Follows or unfollows a row's team (its whole `club`, given one).
    /// Following one from a search records it in `recents`.
    private func toggleFollow(_ team: TeamRef, club: ClubGroup?, wasFollowed: Bool, fromSearch: Bool) {
        if club == nil {
            store.toggle(team)
        } else {
            store.toggleClub(team)
        }
        // New favorites want alerts (`FavoriteTeam.notify`), so the
        // first follow is where the reader is asked for them.
        if !wasFollowed {
            Task { await ScoreAlertsPermissions.requestIfNeeded() }
            if fromSearch {
                recents = RecentSearches.record(query, team: team)
            }
        }
    }

    /// A team row's crest, name and league chips.
    private func teamLabel(_ team: TeamRef, otherBadges: [String]) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            TeamLogo(team: team, size: crestSize)
                .frame(width: crestSize, height: crestSize)

            // Concrete label colours: in a button, the hierarchical
            // `.primary` and `.secondary` take the tint, and every team
            // read as a link.
            Text(team.displayName)
                .foregroundStyle(Color.primary)

            // Always shown: "Kansas City" is four teams in four leagues.
            Text(team.league.badge)
                .font(.caption2.weight(.semibold))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .foregroundStyle(Theme.Palette.metadata)
                .background(Color.secondary.opacity(0.15))
                .clipShape(.capsule)

            // The club's other leagues, cups last. Only labels: a tap
            // anywhere on the row follows (or opens) the club.
            ForEach(otherBadges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .foregroundStyle(Theme.Palette.metadata)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
            }
        }
    }

    /// A team's row: on the search tab one that opens its page
    /// (`searchRow`), elsewhere one that follows or unfollows it
    /// (`followRow`).
    @ViewBuilder
    private func row(_ team: TeamRef, club: ClubGroup? = nil, fromSearch: Bool = false) -> some View {
        if searchTab != nil {
            searchRow(team, club: club, fromSearch: fromSearch)
        } else {
            followRow(team, club: club, fromSearch: fromSearch)
        }
    }

    /// A team to follow or unfollow. Given its `club`, as search results are,
    /// the row stands for the club in every league it was found in: it is
    /// followed under any of them, and the other leagues show as chips.
    /// Following one from a search records it in `recents`.
    private func followRow(_ team: TeamRef, club: ClubGroup?, fromSearch: Bool) -> some View {
        let followed = isFollowed(team, club: club)
        let otherBadges = club?.otherLeagues.map(\.badge) ?? []
        return Button {
            toggleFollow(team, club: club, wasFollowed: followed, fromSearch: fromSearch)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                teamLabel(team, otherBadges: otherBadges)

                Spacer(minLength: 0)

                // Hierarchical, and replaced rather than swapped, so
                // following reads as one symbol changing state (B-2).
                Image(systemName: followed ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(followed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
        .accessibilityLabel(spokenName(team, otherBadges: otherBadges))
        .accessibilityAddTraits(followed ? .isSelected : [])
        .accessibilityIdentifier("teamBrowser.team.\(team.id)")
        .task {
            await RemoteTeamCatalog.shared.prefetchLogos(for: [team])
        }
    }

    /// A team on the search tab: a tap on the row opens its full page on
    /// the tab's stack, and the button at its trailing end follows or
    /// unfollows it without leaving (`followButton`). Given its `club`, as
    /// search results are, the row opens the club's canonical team and
    /// follows the club. `identifier` prefixes the row's identifier:
    /// `search.result` for results and browsed teams, `search.recent` for
    /// recently viewed ones.
    private func searchRow(
        _ team: TeamRef,
        club: ClubGroup? = nil,
        fromSearch: Bool = false,
        identifier: String = "search.result"
    ) -> some View {
        let followed = isFollowed(team, club: club)
        let otherBadges = club?.otherLeagues.map(\.badge) ?? []
        return HStack(spacing: Theme.Spacing.s) {
            // Plain and borderless, so the list leaves each button its own
            // taps rather than making the whole row one.
            Button {
                openTeam(team)
            } label: {
                teamLabel(team, otherBadges: otherBadges)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenName(team, otherBadges: otherBadges))
            .accessibilityHint("Opens the team's page.")
            .accessibilityIdentifier("\(identifier).\(team.id)")

            followButton(team, club: club, followed: followed, fromSearch: fromSearch)
        }
        .task {
            await RemoteTeamCatalog.shared.prefetchLogos(for: [team])
        }
    }

    /// A search row's follow control: a plus, followed a filled checkmark
    /// in the tint, as the picker's rows show it. Its own 44-point target.
    private func followButton(_ team: TeamRef, club: ClubGroup?, followed: Bool, fromSearch: Bool) -> some View {
        Button {
            toggleFollow(team, club: club, wasFollowed: followed, fromSearch: fromSearch)
        } label: {
            Image(systemName: followed ? "checkmark.circle.fill" : "plus.circle")
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(followed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                // The store changes outside any animation; the replace
                // effect needs one to play. None under Reduce Motion.
                .motionAnimation(Theme.Motion.stateChange, value: followed)
        }
        .buttonStyle(.borderless)
        // A success tap on follow, a lighter one on unfollow (B-4, X-11).
        .sensoryFeedback(trigger: followed) { _, nowFollowed in
            nowFollowed ? .success : .impact(weight: .light)
        }
        .accessibilityLabel(followed ? "Unfollow \(team.displayName)" : "Follow \(team.displayName)")
        .accessibilityAddTraits(followed ? .isSelected : [])
        .accessibilityIdentifier("search.follow.\(team.id)")
    }

    // MARK: Actions

    /// Pushes `team`'s page on the search tab's stack and puts it first
    /// among the recently viewed.
    private func openTeam(_ team: TeamRef) {
        guard let searchTab else { return }
        resolvedRecents[team.id] = team
        recentTeamIDs = RecentTeams.recording(team.id, in: recentTeamIDs)
        searchTab.path.wrappedValue.append(.team(team))
    }

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
