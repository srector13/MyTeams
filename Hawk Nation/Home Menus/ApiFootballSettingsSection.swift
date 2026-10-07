//
//  ApiFootballSettingsSection.swift
//  myTeams
//
//  Created by Stephen Rector on 10/7/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// Settings → API-Football: the reader's own key, checked once on save and
/// kept in the Keychain, and the toggle that lets it find soccer photos
/// ESPN and Wikimedia Commons lack (`ApiFootballHeadshotStore`). The key is
/// never shown again, only its last four characters.
struct ApiFootballSettingsSection: View {
    private var settings: ApiFootballSettings { .shared }

    /// The key being typed or pasted; cleared once saved.
    @State private var draft = ""

    var body: some View {
        Section {
            if let suffix = settings.keySuffix {
                LabeledContent("Saved Key", value: "•••• \(suffix)")
                    .accessibilityLabel("Saved key ending in \(suffix)")
                    .accessibilityIdentifier("settings.apiFootball.savedKey")
            }

            SecureField(settings.hasKey ? "Replace API key" : "Paste API key", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.apiFootball.keyField")

            Button("Save Key") {
                let key = draft
                Task {
                    await settings.save(key)
                    if case .accepted = settings.probe { draft = "" }
                }
            }
            .disabled(ApiFootballKey.normalized(draft) == nil || settings.probe == .checking)
            .accessibilityHint("Checks the key with API-Football, then keeps it in the Keychain.")
            .accessibilityIdentifier("settings.apiFootball.save")

            probeRow

            if settings.hasKey {
                Button("Clear Key", role: .destructive) {
                    draft = ""
                    settings.clear()
                }
                .accessibilityIdentifier("settings.apiFootball.clear")
            }

            Toggle("Use API for missing photos", isOn: Binding(
                get: { settings.isEnabled },
                set: { settings.isEnabled = $0 }
            ))
            .disabled(!settings.hasKey)
            .accessibilityHint("Looks up soccer player photos ESPN and Wikimedia Commons don't have.")
            .accessibilityIdentifier("settings.apiFootball.enabled")

            if let dashboard = ApiFootball.dashboardURL {
                Link(destination: dashboard) {
                    Label("Get a Free Key", systemImage: "safari")
                }
                .accessibilityHint("Opens dashboard.api-football.com.")
                .accessibilityIdentifier("settings.apiFootball.dashboard")
            }
        } header: {
            Text("API-Football")
                .accessibilityIdentifier("settings.apiFootball")
        } footer: {
            Text("Create a free account at dashboard.api-football.com: 100 requests a day, no card needed. Copy the API key from the dashboard and paste it above. The key stays on this device, in the Keychain, and the app uses at most \(ApiFootball.dailyRequestCap) requests a day.")
        }
    }

    @ViewBuilder
    private var probeRow: some View {
        switch settings.probe {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Checking key…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.apiFootball.status")
        case .accepted(let summary):
            Label("Key saved. \(summary).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("settings.apiFootball.status")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.apiFootball.status")
        }
    }
}
