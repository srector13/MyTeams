//
//  AthleteHeadshot.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

/// An athlete's photo: ESPN's headshot, else the first photo the sources
/// after it have (`HeadshotTiers`), else ESPN's grey silhouette, or
/// `placeholder` (the app's own silhouette, `Image("blank")`) where ESPN's
/// image would not load at all.
///
/// For soccer the sources are, in order: FotMob, while the reader has
/// turned that experiment on (`FotMobHeadshotStore`); API-Football, with
/// the reader's own key (`ApiFootballHeadshotStore`); TheSportsDB, unless
/// turned off (`TheSportsDBHeadshotStore`); then Wikimedia Commons, found
/// through Wikidata (`WikidataHeadshotStore`). FotMob and TheSportsDB look
/// players up by name, number and club, so they are asked only when the
/// view is given its `team`. Every other sport has Commons alone.
///
/// The sources are asked only once ESPN's image has failed, or the feed
/// had none, only while the view is on screen, and only as far as the
/// first with a photo. One that has not answered holds back the rest for
/// `HeadshotTiers.grace`; past it the next draws, and the earlier one's
/// photo replaces it if it comes. A team page has usually asked Wikidata
/// about its whole roster already (`WikidataHeadshotStore.prefetch(espnIDs:league:)`).
/// The photo fills the same frame when it arrives, so nothing moves; it
/// never waits for its licence. Long-pressing a photo shows its credit:
/// for a Commons photo, its licence too, fetched then.
struct AthleteHeadshot<Placeholder: View>: View {
    private let espnURL: URL?
    /// Whether the feed gave ESPN's generic silhouette (`missingHeadshot`):
    /// it is still drawn, but counts as no headshot.
    private let espnIsSilhouette: Bool
    private let espnID: String
    private let league: LeagueID?
    /// The player's name, number and club, for the soccer sources that
    /// look them up by those; `nil` without a team, or outside soccer.
    private let query: SoccerHeadshotQuery?
    private let showsProgress: Bool
    private let placeholder: Placeholder

    /// Whether ESPN's image failed to load, or there was no URL.
    @State private var espnFailed = false
    /// The fallback photo drawn, once loaded.
    @State private var loaded: LoadedPhoto?
    /// Photos that would not load here — FotMob's 403 for a player it has
    /// no photo of, say: their source counts as having none.
    @State private var failedURLs: Set<URL> = []
    /// Whether `HeadshotTiers.grace` has passed since ESPN failed: past it,
    /// a source's silence counts as no photo.
    @State private var graceElapsed = false

    /// Settings → Advanced → Soccer Photos, read here so a change applies
    /// at once.
    @AppStorage(SoccerPhotoSettings.theSportsDBKey) private var theSportsDBEnabled = SoccerPhotoSettings.theSportsDBDefault
    @AppStorage(SoccerPhotoSettings.fotMobKey) private var fotMobEnabled = SoccerPhotoSettings.fotMobDefault

    private var store: WikidataHeadshotStore { .shared }

    /// - Parameters:
    ///   - photo: the roster feed's headshot URL.
    ///   - espnID: the athlete's ESPN id (`RosterPlayer.playerID`).
    ///   - league: the roster's league; `nil` never looks on Commons.
    ///   - name: the athlete's name, for FotMob and TheSportsDB.
    ///   - number: their shirt number, likewise.
    ///   - team: the roster's club; `nil` never asks FotMob or TheSportsDB.
    init(
        photo: String,
        espnID: String,
        league: LeagueID?,
        name: String = "",
        number: String = "",
        team: TeamRef? = nil,
        showsProgress: Bool = true,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.espnURL = URL(string: photo)
        self.espnIsSilhouette = photo == missingHeadshot
        self.espnID = espnID
        self.league = league
        if let team, team.league.sport == "soccer", !name.isEmpty {
            self.query = SoccerHeadshotQuery(espnID: espnID, name: name, number: number, team: team)
        } else {
            self.query = nil
        }
        self.showsProgress = showsProgress
        self.placeholder = placeholder()
    }

    /// Whether ESPN has no headshot of the athlete, so the other sources
    /// are asked.
    private var needsFallback: Bool { espnIsSilhouette || espnFailed }

    private var order: [HeadshotSource] { HeadshotTiers.order(for: league) }

    /// What each source has said of the athlete; nothing while ESPN's
    /// headshot stands. A photo that would not load counts as none.
    private var tierStates: [HeadshotSource: HeadshotTierState] {
        guard needsFallback else { return [:] }
        var states: [HeadshotSource: HeadshotTierState] = [.commons: commonsState]
        if league?.sport == "soccer" {
            states[.apiFootball] = apiFootballState
            if let query {
                states[.fotMob] = fotMobEnabled ? FotMobHeadshotStore.shared.state(for: query) : .off
                states[.theSportsDB] = theSportsDBEnabled ? TheSportsDBHeadshotStore.shared.state(for: query) : .off
            }
        }
        for (source, state) in states {
            if case .photo(let url) = state, failedURLs.contains(url) {
                states[source] = .noPhoto
            }
        }
        return states
    }

    /// Commons: its photo once Wikidata has given one; none once it has
    /// answered without, or while it is backing off; else pending.
    private var commonsState: HeadshotTierState {
        guard let league, WikidataHeadshots.property(for: league) != nil,
              WikidataHeadshots.isESPNAthleteID(espnID)
        else { return .off }
        if let photo = store.photo(espnID: espnID, league: league) {
            guard let url = photo.imageURL else { return .noPhoto }
            return .photo(url)
        }
        return store.lacksPhoto(espnID: espnID, league: league, waited: false) ? .noPhoto : .pending
    }

    /// API-Football: its photo once a sweep has matched one, while the
    /// reader's key is in use; else none. It has no "pending": a sweep
    /// that finds the player later replaces a later tier's photo.
    private var apiFootballState: HeadshotTierState {
        guard let league, let photo = ApiFootballHeadshotStore.shared.photo(espnID: espnID, league: league),
              let url = photo.imageURL
        else { return .noPhoto }
        return .photo(url)
    }

    var body: some View {
        let states = tierStates
        let choice = HeadshotTiers.choose(order: order, states: states, graceElapsed: graceElapsed)
        let asked = needsFallback
            ? HeadshotTiers.sourcesToAsk(order: order, states: states, graceElapsed: graceElapsed)
            : []
        // A source turned off, or whose key went, takes its photo with it.
        let drawn = loaded.flatMap { isCurrent($0, in: states) ? $0 : nil }
        Group {
            if let drawn {
                fallbackImage(drawn)
            } else if espnFailed {
                placeholder
            } else {
                RemoteImage(url: espnURL, showsProgress: showsProgress, onLoad: { didLoad in
                    if !didLoad { espnFailed = true }
                }) {
                    placeholder
                }
            }
        }
        // The grace: a later tier need not wait on a source that is slow,
        // backing off or never answers.
        .task(id: needsFallback) {
            guard needsFallback else {
                graceElapsed = false
                return
            }
            do {
                try await Task.sleep(for: HeadshotTiers.grace)
            } catch {
                return
            }
            graceElapsed = true
        }
        // Ask Commons and FotMob as the walk reaches them. Both skip what
        // they already know: FotMob looks up the club once for the roster.
        .task(id: asked) {
            if asked.contains(.commons), let league, store.photo(espnID: espnID, league: league) == nil {
                store.request(espnID: espnID, league: league)
            }
            if asked.contains(.fotMob), let query {
                FotMobHeadshotStore.shared.request(query)
            }
        }
        // TheSportsDB's queue holds the player only while they are on
        // screen and still need it, so a row scrolled past costs nothing.
        .task(id: asked.contains(.theSportsDB)) {
            guard asked.contains(.theSportsDB), let query else { return }
            let sportsDB = TheSportsDBHeadshotStore.shared
            sportsDB.request(query)
            try? await Task.sleep(for: .seconds(24 * 60 * 60))
            sportsDB.withdraw(query)
        }
        // Load the chosen photo. Keyed on its URL, so a Commons licence
        // arriving later does not load it again; the photo drawn stays
        // until its replacement has loaded.
        .task(id: choice) {
            guard case .photo(let source, let url) = choice else { return }
            if let loaded, loaded.url == url { return }
            let image = await Self.image(for: url, from: source)
            guard !Task.isCancelled else { return }
            guard let image else {
                failedURLs.insert(url)
                return
            }
            loaded = LoadedPhoto(source: source, url: url, image: image)
            noteShown(source)
        }
    }

    /// Whether `loaded` is still its source's photo.
    private func isCurrent(_ loaded: LoadedPhoto, in states: [HeadshotSource: HeadshotTierState]) -> Bool {
        guard case .photo(let url)? = states[loaded.source] else { return false }
        return url == loaded.url
    }

    /// A fallback photo, with its credit on a long-press.
    @ViewBuilder
    private func fallbackImage(_ loaded: LoadedPhoto) -> some View {
        switch loaded.source {
        case .commons:
            if let league, let photo = store.photo(espnID: espnID, league: league) {
                CommonsHeadshotImage(image: loaded.image, photo: photo, espnID: espnID, league: league)
            } else {
                Image(uiImage: loaded.image)
                    .resizable()
            }
        case .apiFootball:
            CreditedHeadshotImage(image: loaded.image, credit: ApiFootballPhoto.creditLine)
        case .fotMob:
            CreditedHeadshotImage(image: loaded.image, credit: FotMob.creditLine)
        case .theSportsDB:
            CreditedHeadshotImage(image: loaded.image, credit: TheSportsDB.creditLine)
        }
    }

    /// Loads `url` through `source`'s own image loader.
    private static func image(for url: URL, from source: HeadshotSource) async -> UIImage? {
        switch source {
        case .commons:
            return await CommonsImageLoader.shared.image(for: url)
        case .apiFootball:
            return await ApiFootballImageLoader.shared.image(for: url)
        case .fotMob, .theSportsDB:
            return await SoccerPhotoImageLoader.shared.image(for: url)
        }
    }

    /// Records the photo drawn for Settings → Photo Credits.
    private func noteShown(_ source: HeadshotSource) {
        switch source {
        case .commons:
            if let league, let photo = store.photo(espnID: espnID, league: league) {
                store.noteShown(photo)
            }
        case .apiFootball:
            if let league, let photo = ApiFootballHeadshotStore.shared.photo(espnID: espnID, league: league) {
                ApiFootballHeadshotStore.shared.noteShown(photo)
            }
        case .fotMob:
            if let query { FotMobHeadshotStore.shared.noteShown(query) }
        case .theSportsDB:
            if let query { TheSportsDBHeadshotStore.shared.noteShown(query) }
        }
    }

    /// A fallback photo once loaded, and where it came from.
    private struct LoadedPhoto {
        var source: HeadshotSource
        var url: URL
        var image: UIImage
    }
}

/// A photo from API-Football, FotMob or TheSportsDB drawn in place of
/// ESPN's. Long-pressing it shows its credit.
private struct CreditedHeadshotImage: View {
    let image: UIImage
    let credit: String

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .contextMenu {
                Text(credit)
            }
    }
}

/// A Commons photo drawn in place of ESPN's. Long-pressing it shows it
/// larger with its credit, and only then asks Commons for the licence.
private struct CommonsHeadshotImage: View {
    let image: UIImage
    let photo: CommonsPhoto
    let espnID: String
    let league: LeagueID

    private var store: WikidataHeadshotStore { .shared }

    /// The photo as the store has it now, its licence included once fetched.
    private var current: CommonsPhoto {
        store.photo(espnID: espnID, league: league) ?? photo
    }

    var body: some View {
        let photo = current
        Image(uiImage: image)
            .resizable()
            .contextMenu {
                Text(photo.creditLine)
                if let page = photo.descriptionPageURL {
                    Link(destination: page) {
                        Label("View on Wikimedia Commons", systemImage: "safari")
                    }
                }
            } preview: {
                CommonsCreditPreview(image: image, espnID: espnID, league: league, photo: photo)
            }
    }
}

/// The long-press preview: the photo with its credit, which fills in when
/// the licence arrives.
private struct CommonsCreditPreview: View {
    let image: UIImage
    let espnID: String
    let league: LeagueID
    let photo: CommonsPhoto

    private var store: WikidataHeadshotStore { .shared }

    var body: some View {
        let photo = store.photo(espnID: espnID, league: league) ?? self.photo
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 250)
            Text(photo.creditLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 250, alignment: .leading)
        }
        .padding(Theme.Spacing.m)
        // Someone is looking at the credit: now it is worth asking for.
        .task { store.requestLicenses(for: [photo]) }
    }
}

extension AthleteHeadshot {
    /// A roster player's headshot.
    /// - Parameter team: the roster's club, for FotMob and TheSportsDB,
    ///   which look the player up by name, number and club.
    init<Player: RosterPlayer>(
        _ player: Player,
        league: LeagueID?,
        team: TeamRef? = nil,
        showsProgress: Bool = true,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            photo: player.photo,
            espnID: player.playerID,
            league: league,
            name: player.name,
            number: player.number,
            team: team,
            showsProgress: showsProgress,
            placeholder: placeholder
        )
    }
}

// MARK: - Credits

/// Settings → Photo Credits: every Commons photo shown this session, with
/// its author and licence, linking to its description page; then every
/// API-Football, FotMob and TheSportsDB photo shown.
struct PhotoCreditsView: View {
    private var store: WikidataHeadshotStore { .shared }
    private var apiFootball: ApiFootballHeadshotStore { .shared }
    private var fotMob: FotMobHeadshotStore { .shared }
    private var theSportsDB: TheSportsDBHeadshotStore { .shared }

    var body: some View {
        List {
            Section {
                if store.shownThisSession.isEmpty {
                    Text("No Wikimedia Commons photos shown yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.shownThisSession, id: \.fileTitle) { photo in
                        PhotoCreditRow(photo: photo)
                    }
                }
            } footer: {
                Text("Player photos come from ESPN. Where ESPN has none, the photo is from Wikimedia Commons, found through Wikidata, and is used under the licence shown.")
            }

            if !apiFootball.shownThisSession.isEmpty {
                Section {
                    ForEach(apiFootball.shownThisSession, id: \.playerID) { photo in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(photo.name)
                                .font(.subheadline)
                            Text(ApiFootballPhoto.creditLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("API-Football")
                } footer: {
                    Text("Where ESPN has no soccer player's photo, it may be from API-Football / API-Sports, found with your own API key.")
                }
            }

            if !fotMob.shownThisSession.isEmpty {
                Section {
                    ForEach(fotMob.shownThisSession, id: \.id) { member in
                        SourceCreditRow(name: member.name, credit: FotMob.creditLine)
                    }
                } header: {
                    Text("FotMob")
                } footer: {
                    Text("With FotMob (Experimental) on in Settings → Advanced, a soccer player's photo may come from FotMob, through its unofficial public endpoints. The photos belong to their owners.")
                }
            }

            if !theSportsDB.shownThisSession.isEmpty {
                Section {
                    ForEach(theSportsDB.shownThisSession, id: \.playerID) { photo in
                        SourceCreditRow(name: photo.name, credit: TheSportsDB.creditLine)
                    }
                } header: {
                    Text("TheSportsDB")
                } footer: {
                    Text("Where ESPN has no soccer player's photo, it may be from TheSportsDB, a free, community-run sports database. The photos belong to their owners.")
                }
            }
        }
        .navigationTitle("Photo Credits")
        .navigationBarTitleDisplayMode(.inline)
        // Licences are fetched only for credits someone reads.
        .task { store.requestLicenses(for: store.shownThisSession) }
    }
}

/// A player's name over the credit of the source their photo came from.
private struct SourceCreditRow: View {
    let name: String
    let credit: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(name)
                .font(.subheadline)
            Text(credit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PhotoCreditRow: View {
    let photo: CommonsPhoto

    var body: some View {
        let label = VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(photo.displayTitle)
                .font(.subheadline)
            Text(photo.creditLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let page = photo.descriptionPageURL {
            Link(destination: page) { label }
                .accessibilityHint("Opens the photo's page on Wikimedia Commons.")
        } else {
            label
        }
    }
}
