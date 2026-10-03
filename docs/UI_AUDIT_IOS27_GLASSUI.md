# myTeams UI audit: iOS 27 GlassUI (Liquid Glass) + remediation plan

*Task t_bf018dfe. Audited at `7908cce` on branch `wt/t_bf018dfe`. This is a docs-only change; no app code was modified.*

"GlassUI" here means Apple's **Liquid Glass** design system, introduced in iOS 26 and refined in iOS 27. Every file:line below was read from the tree at the commit above. API names are the iOS 26 SDK names unless marked **(verify)**. That tag means the API is new, iOS 27-specific, or something I couldn't confirm with confidence, so check it against current Apple documentation before building on it.

---

## 0. Executive summary

- **The app already uses Liquid Glass wherever it relies on system components.** The deployment target is iOS 26.0 (`myTeams.xcodeproj/project.pbxproj:945`, `:1001`). CI builds with the iOS 26 SDK (`.github/workflows/ios-gate.yml:11`, `runs-on: macos-26`). `Hawk Nation/Info.plist` has **no** `UIDesignRequiresCompatibility` key. So `NavigationStack` bars, toolbars, `.searchable`, `Menu`, `Toggle`, `List`, `.bordered` buttons, `ContentUnavailableView` and sheet chrome already render as Liquid Glass.
- **Almost all of the custom chrome predates Liquid Glass**, and that is where the gap is. The bottom crest picker, the sticky team title bar, the league chip strip, the sheet dismiss "handles", the player-sheet segmented control and the news-sheet header bar are all hand-built. They use `.bar`, `Color.secondary.opacity(0.15)` or opaque `systemBackground` fills.
- **The repo never uses a Liquid Glass API.** A grep for `glassEffect`, `GlassEffectContainer`, `.glass` button styles, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`, `symbolEffect`, `symbolRenderingMode`, `sensoryFeedback`, `contentTransition`, `matchedTransitionSource`, `presentationDetents`, `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityReduceMotion`, `@ScaledMetric` and `dynamicTypeSize` returns **zero hits** in `Hawk Nation/` and `myTeamWidget/`. The only materials are three uses of `.bar`: `TabBar.swift:321`, `TabBar.swift:346` and `TeamBrowserView.swift:224`.
- **Typography is the largest problem.** There are **80** `.font(.system(size:))` call sites across 17 files, against **14** semantic text-style call sites. There are also **30** `Color(uiColor: .systemGray)` foregrounds where `.secondary` (which picks up vibrancy) is expected. Several cards have fixed frames (120×160, 125 pt, 600 pt, `width/4 × width/3`) that will clip once text scales.
- **Totals: 12 surfaces audited, 69 findings (26 P1, 30 P2, 13 P3).** The plan has four phases and comes to roughly **21–28 dev-days**, plus 1–2 designer-days for the app icon.

---

## 1. iOS 26 → 27 GlassUI baseline

### 1.1 Principles the audit checks against

| # | Principle | What it means in SwiftUI |
|---|---|---|
| B1 | **Glass is for the navigation/control layer, not content.** Bars, tab bars, toolbars, floating buttons, sheets and menus are glass. Lists, cards and tables stay on standard backgrounds. Don't stack glass on glass. | System bars and `Tab`/`TabView`; `.glassEffect(_:in:)` only on custom floating controls; never on scrolling content cards. |
| B2 | **Group nearby glass shapes** so they share one sampling region and can morph into each other. | `GlassEffectContainer(spacing:)`, `.glassEffectID(_:in:)`, `.glassEffectUnion(id:namespace:)`. |
| B3 | **Glass variants**: `.regular` (default), `.clear` (over media), `.identity` (off). `.tint(_:)` conveys meaning (selection, primary action), not decoration. `.interactive()` reacts to touch. | `Glass.regular.tint(team.color).interactive()`. |
| B4 | **Use standard controls**, which pick up glass automatically. | `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`; `.buttonBorderShape(.circle/.capsule)`; segmented `Picker`; toolbar `Button(role: .close)` / `.confirm` **(verify, iOS 26 roles)**. |
| B5 | **Content scrolls under the chrome.** Bars float, and a scroll-edge effect keeps them legible. Don't use opaque slabs or spacer views to "clear" a bar. | `.scrollEdgeEffectStyle(_:for:)`; `.safeAreaBar(edge:)` for custom bars that should take part in the edge effect **(verify signature)**; `.backgroundExtensionEffect()` for hero imagery under bars and sidebars. |
| B6 | **Concentric geometry.** Inner corner radii follow their container and the device corners. | `ConcentricRectangle` / `.rect(corners: .concentric)` **(verify)**; otherwise a single radius token set. |
| B7 | **System typography.** SF Pro with optical sizing comes free with text styles, and so does Dynamic Type up to AX5. Bold, left-aligned large titles. | `.font(.title3.bold())` etc.; `@ScaledMetric` for icon and card sizes; layout that adapts at `dynamicTypeSize.isAccessibilitySize`. |
| B8 | **Vibrancy and hierarchy.** On glass, use hierarchical foreground styles so the system can apply vibrancy. Fixed grays and opacity hacks miss it. | `.foregroundStyle(.secondary/.tertiary)`; avoid `Color(uiColor: .systemGray)` and `.primary.opacity(0.5)`. |
| B9 | **SF Symbols 7.** Use hierarchical or palette rendering, `.contentTransition(.symbolEffect(.replace))`, and Draw On/Off and gradient rendering **(verify: `symbolEffect(.drawOn)`, `symbolColorRenderingMode(.gradient)`)**. | `.symbolRenderingMode(.hierarchical)`, `.symbolVariant(.fill)`. |
| B10 | **Motion.** Morph between states rather than cross-fading. Zoom transitions from a source element. Use numeric content transitions for scores. | `.glassEffectTransition(.materialize)` **(verify)**, `.matchedTransitionSource(id:in:)` with `.navigationTransition(.zoom(sourceID:in:))`, `.contentTransition(.numericText(value:))`. |
| B11 | **Accessibility.** System glass adapts by itself to Reduce Transparency, Increase Contrast and Reduce Motion. Custom opacity layers and animations must check the matching environment values. Every control needs a label and traits. Minimum hit target is 44×44 pt. | `@Environment(\.accessibilityReduceTransparency)`, `\.colorSchemeContrast`, `\.accessibilityReduceMotion`; `Button` rather than `.onTapGesture`. |
| B12 | **Sheets.** iOS 26 sheets are glass and float inset at partial detents, then become opaque at `.large`. Let the system draw the background and grabber. | `.presentationDetents([.medium, .large])`, `.presentationDragIndicator(.visible)`; avoid an opaque `.background(...).ignoresSafeArea(.all)`. |
| B13 | **Widgets and Live Activities.** Home Screen Clear and Tinted appearances render widgets in the accented mode with the container background removed **(verify exact mapping on iOS 27)**. Content must respond to `widgetRenderingMode`. Lock Screen and Always-On need `isLuminanceReduced` handling. | `@Environment(\.widgetRenderingMode)`, `.widgetAccentable()`, `Image.widgetAccentedRenderingMode(_:)`, `@Environment(\.isLuminanceReduced)`, `.keylineTint(_:)`. |
| B14 | **App icon.** Layered icons from Icon Composer (`.icon`) with Default, Dark, Clear and Tinted appearances, which the system renders as glass. | Add a `.icon` file to the app target **(verify the Xcode build setting name for `.icon` icons)**. |

### 1.2 What is iOS 27-specific (verify list)

My reference knowledge is solid for the iOS 26 Liquid Glass API surface above. For iOS 27, I'm not inventing API names. These are the items to confirm against the iOS 27 SDK release notes and HIG before Phase 1:

1. **Whether `UIDesignRequiresCompatibility` is still honored.** At WWDC25 Apple described it as a temporary opt-out. This app doesn't use it, so the only effect is that the opt-out isn't available as an escape hatch.
2. **Any new `Glass` variants or modifiers** added in iOS 27, and any changes in tab bar or toolbar defaults (minimize behavior, bottom accessory).
3. **Changed default appearance** of system controls when linking against the iOS 27 SDK. These are linked-on-or-after changes: rebuilding alone can change visuals, so plan a visual regression pass.
4. **Widget and Live Activity rendering changes** in iOS 27 (Clear/Tinted mapping, any new Live Activity presentation sizes).
5. **The SF Symbols version that ships with iOS 27**, plus any new rendering or effect modifiers.

Rule for this plan: **every recommendation uses iOS 26 APIs unless it's marked (verify)**. Because the target is already 26.0, none of them need `#available` checks (see §6).

### 1.3 Factual delta: what the repo uses today

| API family | Uses in `Hawk Nation/` + `myTeamWidget/` | Where |
|---|---|---|
| `Material` | 3 (`.bar` only) | `TabBar.swift:321`, `TabBar.swift:346`, `TeamBrowserView.swift:224` |
| `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial` | 0 | — |
| `glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` | 0 | — |
| `backgroundExtensionEffect`, `scrollEdgeEffectStyle`, `safeAreaBar` | 0 | — |
| `TabView` / `Tab` / `NavigationSplitView` | 0 | root is a custom `ZStack` (`TabBar.swift:54`) |
| `NavigationStack` | 2 (+1 in a Preview) | `TeamBrowserView.swift:130`, `LeadersViews.swift:140` (`AlertsSettingsView.swift:134` is a `#Preview`) |
| `.sheet` | 6 | `TabBar.swift:99`, `:104`; `HomeSections.swift:145`, `:225`, `:457`; `LeadersViews.swift:65` |
| `fullScreenCover`, `presentationDetents`, `presentationBackground` | 0 | — |
| `.buttonStyle(...)` | 5 | `.bordered`: `HomeSections.swift:57`, `AlertsSettingsView.swift:94`; `.plain`: `TeamBrowserView.swift:218`, `HomeSections.swift:446`, `PlayerDetailView.swift:576` |
| `.font(.system(size:))` | **80** across 17 files | 67 in the app; 6 in `myTeamWidget.swift`; 7 in `GameLiveActivity.swift` |
| Semantic text styles (`.title`, `.headline`, `.caption`, …) | 14 | mostly `AlertsSettingsView`, `NewsDetailView`, `GameLiveActivity` banner |
| `Color(uiColor: .systemGray)` foregrounds | **30** | across sections, sheets and cells |
| `Color(uiColor: .systemBackground)` | 18 | section slabs, sheets, spacer views |
| Accessibility environment reads, `@ScaledMetric`, `dynamicTypeSize` | 0 | — |
| `sensoryFeedback`, `symbolEffect`, `symbolRenderingMode`, `contentTransition` | 0 | — |
| `matchedGeometryEffect`, `matchedTransitionSource`, `navigationTransition` | 0 | — |
| `shadow(...)` | 0 | — |
| `widgetRenderingMode`, `widgetAccentedRenderingMode`, `isLuminanceReduced` | 0 | (`.widgetAccentable()` once: `myTeamWidget.swift:218`) |
| Corner radii | 1.5, 10, 15, 20 | `BoxScoreTables.swift:225`; `GameView.swift:130`, `GameDetailView.swift:160/165/173`, `LoadingView.swift:17`; `LeadersViews.swift:99`; `NewsView.swift:19/52/73`, `GameView.swift:116`, `GameDetailView.swift:56/297/348`, `PlayerDetailView.swift:480/494/529/537/582` |

**Already Liquid Glass for free** (system components, iOS 26 SDK, no compatibility opt-out):
- Navigation bar, `EditButton` and Done in `TeamBrowserView.swift:178-188`
- The `.searchable` field (`TeamBrowserView.swift:177`)
- The Alerts push (`TeamBrowserView.swift:136-140`)
- The `LeagueLeadersView` bar and `.insetGrouped` list (`LeadersViews.swift:140-149`, `:193`)
- `Menu` popovers in section headers
- `Toggle` rows (`AlertsSettingsView.swift:106`)
- `.bordered` buttons
- Swipe actions (`TeamBrowserView.swift:150`)
- `ContentUnavailableView` (`TabBar.swift:72`, `TeamBrowserView.swift:246`, `NewsDetailView.swift:31`)
- `AccessoryWidgetBackground` (`myTeamWidget.swift:203`)

---

## 2. Inventory

### 2a. Screen and surface inventory

The app has no tab bar or root `NavigationStack`. `Home` is a single scrolling team page with a custom crest picker. Every other screen is a `.sheet`, and only the team browser and the league leaders have their own `NavigationStack`.

| # | Screen / surface | Entry file:line | Nav path | Key subviews |
|---|---|---|---|---|
| S1 | **Home shell** (crest picker, empty state, sheets host) | `Hawk Nation/NavigationBar/TabBar.swift:16` (`Home`), mounted at `Resources/MyTeamsApp.swift:32` | `WindowGroup` root | `TeamPage` (:161), `TeamPicker` (:267, bottom `safeAreaInset` :84), `TopView` (:326), `ContentUnavailableView` (:72) |
| S2 | **Team page** (roster, schedule, standings, leaders, news) | `Home Menus/TeamHomeView.swift:18` → `TeamHomeContent` (:78) | Inside `TeamPage`'s `ScrollView` (`TabBar.swift:182`), one team at a time | `TeamHomeLayout` (`HomeSections.swift:464`), `RosterSection` (:68) + `PlayerCard` (`Roster/Views/PlayerView.swift:16`), `ScheduleSection` (:152) + `GameView` (`Schedule/Views/GameView.swift:23`), `StandingsSection` (:237) + `StandingsTable` (:303), `LeadersSection` (`Leaders/LeadersViews.swift:16`), `NewsSection` (:411) + `NewsView` (`News/Views/NewsView.swift:43`), `SectionHeader` (:13), `SectionStatusView` (:43), `RosterFilterMenu` (`TeamHomeView.swift:121`) |
| S3 | **Team browser** (also the "Pick Your Teams" onboarding) | `Home Menus/TeamBrowserView.swift:96` | Sheet from the crest picker "+" (`TabBar.swift:99`) or onboarding (`TabBar.swift:104`); own `NavigationStack` (:130) | League chips (:203), rows (:250), search results (:228) |
| S4 | **Alerts settings** (per-team notify toggles, permission status) | `Home Menus/AlertsSettingsView.swift:35` | Push from the browser's `NavigationLink` (`TeamBrowserView.swift:136`) | `statusRow` (:82), `teamToggle` (:105); row model `AlertsSettings.swift:81-118` |
| S5 | **Game detail** (venue header, scoreboard, linescore, box score) | `Schedule/Views/GameDetailView.swift:20` | Sheet from a schedule card (`HomeSections.swift:225`) | `LinescoreView` (`BoxScoreTables.swift:16`), `StatRowView` (`StatRowView.swift:13`), `HockeyBoxScoreView` (:51), `SoccerLineupsView` (:159), `GameDetailDismissHandle` (:290), `GameDetailSkeleton` (:307) |
| S6 | **Player detail** (About / Statistics tabs) | `Roster/Views/PlayerDetailView.swift:454` | Sheet from a roster card (`HomeSections.swift:145`) | `BioView` (`BioViews.swift:11`), `StatView` (`StatView.swift:11`), `StatPercentageView` (`StatPercentageView.swift:11`) → `CircularProgress` (`Classes/CircularProgress.swift:3`) |
| S7 | **League leaders** | `Leaders/LeadersViews.swift:124` | Sheet from the Leaders header button (`LeadersViews.swift:65`); own `NavigationStack` (:140) | `LeaderRow` (:221), `LeaderHeadshot` (:106) |
| S8 | **News detail** (header + `SFSafariViewController`) | `News/Views/NewsDetailView.swift:17` | Sheet from a news card (`HomeSections.swift:457`) | `SafariView` (:68) |
| S9 | **Home Screen widget** (systemSmall / systemMedium) | `myTeamWidget/myTeamWidget.swift:118` (`WidgetEntryView`) | WidgetKit; `AppIntentConfiguration` (:247); tap → `widgetURL` (:137) | `systemSmall` (:140) |
| S10 | **Lock Screen accessory widgets** (rectangular / circular) | `myTeamWidget/myTeamWidget.swift:195` (`AccessoryEntryView`) | WidgetKit (:240 families) | `AccessoryWidgetBackground` (:203) |
| S11 | **Live Activity: Lock Screen banner** | `myTeamWidget/GameLiveActivity.swift:79` (`GameActivityBanner`) | `ActivityConfiguration` (:20); started by `Home Menus/LiveActivityManager.swift:40`; attributes `Home Menus/GameActivityAttributes.swift` | — |
| S12 | **Live Activity: Dynamic Island** (compact, minimal, expanded) | `myTeamWidget/GameLiveActivity.swift:29` | Same activity | `GameActivityTeamScore` (:141) |

Notes:
- The task brief mentions a "score-alerts permissions view", but **there isn't one**. `Home Menus/ScoreAlertsPermissions.swift:22` is a non-UI `enum` around `UNUserNotificationCenter`. The only permission UI is the system prompt plus the status rows in S4.
- "Pick Your Teams" onboarding is S3 with a different title (`TabBar.swift:105`). "Game list" is the schedule carousel inside S2.

### 2b. All `View`-conforming types (58)

| File | Types (line) | Role |
|---|---|---|
| `NavigationBar/TabBar.swift` | `Home` (16), `TeamPage` (161), `TeamPicker` (267), `TopView` (326) | S1 screen + chrome |
| `Home Menus/TeamHomeView.swift` | `TeamHomeView` (18), `TeamHomeContent` (78), `RosterFilterMenu` (121) | S2 screen |
| `Home Menus/HomeSections.swift` | `SectionHeader` (13), `SectionStatusView` (43), `RosterSection` (68), `ScheduleSection` (152), `StandingsSection` (237), `StandingsTable` (303), `NewsSection` (411), `TeamHomeLayout` (464) | S2 sections |
| `Home Menus/TeamBrowserView.swift` | `TeamBrowserView` (96) | S3 screen |
| `Home Menus/AlertsSettingsView.swift` | `AlertsSettingsView` (35) | S4 screen |
| `Schedule/Views/GameView.swift` | `LoadingGameView` (11), `GameView` (23), `GameCardDetails` (234) | S2 schedule card |
| `Schedule/Views/GameDetailView.swift` | `GameDetailView` (20), `GameDetailDismissHandle` (290), `GameDetailSkeleton` (307) | S5 screen |
| `Schedule/Views/BoxScoreTables.swift` | `LinescoreView` (16), `HockeyBoxScoreView` (51), `HockeySkaterTable` (77), `HockeyGoalieTable` (123), `SoccerLineupsView` (159), `SoccerLineupRow` (190), `BoxScoreTeamTitle` (234), `BoxScoreText` (251) | S5 subviews |
| `Schedule/Views/StatRowView.swift` | `StatRowView` (13) | S5 subview |
| `Roster/Views/PlayerView.swift` | `PlayerCard` (16), `LoadingPlayerView` (53) | S2 roster card |
| `Roster/Views/PlayerDetailView.swift` | `PlayerDetailView` (454) | S6 screen |
| `Roster/Views/BioViews.swift`, `StatView.swift`, `StatPercentageView.swift` | `BioView` (11), `StatView` (11), `StatPercentageView` (11) | S6 cells |
| `Leaders/LeadersViews.swift` | `LeadersSection` (16), `TeamLeaderCard` (72), `LeaderHeadshot` (106), `LeagueLeadersView` (124), `LeaderRow` (221) | S2 section + S7 screen |
| `News/Views/NewsView.swift` | `LoadingNewsView` (12), `NewsView` (43) | S2 news card |
| `News/Views/NewsDetailView.swift` | `NewsDetailView` (17) (+ `SafariView` (68), a `UIViewControllerRepresentable`) | S8 screen |
| `Classes/LoadingView.swift` | `LoadingView` (11), `LoadingViewCircle` (40) | shared skeleton primitives |
| `Classes/CircularProgress.swift` | `CircularProgress` (3), `PercentageIndicator.CircularProgressView` (49) (+ `PercentageIndicator` `ViewModifier` (29)) | S6 gauge |
| `Networking/TeamLogo.swift` | `TeamLogo` (25), `MonogramTeam` (94) | shared crest primitives |
| `Networking/RemoteImage.swift` | `RemoteImagePlaceholder` (82), `RemoteImage` (96) | shared image primitives |
| `myTeamWidget/myTeamWidget.swift` | `WidgetEntryView` (118), `AccessoryEntryView` (195) (+ `TeamScheduleWidget` (237), `ScheduleWidgets` bundle (264)) | S9, S10 |
| `myTeamWidget/GameLiveActivity.swift` | `GameActivityBanner` (79), `GameActivityTeamScore` (141) (+ `GameLiveActivity` widget (18)) | S11, S12 |

---

## 3. Findings by screen

Severity: **P1** is a visible mismatch with GlassUI (opaque or hard-coded surfaces where glass is expected, non-standard controls, ignored system typography). **P2** is polish. **P3** is nice-to-have. IDs are stable so the plan in §4 can refer to them.

### X: Cross-cutting (applies to several screens)

**Styling inventory.** There are no tokens: 80 fixed font sizes, 30 `systemGray` foregrounds, radii of 1.5, 10, 15 and 20, ad-hoc paddings (5, 10, 15, 20, 25, 30), and opacities of 0.1, 0.15, 0.2, 0.5, 0.6, 0.7, 0.75 and 0.8. There are no shadows. The app target has no accent colour.

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| X-1 | **P1** | 80 `.font(.system(size:))` sites, e.g. `HomeSections.swift:24`, `GameView.swift:57`, `GameDetailView.swift:180`, `PlayerDetailView.swift:509`, `LeadersViews.swift:82`, `NewsView.swift:82` | Fixed point sizes ignore Dynamic Type and SF Pro optical-size switching (B7). Only 14 call sites use text styles. The one legitimate proportional size is the monogram at `TeamLogo.swift:112`. | Text styles everywhere, with a small named type ramp. | Phase 0 `Theme.Typography` (e.g. `static let sectionTitle = Font.title3.bold()`, `statFigure = Font.title2.weight(.black).monospacedDigit()`), then mechanical replacement. Pair with the fixed-frame fixes (T-, G-, N-, D-, P- items) so nothing clips. |
| X-2 | **P1** | `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` (19 flat PNG entries, no dark or tinted appearances); `project.pbxproj:1015`, `:1039` | Legacy flat icon. On iOS 26+ the system can't produce proper Dark, Clear or Tinted glass appearances from it (B14). | Layered Icon Composer `.icon` with per-layer glass. | Designer exports layers → Icon Composer → add the `.icon` to the app target and point the AppIcon build setting at it **(verify setting)**. Keep the PNG set until verified. |
| X-3 | P2 | 30 × `Color(uiColor: .systemGray)` foregrounds, e.g. `HomeSections.swift:21`, `:26`, `:52`, `:85`, `StatView.swift:44`, `LeadersViews.swift:90`, `GameDetailView.swift:253` | A fixed gray gets no vibrancy over glass or materials (B8), and the contrast doesn't change under Increase Contrast. | Hierarchical styles. | `.foregroundStyle(.secondary)` (or `.tertiary` for captions). |
| X-4 | P2 | Radii listed in §1.3 | Four unrelated radii with nothing concentric. Sheets use 10 inside 20 (`GameDetailView.swift:160` vs `:56`). | Concentric, tokenised geometry (B6). | `Theme.Radius` (`card`, `chip`, `inner`), and `ConcentricRectangle` where it's available **(verify)**. |
| X-5 | P2 | No accessibility environment reads anywhere. Custom opacity layers at `GameView.swift:137`, `TabBar.swift:191`, `NewsView.swift:71`, `PlayerDetailView.swift:516`, `GameDetailView.swift:171` | System glass adapts by itself, but these hand-rolled opacity layers don't respond to Increase Contrast or Reduce Transparency (B11). | Increase opacity under `.increased` contrast, and drop translucency under Reduce Transparency. | A `Theme` modifier `.adaptiveScrim(_:)` that reads `colorSchemeContrast` and `accessibilityReduceTransparency`. |
| X-6 | P2 | `Classes/LoadingView.swift:29-34`, `:57-62` | The skeleton pulses with `repeatForever` and ignores Reduce Motion (B11). | A static placeholder under Reduce Motion. | Check `accessibilityReduceMotion`, or replace the bespoke skeletons with `.redacted(reason: .placeholder)` on real layouts (see D-7). |
| X-7 | P2 | App catalog has no `AccentColor` colorset, and the app target has no `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (only the widget target does: `project.pbxproj:1063`, `:1088`). The widget's `AccentColor.colorset/Contents.json:2-6` defines no colour. | `Color.accentColor` (`TeamBrowserView.swift:215`, `:279`, `LeadersViews.swift:128`) falls back to system blue. Glass tint has no brand colour. | A defined app tint for `.glassProminent` and selection. | Add an `AccentColor` colorset (light/dark/high-contrast) to both catalogs and set the build setting on the app target. |
| X-8 | P2 | `TeamBrowserView.swift:184-187`, `LeadersViews.swift:145-147`, `NewsDetailView.swift:57-61` | Text "Done" buttons. iOS 26 sheets use glass icon buttons for close and confirm. | `Button(role: .close)` / `Button(role: .confirm)` in the toolbar **(verify roles)**. | Swap `Button("Done")` for the role-based button in the same `ToolbarItem`. |
| X-9 | P2 | All 6 `.sheet`s (§1.3); no `presentationDetents` anywhere | Every sheet opens at full height, so users never see the floating glass sheet at a partial detent (B12). | Detents that fit the content. | Game detail: `[.medium, .large]`. Leaders and browser: `.large`. Keep the player sheet at `.large`. |
| X-10 | P2 | `project.pbxproj:1032` (`TARGETED_DEVICE_FAMILY = "1,2"`); `Hawk Nation/Info.plist` iPad orientations | The iPad build is the stretched phone layout. There is no sidebar or `NavigationSplitView`, so iPad users don't get the glass sidebar. | `TabView` with `.tabViewStyle(.sidebarAdaptable)` or `NavigationSplitView` on regular width. | Defer to Phase 3, or decide in Phase 0 to drop iPad. |
| X-11 | P3 | 0 `sensoryFeedback` uses | No haptics on selection, follow or toggle. | Light haptics on discrete state changes. | `.sensoryFeedback(.selection, trigger: selection)` and similar (see H-7, B-4). |
| X-12 | P3 | 0 `contentTransition` / `symbolEffect` uses | Live scores and symbols swap instantly (B9, B10). | Numeric and symbol transitions. | `.contentTransition(.numericText(value:))` on score `Text`s (`GameView.swift:214`, `GameDetailView.swift:225`, `GameLiveActivity.swift:130`, `:152`). |
| X-13 | P3 | 0 `matchedTransitionSource` uses | Cards open sheets with the default slide. | Zoom from the source card (B10). | `.matchedTransitionSource(id: game.gameID, in: ns)` on the card, plus `.navigationTransition(.zoom(sourceID:in:))` on the sheet content. |

### S1: Home shell (`NavigationBar/TabBar.swift`)

**Styling inventory:**
- Team-colour hero `Rectangle`, 500 pt tall (:177-180), with the crest at `opacity(0.5)` (:191).
- Title at 35 pt bold, white (:199-203).
- Bottom crest picker: `LazyHStack(spacing: 4)` (:275); selected capsule in opaque `team.color` (:290); `.background(.bar)` (:321).
- "+" button: 35×35 circle filled with `Color.secondary.opacity(0.15)` (:301-304).
- Sticky `TopView` on `.bar` (:342-348), cross-faded in with `.transition(.opacity)` (:249).
- No `NavigationStack` and no `TabView`.

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| H-1 | **P1** | `TabBar.swift:84-88`, `:290`, `:319-321` | The crest picker is a full-width bar with a flat `.bar` blur, edge to edge with an opaque team-colour selection capsule. It doesn't get the floating, lensing, interactive glass capsule that iOS 26 tab bars use (B1, B2, B3). | A floating glass capsule inset from the edges. Selection shown as a tinted glass pill that morphs between items. | Keep the custom picker (a variable number of favorites doesn't fit `TabView`). Remove `.background(.bar)`, wrap the row in `GlassEffectContainer`, apply `.glassEffect(.regular, in: .capsule)` to the row, and use `.glassEffect(.regular.tint(team.color).interactive(), in: .capsule)` plus `.glassEffectID(team.id, in: ns)` on the selected crest. Pad horizontally so it floats. |
| H-2 | **P1** | `TabBar.swift:299-305` | The "+" is a hand-drawn circle (`Color.secondary.opacity(0.15)`) with a fixed 15 pt glyph. It's a non-standard control (B4). | A standard glass circle button. | `Button(action: editTeams) { Image(systemName: "plus") }.buttonStyle(.glass).buttonBorderShape(.circle)` inside the same `GlassEffectContainer`, so it can merge with the picker (`glassEffectUnion`). |
| H-3 | **P1** | `TabBar.swift:247-250`, `:326-349` (`.fill(.bar)` :346) | `TopView` is a hand-made navigation bar: an opaque `.bar` slab that cross-fades in over the scroll view. There's no scroll-edge effect and no glass (B5). | Content scrolls under a floating bar, and a scroll-edge effect keeps it legible. | Option A: put `TeamPage` in a `NavigationStack`, use `.navigationTitle(team.displayName)` with large-title collapse and the crest as a `ToolbarItem(placement: .principal)`. Option B: keep the custom bar but mount it with `.safeAreaBar(edge: .top)` **(verify)** so the system edge effect applies, and give the title a `.glassEffect(in: .capsule)`. Option A is recommended because it also fixes H-6 through `.toolbarColorScheme`. |
| H-4 | **P1** | `TabBar.swift:199-202` | The team title is `.font(.system(size: 35))`, which ignores Dynamic Type (B7). | Large-title style. | `.font(.largeTitle.bold())`. This goes away entirely with H-3 option A. |
| H-5 | P2 | `TabBar.swift:177-180`, `:186-195` | The hero is a fixed 500 pt colour slab under a crest that's offset and clipped by hand. It doesn't extend under the floating chrome. | Hero media that extends under bars (B5). | Apply `.backgroundExtensionEffect()` to the hero crest and colour group, and size it from geometry instead of 500 pt. |
| H-6 | P2 | `Hawk Nation/Info.plist:55-56` (`UIStatusBarStyleLightContent`) with no `UIViewControllerBasedStatusBarAppearance` | The status bar sits over arbitrary team colours. With view-controller-based appearance (the default), this key does nothing after launch, so light team colours can leave the status bar unreadable **(verify on device)**. | A legible status bar over the hero. | With H-3 option A, use `.toolbarColorScheme(…, for: .navigationBar)` chosen from `TeamColors.relativeLuminance` (`TeamLogo.swift:138`). Remove the dead plist key. |
| H-7 | P3 | `TabBar.swift:277-279`, `:312-318` | Selection switches with `.animation(.default)` and no haptic. | A glass morph and a selection haptic. | `glassEffectID` morph (H-1), `.animation(.bouncy, value: selection)`, `.sensoryFeedback(.selection, trigger: selection)`. |

### S2: Team page (`TeamHomeView.swift`, `HomeSections.swift`, `GameView.swift`, `PlayerView.swift`, `LeadersViews.swift`, `NewsView.swift`)

**Styling inventory:**
- Sections are opaque `systemBackground` slabs (`HomeSections.swift:144`, `:224`, `:289`, `:456`; `LeadersViews.swift:64`), separated by 5 pt `systemGray5` gutters (`HomeSections.swift:469`, `:473`, `:476`).
- Headers are 20 pt bold `systemGray` (`:24-26`).
- Carousels end in 10 pt `systemBackground` spacer views (`:138-139`, `:209-210`).
- Game cards are 120×160 at radius 10 (`GameView.swift:129-130`).
- Leader cards use radius 15 on `systemGray6` (`LeadersViews.swift:98-101`).
- News cards are 125 pt tall with radius-20 thumbnails (`NewsView.swift:73`, `:94`).
- Standings use 12–15 pt fixed type (`HomeSections.swift:349-388`).

> **Note (B1):** the fix for the section slabs is **not** glass. Glass on scrolling content cards is an anti-pattern: it costs GPU and it stacks glass on glass under the picker. Content stays on semantic grouped backgrounds. Glass is reserved for the controls that float above it.

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| T-1 | **P1** | `HomeSections.swift:81-99`, `:249-258` | Section-header controls are `Menu`s whose label is a bare 20 pt glyph tinted `systemGray`, padded only 5 pt. They're non-standard controls with roughly 30 pt hit targets, under the 44 pt minimum (B4, B11). | Standard glass buttons with circle borders, or one overflow menu. | `Menu { … } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)`, with `.accessibilityLabel` set. Put them in a `GlassEffectContainer(spacing: 8)`. |
| T-2 | **P1** | `HomeSections.swift:24`, `:50`, `:173`, `:349`, `:363`, `:378`, `:388`; `PlayerView.swift:33`, `:46`; `LeadersViews.swift:29`, `:82`, `:88`, `:93` | Fixed sizes for section titles, status text, the record, standings and roster and leader captions (X-1). | Text styles. | `.title3.bold()` for headers, `.subheadline` for the record, `.footnote`/`.caption` with `.monospacedDigit()` for standings, `.caption2` for captions. |
| T-3 | **P1** | `HomeSections.swift:133`, `:205` | Roster and schedule cards open sheets through `.onTapGesture`. VoiceOver doesn't treat them as buttons, and they have no pressed state or keyboard/pointer focus. | Real `Button`s (B11). | `Button { selectedPlayer = player } label: { card(player) }.buttonStyle(.plain)`, with an `accessibilityLabel` built from the name, number and position (and opponent, date and result for games). |
| T-4 | P2 | `HomeSections.swift:138-139`, `:144`, `:209-210`, `:224`, `:289`, `:456`, `:469`, `:473`, `:476`; `LeadersViews.swift:64`; `TeamHomeView.swift:92` | Edge-to-edge opaque slabs with 5 pt gray gutters and spacer views painted to match the slab. The corners are square and nothing is concentric with the device (B6). | Inset rounded content cards on grouped backgrounds. | `TeamHomeLayout`: `.background(Color(.systemGroupedBackground))`, sections `.background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.card))` with `.padding(.horizontal)`. Remove the spacer `Color` views and use `.contentMargins(.horizontal, 10, for: .scrollContent)` on the carousels. |
| T-5 | P2 | `HomeSections.swift:452-454` | A 40 pt `systemBackground` slab "clears the crest picker". With a floating glass picker (H-1), content should scroll under it (B5). | Safe-area-driven insets plus a scroll-edge effect. | Remove the slab. The bottom `safeAreaInset` at `TabBar.swift:84` already insets the scroll content. Add `.scrollEdgeEffectStyle(.soft, for: .bottom)` on the page scroll view. |
| T-6 | P2 | `LeadersViews.swift:25-31`, `:98-101` | The "NFL Leaders" link is plain text in the team colour (contrast depends on the team), and the leader cards' radius 15 matches nothing else. | A standard control and tokenised radius. | `.buttonStyle(.glass)` with `.tint(team.color)`, or a `Label(…, systemImage: "chevron.right")` trailing accessory. Use `Theme.Radius.inner` for the cards. |
| T-7 | P2 | `HomeSections.swift:389-391` | The followed standings row is marked only by bold weight and a 15% team-colour wash, which nearly disappears under Increase Contrast and in Dark Mode for dark team colours. | Meaning that doesn't depend on colour alone. | Add a leading `Image(systemName: "star.fill").symbolRenderingMode(.hierarchical)` or a capsule background whose opacity rises when `colorSchemeContrast == .increased`, plus `.accessibilityAddTraits(.isSelected)`. |
| T-8 | P3 | `HomeSections.swift:103-142`, `:178-222`; `LeadersViews.swift:51-61` | Carousels scroll freely and clip at the edges. | Paging that snaps to cards. | `.scrollTargetBehavior(.viewAligned)` + `.scrollTargetLayout()` + `.scrollClipDisabled()`. |
| G-1 | **P1** | `GameView.swift:57`, `:62`, `:121`, `:144`, `:149`, `:183`, `:203`, `:215`, `:223`, `:241`, `:271`; fixed frame `:14`, `:110`, `:126`, `:129` | Eleven fixed font sizes inside a fixed 120×160 card, plus `minimumScaleFactor(0.5)`, means text can't grow (B7). | Scalable card and type. | `@ScaledMetric(relativeTo: .body) var cardWidth = 120` (and the same for height). Use text styles. At `dynamicTypeSize.isAccessibilitySize`, switch the schedule to a vertical `List`. |
| G-2 | **P1** | `GameView.swift:111-126` | The "Info" footer is a fake button: a team-colour `RoundedRectangle` pill with 12 pt text on `systemGray4`. It isn't interactive (the whole card is), so it signals a control that doesn't exist. | No faux controls; status shown as content. | Replace it with a small status `Label` (e.g. "Final", "7:30 PM", "Live") in `.caption.weight(.semibold)` on `.background(.fill.tertiary, in: .capsule)`, or remove it once T-3 makes the card a `Button`. |
| G-3 | P2 | `GameView.swift:40-41`, `:134-138`, `:146`, `:152`, `:218`, `:226`, `:243`, `:273` | White text over `team.color` washed at 50%. White fails contrast on light team colours (e.g. a yellow primary). `TeamColors.monogramTextHex` (`TeamLogo.swift:163`) already solves this but isn't used here. | Legible ink on any team colour. | Pick the ink with `TeamColors.monogramTextHex`-style contrast (≥ 4.5:1 for body text). Strengthen the wash under `.increased` contrast (X-5). |
| G-4 | P2 | `GameView.swift:182-184`, `:202-204`, `:207-208` vs `:187-188` | Leading and trailing are shown only by a green or red arrow. The trailing branch shrinks its lines to 12 pt while the others use 15 pt. | Symbol shape plus an accessible label, and a consistent size. | `Image(systemName: lead ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").symbolRenderingMode(.hierarchical)` with `.accessibilityLabel(lead ? "Leading" : "Trailing")`. Use one `liveLine` size. |
| G-5 | P3 | `GameView.swift:213-219` | The live score jumps without animation. | A numeric transition. | `.contentTransition(.numericText(value: Double(liveScore.score)))` with `.animation(.snappy, value: liveScore)` (X-12). |
| N-1 | **P1** | `NewsView.swift:79`, `:82`, `:86`, `:90`; frames `:18`, `:27`, `:35`, `:37`, `:92`, `:94` | Fixed sizes from 10 to 15 pt in a fixed 125 pt card that's `containerSize.width - 30` wide, so headlines truncate at larger type. | Text styles and a self-sizing row. | `.caption2` for the source and date, `.headline` for the title, and `.subheadline` with `.lineLimit(3)` for the summary. Drop the fixed height and use a `@ScaledMetric` thumbnail size. |
| N-2 | P2 | `NewsView.swift:77-78`, `:88-89` | Source and date use `.primary.opacity(0.5)`, which skips the hierarchical styles (B8). | `.secondary` / `.tertiary`. | `.foregroundStyle(.secondary)`. |

### S3: Team browser (`Home Menus/TeamBrowserView.swift`)

**Styling inventory:**
- System `NavigationStack`, `List`, `.searchable`, and a toolbar with `EditButton` + Done (:130-188). This already renders as glass.
- Custom league chip strip in a top `safeAreaInset` on `.bar` (:174-176, :203-225). Selected chip is opaque `Color.accentColor`; unselected is `Color.secondary.opacity(0.15)`.
- Rows have a 24 pt crest, a league badge capsule (`Color.secondary.opacity(0.15)`, :273) and a checkmark glyph (:278-280).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| B-1 | **P1** | `TeamBrowserView.swift:174-176`, `:203-225` | An opaque `.bar` strip sits directly under the glass navigation bar, which is a double bar. List content scrolls under the nav bar but stops at the strip, so the scroll-edge effect breaks. The chips are `.plain` buttons with hand-painted capsules (B4, B5). | One continuous chrome region, with the chips as glass controls. | Remove `.background(.bar)`. Mount the strip with `.safeAreaBar(edge: .top)` **(verify)**, or as `ToolbarItem(placement: .bottomBar)` / a toolbar row, so it takes part in the edge effect. Render the chips in a `GlassEffectContainer`: selected `.buttonStyle(.glassProminent)`, others `.buttonStyle(.glass)`, `.buttonBorderShape(.capsule)`. Check where the `.searchable` field lands on iPhone in iOS 26/27 so it doesn't collide with a top strip **(verify)**. |
| B-2 | P2 | `TeamBrowserView.swift:278-280` | The follow state flips between `circle` and `checkmark.circle.fill` with no symbol rendering mode and no transition. | Hierarchical rendering and a replace transition (B9). | `.symbolRenderingMode(.hierarchical)` + `.contentTransition(.symbolEffect(.replace))`. |
| B-3 | P2 | `TeamBrowserView.swift:261-262`; `AlertsSettingsView.swift:111-112`; `TabBar.swift:281` | Crest sizes are fixed at 24 and 25 pt while the text next to them scales. | Icons that scale with text. | `@ScaledMetric(relativeTo: .body) private var crestSize: CGFloat = 24`. |
| B-4 | P3 | `TeamBrowserView.swift:252-258` | Follow and unfollow give no haptic. | Success haptic. | `.sensoryFeedback(.success, trigger: followed)` (X-11). |

### S4: Alerts settings (`Home Menus/AlertsSettingsView.swift`)

**Styling inventory:** system `List` with sections, header and footer (:44-64); `Label` with `.body.weight(.semibold)` (:84-85); `.footnote` + `.secondary` (:87-88); `.bordered` action (:94); `Toggle` rows (:106); `.caption2` badge (:116). **This is the most GlassUI-aligned screen in the app and is the reference for the rest.**

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| A-1 | P2 | `AlertsSettingsView.swift:84`; symbols from `AlertsSettings.swift:81`, `:89`, `:97`, `:110`, `:118` | The status symbols (`bell.badge`, `bell.slash`, `bell.fill`, `platter.filled.bottom.iphone`) use monochrome default rendering, so "denied" and "allowed" look the same. | Hierarchical or palette rendering that carries the state (B9). | `.symbolRenderingMode(.hierarchical)`, and `.foregroundStyle(.red)` for the `bell.slash` state (add a `tint` to `AlertsStatusRow`). |
| A-2 | P3 | `AlertsSettingsView.swift:91-94` | "Ask Now" / "Open Settings" are `.bordered`, even though they're the screen's primary action. | Primary actions use prominent styling. | `.buttonStyle(.borderedProminent)`. Keep glass styles out of list rows (B1). |

### S5: Game detail sheet (`Schedule/Views/GameDetailView.swift`, `BoxScoreTables.swift`, `StatRowView.swift`)

**Styling inventory:**
- Full-bleed opaque sheet: `.background(Color(uiColor: .systemBackground).ignoresSafeArea(.all))` and `.ignoresSafeArea(.all)` (:107-108).
- 200 pt venue header at radius 10, with a 60% team-colour-over-black scrim (:155-173).
- Custom 100×5 white "dismiss handle" button (:290-302).
- A 600 pt fixed `RoundedRectangle` card at radius 20 (:56-58).
- Score at 30 pt (:226), header lines at 15 pt with `minimumScaleFactor(0.2)` (:207-214).
- Box-score cells at 11/12 pt (`BoxScoreTables.swift:271`); stat rows at 20/15 pt with `minimumScaleFactor(0.1)` (`StatRowView.swift:21-36`).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| D-1 | **P1** | `GameDetailView.swift:176`, `:290-302`, `:322` | A hand-drawn white capsule acts as a dismiss button. It has **no accessibility label** (VoiceOver reads an unlabeled button), it duplicates the system grabber, and it's invisible on light venue images. | System grabber plus a glass close button (B4, B12). | `.presentationDragIndicator(.visible)` on the sheet, plus an overlay `Button(role: .close) { dismiss() }` **(verify role)** or `Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Close")` at the top trailing edge. |
| D-2 | **P1** | `GameDetailView.swift:98`, `:107-108`, `:234` | `.ignoresSafeArea(.all)` plus a full-bleed opaque background replaces the iOS 26 glass sheet surface and pushes the header under the status bar and Dynamic Island. | Let the sheet draw its own glass surface, and respect the safe area (B12). | Remove both modifiers and the redundant `.ignoresSafeArea()` on the scoreboard HStack. Use `.presentationDetents([.medium, .large])` (X-9). Let the venue header extend with `.backgroundExtensionEffect()` instead of ignoring safe areas. |
| D-3 | **P1** | `GameDetailView.swift:55-58`, `:96`; skeleton `:347-350` | The content card is a fixed `RoundedRectangle` 600 pt tall, sized to `containerSize.width - 25` and drawn **behind** a VStack. Hockey or soccer tables and larger type overflow past it, and short content leaves blank card. | A card that sizes to its content. | `VStack { … }.padding(20).background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.card))`, with no fixed height. |
| D-4 | **P1** | `GameDetailView.swift:180-181`, `:210`, `:213`, `:226`, `:252`, `:273`, `:280`; `StatRowView.swift:21`, `:27`, `:31`, `:36`; `BoxScoreTables.swift:204`, `:243`, `:271` | Fixed sizes, with `minimumScaleFactor` as low as 0.2 and 0.1, shrink text to unreadable sizes instead of reflowing (B7). | Text styles that wrap. | Use `.title.bold().monospacedDigit()` for the score, `.subheadline` for header lines, `.title3.bold()` / `.subheadline` for stat rows, and `.caption.monospacedDigit()` for box-score cells. Keep a minimum scale of at least 0.8. Box-score grids get a horizontal `ScrollView` at AX sizes. |
| D-5 | P2 | `GameDetailView.swift:155-173` | The venue header uses radius 10 inside a radius-20 sheet card (not concentric, X-4), and a flat 60% scrim. | Concentric radius, with the hero extending under the chrome. | `Theme.Radius`/`ConcentricRectangle` **(verify)**, a bottom-weighted `LinearGradient` scrim, and `.backgroundExtensionEffect()` on the image. |
| D-6 | P2 | `BoxScoreTables.swift:202-228` | Soccer goals, yellow and red cards, and substitutions (green and red arrows) are shown by colour and shape only, with no accessibility labels. | Accessible meaning. | `.accessibilityElement(children: .combine)` on `SoccerLineupRow` with a label like "2 goals, yellow card, substituted 67′". Arrows use `.symbolRenderingMode(.hierarchical)`. |
| D-7 | P2 | `GameDetailView.swift:307-385`; `Classes/LoadingView.swift` | An 80-line skeleton duplicates the layout's fixed geometry, so any layout fix has to be made twice. | Placeholder derived from the real layout. | Render the real header and scoreboard with placeholder data and `.redacted(reason: .placeholder)`. Delete `GameDetailSkeleton`. |

### S6: Player detail sheet (`Roster/Views/PlayerDetailView.swift` + cells)

**Styling inventory:**
- Full-bleed opaque sheet with `.ignoresSafeArea(.all)` (:555-556).
- Team-colour header (`Rectangle` + `RoundedRectangle(cornerRadius: 20)`, :476-481) with a 10%-opacity crest watermark (:484-487).
- Custom dismiss capsule (:491-498).
- Name and number at 35 pt (:507-517).
- Hand-built segmented control (:528-538, :564-577).
- Fixed-height content card (`grid.cardHeight`, :63-71, :582-584).
- Cells sized `containerSize.width/4 × width/3` (`StatView.swift:48`, `BioViews.swift:50`, `StatPercentageView.swift:53`).
- Custom half-ring gauge (`CircularProgress.swift:57-82`).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| P-1 | **P1** | `PlayerDetailView.swift:528-538`, `:564-577` | The About/Statistics switcher is a hand-built segmented control: two `.plain` buttons over `systemBackground` rectangles. Selection shows only as opacity 1.0 vs 0.8 (:573), which is close to invisible, and VoiceOver gets no `isSelected` trait. | System segmented picker, which is glass on iOS 26 (B4). | `Picker("Section", selection: $pickerSelectedItem) { Text("About").tag(0); Text("Statistics").tag(1) }.pickerStyle(.segmented)`. |
| P-2 | **P1** | `PlayerDetailView.swift:490-498` | The same unlabeled custom dismiss capsule as D-1. | System grabber plus a glass close button. | Same as D-1. Extract a shared `SheetCloseButton` in Phase 0. |
| P-3 | **P1** | `PlayerDetailView.swift:555-556`, `:614` | An opaque full-bleed background with `.ignoresSafeArea(.all)` replaces the glass sheet surface (B12). | As D-2. | Remove both. Extend the team-colour header with `.backgroundExtensionEffect()`. |
| P-4 | **P1** | `PlayerDetailView.swift:509`, `:514`, `:590`, `:603`; `BioViews.swift:22`, `:31`, `:41`; `StatView.swift:21`, `:30`, `:39`; `StatPercentageView.swift:36`, `:45`; `CircularProgress.swift:79` | 35 pt name and number, then 15–20 pt cells inside frames fixed at `width/4 × width/3`, with `minimumScaleFactor(0.5)` (B7). | Text styles with adaptive cell geometry. | `.largeTitle.bold()` for the name; `.title2.weight(.black).monospacedDigit()` for figures and `.caption.weight(.semibold)` for titles. Replace the HStack-of-fixed-cells with `Grid` or `LazyVGrid(columns: [GridItem(.adaptive(minimum: @ScaledMetric 96))])`. |
| P-5 | **P1** | `PlayerDetailView.swift:63-71`, `:580-584`, `:628-631` | Card height is computed as `120 × rows` (or `130 × (rows+1)`) and drawn behind the content. At larger type the content overflows the card, and blank `Color.clear` cells pad out the rows. | A card that sizes to its content. | `.background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.card))` on the grid. Delete `cardHeight`, `blankFact` and `blankStat` padding once the grid is adaptive. |
| P-6 | P2 | `CircularProgress.swift:20-84`; `StatPercentageView.swift:25-31`, `:60-80` | A custom half-ring gauge with a scaling percentage label (`:81`), hand-rolled colour lightening, and force-unwraps (`color.darker()!`, `:29-30`). It has no accessibility value. | A system gauge. | `Gauge(value: progress) { Text(title) } currentValueLabel: { Text(progress, format: .percent.precision(.fractionLength(0))) }.gaugeStyle(.accessoryCircularCapacity).tint(teamColor)`. Remove the `UIColor` extension. |
| P-7 | P3 | `PlayerDetailView.swift:543-547`, `:566` | Switching tabs swaps content with no transition. | A smooth switch. | `.animation(.snappy, value: pickerSelectedItem)` with `.transition(.blurReplace)`. |

### S7: League leaders sheet (`Leaders/LeadersViews.swift:124-269`)

**Styling inventory:** system `NavigationStack` with an inline title and a Done toolbar item (:140-149), `.insetGrouped` `List` (:193), and rows with 10–17 pt fixed type (:230-263). The followed team's rows use `teamColor.opacity(0.15)` (:267).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| LL-1 | **P1** | `LeadersViews.swift:174`, `:230`, `:239`, `:244`, `:249`, `:259`, `:263` | Fixed sizes in list rows that are otherwise system rows. | Text styles. | `.subheadline.monospacedDigit()` for the rank, `.body` for the name, `.caption` for team and position, `.caption2` for detail, `.headline.monospacedDigit()` for the value. |
| LL-2 | P2 | `LeadersViews.swift:240`, `:267` | Followed players are marked only by bold weight and a 15% tint (the same problem as T-7). | Colour-independent marking. | Add a team crest or `star.fill` badge and `.accessibilityAddTraits(.isSelected)`. Increase the tint under Increase Contrast. |
| LL-3 | P3 | `LeadersViews.swift:172-176` | The season caption sits in a bare first list row. | A title subtitle. | `.navigationSubtitle(Self.caption(leaders))` **(verify iOS availability)**, or a list `Section` header. |

### S8: News detail sheet (`News/Views/NewsDetailView.swift`)

**Styling inventory:** a hand-built 44 pt header (`HStack`: source in `.headline`, author in `.caption`, a Done button in `.primary`, :42-65) over a `Divider()` (:25) and an `SFSafariViewController` (:27-29); opaque `systemBackground` (:39).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| ND-1 | **P1** | `NewsDetailView.swift:23-25`, `:42-65` | A custom navigation bar (fixed 44 pt height, text Done button, hairline divider) above Safari, which on iOS 26 draws its own glass toolbars. The result is a flat bar stacked above glass chrome. | One chrome layer (B1). | Option A, simplest: present `SafariView` alone, since it has its own Done and glass bars, and set `.preferredControlTintColor`. Option B: `NavigationStack` with `.navigationTitle(article.source)` + `.navigationSubtitle(author)` **(verify)** and `ToolbarItem { Button(role: .close) }`. |
| ND-2 | P3 | `NewsDetailView.swift:19` | The `color` property is passed in (`HomeSections.swift:458`) but never used. | Brand-tinted Safari controls. | Map it to `SFSafariViewController.preferredControlTintColor` in `makeUIViewController` (`:78-82`). |

### S9: Home Screen widget (`myTeamWidget/myTeamWidget.swift:118-190`)

**Styling inventory:** `containerBackground` is the team colour plus a 10% watermark logo (:172-188); all text is white at fixed 12/16 pt (:142-166); images use `.renderingMode(.original)` (:151, :179); systemMedium reuses the small layout (:131-133).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| W-1 | **P1** | `myTeamWidget.swift:145`, `:151`, `:158`, `:162`, `:166`, `:172-188` | There's no `widgetRenderingMode` handling. In the Home Screen Clear and Tinted appearances (accented rendering, container background removed **(verify iOS 27 mapping)**), the white text, the `.original` full-colour crest and the team-colour background all render wrong or disappear. | Content adapts to `.fullColor`, `.accented` and `.vibrant` (B13). | `@Environment(\.widgetRenderingMode) var mode`. Use `.foregroundStyle(mode == .fullColor ? .white : .primary)`, `.widgetAccentable()` on the team name, and `Image(...).widgetAccentedRenderingMode(.desaturated)` (or `.accentedDesaturated`) on the crest. Draw the watermark only when `mode == .fullColor`. |
| W-2 | P2 | `myTeamWidget.swift:143`, `:157`, `:161`, `:165` | Fixed 16/12 pt type. | Text styles (widgets honor Dynamic Type within limits). | `.headline` for the team name and `.caption` for detail lines. |
| W-3 | P2 | `myTeamWidget.swift:131-133` | systemMedium centres the small column in a wide tile, which wastes space. | A layout for each family. | A medium layout: crest on the left, matchup, date, time and channel on the right. |

### S10: Lock Screen accessory widgets (`myTeamWidget.swift:195-230`)

**Styling inventory:** the circular widget uses `AccessoryWidgetBackground` (:203) with 11/10 pt fixed text (:206, :208). The rectangular widget uses `.headline` + `.widgetAccentable()` (:217-218) and `.secondary` (:221). Both use a clear container background (:228), which is correct.

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| AC-1 | P2 | `myTeamWidget.swift:205-209` | The circular widget shows two fixed-size text lines with no visual anchor. | A glanceable symbol or crest plus one value. | Show the opponent abbreviation in `.caption2.weight(.semibold)` over the time, or the crest with `widgetAccentedRenderingMode(.accented)`. Use text styles. |

### S11: Live Activity, Lock Screen banner (`myTeamWidget/GameLiveActivity.swift:79-138`)

**Styling inventory:** `.activityBackgroundTint(Color.black.opacity(0.75))` (:23), all content `.foregroundStyle(.white)` (:110), text styles that scale (:95, :99, :126, :131), and good VoiceOver labels (:121-136).

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| LA-1 | **P1** | `GameLiveActivity.swift:23-24`, `:110` | A hard-coded 75% black slab with white ink. It doesn't follow light or dark Lock Screen appearance and reads as a dark rectangle among the system's translucent glass platters **(verify current iOS 27 Lock Screen treatment)**. | System-adaptive background, or the team colour used deliberately. | Either `.activityBackgroundTint(nil)` (system default) with `.primary`/`.secondary` foregrounds, or a team-colour tint with contrast-checked ink (as G-3). Keep `activitySystemActionForegroundColor` consistent with the choice. |
| LA-2 | P2 | `GameLiveActivity.swift:79-113` | No `isLuminanceReduced` handling for Always-On. Bright white text at full weight stays lit. | Dimmed treatment on Always-On (B13). | `@Environment(\.isLuminanceReduced)`: use `.secondary` for non-score text and hide the stale caption. |
| LA-3 | P3 | `GameLiveActivity.swift:118-137` | Text-only rows with no team identity and no animation when the score changes. | Crests (pre-rendered into the shared container) and numeric transitions. | Add small crest images from the app group store. Use `.contentTransition(.numericText(value:))` on scores (X-12). |

### S12: Live Activity, Dynamic Island (`GameLiveActivity.swift:29-71`, `:141-160`)

**Styling inventory:** fixed sizes by design (the comment at :36-37 explains this), `.monospacedDigit()` throughout, and VoiceOver labels on the compact and minimal views (:61, :69). No `keylineTint`.

| ID | Sev | Where | What's wrong | What GlassUI wants | Fix sketch |
|---|---|---|---|---|---|
| DI-1 | P2 | `GameLiveActivity.swift:51-56` | The compact leading view is only the stage text ("Q4 0:48"), so nothing says which app or team it is. HIG asks the leading side to identify the activity. | An identity mark on the leading side. | Show the followed team's abbreviation or crest in compact leading, and move the stage to compact trailing alongside the score, or keep it in expanded only. |
| DI-2 | P3 | `GameLiveActivity.swift:29-71` | No `keylineTint`, and the scores don't animate. | Brand keyline and numeric transitions. | `.keylineTint(teamColor)` on `DynamicIsland`, and `.contentTransition(.numericText(value:))` on `:58` and `:152`. |

### 3b. Summary counts

| Screen | P1 | P2 | P3 | Total |
|---|---:|---:|---:|---:|
| X: Cross-cutting | 2 | 8 | 3 | 13 |
| S1: Home shell | 4 | 2 | 1 | 7 |
| S2: Team page (T, G, N) | 6 | 7 | 2 | 15 |
| S3: Team browser | 1 | 2 | 1 | 4 |
| S4: Alerts settings | 0 | 1 | 1 | 2 |
| S5: Game detail | 4 | 3 | 0 | 7 |
| S6: Player detail | 5 | 1 | 1 | 7 |
| S7: League leaders | 1 | 1 | 1 | 3 |
| S8: News detail | 1 | 0 | 1 | 2 |
| S9: Home Screen widget | 1 | 2 | 0 | 3 |
| S10: Lock Screen accessories | 0 | 1 | 0 | 1 |
| S11: Live Activity banner | 1 | 1 | 1 | 3 |
| S12: Dynamic Island | 0 | 1 | 1 | 2 |
| **Total** | **26** | **30** | **13** | **69** |

---

## 4. Phased remediation plan

Estimates are for one iOS engineer who knows the codebase, and include previews and UI-test updates. They don't include design time, except where noted.

### Phase 0: Foundation (design tokens, glass primitives, platform decisions) · 2.5–3.5 dev-days

| Step | Work | Findings unblocked |
|---|---|---|
| 0.1 | **Decide the deployment-target policy** (§6). Recommendation: stay on iOS 26.0, build with the iOS 27 SDK, and put any iOS 27-only API behind `#available` inside the theme layer. Move CI from `macos-26` (`ios-gate.yml:11`, and the signed gate) to an Xcode 27 image **(verify image name)**. | all |
| 0.2 | **Create `Hawk Nation/Classes/Theme.swift`** (proposed path) with: `Theme.Typography` (named text styles: `sectionTitle`, `cardTitle`, `statFigure`, `caption`…), `Theme.Spacing` (4/8/12/16/20), `Theme.Radius` (`card` 20, `inner` 12, `chip` = capsule) or `ConcentricRectangle` **(verify)**, and `Theme.Surface` (content = grouped backgrounds; chrome = glass). | X-1, X-3, X-4, T-4 |
| 0.3 | **Glass primitives** as `View` extensions so call sites never branch: `glassChrome(in:tint:interactive:)` (wraps `.glassEffect`), `SheetCloseButton` (glass `xmark`, labelled, D-1/P-2), `adaptiveScrim(_:)` (reads `colorSchemeContrast` and `accessibilityReduceTransparency`), and `teamInk(on:)` (contrast-picked foreground using `TeamColors`). | H-1, H-2, D-1, P-2, G-3, X-5 |
| 0.4 | **Asset catalog**: add `AccentColor` (any/dark/high-contrast) to `Hawk Nation/Resources/Assets.xcassets`, set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` on the app target, and fill the empty widget `AccentColor.colorset`. Start Icon Composer work on the app icon (**+1–2 designer-days**). | X-7, X-2 |
| 0.5 | **Info.plist**: don't add `UIDesignRequiresCompatibility`. Remove the dead `UIStatusBarStyle` (`Info.plist:55-56`) once H-6 is handled. | H-6 |
| 0.6 | **Cleanup**: remove the now-dead `if #available(iOS 16.2, *)` (`MyTeamsApp.swift:51`) and `@available(iOS 16.2, *)` (`GameLiveActivity.swift:17`, `:78`, `:171`; `LiveActivityManager.swift:40`; `GameActivityAttributes.swift:102`), since the target is already 26.0. | — |
| 0.7 | **Verification harness**: XCUITest screenshot pass (extend `myTeamsUITests/`) at Dynamic Type `.large`, `.xxxLarge` and `.accessibility3`; Light and Dark; Increase Contrast; Reduce Transparency. Add widget previews for `.fullColor` and `.accented`. | regressions in all phases |

### Phase 1: P1 structural · 9–12 dev-days

Work in this order, because the typography and geometry changes have to land together (see §5.3):

| Step | Work | Findings | Est. |
|---|---|---|---|
| 1a | **Typography + fixed geometry** across cards, sections and sheets: text styles from `Theme.Typography`; `@ScaledMetric` card sizes; drop the fixed heights (`GameView.swift:129`, `NewsView.swift:94`, `GameDetailView.swift:57`, `PlayerDetailView.swift:63-71`, cell frames). | X-1, H-4, T-2, G-1, N-1, D-4, P-4, P-5, D-3, LL-1 | 3.5–4.5 d |
| 1b | **Floating glass chrome on Home**: glass crest picker and "+" in a `GlassEffectContainer`; replace `TopView` with a `NavigationStack` title (option A) or a `safeAreaBar` (verify) glass bar. | H-1, H-2, H-3 | 2–2.5 d |
| 1c | **Sheets use the system surface**: remove `.ignoresSafeArea(.all)` and the opaque backgrounds; add `SheetCloseButton` and the drag indicator; segmented `Picker`; news sheet presents Safari directly or in a `NavigationStack`. | D-1, D-2, P-1, P-2, P-3, ND-1 | 1.5–2 d |
| 1d | **Standard controls on the team page and browser**: header `Menu`s become glass circle buttons; cards become `Button`s; league chips become glass buttons with the strip mounted as a bar. | T-1, T-3, G-2, B-1 | 1–1.5 d |
| 1e | **Extension surfaces**: widget `widgetRenderingMode` handling; Live Activity background and ink. | W-1, LA-1 | 1 d |
| 1f | **App icon**: integrate the Icon Composer `.icon` (after the 0.4 design work). | X-2 | 0.5 d |

Dependencies:
- 1a needs 0.2.
- 1b and 1c need 0.3.
- 1e needs device testing on both the Lock Screen and the Home Screen Clear and Tinted appearances.
- 1f needs the designer deliverable.
- None of it needs `#available` while the target is 26.0.

### Phase 2: P2 polish · 6–8 dev-days

| Step | Work | Findings | Est. |
|---|---|---|---|
| 2a | Content surfaces: grouped backgrounds, inset rounded section cards, remove spacer views, bottom scroll-edge effect, hero `backgroundExtensionEffect`. | T-4, T-5, H-5, D-5, X-4 | 2 d |
| 2b | Vibrancy and colour semantics: `.secondary` everywhere, contrast-picked ink on team colours, colour-independent highlights, symbol rendering modes. | X-3, N-2, G-3, G-4, T-6, T-7, LL-2, A-1, B-2, D-6 | 2 d |
| 2c | Accessibility environment: adaptive scrims, Reduce Motion skeletons via `.redacted`, `@ScaledMetric` crests, system `Gauge` in place of `CircularProgress`. | X-5, X-6, D-7, B-3, P-6 | 1–1.5 d |
| 2d | Presentation and toolbar: detents, close/confirm roles, status bar colour scheme, accent colour adoption. | X-8, X-9, H-6, X-7 | 0.5–1 d |
| 2e | Extensions: widget type, medium layout, accessory layout, Always-On, Dynamic Island identity. | W-2, W-3, AC-1, LA-2, DI-1 | 1–1.5 d |
| 2f | **Decision**: iPad sidebar (`.sidebarAdaptable` / `NavigationSplitView`), or drop iPad. If kept, add **+3–4 d** (likely its own epic). | X-10 | 0 / 3–4 d |

### Phase 3: P3 delight · 3–4 dev-days

| Work | Findings | Est. |
|---|---|---|
| Glass morph and haptics on crest selection; follow haptics. | H-7, B-4, X-11 | 0.5–1 d |
| Numeric score transitions (app, Live Activity, Dynamic Island) and `keylineTint`; Live Activity crests. | G-5, X-12, LA-3, DI-2 | 1–1.5 d |
| Zoom transitions from cards to sheets (`matchedTransitionSource`). | X-13 | 0.5–1 d |
| Snapping carousels, tab-switch transition, `navigationSubtitle` caption, prominent alerts action, Safari tint. | T-8, P-7, LL-3, A-2, ND-2 | 0.5–1 d |

**Total: about 21–28 dev-days** (Phase 0: 2.5–3.5, Phase 1: 9–12, Phase 2: 6–8, Phase 3: 3–4), plus 1–2 designer-days for the icon, plus 3–4 days if the iPad sidebar is kept.

---

## 5. Risks

### 5.1 Backwards compatibility
- **iOS 26 APIs don't need shims.** The project-level `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`project.pbxproj:945`, `:1001`; no target overrides) covers the app, the widget and the tests, so every API in §1.1 can be called directly.
- **Leaking an iOS 27-only API** is the real risk. Without an `#available` check the build fails, which is safe. With a check in the wrong place, iOS 26 users get a degraded path nobody tested. Mitigation: keep iOS 27 branches only inside `Theme.swift` primitives, and run CI against both an iOS 26 and an iOS 27 simulator.
- **Linking against the iOS 27 SDK changes system-component visuals by itself** (linked-on-or-after). Do a visual regression pass on the "free glass" components in §1.3 before shipping even a no-UI-change build.
- **Compatibility opt-out.** If iOS 27 drops `UIDesignRequiresCompatibility` **(verify)**, there's no escape hatch, but this app never used it, so there's nothing to lose.

### 5.2 Layered-material GPU cost
- Each glass shape samples and blurs the content behind it. The live team page already does a lot every frame: carousels, polling every 10 s, remote images. **Don't put glass on scrolling cards** (roster, schedule, leaders, news). That's B1, and it's also the most expensive case, because a `LazyHStack` of glass cards re-samples on every scroll frame.
- Group adjacent glass (picker items and "+", header buttons) in one `GlassEffectContainer` so they share one sampling pass.
- Avoid glass over glass: the picker over the page, with a glass sticky bar at the top, is the maximum. Nothing glass should sit inside sheets except the close button.
- Profile on the oldest supported iOS 26 device class **(verify the minimum device list for iOS 26/27)** with Instruments' SwiftUI and Core Animation hitch templates. Use the current build as the baseline, and budget no new hitches when scrolling the team page.
- The existing per-page polling design (`TabBar.swift:55-59`) keeps only one page mounted, which also limits how much glass is on screen.

### 5.3 Dynamic Type and accessibility regressions
- **The biggest regression risk is Phase 1a done halfway.** Switching to text styles while the 120×160 (`GameView.swift:129`), 125 pt (`NewsView.swift:94`), 600 pt (`GameDetailView.swift:57`) and `width/4 × width/3` (`StatView.swift:48`, etc.) frames remain will clip text at larger sizes that today merely shrinks through `minimumScaleFactor`. Ship type and geometry in the same PR per screen.
- At accessibility sizes, horizontal carousels and nine-column hockey tables (`BoxScoreTables.swift:82-113`) need alternative layouts: vertical lists, and horizontally scrollable grids.
- Glass legibility over team colours: tinted glass over a bright team colour (e.g. yellow) can fall below 4.5:1. Always choose ink through the contrast helper (`TeamColors.contrastRatio`, `TeamLogo.swift:149`).
- Replacing custom controls with system ones (P-1, D-1, T-3) changes the accessibility tree. Update the UI tests that query identifiers (e.g. `teamPicker.team.*` at `TabBar.swift:295`, `teamBrowser.done` at `TeamBrowserView.swift:186`) and keep the identifiers on the new controls.

### 5.4 Widget and Live Activity constraints
- Widgets and Live Activities render as archived, non-interactive snapshots. Arbitrary materials, live blur and `glassEffect` aren't the tool there **(verify whether iOS 27 permits glass in widget content)**. The system supplies the glass (Clear/Tinted Home Screen, Lock Screen platter), and the extension's job is to adapt to `widgetRenderingMode` and `isLuminanceReduced` (W-1, LA-2).
- `containerBackground` is removed in some appearances, so anything important can't live only in the background. Today the team colour and watermark do (`myTeamWidget.swift:172-188`).
- Live Activity content-state updates have a size budget (about 4 KB), so crests can't travel in the push or update payload. Pre-render them into the app-group store the widget already reads (`WidgetScheduleLoader`).
- Dynamic Island regions are system-sized. Fixed fonts are acceptable there (the existing comment at `GameLiveActivity.swift:36-37`), but the Lock Screen banner must keep scaling with text styles, as it does now.
- The widget extension shares the project deployment target. Any iOS 27-only WidgetKit API needs the same `#available` discipline.

---

## 6. iOS 26-compatible vs iOS 27-only: what changes

| | **Stay on 26.0 (recommended)** | **Bump to 27.0** |
|---|---|---|
| Build settings | No change to `IPHONEOS_DEPLOYMENT_TARGET` (`project.pbxproj:945`, `:1001`). | Set both project-level entries to `27.0`. The app, widget and test targets inherit them (no target overrides exist). |
| SDK / CI | Build with the Xcode 27 / iOS 27 SDK. Move `runs-on: macos-26` (`ios-gate.yml:11` and the signed-gate workflow) to an image with Xcode 27 **(verify)**. Keep an iOS 26 simulator in the test matrix. | Same SDK move, with only an iOS 27 simulator. |
| iOS 26 glass APIs (§1.1) | Call directly; no shims. | Call directly. |
| iOS 27-only APIs | Only inside `Theme.swift` primitives: `if #available(iOS 27, *) { new } else { iOS 26 equivalent }`. Call sites stay unconditional. | Call directly and delete the shims. |
| Existing availability checks | `@available(iOS 16.2, *)` / `#available(iOS 16.2, *)` (`MyTeamsApp.swift:51`, `GameLiveActivity.swift:17`, `:78`, `:171`, `LiveActivityManager.swift:40`, `GameActivityAttributes.swift:102`) are already dead. Remove them in 0.6. | Same. |
| Users | Everyone on iOS 26 keeps getting updates. | Drops iOS 26 users and any device iOS 27 doesn't support **(verify device list)**. Check analytics before deciding. |
| Test surface | Two OS versions × the a11y matrix (§0.7). | One OS version. |
| Info.plist | No changes needed for glass. | Same. |

**Recommendation:** stay on iOS 26.0. Nothing in this plan's P1 or P2 work needs an iOS 27-only API. If a verified iOS 27 addition turns out to be worth it, adopt it later through the theme shim without changing the target.

---

## Appendix: verification method

- **Inventory:** `grep -rn -E "struct .*: View" "Hawk Nation" myTeamWidget` (58 view types), cross-checked by reading every view file in full.
- **API delta:** repo-wide `grep` for every API named in §1.3; the counts quoted are from `grep -c` / `wc -l` at `7908cce`.
- **Build facts:** `myTeams.xcodeproj/project.pbxproj`, `Hawk Nation/Info.plist`, `myTeamWidget/Info.plist`, both `Assets.xcassets`, `.github/workflows/ios-gate.yml`.
- **What I didn't do:** no runtime screenshots or Instruments traces (no macOS host in this environment). Items marked "verify on device" need a device or simulator pass before implementation.
