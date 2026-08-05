//
//  DownloadNewsData.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/7/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import Foundation
import Alamofire
import SwiftyJSON

struct News: Identifiable, Equatable {
    var id = UUID()
    //public let source: NewsSource
    public let author: String?
    public let title: String
    public let articleDescription: String?
    public let url: URL
    public let urlToImage: URL?
    public let publishedAt: Date
    public let content: String?
    public let source: String
}

func downloadNewsData(queryURL: String, completion: @escaping ([News]) -> Void) {
    var returnNews = [News]()
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)

            for (_, subJson):(String, JSON) in json["articles"] {
                
                _ = ""
                var newsSource = ""
                var newsAuthor = ""
                var newsTitle = ""
                var newsDescription = ""
                var newsURL = URL(string: "https://www.google.com")
                var newsURLToImage = URL(string: "https://www.google.com")
                var newsPublishedAt = Date()
                var newsContent = ""
                
                newsAuthor = subJson["author"].stringValue
                newsSource = subJson["source"]["name"].stringValue
                newsTitle = subJson["title"].stringValue
                newsDescription = subJson["description"].stringValue
                newsURL = URL(string: subJson["url"].stringValue)
                newsURLToImage = URL(string: subJson["urlToImage"].stringValue)
                newsContent = subJson["content"].stringValue
                
                    
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                
                let isoFormatter = ISO8601DateFormatter()
                    
                newsPublishedAt = isoFormatter.date(from: subJson["publishedAt"].stringValue)!
                
                let tempArticle = News(author: newsAuthor, title: newsTitle, articleDescription: newsDescription, url: newsURL!, urlToImage: newsURLToImage, publishedAt: newsPublishedAt, content: newsContent, source: newsSource)
                
                if(!returnNews.contains(where: {$0.title == tempArticle.title})) {
                    returnNews.append(tempArticle)
                }
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnNews)
        }
    }
    }
}
