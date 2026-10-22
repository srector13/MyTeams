//
//  StatPercentageView.swift
//  myTeams
//
//  Created by Stephen Rector on 5/18/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import SwiftUI

/// A rate's slim bar beneath its row on a player sheet: `fraction` of the
/// track filled in the team's accent (`TeamColors.accent(for:)`, F3), over
/// a track in the system fill, which reads on the inset rows in light and
/// dark alike (P3). The sheet draws one only over enough attempts
/// (`PlayerSheetCell.minimumBarAttempts`); below that the row reads "0 of
/// 3" instead.
///
/// Decorative: the row speaks its label and figure, so VoiceOver skips the
/// bar.
struct StatPercentageView: View {
    /// The share filled, clamped to 0–1.
    var fraction: Double
    /// The fill: the team's accent on a content card.
    var color: Color

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 6

    /// The unfilled track: grey enough to see on the inset surface in
    /// either appearance, firmer under Increase Contrast.
    private static var track: Color { Color(uiColor: .systemFill) }

    private var clamped: Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }

    var body: some View {
        Capsule()
            .fill(Self.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        // A sliver at least as wide as the bar is tall, so a
                        // small share still reads as a mark.
                        .frame(width: clamped > 0 ? max(proxy.size.width * CGFloat(clamped), height) : 0)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        StatPercentageView(fraction: 0.47, color: .blue)
        StatPercentageView(fraction: 0.02, color: .blue)
        StatPercentageView(fraction: 1, color: .blue)
    }
    .padding()
}
