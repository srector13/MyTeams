//
//  AlertsSettingsView.swift
//  myTeams
//
//  Created by Stephen Rector on 9/30/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import ActivityKit
import SwiftUI
import UIKit

extension AlertsSettingsModel {
    /// The model over the real system: notification settings, ActivityKit
    /// and the Settings app.
    static func live() -> AlertsSettingsModel {
        AlertsSettingsModel(
            readPermission: { await ScoreAlertsPermissions.permission() },
            requestPermission: { await ScoreAlertsPermissions.requestIfNeeded() },
            readActivitiesEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
            openSettings: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        )
    }
}

/// Which followed teams send game alerts, and whether the system lets them:
/// the notification permission, with a way to grant it from here, and Live
/// Activities.
///
/// Reached from the team browser, so readers who never followed a new team
/// (whose seeded teams never prompted) can still turn alerts on.
struct AlertsSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = AlertsSettingsModel.live()
    @State private var teams: [TeamRef] = []

    /// A toggle's crest, which scales with the team name beside it (B-3).
    @ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 24

    private var store: FavoritesStore { .shared }

    var body: some View {
        List {
            Section {
                if let row = model.notificationsRow {
                    statusRow(row, identifier: "alerts.notifications")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                statusRow(model.liveActivitiesRow, identifier: "alerts.liveActivities")
            }

            Section {
                ForEach(teams) { team in
                    teamToggle(team)
                }
            } header: {
                Text("Game Alerts")
            } footer: {
                Text("Starts, scores, period ends and finals for each team turned on.")
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refresh()
        }
        .task(id: store.teamIDs) {
            teams = await store.teamRefs()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings, where either may have changed.
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
    }

    // MARK: Pieces

    private func statusRow(_ row: AlertsStatusRow, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(row.title)
            } icon: {
                // Hierarchical, and red when off, so the symbol carries the
                // state as well as the title does (A-1).
                Image(systemName: row.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(row.tint == .off ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            }
            .font(.body.weight(.semibold))
            Text(row.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let action = row.action, let title = row.actionTitle,
               let label = row.actionAccessibilityLabel {
                Button(title) {
                    Task { await model.perform(action) }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(label)
                .accessibilityHint(accessibilityHint(for: action))
                .accessibilityIdentifier("\(identifier).action")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func teamToggle(_ team: TeamRef) -> some View {
        Toggle(isOn: Binding(
            get: { store.notify(for: team.id) },
            set: { store.setNotify($0, for: team.id) }
        )) {
            HStack(spacing: 12) {
                TeamLogo(team: team, size: crestSize)
                    .frame(width: crestSize, height: crestSize)
                    .accessibilityHidden(true)
                Text(team.displayName)
                Text(team.league.badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Game alerts for \(team.displayName), \(team.league.badge)")
        .accessibilityHint("Turns notifications for this team's games on or off.")
        .accessibilityIdentifier("alerts.toggle.\(team.id)")
    }

    private func accessibilityHint(for action: AlertsSettingsAction) -> String {
        switch action {
        case .ask: "Shows the system prompt to allow notifications."
        case .openSettings: "Leaves myTeams for its page in the Settings app."
        }
    }
}

#Preview {
    NavigationStack {
        AlertsSettingsView()
    }
}
