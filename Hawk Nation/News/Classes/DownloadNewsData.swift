//
//  DownloadNewsData.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/7/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct News: Identifiable, Equatable, Hashable, Sendable {
    var id = UUID()
    let author: String?
    let title: String
    let articleDescription: String?
    let url: URL
    let urlToImage: URL?
    let publishedAt: Date
    let content: String?
    let source: String
}

/// Parses the `publishedAt` timestamps NewsAPI returns, e.g.
/// `2021-01-18T23:00:00Z`.
private let publishedAtFormat = Date.ISO8601FormatStyle()

/// Loads a NewsAPI feed and returns its articles in the order the service
/// ranked them.
///
/// An article whose title has already been seen is dropped: the same story is
/// frequently syndicated across the outlets these feeds draw from.
func downloadNewsData(queryURL: String) async -> [News] {
    let json = await HTTPClient.json(from: queryURL)
    var articles: [News] = []

    for (_, subJson): (String, JSON) in json["articles"] {
        // An article with no readable link cannot be opened, and one with no
        // timestamp cannot be placed in the feed, so skip either.
        guard let url = URL(string: subJson["url"].stringValue),
              let publishedAt = try? publishedAtFormat.parse(subJson["publishedAt"].stringValue)
        else { continue }

        let article = News(
            author: subJson["author"].stringValue,
            title: subJson["title"].stringValue,
            articleDescription: subJson["description"].stringValue,
            url: url,
            urlToImage: URL(string: subJson["urlToImage"].stringValue),
            publishedAt: publishedAt,
            content: subJson["content"].stringValue,
            source: subJson["source"]["name"].stringValue
        )

        if !articles.contains(where: { $0.title == article.title }) {
            articles.append(article)
        }
    }

    return articles
}
