//
//  StatPercentageView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A rate in a player sheet's grid: a system capacity gauge in the team's
/// colour over its label, or "N/A" when the rate has no attempts behind it.
/// The grid sets the width (P-4).
///
/// The gauge (P-6) speaks the title and the rate as a percentage, so the
/// label beneath it is hidden from VoiceOver rather than read twice.
struct StatPercentageView: View {
    var progress: Double
    var color: Color
    var title: String

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.xs) {
            if(progress.isFinite) {
                Gauge(value: progress) {
                    Text(title)
                } currentValueLabel: {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(color)
            } else {
                Text("N/A")
                    .font(.subheadline.weight(.black))
                    .multilineTextAlignment(.center)
            }

            Text(title)
                .font(Theme.Typography.statLabel)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityHidden(progress.isFinite)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
    }
}

#Preview {
    StatPercentageView(
        progress: 0.6,
        color: TeamCatalog.seeded(league: .mensCollegeBasketball, espnID: "2305").color,
        title: "Test"
    )
}
