//
//  SettingsView.swift
//  myTeams
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import SwiftUI

/// The reader's choice of light or dark, or the system's. Stored in
/// `UserDefaults` under `storageKey` and applied to the whole app at the
/// root (`MyTeamsApp`).
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    /// The `UserDefaults` key the choice is stored under.
    static let storageKey = "settings.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// What the About section says about this build.
enum AboutInfo {
    /// "2.0.0 (1)": the marketing version and the build number from an
    /// Info.plist, or a dash for whichever is missing.
    static func versionText(info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// The app's settings: appearance and brand accent, game alerts, the reader's teams, photo
/// credits and the API-Football key, and what build this is.
///
/// Opened from the gear in Home's or a team page's navigation bar, as a
/// sheet with its own stack. `Home` presents it, not the page: removing
/// the page's team in Manage Teams unmounts the page, and Settings stays
/// up (A-5).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(BrandAccent.storageKey) private var brandAccent: BrandAccent = .classic

    @State private var showsBrowser = false

    /// The team picker opened to add teams: the tab bar holds teams only,
    /// so this is the way to follow another (t_fa6748f4).
    @State private var showsAddTeams = false

    /// The app's sharing diagnostics, read as Settings opens, after the
    /// favorites were published.
    @State private var sharing: SharedStoreDiagnostics?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityHint("Choose light, dark, or the system's appearance.")
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("Appearance")
                }

                // Applies at once, app-wide: the root reads the same key
                // (`MyTeamsApp`).
                Section {
                    LabeledContent("Accent", value: brandAccent.title)
                        .accessibilityIdentifier("settings.brandAccent.current")
                    BrandAccentPicker(selection: $brandAccent)
                } header: {
                    Text("Accent Color")
                } footer: {
                    // iOS limits (`BrandAccent`): the icon is the bundle's,
                    // and the launch screen is drawn before the app runs.
                    Text("Colors the myTeams logo, buttons and highlights. The App Store icon and the launch screen can't change with this setting.")
                }

                // No header: the row says what it is, and a header repeating
                // it would be the section's only content (B-9).
                Section {
                    // The existing alerts screen: the permission, Live
                    // Activities and each team's toggle.
                    NavigationLink {
                        AlertsSettingsView()
                    } label: {
                        Label("Alerts", systemImage: "bell.badge")
                    }
                    .accessibilityLabel("Alerts")
                    .accessibilityHint("Choose which teams send game alerts, and allow notifications.")
                    .accessibilityIdentifier("settings.alerts")
                }

                Section {
                    Button {
                        showsAddTeams = true
                    } label: {
                        Label("Add Teams", systemImage: "plus.circle")
                    }
                    .accessibilityHint("Find a team by sport, league or name, and follow it.")
                    .accessibilityIdentifier("settings.addTeams")

                    Button {
                        showsBrowser = true
                    } label: {
                        Label("Manage Teams", systemImage: "list.star")
                    }
                    .accessibilityHint("Add, remove or reorder the teams you follow.")
                    .accessibilityIdentifier("settings.teams")
                } header: {
                    Text("Teams")
                }

                // Where a player photo came from Wikimedia Commons, its
                // author and licence (`AthleteHeadshot`).
                Section {
                    NavigationLink {
                        PhotoCreditsView()
                    } label: {
                        Label("Photo Credits", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityHint("Lists the Wikimedia Commons player photos shown, with their authors and licences.")
                    .accessibilityIdentifier("settings.photoCredits")
                }

                // The reader's own API-Football key, for soccer photos
                // neither ESPN nor Commons has (tier 3).
                ApiFootballSettingsSection()

                Section {
                    LabeledContent("Version", value: AboutInfo.versionText(info: Bundle.main.infoDictionary))
                        .accessibilityIdentifier("settings.version")
                } header: {
                    Text("About")
                } footer: {
                    logo
                }

                // What the app was signed with and where it shares the
                // favorites, to compare with the widget's face on a
                // re-signed install (`SharedStoreDiagnostics`).
                Section {
                    ForEach(sharing?.lines ?? [], id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Widget Sharing")
                }
                .accessibilityIdentifier("settings.widgetSharing")
            }
            .onAppear {
                FavoritesStore.shared.publishToWidgets()
                sharing = SharedStoreDiagnostics.current()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Every change applies at once: nothing to confirm, so
                    // it closes, as the system's glass xmark (B-9, X-8).
                    Button(role: .close) {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
        .sheet(isPresented: $showsBrowser) {
            TeamBrowserView()
        }
        .sheet(isPresented: $showsAddTeams) {
            TeamBrowserView(title: "Add Teams")
        }
    }

    /// The brand logo, in the art drawn for the scheme on screen, its
    /// arches in the brand accent.
    private var logo: some View {
        BrandLogoMark(art: colorScheme == .dark ? "myTeamsLogoOnDark" : "myTeamsLogoOnLight")
            .frame(width: BrandLogo.inline)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .accessibilityLabel("myTeams")
    }
}

/// The brand accents as swatches, solids, gradients and specials in turn:
/// a tap picks one. Each swatch draws its fill, and the chosen one is
/// ringed and checked.
private struct BrandAccentPicker: View {
    @Binding var selection: BrandAccent

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: Theme.Spacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(BrandAccent.Style.allCases, id: \.self) { style in
                Text(style.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(BrandAccent.allCases.filter { $0.style == style }) { accent in
                        swatch(accent)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func swatch(_ accent: BrandAccent) -> some View {
        let selected = accent == selection
        return Button {
            selection = accent
        } label: {
            Circle()
                .fill(accent.fill)
                .frame(width: 36, height: 36)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(selected ? AnyShapeStyle(accent.fill) : AnyShapeStyle(Color.clear), lineWidth: 2)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        // A plain style, so the whole row isn't one tappable cell.
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.brandAccent.\(accent.rawValue)")
    }
}

#Preview {
    SettingsView()
}
