# myTeams app review, pass 3: bugs, alignment, next features

*Task t_9463fc21, 2026-10-04. Audited at `a54c70c` (origin/main tip) on branch `wt/t_9463fc21`. This is a docs-only change; no app code was modified.*

**Swept:** every Swift file in `Hawk Nation/**` (59 files, ~14.9k lines), `myTeamWidget/**` (4 files), `myTeamsTests/**` (38 suites plus `Fixtures/`) and `myTeamsUITests/**` (2 files). I also read `Hawk Nation/Info.plist`, the logo, launch-colour and app-icon asset catalogs, and the relevant `project.pbxproj` settings. The recent waves (per `git log --oneline -40`) were the pinned header bar, the native glass tab bar with auto-collapse, Settings, the branded splash and in-app logos, the redesigned schedule cards, club search dedupe, and the Bundesliga, Serie A, Ligue 1 and UCL catalog. I read every one of those in full.

**Method:** static reading only. This host has no `xcodebuild`, so nothing was built or run. Every finding cites the code it rests on. Findings that also need a device or simulator check say **needs verification** and name what to check. Status strings and group names were checked against the captured ESPN fixtures in `myTeamsTests/Fixtures/`.

**Severity:** **S1** crash or data loss · **S2** user-visible breakage · **S3** polish. Features (bucket C) are ranked by value and effort instead.

---

## Summary

| Bucket | S1 | S2 | S3 | Unrated | Total |
|---|---:|---:|---:|---:|---:|
| A. Bugs | 2 | 7 | 11 | – | **20** |
| B. Alignment / visual consistency | 0 | 3 | 14 | – | **17** |
| C. Features worth adding next | – | – | – | 9 | **9** |
| **Total** | **2** | **10** | **25** | **9** | **46** |

Both S1s are crash paths behind malformed feed values. They are unlikely to fire, but each fix is a line or two (A-9, A-10).

The S2s fall into a few groups:
- **Data that is wrong or stale on screen:** A-1, A-2, A-3.
- **State lost from the UI:** A-4 (favorites dropped from the tab bar), A-5 (Settings closes itself).
- **Colour handling:** A-6, B-1, B-2, B-3.
- **A European-league gap:** A-7.

### Carried over from `docs/UI_AUDIT_IOS27_GLASSUI.md`

That doc doesn't mark anything as done, so every item was checked against the current code instead. Most of its 69 findings are fixed in code, and many fixes cite the old ID in a comment. Spot checks:
- **X-1:** the only `.font(.system(size:))` left is the deliberate monogram at `TeamLogo.swift:114`.
- **X-3:** no `systemGray` remains.
- **X-7:** `AccentColor` is set on the app target (`project.pbxproj:1054`).
- **H-1…H-7:** replaced by the native `TabView` (`TabBar.swift:158-176`).
- **H-6:** `UIStatusBarStyle` is gone from `Info.plist`.
- **D-1, P-2:** the shared `SheetCloseButton` (`Theme.swift:510-537`).
- **T-1…T-8:** done in `HomeSections.swift`.
- **W-1…W-3:** done in `myTeamWidget.swift`.
- **LA-1, LA-2:** done in `GameLiveActivity.swift`.

Four items are **still open, or only partly done**, and are carried into this pass:

| Old ID | Status in code | Carried as |
|---|---|---|
| X-2 app icon | Light and dark 1024 px only; no tinted or clear appearance and no `.icon` (`AppIcon.appiconset/Contents.json:2-20`) | B-15 |
| X-10 iPad | Still the phone layout: no `sidebarAdaptable` anywhere | B-14 |
| DI-1 / DI-2 island identity | Done only for the four bundled teams | B-13 |
| X-11 haptics | One `sensoryFeedback` in the whole app (`TeamBrowserView.swift:557`) | C-4 |

---

## A. Bugs

| ID | Sev | Where | Evidence | Impact | Proposed fix |
|---|---|---|---|---|---|
| **A-1** | S2 | `Schedule/Classes/DownloadScheduleData.swift:147-155`, `:163-169`, `:202`, `:231-235` | `eventDateParser` uses a fixed `"yyyy-MM-dd HH:mm"` format with **no `en_US_POSIX` locale and no Gregorian calendar**. By contrast, `scoreboardDayFormatter` (`DownloadScoreboardData.swift:16-17`) and `httpDateParser` (`HTTPClient.swift:274`) both set them. | On devices whose 12/24-hour override or non-Gregorian calendar (Buddhist, Japanese) changes how fixed formats parse (Apple QA1480), `parseGameDate` returns `nil` or the wrong year. A `nil` leaves `dateAsDate = Date()` and `date = ""`. The result: every card reads "TBD" (`GameView.swift:415`), every unfinished game falls inside the live-poll window (`TeamModel.swift:488-493`), and the widget reports "season over" (`WidgetScheduleLoader.swift:98-101`). | Set `locale = Locale(identifier: "en_US_POSIX")` and `calendar = Calendar(identifier: .gregorian)`, or parse with `Date.ISO8601FormatStyle` (as `DownloadNewsData.swift:27` already does). Add a test that runs under a `th_TH@calendar=buddhist` locale. |
| **A-2** | S2 | `Schedule/Views/GameDetailView.swift:335-344`; `Home Menus/HomeSections.swift:354-356`, `:410` | The sheet's status line reads `game.completed`, `gameHalftime`, `gamePeriod` and `gameClock` from the `Game` value captured at tap time (`selectedGame = game`). The scoreline above it does refresh every 10 s from the summary (`:80-84`, `:144`). | During a live game the score moves but the period and clock stay frozen. After the final whistle the sheet shows "Final 3 – 1" over "2nd Half · 67'" and never says "Final". | Parse the header status into `GameSheet` (`DownloadGameData.swift:544-569`: `status.type.detail`, `period`, `displayClock`; `phase` is already parsed and unused). Render the status from the sheet, and fall back to `game` only while loading. |
| **A-3** | S2 | `Home Menus/TeamModel.swift:161-166`, `:175-179`, `:299-320`; `Home Menus/TeamHomeView.swift:43-58` | `load()` refetches only the schedule. Roster, news, standings and leaders go through `…UnlessLoaded` guards. `TeamPages` keeps every model for the life of the process, and nothing in the app uses `.refreshable`. | Standings, news and leaders go stale after a match day and stay that way until the app is killed. That can be days, since iOS keeps the app suspended. The header's "3rd in …" (`HomeSections.swift:705`) goes stale with them. | Stamp a `loadedAt` on each feed and refetch on page mount once it passes a TTL: about 15 min for news and standings, and immediately after a followed game goes final. Pairs with C-1. |
| **A-4** | S2 | `Home Menus/FavoritesStore.swift:99-131`; `NavigationBar/TabBar.swift:120-124`, `:231-243` | `teamRefs()` drops any favorite whose catalog lookup misses a **2 s** deadline. `Home` runs it once per change to `store.teamIDs`, with no retry. `favoritesResolved` then drops a pending deep link to that team. | On a cold start with a slow or offline network and no catalog cache, a non-seed favorite is missing from the tab bar for the whole session. A widget, alert or Live Activity tap for that team does nothing. | Fall back to a placeholder `TeamRef` built from the parsed id (the monogram covers the crest), or re-run resolution when a late lookup lands, for example by observing `RemoteTeamCatalog` loads. |
| **A-5** | S2 | `NavigationBar/TabBar.swift:300`, `:417-419`, `:199-213`, `:120-124`, `:233-235`; `Home Menus/SettingsView.swift:96-103`, `:130-132` | The Settings sheet is owned by `TeamPage`, and a page is only mounted while its team is selected. Settings → Manage Teams opens the browser, where removing the team whose page you came from changes `store.teamIDs`. `favoritesResolved` then moves the selection, the page unmounts, and both sheets are torn down. | Removing the current team from Settings closes Settings and the browser mid-edit. The same happens when a deep link arrives while Settings is open. | Move `showsSettings` and its `.sheet` up to `Home`, next to `showsBrowser`, and pass a `showSettings` action down to `TeamPage`. |
| **A-6** | S2 | `Networking/TeamRef.swift:263`; `Classes/ConvertColor.swift:24-27`; used at `Roster/Views/PlayerDetailView.swift:433`, `:447`, `:591`; `Leaders/LeadersViews.swift:75`, `:81`, `:96`, `:131-133`; `Home Menus/TeamHomeView.swift:110` → `News/Views/NewsDetailView.swift:86`, `:92` | `TeamRef.color` is `Color(hexString: colorHex)`, which is `.clear` for an empty hex. Teams can have empty colours: remote search hits are built with `colorHex: ""` (`TeamBrowserView.swift:95`), as are many college catalog entries. A fallback already exists (`TeamColors.fillHex`, `TeamLogo.swift:157-160`), but these call sites skip it. | For a team with no colour: the player-sheet header is transparent with white text on the sheet, the leader-card figures are invisible, the gauges have no tint, and Safari's `preferredControlTintColor` becomes clear, so the article's Done and toolbar controls disappear. | One line in `TeamRef.swift`: `var color: Color { Color(hexString: TeamColors.fillHex(for: self)) }`. `TeamColors` already compiles into both targets (`WidgetScheduleLoader.swift:35`). Add a test that a team with `colorHex: ""` gets a non-clear colour. |
| **A-7** | S2 | `Networking/Sport.swift:429`, `:445` vs `:494`, `:510`, `:526`; `Schedule/Views/GameView.swift:602-618` | Bundesliga, Serie A and Ligue 1 include `uefa.europa` in `cupCompetitions`; the Premier League and LALIGA don't. No league includes the Conference League, and `cupDisplayName` doesn't know it. | Premier League and LALIGA clubs in the Europa League (and any club in the Conference League) have those fixtures missing from the schedule, the score alerts and the Live Activities (each loops over `[league] + cupCompetitions`: `ScoreAlertEngine.swift:120`, `LiveActivityManager.swift:163`). | Add `.soccer("uefa.europa")` to the Premier League and LALIGA, and `uefa.europa.conf` to all five after checking the slug against a live team schedule, as the comment at `:183-187` asks. Add "Conference League" to `cupDisplayName`, plus a `LeagueRegistryTests` case. |
| **A-8** | S3 | `Home Menus/FavoritesStore.swift:191-194`, `:257-259`; `Networking/TeamRef.swift:756-767`, `:772-777` | `move` changes the order but stamps nothing. `merge(local, remote)` always keeps the local order, and `sameEntries` ignores order, so a reordered list never counts as a change. | Reordering favorites on one device never reaches the others. Each device keeps its own order indefinitely, even though the docs call the store iCloud-synced. | Persist an `orderChangedAt` with the list, and adopt the remote order in `mergeFromCloud` when it's newer. Count an order difference as a change in the "write back" check. |
| **A-9** | S1 | `Schedule/Views/BoxScoreTables.swift:209`, `:214`, `:217`; `Schedule/Classes/SoccerLineups.swift:138`, `:151-153` | `ForEach(0 ..< player.goals)`, and the same for yellow and red cards. The counts come straight from the feed (`stat["value"].int ?? displayValue.intValue`) without clamping. | A negative value from a malformed or corrected feed traps (`Range` requires lower ≤ upper), crashing the game sheet. A huge value builds thousands of views. **Unlikely, but nothing guards it.** | Clamp at parse: `max(0, min(value, 9))` in `SoccerLineups.Player.init(entry:)`. |
| **A-10** | S1 | `Networking/JSON.swift:144-156`, `:164-167`; `Home Menus/Standings.swift:260` | `JSON.number` parses any string with `NSDecimalNumber` (for example `"1e30"`). `int` then calls `Int(number)` after checking only `isFinite`; `StandingsStats.int` does the same with `Int(value)`. | Any feed value of 2⁶³ or more that a parser reads with `.int` or `.intValue` traps. **Unlikely, but every parser goes through this one path.** | Use `Int(exactly: number.rounded(.towardZero))`, or clamp to `Double(Int.min)...Double(Int.max)` before converting, in both places. Add a `JSONTests` case. |
| **A-11** | S3 | `Home Menus/GameActivityAttributes.swift:78-81`; `Home Menus/ScoreDiff.swift:35`, `:92`; compare `Schedule/Classes/Linescore.swift:173-184` | The Live Activity's stage, and the alerts' "End of …" and summary text, use a raw `ordinal(period)`. The cards use the sport-aware `liveCardPeriodLabel`. | NHL overtime reads "4th · 3:12", NFL overtime "5th", soccer extra time "3rd · 95'". Alerts say "End of 4th" after a hockey overtime. Baseball shows "7th" without top or bottom. | Have `LiveActivityStateMapper` and `ScoreAlertEngine.snapshot(of:)` carry a preformatted `stageLabel` built with the league's rules (move `liveCardPeriodLabel` into shared code), and render that. |
| **A-12** | S3 | `Home Menus/ScoreDiff.swift:148-155`; `Home Menus/ScoreAlertEngine.swift:104-107` | The debounce rejects a second event inside 120 s, but the snapshot has already advanced, so that event is gone for good. | Two goals within two minutes produce one alert. The next alert can show a score the reader was never told about. | Coalesce instead of dropping: keep the latest suppressed event per game and post it when the window ends (re-check on the next update after `lastPosted + window`). |
| **A-13** | S3 | `Schedule/Classes/DownloadScheduleData.swift:115-117` vs `:139-144`; `myTeamWidget/WidgetScheduleLoader.swift:60-67`, `:109` | The comment says the formatters follow the reader's 12/24-hour choice, but `dateFormat = "h:mm a"` forces a 12-hour clock, and `"MMM dd, yyyy"` and `"E MMM d, y"` are fixed English orders. | European readers on a 24-hour clock see "7:30 PM" in the game sheet header (`GameDetailView.swift:178-179`), the widget and VoiceOver (`GameView.swift:650`), while the cards, which use `Date.FormatStyle`, show "19:30". | Use `setLocalizedDateFormatFromTemplate("jmm")` / `("yMMMd")`, or `Date.FormatStyle`, for display. Keep fixed formats for parsing only. |
| **A-14** | S3 · needs verification | `Schedule/Classes/DownloadScheduleData.swift:243-245`; `Schedule/Views/GameView.swift:454-462` | Postponed and cancelled games are detected by exact `detail` strings. The fixtures only cover `STATUS_CANCELED` and `STATUS_POSTPONED`; no suspended, abandoned or delayed status is captured. | A match that is `post` and `!completed` under any other status (an abandoned or suspended soccer match) falls through to `.live`, because its date is past, and shows "Live" indefinitely. | Read `status.type.name`, and treat `state == "post" && !completed` as called off. Capture a suspended or abandoned fixture to pin the behaviour. |
| **A-15** | S3 | `Home Menus/TeamModel.swift:412` | Name sort is `$0.lastName < $1.lastName`, a raw code-point comparison. | On European rosters, "Ødegaard", "de Jong" and "van Dijk" sort after "Z". | `localizedStandardCompare` (and `numberInt` as a tiebreak). |
| **A-16** | S3 | `Roster/Classes/DownloadAthleteData.swift:540-576` vs `:233-240` | Baseball season stats are read by array position (`stats[0]…stats[15]`). Football reads the same splits document by its `names` array, and the comment at `:372` records a previous positional-shift bug. | If ESPN reorders or inserts a column, every figure on the baseball sheet is silently off by one. | Zip with `json["names"]` and look stats up by name, as `parseFootballPlayerStats` does. |
| **A-17** | S3 | `NavigationBar/TabBar.swift:519`, `:530-536`; `Networking/LogoStore.swift:110-114` | `TabCrest.drawn` is keyed by `ObjectIdentifier(source).hashValue`, where the source is a `UIImage` that `NSCache` may evict and reallocate at the same address. The dictionary never shrinks. | After an eviction, a reused address can return the wrong crest variant, or a crest from before a rebrand. The dictionary also grows for the whole session. | Key by stored file path plus modification date, and hold the drawn images in an `NSCache`. |
| **A-18** | S3 · needs verification | `Home Menus/LiveActivityManager.swift:212-219`, `:250-254` | Each update starts its own unstructured `Task` that leaves the main actor and calls `activity.update`. Nothing orders them. | Two updates in quick succession can land out of order, leaving an older score on the Lock Screen until the next poll (up to 60 s). | Run updates through one serial queue per activity (an `AsyncStream` or an actor), or tag each with a sequence number and drop stale ones. |
| **A-19** | S3 | `Schedule/Views/GameDetailView.swift:180`, `:235-239`, `:137-140`; `DownloadScheduleData.swift:248-250`; compare `GameView.swift:579-582` | The header prints `game.channel`, which is the parser's "TBD" placeholder when there is none; the cards hide it. `venueLine` always joins `"\(location) | \(city), \(state)"`. | European fixtures often show "TBD" in the sheet. When the summary fails, `gameInfo` stays `.empty` and the venue line reads "Allianz Arena \| , ". | Use `GameCardContent.broadcast(of:)` and build the venue line from its non-empty parts only. |
| **A-20** | S3 | `myTeamsUITests/myTeamsUITests.swift:36`, `:102`, `:110`, `:233-234` | The schedule, search and two-team UI tests `XCTSkip` when the live network doesn't answer. | CI goes green without exercising the schedule cards or search, the screens most of this wave touched. | Add a launch-environment switch that serves `HTTPClient` from the `Fixtures/` JSON (the `RecordingTransport` pattern already exists in unit tests), and assert instead of skipping. |

---

## B. Alignment / visual consistency

| ID | Sev | Where | Evidence | Impact | Proposed fix |
|---|---|---|---|---|---|
| **B-1** | S2 | `Roster/Views/PlayerDetailView.swift:441-447`, `:471-478` | The player's name and number are always `Color.white` on `team.color`. The G-3 fix (`teamInk`) was applied to the game cards and the bar, but not here. | Unreadable on light team colours (yellows, whites), and invisible for the colourless teams in A-6. | `.teamInk(on: team)` for the name and number, and the `fillHex` colour for the header fill. |
| **B-2** | S2 | `Schedule/Views/GameDetailView.swift:221-231`, `:173`, `:245` | The scrim stacks an opaque `Color(hexString: gameColor)` on top of `Color.black`, so the black never shows. The white header text then sits on a 60–85 % wash of the host's colour. | With a light host colour, the competition, time and venue are white on yellow over a stadium photo, below 4.5:1. | Draw the team colour at about 50 % over a fixed black scrim (a blend, not a replacement), or choose the ink with `TeamColors.inkHex(on: gameColor)`. |
| **B-3** | S2 | `Leaders/LeadersViews.swift:131-133`; `Roster/Views/PlayerDetailView.swift:552-555` | The leader card's stat figure and the player sheet's section titles use `foregroundStyle(teamColor)` on neutral surfaces (`insetCard`, `systemBackground`). | Dark team colours (navy, maroon) disappear in Dark Mode, and light ones (gold) in Light Mode. Neither surface checks contrast. | `.primary` for figures and titles, with the team colour as an accent bar or underline only, or a tint checked for contrast against the surface. |
| **B-4** | S3 · needs verification | `NavigationBar/TabBar.swift:327-336`, `:440-445`; `Networking/TeamLogo.swift:178-184` | The bar crest is drawn straight onto the opaque team-colour backdrop. `logoVariant` only switches to the dark crest when the feed has one and the background's luminance is under 0.5. | A single-colour crest in the team's own colour, or a light crest on a light bar with no dark variant, blends into the bar. This is the "light-crest teams on the opaque bar" case in the brief. | When crest and bar contrast is low (the dominant crest colour against `heroHex`), draw the crest on a small ink-coloured disc, as `TabCrest` badges do. Check on device with teams that lack a dark crest. |
| **B-5** | S3 | `Resources/SplashView.swift:22-26`; `Info.plist:48-56`; `myTeamsLogo-light.png` 798×561 @3x | The system launch screen draws the logo at its natural 266 pt width. The SwiftUI splash redraws it at 55 % of the container width plus padding: 221 pt on a 402 pt phone, 242 pt on a 440 pt one. | The logo visibly shrinks (about 17 %) at the hand-off, so the "seamless" splash fade isn't seamless. | `.frame(width: 266)`, the asset's point size (or read it from `UIImage(named:)`), instead of `containerRelativeFrame`, and drop the `.padding()`. |
| **B-6** | S3 | `Resources/MyTeamsApp.swift:35-39`; `Assets.xcassets/LaunchscreenColor.colorset` (white, and black for dark) | The launch screen follows the system appearance. The splash overlay sits below `.preferredColorScheme(appearance.colorScheme)`, so it follows the in-app choice. | A reader who picked Light while the system is Dark (or the reverse) sees a black launch screen, a white splash, then the app. The same flash on every launch. | Apply `.splashOverlay()` outside `preferredColorScheme`, so it keeps the system scheme, and let the fade carry the change. |
| **B-7** | S3 | `Schedule/Views/GameDetailView.swift:186`, `:246`, `:255`, `:260`, `:357`; `Roster/Views/PlayerDetailView.swift:549`, `:555`, `:573`, `:579` | Both sheets' cards use `Color(uiColor: .systemBackground)` and ad-hoc spacing (15, 10, 30, 5). Page cards use `Theme.Surface.contentCard` and `Theme.Spacing` (`Theme.swift:47-53`, `:84-91`, `:254-256`). | The sheet cards don't match the page cards in either appearance: opaque white or black against the grouped tones, on a different spacing rhythm. | `.contentCard()` and `Theme.Spacing.{s,m,l}` throughout both sheets. |
| **B-8** | S3 | `Home Menus/HomeSections.swift:717-727`; `Home Menus/Record.swift:74-75`, `:101` vs `:78-80`; `HomeSections.swift:527-533` | The soccer group name is the season title: `"2026-27 German Bundesliga"` (verified in `Fixtures/bundes_standings.json`). The schedule record is W-L-D (`.winLossTie`) while the table next to it is W-D-L. | The header reads "4-1-0 · 3rd in 2026-27 German Bundesliga": the record order is backwards for European readers and the label carries a season prefix. | For `.pointsTable`, use `league.descriptor.displayName` (or strip a leading season) in `standing(of:in:)`. Show the soccer schedule record as W-D-L. |
| **B-9** | S3 | `Home Menus/SettingsView.swift:81-94`, `:120-127`, `:130-132`; `Home Menus/TeamBrowserView.swift:220-229`, `:313-322`; `Leaders/LeadersViews.swift:196-206`; `Schedule/Views/GameDetailView.swift:115-121` | There are three ways to dismiss a sheet: ✓ confirm (Settings, Browser), ✕ in the toolbar (Leaders) and a floating glass ✕ (game and player sheets). Settings applies changes immediately but shows ✓. "Alerts" is both a section header and its only row. Alerts can be reached from both Settings and the Browser, and Manage Teams stacks a sheet on a sheet. | The Settings form feels unlike the sheets around it, and its navigation is duplicated. | Settings: `Button(role: .close)`; drop the single-row section headers (or use footers); remove the Alerts row from the Browser now that Settings owns it. |
| **B-10** | S3 | `Schedule/Views/GameDetailView.swift:316`, `:318-323`; compare `GameView.swift:180` | The opponent's crest uses `.aspectRatio(contentMode: .fill)` in a fixed frame with no clipping. The followed side uses `TeamLogo`, which fits. | Wide crests spill over the scoreline, and the two sides of the scoreboard look different sizes. | `.fit` for the opponent's crest, as the schedule card does. |
| **B-11** | S3 | `Home Menus/HomeSections.swift:639`, `:641`, `:660-661`, `:552`, `:565`, `:583`; `Leaders/LeadersViews.swift:128-150` | News rows get `spacing: 10` plus `.padding(.top)` each (26 pt between rows, against 12 pt in the carousels). The News header pads leading and top but not trailing. Standings use 10, 4 and 6. The leader card has no horizontal padding. | Schedule, standings, leaders and news cards don't share a vertical rhythm, and leader names run to the card's edge. | `Theme.Spacing` tokens throughout. Drop the per-row top padding in News, and add `.padding(.horizontal, Theme.Spacing.s)` to `TeamLeaderCard`. |
| **B-12** | S3 | `NavigationBar/TabBar.swift:103-106`, `:472`; `News/Views/NewsDetailView.swift:39-42`; `Home Menus/SettingsView.swift:137-142`; `Resources/SplashView.swift:25` | The brand logo appears at 160 pt (empty state), 120 pt (article error), 160×64 (Settings), 20 pt high (bar) and 55 % width (splash). | The logo has no consistent scale across the new branded surfaces. | One small `BrandLogo` size set (bar, inline, hero) beside `SplashView`, used at all five sites. |
| **B-13** | S3 | `myTeamWidget/GameLiveActivity.swift:84`, `:219-244`; `Home Menus/GameActivityAttributes.swift:23-48` | The compact Dynamic Island mark and the keyline tint look the team up in the bundled `TeamCatalog`, which holds only the four seed teams. | Every other team, including every European club, gets a generic sport glyph and the system keyline, so DI-1 and DI-2 are done for four teams only. | Add `favoriteAbbreviation` and `favoriteColorHex` to `GameActivityInfo`. These are static attributes, a few bytes, well inside the budget. Fill them in `LiveActivityStateMapper.info`. |
| **B-14** | S3 | `myTeams.xcodeproj/project.pbxproj:1071`; `Info.plist:65-71`; `NavigationBar/TabBar.swift:154-157` | iPad is a supported device family and allows landscape. On regular width `editIndex` has no capacity limit, and there's no `.tabViewStyle(.sidebarAdaptable)`. | With many favorites, iPad shows an over-long top tab bar and the stretched phone page (X-10 is still open). | `.tabViewStyle(.sidebarAdaptable)` on regular width, with the Teams entry as a sidebar footer, or drop iPad from the device family. |
| **B-15** | S3 | `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json:2-20` | The icon has light and dark 1024 px variants only, with no tinted variant and no Icon Composer `.icon`. | The tinted and clear Home Screen appearances fall back to the system's treatment of a flat icon (X-2 is only partly done). | Add a tinted variant, or ship the Icon Composer `.icon` once the design has one. |
| **B-16** | S3 | `myTeamWidget/myTeamWidget.swift:57-58`, `:79-83`; `myTeamWidget/WidgetScheduleLoader.swift:38-51`, `:110` | A failed load or the end of the season fills the tile with "N/A" three times. The channel line shows the parser's "TBD". | A placed widget can sit as "N/A / N/A / N/A" for the whole off-season. | A single line, "No upcoming games" or "Couldn't update", with the crest. Hide "TBD", as the cards do. |
| **B-17** | S3 | `Roster/Views/PlayerView.swift:42-51` | The name caption is `.caption2` regular, the number caption bold, the position `.caption2` bold. None has a line limit. | Cards in one carousel change weight with the sort, and long names wrap to different heights. | One caption style for all three sorts, with `lineLimit(2)` and centred alignment. |

---

## C. Features worth adding next

Two candidates from the brief **already ship**:
- **Favorites reordering:** the Browser's EditButton with `onMove` (`TeamBrowserView.swift:241`, `:308-312`). Its cross-device sync bug is A-8.
- **Game-card tap-through to the box score:** `HomeSections.swift:354-357` → `GameDetailView`. C-6 extends it.

Ranked by value for the effort:

| Rank | ID | Feature | Grounding | Value · effort | Sketch |
|---:|---|---|---|---|---|
| 1 | **C-1** | Pull-to-refresh on the team page, plus TTL refresh (refresh parity across standings, news and leaders) | No `.refreshable` anywhere (grep); A-3 | High · S | `TeamModel.refreshAll()` (forces every feed), then `.refreshable` on the page `ScrollView` (`TabBar.swift:356`), routed through an environment action set by `TeamHomeContent`. |
| 2 | **C-2** | Qualification and relegation zones in soccer standings | `note` and `noteColorHex` are parsed (`Standings.swift:50-54`, `:214-215`) but never read (grep) | High for the five European leagues · S | A 3 pt leading bar in `noteColorHex` on each row of `StandingsTable` (`HomeSections.swift:578-609`), with a legend of distinct notes under the table. |
| 3 | **C-3** | Alerts quiet hours and per-event choice (finals only, scores, starts) | Alerts post unconditionally once allowed (`ScoreAlertEngine.swift:165-177`) | High · M | Store the window and event mask with the alerts settings (`AlertsSettings.swift`), filter in `post(_:)`, and add a section to `AlertsSettingsView`. Quiet hours could also use `.passive` interruption level instead of muting. |
| 4 | **C-4** | Haptics | One `sensoryFeedback` in the app (`TeamBrowserView.swift:557`) | Medium · S | `.sensoryFeedback(.selection, trigger: selection)` on the `TabView` (`TabBar.swift:158`), `.success` when a retry succeeds and when an alert toggle changes, and `.impact` when a live score changes on a card. |
| 5 | **C-5** | Widget shows the live score or last result, and the medium tile links to the game | The widget only ever picks the next unplayed fixture (`WidgetScheduleLoader.swift:98-101`); one `widgetURL` for the whole tile (`myTeamWidget.swift:138`) | High · M | Phase 1 (widget only): show the in-progress game (from a small scoreboard snapshot the app writes to the App Group defaults) or else the last result. Phase 2: a `myteams://game/<league>:<id>` route, so `Link`s in the medium tile open the game sheet. |
| 6 | **C-6** | Tap a lineup or box-score player to open their sheet | Lineup and skater rows aren't interactive (`BoxScoreTables.swift:100-113`, `:192-235`); `PlayerDetailView` is generic (`PlayerDetailView.swift:416`) | Medium · M | Add athlete ids to the rows (already parsed: `SoccerLineups.Player.athleteID`), and present `PlayerDetailView` from the game sheet with a lightweight player value. |
| 7 | **C-7** | Recent searches in the team picker | The query is cleared on every navigation (`TeamBrowserView.swift:279-281`); nothing is persisted | Medium · S | Keep the last 8 followed-from-search queries and teams in `UserDefaults`, shown as a "Recent" section when the field is focused and empty. |
| 8 | **C-8** | Don't banner-alert for the team page on screen | `willPresent` always returns `[.banner, .list, .sound]` (`ScoreAlertEngine.swift:261-266`) | Medium · S | Pass the selected team id into the presenter, and return `[.list]` for that team's alerts while its page is foremost. |
| 9 | **C-9** | Add an upcoming game to the calendar | Upcoming cards carry the start, venue and channel (`GameView.swift:414-416`, `:440-445`) | Low-medium · M | A context menu on upcoming cards with `EKEventEditViewController`. Needs the calendar-write usage string in `Info.plist`. |

---

## Prioritized punch-list (top 10)

| # | Item(s) | Why first |
|---:|---|---|
| 1 | **A-9, A-10:** clamp lineup counts; range-safe `Int` conversion in JSON and standings | The only crash paths found. One or two lines each. |
| 2 | **A-1:** POSIX locale and Gregorian calendar on `eventDateParser` | A two-line fix for whole schedules going wrong on affected locales, which also drives polling and the widget. |
| 3 | **A-2:** game sheet status from the refreshed summary | A live screen showing contradictory information. |
| 4 | **A-6:** `TeamRef.color` falls back to `fillHex` | One line. Fixes invisible headers, figures and Safari controls for teams without a colour. |
| 5 | **A-5:** move the Settings sheet up to `Home` | Settings closing itself mid-edit is the most visible regression from the Settings wave. |
| 6 | **A-3 + C-1:** feed TTLs and pull-to-refresh | Stale standings and news are the most likely user complaint after a match day. |
| 7 | **A-4:** keep unresolved favorites on the tab bar | Cold-start offline users lose teams and deep links. |
| 8 | **A-7:** Europa League and Conference League for every European league | A coverage gap in the newest feature. Catalog data only. |
| 9 | **B-1, B-2, B-3:** team-colour contrast on the sheets and leader cards | Legibility on light and dark team colours. Uses the existing `teamInk` helpers. |
| 10 | **B-8:** soccer header copy (W-D-L, no season prefix) | The first line European readers see on every team page. |

---

## Suggested implementation cards (file ownership)

Each card **owns** the files listed. No two cards that may run in parallel share a file. Where a later card needs an earlier one's API, the dependency is stated, so run those in sequence. Tests go in the suites named; each suite is owned by one card. Cards are in priority order.

| # | Card | Findings | Owns (exclusive) | Depends on |
|---:|---|---|---|---|
| 1 | **Parsing hardening** | A-1, A-9, A-10, A-13 (app formatters), A-14, A-16 | `Schedule/Classes/DownloadScheduleData.swift`, `Networking/JSON.swift`, `Home Menus/Standings.swift`, `Schedule/Classes/SoccerLineups.swift`, `Roster/Classes/DownloadAthleteData.swift`; tests `ScheduleParsingTests.swift`, `JSONTests.swift`, `SportBoxScoreTests.swift`, `PlayerSeasonStatsTests.swift` | – |
| 2 | **Game sheet: live status and header** | A-2, A-19, B-2, B-7 (game sheet), B-10 | `Schedule/Views/GameDetailView.swift`, `Schedule/Classes/DownloadGameData.swift`; test `BoxScoreParsingTests.swift` | – |
| 3 | **Favorites and the team model's colour** | A-6, A-4, A-8, B-9 (Browser's Alerts row), C-7 | `Networking/TeamRef.swift`, `Home Menus/FavoritesStore.swift`, `Home Menus/TeamBrowserView.swift`; tests `FavoritesStoreTests.swift`, `TeamSearchTests.swift`, `TeamCatalogTests.swift` | – |
| 4 | **Team-model refresh** | A-3, A-15, C-1 (model half: `refreshAll()`, TTLs) | `Home Menus/TeamModel.swift`, `Home Menus/TeamHomeView.swift`; test `TeamPagesTests.swift` | – |
| 5 | **Home shell, Settings and splash** | A-5, A-17, B-4, B-5, B-6, B-9 (Settings), B-12, B-14, C-1 (wire `.refreshable`), C-4 (tab haptic) | `NavigationBar/TabBar.swift`, `Home Menus/SettingsView.swift`, `Resources/MyTeamsApp.swift`, `Resources/SplashView.swift`, `News/Views/NewsDetailView.swift`; tests `TabBarTests.swift`, `SettingsTests.swift`, `SplashTests.swift`, `WidgetDeepLinkRoutingTests.swift` | Card 4 for C-1 wiring only. Everything else can start in parallel. |
| 6 | **Player and leader contrast** | B-1, B-3, B-7 (player sheet), B-17 | `Roster/Views/PlayerDetailView.swift`, `Leaders/LeadersViews.swift`, `Roster/Views/PlayerView.swift`; test `ThemeTests.swift` (ink cases) | – (card 3 fixes clear colours centrally; this card can use `fillHex` locally meanwhile) |
| 7 | **European competitions** | A-7 | `Networking/Sport.swift`, `Schedule/Views/GameView.swift`; tests `LeagueRegistryTests.swift`, `GameCardContentTests.swift`, `CrossLeagueAcceptanceTests.swift` | – |
| 8 | **Team page sections** | B-8, B-11, C-2 | `Home Menus/HomeSections.swift`, `Home Menus/Record.swift`; tests `StandingsTests.swift`, `RecordTests.swift` | – |
| 9 | **Alerts and Live Activities** | A-11, A-12, A-18, B-13, C-3, C-8 | `Home Menus/ScoreDiff.swift`, `Home Menus/ScoreAlertEngine.swift`, `Home Menus/GameActivityAttributes.swift`, `Home Menus/LiveActivityStateMapper.swift`, `Home Menus/LiveActivityManager.swift`, `Home Menus/AlertsSettings.swift`, `Home Menus/AlertsSettingsView.swift`, `myTeamWidget/GameLiveActivity.swift`; tests `ScoreDiffTests.swift`, `ScoreAlertEngineTests.swift`, `LiveActivityMapperTests.swift`, `AlertsSettingsTests.swift` | – |
| 10 | **Widget polish** | A-13 (widget formatter), B-16, C-5 phase 1 | `myTeamWidget/myTeamWidget.swift`, `myTeamWidget/WidgetScheduleLoader.swift`, `myTeamWidget/TeamEntity.swift`; test `WidgetDeepLinkTests.swift` | C-5 phase 2 (the game deep link) touches `TeamRef.swift` and `MyTeamsApp.swift`, so it is a follow-up after cards 3 and 5. |
| 11 | **UI-test network fixtures** | A-20 | `myTeamsUITests/**`, `Networking/HTTPClient.swift`; tests `HTTPClientTests.swift`, `RecordingTransport.swift`, `FixtureLoader.swift` | – |
| 12 | **Lineup and box-score tap-through** | C-6 | `Schedule/Views/BoxScoreTables.swift`, plus `GameDetailView.swift` and `SoccerLineups.swift` **once cards 1 and 2 have merged** | Cards 1 and 2 |
| 13 | **App icon tinted appearance** | B-15 | `Resources/Assets.xcassets/AppIcon.appiconset/**` | Design asset |

Unowned and untouched by any card: `Classes/Theme.swift`, `Classes/LoadingView.swift`, `Classes/ConvertColor.swift`, `Classes/RepeatingTask.swift`, `Networking/LogoStore.swift`, `Networking/RemoteImage.swift`, `Networking/RemoteTeamCatalog.swift`, `Networking/TeamLogo.swift`, `Leaders/StatLeaders.swift`, `Home Menus/LeagueScoreboardCenter.swift`, `Home Menus/ScoreAlertsPermissions.swift`, `Schedule/Classes/HockeyBoxScore.swift`, `Schedule/Classes/Linescore.swift`, `Schedule/Views/StatRowView.swift`, `Schedule/Views/GetNextGame.swift`, `News/**` (except `NewsDetailView.swift`, card 5), `Roster/Classes/DownloadRosterData.swift`, `Roster/Views/{BioViews,StatView,StatPercentageView}.swift`, `Resources/AppDelegate.swift`. A card that finds it must edit one of these should claim it on the board first. The likely case is A-11 moving `liveCardPeriodLabel` out of `Linescore.swift` into card 9's files: copy it rather than move it, so the two cards don't collide.

---

## Follow-up: the UI-test launch stall (t_2cab5bf3, 2026-10-05)

*After A-20 (`e3ec7ad`), `testCrestBarSwitchesTeams` failed on main, and later greens only just passed: `testBrowserSearchFindsTeams` took 180 s at `f0cec8f`, 55 s of it before the app idled.*

**Root cause: the simulator, not the app.** XCUITest's launch steps ("Launch", "Setting up automation session") were waiting on a simulator still busy with the work iOS does after a fresh boot. `xcodebuild test` booted it only minutes before the UI tests ran. Diagnostic gate runs logged the app's own launch callbacks and a main-thread heartbeat to settle it:

- Run 37347991951: XCUITest logged "Launch" at 17:30:27, but `willFinishLaunching` ran at 17:32:23. For 110 s the app process did not exist yet.
- Run 37347962897: the main thread was blocked for 36.6 s while serving an accessibility snapshot. A background thread that should log every 5 s logged every 12 to 16 s, so the whole process was CPU-starved, not deadlocked.
- A host-side CPU monitor (run 37353417043) showed several iOS-runtime daemons, a few seconds to a minute old, each using 50 to 90 % CPU.

Fixtures only moved the stall around. It hit the first UI test before A-20 too (56 s at `b23f25d`), and live-network launches as well as fixture ones.

Two leads in the brief did not hold:

- The `[network] … HTTP 429/503` lines come from the unit-test host running the stubbed `HTTPClientTests`. They are not a fixture launch reaching ESPN.
- No app loop keeps the app busy. Every poller sleeps between requests.

**The failing assertion was a second problem.** On some launches every tab-bar button keeps its accessibility label but loses its identifier (the hierarchy is in run 37345407532). So `teamPicker.edit` never matches, even though the Teams tab is on screen. The bar was not minimized; the identifier simply wasn't there.

**Fixes:**

- `.github/workflows/ios-gate.yml` boots the test simulator right after checkout. Its post-boot work then finishes during the build, and the Test step targets that device by UDID.
- `myTeamsUITests.swift`: `teamsTab(_:)`, `teamTabs(_:)` and `pinnedTab(_:in:)` still prefer the identifiers. When the bar has dropped them, they fall back to the app's own tab labels inside the tab bar ("Add or Edit Teams", the team names) and print the bar.
- Fixture launches are hermetic (`HTTPClient.servesFixtures`, Debug only). They no longer fetch crests or headshots from the CDN, and they cache the team catalog under `TeamCatalog-Fixtures`. Before this, the trimmed fixture catalogs were written into the live launches' week-long catalog cache, and the live catalogs into theirs. Release builds are unchanged.

**Result:** gate runs 37351771337 (attempts 1 and 2) and 37353952069 were green. Every UI test's first idle came within 14 s of launch, and the fixture tests' within 10.2 s:

| Fixture test | First idle (three runs) |
|---|---|
| `testBrowserSearchFindsTeams` | 4.8 s, 5.0 s, 3.3 s |
| `testCrestBarSwitchesTeams` | 10.2 s, 6.0 s, 4.3 s |
| `testScheduleCardsReadWithoutPlaceholders` | 3.1 s, 4.5 s, 2.5 s |

The same day without the early boot, launches stalled 15 to 116 s.
