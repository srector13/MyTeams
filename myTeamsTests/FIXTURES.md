# ESPN fixtures

`myTeamsTests/Fixtures/` holds real ESPN responses, captured on **2026-09-27**
between 17:05Z and 17:39Z (the news feed at 19:33Z). `GoldenParserTests.swift`
runs every parser over them and asserts exactly what the code produces today.
See the roadmap (`docs/ANALYSIS-any-team-roadmap.md` §6 Phase 1, "Tests
first").

## How the tests find them

`Fixtures` is a **folder reference** in the `myTeamsTests` target's Resources
phase, so the test bundle contains `Fixtures/<name>.json`. `FixtureLoader.swift`
(`Fixture.json("chiefs_schedule")`) looks there first. If the file isn't in the
bundle, it falls back to the source tree next to `FixtureLoader.swift` via
`#filePath`. That fallback covers a target edited by hand or a runner that skips
the Resources phase, and it only works on the machine that built the tests.

## What was captured

The capture script is not checked in. The URLs below were rebuilt from the
app's own endpoint patterns (`Team.scheduleURL` / `summaryURL`, the roster and
splits URLs in `Roster/Classes`) and checked against each document's
`timestamp`/`season` blocks.

`{league}`: `basketball/mens-college-basketball` (jayhawks, team 2305),
`football/nfl` (chiefs, 12), `baseball/mlb` (royals, 7), `soccer/usa.1`
(sporting, 186).

| File | URL | Captured (`timestamp`) |
|---|---|---|
| `{team}_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/{league}/teams/{id}/schedule` | chiefs 17:38:53Z, royals 17:39:00Z, sporting 17:37:17Z |
| `jayhawks_schedule_offseason.json` | same, Kansas: the live feed today. `events: []`, season 2027 (2026-27 preseason) | 17:38:28Z |
| `jayhawks_schedule_2026.json` | same, plus `?season=2026` (the 2025-26 season, 33 games) | 17:33:13Z |
| `{team}_summary_{phase}_{eventID}.json` | `https://site.api.espn.com/apis/site/v2/sports/{league}/summary?event={eventID}` | 2026-09-27 (no timestamp field) |
| `{team}_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/{league}/teams/{id}/roster` | jayhawks 17:38:43Z, chiefs 17:39:00Z, royals 17:38:56Z, sporting 17:38:00Z |
| `jayhawks_roster_2026.json` | same, plus `?season=2026` (2025-26 postseason roster) | 17:05:40Z |
| `{team}_splits_{athleteID}.json` | `https://site.web.api.espn.com/apis/common/v3/sports/{league}/athletes/{athleteID}/splits` | 2026-09-27 |
| `sporting_athlete_249729.json` | `https://site.web.api.espn.com/apis/common/v3/sports/soccer/usa.1/athletes/249729` | 2026-09-27 |
| `chiefs_news.json` | `https://site.api.espn.com/apis/site/v2/sports/football/nfl/news?team=12&limit=25` (25 articles; newest `published` 2026-09-27T18:50:54Z) | 19:33Z (file time; the feed has no timestamp field) |
| `_athletes.json` | Not a response. It lists the athlete ids chosen for splits: jayhawks 4872739 (Elmarko Jackson), chiefs 4912218 (Cyrus Allen), royals 5136077 (Spencer Bivens, RP), sporting 249729 (Stefan Cleveland, GK) | — |

### Game phase of each summary

`header.competitions[0].status.type`:

| Fixture | Event | `state` | `detail` | What it covers |
|---|---|---|---|---|
| `chiefs_summary_pregame_401872976` | Chiefs at Raiders, Oct 4 | `pre` | `Sun, October 4th at 4:25 PM EDT` | Pre-game: no header scores, box score holds season averages, `predictor` present |
| `chiefs_summary_live_401872952` | Chiefs at Dolphins | **`in`** | `13:49 - 2nd Quarter` | A real **in-game** snapshot: 7–7, two linescores |
| `chiefs_summary_final_401872945` | Colts at Chiefs, 33–30 | `post` | **`Final/OT`** | Overtime: five linescores per side |
| `jayhawks_summary_final_401851305` | Kansas at Houston (neutral: Kansas City), 47–69 | `post` | `Final` | Regulation college game (two halves) |
| `royals_summary_final_401817094` | Guardians at Royals, 11–5 | `post` | `Final` | Nine innings of per-inning linescores |
| `royals_summary_pregame_401817109` | Guardians at Royals, Sep 27 | `pre` | `Scheduled` | Pre-game MLB: box score holds season totals |
| `sporting_summary_final_761450` | Sporting at San Jose, 0–3 | `post` | `FT` | MLS full time |

### Status strings in the schedules

| Detail | Where |
|---|---|
| `Final` | everywhere |
| `Final/OT` | chiefs 401872945; jayhawks_2026 401817259, 401827601 |
| `Final/10` (extra innings) | royals 401815101 (the only extra-innings event kept after trimming) |
| `Postponed` | royals 401814790 |
| `14:14 - 2nd Quarter` (`state: in`) | chiefs 401872952 |
| `FT` | all 26 sporting events |
| pre-game date strings, `1/3 - TBD` | chiefs events 3–16 |

No captured feed has a `Canceled` or `Suspended` game. The tests make those
cases by copying a real event and replacing only `status.type.detail`
(`JSON.setting(_:to:)`).

## Trimming

`royals_schedule.json` was trimmed from 163 events to 9 before it was wired in
as a resource. **2,733,966 bytes were removed** (2,879,870 → 145,904). The kept
events, in feed order, are:

- the first five (401814691, 401814710, 401814725, 401814743, 401814772)
- the only `Postponed` game (401814790)
- one `Final/10` extra-innings game (401815101)
- the two events that have summary fixtures (401817094, 401817109)

The rest of the document (`season`, `team`, `allstarsgame`, …) is unchanged.
The original file was compact JSON, and the trim re-serialised it the same way
(`separators=(',', ':')`), so every kept event is byte-identical to the capture.
Every other fixture is byte-for-byte what ESPN returned.

## Team catalogs (P2-a)

`RemoteTeamCatalogTests.swift` reads two `teams` documents, captured on
**2026-09-27** from this host:

```sh
base=https://site.api.espn.com/apis/site/v2/sports
curl -s "$base/football/nfl/teams?limit=500" -o nfl_teams.json
curl -s "$base/football/college-football/teams?limit=1000&groups=50" -o college_football_teams.json
```

Both were **trimmed to 15 teams** (`sports[0].leagues[0].teams`), keeping
feed order and every other key; each kept team object is unchanged. They were
re-serialised compactly (`separators=(',', ':')`).

| File | Teams | Bytes (capture → trimmed) | Kept |
|---|---|---|---|
| `nfl_teams.json` | 32 → 15 | 148,848 → 69,777 | the first 13 in feed order, plus Kansas City (12) and Las Vegas (13) |
| `college_football_teams.json` | 762 → 15 | 1,856,910 → 39,381 | the first 11 in feed order, plus Andrew (134002: no logos, no colours), Apprentice School (3111: colour, no logos), Arizona Christian (108358: no logos) and Kansas (2305) |

Notes on the live shape:

- `limit=500` caps college football at 500 teams; `limit=1000` returns all
  762 (with or without `groups=50`). The app asks for `limit=1000`.
- 91 of the 762 college teams have no `logos`, and 72 have no `color`. Every
  team with logos had both a `["full","default"]` and a `["full","dark"]`
  entry, so the dark-absent case is made in the test by filtering one real
  team's `logos` (`JSON.setting`), not by editing the fixture.
- NFL teams list 17 logos: default, dark, scoreboard, scoreboard-dark,
  grayscale and twelve 4096 px `guid/…` brand-service images. Default is first
  in the feed, so the selection test reverses the Chiefs' array in memory.

## League scoreboards (P2-c)

`LeagueScoreboardTests.swift` reads three scoreboard documents, captured on
**2026-09-28 at 03:44Z** (Sunday evening US time) from this host:

```sh
base=https://site.api.espn.com/apis/site/v2/sports
curl -s "$base/football/nfl/scoreboard?dates=20260927" -o nfl_scoreboard_20260927.json
curl -s "$base/baseball/mlb/scoreboard?dates=20260927" -o mlb_scoreboard_20260927.json
curl -s "$base/football/nfl/scoreboard?dates=20260928" -o nfl_scoreboard_20260928.json
```

The responses carried `Cache-Control: max-age=4` (NFL) and `max-age=3` (MLB).
The two Sunday boards were **trimmed to three events** each, keeping feed
order and every other key; each kept event is unchanged. They were
re-serialised compactly (`separators=(',', ':')`, `ensure_ascii=False`).
Monday's board has one event and is as captured.

| File | Events (capture → kept) | Bytes (capture → trimmed) | Kept |
|---|---|---|---|
| `nfl_scoreboard_20260927.json` | 14 → 3 | 239,943 → 49,076 | 401872962 Rams (14) at Broncos (7), **`in`**, 26–23 with 0:48 left, kicked off 00:20Z Monday (so on Sunday's board); 401872952 Chiefs (12) at Dolphins (15), final 24–10 (the event of `chiefs_summary_live_401872952`); 401872961 Raiders (13) at Saints (18), final 35–27 |
| `mlb_scoreboard_20260927.json` | 15 → 3 | 402,061 → 68,343 | 401817103 Orioles (1) at Yankees (10), `STATUS_CANCELED` (`post`, not completed, 0–0); 401817106 Mets (21) at Nationals (20), final 6–4 to Washington; 401817109 Guardians (5) at Royals (7), final 3–2 (the event of `royals_summary_pregame_401817109`) |
| `nfl_scoreboard_20260928.json` | 1 → 1 | 23,187 (as captured) | 401872963, Monday night, `pre`, both scores `"0"` |

Scoreboard competitors carry `score` as a bare string (`"23"`), like the
summary header, not the schedule's `{"displayValue": …}`.

## New leagues (P3-a)

`LeagueRegistryTests.swift` reads 63 documents for the nine leagues P3-a
registered, captured on **2026-09-28 between 04:45:24Z and 04:46:20Z** from
this host by the checked-in script:

```sh
python3 scripts/capture_fixtures_p3a.py            # every league
python3 scripts/capture_fixtures_p3a.py nba epl    # just these
```

The script uses plain `curl` (ESPN's Akamai front answers browser
User-Agents with 403), spaces requests 0.5 s apart, retries a 403/429 once
after 5 s, and checks every file it writes parses and is non-trivial (teams
> 0; an `events` key; standings `children` ≥ 1; a summary with `header` and
`boxscore`). It prints the table below.

Per league: `{lg}_teams`, `{lg}_schedule`, `{lg}_roster`, `{lg}_news`,
`{lg}_scoreboard_{YYYYMMDD}`, `{lg}_standings` and
`{lg}_summary_{phase}_{eventID}` — 7 files × 9 leagues. Sample teams: NBA
Hawks (1), WNBA Dream (20), NHL Ducks (25), NCAAF and NCAAW Kansas (2305),
EPL Arsenal (359), LALIGA 83, Liga MX 227, NWSL 21422. Every sport kind has a
summary: basketball (nba, wnba, ncaaw), hockey (nhl), football (ncaaf),
soccer (epl, laliga, ligamx, nwsl).

### Trimming

Trimmed files keep feed order and every other key, and each kept element is
unchanged; they are re-serialised compactly (`separators=(',', ':')`,
`ensure_ascii=False`). Every other file is byte-for-byte what ESPN returned.

- **teams**: 15 teams (`sports[0].leagues[0].teams`), the first 14 plus the
  sample team if it was not among them (or the first 15 if it was).
- **scoreboard**: 3 events, always keeping the summary's event. Trimmed boards
  also drop the copy of the events under `leagues[0].events` (the app reads
  the top-level `events`); untrimmed boards keep it.
- **schedule**: 12 events, keeping the summary's event if listed.
- **standings**: only the two college trees, by conference abbreviation —
  `ncaaf` keeps Big 12 (`big12`) and Sun Belt (`belt`, the one FBS
  conference split into divisions); `ncaaw` keeps America East (`aeast`) and
  Big 12. (Uncut, they are 2.6 MB and 6.2 MB: each entry carries ~20 stats.)

### What was captured

| File | URL | Captured | Contents |
|---|---|---|---|
| `nba_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams?limit=1000` | 2026-09-28T04:45:24Z | teams=15; trimmed 30 → 15 teams |
| `nba_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/1/schedule` | 2026-09-28T04:45:26Z | events=5 |
| `nba_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/1/roster` | 2026-09-28T04:45:26Z | athletes=18 shape=flat |
| `nba_news.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/news?team=1&limit=25` | 2026-09-28T04:45:31Z | articles=25 |
| `nba_scoreboard_20261003.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=20261003` | 2026-09-28T04:45:32Z | events=1 |
| `nba_standings.json` | `https://site.api.espn.com/apis/v2/sports/basketball/nba/standings` | 2026-09-28T04:45:37Z | children=2 entries=30 |
| `nba_summary_pregame_401902644.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=401902644` | 2026-09-28T04:45:37Z | phase=pregame |
| `wnba_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/teams?limit=1000` | 2026-09-28T04:45:40Z | teams=15 |
| `wnba_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/teams/20/schedule` | 2026-09-28T04:45:40Z | events=12; trimmed 49 → 12 events |
| `wnba_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/teams/20/roster` | 2026-09-28T04:45:40Z | athletes=14 shape=flat |
| `wnba_news.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/news?team=20&limit=25` | 2026-09-28T04:45:41Z | articles=25 |
| `wnba_scoreboard_20260814.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/scoreboard?dates=20260814` | 2026-09-28T04:45:42Z | events=2 |
| `wnba_standings.json` | `https://site.api.espn.com/apis/v2/sports/basketball/wnba/standings` | 2026-09-28T04:45:42Z | children=2 entries=15 |
| `wnba_summary_final_401857143.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/wnba/summary?event=401857143` | 2026-09-28T04:45:43Z | phase=final |
| `nhl_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams?limit=1000` | 2026-09-28T04:45:43Z | teams=15; trimmed 32 → 15 teams |
| `nhl_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/25/schedule` | 2026-09-28T04:45:44Z | events=4 |
| `nhl_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/25/roster` | 2026-09-28T04:45:44Z | athletes=56 shape=grouped |
| `nhl_news.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/news?team=25&limit=25` | 2026-09-28T04:45:45Z | articles=25 |
| `nhl_scoreboard_20260919.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=20260919` | 2026-09-28T04:45:45Z | events=3; trimmed 7 → 3 events |
| `nhl_standings.json` | `https://site.api.espn.com/apis/v2/sports/hockey/nhl/standings` | 2026-09-28T04:45:51Z | children=2 entries=32 |
| `nhl_summary_final_401881922.json` | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event=401881922` | 2026-09-28T04:45:51Z | phase=final |
| `ncaaf_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams?limit=1000&groups=50` | 2026-09-28T04:45:52Z | teams=15; trimmed 762 → 15 teams |
| `ncaaf_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/2305/schedule` | 2026-09-28T04:45:52Z | events=12 |
| `ncaaf_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/2305/roster` | 2026-09-28T04:45:53Z | athletes=100 shape=grouped |
| `ncaaf_news.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/news?team=2305&limit=25` | 2026-09-28T04:45:53Z | articles=25 |
| `ncaaf_scoreboard_20260829.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard?dates=20260829` | 2026-09-28T04:45:53Z | events=3; trimmed 8 → 3 events |
| `ncaaf_standings.json` | `https://site.api.espn.com/apis/v2/sports/football/college-football/standings?group=80` | 2026-09-28T04:45:54Z | children=2 entries=30; trimmed 11 → 2 children |
| `ncaaf_summary_final_401864494.json` | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/summary?event=401864494` | 2026-09-28T04:45:55Z | phase=final |
| `ncaaw_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/teams?limit=1000&groups=50` | 2026-09-28T04:45:55Z | teams=15; trimmed 362 → 15 teams |
| `ncaaw_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/teams/2305/schedule` | 2026-09-28T04:45:56Z | events=12; trimmed 31 → 12 events |
| `ncaaw_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/teams/2305/roster` | 2026-09-28T04:45:56Z | athletes=12 shape=flat |
| `ncaaw_news.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/news?team=2305&limit=25` | 2026-09-28T04:45:57Z | articles=25 |
| `ncaaw_scoreboard_20261102.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/scoreboard?dates=20261102&groups=50&limit=1000` | 2026-09-28T04:45:57Z | events=3; trimmed 118 → 3 events |
| `ncaaw_standings.json` | `https://site.api.espn.com/apis/v2/sports/basketball/womens-college-basketball/standings?group=50` | 2026-09-28T04:45:58Z | children=2 entries=25; trimmed 31 → 2 children |
| `ncaaw_summary_pregame_401926040.json` | `https://site.api.espn.com/apis/site/v2/sports/basketball/womens-college-basketball/summary?event=401926040` | 2026-09-28T04:45:58Z | phase=pregame |
| `epl_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams?limit=1000` | 2026-09-28T04:45:59Z | teams=15; trimmed 20 → 15 teams |
| `epl_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams/359/schedule` | 2026-09-28T04:45:59Z | events=5 |
| `epl_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams/359/roster` | 2026-09-28T04:46:00Z | athletes=27 shape=flat |
| `epl_news.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/news?team=359&limit=25` | 2026-09-28T04:46:00Z | articles=25 |
| `epl_scoreboard_20260821.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20260821` | 2026-09-28T04:46:01Z | events=1 |
| `epl_standings.json` | `https://site.api.espn.com/apis/v2/sports/soccer/eng.1/standings` | 2026-09-28T04:46:01Z | children=1 entries=20 |
| `epl_summary_final_401879301.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/summary?event=401879301` | 2026-09-28T04:46:02Z | phase=final |
| `laliga_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams?limit=1000` | 2026-09-28T04:46:02Z | teams=15; trimmed 20 → 15 teams |
| `laliga_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams/83/schedule` | 2026-09-28T04:46:03Z | events=7 |
| `laliga_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams/83/roster` | 2026-09-28T04:46:03Z | athletes=30 shape=flat |
| `laliga_news.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/news?team=83&limit=25` | 2026-09-28T04:46:04Z | articles=25 |
| `laliga_scoreboard_20260815.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/scoreboard?dates=20260815` | 2026-09-28T04:46:04Z | events=2 |
| `laliga_standings.json` | `https://site.api.espn.com/apis/v2/sports/soccer/esp.1/standings` | 2026-09-28T04:46:05Z | children=1 entries=20 |
| `laliga_summary_final_401882926.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/summary?event=401882926` | 2026-09-28T04:46:06Z | phase=final |
| `ligamx_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/teams?limit=1000` | 2026-09-28T04:46:06Z | teams=15; trimmed 18 → 15 teams |
| `ligamx_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/teams/227/schedule` | 2026-09-28T04:46:08Z | events=8 |
| `ligamx_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/teams/227/roster` | 2026-09-28T04:46:09Z | athletes=35 shape=flat |
| `ligamx_news.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/news?team=227&limit=25` | 2026-09-28T04:46:09Z | articles=25 |
| `ligamx_scoreboard_20260815.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/scoreboard?dates=20260815` | 2026-09-28T04:46:10Z | events=3 |
| `ligamx_standings.json` | `https://site.api.espn.com/apis/v2/sports/soccer/mex.1/standings` | 2026-09-28T04:46:11Z | children=1 entries=18 |
| `ligamx_summary_final_401877018.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/mex.1/summary?event=401877018` | 2026-09-28T04:46:11Z | phase=final |
| `nwsl_teams.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/teams?limit=1000` | 2026-09-28T04:46:16Z | teams=15; trimmed 16 → 15 teams |
| `nwsl_schedule.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/teams/21422/schedule` | 2026-09-28T04:46:17Z | events=12; trimmed 26 → 12 events |
| `nwsl_roster.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/teams/21422/roster` | 2026-09-28T04:46:18Z | athletes=25 shape=flat |
| `nwsl_news.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/news?team=21422&limit=25` | 2026-09-28T04:46:18Z | articles=25 |
| `nwsl_scoreboard_20260814.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/scoreboard?dates=20260814` | 2026-09-28T04:46:18Z | events=3; trimmed 4 → 3 events |
| `nwsl_standings.json` | `https://site.api.espn.com/apis/v2/sports/soccer/usa.nwsl/standings` | 2026-09-28T04:46:19Z | children=1 entries=16 |
| `nwsl_summary_final_401853969.json` | `https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/summary?event=401853969` | 2026-09-28T04:46:20Z | phase=final |

"Captured" is the script's clock at each response. The schedule and roster
`timestamp` fields are ESPN's cache time and run up to 80 s earlier (e.g.
`ncaaf_schedule` 04:44:32Z) — not a capture time.

### Seasons the feeds returned

No request named a season. The `season` block of each schedule (the roster's
matches it):

| League | `season.year` | `displayName` | `name` |
|---|---|---|---|
| nba, nhl | 2027 | 2026-27 | Preseason |
| ncaaw | 2027 | 2026-27 | Preseason |
| wnba | 2026 | 2026 | Postseason |
| ncaaf | 2026 | 2026 | Regular Season |
| epl, laliga, ligamx | 2026 | 2026-27 … | the league's season name |
| nwsl | 2026 | 2026 NWSL | Regular Season |

So ESPN numbers NBA, NHL and college basketball seasons by their **ending**
year and football and soccer by their **starting** year. The college
basketball standings are the exception to "current season": `ncaaw_standings`
has a root `season` of 2027, but both conference tables are `2025-26`
(`children[i].standings.seasonDisplayName`) — last season's final table,
since 2026-27 has not tipped off.

### Standings tree shape

`https://site.api.espn.com/apis/v2/sports/{league}/standings` (no `/site`;
the `/apis/site/v2/…/standings` path is an empty stub). The root is the
league (or the college division) and has **no `standings` of its own**; the
tables are in `children`:

```
root {name, season, seasons, children: [
  child {name, abbreviation, standings: {seasonDisplayName, entries: [
    {team: {id, displayName, …}, note?, stats: [{name, displayName, abbreviation, value, displayValue, …}]}
  ]}}
  | child {name, abbreviation, children: [ …grandchildren with standings… ]}
]}
```

- NBA, WNBA, NHL: 2 children (Eastern / Western Conference), 30 / 15 / 32
  entries.
- Soccer (EPL, LALIGA, Liga MX, NWSL): **exactly one child**, named for the
  season (`2026-27 English Premier League`), holding the whole table. Soccer
  entries carry a `note` (qualification / relegation colour and text).
- NCAAF `group=80` (FBS): 11 conference children; **Sun Belt has no
  `standings`, only `children`** (Sun Belt - East / West), so a parser has
  to walk one level deeper. Without `group` the feed also returns FBS;
  `group=50` would be one FCS conference.
- NCAAW / NCAAM `group=50` (Division I): 31 conference children. Without
  `group` the feed returns the same Division I tree today; the registry
  names it anyway.
- Stats are found by `name` (`wins`, `losses`, `gamesBehind`, `points`, …);
  their order differs by league.

### Reading the standings (P3-b)

`StandingsTests.swift` runs `parseStandings` over all nine trees. What the
parser has to allow for, found in these captures:

- **Stat `name`s repeat in college rows.** NCAAF and NCAAW rows carry every
  stat once per split (home, away, conference, vs AP Top 25), all under the
  same `name` (`wins`); only `type` tells them apart (`wins`,
  `homerecord_wins`, `vsconf_wins`). `type` is unique within a row, so the
  parser keys on it.
- **NCAAF rows have no `losses` stat.** Losses come from the `overall`
  summary (`type: total`, `"1-2"`).
- **Soccer's `ties` are draws, and its summary is W-D-L**: NWSL Gotham
  `"16-6-4"` is 16 W, 6 D, 4 L. Tables rank by the `rank` stat.
- **NHL rows carry both `otLosses` and `overtimeLosses`** (equal); the
  summary is `"W-L-OTL, N PTS"`.
- **`points` means different things.** Soccer and NHL: league points. NBA
  and WNBA: games over .500 (`8.0` for a 30–14 Dream) — not read.
- **Row order is not always first place first.** NCAAW conference tables list
  the lowest seed first; rows are ordered by `rank`/`playoffSeed` when every
  row has one. The NBA and NHL captures are preseason: every stat 0, every
  seed 0, teams alphabetical — kept in feed order.
- The NHL test gives the Ducks' preseason row a season by rewriting four
  `value`s in memory (`JSON.setting`); the fixture is unchanged.

No rankings document was captured. The college fallback
(`https://site.api.espn.com/apis/site/v2/sports/{league}/rankings`:
`rankings[].ranks[]` of `current`, `recordSummary`, `team`) is tested with
a hand-written document in that shape, checked against the live endpoint on
2026-09-28.

### Cup schedules (P3-b)

A soccer team's cups are fetched from the same team schedule endpoint under
the cup's path (`soccer/eng.fa/teams/359/schedule`). Checked live on
2026-09-28 for Arsenal, LALIGA 83, Liga MX 227 and Sporting KC: a cup the
team has no current fixtures in answers with its **previous edition** (the
FA Cup returned the 2025-26 run), so cup events are kept only when their
`season.year` matches the league feed's. `usa.nwsl.cup` listed nothing and
is not registered. No cup schedule was captured; the merge tests build a
cup feed from `epl_schedule` events.

### Roster shapes

As the recon expected: basketball (nba, wnba, ncaaw) and soccer feeds are
flat. NHL is grouped **by position** (`position`: Centers, Left Wings, Right
Wings, Defense, Goalies), not by unit; NCAAF is grouped by unit
(`offense`/`defense`/`specialTeam`) like the NFL, with the line as one
`Offensive Lineman` position, plus three status groups the NFL-style menu
does not filter on: `injuredReserveOrOut`, `suspended`, `practiceSquad`.

## Refreshing

1. Re-run the requests above, for example:

   ```sh
   cd myTeamsTests/Fixtures
   base=https://site.api.espn.com/apis/site/v2/sports
   web=https://site.web.api.espn.com/apis/common/v3/sports
   curl -s "$base/football/nfl/teams/12/schedule" -o chiefs_schedule.json
   curl -s "$base/football/nfl/summary?event=401872952" -o chiefs_summary_live_401872952.json
   curl -s "$base/football/nfl/teams/12/roster" -o chiefs_roster.json
   curl -s "$web/football/nfl/athletes/4912218/splits" -o chiefs_splits_4912218.json
   curl -s "$base/football/nfl/news?team=12&limit=25" -o chiefs_news.json
   # …and the same per team/league from the tables above.
   ```

   A live summary only exists while a game is being played. To replace
   `chiefs_summary_live_*`, capture during a game and keep the event id in the
   file name.
2. Check each file with `python3 -m json.tool < file > /dev/null`.
3. Re-trim `royals_schedule.json` if it has grown (keep the events listed
   above, or their new equivalents).
4. Every golden value in `GoldenParserTests.swift` has a comment naming the
   fixture and key path it came from. Re-derive each one from the new files,
   for example `python3 -c 'import json; print(json.load(open("chiefs_schedule.json"))["events"][0]["competitions"][0]["status"])'`,
   and update the assertion. Don't copy whatever the parser now outputs: a
   new value has to be traced to the feed.
5. The `.knownBug` tests are pinned to today's wrong output. If a refresh
   changes one of them, find out whether the feed changed or the bug did.
