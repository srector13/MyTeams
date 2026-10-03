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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // A third of the width can't hold the title at these sizes: it
            // goes above, and the two figures share the row beneath it.
            VStack(spacing: Theme.Spacing.xs) {
                titleText

                HStack {
                    stat(homeStat, alignment: .leading)
                    stat(awayStat, alignment: .trailing)
                }
            }
        } else {
            HStack() {
                stat(homeStat, alignment: .leading)

                titleText
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                stat(awayStat, alignment: .trailing)
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// A team's figure. One line, trimmed no further than 0.8 (D-4).
    private func stat(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.title3.bold().monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
    }
}

#Preview {
    StatRowView(title: "Field Goals", homeStat: "10", awayStat: "20")
}
