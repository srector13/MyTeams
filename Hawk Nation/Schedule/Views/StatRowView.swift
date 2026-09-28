//
//  StatRowView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/20/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

//WILL REPLACE THIS WITH A GRID VIEW (SWIFTUI 2)

struct StatRowView: View {
    var title: String
    var homeStat: String
    var awayStat: String
    
    var body: some View {
        HStack() {
            Text(homeStat)
                .font(.system(size: 20))
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .systemGray))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            
            Text(awayStat)
                .font(.system(size: 20))
                .fontWeight(.bold)
                .minimumScaleFactor(0.5)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            
        }
    }
}

#Preview {
    StatRowView(title: "Field Goals", homeStat: "10", awayStat: "20")
}
