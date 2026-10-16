//
//  PlayerJerseyAvatar.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI
import UIKit

/// What stands in for a headshot no source has: the player's shirt number,
/// large, in the team's ink on the team colour, with the crest faint behind
/// it, as a jersey's back reads. Without a number it shows the position's
/// initials, then the name's (`jerseyAvatarLabel`). Without a team (a
/// roster card, which isn't told it) it draws in the system's grey.
///
/// Most soccer players have no ESPN headshot, so this is what their sheet
/// leads with rather than a grey silhouette. Decorative: the sheet's header
/// and the roster card already say who it is.
struct PlayerJerseyAvatar: View {
    let label: String
    let team: TeamRef?
    let size: CGFloat

    init(number: String, position: String, name: String, team: TeamRef?, size: CGFloat) {
        self.label = jerseyAvatarLabel(number: number, position: position, name: name)
        self.team = team
        self.size = size
    }

    /// A roster player's avatar.
    init<Player: RosterPlayer>(_ player: Player, team: TeamRef?, size: CGFloat) {
        self.init(number: player.number, position: player.position, name: player.name, team: team, size: size)
    }

    /// The team colour, or the system's grey without a team.
    private var fill: Color {
        guard let team else { return Color(uiColor: .systemGray5) }
        return Color(hexString: TeamColors.fillHex(for: team))
    }

    /// The ink that reads on `fill` (G-3).
    private var ink: Color {
        guard let team else { return Color(uiColor: .secondaryLabel) }
        return TeamColors.ink(on: team)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)

            // A soft sheen from the top, so the disc reads apart from a
            // team-colour backdrop of the same colour.
            Circle()
                .fill(LinearGradient(colors: [ink.opacity(0.18), ink.opacity(0)], startPoint: .top, endPoint: .bottom))

            if let team {
                TeamLogo(team: team, size: size * 0.8, forceVariant: .default)
                    .saturation(0.1)
                    .opacity(0.16)
            }

            if label.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(ink)
            } else {
                // Proportional to the avatar, not to Dynamic Type: the
                // avatar itself scales.
                Text(label)
                    .font(.system(size: size * (label.count > 2 ? 0.32 : 0.44), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
