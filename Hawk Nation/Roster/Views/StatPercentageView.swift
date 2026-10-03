//
//  StatPercentageView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A rate in a player sheet's grid: a half-ring gauge over its label, or
/// "N/A" when the rate has no attempts behind it. Sizes to its text, with
/// the ring scaled alongside it; the grid sets the width (P-4).
struct StatPercentageView: View {
    var progress: CGFloat
    var color: UIColor
    var title: String

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 90

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            if(progress.isFinite) {
                CircularProgress(percentage: progress,
                                 font: Theme.Typography.caption,
                                 backgroundColor: Color(uiColor: .systemBackground),
                                 fontColor : Color.primary,
                                 borderColor1: Color(color.darker()!),
                                 borderColor2: LinearGradient(gradient: Gradient(colors: [Color(color), Color(color.lighter()!)]),startPoint: .top, endPoint: .bottom)
                )
                .frame(width: ringSize, height: ringSize)
            } else {
                Text("N/A")
                    .font(.subheadline.weight(.black))
                    .multilineTextAlignment(.center)
            }

            Text(title)
                .font(Theme.Typography.statLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
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
