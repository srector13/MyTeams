//
//  StatPercentageView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct StatPercentageView: View {
    @Environment(\.containerSize) private var containerSize

    var progress: CGFloat
    var color: UIColor
    var title: String

    var body: some View {

        
            VStack(alignment: .center, spacing: 0) {
                
                
                if(progress.isFinite) {
                    CircularProgress(percentage: progress,
                                      fontSize: 10,
                                      backgroundColor: Color(uiColor: .systemBackground),
                                      fontColor : Color.primary,
                                      borderColor1: Color(color.darker()!),
                                      borderColor2: LinearGradient(gradient: Gradient(colors: [Color(color), Color(color.lighter()!)]),startPoint: .top, endPoint: .bottom)
                          ).frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
                    //.offset(y: 10)
                    //.padding(.bottom, 10)
                } else {
                    Text("N/A")
                        .font(.system(size: 15))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        //.lineLimit(2)
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




extension UIColor {

    func lighter(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjust(by: abs(percentage) )
    }

    func darker(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjust(by: -1 * abs(percentage) )
    }

    func adjust(by percentage: CGFloat = 30.0) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: min(red + percentage/100, 1.0),
                           green: min(green + percentage/100, 1.0),
                           blue: min(blue + percentage/100, 1.0),
                           alpha: alpha)
        } else {
            return nil
        }
    }
}

#Preview {
    StatPercentageView(
        progress: 0.6,
        color: UIColor(TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305").color),
        title: "Test"
    )
}
