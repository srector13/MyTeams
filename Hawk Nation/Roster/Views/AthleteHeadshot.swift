//
//  AthleteHeadshot.swift
//  myTeams
//
//  Created by Stephen Rector on 10/6/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

/// An athlete's photo: ESPN's headshot, else their Wikimedia Commons photo
/// found through Wikidata (`WikidataHeadshotStore`), else `placeholder` —
/// the card's blank or the sheet's monogram, as before.
///
/// A team page has usually asked Wikidata about its whole roster already
/// (`WikidataHeadshotStore.prefetch(espnIDs:league:)`), so the photo is
/// known by the time ESPN's image fails. Elsewhere Commons is asked only
/// once ESPN's image has failed, or the feed had none, and only while the
/// view is on screen. The photo fills the same frame when it arrives, so
/// nothing moves; it never waits for its licence. Long-pressing a Commons
/// photo shows its credit and licence, fetching them then.
struct AthleteHeadshot<Placeholder: View>: View {
    private let espnURL: URL?
    /// Whether the feed gave ESPN's generic silhouette (`missingHeadshot`):
    /// it is still drawn, but counts as no headshot.
    private let espnIsSilhouette: Bool
    private let espnID: String
    private let league: LeagueID?
    private let showsProgress: Bool
    private let placeholder: Placeholder

    /// Whether ESPN's image failed to load, or there was no URL.
    @State private var espnFailed = false
    @State private var commonsImage: UIImage?

    private var store: WikidataHeadshotStore { .shared }

    /// - Parameters:
    ///   - photo: the roster feed's headshot URL.
    ///   - espnID: the athlete's ESPN id (`RosterPlayer.playerID`).
    ///   - league: the roster's league; `nil` never looks on Commons.
    init(
        photo: String,
        espnID: String,
        league: LeagueID?,
        showsProgress: Bool = true,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.espnURL = URL(string: photo)
        self.espnIsSilhouette = photo == missingHeadshot
        self.espnID = espnID
        self.league = league
        self.showsProgress = showsProgress
        self.placeholder = placeholder()
    }

    /// Whether ESPN has no headshot of the athlete, so Commons is asked.
    private var needsFallback: Bool { espnIsSilhouette || espnFailed }

    /// The Commons photo, once the store has one for this athlete.
    private var commonsPhoto: CommonsPhoto? {
        guard needsFallback, let league else { return nil }
        return store.photo(espnID: espnID, league: league)
    }

    var body: some View {
        let photo = commonsPhoto
        Group {
            if let commonsImage {
                if let photo, let league {
                    CommonsHeadshotImage(image: commonsImage, photo: photo, espnID: espnID, league: league)
                } else {
                    Image(uiImage: commonsImage)
                        .resizable()
                }
            } else if espnFailed {
                placeholder
            } else {
                RemoteImage(url: espnURL, showsProgress: showsProgress, onLoad: { loaded in
                    if !loaded { espnFailed = true }
                }) {
                    placeholder
                }
            }
        }
        // Ask Commons once ESPN has failed; draw its photo once known. Keyed
        // on the image, not the whole photo, so a licence arriving later
        // does not load it again.
        .task(id: FallbackState(needsFallback: needsFallback, imageURL: photo?.imageURL)) {
            guard needsFallback, let league else { return }
            guard let photo else {
                store.request(espnID: espnID, league: league)
                return
            }
            guard let url = photo.imageURL,
                  let image = await CommonsImageLoader.shared.image(for: url),
                  !Task.isCancelled
            else { return }
            commonsImage = image
            store.noteShown(photo)
        }
    }

    private struct FallbackState: Equatable {
        var needsFallback: Bool
        var imageURL: URL?
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
    init<Player: RosterPlayer>(
        _ player: Player,
        league: LeagueID?,
        showsProgress: Bool = true,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            photo: player.photo,
            espnID: player.playerID,
            league: league,
            showsProgress: showsProgress,
            placeholder: placeholder
        )
    }
}

// MARK: - Credits

/// Settings → Photo Credits: every Commons photo shown this session, with
/// its author and licence, linking to its description page.
struct PhotoCreditsView: View {
    private var store: WikidataHeadshotStore { .shared }

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
        }
        .navigationTitle("Photo Credits")
        .navigationBarTitleDisplayMode(.inline)
        // Licences are fetched only for credits someone reads.
        .task { store.requestLicenses(for: store.shownThisSession) }
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
