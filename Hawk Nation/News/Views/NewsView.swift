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
    @Environment(\.containerSize) private var containerSize

    var body: some View {
        HStack(alignment: .top) {
            LoadingView()
                .frame(width: 125, height: 125)
                .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                LoadingView()
                    .frame(width: 40, height: 10)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(width: containerSize.width - 225, height: 15)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(height: 15)
                LoadingView()
                    .frame(width: 40, height: 10)
            }
            .frame(height: 125, alignment: .leading)
        }
        .frame(width: containerSize.width - 30, height: 125, alignment: .leading)
    }
}

/// One article in a team's news feed: thumbnail, outlet, headline, summary and
/// date.
struct NewsView: View {
    var article: News

    @Environment(\.containerSize) private var containerSize

    var body: some View {
        HStack(alignment: .top) {
            ZStack {
                RemoteImage(url: article.urlToImage) {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(Color(uiColor: .systemGray))
                        .opacity(0.8)
                }
                .scaledToFill()
                .frame(width: 125, height: 125)

                // Darkens the foot of the thumbnail so light images still
                // separate from the card beneath them.
                Rectangle()
                    .foregroundStyle(.clear)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 125, height: 125)
                    .opacity(0.2)
            }
            .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                Text(article.source)
                    .foregroundStyle(.primary)
                    .opacity(0.5)
                    .font(.system(size: 10))
                Text(article.title)
                    .foregroundStyle(.primary)
                    .font(.system(size: 15))
                    .fontWeight(.bold)
                Text(article.articleDescription ?? "")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
                Text(article.publishedAt, format: .dateTime.month().day().year())
                    .foregroundStyle(.primary)
                    .opacity(0.5)
                    .font(.system(size: 10))
            }
            .frame(height: 125, alignment: .leading)
        }
        .frame(width: containerSize.width - 30, height: 125, alignment: .leading)
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
