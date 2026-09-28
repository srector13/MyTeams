#!/usr/bin/env python3
"""Captures the P3-e ESPN fixtures: the finished games the cross-league
acceptance walkthrough needs, and a cup scoreboard for the live-score seam.

Writes myTeamsTests/Fixtures/<league>_<endpoint>[_<scope>].json and prints
one Markdown table row per file for FIXTURES.md.

    python3 scripts/capture_fixtures_p3e.py

P3-a's captures left three of the four walkthrough teams without a finished
game of their own: the Hawks' feed was all preseason (and its summary a
Heat–Raptors pregame), the NHL summary is a Maple Leafs game, and the NCAAF
one is USC's. This script adds each team's own final, the Hawks' 2025-26
schedule that lists theirs, and Arsenal's Champions League schedule and
match-day scoreboards (the Champions League's, and the Premier League's
empty one for the same day).

Client rules, trimming and validation are P3-a's (capture_fixtures_p3a.py).
"""

import datetime
import json
import os
import sys

sys.dont_write_bytecode = True  # no __pycache__ beside the scripts

from capture_fixtures_p3a import OUT, SITE, compact, fetch, summary_phase, trim_events, validate

KEEP_SCHEDULE_EVENTS = 12
KEEP_SCOREBOARD_EVENTS = 3

# (endpoint, name, URL, event to keep when trimming, who)
REQUESTS = [
    ("schedule", "nba_schedule_2026", f"{SITE}/basketball/nba/teams/1/schedule?season=2026", "401811028",
     "Hawks 2025-26 regular season"),
    ("summary", "nba_summary", f"{SITE}/basketball/nba/summary?event=401811028", None,
     "Pistons at Hawks, Apr 10 2026"),
    ("summary", "nhl_summary", f"{SITE}/hockey/nhl/summary?event=401879368", None,
     "Sharks at Ducks, preseason, Sep 20 2026"),
    ("summary", "ncaaf_summary", f"{SITE}/football/college-football/summary?event=401856769", None,
     "Kansas home opener, Sep 4 2026"),
    ("schedule", "ucl_schedule_359", f"{SITE}/soccer/uefa.champions/teams/359/schedule", None,
     "Arsenal in the Champions League"),
    ("scoreboard", "ucl_scoreboard_20260909", f"{SITE}/soccer/uefa.champions/scoreboard?dates=20260909",
     "401915423", "Champions League match day"),
    ("scoreboard", "epl_scoreboard_20260909", f"{SITE}/soccer/eng.1/scoreboard?dates=20260909", None,
     "Premier League, same day"),
]


def main():
    rows = []
    for endpoint, name, url, keep, who in REQUESTS:
        body = fetch(url)
        captured = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        document = json.loads(body)
        note = None
        if endpoint == "schedule":
            note = trim_events(document, KEEP_SCHEDULE_EVENTS, {keep})
        elif endpoint == "scoreboard":
            note = trim_events(document, KEEP_SCOREBOARD_EVENTS, {keep})
        elif endpoint == "summary":
            event = url.rsplit("=", 1)[1]
            name = f"{name}_{summary_phase(document)}_{event}"
        data = compact(document) if note else body
        written = json.loads(data)
        summary = validate(name, written, endpoint)
        if keep:
            assert any(e.get("id") == keep for e in written["events"]), f"{name}: {keep} not kept"
        with open(os.path.join(OUT, f"{name}.json"), "wb") as f:
            f.write(data)
        print(f"ok {name}.json {len(body)}→{len(data)} bytes {summary}" + (f" (trimmed {note})" if note else ""),
              file=sys.stderr)
        rows.append(f"| `{name}.json` | `{url}` | {captured} | {who}; {summary}{'; trimmed ' + note if note else ''} |")
    print("| File | URL | Captured | Contents |")
    print("|---|---|---|---|")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
