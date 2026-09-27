//
//  NewsDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SafariServices

/// An article opened from the news feed: a compact bar naming the outlet and
/// byline, with the page in Safari below it.
///
/// The bar sits above the Safari view, never over it — Apple requires that
/// nothing hide or obscure `SFSafariViewController`'s content or controls.
struct NewsDetailView: View {
    var article: News
    var color: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if SafariView.canDisplay(article.url) {
                SafariView(url: article.url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    "Can't Open This Article",
                    systemImage: "safari",
                    description: Text("The link isn't a web page.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(article.source)
                    .font(.headline)
                if let author = article.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal)
        .frame(height: 44)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    /// Whether `SFSafariViewController` can load `url`: it throws on any
    /// scheme but http and https.
    static func canDisplay(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    }
}
