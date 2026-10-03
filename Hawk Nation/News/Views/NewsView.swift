//
//  NewsView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The placeholder card shown in the news feed before it has loaded.
struct LoadingNewsView: View {
    @ScaledMetric(relativeTo: .body) private var thumbnailSize = NewsView.baseThumbnailSize

    var body: some View {
        HStack(alignment: .top) {
            LoadingView()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                LoadingView()
                    .frame(width: 40, height: 10)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(height: 15)
                    .padding(.trailing, 40)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(width: 40, height: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One article in a team's news feed: thumbnail, outlet, headline, summary and
/// date.
///
/// The row sizes to its text (N-1). At accessibility text sizes the
/// thumbnail moves above the text, which then gets the row's full width.
struct NewsView: View {
    /// The thumbnail's side at the default text size, in points.
    static let baseThumbnailSize: CGFloat = 125

    var article: News

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var thumbnailSize = NewsView.baseThumbnailSize

    private var stacksThumbnail: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = stacksThumbnail
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout(alignment: .top))

        layout {
            // A clear frame carries the size, so a filled image can't widen
            // the row; the image and its shade are drawn over it.
            Color.clear
                .frame(width: stacksThumbnail ? nil : thumbnailSize, height: thumbnailSize)
                .frame(maxWidth: stacksThumbnail ? CGFloat.infinity : nil)
                .overlay {
                    RemoteImage(url: article.urlToImage) {
                        RoundedRectangle(cornerRadius: 20)
                            .foregroundStyle(Color(uiColor: .systemGray))
                            .opacity(0.8)
                    }
                    .scaledToFill()
                }
                // Darkens the foot of the thumbnail so light images still
                // separate from the card beneath them.
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(0.2)
                }
                .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                Text(article.source)
                    .foregroundStyle(.primary)
                    .opacity(0.5)
                    .font(.caption2)
                Text(article.title)
                    .foregroundStyle(.primary)
                    .font(Theme.Typography.cardTitle)
                Text(article.articleDescription ?? "")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .lineLimit(3)
                Text(article.publishedAt, format: .dateTime.month().day().year())
                    .foregroundStyle(.primary)
                    .opacity(0.5)
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NewsView(
        article: News(
            author: "Motolani Alake",
            title: "Shakira celebrates Africa at the 2020 Super Bowl - Pulse Nigeria",
            articleDescription: "This edition was the 54th in history and it was decided when Kansas City Chiefs defeated the San Francisco 49ers, 31–20",
            url: URL(string: "https://www.pulse.ng")!,
            urlToImage: nil,
            publishedAt: .now,
            content: "testing",
            source: "ESPN"
        )
    )
    .environment(\.containerSize, CGSize(width: 390, height: 844))
}
