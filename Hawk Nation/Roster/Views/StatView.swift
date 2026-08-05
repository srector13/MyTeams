//
//  StatView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct StatView: View {
    var title: String
    var info: String
    
    var body: some View {
            VStack(alignment: .center, spacing: 0){
                if(info == "") {
                    Text("N/A")
                        .font(.system(size: 20))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        //.lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: 0, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                    
                } else {
                    Text(info)
                        .font(.system(size: 20))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: 0, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                }
                
                Text(title)
                    .font(.system(size: 15))
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(UIColor.systemGray))
                    .frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: 0, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                
                
            }.frame(width: (UIScreen.main.bounds.width/4), height: UIScreen.main.bounds.width/3)
        }
}

struct StatView_Previews: PreviewProvider {
    static var previews: some View {
        StatView(title: "test", info: "0.5")
    }
}



