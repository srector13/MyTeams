# Team search: duplicate-club audit (t_adc80524)

Read-only audit. No app code was changed. Line numbers are against `8dfffd6`
(after BE-3 merged).

**Summary.** Searching "Bayern" shows **two rows**: `Bayern Munich [Bundesliga]`
and `Bayern Munich [UCL]`. ESPN does not return Bayern twice in any one
response. The client builds the second row itself, because it searches the
union of every browsable league's `/teams` catalog, and BE-3 made
`uefa.champions` one of those leagues. The two rows have different identities
(`soccer/ger.1:132` and `soccer/uefa.champions:132`), so following one or the
other saves **different favorites with different behaviour**. Following from
the Bundesliga row gives the full schedule (league plus cups). Following from
the UCL row gives only Champions League games.

There is no server code in this repo. Search runs entirely in the Swift client
(app and widget) against ESPN.

---

## 1. Relevant files

| Concern | Location |
|---|---|
| Picker / search screen | `Hawk Nation/Home Menus/TeamBrowserView.swift:149` (`TeamBrowserView`) |
| Navigation routes (sport → league drilldown) | `TeamBrowserView.swift:153-156` (`Route.sport`, `Route.league`), `:243-250` |
| Search field | `TeamBrowserView.swift:293` (`.searchable(text: $query, prompt: "Search all teams")`), attached to every page via `page(_:)` `:280-313` |
| Results list | `TeamBrowserView.swift:458-479` (`searchResults`) |
| Result row view | `TeamBrowserView.swift:481-532` (`row(_:)`) |
| Local match set | `TeamBrowserView.swift:197-204` (`localMatches`) |
| Catalog loading | `TeamBrowserView.swift:254-260`, `:536-540` (`load`), `:544-561` (`searchRemotelyIfNeeded`) |
| Text matcher | `Hawk Nation/Networking/TeamRef.swift:363-388` (`TeamSearch`) |
| ESPN remote search fallback | `TeamBrowserView.swift:16-86` |
| Team model and identity | `TeamRef.swift:213-246` (`TeamRef`, `id`) |
| Browsable leagues (UCL added) | `TeamRef.swift:334-350`; `LeagueID.championsLeague` `:63` |
| League → cup mapping | `Hawk Nation/Networking/Sport.swift:183-188` (`cupCompetitions`), Bundesliga `:482-496`, UCL `:530-546` |
| Catalog fetch / parse | `Hawk Nation/Networking/RemoteTeamCatalog.swift:102-114`, `:163-188`, `:203-223`; URL `TeamRef.swift:98-100` |
| Follow persistence | `Hawk Nation/Home Menus/FavoritesStore.swift:82-159`; record `TeamRef.swift:509-540` (`FavoriteTeam`) |
| Schedule fetch | `Hawk Nation/Schedule/Classes/DownloadScheduleData.swift:326-357` |
| Scoreboard / alerts / Live Activity keyed by follow | `LeagueScoreboardCenter.swift:265-301`, `:409-424`; `ScoreAlertEngine.swift:119-130`; `LiveActivityManager.swift:157-170`; `TeamModel.swift:208-210` |
| Widget team search (same pattern) | `myTeamWidget/TeamEntity.swift:58-81` |
| Fixtures proving shared ESPN id | `myTeamsTests/Fixtures/bundes_teams.json` and `uclleague_teams.json` both list `id 132 "Bayern Munich"` (also `124` Dortmund) |

## 2. Current behavior (data path)

**API → model.** Each browsable league's catalog comes from
`GET site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams?limit=1000`
(`TeamRef.swift:98-100`). `RemoteTeamCatalog.parseTeams` turns every entry
into a `TeamRef` and **stamps it with the league that was requested**, not
with any league the payload names (`RemoteTeamCatalog.swift:203-222`):

```swift
return TeamRef(
    league: league,          // the requested catalog's league
    espnID: espnID,          // team["id"], e.g. "132"
    displayName: team["displayName"].stringValue, ...
```

So `soccer/uefa.champions/teams` gives Bayern as
`TeamRef(league: .championsLeague, espnID: "132")`, and `soccer/ger.1/teams`
gives `TeamRef(league: .bundesliga, espnID: "132")`.

**Model → view state.** On appear, the picker loads every browsable league,
UCL included, into `@State catalogs: [LeagueID: [TeamRef]]`
(`TeamBrowserView.swift:161`, `:254-260`, `:536-540`). While a query is
typed, it also makes sure every non-college browsable league is loaded
(`:547-549`).

**View state → rows.** There is no view model. `localMatches` flattens all
catalogs and filters them, with no grouping step (`TeamBrowserView.swift:197-204`):

```swift
let ordered = (current.map { [$0] } ?? []) + rest   // league on screen first, rest by path
return ordered
    .flatMap { catalogs[$0] ?? [] }
    .filter { TeamSearch.matches($0, query: query) }
```

`searchResults` renders those matches directly (`:459-466`):
`ForEach(local) { team in row(team) }`. Each row draws the crest, the
`displayName`, and the league badge capsule `team.league.badge`
(`:492-505`; badge lookup `TeamRef.swift:354-356` → `"Bundesliga"` / `"UCL"`).
The comment at `:498` explains why the badge is always shown: "Kansas City" is
four teams in four leagues. The design already expects the same name to appear
in several rows.

**Remote fallback.** ESPN search runs only when `localMatches` is empty
(`:555`) and is shown only in that case (`:467`). Each hit gets one league,
from `defaultLeagueSlug` (`:59`, `:68`), and hits are deduped by `TeamRef.id`
(`:46-50`). The fallback therefore never runs for "Bayern", and it cannot
produce a cross-league duplicate by itself.

## 3. Duplicate-row mechanics

- **Count:** "Bayern" gives **two** rows. With the default path ordering
  (`:199`), `soccer/ger.1` sorts before `soccer/uefa.champions`, so the
  Bundesliga row comes first. If the user is drilled into UCL, the UCL row comes
  first (`:198-200`).
- **Cause:** the client generates the extra row. It is a *catalog union*, not a
  roster cross-product, and not duplication inside one ESPN response. ESPN uses
  the same club id in both catalogs (`132` in `bundes_teams.json` and
  `uclleague_teams.json`). `parseTeams` qualifies that id with the requested
  league (`RemoteTeamCatalog.swift:210`), and `localMatches` concatenates the
  catalogs (`TeamBrowserView.swift:202`).
- **What triggered it:** UCL was added to `LeagueID.browsable`
  (`TeamRef.swift:349`). Before BE-3, `uefa.champions` existed only as a
  `cupCompetitions` entry (`Sport.swift:494`). It was fetched for schedules but
  never loaded as a catalog, so search could not see it.
- **Scope:** every UCL club whose domestic league is browsable now appears
  twice (EPL, La Liga, Bundesliga, Serie A, Ligue 1; e.g. Arsenal `359`, Dortmund
  `124`). UCL clubs from leagues that are not browsable (e.g. Portugal,
  Netherlands) appear **once, only as UCL**. No other browsable cup exists today.
  MLS and Liga MX cups are `cupCompetitions` only (`Sport.swift:307`, `:461`).
- **Same pattern elsewhere:** the widget's configuration search loops over the
  cached browsable catalogs in the same way and appends every match
  (`TeamEntity.swift:65-79`). Once the UCL catalog is cached, it shows both
  Bayern entities (subtitle `team.league.badge`, `:31`).
- **Counts in the drilldown:** the Soccer sport row and the league rows count
  followed teams per `TeamRef.league` (`TeamBrowserView.swift:368`, `:407`).
  Following both Bayern rows shows "2" on Soccer. The sport row's team total
  (`:369-373`) also counts each UCL club twice.

## 4. Row identity keys

- `TeamRef: Identifiable` with `id = "\(league.path):\(espnID)"`
  (`TeamRef.swift:240-246`). So the two rows are
  `soccer/ger.1:132` and `soccer/uefa.champions:132`.
- Every team `ForEach` uses that implicit `id`: results `:463`, remote `:469`,
  league page `:346`, My Teams `:222`.
- Row automation id: `teamBrowser.team.\(team.id)` (`:528`). VoiceOver label:
  `"\(displayName), \(league.badge)"` (`:526`).
- Because the ids differ, **SwiftUI sees no identity collision**. The duplicate
  is semantic only, and list diffing is correct as written.
- The widget's `TeamEntity.id` is the same `TeamRef.id` (`TeamEntity.swift:21-22`).

## 5. Follow semantics: UCL row vs Bundesliga row

**Tap.** `row(_:)` calls `store.toggle(team)` (`TeamBrowserView.swift:483-484`).
The check state is `store.isFavorite(team.id)` (`:482`). It matches the exact
id, so following one Bayern row **does not** check the other
(`FavoritesStore.swift:82-84`).

**Persisted.** `add` appends `FavoriteTeam(teamID: team.id, …)`
(`FavoritesStore.swift:136-143`). The stored key is the **club+league pair**
string (`TeamRef.swift:510-511`). It is saved under `favorites.v1` in App Group
defaults and mirrored to iCloud KVS (`TeamRef.swift:565`, `:645-649`). Both
rows can be followed together, and they become two favorites and two crest-bar
tabs.

**After the follow, everything keys off `TeamRef.parse(id).league`:**

| | Follow from **Bundesliga** row (`soccer/ger.1:132`) | Follow from **UCL** row (`soccer/uefa.champions:132`) |
|---|---|---|
| Schedule fetch | `ger.1/teams/132/schedule`, plus cups `ger.dfb_pokal`, `uefa.champions`, `uefa.europa`, merged (`DownloadScheduleData.swift:327`, `:335-355`; cups `Sport.swift:494`) | `uefa.champions/teams/132/schedule` only. `cupCompetitions` is `[]` (`Sport.swift:544`), so **no Bundesliga or Pokal games** |
| Record in header | Bundesliga record (`TeamModel.swift:151-152`) | UCL league-phase record |
| Standings | Bundesliga table (`TeamModel.swift:283`) | UCL table |
| Roster / news / leaders | `ger.1` paths (`TeamRef.swift:273-277`; `TeamModel.swift:136`) | `uefa.champions` paths |
| Scoreboard fan-out | Registered for `ger.1` **and** for `uefa.champions` through its cups (`LeagueScoreboardCenter.swift:265-269`), and lines merged across competitions (`:289-295`) | Registered for `uefa.champions` only |
| Score alerts / Live Activities | League + cups (`ScoreAlertEngine.swift:119-120`; `LiveActivityManager.swift:163`) | UCL games only |
| Deep link / LA tap target | `soccer/ger.1:132` | `soccer/uefa.champions:132`. This contradicts the stated rule that links are built "in its home league" (`TeamRef.swift:290-292`; `GameActivityAttributes.swift:37-42`) |

If both are followed, a UCL tie appears on both team pages and in both
registries for `uefa.champions`. Alerts dedupe per game id: the first follower
wins (`ScoreAlertEngine.swift:127-129`).

The UCL row is the less useful follow for a club whose league is browsable,
but nothing in the row tells the user that.

## 6. UI-only-fix constraints and seams

**Seams where a dedupe or group-by-club fits without backend changes:**

1. **`localMatches`** (`TeamBrowserView.swift:197-204`). This is the narrowest
   seam. Group by `(sport, espnID)` after the filter and pick a canonical
   `TeamRef`. A good rule: prefer a non-cup league, i.e. any league for which
   `LeagueDescriptor.known.values.contains { $0.cupCompetitions.contains(league) }`
   is true counts as a cup. Keep the UCL entry only when the club has no
   browsable domestic league loaded. All inputs are already in memory.
2. **`searchResults`** (`:459-466`). The same grouping can be done at render
   time, with one row per club and secondary badges (e.g. "Bundesliga · UCL")
   that are display-only.
3. **Widget** `TeamEntityQuery.entities(matching:)` (`TeamEntity.swift:74-79`).
   It needs the same rule, or the widget picker still shows two Bayerns. A
   shared helper next to `TeamSearch` (`TeamRef.swift:363`) would serve both,
   since that file is already shared with the widget (`:361-362`).

**What a dedupe must not break:**

- **Per-league context in the row.** The row's badge and follow target are both
  `team.league`. A merged row must still follow **one** concrete `TeamRef`, so
  the canonical pick decides follow semantics (§5). Don't follow both.
- **Cross-sport homonyms must stay separate.** ESPN ids are per sport, not
  global. Key on `(league.sport, espnID)`, never on `espnID` alone or on
  `displayName` ("Kansas City" is four different teams, `:498`).
- **UCL-only clubs** (non-browsable domestic league) must survive the dedupe,
  because UCL is their only follow path.
- **Existing UCL follows.** Users who already followed `soccer/uefa.champions:132`
  have that id persisted and iCloud-synced (`FavoritesStore.swift:194`). The
  canonical row's checkmark tests only its own id (`:482`), so after a dedupe
  that user would see Bayern as *unfollowed* in search. Either the check state
  must look at any `(sport, espnID)` sibling, or the follow must be migrated.
  Migration is a data change and outside a UI-only fix.
- **Sport → league drilldown (UI-4).** Do not dedupe the per-league pages:
  `teamsPage(.championsLeague)` (`:335-360`) should still list every UCL club,
  Bayern included, with its UCL id. Its footer count (`:353`) and the
  sport/league follow badges (`:368`, `:407`) are per league by design. Only the
  cross-league search results need grouping. Search is mounted on every page
  (`:287-293`) and is cleared on navigation (`:268-270`). On the UCL page,
  "current league first" ordering (`:198-200`) arguably *should* favor the UCL
  entry, which conflicts with a global "prefer domestic" rule. This needs a
  product decision (see Open questions).
- **Tests.** There are no tests on `localMatches` or the results list today.
  `TeamSearchTests.swift` covers only `TeamSearch.matches`, badges, id
  round-trip and remote parsing (`:46-123`). `GlassUIScreenshotTests` /
  `myTeamsUITests` may depend on `teamBrowser.team.<id>` identifiers (`:528`).

**Prior docs.**

- `docs/ANALYSIS-any-team-roadmap.md:330-335` specifies local search over the
  cached catalogs, with remote search only as a fallback. The current code
  follows this.
- `:529` plans "major soccer leagues … plus cups" without saying how a cup
  catalog should interact with search.
- `docs/UI_AUDIT_IOS27_GLASSUI.md:100`, `:221-227` audits the browser as it was
  before the redesign (league chip row; line refs now stale) and says nothing
  about duplicates.
- No existing doc mentions "UI-4" or cross-league dedupe.

## Open questions

1. When the user is drilled into the UCL page, should search prefer the UCL
   entry (current ordering) or the domestic one (the richer follow)?
2. Should an existing `uefa.champions:<id>` follow be shown as followed on the
   domestic row, migrated to the domestic id, or left alone?
3. Should the UCL catalog (`teamsPage(.championsLeague)`) follow the
   *domestic* `TeamRef` when the club has one? This would change the drilldown
   follow semantics, not only search.
4. Should the widget's team search (`TeamEntity.swift:58`) get the same dedupe
   in the same change?
5. The sport row total (`TeamBrowserView.swift:369-373`) counts UCL clubs twice.
   Is that acceptable, or should it count unique clubs?
6. Live Activity and alert deep links for a UCL-filed favorite open the UCL
   team page (`soccer/uefa.champions:132`). Is that acceptable, given
   `TeamRef.swift:290-292` says links should use the home league?
