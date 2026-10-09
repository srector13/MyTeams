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
/// Activities; then which kinds of alert go out, and quiet hours
/// (`AlertPreferences`). Each team pushes to its own alerts
/// (`TeamAlertsView`, R-6): on or off, and the global kinds or its own.
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
    private var preferences: AlertPreferencesStore { .shared }

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
                    teamRow(team)
                }
            } header: {
                Text("Game Alerts")
            } footer: {
                Text("Starts, scores, period ends and finals for each team turned on. With the app closed, iOS decides when scores are checked, and may check rarely if you seldom open the app.")
            }

            Section {
                ForEach(ScoreAlertKind.allCases, id: \.self) { kind in
                    kindToggle(kind)
                }
            } header: {
                Text("Alert Types")
            } footer: {
                Text("Score updates include the end of each period. A team can choose its own types instead.")
            }

            Section {
                Toggle("Quiet Hours", isOn: preference(\.quietHoursEnabled))
                    .accessibilityHint("Delivers alerts silently, without a banner, during the hours below.")
                    .accessibilityIdentifier("alerts.quietHours")
                if preferences.preferences.quietHoursEnabled {
                    DatePicker("From", selection: quietTime(\.quietStart), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("alerts.quietHours.start")
                    DatePicker("To", selection: quietTime(\.quietEnd), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("alerts.quietHours.end")
                }
            } header: {
                Text("Quiet Hours")
            } footer: {
                Text("Alerts still arrive in Notification Center during quiet hours, without a sound or a banner.")
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
                // The screen's primary action, so prominent; a system
                // style, not glass, since it sits in a list row (A-2, B1).
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(label)
                .accessibilityHint(accessibilityHint(for: action))
                .accessibilityIdentifier("\(identifier).action")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// A team's row: its alerts at a glance, pushing to their settings.
    private func teamRow(_ team: TeamRef) -> some View {
        let status = TeamAlertsView.status(store.alertKinds(for: team.id))
        return NavigationLink {
            TeamAlertsView(team: team)
        } label: {
            HStack(spacing: 12) {
                TeamLogo(team: team, size: crestSize)
                    .frame(width: crestSize, height: crestSize)
                    .accessibilityHidden(true)
                Text(team.displayName)
                Text(team.league.badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Game alerts for \(team.displayName), \(team.league.badge): \(status)")
        .accessibilityHint("Shows this team's alert settings.")
        .accessibilityIdentifier("alerts.team.\(team.id)")
    }

    private func kindToggle(_ kind: ScoreAlertKind) -> some View {
        Toggle(kind.title, isOn: Binding(
            get: { preferences.preferences.sends(kind) },
            set: { sends in preferences.update { $0.setSends(sends, for: kind) } }
        ))
        .accessibilityHint("Turns \(kind.title.lowercased()) on or off for every team.")
        .accessibilityIdentifier("alerts.kind.\(kind.rawValue)")
    }

    /// A binding to one of the alert preferences, written through to the
    /// store.
    private func preference<Value>(_ keyPath: WritableKeyPath<AlertPreferences, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { preferences.preferences[keyPath: keyPath] },
            set: { value in preferences.update { $0[keyPath: keyPath] = value } }
        )
    }

    /// A time picker's binding to a quiet-hours bound, kept in minutes after
    /// midnight: shown as that time today, and read back as its hour and
    /// minute.
    private func quietTime(_ keyPath: WritableKeyPath<AlertPreferences, Int> & Sendable) -> Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                let minutes = AlertPreferences.normalized(preferences.preferences[keyPath: keyPath])
                return calendar.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                preferences.update { $0[keyPath: keyPath] = minutes }
            }
        )
    }

    private func accessibilityHint(for action: AlertsSettingsAction) -> String {
        switch action {
        case .ask: "Shows the system prompt to allow notifications."
        case .openSettings: "Leaves myTeams for its page in the Settings app."
        }
    }
}

/// One followed team's game alerts (R-6): on or off, and either the global
/// alert types or the team's own (`FavoriteTeam.alertKinds`). Choosing a
/// type here stores the team's own set; going back to the global types
/// stores none, so the team follows later changes to them.
struct TeamAlertsView: View {
    let team: TeamRef

    private var store: FavoritesStore { .shared }
    private var preferences: AlertPreferencesStore { .shared }

    /// What a team's row says of its alerts.
    static func status(_ kinds: AlertMask?) -> String {
        switch kinds {
        case nil: "On"
        case let kinds? where kinds.isEmpty: "Off"
        default: "Custom"
        }
    }

    private var kinds: AlertMask? { store.alertKinds(for: team.id) }

    var body: some View {
        List {
            Section {
                Toggle("Game Alerts", isOn: Binding(
                    get: { store.notify(for: team.id) },
                    set: { store.setNotify($0, for: team.id) }
                ))
                .accessibilityLabel("Game alerts for \(team.displayName), \(team.league.badge)")
                .accessibilityHint("Turns notifications for this team's games on or off.")
                .accessibilityIdentifier("alerts.toggle.\(team.id)")
            }

            if kinds != AlertMask() {
                Section {
                    Toggle("Use Default Types", isOn: Binding(
                        get: { kinds == nil },
                        set: { usesDefault in
                            store.setAlertKinds(usesDefault ? nil : ownKindsToStart, for: team.id)
                        }
                    ))
                    .accessibilityHint("Follows the alert types chosen for every team.")
                    .accessibilityIdentifier("alerts.team.default")
                    ForEach(ScoreAlertKind.allCases, id: \.self) { kind in
                        kindToggle(kind)
                    }
                } header: {
                    Text("Alert Types")
                } footer: {
                    Text("Turn off Use Default Types to choose this team's own. Turning every type off turns its alerts off.")
                }
            }
        }
        .navigationTitle(team.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The team's own kinds when it leaves the defaults: the global ones as
    /// they stand, or every kind should those all be off.
    private var ownKindsToStart: AlertMask {
        let global = preferences.preferences.kinds
        // The defaults send every kind.
        return global == AlertMask() ? AlertPreferences().kinds : global
    }

    private func kindToggle(_ kind: ScoreAlertKind) -> some View {
        Toggle(kind.title, isOn: Binding(
            get: {
                guard let kinds else { return preferences.preferences.sends(kind) }
                return kinds.contains(kind.mask)
            },
            set: { sends in
                var own = kinds ?? ownKindsToStart
                if sends {
                    own.insert(kind.mask)
                } else {
                    own.remove(kind.mask)
                }
                store.setAlertKinds(own, for: team.id)
            }
        ))
        .disabled(kinds == nil)
        .accessibilityHint("Turns \(kind.title.lowercased()) on or off for this team.")
        .accessibilityIdentifier("alerts.team.kind.\(kind.rawValue)")
    }
}

#Preview {
    NavigationStack {
        AlertsSettingsView()
    }
}
