//
//  HomeCustomization.swift
//  myTeams
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// One of Home's sections under the hero, which the reader can hide and
/// reorder (`HomeCustomizeSheet`). The hero always shows.
enum HomeSectionKind: String, CaseIterable, Identifiable, Sendable {
    case myTeams
    case week
    /// Around Your Leagues: the other games in the favorites' leagues.
    case leagues
    case standings
    case performers
    case news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myTeams: "My Teams"
        case .week: "This Week"
        case .leagues: "Around Your Leagues"
        case .standings: "Standings"
        case .performers: "Top Performers"
        case .news: "News"
        }
    }

    /// The SF Symbol in the section's header and its row in the sheet.
    var systemImage: String {
        switch self {
        case .myTeams: "star"
        case .week: "calendar"
        case .leagues: "sportscourt"
        case .standings: "list.number"
        case .performers: "trophy"
        case .news: "newspaper"
        }
    }

    /// Where the section sits on an iPad (B-14, H10).
    enum RegularColumn: Sendable {
        /// The left column: the teams and their week.
        case leading
        /// The right column: the tables, beside them.
        case trailing
        /// Full width beneath both columns: the news, whose stories read
        /// better wide than squeezed into half the page, and Around Your
        /// Leagues, whose league blocks sit two across there.
        case fullWidth
    }

    /// Which column the section takes on an iPad, so the two columns come
    /// out about the same height (H10): My Teams and This Week on the left,
    /// Standings and Top Performers on the right, Around Your Leagues and
    /// the news under both — a league's games would make whichever column
    /// held them the taller by far.
    var regularColumn: RegularColumn {
        switch self {
        case .myTeams, .week: .leading
        case .standings, .performers: .trailing
        case .leagues, .news: .fullWidth
        }
    }
}

/// Home's sections in the reader's order, and which are hidden, as kept in
/// `@AppStorage(storageKey)`: the raw values comma-separated, a hidden one
/// prefixed `-` — `"week,myTeams,-standings,performers,news"`.
///
/// Read leniently, so an update's new section shows up: a value it doesn't
/// know is dropped, and a section the string doesn't name is added, shown,
/// just after the section it follows in the default layout (Around Your
/// Leagues after This Week), or after the others when that one isn't named
/// either. An empty string is the default layout.
struct HomeSectionLayout: Equatable, Sendable {
    /// The `UserDefaults` key.
    static let storageKey = "home.sections"

    private static let hiddenPrefix = "-"

    /// Every section, in order, shown or hidden.
    var order: [HomeSectionKind]
    var hidden: Set<HomeSectionKind>

    /// Every section, in `HomeSectionKind`'s order, none hidden.
    static let standard = HomeSectionLayout(order: HomeSectionKind.allCases, hidden: [])

    init(order: [HomeSectionKind], hidden: Set<HomeSectionKind>) {
        self.order = order
        self.hidden = hidden
    }

    /// Reads a stored layout. See the type's documentation.
    init(storage: String) {
        var order: [HomeSectionKind] = []
        var hidden: Set<HomeSectionKind> = []
        for token in storage.split(separator: ",") {
            var value = token.trimmingCharacters(in: .whitespaces)
            let isHidden = value.hasPrefix(Self.hiddenPrefix)
            if isHidden {
                value.removeFirst(Self.hiddenPrefix.count)
            }
            guard let kind = HomeSectionKind(rawValue: value), !order.contains(kind) else { continue }
            order.append(kind)
            if isHidden {
                hidden.insert(kind)
            }
        }
        let all = HomeSectionKind.allCases
        for (index, kind) in all.enumerated() where !order.contains(kind) {
            let previous = index > 0 ? order.firstIndex(of: all[index - 1]) : nil
            if let previous {
                order.insert(kind, at: previous + 1)
            } else {
                order.append(kind)
            }
        }
        self.init(order: order, hidden: hidden)
    }

    /// The layout as stored.
    var storage: String {
        order
            .map { hidden.contains($0) ? Self.hiddenPrefix + $0.rawValue : $0.rawValue }
            .joined(separator: ",")
    }

    /// The sections Home draws, in order.
    var visible: [HomeSectionKind] {
        order.filter { !hidden.contains($0) }
    }

    /// `kind` shown or hidden.
    func setting(_ kind: HomeSectionKind, shown: Bool) -> HomeSectionLayout {
        var next = self
        if shown {
            next.hidden.remove(kind)
        } else {
            next.hidden.insert(kind)
        }
        return next
    }

    /// The sections at `source` moved to `destination`, as a list's
    /// `onMove` reports it.
    func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> HomeSectionLayout {
        var next = self
        next.order.move(fromOffsets: source, toOffset: destination)
        return next
    }
}

// MARK: - Around Your Leagues settings

/// How far Around Your Leagues looks: today's boards, or the week around
/// today — the next seven days and the last two days' results.
enum HomeLeaguesScope: String, CaseIterable, Identifiable, Sendable {
    case today
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        }
    }
}

/// How many games each league's block lists before its "See all" row.
enum HomeLeaguesGameLimit: Int, CaseIterable, Identifiable, Sendable {
    case three = 3
    case five = 5
    case ten = 10
    /// Every game, never capped.
    case all = 0

    var id: Int { rawValue }

    var title: String {
        self == .all ? "All" : "\(rawValue)"
    }

    /// The cap, or `nil` for every game.
    var count: Int? {
        self == .all ? nil : rawValue
    }
}

/// What Around Your Leagues shows (`HomeSectionKind.leagues`), as the
/// reader set it in Customize Home or the section header's picker. Each
/// value is its own `UserDefaults` key, in the plain form `@AppStorage`
/// writes — a string, an integer, a flag — so the views bind to them
/// directly and a value read here is the one they wrote.
///
/// The leagues are kept as the ones switched *off*, so a league the reader
/// starts following a team in shows without being switched on.
struct HomeLeaguesSettings: Equatable, Sendable {
    /// `HomeLeaguesScope`'s raw value.
    static let scopeKey = "home.leagues.scope"
    /// The switched-off leagues' paths, comma-separated
    /// (`"soccer/eng.1,football/nfl"`): paths hold `/` and `.`, never `,`.
    static let hiddenLeaguesKey = "home.leagues.hidden"
    /// `HomeLeaguesGameLimit`'s raw value.
    static let limitKey = "home.leagues.limit"
    static let rankedOnlyKey = "home.leagues.top25"
    static let includesMyTeamsKey = "home.leagues.includeMine"

    var scope: HomeLeaguesScope = .today
    var hiddenLeagues: Set<LeagueID> = []
    var limit: HomeLeaguesGameLimit = .five
    /// A college league lists only games with a ranked team in them.
    var rankedOnly = true
    /// The favorites' own games are listed too, marked. Off by default:
    /// My Teams and This Week show them already.
    var includesMyTeams = false

    /// Every value at its default.
    static let standard = HomeLeaguesSettings()

    /// Whether `league`'s block shows.
    func shows(_ league: LeagueID) -> Bool {
        !hiddenLeagues.contains(league)
    }

    /// Whether `league`'s block keeps only games with a ranked team: a
    /// college league, with Top 25 only on.
    func ranksOnly(_ league: LeagueID) -> Bool {
        rankedOnly && league.isCollege
    }

    /// The stored switched-off leagues. A malformed path is dropped.
    static func hiddenLeagues(storage: String) -> Set<LeagueID> {
        Set(storage.split(separator: ",").compactMap { token in
            LeagueID(path: token.trimmingCharacters(in: .whitespaces))
        })
    }

    /// The switched-off leagues as stored, in a stable order.
    static func storage(hiddenLeagues: Set<LeagueID>) -> String {
        hiddenLeagues.map(\.path).sorted().joined(separator: ",")
    }

    /// `storage` less the leagues no favorite plays in any more, so
    /// following a team there again later shows its league; `nil` when
    /// nothing changes. Nothing is pruned without favorites to go by.
    static func pruned(storage: String, favoriteLeagues: [LeagueID]) -> String? {
        guard !favoriteLeagues.isEmpty else { return nil }
        let stored = hiddenLeagues(storage: storage)
        let kept = stored.intersection(favoriteLeagues)
        let pruned = Self.storage(hiddenLeagues: kept)
        return pruned == storage ? nil : pruned
    }

    /// The favorites' leagues, each once, in favorites order: the leagues
    /// Around Your Leagues has a block for.
    static func favoriteLeagues(teamIDs: [TeamRef.ID]) -> [LeagueID] {
        var leagues: [LeagueID] = []
        for id in teamIDs {
            if let league = TeamRef.parse(id: id)?.league, !leagues.contains(league) {
                leagues.append(league)
            }
        }
        return leagues
    }
}

extension HomeLeaguesSettings {
    /// The settings as stored in `defaults`; each one missing or unreadable
    /// is its default.
    init(defaults: UserDefaults) {
        self.init(
            scope: defaults.string(forKey: Self.scopeKey).flatMap(HomeLeaguesScope.init(rawValue:)) ?? .today,
            hiddenLeagues: Self.hiddenLeagues(storage: defaults.string(forKey: Self.hiddenLeaguesKey) ?? ""),
            limit: (defaults.object(forKey: Self.limitKey) as? Int).flatMap(HomeLeaguesGameLimit.init(rawValue:)) ?? .five,
            rankedOnly: defaults.object(forKey: Self.rankedOnlyKey) as? Bool ?? true,
            includesMyTeams: defaults.object(forKey: Self.includesMyTeamsKey) as? Bool ?? false
        )
    }

    /// Stores every value in `defaults`, as the views' `@AppStorage` would.
    func write(to defaults: UserDefaults) {
        defaults.set(scope.rawValue, forKey: Self.scopeKey)
        defaults.set(Self.storage(hiddenLeagues: hiddenLeagues), forKey: Self.hiddenLeaguesKey)
        defaults.set(limit.rawValue, forKey: Self.limitKey)
        defaults.set(rankedOnly, forKey: Self.rankedOnlyKey)
        defaults.set(includesMyTeams, forKey: Self.includesMyTeamsKey)
    }
}

// MARK: - Customize Home

/// "Customize Home": every section under the hero with a switch to show
/// or hide it, in Home's order, dragged to reorder; then what Around Your
/// Leagues shows. Saved as it changes, so Home underneath follows along.
///
/// A sheet from Home's foot, or a page pushed from Settings' Home row
/// (`isPushed`), the same settings either way.
struct HomeCustomizeSheet: View {
    /// Pushed onto Settings' stack rather than presented: no stack or Done
    /// of its own, and Edit at the trailing end, clear of the back button.
    var isPushed = false

    @AppStorage(HomeSectionLayout.storageKey) private var storage = ""

    @AppStorage(HomeLeaguesSettings.scopeKey) private var leaguesScope: HomeLeaguesScope = .today
    @AppStorage(HomeLeaguesSettings.hiddenLeaguesKey) private var hiddenLeagues = ""
    @AppStorage(HomeLeaguesSettings.limitKey) private var leaguesLimit: HomeLeaguesGameLimit = .five
    @AppStorage(HomeLeaguesSettings.rankedOnlyKey) private var rankedOnly = true
    @AppStorage(HomeLeaguesSettings.includesMyTeamsKey) private var includesMyTeams = false

    @Environment(\.dismiss) private var dismiss

    private var layout: HomeSectionLayout { HomeSectionLayout(storage: storage) }

    /// The favorites' leagues, read from the favorites' ids, so a league
    /// shows here before its teams have resolved.
    private var leagues: [LeagueID] {
        HomeLeaguesSettings.favoriteLeagues(teamIDs: FavoritesStore.shared.teamIDs)
    }

    var body: some View {
        if isPushed {
            form
        } else {
            NavigationStack {
                form
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                            .accessibilityIdentifier("home.customize.done")
                        }
                    }
            }
            // Full height, so every section and Restore Default Layout are
            // in view without dragging the sheet up (H6).
            .presentationDetents([.large])
        }
    }

    private var form: some View {
        List {
            Section {
                ForEach(layout.order) { kind in
                    Toggle(isOn: shown(kind)) {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                    .accessibilityIdentifier("home.customize.\(kind.rawValue)")
                }
                .onMove { source, destination in
                    storage = layout.moving(fromOffsets: source, toOffset: destination).storage
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Your next game always leads Home. Tap Edit to drag the sections into the order you like.")
            }

            leaguesSection

            Section {
                Button("Restore Default Layout") {
                    storage = HomeSectionLayout.standard.storage
                }
                .disabled(layout == .standard)
                .accessibilityIdentifier("home.customize.reset")
            }
        }
        .navigationTitle("Customize Home")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: isPushed ? .topBarTrailing : .topBarLeading) {
                EditButton()
            }
        }
    }

    /// Around Your Leagues: how far it looks, how many games a league
    /// lists, Top 25 only where a college league is followed, the
    /// favorites' own games, and a switch per league.
    private var leaguesSection: some View {
        let leagues = leagues
        return Section {
            Picker("Show", selection: $leaguesScope) {
                ForEach(HomeLeaguesScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .accessibilityIdentifier("home.customize.leagues.scope")

            Picker("Games per League", selection: $leaguesLimit) {
                ForEach(HomeLeaguesGameLimit.allCases) { limit in
                    Text(limit.title).tag(limit)
                }
            }
            .accessibilityIdentifier("home.customize.leagues.limit")

            if leagues.contains(where: \.isCollege) {
                Toggle("Top 25 Only", isOn: $rankedOnly)
                    .accessibilityHint("In college leagues, lists only games with a ranked team.")
                    .accessibilityIdentifier("home.customize.leagues.top25")
            }

            Toggle("Include My Teams' Games", isOn: $includesMyTeams)
                .accessibilityHint("Lists your own teams' games among the league's, marked.")
                .accessibilityIdentifier("home.customize.leagues.includeMine")

            ForEach(leagues, id: \.self) { league in
                Toggle(isOn: leagueShown(league)) {
                    Label(league.descriptor.displayName, systemImage: TeamColors.symbolName(for: league.descriptor.kind))
                }
                .accessibilityIdentifier("home.customize.league.\(league.path)")
            }
        } header: {
            Text(HomeSectionKind.leagues.title)
        } footer: {
            Text("The other games in the leagues your teams play in. This Week shows the next seven days and the last two days' results.")
        }
    }

    /// Whether `kind` shows, saved as it's switched.
    private func shown(_ kind: HomeSectionKind) -> Binding<Bool> {
        Binding {
            !layout.hidden.contains(kind)
        } set: { isShown in
            storage = layout.setting(kind, shown: isShown).storage
        }
    }

    /// Whether `league`'s block shows, saved as it's switched.
    private func leagueShown(_ league: LeagueID) -> Binding<Bool> {
        Binding {
            !HomeLeaguesSettings.hiddenLeagues(storage: hiddenLeagues).contains(league)
        } set: { isShown in
            var hidden = HomeLeaguesSettings.hiddenLeagues(storage: hiddenLeagues)
            if isShown {
                hidden.remove(league)
            } else {
                hidden.insert(league)
            }
            hiddenLeagues = HomeLeaguesSettings.storage(hiddenLeagues: hidden)
        }
    }
}

#Preview {
    HomeCustomizeSheet()
}
