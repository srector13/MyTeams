//
//  BioViews.swift
//  myTeams
//
//  Created by Stephen Rector on 5/14/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A biography fact in a player sheet's grid: the value over its label.
/// Sizes to its text; the grid sets the width (P-4).
struct BioView: View {
    var title: String
    var info: String

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Text(info == "" ? "N/A" : info)
                .font(.subheadline.weight(.black))
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
    BioView(title: "Position", info: "Guard")
}
