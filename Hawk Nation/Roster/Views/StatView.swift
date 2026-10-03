//
//  StatView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A season statistic in a player sheet's grid: the figure over its label.
/// Sizes to its text; the grid sets the width (P-4).
struct StatView: View {
    var title: String
    var info: String

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Text(info == "" ? "N/A" : info)
                .font(Theme.Typography.statFigure)
                .multilineTextAlignment(.center)

            Text(title)
                .font(Theme.Typography.statLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(uiColor: .systemGray))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
    }
}

#Preview {
    StatView(title: "test", info: "0.5")
}



