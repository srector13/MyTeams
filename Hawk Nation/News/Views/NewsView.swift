//
//  NewsView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

var samplejayhawkArticles = [News]()

struct LoadingNewsView: View {
    var body: some View {
        
        ZStack() {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: (UIScreen.main.bounds.width - 30), height: 125, alignment: .center)
                .foregroundColor(Color(UIColor.darkGray))
                .opacity(0.0)
            
            HStack(alignment: .top) {
                ZStack() {
                    LoadingView()
                    .frame(width: 125, height: 125)
                    
                }.overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(UIColor.systemGray), lineWidth: 0)
                )
                .cornerRadius(20)
                //.padding(.leading, 10)
                
                VStack(alignment: .leading, spacing: 5) {
                    LoadingView()
                        .frame(width: 40, height: 10)
                    LoadingView()
                        .frame(height: 15)
                    LoadingView()
                        .frame(width: (UIScreen.main.bounds.width - 225), height: 15)
                    LoadingView()
                        .frame(height: 15)
                    LoadingView()
                        .frame(height: 15)
                    LoadingView()
                        .frame(width: 40, height: 10)
                }.frame(height: 125, alignment: .leading)
            }.frame(width: (UIScreen.main.bounds.width - 30), height: 125, alignment: .leading)
        }
        
        
    }
}

struct NewsView: View {
    
    var article: News
    
    static let taskDateFormat: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter
        }()
    
    var body: some View {
        
        ZStack() {
            RoundedRectangle(cornerRadius: 20)
                .frame(width: (UIScreen.main.bounds.width - 30), height: 125, alignment: .center)
                .foregroundColor(Color(UIColor.darkGray))
                .opacity(0.0)
            
            HStack(alignment: .top) {
                ZStack() {
                    WebImage(url: article.urlToImage)
                    .onSuccess { image, cacheType in
                        // Success
                    }
                    .resizable()
                    //.placeholder(Image("news"))
                        .placeholder {
                            RoundedRectangle(cornerRadius: 20)
                                .foregroundColor(Color(UIColor.systemGray))
                                .opacity(0.8)
                        }
                    .indicator(.activity)
                    .scaledToFill()
                    .frame(width: 125, height: 125)
                    
                    Rectangle()
                        .foregroundColor(.clear)
                        .background(LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom))
                        .frame(width: 125, height: 125)
                        .opacity(0.2)
                }.overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(UIColor.systemGray), lineWidth: 0)
                )
                .cornerRadius(20)
                //.padding(.leading, 10)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(article.source)
                        .foregroundColor(.primary)
                        .opacity(0.5)
                        .font(.system(size: 10))
                    Text(article.title)
                        .foregroundColor(.primary)
                        .font(.system(size: 15))
                        .fontWeight(.bold)
                    Text(article.articleDescription!)
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                    Text("\(article.publishedAt, formatter: Self.taskDateFormat)")
                        .foregroundColor(.primary)
                        .opacity(0.5)
                        .font(.system(size: 10))
                }.frame(height: 125, alignment: .leading)
            }.frame(width: (UIScreen.main.bounds.width - 30), height: 125, alignment: .leading)
        }
        
        
    }
}

let identifier = UUID()

var sampleNews = News(id: identifier, author: Optional("Motolani Alake"), title: "Shakira celebrates Africa at the 2020 Super Bowl - Pulse Nigeria", articleDescription: Optional("This edition was the 54th in history and it was decided when Kansas City Chiefs defeated the San Francisco 49ers, 31–20"), url: URL(string: "https://www.pulse.ng/entertainment/music/super-bowl-2020-shakira-performs-waka-waka-to-thrill-crowd/gjmqylv")!, urlToImage: Optional(URL(string: "https://ocdn.eu/pulscms-transforms/1/niLktkpTURBXy9hN2VlMTY5NWU3YzgzOGEzMTk2OGIzZTdjYzA2MWI2Yy5qcGeSlQMAAM0FAM0C0JMFzQSwzQJ2"))!, publishedAt: Date(), content: "testing", source: "ESPN")

struct NewsView_Previews: PreviewProvider {
    static var previews: some View {
        NewsView(article: sampleNews)
    }
}
