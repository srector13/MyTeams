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
/// Commons is asked only once ESPN's image has failed, or the feed had
/// none, and only while the view is on screen. The photo fills the same
/// frame when it arrives, so nothing moves. Long-pressing a Commons photo
/// shows its credit and licence.
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
                Image(uiImage: commonsImage)
                    .resizable()
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
        // Ask Commons once ESPN has failed; draw its photo once known.
        .task(id: FallbackState(needsFallback: needsFallback, photo: photo)) {
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
        .contextMenu {
            if commonsImage != nil, let photo {
                Text(photo.creditLine)
                if let page = photo.descriptionPageURL {
                    Link(destination: page) {
                        Label("View on Wikimedia Commons", systemImage: "safari")
                    }
                }
            }
        }
    }

    private struct FallbackState: Equatable {
        var needsFallback: Bool
        var photo: CommonsPhoto?
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
                    ForEach(store.shownThisSession, id: \.self) { photo in
                        PhotoCreditRow(photo: photo)
                    }
                }
            } footer: {
                Text("Player photos come from ESPN. Where ESPN has none, the photo is from Wikimedia Commons, found through Wikidata, and is used under the licence shown.")
            }
        }
        .navigationTitle("Photo Credits")
        .navigationBarTitleDisplayMode(.inline)
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
