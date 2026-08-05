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

    static var jayhawks: String {
        feed(
            query: "q=+jayhawks+basketball&qInTitle=kansas"
                + "&domains=espn.com,bleacherreport.com,foxsport.com"
        )
    }

    static var chiefs: String {
        feed(
            query: "qInTitle=+chiefs"
                + "&domains=espn.com,bleacherreport.com,foxsport.com,nfl.com"
        )
    }

    static var royals: String {
        feed(
            query: "q=+royals+kansas+city"
                + "&domains=espn.com,bleacherreport.com,foxsport.com"
        )
    }

    static var sporting: String {
        feed(query: "q=+sporting+kc+mls")
    }
}
