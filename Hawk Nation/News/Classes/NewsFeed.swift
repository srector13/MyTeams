//
//  NewsFeed.swift
//  myTeams
//
//  Created by Stephen Rector on 2/7/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation

/// The NewsAPI queries behind each team's news feed.
enum NewsFeed {
    /// The NewsAPI key, read from the `NEWS_API_KEY` entry in Info.plist so it
    /// can be supplied per build configuration rather than compiled in.
    private static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "NEWS_API_KEY") as? String ?? ""
    }

    private static func feed(query: String) -> String {
        "https://newsapi.org/v2/everything?\(query)&sortBy=publishedAt&apiKey=\(apiKey)"
    }

    /// The feed for `team`: its catalogued query, or else a search for its
    /// full name.
    static func url(for team: TeamRef) -> String {
        feed(query: team.newsQuery ?? defaultQuery(for: team))
    }

    private static func defaultQuery(for team: TeamRef) -> String {
        let phrase = "\"\(team.displayName)\""
        return "q=" + (phrase.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    }
}
