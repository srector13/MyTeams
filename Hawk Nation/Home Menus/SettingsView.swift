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

/// The app's settings: the display (appearance and the theme,
/// `ThemeSettingsView`), the reader's teams and their game alerts, the
/// advanced settings, and photo credits and what build this is.
///
/// Every row leads with a symbol in one column, so the titles line up and
/// wrap beside it at any text size (`SettingsRowLabelStyle`, S1, A2).
///
/// Opened from the gear in Home's or a team page's navigation bar, as a
/// sheet with its own stack. `Home` presents it, not the page: removing
/// the page's team in Edit My Teams unmounts the page, and Settings stays
/// up (A-5).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    /// The brand theme, named on the Theme row and tinting the sheets
    /// opened from here (O3).
    @AppStorage(BrandTheme.storageKey) private var theme: BrandTheme = .classic

    @State private var showsBrowser = false

    /// The team picker opened to add teams: the tab bar holds teams only,
    /// so this is the way to follow another (t_fa6748f4).
    @State private var showsAddTeams = false

    /// The notification permission, for the Alerts row's On or Off.
    @State private var alerts = AlertsSettingsModel.live()

    private var store: FavoritesStore { .shared }

    /// "On" or "Off" for the Alerts row (`AlertsSummary`); `nil` until the
    /// permission is read.
    private var alertsValue: String? {
        AlertsSummary.value(
            permission: alerts.permission,
            anyTeamOn: store.teamIDs.contains { AlertsTeamRowStatus(kinds: store.alertKinds(for: $0), blocked: false).isOn }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityHint("Choose light, dark, or the system's appearance.")
                    .accessibilityIdentifier("settings.appearance")

                    // The brand theme, on its own screen: the palette grid is
                    // too tall for this list.
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        LabeledContent {
                            Text(theme.title)
                        } label: {
                            Label("Theme", systemImage: "paintpalette")
                        }
                    }
                    .accessibilityLabel("Theme")
                    .accessibilityValue(theme.title)
                    .accessibilityHint("Choose the palette for the accent color, the myTeams logo and the app icon.")
                    .accessibilityIdentifier("settings.theme")

                    // Customize Home, as Home's foot opens it: its sections,
                    // and what Around Your Leagues shows.
                    NavigationLink {
                        HomeCustomizeSheet(isPushed: true)
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .accessibilityHint("Show, hide and reorder Home's sections, and choose the league games it shows.")
                    .accessibilityIdentifier("settings.home")
                } header: {
                    Text("Display")
                }

                Section {
                    Button {
                        showsAddTeams = true
                    } label: {
                        sheetRow("Add Teams", systemImage: "plus.circle")
                    }
                    .accessibilityHint("Find a team by sport, league or name, and follow it.")
                    .accessibilityIdentifier("settings.addTeams")

                    Button {
                        showsBrowser = true
                    } label: {
                        sheetRow("Edit My Teams", systemImage: "list.star")
                    }
                    .accessibilityHint("Add, remove or reorder the teams you follow.")
                    .accessibilityIdentifier("settings.teams")

                    // The alerts screen: the permission, Live Activities and
                    // each team's alerts. A plain bell: the value says
                    // whether they're on (S1).
                    NavigationLink {
                        AlertsSettingsView()
                    } label: {
                        LabeledContent {
                            Text(alertsValue ?? "")
                        } label: {
                            Label("Alerts", systemImage: "bell")
                        }
                    }
                    .accessibilityLabel("Alerts")
                    .accessibilityValue(alertsValue ?? "")
                    .accessibilityHint("Choose which teams send game alerts, and allow notifications.")
                    .accessibilityIdentifier("settings.alerts")
                } header: {
                    Text("Teams")
                }

                // The API-Football key and the widget diagnostics: for the
                // few who need them, a screen of their own rather than the
                // middle of everyone's Settings.
                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Label("Advanced", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityHint("Your own API-Football key for soccer photos, and widget sharing details.")
                    .accessibilityIdentifier("settings.advanced")
                } header: {
                    Text("More")
                }

                Section {
                    // Where a player photo came from Wikimedia Commons, its
                    // author and licence (`AthleteHeadshot`).
                    NavigationLink {
                        PhotoCreditsView()
                    } label: {
                        Label("Photo Credits", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityHint("Lists the Wikimedia Commons player photos shown, with their authors and licences.")
                    .accessibilityIdentifier("settings.photoCredits")

                    LabeledContent {
                        Text(AboutInfo.versionText(info: Bundle.main.infoDictionary))
                    } label: {
                        Label("Version", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settings.version")
                } header: {
                    Text("About")
                } footer: {
                    logo
                }
            }
            .labelStyle(SettingsRowLabelStyle())
            .onAppear {
                FavoritesStore.shared.publishToWidgets()
                // Again on each return from Alerts, where it may change.
                Task { await alerts.refresh() }
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
                    // The toolbar's own icon-only label, not a row's.
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
        // The theme's accent on every control, here and in the sheets
        // opened from here, never the system's blue (O3).
        .tint(theme.swatchColor)
        .sheet(isPresented: $showsBrowser) {
            TeamBrowserView()
                .tint(theme.swatchColor)
        }
        .sheet(isPresented: $showsAddTeams) {
            TeamBrowserView(title: "Add Teams")
                .tint(theme.swatchColor)
        }
    }

    /// A row that opens a sheet: its symbol and title in the primary
    /// colour, not the tint a button's label takes, and a chevron, as the
    /// rows that push have.
    private func sheetRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer(minLength: Theme.Spacing.s)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.metadata)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// The brand logo, in the art drawn for the scheme on screen: the
    /// shipped wordmark art for the classic theme, the theme's otherwise.
    private var logo: some View {
        BrandLogoMark(art: colorScheme == .dark ? "myTeamsLogoOnDark" : "myTeamsLogoOnLight")
            .frame(width: BrandLogo.inline)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .accessibilityLabel("myTeams")
    }
}

/// A settings row's label at any text size: the symbol in a column of its
/// own, in the tint, and the title in the primary colour beside it,
/// first baselines aligned. A long title, or a large text size, wraps
/// within its column rather than under the symbol (A2), and the row's
/// separator starts where the title does.
struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsRowLabel(configuration: configuration)
    }
}

private struct SettingsRowLabel: View {
    let configuration: LabelStyleConfiguration

    /// The symbol column, which grows with the text beside it.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            configuration.icon
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            configuration.title
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                    dimensions[.leading]
                }
        }
    }
}

/// Settings few people need: where soccer photos ESPN lacks may come from
/// (TheSportsDB, on by default; FotMob, an experiment, off), the reader's
/// own API-Football key for more of them, and what the app was signed with
/// and where it shares the favorites, to compare with the widget's face on
/// a re-signed install (`SharedStoreDiagnostics`).
struct AdvancedSettingsView: View {
    /// The app's sharing diagnostics, read as the screen opens, after
    /// Settings published the favorites.
    @State private var sharing: SharedStoreDiagnostics?

    /// Soccer Photos: stored where `AthleteHeadshot` reads them, so a change
    /// applies to the next headshot drawn (`SoccerPhotoSettings`).
    @AppStorage(SoccerPhotoSettings.theSportsDBKey) private var theSportsDBEnabled = SoccerPhotoSettings.theSportsDBDefault
    @AppStorage(SoccerPhotoSettings.fotMobKey) private var fotMobEnabled = SoccerPhotoSettings.fotMobDefault

    var body: some View {
        Form {
            Section {
                Toggle("TheSportsDB", isOn: $theSportsDBEnabled)
                    .accessibilityHint("Looks up soccer player photos ESPN doesn't have in TheSportsDB.")
                    .accessibilityIdentifier("settings.thesportsdb.enabled")

                Toggle("FotMob (Experimental)", isOn: $fotMobEnabled)
                    .accessibilityHint("Looks up soccer player photos ESPN doesn't have through FotMob's unofficial endpoints.")
                    .accessibilityIdentifier("settings.fotmob.enabled")
            } header: {
                Text("Soccer Photos")
                    .accessibilityIdentifier("settings.soccerPhotos")
            } footer: {
                Text("Where ESPN has no photo of a soccer player, the app can look for one elsewhere. TheSportsDB is a free, community-run sports database, asked a few players at a time. FotMob (Experimental) uses FotMob's unofficial public endpoints, which may stop working at any time. Photos belong to their owners.")
            }

            ApiFootballSettingsSection()

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
            sharing = SharedStoreDiagnostics.current()
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
