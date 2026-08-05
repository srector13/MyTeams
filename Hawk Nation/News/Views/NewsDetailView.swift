//
//  NewsDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import WebKit
import SafariServices

struct NewsDetailView: View {
    var article: News
    var color: Color
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack(alignment: .top) {
            SafariView(url: article.url)
            //WebKit(request: URLRequest(url: article.url))
            .edgesIgnoringSafeArea(.top)
            
            Rectangle()
                .foregroundColor(Color(UIColor.systemBackground))
                .frame(height: 60)
            
            
            HStack() {
                //News Logo
                if (article.source == "Bleacher Report") {
                    Image(article.source)
                        .resizable()
                        .frame(width: 80, height: 40)
                        .padding(.top, 4)
                } else if ((article.source == "ESPN")) {
                    Image(article.source)
                        .resizable()
                        .frame(width: 100, height: 50)
                } else if ((article.source == "NFL News")) {
                    Image(article.source)
                        .resizable()
                        .frame(width: 40, height: 40)
                }
                
                Spacer()
                
                //DISMISS BUTTON
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 20))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }.padding(.horizontal)
            .frame(height: 60)
        }.background(Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all))
            .edgesIgnoringSafeArea(.all)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        return SFSafariViewController(url: url, entersReaderIfAvailable: true)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
    }
}

struct WebKit: UIViewRepresentable {
    let request: URLRequest
    
    func makeUIView(context: UIViewRepresentableContext<WebKit>) -> WKWebView {
        return WKWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(request)
    }
}
