# MyTeams Architecture Analysis — Path to an Any-Team Sports App

Repo: /home/srector/workspace/MyTeams @ main (25700d6). Generated 2026-09-27 by read-only Claude Code analysis passes.

---

## §1 Architecture map

**Premise correction:** `TeamModel.swift` does not contain the `Team` enum. `Team` is defined in `Hawk Nation/Networking/Sport.swift:23`. `TeamModel.swift` holds the generic per-tab view model `TeamModel<Player>` (`TeamModel.swift:42`).

### 1.1 Team definitions (`Hawk Nation/Networking/Sport.swift`)
- `enum Team: String, CaseIterable, Identifiable` has four cases: `jayhawks = "jayhawk"`, `chiefs`, `royals`, `sporting` (`Sport.swift:23-27`). The raw value is also the logo asset name (`Sport.swift:21-22`, `:54`).
- Every per-team property is an exhaustive `switch`:
  - `displayName` (`:34-41`)
  - `shortName` (`:44-51`)
  - `brandRGB` (`:63-70`), from which `color` (`:73-79`) and `brandHex` (`:84-89`) are derived
  - `leaguePath` (`:94-101`)
  - `espnTeamId` (`:104-111`)
  - `homeCity` (`:114-119`)
  - `boxscoreName` (`:123-130`)
  - `scheduleTeamName` (`:136-143`)
  - `scheduleNameField` (`:145-150`)
- A header comment says this enum replaced three drifting copies (`Sport`, a TabBar `Team`, and `WidgetTeam`) (`Sport.swift:14-19`, `WidgetScheduleLoader.swift:47-50`).
- `TeamNameField` (`.nickname` / `.shortDisplayName`) is defined in `DownloadScheduleData.swift:42-45`.

### 1.2 Networking and data flow
- **HTTP layer.** `HTTPClient.json(from:)` uses one cached `URLSession` with a 20 s timeout and `waitsForConnectivity` (`HTTPClient.swift:22-28`). Non-2xx responses, errors and cancellations all return `JSON.null` rather than throwing (`:31-48`). A malformed URL string also returns `.null` (`:52-61`).
- **ESPN URLs built from `Team`:**
  - Schedule: `https://site.api.espn.com/apis/site/v2/sports/{leaguePath}/teams/{espnTeamId}/schedule` (`Sport.swift:154-156`)
  - Summary: `…/sports/{leaguePath}/summary?event={gameID}` (`Sport.swift:158-160`)
- **ESPN URLs hardcoded as literals, not built from `Team`:**
  - Rosters: `…/basketball/mens-college-basketball/teams/2305/roster` (`DownloadRosterData.swift:118`), `…/football/nfl/teams/12/roster` (`:154`), `…/baseball/mlb/teams/7/roster` (`:201`), `…/soccer/usa.1/teams/186/roster` (`:243`)
  - Athlete splits on `site.web.api.espn.com/apis/common/v3/sports/{league}/athletes/{id}/splits`: NFL (`DownloadAthleteData.swift:221`), NCAAM (`:333`), MLB (`:371`)
  - Soccer athlete: `…/soccer/usa.1/athletes/{id}` (`:425`). Its loader `downloadSoccerPlayerStats` has no callers; the only references are in its own file (`DownloadAthleteData.swift:263-442`).
  - Headshot fallback on `a.espncdn.com` (`DownloadRosterData.swift:96`)
- **News.** Uses NewsAPI `https://newsapi.org/v2/everything?{query}&sortBy=publishedAt&apiKey=` (`NewsFeed.swift:19-21`). The key comes from the `NEWS_API_KEY` Info.plist entry (`NewsFeed.swift:15-17`, `Hawk Nation/Info.plist`, pbxproj `:780`, `:805`).
- **Schedule parsing.** `downloadScheduleData(queryURL:teamName:teamNameField:)` maps `events` into `Game` values (`DownloadScheduleData.swift:213-228`).
  - The followed team is found by comparing `competitor.team[teamNameField] == teamName`; any other competitor is the opponent (`:162-169`).
  - `Game.team` holds the `teamName` string (`:184`).
  - Display times are pinned to `America/Chicago` (`:59`).
- **Load cycle (`TeamModel.load`).** Roster, schedule and news are fetched concurrently (`TeamModel.swift:108-122`).
  - The schedule comes from `team.scheduleURL`, `scheduleTeamName` and `scheduleNameField` (`:176-182`).
  - The schedule is refetched every 60 s (`:129-139`).
  - Live scores are fetched only for games in the polling window (`:146-174`, `:275-280`), via `downloadLiveGameScore(gameID:team:isHome:)`, which reads `team.summaryURL` and `team.boxscoreName` (`DownloadGameData.swift:129-152`).
- **Detail sheets.**
  - Game sheets poll every 10 s. Each calls a per-sport stats loader plus `downloadGameInfo(gameID:team:)` (`GameDetailView.swift:405-407`, `:788-790`, `:1063-1065`, `:1340-1342`).
  - `downloadGameInfo` picks the accent colour using `team.homeCity`, `team.brandHex` and `team.boxscoreName` (`DownloadGameData.swift:159-182`).
  - Player sheets fetch splits once in `.task` (`PlayerDetailView.swift:244-245`, `:477-478`, `:792-796`).
- **Widget.** `WidgetScheduleLoader.nextGame(for:)` reuses `downloadScheduleData` with the same three `Team` properties (`WidgetScheduleLoader.swift:70-75`). It picks the earliest future game that is neither cancelled nor postponed (`:85-88`) and embeds the opponent logo bytes (`:96`, `:101-104`).

### 1.3 How views branch on team identity
- **Sport is fixed per file and per type, not chosen with a runtime switch.** There is one `Home` view per team (§2), each with a concrete player type:
  - `TeamModel<FootBallPlayer>` (`ChiefsHome.swift:12`)
  - `TeamModel<BasketballPlayer>` (`JayhawksHome.swift:12`)
  - `TeamModel<BaseballPlayer>` (`RoyalsHome.swift:12`)
  - `TeamModel<SoccerPlayer>` (`SportingHome.swift:12`)
- **Each Home view hand-picks its card and detail types:**
  - Schedule card: `FootballGameView` for the Chiefs only (`ChiefsHome.swift:62`); `GameView` for the other three (`JayhawksHome.swift:34`, `RoyalsHome.swift:46`, `SportingHome.swift:49`)
  - Game detail: `BasketballGameDetailView` / `FootballGameDetailView` / `BaseballGameDetailView` / `SoccerGameDetailView`
  - Player detail: one `*PlayerDetailView` per sport
- **Per-team behaviour flags are passed as arguments:**
  - `usesDateForNextGame: true` for Sporting only (`SportingHome.swift:17`)
  - `countsAbandonedGamesAsLosses: true` for the Royals only (`RoyalsHome.swift:45`)
- **The only runtime branch on identity is string matching** in `getPeriod(period:team:)`. It compares `Game.team` against `"Kansas"` / `"Kansas City"` (halves), `"Royals"` (empty) and `"KC"` (quarters) (`GameView.swift:639-663`).
- **The shared sections are team-agnostic:** `RosterSection`, `ScheduleSection`, `NewsSection` and `TeamHomeLayout` in `HomeSections.swift:45`, `:114`, `:183`, `:227`.

### 1.4 TabBar, HomeSections and widget wiring
- **App entry.** `MyTeamsApp` → `Home()` (`MyTeamsApp.swift:14-16`).
- **Home (`TabBar.swift`).**
  - The default selection is `.jayhawks` (`TabBar.swift:17`).
  - Four hardcoded `TeamPage(team:) { XHome() }` stacks are toggled by opacity (`:25-32`).
  - The team picker is data-driven through `Team.allCases` (`:138`, `:159`), so the picker and the page stack can disagree.
  - `TeamPage` and `TopView` read `team.color`, `team.logo`, `team.displayName` and `team.logoImage` (`:59`, `:65`, `:79`, `:178`, `:183`).
- **HomeSections.** Contains no team references. Each Home view supplies the `TeamModel`, its closures and `teamColor`.
- **Widget (`myTeamWidget/myTeamWidget.swift`).**
  - One shared `GameTimelineProvider(team:)` with hourly refresh (`:22-53`).
  - Four hand-written `Widget` structs (`:108-162`), registered in the `ScheduleWidgets` bundle (`:165-171`).
  - The background crest is `Image(entry.tempGame.backgroundLogo)` = `team.logo` (`:94`; `WidgetScheduleLoader.swift:36`, `:91`), so it must resolve in the widget's own asset catalog.
- **Shared code.** The widget target compiles `HTTPClient.swift`, `JSON.swift`, `Sport.swift` and `DownloadScheduleData.swift` from the app (pbxproj `:47-50`, `:601-604`).

---

## §2 Coupling-point inventory (file by file)

### `Hawk Nation/Networking/Sport.swift`
- `:23-27`: the case list, and the raw value `"jayhawk"` as the asset key
- `:34-41` `displayName`, `:44-51` `shortName`, `:63-70` `brandRGB`
- `:94-101` `leaguePath` (`basketball/mens-college-basketball`, `football/nfl`, `baseball/mlb`, `soccer/usa.1`)
- `:104-111` `espnTeamId` (2305, 12, 7, 186)
- `:114-119` `homeCity` (`"Lawrence"` / `"Kansas City"`)
- `:123-130` `boxscoreName` (`"Kansas"`, `"Chiefs"`, `"Royals"`, `"Kansas City"`)
- `:136-143` `scheduleTeamName` (`"Kansas"`, `"KC"`, `"Royals"`, `"Kansas City"`)
- `:145-150` `scheduleNameField`
- `:155`, `:159`: ESPN host and path templates

### `Hawk Nation/Home Menus/TeamModel.swift`
- `:22-25`: `RosterPlayer` conformances for exactly four sport-specific player types
- `:37-39`: the doc comment assumes "the four tabs"
- `:91-92`, `:228-230`: doc references to "the baseball tab" / `RoyalsHome` rule
- `:67`, `:156-159`, `:176-182`: `Team` drives the schedule and live-score URLs. Generic in itself, but bounded by the enum.

### `Hawk Nation/Home Menus/ChiefsHome.swift`
- `:12-16`: `TeamModel<FootBallPlayer>(team: .chiefs, newsURL: NewsFeed.chiefs, loadRoster: downloadFootballRoster)`
- `:18`: `Team.chiefs.color`
- `:29-57`: hardcoded NFL unit and position filter lists, keyed on the unit strings `"defense"`, `"offense"`, `"specialTeam"`
- `:90`, `:95`: filters on `FootBallPlayer.team`, which actually holds the unit string (`DownloadRosterData.swift:42`, `:187`)
- `:62-73`: `FootballGameView` / `FootballGameDetailView` with `team: .chiefs`

### `Hawk Nation/Home Menus/JayhawksHome.swift`
- `:12-16`: `.jayhawks`, `NewsFeed.jayhawks`, `downloadBasketballRoster`
- `:18`: `Team.jayhawks.color`
- `:28-29`: filters on `"Forward"` / `"Guard"`
- `:25`: `BasketballPlayerDetailView(player:)` receives no `teamColor`
- `:34-45`: `team: .jayhawks`

### `Hawk Nation/Home Menus/RoyalsHome.swift`
- `:12-16`: `.royals`, `NewsFeed.royals`, `downloadBaseballRoster`
- `:18`: `Team.royals.color`
- `:20-23`: MLB position list
- `:45`: `countsAbandonedGamesAsLosses: true`
- `:46-57`: `team: .royals`

### `Hawk Nation/Home Menus/SportingHome.swift`
- `:12-19`: `.sporting`, `NewsFeed.sporting`, `usesDateForNextGame: true`, `downloadSoccerRoster`
- `:21`: `Team.sporting.color`
- `:24-29`: soccer position-to-label map
- `:49-60`: `team: .sporting`

### `Hawk Nation/Home Menus/HomeSections.swift`
- `:117-119`: `countsAbandonedGamesAsLosses` flag (a per-team rule surfaced as a parameter)
- `:226`: comment "shared by all four team pages". No other coupling.

### `Hawk Nation/NavigationBar/TabBar.swift`
- `:17`: default `.jayhawks`
- `:25-32`: four hardcoded `TeamPage` / `XHome()` pairs with per-case opacity checks. Adding a case to `Team` would add a picker button with no page.
- `:138`, `:159`: `Team.allCases` (picker)

### `Hawk Nation/News/Classes/NewsFeed.swift`
- `:23-46`: one static query per team (`jayhawks`, `chiefs`, `royals`, `sporting`) with team-specific search terms and domains (e.g. `nfl.com` for the Chiefs only, `:33`)

### `Hawk Nation/News/Views/NewsDetailView.swift`
- `:29-39`: bundled outlet logos keyed on `"Bleacher Report"`, `"ESPN"`, `"NFL News"`. The NFL outlet is sport-specific.

### `Hawk Nation/Roster/Classes/DownloadRosterData.swift`
- `:11-93`: four sport-specific player structs
- `:115-146`: Kansas basketball loader, URL `…/mens-college-basketball/teams/2305/roster` (`:118`)
- `:148-194`: Chiefs loader, `…/nfl/teams/12/roster` (`:154`)
- `:196-234`: Royals loader, `…/mlb/teams/7/roster` (`:201`)
- `:236-296`: Sporting loader, `…/usa.1/teams/186/roster` (`:243`)
- All four duplicate `Team.leaguePath` and `Team.espnTeamId` as literals.

### `Hawk Nation/Roster/Classes/DownloadAthleteData.swift`
- `:219-222`: NFL splits URL. Doc comment says "a Chiefs player" (`:211`).
- `:331-334`: NCAAM splits. Doc comment says "a Kansas player" (`:326`).
- `:366-372`: MLB splits. Doc comment says "a Royals player" (`:361`).
- `:420-426`: MLS athlete URL. This loader is unused (see §1.2).
- `:102-178`: NFL stat catalogue. Sport-specific, not team-specific.

### `Hawk Nation/Roster/Views/PlayerView.swift`
- `:65-68`: four per-sport `PlayerCard` typealiases

### `Hawk Nation/Roster/Views/PlayerDetailView.swift`
- **Hardcoded crests:** `Team.jayhawks.logoImage` (`:32`), `Team.chiefs.logoImage` (`:271`), `Team.royals.logoImage` (`:504`), `Team.sporting.logoImage` (`:822`). The crest is fixed even though three of the four views take `teamColor`.
- **Hardcoded Jayhawks RGB (0,81,186)** instead of `Team.jayhawks.color`: `:25`, `:29`, `:196`, `:199`, `:202`
- **Hardcoded Sporting RGB (0,42,92)** in `UIColor`: `:988`, `:991`, `:1033`, `:1036`
- `:12-18`: `BasketballPlayerDetailView` has no `teamColor` parameter (the others do at `:254`, `:487`, `:805`)
- Per-sport loaders are called at `:245`, `:478`, `:793`

### `Hawk Nation/Roster/Views/StatPercentageView.swift`
- `:86`: the preview uses the Jayhawks RGB

### `Hawk Nation/Schedule/Classes/DownloadScheduleData.swift`
- `:38-41`: documents the per-feed name-field split
- `:54-59`: `America/Chicago`, justified as "the home zone of all four teams"

### `Hawk Nation/Schedule/Classes/DownloadGameData.swift`
- `:189`: `Team.jayhawks.summaryURL` inside `downloadBasketballGameTeamStatsData`. Sport and team are treated as one-to-one.
- `:201`: identifies the followed team by `team.name == "Jayhawks"`, a literal rather than `Team.boxscoreName`
- `:239`: `Team.chiefs.summaryURL`
- `:244`: `team.name == "Chiefs"`
- `:306`: `Team.royals.summaryURL`
- `:343`: `Team.sporting.summaryURL`
- `:166-168`: `team.homeCity` and `team.boxscoreName` decide the accent colour
- `:26-107`: four per-sport box-score structs

### `Hawk Nation/Schedule/Views/GameView.swift`
- `:18`, `:306`: two card types, with `FootballGameView` used only for the Chiefs
- `:35`, `:321`: `team.logoImage`
- `:639-663`: `getPeriod` string-matches `"Kansas"`, `"Kansas City"`, `"Royals"`, `"KC"`. Its callers are `:219`, `:511`, `:531`, `:559`.

### `Hawk Nation/Schedule/Views/GameDetailView.swift`
- **Four per-sport views:** `:11`, `:416`, `:799`, `:1073`
- **Hardcoded followed-team labels:**
  - `Text("Kansas")` at `:142`, `:247`
  - `Text("Chiefs")` at `:547`, `:649`
  - `Text("Royals")` at `:918`, `:1020`
  - `Text("Kansas City")` at `:1193`, `:1295`
- **Crest via `team.logoImage`:** `:137`, `:242`, `:542`, `:644`, `:913`, `:1015`, `:1188`, `:1290`
- **`getPeriod` callers:** `:167`, `:225`, `:567`, `:627`, `:938`, `:998`, `:1213`, `:1273`
- **`Image("soccerField")`:** `:1092`. The asset file is `NashvilleSCrendering.jpg`.
- **Per-sport loaders plus `downloadGameInfo(team:)`:** `:406-407`, `:789-790`, `:1064-1065`, `:1341-1342`

### `myTeamWidget/myTeamWidget.swift`
- `:20-21`: doc comment still says "The three teams"
- `:108-162`: four `Widget` structs, with:
  - kinds `"myTeamsWidget"` / `"myTeamsWidget2"` / `"myTeamsWidget3"` / `"myTeamsWidget4"` (`:111`, `:125`, `:139`, `:153`)
  - `GameTimelineProvider(team: .x)` (`:112`, `:126`, `:140`, `:154`)
  - display names and descriptions (`:116-117`, `:130-131`, `:144-145`, `:158-159`)
- `:165-171`: bundle list
- `:174-177`: preview hardcodes `.jayhawks`

### `myTeamWidget/WidgetScheduleLoader.swift`
- `:36`, `:91`: `team.logo` as the background asset name, which requires a matching widget imageset
- `:59`: `America/Chicago`

### Bundled assets
- **App catalog, team crests:** `Hawk Nation/Resources/Assets.xcassets/{jayhawk,chiefs,royals,sporting}.imageset`, looked up as `Team.logo`
- **App catalog, tab icons:** `{jayhawkTab,chiefsTab,royalsTab,sportingTab}.imageset`. No Swift code references them.
- **App catalog, sport-specific:** `soccerField.imageset`, and `NFL News.imageset` (news outlet)
- **Widget catalog:** `myTeamWidget/Assets.xcassets/{jayhawk,chiefs,royals,sporting}.imageset`, a duplicate set required by `myTeamWidget.swift:94`

### Entitlements and `myTeams.xcodeproj/project.pbxproj`
- **`myTeams.entitlements`** is an empty `<dict/>`; the App Group was removed (comment in the file). It is shared by the app and widget targets (pbxproj `:768`, `:793`, `:819`, `:844`) and has no team coupling.
- **Per-team Home files** appear in pbxproj as build files `:14-18`, file refs `:102-106`, group `:220-224`, and Sources phase `:563-567`.
- **Jayhawks-branded project naming:** source root `"Hawk Nation/"` and `INFOPLIST_FILE = "Hawk Nation/Info.plist"` (`:774`, `:799`); bundle IDs `PolarReailty.Hawk-Nation` (`:781`, `:806`), `…Hawk-Nation.myTeamWidget` (`:830`, `:855`), `…Hawk-NationTests` (`:873`, `:890`).
- **Widget target** shares `Sport.swift` and the schedule parser (`:49-50`, `:603-604`), so a new `Team` case reaches the widget target at compile time. The widget still needs a new struct, a bundle entry and a widget-catalog asset.

### `myTeamsTests/`
- **No test references the `Team` enum** or iterates `allCases`; nothing checks per-case properties or URLs.
- **Fixtures hardcode team strings:**
  - `JSONTests.swift:27-84` ("Kansas", "Jayhawks"), `:190` (ChiefsHome filter comment)
  - `BoxScoreParsingTests.swift:24-90`, `:125`, `:149`, `:171-213` ("Royals", "Kansas City")
  - `ScheduleParsingTests.swift:246` ("Jayhawks")


---

## §3 Data-driven redesign

### 3.1 What the code hard-codes today

- **Team identity is a closed enum.** `enum Team` (`Hawk Nation/Networking/Sport.swift:23-161`) holds everything as 4-way switches: names (`:34-51`), the logo asset name (`:54-57`), brand RGB (`:63-70`), league path (`:94-101`), ESPN id (`:104-111`), home city (`:114-119`), and three name-matching fields (`:123-150`).
- **The four per-team views only differ in configuration.** `ChiefsHome` (`Home Menus/ChiefsHome.swift:11-99`) and `RoyalsHome` (`RoyalsHome.swift:11-64`) differ in:
  - the concrete `TeamModel<Player>` type (`ChiefsHome.swift:12-16`);
  - the card and detail closures;
  - a hand-written position filter menu (`ChiefsHome.swift:26-57`, `RoyalsHome.swift:20-39`);
  - two record rules: `countsAbandonedGamesAsLosses` (`RoyalsHome.swift:42-45`) and `usesDateForNextGame` (`SportingHome.swift:17`).
  
  The section views are already generic (`HomeSections.swift:45`, `:114`, `:183`, `:227`).
- **Teams are matched by name, not id.** The schedule parser picks "our" competitor by comparing names (`DownloadScheduleData.swift:163`). Live scores and game info fall back to `boxscoreName` (`DownloadGameData.swift:140`, `:168`). Box scores compare literal strings (`"Jayhawks"` at `:201`, `"Chiefs"` at `:244`) and build URLs from a fixed team (`:189`, `:239`, `:306`, `:343`). Rosters use hard-coded URLs (`DownloadRosterData.swift:118`, `:154`, `:201`, `:243`). Player detail pins a crest (`PlayerDetailView.swift:32`, `:271`, `:504`, `:822`).
- **The root view mounts every page.** `Home` keeps all four pages mounted and switches between them by opacity (`NavigationBar/TabBar.swift:25-32`). Each page runs its own 60-second polling loop (`TeamModel.swift:129-139`), so every favorite would poll all the time.
- **Presentation assumes Central time.** Display is pinned to `America/Chicago` (`DownloadScheduleData.swift:59`, `myTeamWidget/WidgetScheduleLoader.swift:59`).
- **News is hand-tuned per team.** Each team has its own NewsAPI query (`News/Classes/NewsFeed.swift:23-46`).

### 3.2 Dynamic team registry model

Replace the enum with a value type filled from ESPN's `teams` endpoint (§5). The key change is to **identify teams by ESPN id everywhere**. That makes `scheduleTeamName`, `scheduleNameField` and `boxscoreName` unnecessary: every competitor node carries `team.id`, and the schedule, summary header and box score all expose it.

```swift
struct LeagueID: Hashable, Codable, Sendable { let sport: String; let league: String }  // "football","nfl"
var path: String { "\(sport)/\(league)" }                                               // replaces Team.leaguePath

struct TeamRef: Hashable, Codable, Sendable, Identifiable {
    let league: LeagueID
    let espnID: String                       // replaces espnTeamId
    var id: String { "\(league.path):\(espnID)" }   // stable key for persistence and widgets
    var displayName: String; var shortDisplayName: String; var abbreviation: String
    var location: String                     // replaces homeCity (better: compare venue/team id)
    var colorHex: String; var alternateColorHex: String   // from feed `color`/`alternateColor`
    var logoURL: URL?; var logoDarkURL: URL?
}
```

- A `TeamCatalog` actor holds `[LeagueID: [TeamRef]]`. It is loaded lazily per league and persisted as JSON in the App Group caches directory with a TTL of about 7 days.
- Keep the old enum's raw values (`"jayhawk"`, `"chiefs"`, …) as a one-time migration map to `TeamRef.id`, and seed favorites with those four teams on first launch.
- `downloadGameInfo`'s home-colour logic (`DownloadGameData.swift:165-172`) becomes: find the competitor whose `team.id == ref.espnID` and whose `homeAway == "home"`, and use the feed's `team.color`.
- `downloadLiveGameScore` already keys on `homeAway` (`:136-138`). Drop its name fallback in favour of `team.id`.

### 3.3 League abstraction

What differs by sport is behaviour, not data. Put those differences in one place:

```swift
enum SportKind: String, Codable { case football, basketball, baseball, soccer, hockey, other }

struct LeagueDescriptor: Sendable {
    let id: LeagueID; let kind: SportKind; let displayName: String; let isCollege: Bool
    var rosterShape: RosterShape          // .grouped (NFL/MLB, DownloadRosterData.swift:159,206) | .flat (NCAAM/MLS, :121,:246)
    var recordRule: RecordRule            // folds countingAbandonedAsLosses + pastDatesCountAsPlayed (TeamModel.swift:236-255)
    var catalogQuery: [URLQueryItem]      // e.g. limit=1000 / groups= for college
}
```

- **One generic athlete type.** Collapse the four player structs (`DownloadRosterData.swift:11-93`) into one `Athlete` with the common `RosterPlayer` fields (`TeamModel.swift:13-20`) plus `bio: [LabeledValue]` for height, weight, class, hometown, bats/throws and so on. Only sport-specific stats stay typed, and they load on demand in the detail sheet.
- **Filters come from the data.** Build the roster filter menu from the positions actually in the roster, grouped by the feed's unit `position` where one exists. This removes the literal position lists.
- **Unknown sports degrade gracefully.** They get a generic schedule card, a name/number/position roster and no box score. The app still works for any league ESPN lists.

### 3.4 Generic team views

- **One team view.** `TeamHomeView(team: TeamRef)` composes the existing `RosterSection`, `ScheduleSection` and `NewsSection`. A `SportRenderer` switch on `kind` supplies `card`, `detail` and `gameCard`/`gameDetail`. The existing views take `team: Team` (`Schedule/Views/GameView.swift:22`, `:310`; `GameDetailView.swift:19`, `:424`, `:807`, `:1081`); change them to `TeamRef`. Hockey needs a new card and box score.
- **A non-generic model.** Make `TeamModel` non-generic by using `Athlete`. Then:
  - Keep the models in a `TeamModelStore` keyed by `TeamRef.id`.
  - Mount only the selected page, so N favorites don't mean N pollers.
  - Keep scroll position by storing a per-team `ScrollPosition`, instead of keeping the page alive with opacity.
  - Start and stop polling from `.task(id: selection)`.
  - Prefer one `scoreboard` call per league per minute over per-game `summary` calls (§5).
- **Team picker bar.** The bottom `TeamPicker` lays crests out with `Spacer`s (`TabBar.swift:137-163`), which stops fitting beyond about 5 teams. Make it a horizontal `ScrollView` of crests with a trailing "+" / "Edit" button, and keep the selected-capsule style.
- **Time zones and news.** Replace the Central-time pin with the device's time zone (or the venue's). Replace `NewsFeed` queries with the ESPN team news endpoint (§5).

### 3.5 Favorites persistence

**What needs storing:** an ordered list of 1–30 `TeamRef` ids, a selected index, maybe per-team notification flags, and an optional team-catalog cache. The widget extension must be able to read it.

| | UserDefaults (App Group suite) | SwiftData | Core Data |
|---|---|---|---|
| Fit for "ordered list of ~20 ids" | Exact fit: one Codable array | Overkill: model plus a sort-index column | Overkill |
| Widget / AppIntent access | `UserDefaults(suiteName:)`, synchronous, trivial in `EntityQuery` | `ModelConfiguration(groupContainer:)` works; two processes share one SQLite file (needs care; widget should be read-only) | Same as SwiftData, more boilerplate |
| iCloud sync | Mirror to `NSUbiquitousKeyValueStore` (≈20 lines) | Built-in CloudKit (private DB; schema rules: all optional/defaulted, no unique constraints) | `NSPersistentCloudKitContainer`, mature |
| Migration cost | Codable versioning by hand (trivial at this size) | Schema versioning / `VersionedSchema` | Mapping models |
| Deployment target | Any | iOS 17+ (project is iOS 26: `project.pbxproj:697`) | Any |
| Querying a large cached catalog | Poor (whole-blob load) | Good (`#Predicate`, `@Query`) | Good |

**Recommendation:** use **UserDefaults in an App Group suite** for favorites, behind an `@Observable FavoritesStore` that:
- encodes `[FavoriteTeam]` as JSON (`{ teamID, addedAt, notify }`) in list order;
- mirrors to `NSUbiquitousKeyValueStore` for cross-device sync;
- calls `WidgetCenter.shared.reloadAllTimelines()` on every change.

Store the **team catalog as JSON files** in the shared caches directory rather than in a database. It's a few thousand small rows, rebuilt from the network, and searched in memory. Only adopt SwiftData later, if you add persistent schedule history, offline box scores or per-game notification state. Skip Core Data: on an iOS 26 target it offers nothing SwiftData doesn't, with more code.

### 3.6 Searchable team picker UX

- **Entry points.** Show a first-run onboarding sheet ("Pick your teams", pre-checked with the four legacy teams for existing users), plus the "+"/"Edit" button in the crest bar.
- **Layout.** A `NavigationStack` with a `List` and `.searchable(text:)`. Put a `Picker(.segmented)` or chip row of leagues above it (NFL · NBA · MLB · NHL · MLS · WNBA · NCAAF · NCAAM · NCAAW · EPL…). College lists get sections by conference (the `groups` data from the teams/standings feeds).
- **Rows.** Each row shows the remote crest (§4), display name and league badge, with a checkmark toggle. Selected teams float to a "My Teams" section at the top that supports `.onMove` reordering and swipe-to-remove.
- **Search.** Search locally over the cached catalog, matching `displayName`, `shortDisplayName`, `abbreviation`, `location` and `nickname`, case- and diacritic-insensitive. That's instant and works offline. Load a league's catalog the first time its chip is tapped, or all pro leagues in the background (a handful of requests). Fall back to ESPN's remote search only for queries with no local match (§5).
- **Disambiguation.** "Kansas City" matches the Chiefs, Royals, Sporting KC and Current, and "Kansas" matches the Jayhawks and K-State. Always show the league badge.

### 3.7 App Group and dynamic widget configuration

- **Re-add the App Group.** It was removed (`myTeams.entitlements:4-8`). Add `com.apple.security.application-groups` = `group.PolarReailty.Hawk-Nation` to both targets. Both currently share one entitlements file (`project.pbxproj:768`, `:793`, `:819`, `:844`); give the widget its own file.
- **One configurable widget.** Replace the four `StaticConfiguration` widgets (`myTeamWidget/myTeamWidget.swift:108-171`) with one `AppIntentConfiguration`:
  - `TeamEntity: AppEntity` (id = `TeamRef.id`) with an `EntityQuery` whose `suggestedEntities()` reads favorites from the shared defaults, plus `EntityStringQuery` over the cached catalog.
  - `SelectTeamIntent: WidgetConfigurationIntent` with `@Parameter var team: TeamEntity?`. When it's nil, show the first favorite.
- **Existing placed widgets.** Keep the kind `"myTeamsWidget"` (`myTeamWidget.swift:111`) for the new configurable widget so current Jayhawks placements survive. Removing kinds `"myTeamsWidget2"` to `"myTeamsWidget4"` deletes those placed widgets. Either keep them as thin legacy wrappers for one release, or accept the loss and note it in release notes.
- **Widget data.** `GameTimelineProvider` (`myTeamWidget.swift:22-53`) takes a `TeamRef` from the intent. The background crest (`myTeamWidget.swift:94`, `WidgetScheduleLoader.swift:36`, `:91`) is read from the shared logo cache (§4), not the asset catalog. `teamColor` comes from `TeamRef.colorHex`. Opponent logo fetching stays in the timeline (`WidgetScheduleLoader.swift:20-25`, `:96`) but goes through the shared logo store.
- **Accessory widgets.** Consider `.accessoryRectangular`/`.accessoryCircular` families for the Lock Screen now that configuration is dynamic.

---

## §4 Asset strategy for arbitrary teams

### 4.1 Current state

- **Bundled crests.** Four PNG crests are bundled twice: in `Hawk Nation/Resources/Assets.xcassets` (`chiefs`, `jayhawk`, `royals`, `sporting`, plus `*Tab` variants) and again in `myTeamWidget/Assets.xcassets`. `Team.logo` is the asset name (`Sport.swift:21-22`, `:54-57`). Crests are drawn with `Image(team.logo)` (`TabBar.swift:65`, `:143`) and `team.logoImage` (`TabBar.swift:178`, `GameView.swift:35`, `:321`, `GameDetailView.swift:137`, …).
- **Unused assets.** The `*Tab` imagesets have no references in Swift. The news-source images are looked up by source name (`NewsDetailView.swift:29-39`).
- **Remote images already work.** Opponent logos and headshots are remote via `RemoteImage` (`GameView.swift:58`, `:109`). It's backed by an in-memory `NSCache` (400 items) and a private `URLCache` (16 MB memory / 128 MB disk) with `.returnCacheDataElseLoad` (`Networking/RemoteImage.swift:21-38`), and it coalesces in-flight requests (`:40-77`).
- **Placeholders.** Grey rectangles (`RemoteImage.swift:82-87`) or the `blankTeam` / `blank` assets (`GameView.swift:54`, `PlayerView.swift:23`).
- **Fragile logo pick.** The schedule parser picks the last logo whose href doesn't contain "dark" (`DownloadScheduleData.swift:171-178`).
- **The widget has no cache.** It downloads opponent logos through `URLSession.shared` on every timeline (`WidgetScheduleLoader.swift:101-104`), sharing nothing with the app.

### 4.2 ESPN remote team logos

- **Source.** Take the `team.logos[]` array from the teams / team-detail / schedule feeds. Each entry has `href`, `width`, `height` and `rel` (e.g. `["full","default"]`, `["full","dark"]`, `["full","scoreboard"]`). Select by `rel` instead of URL substrings.
  - Store `logoURL` (default) and `logoDarkURL` on `TeamRef`.
  - Typical hrefs: `https://a.espncdn.com/i/teamlogos/{nfl|mlb|nba|nhl}/500/{abbr}.png`, `…/ncaa/500/{id}.png`, `…/soccer/500/{id}.png`. Read them from the feed rather than constructing them; the patterns aren't a contract.
- **Right-sizing.** Request sized crests through ESPN's combiner, which the code already uses for the no-photo headshot (`DownloadRosterData.swift:96`): `https://a.espncdn.com/combiner/i?img=/i/teamlogos/nfl/500/kc.png&w=120&h=120`. This matters most for the widget, which has a small memory budget, and the 25-point crest bar (`TabBar.swift:144-145`).
- **Variants.** Use the dark variant when `colorScheme == .dark` and when the crest sits on a background close to its own colour. The page header draws the crest at 50% opacity over `team.color` (`TabBar.swift:58-67`), and some crests disappear there. Compute the contrast of `colorHex` vs `alternateColorHex` and pick the background accordingly.

### 4.3 On-disk caching

Use two tiers:

1. **General imagery** (headshots, news art, opponent crests in carousels): keep `ImageCache` as is. Optionally add image downsampling with ImageIO (`CGImageSourceCreateThumbnailAtIndex`) before caching, so decoded memory tracks display size.
2. **`LogoStore` for catalog and favorite crests** (new):
   - Persistent files in the App Group container, e.g. `Library/Application Support/Logos/{sport}.{league}.{espnID}.{default|dark}.png`. Use Application Support for favorites so the OS can't purge crests the widget needs, and `Library/Caches` for non-favorite catalog crests.
   - Write downscaled PNGs (e.g. 256 px max) at insert time.
   - Prefetch on favorite-add and when a league's catalog loads (visible rows only).
   - Revalidate at most weekly with a conditional GET (`If-None-Match` / `If-Modified-Since`); logos change only on rebrands.
   - Expose a synchronous `func image(for: TeamRef, variant:) -> UIImage?` so widget views never need the network.
   - The widget timeline also writes opponent crests there, so the hourly timeline stops re-downloading them (`WidgetScheduleLoader.swift:101-104`).

A single SwiftUI entry point, `TeamLogo(team:size:)`, resolves in this order: `LogoStore` file → `RemoteImage` of the sized URL → bundled legacy asset (for the four migrated ids only) → generated monogram.

### 4.4 Placeholder fallbacks

- **Monogram badge instead of grey boxes.** A circle filled with `TeamRef.colorHex` (or a hash-derived colour if absent), `abbreviation` in `alternateColorHex` or white chosen by contrast, and an optional SF Symbol for the sport (`football.fill`, `basketball.fill`, `baseball.fill`, `soccerball`, `hockey.puck.fill`). It's deterministic, needs no assets, looks intentional offline, and works for teams ESPN has no logo for (common in lower college divisions and some soccer leagues).
- **Keep generic assets until the monogram covers them.** Keep `blank` / `blankTeam` until then, and keep the neutral non-team assets (`soccerField`, `GameDetailView.swift:1092`; `AppIcon`; `LaunchscreenColor`).
- **Loading vs failure.** Distinguish the two. Show a shimmer or `ProgressView` while loading, which `RemoteImage` already does (`RemoteImage.swift:123-129`), and switch to the monogram on failure or 404 instead of leaving a grey box.

### 4.5 Migration path away from bundled imagesets

1. **Additive (no visual change).** Add `logoURL` / `logoDarkURL` to `TeamRef`, add `LogoStore` and `TeamLogo`, and route every `Image(team.logo)` / `team.logoImage` call site through `TeamLogo`. The bundled fallback keeps the four legacy teams identical.
2. **Seed.** On first launch after the update, copy the four bundled PNGs into `LogoStore` under their new `TeamRef.id` keys. Offline first run then still shows crests, and the widget reads them from the shared container.
3. **Widget catalog first.** Delete `chiefs`, `jayhawk`, `royals` and `sporting` from `myTeamWidget/Assets.xcassets`; the widget now reads `LogoStore`. Remove the unused `*Tab` imagesets from the app catalog.
4. **App catalog.** After one release with the seed step, delete the four crest imagesets from the app catalog. Replace the per-source news logos (`NewsDetailView.swift:29-39`) with the source name, or with the favicon/`images` the ESPN news feed returns.
5. **Legal note.** Team marks are trademarks. Hot-linking ESPN's CDN carries the same unlicensed-use exposure as the API (§5). Bundling hundreds of third-party marks would be worse, since you'd be distributing them. A licensed provider (§5) is how you get image rights.

---

## §5 API strategy

### 5.1 ESPN endpoints used today (exact patterns)

| # | Pattern | Where |
|---|---|---|
| 1 | `https://site.api.espn.com/apis/site/v2/sports/{leaguePath}/teams/{espnTeamId}/schedule` (no `season` or `seasontype` params) | built at `Networking/Sport.swift:154-156`; used by `TeamModel.swift:176-182` and `WidgetScheduleLoader.swift:71-75` |
| 2 | `https://site.api.espn.com/apis/site/v2/sports/{leaguePath}/summary?event={gameID}` | built at `Sport.swift:158-160`; live score `DownloadGameData.swift:130`, game info `:160`, box scores `:189` (NCAAM), `:239` (NFL), `:306` (MLB), `:343` (MLS) |
| 3 | `https://site.api.espn.com/apis/site/v2/sports/{leaguePath}/teams/{id}/roster`, hard-coded per team | `DownloadRosterData.swift:118` (…/mens-college-basketball/teams/2305), `:154` (…/nfl/teams/12), `:201` (…/mlb/teams/7), `:243` (…/soccer/usa.1/teams/186) |
| 4 | `https://site.web.api.espn.com/apis/common/v3/sports/{leaguePath}/athletes/{id}/splits` | `DownloadAthleteData.swift:221` (NFL), `:333` (NCAAM), `:371` (MLB) |
| 5 | `https://site.web.api.espn.com/apis/common/v3/sports/soccer/usa.1/athletes/{id}` (athlete overview, `statsSummary`) | `DownloadAthleteData.swift:425` |
| 6 | CDN: `https://a.espncdn.com/combiner/i?img=/i/headshots/nophoto.png`, plus logo and headshot hrefs taken from feeds | `DownloadRosterData.swift:96`, `:103-106`; `DownloadScheduleData.swift:173-177` |

The league paths in use are `basketball/mens-college-basketball`, `football/nfl`, `baseball/mlb` and `soccer/usa.1` (`Sport.swift:94-101`).

The one non-ESPN source is NewsAPI: `https://newsapi.org/v2/everything?{query}&sortBy=publishedAt&apiKey=…` (`NewsFeed.swift:19-21`).

All requests go through `HTTPClient`: a 20-second timeout, protocol cache policy, and any non-2xx or failure returned as `JSON.null` (`HTTPClient.swift:22-48`).

### 5.2 What ESPN's public site API offers for arbitrary teams and leagues

These endpoints are undocumented but widely used. Shapes are as observed; treat them as unstable. `{s}/{l}` means `{sport}/{league}`, e.g. `hockey/nhl`, `basketball/nba`, `basketball/wnba`, `football/college-football`, `basketball/womens-college-basketball`, `soccer/eng.1`, `soccer/usa.nwsl`.

- **Team list (catalog).** `GET https://site.api.espn.com/apis/site/v2/sports/{s}/{l}/teams`
  - Returns `sports[0].leagues[0].teams[].team` with `id`, `uid`, `slug`, `abbreviation`, `displayName`, `shortDisplayName`, `name`, `nickname`, `location`, `color`, `alternateColor`, `logos[]`, `links[]`. That's everything `TeamRef` needs in one call per league.
  - College lists are truncated by default: pass a large `limit` (e.g. `?limit=1000`), and `groups=` to pick the division or conference.
- **Team detail.** `…/{s}/{l}/teams/{id}` adds `record`, `standingSummary` and `nextEvent`. That's enough for a picker preview or a widget without fetching the full schedule.
- **Schedule / roster / summary.** Same patterns as §5.1 #1–#3, for any league above.
  - For schedules, pass `season=` and `seasontype=` (1 = pre, 2 = regular, 3 = post) explicitly. The default follows the current season phase, which surprises you around the preseason and postseason boundaries.
- **Scoreboard.** `…/{s}/{l}/scoreboard?dates=YYYYMMDD` (or a range `YYYYMMDD-YYYYMMDD`); college adds `groups=` (e.g. D-I). One call returns every game in the league that day, with scores, clock and status.
  - This should replace per-game `summary` polling for cards (`TeamModel.swift:146-174`): one request per league per minute covers all favorites in that league.
  - Keep `summary` for the detail sheets.
- **Standings.** `https://site.api.espn.com/apis/v2/sports/{s}/{l}/standings`. Note there's no `/site/` in the path; the `/apis/site/v2/…/standings` variant returns only a stub. It takes `season=` and `level=` / `group=` for conference and division breakdowns.
- **News.** `…/apis/site/v2/sports/{s}/{l}/news?team={id}&limit=N`. This replaces the per-team NewsAPI queries (`NewsFeed.swift:23-46`), removes the extractable `NEWS_API_KEY` (`NewsFeed.swift:13-17`), and works for any team automatically.
- **Core API (HATEOAS).** `https://sports.core.api.espn.com/v2/sports/{s}/leagues/{l}/teams?limit=1000`, `…/seasons/{yyyy}/types/{t}/teams/{id}/record`, `…/athletes/{id}/statistics`, `…/events/{id}/competitions/{id}/…`, and `…/v2/sports/{s}/leagues` for league discovery.
  - The data is richer and has stable `$ref` ids, but every item is a separate `$ref` fetch, so fan-out is expensive.
  - Use it offline or at catalog-build time, not per screen.
- **Athlete data.** `https://site.web.api.espn.com/apis/common/v3/sports/{s}/{l}/athletes/{id}`, plus `/splits`, `/gamelog` and `/stats`. The same family the app already uses (#4, #5), available per league.
- **Search.** `https://site.web.api.espn.com/apis/common/v3/search?query={q}&type=team&limit=10` (an older variant is `https://site.api.espn.com/apis/search/v2?query={q}`). The response shape is the least stable of all these endpoints. Use it only as a fallback after local catalog search (§3.6).

### 5.3 Known gaps and risks

- **Schema drift.** The code already documents shape changes ("Shape pin (M6)": `DownloadRosterData.swift:160-165`, `:257-261`; `DownloadScheduleData.swift:132-137`). Much of the parsing indexes stats by array position:
  - `DownloadGameData.swift:211-223`, `:253-260`
  - `DownloadAthleteData.swift:378-410`, `:437-440`
  - `DownloadRosterData.swift:249-289`
  
  Before adding leagues, switch to name-keyed lookups like the existing `boxscoreStatistic` (`DownloadGameData.swift:273-286`). Extend the recorded-fixture tests (`myTeamsTests/BoxScoreParsingTests.swift`, `ScheduleParsingTests.swift`) with one fixture per league per endpoint.
- **Deep stats.**
  - Splits and gamelogs differ in shape per sport.
  - No advanced metrics: no Statcast, xG, tracking or play-by-play-derived rates beyond what `summary` embeds.
  - Soccer player stats are thin; the app already shows only goalkeeper numbers (`DownloadAthleteData.swift:416-419`).
  - Historical seasons are patchy.
- **NBA / NHL / college coverage.**
  - NBA, NHL and WNBA have full site-API coverage (teams, schedule, roster, summary, scoreboard, standings). The work there is renderers, especially the hockey box score, not data.
  - College football and men's/women's basketball are well covered for major programs. Smaller D-I and non-D-I programs often lack headshots, player stats or box-score detail.
  - Other college sports are sparse.
  - Soccer: coverage varies by competition id.
- **Rate limits.** Undocumented. The code already tolerates throttling by keeping the last known score (`TeamModel.swift:144-145`, `DownloadGameData.swift:126-128`). With N favorites, today's model (all pages mounted, per-game summaries every minute) multiplies requests by N. To mitigate:
  - poll only the visible team;
  - use one scoreboard call per league instead of per-game summaries;
  - add exponential backoff on 403/429/5xx;
  - honour cache headers, which the session already does (`HTTPClient.swift:24`).
  - At scale, put a small caching proxy in front so ESPN sees one client, not every install.
- **Terms of service.** ESPN shut down its public developer API program in 2014. These site/core endpoints are unlicensed for third-party apps, and ESPN's terms restrict automated and commercial use of its content. For a personal or TestFlight app the practical risk is breakage. For a public or monetized App Store app, the risks are:
  - takedown or App Review rejection under guideline 5.2 (IP), aggravated by using team marks (§4.5);
  - sudden unannounced schema or access changes, with no recourse.
- **NewsAPI.** The free Developer plan is for development only; production use needs a paid plan. The key ships inside the app bundle.

### 5.4 When to add a licensed provider, and what it buys

**Triggers:**
- a public or monetized App Store release;
- push notifications for scores (which need a server polling a reliable feed anyway);
- deep or advanced stats;
- an ESPN breakage costing more than about a day of fixes per season;
- enough users that you need a backend cache regardless.

Put a `SportsDataProvider` protocol in front of all of this (`teams(league:)`, `schedule(team:season:)`, `roster(team:)`, `scoreboard(league:date:)`, `summary(event:)`, `news(team:)`) returning app-domain models. Ship `ESPNProvider` first, add a per-provider id-mapping table to the catalog (ESPN id ↔ SportsData id ↔ MLB `teamId`), and route by league. Licensed keys can't ship in the app binary, so adding one effectively means adding a thin backend proxy.

| Provider | What it buys | Cost / caveats |
|---|---|---|
| **MLB Stats API** (`https://statsapi.mlb.com/api/v1/…`; live game feed `…/api/v1.1/game/{gamePk}/feed/live`; schedule `…/api/v1/schedule?sportId=1&teamId=…`) | The deepest free baseball data: pitch-by-pitch, Statcast fields, full box scores, transactions, minor leagues. A strong upgrade for the Royals/MLB detail views. | No key and no SLA. MLB's copyright notice limits use to individual, non-commercial purposes, so it improves depth, **not** licensing. MLB only. (NHL has an analogous unofficial `api-web.nhle.com`.) |
| **SportsData.io** | Licensed, documented, versioned feeds for NFL, NBA, MLB, NHL, NCAA football/basketball, WNBA and soccer. Stable ids, injuries, depth charts, projections, odds, a real-time tier and an SLA. Image and headshot licensing is available as an add-on. | Paid per league and tier; production pricing is by quote and can run from hundreds to thousands of dollars per month. The free trial serves scrambled data. |
| **RapidAPI marketplace** (e.g. API-Sports: API-Football, -Basketball, -Hockey, -American-Football, -Baseball) | Cheap tiered keys and very broad global soccer coverage (hundreds of leagues). Fixtures, lineups, events, standings and player stats through one billing account. | Data quality and latency vary by API. Free tiers are around 100 requests/day, per key, so a proxy is mandatory. Check each API's redistribution and image terms separately. |

**Recommended sequencing:**
1. Stay on ESPN while building the data-driven app (§3), with a provider abstraction, name-keyed parsing, scoreboard batching and ESPN news in place of NewsAPI.
2. If MLB depth matters for personal use, add the MLB Stats API behind the same protocol.
3. Before any public or monetized release, move core leagues to a licensed feed (SportsData.io for US leagues, API-Sports for global soccer) behind a small caching backend. Keep ESPN only as a non-critical fallback, or drop it.


---

## §6 Phased roadmap: from 4 hard-coded teams to an any-team sports app

Durations are for one developer working full time. Part-time (evenings and weekends), multiply by about 2–2.5×. The whole plan comes to roughly **22–35 weeks** full time. Across every phase, the biggest risk is that everything depends on ESPN's site API, which is unofficial, undocumented and has no SLA. Put a `ScoresProvider` boundary in during Phase 1 so a licensed feed (Sportradar, SportsDataIO, API-Sports) could replace it later.

### Phase 0 (recommended first, about 1 week): fix the P0 bugs in §7
Do these before refactoring, so the fixture tests in Phase 1 lock in correct behaviour instead of today's bugs:
- live score reads 0–0 (#1)
- detail sheet is a frozen snapshot (#2)
- white-on-white text (#3)
- endless skeletons (#4)
- draws counted as losses (#5)

### Phase 1: data-driven team model, no new features, same 4 teams (4–6 weeks)
- **Team identity:** replace the `switch`-per-property `enum Team` (`Sport.swift:23-161`) with a `TeamDescriptor` value (league, ESPN id, abbreviation, names, colours, logo URL) plus a `League` descriptor (sport path, period naming, whether draws exist, record format).
  - Match the followed team by **ESPN team id**, not by name. That removes `scheduleTeamName`, `scheduleNameField`, `boxscoreName` and `homeCity` (`Sport.swift:121-150`, `DownloadScheduleData.swift:163`, `DownloadGameData.swift:140,166-168,201,244`).
- **Sport adapters:** add a `SportAdapter` protocol covering roster parsing, box-score lines as `[(label, home, away)]`, period formatting and player stat groups.
  - Collapse the four `*Home` views into one `TeamHomeView(team:)`.
  - Collapse the four `*GameDetailView`s (`GameDetailView.swift:11/416/799/1073`) into one view that renders adapter rows.
  - Collapse `GameView` and `FootballGameView` into one view, and the four player detail views into one.
  - Replace `getPeriod` (`GameView.swift:639-663`) with `League.periodName(_:)`.
- **Networking:** make `HTTPClient` throw typed errors (offline, HTTP status, decode) and make it injectable through a protocol. Add a `Loadable<T>` state (idle, loading, loaded, empty, failed) for every section.
  - Read stats by **name**, as the MLB/MLS readers already do, instead of by array index.
- **Tests first:** before touching the parsers, capture real ESPN fixtures for each sport (schedule, summary before/during/after a game, athlete splits, roster) and write golden tests against them.
- **Key risk:** today the per-sport quirks are special cases scattered across the code. Examples: MLS completion flags that lag (`TeamModel.swift:71-75`), NCAAM scored by halves, MLB's grouped stats, and the Royals "cancelled counts as a loss" rule (`RoyalsHome.swift:42-45`). A unifying refactor can silently drop one of them. The fixture tests are the mitigation, which is why they come first.

### Phase 2: favorites, team picker, follow any ESPN team (3–5 weeks)
- **Team catalogue:** load it from `/sports/{sport}/{league}/teams`, with search. Colours come from the feed's `color`/`alternateColor`, with a contrast check. Crests become remote images instead of the four bundled assets.
- **Favorites:** store them in an **App Group** container (SwiftData or `UserDefaults(suiteName:)`) so the widget can read them in Phase 4.
- **Navigation:** replace the fixed four-crest `HStack` picker (`TabBar.swift:133-170`) with a scrolling picker plus "Manage teams", or a `TabView` with sidebar on iPad.
  - Stop keeping every page mounted (`TabBar.swift:22-32`). With N favorites that means N schedule polls a minute plus live polling for teams nobody is looking at.
  - Instead, poll one **league scoreboard** per league and fan the results out to favorites.
- **News:** drop the hand-written NewsAPI query per team (`NewsFeed.swift:23-46`) and use ESPN's `/news?team={id}`. This also removes the API-key problem (§7 #9).
- **Key risk:** request volume and rate limiting from the unofficial API as the number of teams grows. Using team logos and trademarks for arbitrary teams is also an App Review and legal exposure that four local teams didn't really trigger.

### Phase 3: more leagues, standings, stats leaders, roster parity (6–10 weeks)
- **Leagues:** NBA, WNBA, NHL, NCAAF, NCAAW, and major soccer leagues (EPL, La Liga, Liga MX, NWSL) plus cups. Leave out non-team sports (golf, F1, tennis).
- **Standings:** these use a different base path (`/apis/v2/sports/.../standings`) and are shaped differently: conference/division groups, soccer points tables, college rankings.
- **Stats leaders:** at team and league level.
- **Roster/athlete parity:** give every sport a stats screen. Today soccer shows "N/A" for everyone except keepers (`DownloadAthleteData.swift:428-432`).
- **Record model:** move to W-L-T and W-D-L-Pts. Hockey needs OT/SO handling. Soccer teams play in several competitions, which breaks the "one competition per event" assumption (`DownloadScheduleData.swift:131-137`).
- **Key risk:** the number of sport × league quirks, and schema drift between ESPN's `site`, `site.web` and `core` APIs. Anything still read by position breaks silently: it returns 0, never an error, because of the lenient `JSON` accessors (`JSON.swift:160-168`).

### Phase 4: push score alerts, per-favorite widgets, iCloud sync (8–12 weeks, mostly backend)
- **Push alerts need a server.** iOS background refresh is opportunistic and can't deliver score changes within a minute.
  - The backend is a small service: a poller that watches live-window scoreboards every 15–30 s, a diff engine (start, score change, period end, final), a device-token and subscription registry, and an APNs sender.
  - Add **Live Activities** with push updates for games in progress.
- **Widgets:** replace the four `StaticConfiguration` widgets (`myTeamWidget.swift:108-162`) with one `AppIntentConfiguration` backed by a `TeamEntity` query over favorites. Add Lock Screen accessory widgets, and schedule a timeline reload at kickoff.
- **iCloud sync:** `NSUbiquitousKeyValueStore` is enough for a favorites list. Use SwiftData+CloudKit only if you sync more than that.
- **Key risk:** running a 24/7 poller. Hosting costs money; the ESPN rate-limit or ban risk is **much higher from one server IP than from spread-out clients**; redistributing ESPN data from your own server is a clearer terms-of-service problem; and users will expect alerts as fast as the ESPN app's. This is the phase where moving to a licensed feed becomes hard to avoid.

---

## §7 Bugs and weaknesses found in the code

Severity: **P0** means the user sees wrong data or a broken screen; **P1** means a correctness or robustness defect; **P2** means maintainability or hygiene.

### P0: wrong data or broken UI

| # | Issue | Evidence |
|---|---|---|
| 1 | **Every live score reads 0–0.** The code reads `score.displayValue` from summary `header` competitors. There, `score` is a plain string (`"24"`), so the lookup hits `.null` and `.intValue` gives 0. The `Int?` variables therefore always get a value, the `guard … else { return nil }` never fires, and the "keep last known score" logic never runs. The code's own fixtures and the sibling readers confirm the flat shape. The FootballGameView arrow logic then always takes the "tied" branch. | `DownloadGameData.swift:144,146,150`. Shape confirmed by `BoxScoreParsingTests.swift:32-35,82-85` and by the readers at `DownloadGameData.swift:245,321`. Effect: `TeamModel.swift:169-173`, `GameView.swift:233,496-571` |
| 2 | **The game-detail clock and status freeze.** Each detail view gets a snapshot `game` when the card is tapped, and the period, clock, "Final" and halftime text all come from that snapshot. The 10-second refresh only updates stats and venue info. The live clock it does fetch (`gameClock` in the basketball and football stat structs) is never shown. The sheet can't re-find its game in the refreshed schedule either, because `Game.id = UUID()` is regenerated on every parse. | Snapshot: `GameDetailView.swift:15,420,803,1077`, from `HomeSections.swift:124,158,178`. Frozen text: `GameDetailView.swift:155-175,218-235,560-577,620-637,931-948,991-1008,1206-1223,1266-1283`. Unused clock: `DownloadGameData.swift:192,242`. UUID: `DownloadScheduleData.swift:12` |
| 3 | **Baseball and soccer detail sheets draw "Final", the period and the clock in white on a white card** in light mode. | `.foregroundStyle(Color.white)` at `GameDetailView.swift:936,942,948,996,1002,1008,1211,1217,1223,1271,1277,1283`, on the `.systemBackground` card at `889-891` and `1164-1166` |
| 4 | **Loading skeletons can run forever.** `HTTPClient` sets `waitsForConnectivity = true` but keeps the default `timeoutIntervalForResource` of 7 days, so offline requests just wait. Every section shows skeletons whenever its data is empty, so failure, offseason and loading all look the same. `apply(schedule:)` throws away empty results, and roster and news are fetched once with no retry. The header comment says this is intentional. The README says a missing news key leaves news "empty", but it actually shows 5 skeletons forever. | `HTTPClient.swift:15-18,26`. `HomeSections.swift:82,148,197`. `TeamModel.swift:108-122,187`. `README.md:31-32` |
| 5 | **Draws and ties are counted as losses.** Any finished game without `winner` goes in the losses column, and the card says "Loss". MLS draws happen often, and NFL ties occasionally. A unit test locks this behaviour in. | `TeamModel.swift:250`. `GameView.swift:153-166,439-452`. `ScheduleParsingTests.swift:93-99` |
| 6 | **Basketball totals drop overtime.** The score is `linescores[0] + linescores[1]` only. | `DownloadGameData.swift:196-199` |
| 7 | **Baseball ERA is stored as `Int`**, so 3.45 shows as "3". | `DownloadAthleteData.swift:279,378`, shown at `PlayerDetailView.swift:701` |
| 8 | **Basketball season averages are the plain mean of the home and away splits**, not weighted by games played. A player with only one split gets every rate halved. | `DownloadAthleteData.swift:339-357` |

### P1: error handling, parsing robustness, API keys

| # | Issue | Evidence |
|---|---|---|
| 9 | **The news API key is shipped in the app and probably resolves to empty.** `NEWS_API_KEY = "$(NEWS_API_KEY)"` refers to itself at target level, and no `.xcconfig` is attached (the pbxproj has no `baseConfigurationReference`). So the README's "an .xcconfig that is not checked in" does nothing unless it is attached as a base config or passed to `xcodebuild`. When the key *is* set, it is copied in plain text into `Info.plist` (readable from the IPA) and sent in the query string. NewsAPI's free plan also forbids production use. | `project.pbxproj:780,805`. `Info.plist:23-24`. `NewsFeed.swift:15-21`. `README.md:23-29` |
| 10 | **`HTTPClient` turns every failure into `JSON.null`.** Offline, 404, 429, 5xx and bad JSON all become "no events". Callers can't tell error from empty. The football stats tab shows "No season statistics…" after a network error, and the detail sheets replace good stats with `[]` on one failed poll, so the view flickers to "No game statistics". | `HTTPClient.swift:31-48`. `JSON.swift:65-72`. `DownloadAthleteData.swift:226-228` with `PlayerDetailView.swift:455`. `GameDetailView.swift:409,792,1067,1344` |
| 11 | **Stats are read by array position**, so any change to ESPN's ordering silently shows wrong numbers as 0s. | `DownloadGameData.swift:211-223,253-260`. `DownloadAthleteData.swift:340-357,378-410,437-440` |
| 12 | **`getPeriod` is incomplete and keyed on team-name strings.** It returns "" for every MLB inning, every OT period and soccer extra time. Royals and Sporting cards reuse the basketball `GameView`, so a live Royals card shows a blank period and ESPN's clock string. | `GameView.swift:639-663`. `RoyalsHome.swift:46`, `SportingHome.swift:49` |
| 13 | **Game status comes from exact `detail` strings** (`"Postponed"`, `"Canceled"`, `"Halftime"`) instead of `status.type.name`. Suspended and delayed games aren't handled. | `DownloadScheduleData.swift:149,153-155` |
| 14 | **A date that fails to parse becomes `Date()` ("now").** That puts the game in the live-poll window and renders it as in progress. The parser format also rejects timestamps that include seconds. | `DownloadScheduleData.swift:80,117,141-145`. `TeamModel.swift:278`. `GameView.swift:170` |
| 15 | **The followed team is matched by name string.** If the name doesn't match, both competitors go down the "opponent" branch, giving an empty score and `gameHome = false`. | `DownloadScheduleData.swift:163-169` |
| 16 | **Detail-sheet state mismatches:** only the home branch has "Halftime". Baseball and soccer have no "postponed" message (and no loading skeleton). Team labels are hard-coded ("Kansas", "Chiefs", "Royals", "Kansas City") instead of `team.shortName`. | `GameDetailView.swift:161` vs `218-236`. `894,1169`. `142,247,547,649,918,1020,1193,1295` |
| 17 | **Wasted requests:** each detail tick fetches the same summary URL twice (stats and info), every 10 s, even for finished or future games. All four team pages stay mounted and keep polling while hidden. The `Game.id` UUID churn rebuilds every schedule card each minute. | `GameDetailView.swift:405-412` (and 788, 1063, 1340). `TabBar.swift:22-32`. `DownloadScheduleData.swift:12` with `HomeSections.swift:154` |
| 18 | **`NewsDetailView` covers the top 60 pt of `SFSafariViewController`**, which Apple says must not be hidden or obscured. `SFSafariViewController` also throws on URLs that aren't http(s), and article URLs are not checked. | `NewsDetailView.swift:19-24,63`. `DownloadNewsData.swift:39` |
| 19 | **Royals record counts cancelled and postponed games as losses.** The code keeps this on purpose, but it's wrong for MLB. | `RoyalsHome.swift:42-45`. `TeamModel.swift:245-249` |

### Widget

| # | Issue | Evidence |
|---|---|---|
| 20 | **`getSnapshot` always returns the placeholder**, so the gallery and transient snapshots never show a real fixture (it doesn't check `context.isPreview`). | `myTeamWidget.swift:36-38` |
| 21 | **A failed fetch looks like "season over":** "N/A" is shown for a full hour. The extension also inherits the offline wait from `waitsForConnectivity`, so `getTimeline` can outlive the extension's time budget, and `completion` is never called. Nothing reloads the timeline at kickoff. | `myTeamWidget.swift:41-51`. `WidgetScheduleLoader.swift:85-88`. `HTTPClient.swift:26` |
| 22 | **Four copy-pasted `StaticConfiguration` widgets**, and no way to configure which team a widget shows. | `myTeamWidget.swift:108-162` |

### P2: deprecated APIs, duplication, hygiene

| # | Issue | Evidence |
|---|---|---|
| 23 | **`.animation(_:)` without `value:` is deprecated** (since iOS 15). The legacy `ScrollView(.vertical, showsIndicators:)` also sits alongside the modern `.scrollIndicators(.hidden)` used elsewhere. | `PlayerDetailView.swift:197,200,203,989,992,1034,1037`. `GameDetailView.swift:25,430,811,1085` vs `HomeSections.swift:104` |
| 24 | **Duplicated view bodies.** There are four near-identical game detail views (about 1,350 lines), each with mirrored home/away branches and two identical copies of the loading skeleton. `GameView` and `FootballGameView` are about 95% the same. There are four player detail views. | `GameDetailView.swift:11-414 / 416-797 / 799-1071 / 1073-1348`, skeletons `310-399` = `695-784`. `GameView.swift:18-304` vs `306-637`. `PlayerDetailView.swift:12,250,483,801` |
| 25 | **Leftover Xcode placeholder tokens and hard-coded values:** 34 `/*@START_MENU_TOKEN@*/` placeholders in `GameDetailView` alone; Jayhawks RGB hard-coded instead of `Team.color`; the `teamColor` parameter is never used by the detail views. | e.g. `GameDetailView.swift:146`, `StatRowView.swift:24`. `PlayerDetailView.swift:25,29,196`. `GameDetailView.swift:16,421` |
| 26 | **The README is out of date.** It says "three widgets" and describes three team enums that were merged into one. | `README.md:44,51-67` vs `Sport.swift:12-19` and `myTeamWidget.swift:164-171` |

### Testing gaps

| # | Gap | Evidence |
|---|---|---|
| 27 | **Live-score parsing has no test and can't be tested as written.** The parsing is inline in an async network function, which is exactly why bug #1 went unnoticed. | `DownloadGameData.swift:129-152` |
| 28 | **The schedule parser is `private` and never exercised.** The "two-competition" test re-implements the loop instead of calling `parseGame`, so it proves nothing about the real parser. | `DownloadScheduleData.swift:106`. `JSONTests.swift:199-232` |
| 29 | **Untested:** basketball and football box scores (including the OT bug), `downloadGameInfo` colour logic, all athlete-stat loaders (ERA and averaging bugs), news parsing, `WidgetScheduleLoader`, and `getPeriod`. | `DownloadGameData.swift:159-266`. `DownloadAthleteData.swift:219-442`. `WidgetScheduleLoader.swift:70-104` |
| 30 | **`HTTPClient` can't be substituted in tests:** it's a static enum with a private session, so there are no offline or error-path tests. There is one UI smoke test, and no snapshot tests (bug #3 would have been caught by one). | `HTTPClient.swift:19-28`. `myTeamsUITests.swift:17-27` |
 connectors need authorization in your claude.ai connector settings before they can be used. This analysis didn't need either of them.

