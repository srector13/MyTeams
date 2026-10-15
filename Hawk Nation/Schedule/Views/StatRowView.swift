//
//  StatRowView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/20/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

//WILL REPLACE THIS WITH A GRID VIEW (SWIFTUI 2)

/// One comparison row of a game sheet's box score: the away side's figure
/// on the left and the home side's on the right, as the scoreboard reads.
struct StatRowView: View {
    var title: String
    var homeStat: String
    var awayStat: String
    /// The sides' names, for VoiceOver; "home" and "away" when empty.
    var homeName: String = ""
    var awayName: String = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        row
            // One element, read as "Total Yards, Raiders 437, Chiefs 399"
            // rather than three loose figures.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var row: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // A third of the width can't hold the title at these sizes: it
            // goes above, and the two figures share the row beneath it.
            VStack(spacing: Theme.Spacing.xs) {
                titleText

                HStack {
                    stat(awayStat, alignment: .leading)
                    stat(homeStat, alignment: .trailing)
                }
            }
        } else {
            HStack() {
                stat(awayStat, alignment: .leading)

                titleText
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)

                stat(homeStat, alignment: .trailing)
            }
        }
    }

    private var accessibilityText: String {
        let away = awayName.isEmpty ? "away" : awayName
        let home = homeName.isEmpty ? "home" : homeName
        return "\(title), \(away) \(awayStat), \(home) \(homeStat)"
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

/// The team each column of the comparison rows belongs to, over them: away
/// on the left, home on the right, as the scoreboard reads. Hidden from
/// VoiceOver, since each row names both sides itself.
struct StatColumnsHeader: View {
    var away: String
    var home: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label(away, alignment: .leading)
            label(home, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func label(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
    }
}

#Preview {
    VStack {
        StatColumnsHeader(away: "LV", home: "KC")
        StatRowView(title: "Field Goals", homeStat: "10", awayStat: "20", homeName: "Chiefs", awayName: "Raiders")
    }
}
