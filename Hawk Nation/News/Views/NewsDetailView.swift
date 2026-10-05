//
//  NewsDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SafariServices

/// An article opened from the news feed: the page in Safari, filling the
/// sheet, with Safari's own bars and Done button as its only chrome and its
/// controls in the team's colour.
///
/// Nothing is drawn over the Safari view: Apple requires that nothing hide
/// or obscure `SFSafariViewController`'s content or controls.
struct NewsDetailView: View {
    var article: News
    var color: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if SafariView.canDisplay(article.url) {
            SafariView(url: article.url, tint: color) {
                dismiss()
            }
            // Safari insets its own content and bars.
            .ignoresSafeArea()
            // Full height: a hand-off to Safari, whose page and bars need
            // the room (X-9).
            .presentationDetents([.large])
        } else {
            ContentUnavailableView {
                Label {
                    Text("Can't Open This Article")
                } icon: {
                    // Asset-catalog appearances pick the light/dark art.
                    Image("myTeamsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: BrandLogo.inline)
                        .accessibilityHidden(true)
                }
            } description: {
                Text("The link isn't a web page.")
            }
            // No Safari, so no Done: close it like the other sheets.
            .overlay(alignment: .topTrailing) {
                SheetCloseButton()
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("newsDetail.close")
                    .padding(Theme.Spacing.m)
            }
            // A short message: the medium detent fits it, and large
            // gives accessibility text sizes room (X-9).
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    /// Safari's control tint, e.g. the team's colour; the system's when nil.
    var tint: Color?
    /// Called when the reader taps Safari's Done button.
    var onDone: (() -> Void)?

    /// Whether `SFSafariViewController` can load `url`: it throws on any
    /// scheme but http and https.
    static func canDisplay(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.delegate = context.coordinator
        safari.preferredControlTintColor = tint.map { UIColor($0) }
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        context.coordinator.onDone = onDone
        uiViewController.preferredControlTintColor = tint.map { UIColor($0) }
    }

    /// Forwards Done to SwiftUI. Embedded in a sheet rather than presented
    /// itself, Safari can't close the sheet on its own terms: the sheet's
    /// `dismiss` does, which also clears the binding that presented it.
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onDone: (() -> Void)?

        init(onDone: (() -> Void)?) {
            self.onDone = onDone
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDone?()
        }
    }
}
