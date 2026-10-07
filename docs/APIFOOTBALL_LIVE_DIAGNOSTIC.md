# API-Football tier 3: live diagnostic (2026-10-07)

**Symptom.** With a working free-plan API-Football key saved and the toggle on,
no soccer roster showed one API-Football photo. Nothing failed visibly.

**Root cause.** The tier-3 sweep paged `GET /players?league=<id>&season=<S>`.
The free plan **refuses any page past 3**. The EPL has 57 pages of 20 rows,
sorted by ascending player id, so the three it gives hold the league's
longest-serving players. Those rows include none of Arsenal's current squad.
The sweep paused for an hour on the page-4 refusal and asked for page 4 again
on the next roster open. It never finished.

**Fix.** Sweep per **club**: `GET /players?team=<id>&season=<S>`. Arsenal fits
in 3 pages, and its rows join 12 of 27 current players (13 in the Python
mirror; see below). A page-cap error now ends a sweep as finished. It never
pauses.

All requests below went out once, from the developer's machine, with the
reader's free key. The key is shown as `<KEY>` and appears in no capture.
Captures are in `myTeamsTests/Fixtures/` (see FIXTURES.md, "Live captures").

## Per-stage results

| # | Request | Response (excerpt) | Verdict |
|---|---|---|---|
| 1 | `curl -H 'x-apisports-key: <KEY>' 'https://v3.football.api-sports.io/status'` | `subscription.plan: "Free"`, `requests: {current: 6, limit_day: 100}` | Key valid. Free plan, 100 requests a day, 6 used at probe time |
| 2 | `curl -H 'x-apisports-key: <KEY>' 'https://v3.football.api-sports.io/players?league=39&season=2026&page=1'` | HTTP 200, `errors.plan: "Free plans do not have access to this season, try from 2022 to 2024."`, `response: []` | Expected. The existing `fallbackSeason` retries with 2024 |
| 3 | the same, `season=2025` | the same `errors.plan` | Confirms 2024 is the newest free season |
| 4 | the same, `season=2024&page=1` | `results: 20`, `paging: {current: 1, total: 57}`. First row id 5 (M. Akanji), last id 169 | Works, but **57 pages** at 20 rows each, by ascending id |
| 5 | the same, `page=2`, `page=3` | 20 rows each, `paging.total: 57` | OK |
| 6 | the same, `page=4` | HTTP 200, `errors.plan: "Free plans are limited to a maximum value of 3 for the Page parameter"`, `response: []` (`apifootball_players_page_cap.json`) | **Root cause.** The old code found no year in this message, so it called `pause()` and returned. The sweep never completed, so every roster open spent a request on page 4 and paused for 1 h |
| 7 | Join replay: ESPN Arsenal roster (27 players, `arsenal_roster_live.json`) against the 60 rows from pages 1–3 | Only T. Partey (49) and Cédric Soares (190) name Arsenal, and both have left | **0 / 27 matched.** This is the device symptom |
| 8 | `curl -H 'x-apisports-key: <KEY>' 'https://v3.football.api-sports.io/teams?league=39&season=2026'` | the same season `errors.plan` ("try from 2022 to 2024") | Same fallback |
| 9 | the same, `season=2024` | `results: 20`, `paging: {current: 1, total: 1}`. `{id: 42, name: "Arsenal"}`, `{id: 49, name: "Chelsea"}`, … (`apifootball_teams_epl_live.json`) | Map OK: Arsenal = **42** |
| 10 | `curl -H 'x-apisports-key: <KEY>' 'https://v3.football.api-sports.io/players?team=42&season=2024&page=1'` (and `page=2`, `page=3`) | 20 + 20 + 19 rows, `paging: {current: n, total: 3}` (`apifootball_players_team42_p1…p3.json`) | **Fits the free plan's page cap** |
| 11 | Join replay: ESPN Arsenal roster against those 59 rows | Raya, Kepa, Saliba, B. White, J. Timber, Calafiori, Gabriel Magalhães, Ødegaard, Merino, Rice, Havertz, Saka (+ Lewis-Skelly in the Python mirror of the join) | **12 / 27 matched.** Accents and initials join. The misses are 2025-26 arrivals with no 2024 row; tiers 1 and 2 cover them |
| 12 | `curl 'https://media.api-sports.io/football/players/{978,1460,19465,37127}.png'` (keyless) | 150×150 PNGs of 30,795 / 23,346 / 25,197 / 31,363 B (Havertz, Saka, Raya, Ødegaard) | Real photos, not the 5,192 B or 8,624 B placeholders. The CDN and placeholder rejection are not involved |

Requests for a reader who opens 1 to 3 clubs: 1–2 for the league's club map
(2 when the season falls back), plus 2–3 per club. That is well under
`ApiFootball.dailyRequestCap` (40).

## The fix (`Hawk Nation/Networking/ApiFootballHeadshotStore.swift`)

- **Club map.** `GET /teams?league=&season=` (`ApiFootball.teamsURL`,
  `parseTeams`) is fetched once a season. It uses the same season fallback and
  is kept in `teams-league-<id>.json` (`ApiFootballTeamMap`). The map stores
  the season asked for (it is refetched only when the computed season
  changes) and the season actually served (club sweeps start there).
- **Club id.** `ApiFootball.teamID(for:in:)` matches ESPN's team name against
  the map with the existing `teamsMatch`. With no single match, that club gets
  no tier 3: no requests and no retries.
- **Club sweep.** `GET /players?team=&season=&page=` (`teamPlayersURL`) for
  each club seen in a roster. Each club's sweep is kept in `team-<id>.json`
  (`ApiFootballSweep`, `route: .team`) with the same 7-day freshness. Rows are
  still attributed to the league they were swept from (`parsePlayers(_:league:)`).
- **Page cap.** `ApiFootball.pageCap(from:)` reads "maximum value of N for the
  Page parameter". A page-cap error completes the sweep (`completed = now`,
  rows kept, `pageCap` stored). Once the cap is known, a sweep stops after
  page N without asking for page N+1. Season errors still go through
  `fallbackSeason`. Every other error still pauses.
- **Join pool.** All sweeps whose rows belong to the league: old
  `league-<id>.json` files (decoded with `route` defaulting to `.league`, read
  only, never resumed) plus every club file.
- **Unchanged.** The budget, request spacing, the 1-hour pause on real
  failures, the name join, and the credentials gate (no key or toggle off
  means zero requests; a key saved after the roster loaded starts the sweep,
  as in t_1fa9b665).

Known gap: ESPN club names that `teamsMatch` cannot pair with API-Football's
short names (in the 2024 EPL map, "Wolverhampton Wanderers" vs "Wolves") get
no tier 3. Tiers 1 and 2 still apply.
