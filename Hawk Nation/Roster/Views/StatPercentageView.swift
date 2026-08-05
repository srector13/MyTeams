//
//  StatPercentageView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

struct StatPercentageView: View {
    var progress: CGFloat
    var color: UIColor
    var title: String

    var body: some View {

        
            VStack(alignment: .center, spacing: 0) {
                
                
                if(progress.isFinite) {
                    CircularProgress(percentage: progress,
                                      fontSize: 10,
                                      backgroundColor: Color(UIColor.systemBackground),
                                      fontColor : Color.primary,
                                      borderColor1: Color(color.darker()!),
                                      borderColor2: LinearGradient(gradient: Gradient(colors: [Color(color), Color(color.lighter()!)]),startPoint: .top, endPoint: .bottom)
                          ).frame(minWidth: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/, maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, minHeight: 0, maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                    //.offset(y: 10)
                    //.padding(.bottom, 10)
                } else {
                    Text("N/A")
                        .font(.system(size: 15))
                        .fontWeight(.black)
                        .minimumScaleFactor(0.5)
                        //.lineLimit(2)
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
                
            }.frame(width: (UIScreen.main.bounds.width/4), height: (UIScreen.main.bounds.width/3))
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

struct StatPercentageView_Previews: PreviewProvider {
    static var previews: some View {
        StatPercentageView(progress: 0.6, color: UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00), title: "Test")
    }
}
