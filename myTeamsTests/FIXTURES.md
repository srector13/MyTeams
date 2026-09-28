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
