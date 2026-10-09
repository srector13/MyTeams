# myTeams feature recommendations: full-pass audit

*Task t_fd978c1b, 2026-10-08. Audited at `e983fe7` (main) on branch `wt/t_fd978c1b`. This is a docs-only change; no app code, test or CI file was modified.*

**Swept:** every Swift file in `Hawk Nation/**`, `myTeamWidget/**`, `myTeamsTests/**` (732 tests in 42 files) and `myTeamsUITests/**`; `scripts/*.py`; `.github/workflows/*.yml`; `Hawk Nation/Info.plist`, both entitlements files, both privacy manifests and the relevant `project.pbxproj` settings; `README.md` and `site/`. I also checked which fields the captured ESPN summary fixtures in `myTeamsTests/Fixtures/` carry, so that every "the data is already there" claim below rests on a real capture.

**Prior audits read first** (recommendations build on these; overlaps are flagged per item):

| Doc | What it covers | State on main |
|---|---|---|
| `docs/ANALYSIS-any-team-roadmap.md` | The 4-team to any-team architecture plan; ESPN API strategy (§5); phased roadmap (§6), including "Phase 4: push score alerts" | Phases 1–3 shipped (`TeamRef`, `LeagueDescriptor`, `RemoteTeamCatalog`, 19 leagues). Phase 4 push has a seam only: `AppDelegate.swift:18-23` |
| `docs/UI_AUDIT_IOS27_GLASSUI.md` | 69 Liquid Glass / typography / accessibility findings | Mostly shipped (see `APP_REVIEW_PASS3.md:30-50`) |
| `docs/APP_REVIEW_PASS3.md` | 20 bugs (A-), 17 alignment (B-), 9 features (C-) | A-1…A-20, B-*, C-1…C-8 shipped per `git log` (`8c81d4f`, `c5838ee`, `0dd74af`, `d7dae80`, `24e4b51`, `2874a8e`, …). **C-9 (calendar) did not ship**: no `EventKit` anywhere in the tree. **C-5 phase 2 (game deep link) did not ship**: `myteams://game/…` still parses to nil (`myTeamsTests/WidgetDeepLinkTests.swift:54`) |
| `docs/HEADSHOT_SOURCE_APIFOOTBALL.md` | API-Football / API-Sports vendor recon and budget math | Led to the BYO-key tier 3 (`ca8e834`) |
| `docs/APIFOOTBALL_LIVE_DIAGNOSTIC.md` | Free-plan page cap root cause; per-club sweep fix | Shipped (`e72f55e`). Records one known gap ("Wolves", `:70-72`) that R-11 picks up |
| `docs/CIOSIGNING.md` | Ad-hoc, development and unsigned (Feather) `.ipa` builds | Distribution is sideload-only. No TestFlight or App Store path (`CIOSIGNING.md:8`). This limits R-1 and R-8 |

---

## Ranked summary

Ranked by impact ÷ effort. **Impact** is how many readers notice it and how often. **Effort:** S ≤ 2 dev-days, M 3–8, L more than 8. "Non-code" means a deliverable that has to come from outside the codebase.

| Rank | ID | Recommendation | Impact | Effort | Risk | Non-code dependency | Overlap |
|---:|---|---|---|---|---|---|---|
| 1 | **R-1** | Background refresh: alerts, widget and Live Activity updates without the app open (interim, no server) | High | M | Low–Med (opportunistic scheduling) | None | Interim step before roadmap §6 Phase 4 |
| 2 | **R-2** | Game sheet "story": scoring timeline, key events, win probability, injuries | High | M | Med (ESPN schema drift) | None | New; extends pass-3 C-6 |
| 3 | **R-3** | Game-level deep links plus Share | High | M | Low | None | **Completes pass-3 C-5 phase 2** |
| 4 | **R-4** | Offline-first: last-known schedules, standings and news kept on disk | Med–High | M | Low | None | Narrows roadmap §3.5 (SwiftData "only if offline") |
| 5 | **R-5** | Standings depth: form, streak, conference record, college conferences, rankings | Med | M | Low–Med | None | Picks up the `TeamBrowserView.swift:400` TODO |
| 6 | **R-6** | Smarter alerts: close-game and OT alerts, per-team event choice, Time Sensitive | Med–High | S–M | Med (entitlement and App Review copy) | Time Sensitive entitlement | Extends pass-3 C-3 (shipped) |
| 7 | **R-7** | Add games to the calendar (one game or a whole season) | Med | S–M | Low | None | **Carries pass-3 C-9 forward unchanged in intent** |
| 8 | **R-8** | Server push for alerts and Live Activities (roadmap P4-e) | Very high | L | High (ESPN ToS from one IP, hosting, APNs) | Backend host, APNs key, `aps-environment` entitlement | **Is roadmap §6 Phase 4.** Restated with today's seams |
| 9 | **R-9** | Widget family expansion: Large "My Day", inline accessory, Control Center control | Med | M | Low | None (R-1 makes it fresh) | Builds on pass-3 C-5 (shipped) |
| 10 | **R-10** | Player depth: game logs, previous seasons, AVG/OBP/SLG | Med | M | Med (per-sport shapes) | None | Extends roadmap §5.3 "Deep stats" |
| 11 | **R-11** | Headshot coverage v2: tier independence, negative-cache TTL, club aliases, coverage readout | Med (soccer) | S–M | Low–Med (third-party key) | Reader's own API-Football key (as today) | **Picks up `APIFOOTBALL_LIVE_DIAGNOSTIC.md:70-72` known gap** |
| 12 | **R-12** | App Intents, Siri and Spotlight: "When do the Chiefs play next?" | Med | M | Low | None | New; the widget's `TeamEntity` is the seed |

Then **27 cheap wins** (S or less), listed at the end.

**Suggested order:** R-1, R-3, R-7, R-6 and the cheap wins first. They are client-only and low risk. R-2, R-4 and R-5 next. R-8 only after a decision on a backend and a licensed data feed (roadmap §5.4). R-8 also makes the most sense once the app has a TestFlight or App Store path, which it doesn't have today (`CIOSIGNING.md:8`).

---

## R-1 · Background refresh: alerts, widget and Live Activity updates without the app open

**User problem.** Score alerts, the widget's live score and Live Activity updates all stop the moment the app leaves the foreground:
- `LeagueScoreboardCenter.sceneDidChange` stops following favorites on `.background` ("nothing polls in the background", `Hawk Nation/Resources/MyTeamsApp.swift:86-98`).
- The alert engine says as much: "With the app suspended or closed, no alert fires" (`Home Menus/ScoreAlertEngine.swift:32-35`).
- `Info.plist` has no `UIBackgroundModes` key, and nothing in the tree uses `BGTaskScheduler`.
- The widget promises "the live score" (`myTeamWidget/myTeamWidget.swift:506`), but its scores come only from the app's snapshot, which goes stale after 30 minutes (`Home Menus/WidgetScoreboardSnapshot.swift:86`).
- The site sells "Live scores and alerts" without that caveat (`site/index.html:122-127`).

For most readers, a sports app's alerts arrive with the phone locked. Today they never do.

**Why now.** The pieces a background pass needs already exist and are already separated from the UI:
- `LeagueScoreboardCenter` can follow favorites with no view mounted (`startFollowingFavorites`, `LeagueScoreboardCenter.swift:317-332`).
- `ScoreAlertEngine` turns board changes into events.
- `WidgetScoreboardWriter` writes the App Group snapshot and reloads widgets only on change (`WidgetScoreboardWriter.swift:57-87`).
- `LiveActivityManager` queues ordered updates (`LiveActivityManager.swift:254-302`).

This gets most of the value of R-8 for a fraction of the cost. It isn't minute-accurate, but finals and most score changes would arrive within 15–30 minutes, and the widget would stop going stale.

**Sketch.**
1. `Info.plist`: add `UIBackgroundModes = [fetch]` and `BGTaskSchedulerPermittedIdentifiers = [<bundle>.scoreboard-refresh]`.
2. `AppDelegate.swift` (or `MyTeamsApp` with `.backgroundTask(.appRefresh(...))`): register a `BGAppRefreshTask`.
   - Each run: one `LeagueScoreboardCenter.refresh` pass over favorites' leagues for today. Let `ScoreAlertEngine` and `WidgetScoreboardWriter` react, push Live Activity updates, then reschedule.
   - Schedule the next run for about 15 minutes ahead while any favorite has a live game, otherwise at the next kickoff (`TeamModel.shouldPollLiveScore` already knows the window, `TeamModel.swift:657-662`).
3. **Required change:** persist the alert snapshots. Today the first sighting of a game only seeds state, and snapshots live in memory only (`ScoreDiff.swift:189-193`, `ScoreAlertEngine.swift:61-66`). A cold background launch would otherwise seed everything and alert on nothing.
   - Store `[gameID: ScoreSnapshot]` plus the debounce times in the App Group defaults with a 24 h expiry, the same pattern `LiveActivityStateMapper` uses for retired games (`LiveActivityStateMapper.swift:260-262`).
4. Tests: an engine test that restores persisted snapshots and alerts on the first background diff, in `ScoreAlertEngineTests.swift`.

**Effort:** M (4–6 days). **Dependencies:** none. **Risk:**
- iOS decides when refresh runs, based on usage, and it may run rarely for lightly used installs. Set expectations in the alerts footer (`AlertsSettingsView`).
- It barely changes ESPN load: one scoreboard call per league per wake.
- No App Review concern for `fetch`.

**Non-code:** none.

**Overlap with prior audits.** Roadmap §6 Phase 4 says "iOS background refresh is opportunistic and can't deliver score changes within a minute" (`ANALYSIS-any-team-roadmap.md:537`). That is true, and this recommendation doesn't contradict it. R-1 is a deliberate interim step, not a replacement for R-8. It reuses the same event model, as `ScoreAlertEngine.swift:35-37` already plans.

---

## R-2 · Game sheet "story": scoring timeline, key events, win probability, injuries

**User problem.** After a game, the sheet shows a linescore, a few team stat rows and, for hockey and soccer only, player tables (`Schedule/Views/GameDetailView.swift:90-96`, `BoxScoreTables.swift:54-259`). For football, basketball and baseball, the sheet can't answer "how did we score?". Football gets 8 team stats (`DownloadGameData.swift:545-554`) and baseball gets R/H/E only (`:573-577`).

**Why now.** The summary the sheet already polls every 10 s carries the data. The captured fixtures prove it:

| Field | Present in fixtures | Read today? |
|---|---|---|
| `keyEvents` (goals, cards, subs, with minute) | every soccer summary: `epl_`, `laliga_`, `bundes_`, `seriea_`, `ligue1_`, `ligamx_`, `nwsl_`, `wsl_`, `premiere_`, `uclleague_`, `sporting_summary_final_*.json` | No. Soccer reads `plays` only for substitution minutes (`SoccerLineups.swift:142`) |
| `scoringPlays` | `chiefs_summary_final/live_*`, `ncaaf_summary_final_*` | No |
| `winprobability` | NFL, NBA, WNBA, MLB, NCAAF, NCAAM and NCAAW summaries | No. The basketball `predictor.gameProjection` is parsed (`DownloadGameData.swift:367-369`) but `BoxScore(basketball:)` never uses it (`:516-530`) |
| `injuries` | NFL, NBA, WNBA, NHL and MLB summaries | No |
| `gameInfo.attendance`, venue `capacity` | all | Parsed (`DownloadGameData.swift:311-312`), never shown |

Most of this feature is rendering. The fetch and refresh loop are done, and the backoff is already in place (`GameSheetLoad`, `DownloadGameData.swift:637`; `GameDetailView.swift:140-177`).

**Sketch.**
- `Schedule/Classes/`: add a `GameTimeline.swift` parser that maps `scoringPlays` (US sports) and `keyEvents` (soccer) to `[TimelineEvent(clock, period, teamID, kind, text, athleteIDs)]`. Use name-keyed lookups (roadmap §5.3 warns against positional parsing).
- Also parse `winprobability` into `[(playIndex, homePct)]`, and pregame `injuries` into per-team lists.
- `GameDetailView.swift`: add a "Timeline" section between the scoreboard and the box score. Add a small win-probability sparkline with Swift Charts (`Chart { LineMark }`, iOS 16+, already available on the 26.0 target) and an "Injuries" disclosure for pregame sheets.
- Timeline rows with `athleteIDs` reuse the C-6 tap-through (`BoxScoreTables.swift:383-396`).
- Show attendance in the header venue line.
- Tests: golden tests against the fixtures listed above, in `BoxScoreParsingTests.swift` / `SportBoxScoreTests.swift`.

**Effort:** M (5–7 days across sports; soccer `keyEvents` alone is S). **Dependencies:** none. **Risk:**
- ESPN `summary` shapes differ by sport and drift over time. The fixtures and golden tests mitigate this.
- **Leave `pickcenter` (odds) out.** It is present in every summary fixture, but betting lines draw App Review scrutiny (guideline 5.3) and conflict with the "private by design" positioning.

**Non-code:** none. A designer pass on the timeline row would help but isn't required. The `Theme` tokens cover it.

**Overlap with prior audits.** None of these fields appear in earlier audits. Pass-3 C-6 (shipped) made player rows tappable, and this reuses it. The roadmap's §5.3 "no play-by-play-derived rates" refers to advanced metrics, not the raw timeline used here, so there is no contradiction.

---

## R-3 · Game-level deep links plus Share

**User problem.** Every external entry point lands on a team page, never on the game:
- Tapping a score alert, a Live Activity or the widget opens `myteams://team/<id>` (`ScoreAlertEngine.swift:301-303`, `myTeamWidget/GameLiveActivity.swift:27`, `:86`, `myTeamWidget.swift:164`). The reader then has to find the game card themselves.
- The app has no share action at all: no `ShareLink` anywhere in `Hawk Nation/`. News sharing only works through Safari's own button (`News/Views/NewsDetailView.swift:81-88`).

**Why now.**
- The routing exists. `WidgetDeepLink` builds and parses `myteams://team/…` (`Networking/TeamRef.swift:312-335`), `.onOpenURL` handles it (`MyTeamsApp.swift:41`), and a test pins `myteams://game/…` returning nil (`myTeamsTests/WidgetDeepLinkTests.swift:54`), so the gap is known and fenced.
- Every caller already has the game id: alerts have `gameID` in `ScoreEvent` (`ScoreDiff.swift:141-146`), and `GameActivityInfo` has it too.
- Game cards are already `Button`s with zoom transitions (pass-3, GlassUI X-13), so a rendered card image is easy to produce.

**Sketch.**
1. `TeamRef.swift`: add `WidgetDeepLink.url(forGame: league, eventID, teamID)`, giving `myteams://game/<league path>:<eventID>?team=<teamID>`, and extend the parser.
2. `NavigationBar/TabBar.swift` (the deep-link owner): select the team tab, then present `GameDetailView` for the event. The sheet can load from the event id alone through `GameSheetLoad`.
3. Callers: the `ScoreAlertEngine` content `userInfo`, `GameLiveActivity` `widgetURL`, and medium-widget `Link`s.
4. **Share:** a `ShareLink` in the game sheet toolbar and the card context menu. The item is an `ImageRenderer` snapshot of the existing score card, plus a text line ("KC 27–24 BUF · Final") and the ESPN game web URL. Use the ESPN URL, not `myteams://`: there are no universal links (no associated-domains entitlement), so a custom-scheme URL means nothing to recipients.
5. Tests: `WidgetDeepLinkTests` and `WidgetDeepLinkRoutingTests` cases for game URLs.

**Effort:** M (3–4 days). **Dependencies:** none. **Risk:** low. Rendering a team crest into a shared image raises the same trademark question as showing it in the app (roadmap §4.5). Keep it a personal-share snapshot and don't add branding.

**Non-code:** none.

**Overlap with prior audits.** This **is** pass-3 C-5 phase 2 (`APP_REVIEW_PASS3.md:119`, `:159`), which the widget-polish card deferred. Share is new.

---

## R-4 · Offline-first: last-known schedules, standings and news kept on disk

**User problem.** On a subway or a flight, a relaunch shows error states for every section. Schedules, standings, news, leaders and summaries are held in memory only:
- `HTTPClient` has no retry and no persistent JSON cache beyond the default `URLCache` (`Networking/HTTPClient.swift:263-270`, `:294-329`).
- Only team catalogs and crests reach disk (`RemoteTeamCatalog.swift:251-267`, `LogoStore.swift:107-113`).
- While the app runs, stale data is kept on failure (`TeamModel.swift:555-560`). After a relaunch it is gone.

The widget has the same problem, because it fetches the schedule itself on every timeline (`myTeamWidget/WidgetScheduleLoader.swift:136`).

**Why now.** `RemoteTeamCatalog` already implements the right pattern: one JSON file per key in the shared caches, a TTL, and a fall-back order of fresh, network, stale, bundled (`RemoteTeamCatalog.swift:163-188`). Generalising it is mechanical. `TeamModel` already tracks per-feed `loadedAt` and TTLs (pass-3 A-3, `TeamModel.swift:73`), so freshness labels come for free.

**Sketch.**
- New `Networking/FeedCache.swift`: an actor keyed by feed URL that stores raw `Data` plus `fetchedAt` under `SharedPaths` caches. It has a size cap, an LRU, and evicts anything older than 14 days.
- `HTTPClient.json(from:)` gains an opt-in `cache: .persist` that writes on 2xx and serves the stored copy on `.offline`.
- `TeamModel` and `HomeViewModel` show an "Updated 2 h ago" caption when serving stale data. A design note: use `Theme.Typography.caption` (`Theme.swift:24-43`).
- The widget reads the same cache before going to the network, which also cuts its request count.
- Skip SwiftData. Raw JSON blobs keep the parsers as the single source of truth.
- Tests: `HTTPClientTests` with the existing `StubTransport` (`HTTPClientTests.swift:15-45`) serving `.offline` after a good response.

**Effort:** M (3–5 days). **Dependencies:** none (R-1 benefits). **Risk:** low. Watch disk growth: cap it at about 20 MB. Serving a cached schedule must not feed the live-poll window with stale "live" states. Clamp the `shouldPollLiveScore` input to network-fresh data.

**Non-code:** none.

**Overlap with prior audits.** Roadmap §3.5 said "only adopt SwiftData later, if you add persistent schedule history, offline box scores…" (`ANALYSIS-any-team-roadmap.md:328`). This adds offline support **without** SwiftData, consistent with that doc's preference for JSON files. Roadmap §7 #4 (endless skeletons when offline) was fixed by pass-3-era work. This goes further: it shows data instead of an error.

---

## R-5 · Standings depth: form, streak, conference record, college conferences, rankings

**User problem.** Standings show the table and soccer zones (pass-3 C-2, shipped, `HomeSections.swift:583-605`), but not the context fans look for:
- **Streak** and **conference record** are parsed but never rendered (`Home Menus/Standings.swift:211`, `:213`).
- `seasonDisplayName` is parsed (`Standings.swift:78`, `:141`) and never shown.
- There is no last-5 form guide.
- College leagues are one alphabetical list in the picker (`TeamBrowserView.swift:400-402`, a TODO).
- AP and coaches rankings appear only as a fallback when a college league has no table, and that path is "exercised only by the tests' hand-built document" (`Standings.swift:288-290`, `:379-385`).

**Why now.**
- The two most-asked fields are already in the model.
- Form needs no new endpoint: it can be derived from the team's own schedule, which `Record.swift:150-177` already walks for W-L-D.
- The standings feed's conference `groups` (roadmap §3.6) give the college sections the TODO says are missing.

**Sketch.**
- `HomeSections.swift` standings table: add optional "Strk" and "Conf" columns, shown when non-empty and the width allows (accessibility sizes keep the current columns). Put the season label in the section header.
- `Record.swift`: add `form(last: 5) -> [Outcome]`, rendered as five W/D/L capsules on the team header next to the record (the header in `HomeSections.swift`).
- College conferences: during catalog load, read `/apis/v2/sports/{s}/{l}/standings` groups, map `teamID` to the conference name in `RemoteTeamCatalog`, and section the browser list. Store it as an optional `conference` on `TeamRef` (Codable default nil, so no migration).
- Rankings: show "#7" before college team names on cards and in the header when the poll lists them. Capture a live rankings fixture (via `scripts/capture_fixtures_p3a.py`) to retire the hand-built one.

**Effort:** M (4–6 days; columns and form alone are S). **Dependencies:** none. **Risk:** the standings group shape differs between college and pro (roadmap §6 Phase 3). The rankings endpoint is unexercised live, so capture before building.

**Non-code:** none.

**Overlap with prior audits.** Pass-3 C-2 (zones) shipped. Roadmap §3.6 proposed conference sections, and this implements that. No contradiction.

---

## R-6 · Smarter alerts: close-game and OT alerts, per-team event choice, Time Sensitive

**User problem.**
- There are only four event kinds: start, score change, period end and final (`Home Menus/ScoreDiff.swift:141-146`). There is no "close game late", "going to OT" or "upset" alert, which are the ones that make people open the app.
- Event types are global (`AlertsSettings.swift:138-162`). A reader can't take finals only for one team and every goal for another.
- Permission is requested with `[.alert, .sound]` only (`ScoreAlertsPermissions.swift:34`), and nothing uses `.timeSensitive`, so Focus modes swallow a final.

**Why now.** `ScoreDiff` is a pure, well-tested diff (`ScoreDiffTests`, `ScoreAlertEngineTests`), so new event kinds are cheap and testable. Quiet hours and `interruptionLevel` handling already exist (`ScoreAlertEngine.swift:293-299`). Per-team settings already exist as `FavoriteTeam.notify`, which is iCloud-merged with `notifyChangedAt` (`FavoritesStore.swift:344-375`).

**Sketch.**
- `ScoreDiff.swift`: add `.closeLate`, fired once per game when the period is at least the league's final period, the margin is at most N (from the league: 1 goal in soccer and hockey, 8 points in basketball, 8 in football), and the clock is under a threshold. Add `.overtime` on the period crossing regulation. Thresholds go in `LeagueDescriptor` (`Sport.swift:131-209`) alongside `periodStyle`.
- `FavoriteTeam`: replace `notify: Bool` with `notify: AlertMask?`, where nil means "use the global default". Decode the old Bool as the global default so stored data migrates.
- `AlertsSettingsView`: a per-team detail push.
- `ScoreAlertEngine.post`: finals and close-late use `.timeSensitive` outside quiet hours.

**Effort:** S–M (2–4 days). **Dependencies:** R-1 makes it useful with the app closed. **Risk:**
- Time Sensitive needs the `com.apple.developer.usernotifications.time-sensitive` entitlement. Both signed workflows check entitlements (`ios-signed-gate.yml:308-422`), so add it to `myTeams-app.entitlements` and the profiles.
- Overuse of Time Sensitive can be flagged in App Review and annoys readers, so keep it to finals and close-late.

**Non-code:** regenerate the provisioning profiles with the new capability (`CIOSIGNING.md` §Secrets).

**Overlap with prior audits.** Pass-3 C-3 (quiet hours and per-event choice) shipped globally. This adds per-team choice and new event kinds, which C-3 didn't cover. Pass-3 A-11 (stage labels) and A-12 (coalescing) shipped and are reused.

---

## R-7 · Add games to the calendar (one game or a whole season)

**User problem.** Readers plan around kickoffs, but the app can't put a game, or a season of games, on their calendar. There is no `EventKit` import anywhere in the tree.

**Why now.** Upcoming cards carry the start time, venue and broadcast (`GameView.swift:579-587`). Context menus already exist on cards. Times are parsed as UTC (`DownloadScheduleData.swift:162-185`), so events are correct across time zones.

**Sketch.**
- **One game:** a context-menu item on upcoming cards and a toolbar item in the game sheet. Present `EKEventEditViewController` (write-only access, iOS 17+: `NSCalendarsWriteOnlyAccessUsageDescription` in `Info.plist`). Fill in the title ("Chiefs vs Bills"), start, a duration by sport, the venue as location, the broadcast in notes, and a `myteams://game/…` URL once R-3 lands.
- **Season:** "Add remaining games" on the schedule section header menu (`HomeSections.swift`). Batch-write with `EKEventStore` into a dedicated "myTeams – <Team>" calendar, with the ESPN event id stored in the URL field. A later "Update calendar" can then move rescheduled games rather than duplicating them.
- Tests: a pure `CalendarEventBuilder(game:) -> EventDraft` in `GameCardContentTests`.

**Effort:** S for a single game; M with season sync. **Dependencies:** R-3 for the deep link (optional). **Risk:**
- The write-only permission prompt needs clear wording.
- Rescheduled and TBD-time games: skip `"TBD"` times (the `GameCardContent.broadcast(of:)` pattern) or write all-day events.

**Non-code:** none.

**Overlap with prior audits.** This **is** pass-3 C-9 (`APP_REVIEW_PASS3.md:123`), not yet implemented. It adds season sync, which C-9 didn't cover.

---

## R-8 · Server push for alerts and Live Activities (roadmap P4-e)

**User problem.** The same as R-1, but needing minute-accurate delivery and Live Activities that update on the Lock Screen for a whole game. Today activities start only in the foreground (`LiveActivityManager.swift:152`) with `pushType: nil` (`:243-247`), go stale after 10 minutes without the app (`:52`; "Open myTeams to update", `GameLiveActivity.swift:135-136`), and are capped at 6 (`LiveActivityStateMapper.swift:148`).

**Why now.** The client seams are in place:
- `AppDelegate.pushRegistrationEnabled = false` with token capture written (`AppDelegate.swift:18-47`).
- `ScoreEvent` and the debounce are designed to be shared by both sides (`ScoreAlertEngine.swift:35-37`).
- Live Activity updates are already serialised per game.

What's missing is entirely server-side, plus entitlements.

**Sketch.**
- **Server** (new repo): a poller of league scoreboards every 15–30 s in live windows. Port `ScoreDiff`'s rules to it, or keep it in Swift with Swift on Server and share the `ScoreDiff.swift` file. Add a device and subscription registry keyed by `TeamRef.id` plus `AlertMask` (R-6), and an APNs sender for alerts and `liveactivity` pushes.
- **Client:**
  - Flip `pushRegistrationEnabled` and POST the token and favorites (from `FavoritesStore`) on change.
  - `Activity.request(…, pushType: .token)`, observe `pushTokenUpdates`, and upload them.
  - Use iOS 17.2+ push-to-start, so activities can begin without the app.
  - Add `aps-environment` to `myTeams-app.entitlements`.
  - Keep R-1's local path as the fallback when no server answers.

**Effort:** L (server 2–3 weeks; client about 1 week). **Dependencies:**
- a hosted backend, an APNs auth key, and the push capability on the App ID and profiles;
- ideally a licensed data feed (roadmap §5.4);
- a distribution path for which push makes sense. It works with ad-hoc and development builds, but sideloaded Feather re-signs with a single profile (`CIOSIGNING.md:48-52`), which will usually lack push.

**Risk: high.**
- One server IP polling ESPN is far more visible than spread-out clients, and redistributing ESPN data is a clearer ToS problem (`ANALYSIS-any-team-roadmap.md:542`).
- Hosting costs.
- The privacy story changes: the site's "no account, no data collected" claim has to be revised, and so does `PrivacyInfo.xcprivacy`.

**Non-code:** backend hosting, an Apple Developer APNs key, a privacy-policy update, and possibly a data licence.

**Overlap with prior audits.** This **is** roadmap §6 Phase 4 (`ANALYSIS-any-team-roadmap.md:536-542`) and §5.4's trigger list. It is restated here only to map it onto today's seams, and I agree with that doc's risk assessment. Ranked 8th despite the highest impact because of effort and risk. Do R-1 first.

---

## R-9 · Widget family expansion: Large "My Day", inline accessory, Control Center control

**User problem.** There is one widget kind, for one team at a time, in `.systemSmall`, `.systemMedium`, `.accessoryRectangular` and `.accessoryCircular` (`myTeamWidget/myTeamWidget.swift:490-496`). A reader with six favorites needs six widgets to see today's games. There is no `.systemLarge`, no `.accessoryInline` (the line above the Lock Screen clock), and no Control Center control.

**Why now.**
- The App Group snapshot already holds every favorite's live and final lines (`WidgetScoreboardSnapshot.swift:81-105`).
- Favorites are readable from the shared defaults (`TeamRef.swift:672`).
- Crests are in the shared `LogoStore`.
- Home already computes exactly the "My Day" set (live, then upcoming, then results within ±7 days) in `HomeViewModel.swift:63-157`, and that logic is UI-free.

**Sketch.**
- Move `HomeFeed`'s window and grouping functions into a file compiled into both targets, like `WidgetScoreboardSnapshot.swift` (`:17`).
- New widget kind `"myTeamsDay"`, a `StaticConfiguration` with `.systemLarge` (and `.systemExtraLarge` on iPad): up to 6 rows of live, today and next games across favorites, each row a `Link` to R-3's game URL.
- Add `.accessoryInline` to the existing kind: "KC 21–17 Q3" or "KC vs BUF 7:20".
- `ControlWidget` (iOS 18+): "Open live game", a `ControlWidgetButton` whose `OpenIntent` targets the first live favorite game, or the Home tab otherwise.
- Previews for the `.fullColor` and `.accented` rendering modes, following the existing pattern (`myTeamWidget.swift:572-592`).

**Effort:** M (4–5 days). **Dependencies:** R-1 for freshness with the app closed. R-3 for row links. **Risk:**
- Large timelines that hold many games must stay inside the widget memory budget, so read crests downscaled from `LogoStore`.
- The widget extension has no tests at all today (no test touches `myTeamWidget/`). Add a `WidgetDayBuilder` test with the feed logic.

**Non-code:** none.

**Overlap with prior audits.** GlassUI W-3 and AC-1 (medium and accessory layouts) and pass-3 C-5 phase 1 (live and last result) are shipped. Roadmap §3.7 suggested accessory families, which shipped. Large, inline and Control are new.

---

## R-10 · Player depth: game logs, previous seasons, AVG/OBP/SLG

**User problem.** A player sheet shows only the current season split (`Roster/Classes/DownloadAthleteData.swift:364`) and bio facts (`PlayerDetailView.swift:98-464`). There are no recent games, no previous seasons, and no career line. Baseball batters see OPS only: the comment says "The feed gives no AVG, OBP or SLG" (`PlayerDetailView.swift:234-235`), but `Avg`, `OnBasePct` and `SlugAvg` **are** parsed (`DownloadAthleteData.swift:592-594`).

**Why now.** The athlete endpoint family the app already calls (`site.web.api.espn.com/apis/common/v3/…/athletes/{id}` and `/splits`) also serves `/gamelog` and multi-season `/stats` (roadmap §5.2, `ANALYSIS-any-team-roadmap.md:437`). Name-keyed stat parsing is in place for football and baseball (pass-3 A-16), so the same `names`-zipped reader extends to game logs.

**Sketch.**
- `DownloadAthleteData.swift`: `downloadGameLog(athlete:league:)`, parsed into `[GameLogRow(date, opponentID, result, stats: [name: display])]` with name-keyed columns.
- `PlayerDetailView.swift`: a "Last 5 games" card under Season Stats, and a season picker (`Picker(.menu)`) when the stats document lists several seasons.
- Baseball: show the AVG/OBP/SLG slash line (cheap win #9) as a headline tile.
- Capture fixtures per sport with `scripts/capture_fixtures_p3d.py athletes` (extend it with gamelog URLs) and add golden tests to `PlayerSeasonStatsTests.swift`.

**Effort:** M (4–6 days across five sports; baseball slash line is a cheap win). **Dependencies:** none. **Risk:**
- Game-log shapes differ per sport, and soccer game logs are thin (roadmap §5.3).
- Each sheet adds one request, made lazily when the card scrolls into view.

**Non-code:** none.

**Overlap with prior audits.** Roadmap §5.3 "Deep stats" notes historical seasons are patchy. This recommendation agrees and scopes to what the endpoint returns. Phase 3's "roster/athlete parity" shipped.

---

## R-11 · Headshot coverage v2: tier independence, negative-cache TTL, club aliases, coverage readout

**User problem.** Soccer rosters, especially the WSL and Première Ligue, are still largely silhouettes. The headshot doc found ESPN at WSL 0/24 and EPL 2/27 (`HEADSHOT_SOURCE_APIFOOTBALL.md:139`). Four structural gaps keep photos away even when a source has them:
1. **Tier 3 waits on tier 2.** API-Football is only asked once Wikidata has *answered* with no photo (`Roster/Views/AthleteHeadshot.swift:71-76`). A Wikidata backoff (`WikidataHeadshotStore.swift:345`, `:622-626`) therefore blocks tier 3 too.
2. **"No photo" is cached forever.** "A cached athlete is never asked about again" (`WikidataHeadshotStore.swift:72`, `:295`). `HeadshotRecord.checked` is written (`:76`) but never read. A player who gets a Commons photo mid-season never shows it.
3. **Club-name misses.** "Wolverhampton Wanderers" vs "Wolves" gets no tier 3 at all (`APIFOOTBALL_LIVE_DIAGNOSTIC.md:70-72`). Clubs are matched on `team.displayName` (`TeamHomeView.swift:187`), and a club with no match is silently never swept.
4. **No visibility.** A reader who saved a key can't tell whether it's doing anything. The Settings section shows key status only (`ApiFootballSettingsSection.swift:79-100`).

**Why now.** Tier 3 shipped this week (`ca8e834`, `e72f55e`), and the live diagnostic left these as explicit follow-ups. All four are local changes to the two stores.

**Sketch.**
- `AthleteHeadshot.apiFootballPhoto`: also accept "Wikidata unavailable" (store backoff active, or no record after the 2 s cap), not just "answered with none".
- `WikidataHeadshotStore`: re-ask "no photo" records whose `checked` is older than 30 days, in the existing 200-id batches. Leave positive hits alone.
- `ApiFootballHeadshotStore`:
  - add a small alias table (`["Wolverhampton Wanderers": "Wolves", "Brighton & Hove Albion": "Brighton", …]`) consulted before `teamsMatch`, plus a fallback match on the API's `team.code` against ESPN's abbreviation;
  - log unmatched clubs;
  - move the 1 h pause to persisted state on the injected clock (`:872-881` uses `Date()`);
  - spend the budget after a response rather than before (`:841`).
- Settings: an "API-Football usage" row showing today's requests (out of 40), clubs swept, and photos found, read from `ApiFootballBudget` and the sweep files.

**Effort:** S–M (2–3 days). **Dependencies:** the reader's own key (unchanged). **Risk:**
- Low on the client side.
- The free plan's season cap (2024 newest, `APIFOOTBALL_LIVE_DIAGNOSTIC.md:27-28`) still limits new signings, and that won't change.
- Re-asking Wikidata adds load. At 30 days and in batches, it's negligible.

**Non-code:** none beyond the reader's key. Re-confirm API-Football's terms (`HEADSHOT_SOURCE_APIFOOTBALL.md:182-186` asked for a human review before adoption; record whether that happened).

**Overlap with prior audits.** This directly picks up `APIFOOTBALL_LIVE_DIAGNOSTIC.md:70-72` (known gap) and does not contradict either headshot doc. Their "never wire an id-through without an identity join" rule (`HEADSHOT_SOURCE_APIFOOTBALL.md:124-127`) is kept: aliases only affect club matching, and players are still joined by name and team.

---

## R-12 · App Intents, Siri and Spotlight: "When do the Chiefs play next?"

**User problem.** The app has no system presence outside the widget. There are no App Shortcuts, no Siri phrases, no Spotlight results for a followed team, and no Handoff. App Intents exist only inside the widget for team selection (`myTeamWidget/TeamEntity.swift:17`, `:94`).

**Why now.** `TeamEntity: AppEntity` with an `EntityQuery` over favorites and cached catalogs already exists and works (`TeamEntity.swift:37-89`). Moving it into a file shared by both targets makes it usable by app intents. Next-game data comes from the same schedule download the widget already uses (`WidgetScheduleLoader.swift:136`).

**Sketch.**
- Move `TeamEntity` and `TeamEntityQuery` to a file compiled into both targets.
- App target: `NextGameIntent(team:)` returns a dialog plus a snippet view: the existing small widget view, reused. Add `OpenTeamIntent(team:)` (`openAppWhenRun`, routing through the existing deep link).
- An `AppShortcutsProvider` with phrases like "When do \(.applicationName)'s \(\.$team) play next" and "Open \(\.$team) in \(.applicationName)".
- Spotlight: make `TeamEntity` conform to `IndexedEntity` (iOS 18) and index favorites on change in `FavoritesStore`, so typing "Chiefs" in Spotlight offers the team page.
- Tests: an intent `perform()` test against fixture schedules (`FixtureTransport`, `HTTPClient.swift:160-196`).

**Effort:** M (3–4 days). **Dependencies:** none (R-3 for game-level intents). **Risk:**
- Low. App Intents are compile-time metadata.
- Phrases must contain the app name.
- Localization of phrases needs a string catalog (see "Also considered").

**Non-code:** none.

**Overlap with prior audits.** None. The roadmap's §3.7 `TeamEntity` design shipped for the widget, and this reuses it.

---

## Also considered (not in the ranked list)

- **Localization (String Catalog).** There are no `.strings` or `.xcstrings` files. `knownRegions` is only `en` (`project.pbxproj:759-762`), although `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`. English is hard-coded in the model layer (box-score titles `DownloadGameData.swift:517-596`, period names `Sport.swift:216-218`, `"pts"` `Record.swift:90`), and plurals are built by interpolation (`TeamBrowserView.swift:517`). With 9 European and Mexican soccer leagues, Spanish, French and German would fit. Not ranked: it is L once you count translation, it needs translators (non-code), and it's best done after the string surface settles. A useful first step is extracting the model-layer strings into `LocalizedStringResource`.
- **Fixture drift canary.** `scripts/verify_acceptance_p3e.py` and the capture scripts never run in CI, and drift detection is manual (`myTeamsTests/FIXTURES.md:775-803`). A weekly scheduled workflow could re-capture to a temp directory and diff key paths. Not ranked: it's a CI change (out of scope for this audit's file rule), and ESPN rate-limits GitHub runner IPs unpredictably.
- **iPad sidebar.** Already covered by GlassUI X-10 and pass-3 B-14. Not repeated.
- **Odds and pickcenter.** Present in every summary fixture, but deliberately excluded (R-2 risk note).

---

## Cheap wins (S or less)

Found during the pass. Grep run over `*.swift`, `*.py` and `*.yml` for `TODO|FIXME|XXX|HACK|unimplemented|fatalError|not yet|stub|#if false|deprecated`. **There are no FIXME, HACK, `unimplemented` or `#if false` hits.** Every `TODO` and `fatalError` hit is listed (#1–#5). The "not yet", "stub" and "placeholder" hits were all behavioural comments or identifiers, not unfinished work, and are omitted. The rest are dead code, stale comments and parsed-but-unshown data found by reading.

### Markers (TODO / fatalError)

| # | Where | What | Fix |
|---:|---|---|---|
| 1 | `Hawk Nation/Home Menus/TeamBrowserView.swift:400-402` | `// TODO(P3): conference sections for college leagues.` | Tracked as R-5 (M as a whole). Listed here for completeness |
| 2 | `Hawk Nation/Classes/Theme.swift:74-75` | `// TODO(GlassUI): try ConcentricRectangle here once confirmed in the SDK…` | Verify on the iOS 26 SDK (it is in the iOS 26 SwiftUI API), then swap and delete the TODO |
| 3 | `.github/workflows/ios-gate.yml:11`, `build-ipa.yml:93`, `ios-signed-gate.yml:68` | `# TODO(GlassUI 0.1): move to the GitHub image that ships Xcode 27…` | Pin `runs-on` and `xcode-select` once the image exists. **CI change, out of scope for this doc. Noted only** |
| 4 | `Hawk Nation/Networking/TeamRef.swift:515` | `fatalError("The bundled teams.json could not be read: …")` | `assertionFailure` plus an empty seed. A corrupt bundle file shouldn't crash a Release launch, now that `RemoteTeamCatalog` exists |
| 5 | `Hawk Nation/Networking/TeamRef.swift:533` | `fatalError("teams.json has no …")` | Same: return nil from the lookup |

### Stale comments

| # | Where | What | Fix |
|---:|---|---|---|
| 6 | `Hawk Nation/Home Menus/ScoreAlertEngine.swift:363-368` | Says the foreground hook "is not wired there yet … Until then it stays nil". It is wired at `NavigationBar/TabBar.swift:229-231` | Update the comment |
| 7 | `Hawk Nation/Home Menus/ScoreAlertEngine.swift:32-34` | "runs only while … a team page wants a live day". The center follows all favorites in the foreground (`MyTeamsApp.swift:76-79`) | Update (and again after R-1) |
| 8 | `Hawk Nation/Home Menus/AlertsSettingsView.swift:34` | "Reached from the team browser". It is only opened from Settings since B-9 | Update |
| 9 | `Hawk Nation/NavigationBar/TabBar.swift:14-16` | Home described as "today's games". It is a ±7-day window (`HomeViewModel.swift:63`, `:66`) | Update |
| 10 | `Hawk Nation/Networking/TeamRef.swift:502-504` | "Loading catalogs from ESPN is Phase 2". `RemoteTeamCatalog` already does it | Update |
| 11 | `myTeamWidget/WidgetScheduleLoader.swift:85-87` | "the legacy fixed-team widgets pin a seed team". They are retired (`myTeamWidget.swift:512-514`) | Delete the clause |
| 12 | `Hawk Nation/Home Menus/TeamHomeView.swift:182-183` | "starts the league's weekly sweep". Sweeps are per club since `e72f55e` | Update |

### User-visible

| # | Where | What | Fix |
|---:|---|---|---|
| 13 | `Hawk Nation/Roster/Views/PlayerDetailView.swift:269` | Typo shown to users: `"Save Opportunites"` | `"Save Opportunities"` |
| 14 | `Hawk Nation/Roster/Views/PlayerDetailView.swift:234-235` vs `Roster/Classes/DownloadAthleteData.swift:592-594` | "The feed gives no AVG, OBP or SLG", but they are parsed | Show the slash line as a batter headline tile (part of R-10) |
| 15 | `Hawk Nation/Home Menus/TeamHomeView.swift:30` | `case .other: EmptyView()`: a league of unknown sport kind renders a blank page | `ContentUnavailableView` with the schedule only, or a "Not supported yet" message |
| 16 | `Hawk Nation/Schedule/Classes/DownloadGameData.swift:311-312` | `capacity` and `attendance` parsed, never shown | Add "Att. 73,421" to the game sheet venue line for finished games |
| 17 | `Hawk Nation/Home Menus/Standings.swift:78`, `:211`, `:213` | `seasonDisplayName`, `streak` and `conferenceRecord` parsed, never shown | Season label in the standings header now; columns in R-5 |
| 18 | `Hawk Nation/Home Menus/HomeSections.swift:794-800` | Article context menu ("open tagged team") exists on team pages only; Home's merged feed has none | Reuse the same `.contextMenu` in `HomeView`'s news rows |
| 19 | `Hawk Nation/Schedule/Views/GameView.swift:602-619` | `cupDisplayName` has no women's cups (`eng.w.fa`, `eng.w.league_cup`, `uefa.wchampions`, from `Sport.swift:580`, `:599`). Falls back to the raw feed name | Add three cases plus a `GameCardContentTests` case |

### Dead or test-only code

| # | Where | What | Fix |
|---:|---|---|---|
| 20 | `Hawk Nation/Roster/Views/BioViews.swift:13`, `Roster/Views/StatView.swift:13` | `BioView` and `StatView` are referenced only by their own `#Preview`s. `PlayerDetailView` uses private `FactRow`/`StatCell` | Delete both files (and pbxproj entries) |
| 21 | `Hawk Nation/Schedule/Classes/DownloadGameData.swift:135` | `parseLiveGameScore` has no production caller (scores come from the scoreboard) | Delete it, with its tests, or mark it test-support |
| 22 | `Hawk Nation/Schedule/Classes/SoccerLineups.swift:30`, `:150`; `News/Classes/DownloadNewsData.swift:11` | `subbedOut` and `News.author` are parsed, never read by a view | Drop, or use: `subbedOut` for an "off" arrow when the minute is missing; `author` under the headline |
| 23 | `myTeamWidget/GameLiveActivity.swift:131-134` | The `.pending` kickoff branch is unreachable: activities start only when live (`LiveActivityStateMapper.swift:233-241`) | Delete, or keep it for R-8 push-to-start (where it becomes reachable) and note why |
| 24 | `Hawk Nation/Home Menus/GameActivityAttributes.swift:102` | A second `ordinal` (the widget can't see `ScoreSnapshot.ordinal`) | Move one copy to a file shared by both targets |

### Robustness and docs

| # | Where | What | Fix |
|---:|---|---|---|
| 25 | `Hawk Nation/Networking/ApiFootballHeadshotStore.swift:838-841`, `:875-881` | The budget is spent before the request; the 1 h pause uses `Date()`, not the injected clock, and lives in memory only | Spend after the response; use `now()`. (Part of R-11, but each is a one-liner) |
| 26 | `README.md:8`, `:12`, `:142` | "No API keys are needed" (there is an optional API-Football key); "ten leagues" (19 registered, 18 browsable: `TeamRef.swift:76-82`, `:360-380`); "`seedIDs` seeds it on a fresh install" (fresh installs start empty, `FavoritesStore.swift:95`) | Docs fix |
| 27 | `site/screenshots/` (only `.gitkeep`); `site/index.html:122-127` | All 7 screenshot slots show placeholders; "Live scores and alerts" doesn't say foreground-only | Add captures (the `GlassUIScreenshotTests` harness can produce them with `GLASSUI_SCREENSHOTS=1`); add the caveat until R-1 ships. **Screenshots are a non-code deliverable** |

---

## Method notes

- Static reading only. This host has no `xcodebuild`, so nothing was built or run. Line numbers are from `e983fe7`.
- The "already in the feed" claims for R-2 were checked by grepping the captured fixtures for each key (`keyEvents`, `scoringPlays`, `winprobability`, `injuries`, `pickcenter`). Fixtures are trimmed captures (`scripts/capture_fixtures_*.py`), so presence is confirmed but completeness per game is not.
- Effort assumes one engineer who knows the codebase, including tests and fixture captures, and excludes design time.
