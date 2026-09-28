//
//  BioViews.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct BioView: View {
    @Environment(\.containerSize) private var containerSize

    var title: String
    var info: String
    
    var body: some View {
            
            VStack(alignment: .center, spacing: 0) {
                if(info == "") {
                    Text("N/A")
                        .font(.system(size: 15))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                    
                } else {
                    Text(info)
                        .font(.system(size: 15))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                    
                }
                
                Text(title)
                    .font(.system(size: 15))
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                
                
            }.frame(width: (containerSize.width/4), height: (containerSize.width/3))
        }
}

#Preview {
    BioView(title: "Position", info: "Guard")
}
