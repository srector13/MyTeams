//
//  NewsDetailView.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 2/6/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI
import SafariServices

struct NewsDetailView: View {
    var article: News
    var color: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .top) {
            SafariView(url: article.url)
            .ignoresSafeArea(.top)
            
            Rectangle()
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(height: 60)
            
            
            HStack() {
                //News Logo
                if (article.source == "Bleacher Report") {
                    Image(article.source)
                        .frame(width: 80, height: 40)
                        .padding(.top, 4)
                } else if ((article.source == "ESPN")) {
                    Image(article.source)
                        .frame(width: 100, height: 50)
                } else if ((article.source == "NFL News")) {
                    Image(article.source)
                        .frame(width: 40, height: 40)
                }
                
                Spacer()
                
                //DISMISS BUTTON
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 20))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }.padding(.horizontal)
            .frame(height: 60)
        }.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))
            .ignoresSafeArea(.all)
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
