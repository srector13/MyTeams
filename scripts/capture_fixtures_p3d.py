#!/usr/bin/env python3
"""Captures the P3-d ESPN fixtures: stat leaders, and the athlete documents
behind roster player statistics.

Writes myTeamsTests/Fixtures/<league>_<endpoint>[_<scope|athleteID>].json and
prints one Markdown table row per file for FIXTURES.md.

    python3 scripts/capture_fixtures_p3d.py              # everything
    python3 scripts/capture_fixtures_p3d.py leaders      # just the leaders
    python3 scripts/capture_fixtures_p3d.py athletes     # just the athletes
    python3 scripts/capture_fixtures_p3d.py gamelogs     # just the game logs

Requests go through plain `curl` with its default User-Agent (ESPN's Akamai
front answers browser User-Agents with 403), spaced 0.5 s apart; a 403 or 429
is retried once after 5 s. See capture_fixtures_p3a.py.

Leaders URLs are built the way `LeagueID.leadersURL` builds them:

    https://site.api.espn.com/apis/site/v3/sports/{path}/leaders?limit=N
        [&season=YYYY&seasontype=1]   soccer only: without them the feed answers
                                      with a playoff round, an all-star stub or 404
        [&team=ID]                    one team's leaders

Leaders documents repeat, per leader, arrays the app never reads: the
athlete's and team's `links` (a dozen URLs each), the team's `logos`, and
(US leagues) a `teams` list. The script drops those four and nothing else,
and re-serialises compactly (separators=(',', ':'), ensure_ascii=False).
Athlete and splits documents are written byte-for-byte.

Game logs (`.../athletes/{id}/gamelog`) lose the `links` arrays on each
event, its opponent and its team, and nothing else, and are re-serialised
the same compact way.
"""

import datetime
import json
import os
import subprocess
import sys
import time

SITE_V3 = "https://site.api.espn.com/apis/site/v3/sports"
COMMON = "https://site.web.api.espn.com/apis/common/v3/sports"

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "myTeamsTests", "Fixtures")

LEADERS_LIMIT = 5

# key: (path, soccer season or None). Soccer seasons are the starting year
# (`SeasonNaming.startingYear` / `.calendarYear`) on 2026-09-28.
LEAGUES = {
    "ncaam": ("basketball/mens-college-basketball", None),
    "nfl": ("football/nfl", None),
    "mlb": ("baseball/mlb", None),
    "mls": ("soccer/usa.1", 2026),
    "nba": ("basketball/nba", None),
    "wnba": ("basketball/wnba", None),
    "ncaaw": ("basketball/womens-college-basketball", None),
    "nhl": ("hockey/nhl", None),
    "ncaaf": ("football/college-football", None),
    "epl": ("soccer/eng.1", 2026),
    "laliga": ("soccer/esp.1", 2026),
    "ligamx": ("soccer/mex.1", 2026),
    "nwsl": ("soccer/usa.nwsl", 2026),
}

# Team leaders: one team per sport kind the leaders screen labels differently.
TEAM_LEADERS = [("nba", "1"), ("nhl", "25"), ("epl", "359"), ("ncaaf", "2305")]

# (league key, endpoint, athlete id, who): athlete documents for the roster
# player sheets. Each is a sample team's player (see P3-a's sample teams).
ATHLETES = [
    ("epl", "athlete", "280555", "Bukayo Saka, Arsenal forward"),
    ("laliga", "athlete", "231050", "Raphinha, Barcelona forward"),
    ("ligamx", "athlete", "93184", "Henry Martín, América forward"),
    ("nwsl", "athlete", "402432", "Maiara Niehues, NWSL 21422 midfielder"),
    ("mls", "athlete", "293695", "Calvin Harris, Sporting KC forward"),
    ("nhl", "splits", "5080145", "Cutter Gauthier, Ducks left wing"),
    ("nhl", "splits", "4588165", "Lukas Dostal, Ducks goaltender"),
    ("nba", "splits", "4869342", "Dyson Daniels, Hawks guard"),
    ("wnba", "splits", "3058901", "Allisha Gray, Dream guard"),
    ("ncaaw", "splits", "5108548", "Sania Copeland, Kansas guard"),
    ("ncaaf", "splits", "5079604", "Isaiah Marshall, Kansas quarterback"),
]

# (league key, athlete id, who): athlete game logs for the player sheet's
# "Last 5 games" card (R-10), one or two per sport.
GAMELOGS = [
    ("nfl", "3139477", "Patrick Mahomes, Chiefs quarterback"),
    ("nba", "4869342", "Dyson Daniels, Hawks guard"),
    ("mlb", "42403", "Bobby Witt Jr., Royals shortstop"),
    ("mlb", "5136077", "Royals relief pitcher"),
    ("nhl", "5080145", "Cutter Gauthier, Ducks left wing"),
    ("nhl", "4588165", "Lukas Dostal, Ducks goaltender"),
    ("epl", "280555", "Bukayo Saka, Arsenal forward"),
]

_last_request = 0.0


def fetch(url):
    """The response body, after pacing; retries a 403/429 once after 5 s."""
    global _last_request
    for attempt in range(2):
        wait = 0.5 - (time.monotonic() - _last_request)
        if wait > 0:
            time.sleep(wait)
        _last_request = time.monotonic()
        result = subprocess.run(
            ["curl", "-s", "--compressed", "-w", "\n%{http_code}", url],
            capture_output=True, check=True,
        )
        body, _, code = result.stdout.rpartition(b"\n")
        code = int(code)
        if code == 200:
            return body
        if code in (403, 429) and attempt == 0:
            print(f"  {code} for {url}; retrying in 5 s", file=sys.stderr)
            time.sleep(5)
            continue
        raise RuntimeError(f"HTTP {code} for {url}")


def compact(document):
    return json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def leaders_url(path, soccer_season, team=None):
    query = [f"limit={LEADERS_LIMIT}"]
    if soccer_season:
        query += [f"season={soccer_season}", "seasontype=1"]
    if team:
        query.append(f"team={team}")
    return f"{SITE_V3}/{path}/leaders?" + "&".join(query)


def strip_unread(document):
    """Drops what the app never reads from each leader: the athlete's and
    team's `links`, the team's `logos`, and the `teams` list the US leagues
    repeat per leader. Returns how many arrays were dropped."""
    dropped = 0
    for category in document["leaders"]["categories"]:
        for leader in category.get("leaders", []):
            for owner, key in (("athlete", "links"), ("team", "links"), ("team", "logos")):
                if key in leader.get(owner, {}):
                    del leader[owner][key]
                    dropped += 1
            if "teams" in leader:
                del leader["teams"]
                dropped += 1
    return dropped


def validate_leaders(name, document, team):
    categories = document["leaders"]["categories"]
    led = [c for c in categories if c.get("leaders")]
    assert led, f"{name}: no category has leaders"
    empty = [c["name"] for c in categories if not c.get("leaders")]
    for category in led:
        if team:
            teams = {leader.get("team", {}).get("id") for leader in category["leaders"]}
            assert teams == {team}, f"{name}: {category.get('name')} lists teams {teams}"
    season = document["requestedSeason"]
    return (f"season={season['year']} ({season['type']['name']}) categories={len(categories)}"
            + (f" (empty: {', '.join(empty)})" if empty else "")
            + f" first={led[0]['name']}: {led[0]['leaders'][0]['athlete']['displayName']} "
            f"{led[0]['leaders'][0]['displayValue']}")


def validate_athlete(name, document, endpoint):
    if endpoint == "athlete":
        summary = document["athlete"]["statsSummary"]
        stats = summary["statistics"]
        assert stats, name
        return f"{summary['displayName']}: " + ", ".join(f"{s['name']}={s['displayValue']}" for s in stats)
    names = document["names"]
    rows = document["splitCategories"][0]["splits"]
    assert names and all(len(r["stats"]) == len(names) for r in rows), name
    return f"names={len(names)} splits=" + "/".join(r["displayName"] for r in rows[:4])


def capture_leaders():
    rows = []
    scopes = [(key, None) for key in LEAGUES] + TEAM_LEADERS
    for key, team in scopes:
        path, soccer_season = LEAGUES[key]
        name = f"{key}_leaders" + (f"_team_{team}" if team else "")
        url = leaders_url(path, soccer_season, team)
        body = fetch(url)
        captured = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        document = json.loads(body)
        dropped = strip_unread(document)
        data = compact(document)
        summary = validate_leaders(name, json.loads(data), team)
        with open(os.path.join(OUT, f"{name}.json"), "wb") as f:
            f.write(data)
        print(f"ok {name}.json {len(body)}→{len(data)} bytes {summary}", file=sys.stderr)
        rows.append(f"| `{name}.json` | `{url}` | {captured} | {summary}; {len(body)}→{len(data)} bytes |")
    return rows


def capture_athletes():
    rows = []
    for key, endpoint, athlete, who in ATHLETES:
        path, _ = LEAGUES[key]
        url = f"{COMMON}/{path}/athletes/{athlete}" + ("/splits" if endpoint == "splits" else "")
        name = f"{key}_{endpoint}_{athlete}"
        body = fetch(url)
        captured = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        summary = validate_athlete(name, json.loads(body), endpoint)
        with open(os.path.join(OUT, f"{name}.json"), "wb") as f:
            f.write(body)
        print(f"ok {name}.json {len(body)} bytes {summary}", file=sys.stderr)
        rows.append(f"| `{name}.json` | `{url}` | {captured} | {who}. {summary} |")
    return rows


def validate_gamelog(name, document):
    """Summarises a game log: its season types and categories (with event
    counts), the column `names`, and the first event's metadata."""
    names = document.get("names") or []
    events = document.get("events") or {}
    seasons = []
    for season in document.get("seasonTypes") or []:
        counted = []
        for category in season.get("categories") or []:
            rows = category.get("events") or []
            assert all(len(r.get("stats", [])) == len(names) for r in rows), f"{name}: row width"
            counted.append(f"{category.get('displayName') or category.get('type')}x{len(rows)}")
        seasons.append(f"{season.get('displayName')} [{', '.join(counted)}]")
    first = next(iter(events.values()), {})
    sample = (f" first={first.get('gameDate')} {first.get('atVs')} "
              f"{first.get('opponent', {}).get('abbreviation')} {first.get('gameResult')} {first.get('score')}"
              if first else "")
    return f"names={names} events={len(events)} seasonTypes={'; '.join(seasons) or 'none'}" + sample


def strip_gamelog_links(document):
    """Drops the `links` arrays on each event, its `opponent` and its `team`
    (a dozen URLs apiece, never read; a season of MLB games is otherwise
    over a megabyte). Returns how many arrays were dropped."""
    dropped = 0
    for event in (document.get("events") or {}).values():
        for owner in (event, event.get("opponent") or {}, event.get("team") or {}):
            if "links" in owner:
                del owner["links"]
                dropped += 1
    return dropped


def capture_gamelogs():
    rows = []
    for key, athlete, who in GAMELOGS:
        path, _ = LEAGUES[key]
        url = f"{COMMON}/{path}/athletes/{athlete}/gamelog"
        name = f"{key}_gamelog_{athlete}"
        body = fetch(url)
        captured = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        document = json.loads(body)
        strip_gamelog_links(document)
        data = compact(document)
        summary = validate_gamelog(name, json.loads(data))
        with open(os.path.join(OUT, f"{name}.json"), "wb") as f:
            f.write(data)
        print(f"ok {name}.json {len(body)}→{len(data)} bytes {summary}", file=sys.stderr)
        rows.append(f"| `{name}.json` | `{url}` | {captured} | {who}. {summary}; {len(body)}→{len(data)} bytes |")
    return rows


def main():
    parts = sys.argv[1:] or ["leaders", "athletes", "gamelogs"]
    rows = []
    if "leaders" in parts:
        rows += capture_leaders()
    if "athletes" in parts:
        rows += capture_athletes()
    if "gamelogs" in parts:
        rows += capture_gamelogs()
    print("| File | URL | Captured | Contents |")
    print("|---|---|---|---|")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
