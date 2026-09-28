//
//  DownloadNewsData.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/7/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

struct News: Identifiable, Equatable, Hashable, Sendable {
    let author: String?
    let title: String
    let articleDescription: String?
    let url: URL
    let urlToImage: URL?
    let publishedAt: Date
    let content: String?
    let source: String

    /// An article is identified by its link, which stays the same however
    /// often the feed is fetched.
    var id: String { url.absoluteString }
}

/// Parses ESPN's `published` timestamps, e.g. `2026-09-27T18:50:54Z`.
private let publishedAtFormat = Date.ISO8601FormatStyle()

/// Loads a team's ESPN news feed (`TeamRef.newsURL`) and returns its articles
/// in feed order, which is newest first.
///
/// An article whose title or link has already been seen is dropped: ESPN can
/// list the same story more than once.
func downloadNewsData(queryURL: String) async -> Result<[News], NetworkError> {
    await HTTPClient.shared.fetch(queryURL).map(empty: [], parseNews(from:))
}

/// Builds the article list from an ESPN news document. See `downloadNewsData`.
///
/// Each of `articles[]` maps as `headline` → `title`, `description` →
/// `articleDescription`, `byline` → `author`, `links.web.href` → `url`, the
/// first of `images[].url` → `urlToImage` and `published` → `publishedAt`.
/// ESPN leaves `source` and `author` null, so every article is credited to
/// ESPN, and there is no article body for `content`. Stories, headline news
/// and video clips are all kept.
func parseNews(from json: JSON) -> [News] {
    var articles: [News] = []

    for (_, subJson): (String, JSON) in json["articles"] {
        // An article needs a headline to show, a timestamp to place it in the
        // feed, and an https link: SFSafariViewController throws on any
        // scheme but http(s), and the feed's few plain-http links are game
        // previews rather than stories.
        guard let title = nonEmpty(subJson["headline"].string),
              let url = URL(string: subJson["links"]["web"]["href"].stringValue),
              url.scheme?.lowercased() == "https",
              let publishedAt = try? publishedAtFormat.parse(subJson["published"].stringValue)
        else { continue }

        let article = News(
            author: nonEmpty(subJson["byline"].string),
            title: title,
            articleDescription: nonEmpty(subJson["description"].string),
            url: url,
            urlToImage: URL(string: subJson["images"][0]["url"].stringValue),
            publishedAt: publishedAt,
            content: nil,
            source: "ESPN"
        )

        // Matching links are dropped too: the link is the article's `id`.
        if !articles.contains(where: { $0.title == article.title || $0.url == article.url }) {
            articles.append(article)
        }
    }

    return articles
}

/// `text`, or `nil` when it is missing or blank.
private func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return text
}
