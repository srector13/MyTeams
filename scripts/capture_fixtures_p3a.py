#!/usr/bin/env python3
"""Captures the P3-a ESPN fixtures for the nine leagues added in P3-a.

Writes myTeamsTests/Fixtures/<league>_<endpoint>[_<date|phase_event>].json
and prints one Markdown table row per file for FIXTURES.md.

    python3 scripts/capture_fixtures_p3a.py            # every league
    python3 scripts/capture_fixtures_p3a.py nba epl    # just these

Requests go through plain `curl` with its default User-Agent: ESPN's Akamai
front answers browser User-Agents with 403. Requests are spaced 0.5 s apart,
and a 403 or 429 is retried once after 5 s.

Bulky feeds are trimmed, keeping feed order and every other key; each kept
element is unchanged. Trimmed files are re-serialised compactly
(separators=(',', ':'), ensure_ascii=False); every other file is written
byte-for-byte as ESPN returned it.
"""

import datetime
import json
import os
import subprocess
import sys
import time

SITE = "https://site.api.espn.com/apis/site/v2/sports"
# Standings live under /apis/v2 — the /apis/site/v2 variant is an empty stub.
STANDINGS = "https://site.api.espn.com/apis/v2/sports"

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "myTeamsTests", "Fixtures")

# key: (path, sample team id, scoreboard date, summary event id, standings group)
LEAGUES = {
    "nba": ("basketball/nba", "1", "20261003", "401902644", None),
    "wnba": ("basketball/wnba", "20", "20260814", "401857143", None),
    "nhl": ("hockey/nhl", "25", "20260919", "401881922", None),
    "ncaaf": ("football/college-football", "2305", "20260829", "401864494", "80"),
    "ncaaw": ("basketball/womens-college-basketball", "2305", "20261102", "401926040", "50"),
    "epl": ("soccer/eng.1", "359", "20260821", "401879301", None),
    "laliga": ("soccer/esp.1", "83", "20260815", "401882926", None),
    "ligamx": ("soccer/mex.1", "227", "20260815", "401877018", None),
    "nwsl": ("soccer/usa.nwsl", "21422", "20260814", "401853969", None),
}

KEEP_TEAMS = 15
KEEP_SCOREBOARD_EVENTS = 3
KEEP_SCHEDULE_EVENTS = 12
# The college standings trees run to megabytes (each entry carries ~20 stat
# objects). Keep these conference children, by abbreviation: Kansas's Big 12,
# plus Sun Belt for FBS (the one conference split into divisions, so a
# grandchild level) and America East for D-I (the feed's first child).
KEEP_STANDINGS_CHILDREN = {
    "ncaaf": ["big12", "belt"],
    "ncaaw": ["aeast", "big12"],
}

# A rankings document carries every poll (five for FBS), each with a $ref
# season blob per rank. Keep the AP poll plus the first other poll, each
# cut to this many ranks.
KEEP_RANKS = 25

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
            ["curl", "-s", "-w", "\n%{http_code}", url],
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


def trim_teams(document, keep_id):
    teams = document["sports"][0]["leagues"][0]["teams"]
    if len(teams) <= KEEP_TEAMS:
        return None
    kept = teams[:KEEP_TEAMS - 1]
    if not any(t["team"]["id"] == keep_id for t in kept):
        kept += [t for t in teams if t["team"]["id"] == keep_id]
    else:
        kept = teams[:KEEP_TEAMS]
    document["sports"][0]["leagues"][0]["teams"] = kept
    return f"{len(teams)} → {len(kept)} teams"


def trim_events(document, limit, keep_ids):
    """Keeps the first events, plus any in keep_ids, up to about `limit`."""
    events = document["events"]
    if len(events) <= limit:
        return None
    wanted = [e for e in events if e.get("id") in keep_ids]
    kept = [e for e in events if e.get("id") not in keep_ids][:max(limit - len(wanted), 0)]
    kept_ids = {e.get("id") for e in kept + wanted}
    document["events"] = [e for e in events if e.get("id") in kept_ids]
    # The scoreboard repeats its events under leagues[0]; the app reads the
    # top-level list, so the copy is dropped rather than left out of step.
    for league in document.get("leagues", []):
        league.pop("events", None)
    return f"{len(events)} → {len(document['events'])} events"


def trim_standings(document, keep_abbreviations):
    children = document["children"]
    kept = [c for c in children if c.get("abbreviation") in keep_abbreviations]
    missing = set(keep_abbreviations) - {c.get("abbreviation") for c in kept}
    assert not missing, f"standings children not found: {missing}"
    document["children"] = kept
    return f"{len(children)} → {len(kept)} children"


def trim_rankings(document):
    """Keeps the AP poll (`type == "ap"`) and the first other poll, in feed
    order, each cut to its first KEEP_RANKS ranks; every key is kept."""
    polls = document["rankings"]
    ap = next((p for p in polls if p.get("type") == "ap"), None)
    other = next((p for p in polls if p is not ap), None)
    kept = [p for p in polls if p is ap or p is other]
    ranks_before = sum(len(p.get("ranks", [])) for p in kept)
    for poll in kept:
        poll["ranks"] = poll.get("ranks", [])[:KEEP_RANKS]
    document["rankings"] = kept
    ranks_after = sum(len(p["ranks"]) for p in kept)
    return f"{len(polls)} → {len(kept)} polls, {ranks_before} → {ranks_after} ranks"


def summary_phase(document):
    state = document.get("header", {}).get("competitions", [{}])[0].get("status", {}).get("type", {}).get("state")
    return {"pre": "pregame", "in": "live", "post": "final"}.get(state, "unknown")


def validate(name, document, endpoint):
    """Raises unless the document is a non-trivial example of its endpoint."""
    if endpoint == "teams":
        count = len(document["sports"][0]["leagues"][0]["teams"])
        assert count > 0, name
        return f"teams={count}"
    if endpoint in ("schedule", "scoreboard"):
        assert "events" in document, name
        return f"events={len(document['events'])}"
    if endpoint == "roster":
        athletes = document["athletes"]
        assert athletes, name
        grouped = isinstance(athletes[0], dict) and "items" in athletes[0]
        count = sum(len(g["items"]) for g in athletes) if grouped else len(athletes)
        return f"athletes={count} shape={'grouped' if grouped else 'flat'}"
    if endpoint == "news":
        assert "articles" in document, name
        return f"articles={len(document['articles'])}"
    if endpoint == "standings":
        children = document.get("children", [])
        assert len(children) >= 1, name

        def entries(node):
            return len(node.get("standings", {}).get("entries", [])) + sum(entries(c) for c in node.get("children", []))
        return f"children={len(children)} entries={entries(document)}"
    if endpoint == "rankings":
        polls = document["rankings"]
        ranked = [p for p in polls if p.get("ranks")]
        assert ranked, name
        return "polls=" + ",".join(f"{p.get('type')}:{len(p.get('ranks', []))}" for p in polls)
    if endpoint == "summary":
        assert "header" in document and "boxscore" in document, name
        return f"phase={summary_phase(document)}"
    raise ValueError(endpoint)


def capture(key):
    path, team, day, event, group = LEAGUES[key]
    college_hoops = "college" in path and path.startswith("basketball/")
    teams_query = "?limit=1000" + ("&groups=50" if "college" in path else "")
    standings_query = f"?group={group}" if group else ""
    requests = [
        ("teams", f"{key}_teams", f"{SITE}/{path}/teams{teams_query}"),
        ("schedule", f"{key}_schedule", f"{SITE}/{path}/teams/{team}/schedule"),
        ("roster", f"{key}_roster", f"{SITE}/{path}/teams/{team}/roster"),
        ("news", f"{key}_news", f"{SITE}/{path}/news?team={team}&limit=25"),
        ("scoreboard", f"{key}_scoreboard_{day}",
         f"{SITE}/{path}/scoreboard?dates={day}" + ("&groups=50&limit=1000" if college_hoops else "")),
        ("standings", f"{key}_standings", f"{STANDINGS}/{path}/standings{standings_query}"),
        ("summary", None, f"{SITE}/{path}/summary?event={event}"),
    ]
    if "college" in path:
        requests.append(("rankings", f"{key}_rankings", f"{SITE}/{path}/rankings"))
    rows = []
    for endpoint, name, url in requests:
        body = fetch(url)
        captured = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        document = json.loads(body)
        note = None
        if endpoint == "teams":
            note = trim_teams(document, team)
        elif endpoint == "scoreboard":
            note = trim_events(document, KEEP_SCOREBOARD_EVENTS, {event})
        elif endpoint == "schedule":
            note = trim_events(document, KEEP_SCHEDULE_EVENTS, {event})
        elif endpoint == "standings" and key in KEEP_STANDINGS_CHILDREN:
            note = trim_standings(document, KEEP_STANDINGS_CHILDREN[key])
        elif endpoint == "rankings":
            note = trim_rankings(document)
        elif endpoint == "summary":
            name = f"{key}_summary_{summary_phase(document)}_{event}"
        data = compact(document) if note else body
        # Round-trip what is written, not what was fetched.
        written = json.loads(data)
        summary = validate(name, written, endpoint)
        with open(os.path.join(OUT, f"{name}.json"), "wb") as f:
            f.write(data)
        print(f"ok {name}.json {len(body)}→{len(data)} bytes {summary}" + (f" (trimmed {note})" if note else ""),
              file=sys.stderr)
        rows.append(f"| `{name}.json` | `{url}` | {captured} | {summary}{'; trimmed ' + note if note else ''} |")
    return rows


def main():
    keys = sys.argv[1:] or list(LEAGUES)
    rows = []
    for key in keys:
        rows += capture(key)
    print("| File | URL | Captured | Contents |")
    print("|---|---|---|---|")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
