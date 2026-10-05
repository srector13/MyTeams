//
//  TabBar.swift
//  myTeams
//
//  Created by Stephen Rector on 10/22/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

// The teams on this screen are the reader's favorites (`FavoritesStore`),
// resolved through `RemoteTeamCatalog` and shown in favorites order.

/// The app's root screen: the system tab bar, one tab per favorite team, each
/// showing that team's scrolling page, and a "Teams" tab that opens the team
/// picker.
///
/// A standard `TabView`, so the platform draws the bar: its Liquid Glass,
/// selection indicator and animation, the large content viewer, minimizing
/// on scroll, and the "More" tab that takes the favorites past what the bar
/// holds.
struct Home: View {
    /// A team to switch to, set when a widget link opens the app. Cleared
    /// once handled; a team that is not a favorite is ignored.
    @Binding var deepLinkedTeamID: TeamRef.ID?

    /// The favorites as teams. Starts with those the bundled catalog knows,
    /// so the first frame has the seed teams, then fills in from the catalog.
    @State private var teams: [TeamRef] = FavoritesStore.shared.teamIDs.compactMap(TeamCatalog.team(id:))

    @State private var selection: TeamRef.ID = FavoritesStore.shared.teamIDs.first ?? ""

    @State private var showsBrowser = false

    /// Settings, opened from a team page's gear. Here rather than on the
    /// page, which is mounted only while its team is selected: removing
    /// that team in Settings → Manage Teams, or a widget link arriving,
    /// moves the selection and unmounts the page, and Settings with it
    /// (A-5).
    @State private var showsSettings = false

    /// Each team's model and scroll offset, kept while its page is not
    /// mounted.
    @State private var pages = TeamPages()

    /// Bumped when a favorite's crest lands in `LogoStore`, so the tab items
    /// read it again (`TabCrest`).
    @State private var crestRevision = 0

    @Bindable private var store = FavoritesStore.shared

    /// VoiceOver and Switch Control keep the bar at full size: a minimized
    /// bar hides the other teams' tabs from them.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    // Spelled out: the private state makes the memberwise init private.
    init(deepLinkedTeamID: Binding<TeamRef.ID?>) {
        self._deepLinkedTeamID = deepLinkedTeamID
    }

    private var routing: HomeRouting.State {
        HomeRouting.State(selection: selection, pendingLink: deepLinkedTeamID, showsSettings: showsSettings)
    }

    private func apply(_ routed: HomeRouting.State) {
        if selection != routed.selection {
            selection = routed.selection
        }
        if deepLinkedTeamID != routed.pendingLink {
            deepLinkedTeamID = routed.pendingLink
        }
        if showsSettings != routed.showsSettings {
            showsSettings = routed.showsSettings
        }
    }

    /// The tab view's selection. The "Teams" tab is a button, not a page: a
    /// tap on it opens the picker and the team on screen stays selected, so
    /// the bar goes back to that team's tab.
    private var tabSelection: Binding<TeamRef.ID> {
        Binding {
            selection
        } set: { tab in
            if tab == HomeTabs.edit {
                showsBrowser = true
            } else {
                selection = tab
            }
        }
    }

    /// Restarts the crest prefetch when the favorites or the colour scheme
    /// (and with it the crest variant) change.
    private var crestTaskID: String {
        teams.map(\.id).joined(separator: ",") + (colorScheme == .dark ? "|dark" : "|light")
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if teams.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Teams")
                        } icon: {
                            // Asset-catalog appearances pick the light/dark art.
                            Image("myTeamsLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: BrandLogo.hero)
                                .accessibilityHidden(true)
                        }
                    } description: {
                        Text("Follow a team to see its schedule, roster and news.")
                    } actions: {
                        Button("Pick Your Teams") { showsBrowser = true }
                    }
                } else {
                    tabs
                }
            }
            .environment(\.containerSize, proxy.size)
        }
        .task(id: store.teamIDs) {
            pages.retain(store.teamIDs)
            teams = await store.teamRefs()
            apply(HomeRouting.favoritesResolved(routing, teams: teams.map(\.id)))
        }
        .onChange(of: deepLinkedTeamID, initial: true) { _, _ in
            apply(HomeRouting.linkChanged(routing, teams: teams.map(\.id), favoriteIDs: store.teamIDs))
        }
        // A tab item takes a finished image, not a view that loads one, so
        // the crests are fetched here and the items redrawn as each lands.
        .task(id: crestTaskID) {
            let dark = colorScheme == .dark
            for team in teams {
                if await TabCrest.prefetch(team, dark: dark) {
                    crestRevision += 1
                }
            }
        }
        .sheet(isPresented: $showsBrowser) {
            TeamBrowserView()
        }
        // Outlives any one team's page (A-5).
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // A fresh install opens on "Pick your teams", the seed teams already
        // checked. Dismissing it, however, finishes onboarding.
        .sheet(isPresented: $store.needsOnboarding, onDismiss: { store.completeOnboarding() }) {
            TeamBrowserView(title: "Pick Your Teams")
        }
    }

    /// The favorites' tabs with the "Teams" tab among them: last while the
    /// bar holds them all, otherwise in the bar's last slot before "More"
    /// (`HomeTabs.editIndex`), so it is always in the bar.
    @ViewBuilder
    private var tabs: some View {
        let _ = crestRevision
        let editIndex = HomeTabs.editIndex(
            teamCount: teams.count,
            barCapacity: sizeClass == .compact ? HomeTabs.compactCapacity : nil
        )
        TabView(selection: tabSelection) {
            ForEach(Array(teams.prefix(editIndex))) { team in
                teamTab(team)
            }

            Tab("Teams", systemImage: "plus.circle", value: HomeTabs.edit) {
                // Never shown: selecting the tab opens the picker instead.
                Color.clear
            }
            .accessibilityLabel(Text("Add or Edit Teams"))
            .accessibilityIdentifier(HomeTabs.edit)
            // Left visible in every placement: hiding it for the sidebar
            // (`defaultVisibility`) coincided with it missing from the
            // phone's bar in UI tests. The iPad sidebar adds a footer
            // entry as well (B-14).

            ForEach(Array(teams.dropFirst(editIndex))) { team in
                teamTab(team)
            }
        }
        // The bar shrinks to the selected tab as the page scrolls down and
        // comes back on scrolling up or a tap, as the system's apps do.
        .tabBarMinimizeBehavior(voiceOver || switchControl ? .never : .onScrollDown)
        .modifier(HomeSidebar(isRegularWidth: sizeClass == .regular) { showsBrowser = true })
        // A tick as the team changes (C-4).
        .sensoryFeedback(.selection, trigger: selection)
        // The alerts presenter skips the banner for the team on screen (C-8).
        .onChange(of: selection, initial: true) { ScoreAlertForeground.shared.teamID = $1 }
    }

    /// A favorite's tab: its crest over its short name.
    private func teamTab(_ team: TeamRef) -> some TabContent<TeamRef.ID> {
        Tab(value: team.id) {
            teamPage(team)
        } label: {
            Label {
                Text(team.shortName)
            } icon: {
                Image(uiImage: TabCrest.image(for: team, dark: colorScheme == .dark, scale: displayScale))
                    .renderingMode(.original)
            }
        }
        .accessibilityLabel(Text(team.displayName))
        .accessibilityIdentifier("teamPicker.team.\(team.id)")
    }

    /// Only the selected team's page is mounted, so only it loads and polls:
    /// leaving the page cancels its task. Every page used to stay mounted,
    /// each polling on its own. `pages` keeps each team's loaded data and
    /// scroll offset for when the reader comes back.
    @ViewBuilder
    private func teamPage(_ team: TeamRef) -> some View {
        if team.id == selection {
            TeamPage(
                team: team,
                savedOffset: pages.scrollOffset(for: team.id),
                saveOffset: { pages.setScrollOffset($0, for: team.id) },
                showSettings: { showsSettings = true }
            ) {
                TeamHomeView(team: team, pages: pages)
            }
            .id(team.id)
        } else {
            Theme.Surface.content
                .ignoresSafeArea()
        }
    }
}

/// Which team `Home` shows, and what becomes of a widget link, as plain
/// values: the view feeds it its state and applies the answer.
enum HomeRouting {
    struct State: Equatable, Sendable {
        /// The selected team's id; `""` with no teams.
        var selection: TeamRef.ID
        /// A widget link not yet handled (`Home.deepLinkedTeamID`).
        var pendingLink: TeamRef.ID?
        /// Whether Settings is open (`Home.showsSettings`). Nothing here
        /// closes it: not the selection moving off a removed team, not a
        /// link (A-5).
        var showsSettings = false
    }

    /// The favorites have been resolved to `teams`, in order. A selection
    /// no longer among them falls back to the first; a link that arrived
    /// while the favorites were loading is handled now, selecting its team
    /// if it resolved and dropped either way.
    static func favoritesResolved(_ state: State, teams: [TeamRef.ID]) -> State {
        var next = state
        if !teams.contains(next.selection) {
            next.selection = teams.first ?? ""
        }
        if let id = next.pendingLink {
            next.pendingLink = nil
            if teams.contains(id) {
                next.selection = id
            }
        }
        return next
    }

    /// A widget link arrived (or `Home` appeared with one). A resolved
    /// team is selected at once and a team that is not a favorite is
    /// dropped; a favorite still resolving stays pending for
    /// `favoritesResolved`.
    static func linkChanged(_ state: State, teams: [TeamRef.ID], favoriteIDs: [TeamRef.ID]) -> State {
        guard let id = state.pendingLink else { return state }
        var next = state
        if teams.contains(id) {
            next.selection = id
            next.pendingLink = nil
        } else if !favoriteIDs.contains(id) {
            next.pendingLink = nil
        }
        return next
    }
}

/// What a team page's scrolling content tells the page around it
/// (`TeamPage`): how tall the summary at the top of the page is. Set only
/// as that changes, never per scrolled frame.
@MainActor
@Observable
final class TeamPageChrome {
    /// The summary's height (`TeamPageHeader`), which the team colour
    /// behind it must cover.
    var headerHeight: CGFloat = 0

    /// What pulling the page down does: set by the content, which owns the
    /// team's model (`TeamModel.refreshAll()`, C-1). Not drawn, so not
    /// observed.
    @ObservationIgnored var refresh: (@MainActor @Sendable () async -> Void)?
}

/// One team's scrolling page: the team's crest and name pinned in the
/// navigation bar over the team colour, and below it the page — the
/// record and next game over the team colour, then the page of cards
/// (UI-1, t_5478d64e).
///
/// Layered back to front, so the bar's content is never drawn under or
/// over the cards by construction: the team colour; the scroll view; an
/// opaque team-colour layer exactly covering the status bar and the
/// navigation bar (`barBackdrop`), which the page scrolls beneath; then the
/// system bar with the crest and name (`TeamBarTitle`). Nothing in the bar
/// depends on the scroll offset, so it's the same at rest, scrolled and
/// pulled past the top. The crest is drawn once, in the bar.
///
/// The page is mounted only while its team is selected, so it reports its
/// scroll offset as it moves (`saveOffset`) and opens where it was left
/// (`savedOffset`) through a `ScrollPosition`.
private struct TeamPage<Content: View>: View {
    let team: TeamRef
    /// How far down the reader last left this team's page, in points.
    let savedOffset: CGFloat
    let saveOffset: @MainActor (CGFloat) -> Void
    /// Opens Settings, which `Home` presents so that it outlives the page
    /// (A-5).
    let showSettings: @MainActor () -> Void
    @ViewBuilder var content: Content

    @State private var position = ScrollPosition(edge: .top)

    @State private var chrome = TeamPageChrome()

    @Environment(\.containerSize) private var containerSize

    /// The team colour, or the fallback its badge takes when the feed has
    /// none, so the bar's ink and crest variant are picked against what is
    /// drawn.
    private var heroHex: String { TeamColors.fillHex(for: team) }

    /// The bar's colour scheme over the team colour (H-6): dark, for a white
    /// status bar and controls, when white reads better on it than black.
    private var heroBarScheme: ColorScheme {
        TeamColors.inkHex(on: heroHex) == "FFFFFF" ? .dark : .light
    }

    /// Tall enough to sit behind the summary and the page's rounded top
    /// with room to spare for pulling the page down, on any device and at
    /// any text size.
    private var heroHeight: CGFloat {
        max(containerSize.height / 2, chrome.headerHeight + containerSize.height / 4)
    }

    /// The team colour behind the status bar and the navigation bar, and
    /// only there: a zero-height view at the top of the safe area whose
    /// background takes the top safe area, which is exactly the two bars.
    /// Opaque and above the scroll view, so the page scrolls under it and
    /// never shows behind the bar's crest and name.
    private var barBackdrop: some View {
        Color.clear
            .frame(height: 0)
            .background(alignment: .bottom) {
                Color(hexString: heroHex)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // The team colour. It never scrolls: the cards cover it.
                // It extends under the navigation bar, the status bar and
                // any landscape side insets (H-5, B5). Flat, so it meets
                // `barBackdrop` without a seam.
                Rectangle()
                    .fill(Color(hexString: heroHex))
                    .frame(height: heroHeight)
                    .backgroundExtensionEffect()
                    .accessibilityHidden(true)

                // Not ignoring the top safe area: the scroll view starts its
                // content — the summary, then the cards — below the
                // navigation bar and scrolls it under `barBackdrop`. Full
                // width: `TeamHomeLayout` insets its own section cards on
                // the grouped background (T-4).
                ScrollView(.vertical) {
                    content
                }
                .scrollIndicators(.hidden)
                // Pull to refresh every feed, whatever its age (C-1). The
                // content sets what that does; the spinner shows until
                // every feed has answered.
                .refreshable { [chrome] in
                    await chrome.refresh?()
                }
                // The page scrolls under the tab bar; the soft edge fades it
                // there, so neither the tabs nor the cards fight for
                // legibility (T-5, B5).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                // The bar is opaque team colour: nothing to soften there.
                .scrollEdgeEffectHidden(true, for: .top)
                .scrollBounceBehavior(.basedOnSize)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    saveOffset(max(offset, 0))
                }
                .onAppear {
                    // The team's model outlives the page, so its content is
                    // already laid out at full height here.
                    if savedOffset > 0 {
                        position.scrollTo(point: CGPoint(x: 0, y: savedOffset))
                    }
                }

                // Drawn after the scroll view, so over the page.
                barBackdrop
            }
            // The grouped page behind the hero, showing past the foot of
            // the page and under the tab bar, the colour of the page.
            .background(Theme.Surface.content)
            .environment(chrome)
            .navigationTitle(team.displayName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // The crest and name, always: pinned in the bar, at every
                // scroll offset (H-3).
                ToolbarItem(placement: .principal) {
                    TeamBarTitle(team: team, backgroundHex: heroHex)
                }
                // A title, not a button: no glass behind it.
                .sharedBackgroundVisibility(.hidden)

                // The app's mark, small, in the bar's ink: the white
                // silhouette as a template, so it reads on any team colour.
                ToolbarItem(placement: .topBarLeading) {
                    BrandBarLogo(backgroundHex: heroHex)
                }
                // A mark, not a button: no glass behind it.
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("home.settings")
                }
            }
            // The system bar in the team colour too, and the scheme that
            // reads on it whatever is scrolled beneath.
            .toolbarBackground(Color(hexString: heroHex), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(heroBarScheme, for: .navigationBar)
        }
    }
}

/// A team page's bar title: the team's crest — the page's only one — and
/// its name, in the ink and crest variant for the team colour behind the
/// bar (`teamInk(onHex:)`, `TeamColors.logoVariant`).
private struct TeamBarTitle: View {
    let team: TeamRef
    let backgroundHex: String

    @ScaledMetric(relativeTo: .headline) private var crestSize: CGFloat = 28

    var body: some View {
        // Capped: the bar doesn't grow with the text.
        let size = min(crestSize, 36)
        let variant = TeamColors.logoVariant(for: team, onBackground: backgroundHex)
        // A crest that would vanish into the bar sits on a disc in the
        // bar's ink, as a badge (B-4).
        let badged = BarCrest.needsBadge(team: team, variant: variant, onHex: backgroundHex)
        HStack(spacing: Theme.Spacing.s) {
            TeamLogo(team: team, size: badged ? size * BarCrest.badgeInset : size, forceVariant: variant)
                .frame(width: size, height: size)
                .background {
                    if badged {
                        Circle()
                            .fill(Color(hexString: TeamColors.inkHex(on: backgroundHex)))
                    }
                }
                .accessibilityHidden(true)

            Text(team.displayName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .teamInk(onHex: backgroundHex)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("teamPage.header")
    }
}

/// The myTeams mark in a team page's bar: the mono-white logo drawn as a
/// template in the bar's ink (`teamInk(onHex:)`), white or black, so it
/// reads on whatever the team colour is, like the title beside it.
private struct BrandBarLogo: View {
    let backgroundHex: String

    var body: some View {
        Image("myTeamsLogoMonoWhite")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            // Fixed: brand presence, not a control that grows with text.
            .frame(height: BrandLogo.bar)
            .teamInk(onHex: backgroundHex)
            .accessibilityLabel("myTeams")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("home.brandLogo")
    }
}

/// Where the "Teams" tab goes among the favorites' tabs.
enum HomeTabs {
    /// The "Teams" tab's value, and its accessibility identifier. Never a
    /// team's id, which is `"<leaguePath>:<espnID>"`.
    static let edit = "teamPicker.edit"

    /// The most items a compact-width tab bar shows. With more tabs it
    /// shows one fewer and a "More" item listing the rest.
    static let compactCapacity = 5

    /// The "Teams" tab's index among `teamCount` favorites' tabs: last while
    /// every tab fits a bar of `barCapacity` (no limit for `nil`), otherwise
    /// the last slot before "More", so the button never ends up in its list.
    static func editIndex(teamCount: Int, barCapacity: Int?) -> Int {
        guard let barCapacity, teamCount + 1 > barCapacity else { return teamCount }
        return min(teamCount, max(0, barCapacity - 2))
    }
}

/// A favorite's crest as a tab item's image.
///
/// A tab item is a `UITabBarItem` underneath: SwiftUI takes one finished
/// image from its label, and a view that loads one later (`TeamLogo`,
/// `RemoteImage`) never reaches the bar. So the image is drawn here from
/// what is on hand: the crest stored in `LogoStore` (for the scheme's
/// variant, else the default one), the bundled asset, or the team's
/// `MonogramTeam` badge, with the sport's symbol as a last resort. `Home`
/// fetches missing crests into `LogoStore` (`prefetch`) and redraws the items
/// as they land.
///
/// Drawn at a fixed tab-icon size and kept in full colour
/// (`.alwaysOriginal`): a template-rendered crest would be a flat
/// silhouette.
@MainActor
enum TabCrest {
    /// About a standard tab bar icon.
    static let size: CGFloat = 28

    /// Crests already drawn, by team, scale and source (`sourceKey`). An
    /// `NSCache`, so it gives memory back under pressure (A-17).
    private static let drawn: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    /// The variant for the colour scheme, as `TeamLogo` picks it.
    static func variant(for team: TeamRef, dark: Bool) -> LogoVariant {
        dark && LogoStore.sourceURL(for: team, variant: .dark) != nil ? .dark : .default
    }

    static func image(for team: TeamRef, dark: Bool, scale: CGFloat) -> UIImage {
        let source = source(for: team, dark: dark)
        let key = "\(team.id)|\(scale)|\(source.key)" as NSString
        if let image = drawn.object(forKey: key) {
            return image
        }
        let image = draw(source.image ?? monogram(team, scale: scale), scale: scale)
        drawn.setObject(image, forKey: key)
        return image
    }

    /// A key for a stored crest that changes whenever the file does: its
    /// path and modification date. Never the decoded image's identity,
    /// which `LogoStore`'s cache may evict and reallocate at the same
    /// address for another crest (A-17).
    nonisolated static func sourceKey(path: String, modified: Date?) -> String {
        "file:\(path)@\(modified?.timeIntervalSinceReferenceDate ?? 0)"
    }

    /// The stored crest's `sourceKey`.
    static func sourceKey(of file: URL) -> String {
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return sourceKey(path: file.path(percentEncoded: false), modified: modified)
    }

    /// What the tab item is drawn from — the stored crest for the scheme's
    /// variant, else the default one, else the bundled asset — and a key
    /// naming it. `nil` with `"monogram"` when there's none.
    private static func source(for team: TeamRef, dark: Bool) -> (image: UIImage?, key: String) {
        let wanted = variant(for: team, dark: dark)
        for candidate in [wanted, LogoVariant.default] {
            if let file = LogoStore.url(for: team, variant: candidate),
               let image = LogoStore.image(for: team, variant: candidate) {
                return (image, sourceKey(of: file))
            }
        }
        if let asset = team.logoAsset, let image = UIImage(named: asset) {
            return (image, "asset:\(asset)")
        }
        return (nil, "monogram")
    }

    /// Fetches the team's crest into `LogoStore` if it isn't there.
    /// Whether one newly arrived.
    static func prefetch(_ team: TeamRef, dark: Bool) async -> Bool {
        let variant = variant(for: team, dark: dark)
        guard LogoStore.url(for: team, variant: variant) == nil else { return false }
        return await LogoStore.prefetched(team, variant: variant)
    }

    /// The crest fitted into the icon's square, centred.
    private static func draw(_ source: UIImage?, scale: CGFloat) -> UIImage {
        let canvas = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            guard let source, source.size.width > 0, source.size.height > 0 else { return }
            let ratio = min(canvas.width / source.size.width, canvas.height / source.size.height)
            let fitted = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
            source.draw(in: CGRect(
                x: (canvas.width - fitted.width) / 2,
                y: (canvas.height - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            ))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// The badge `TeamLogo` draws for a team with no crest, else the
    /// sport's symbol.
    private static func monogram(_ team: TeamRef, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: MonogramTeam(team: team, size: size))
        renderer.scale = scale
        return renderer.uiImage
            ?? UIImage(systemName: TeamColors.symbolName(for: team.league.descriptor.kind))
    }
}

/// The crest in a team page's bar against the opaque team colour behind it
/// (B-4). `logoVariant` swaps in the dark crest on a dark bar only when the
/// feed has one, so a crest in the team's own colour, or a light crest on a
/// light bar, can blend into the bar. Such a crest is drawn on a small disc
/// in the bar's ink, like `MonogramTeam`'s badge.
@MainActor
enum BarCrest {
    /// Below this contrast between the crest's dominant colour and the bar,
    /// the crest gets its disc. Low on purpose: a crest is artwork with
    /// edges and detail of its own, not text, so only a near match fails.
    nonisolated static let minimumContrast = 2.0

    /// The crest's size on its disc, as a share of the disc.
    static let badgeInset: CGFloat = 0.72

    /// Dominant luminances measured so far, by `TabCrest.sourceKey`, so a
    /// changed file is measured again.
    private static let measured: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 100
        return cache
    }()

    /// Whether a crest whose dominant colour has `dominantLuminance` (WCAG
    /// relative luminance, 0 to 1) is too close to the bar's `heroHex` to
    /// read on it. Never for a colour that isn't a hex colour.
    nonisolated static func crestNeedsBadge(dominantLuminance: Double, heroHex: String) -> Bool {
        guard let bar = TeamColors.relativeLuminance(hex: heroHex) else { return false }
        let ratio = (max(dominantLuminance, bar) + 0.05) / (min(dominantLuminance, bar) + 0.05)
        return ratio < minimumContrast
    }

    /// Whether the stored crest `TeamLogo` draws for `team` in `variant`
    /// needs the disc on `heroHex`. No for a crest not stored yet: the
    /// monogram it falls back to is a badge already.
    static func needsBadge(team: TeamRef, variant: LogoVariant, onHex heroHex: String) -> Bool {
        guard let file = LogoStore.url(for: team, variant: variant) else { return false }
        let key = TabCrest.sourceKey(of: file) as NSString
        let luminance: Double
        if let cached = measured.object(forKey: key) {
            luminance = cached.doubleValue
        } else {
            guard let image = LogoStore.image(for: team, variant: variant),
                  let dominant = dominantLuminance(of: image)
            else { return false }
            measured.setObject(NSNumber(value: dominant), forKey: key)
            luminance = dominant
        }
        return crestNeedsBadge(dominantLuminance: luminance, heroHex: heroHex)
    }

    /// The relative luminance of the image's most common shade: its opaque
    /// pixels, sampled on a small grid, sorted into luminance bands, and
    /// the busiest band's mean. `nil` for an image with no opaque pixels.
    nonisolated static func dominantLuminance(of image: UIImage) -> Double? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bands = 8
        var counts = [Int](repeating: 0, count: bands)
        var sums = [Double](repeating: 0, count: bands)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            // Edges and shadows are mostly transparent: only the crest.
            guard alpha >= 0.5 else { continue }
            func channel(_ value: UInt8) -> Double {
                // Un-premultiplied, then linearized as WCAG does.
                let c = min(Double(value) / 255 / alpha, 1)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * channel(pixels[offset])
                + 0.7152 * channel(pixels[offset + 1])
                + 0.0722 * channel(pixels[offset + 2])
            let band = min(Int(luminance * Double(bands)), bands - 1)
            counts[band] += 1
            sums[band] += luminance
        }
        guard let busiest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[busiest] > 0 else {
            return nil
        }
        return sums[busiest] / Double(counts[busiest])
    }
}

/// iPad (B-14): on regular width the tab bar can become a sidebar, which
/// lists every favorite rather than a stretched phone bar, with "Teams" at
/// its foot. Compact width keeps the plain tab bar and its "More" item.
private struct HomeSidebar: ViewModifier {
    let isRegularWidth: Bool
    let openBrowser: @MainActor () -> Void

    func body(content: Content) -> some View {
        if isRegularWidth {
            content
                .tabViewStyle(.sidebarAdaptable)
                .tabViewSidebarFooter {
                    Button {
                        openBrowser()
                    } label: {
                        Label("Teams", systemImage: "plus.circle")
                    }
                    .accessibilityLabel(Text("Add or Edit Teams"))
                    .accessibilityIdentifier("teamPicker.sidebarEdit")
                }
        } else {
            content
        }
    }
}

#Preview {
    Home(deepLinkedTeamID: .constant(nil))
}
