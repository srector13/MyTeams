#!/usr/bin/env python3
"""Captures the BE-3 ESPN fixtures for Bundesliga, Serie A, Ligue 1 and the
Champions League as a league.

Writes myTeamsTests/Fixtures/<prefix>_<endpoint>[_<date|phase_event>].json
and prints one Markdown table row per file for FIXTURES.md.

    python3 scripts/capture_fixtures_be3.py               # every league
    python3 scripts/capture_fixtures_be3.py bundes        # just this one

Client rules, trimming and validation are imported from
capture_fixtures_p3a.py. On top of P3-a's seven files per league, each
league also gets `<prefix>_schedule_fixtures`: the sample team's schedule
with `?fixture=true`, which lists the unplayed matches the bare schedule
leaves out (see ScheduleDownload's soccer merge). It is trimmed to the first
10 events.
"""

import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capture_fixtures_p3a import (  # noqa: E402
    OUT, SITE, STANDINGS, compact, fetch, summary_phase, trim_events, trim_teams, validate,
)

# key: (path, sample team id, scoreboard date, summary event id)
LEAGUES = {
    "bundes": ("soccer/ger.1", "132", "20260918", "401884790"),
    "seriea": ("soccer/ita.1", "110", "20260919", "401874753"),
    "ligue1": ("soccer/fra.1", "160", "20260920", "401876449"),
    "uclleague": ("soccer/uefa.champions", "359", "20260909", "401915423"),
}

KEEP_SCOREBOARD_EVENTS = 3
KEEP_SCHEDULE_EVENTS = 10


def capture(key):
    path, team, day, event = LEAGUES[key]
    requests = [
        ("teams", f"{key}_teams", f"{SITE}/{path}/teams?limit=1000"),
        ("schedule", f"{key}_schedule", f"{SITE}/{path}/teams/{team}/schedule"),
        ("schedule", f"{key}_schedule_fixtures", f"{SITE}/{path}/teams/{team}/schedule?fixture=true"),
        ("roster", f"{key}_roster", f"{SITE}/{path}/teams/{team}/roster"),
        ("news", f"{key}_news", f"{SITE}/{path}/news?team={team}&limit=25"),
        ("scoreboard", f"{key}_scoreboard_{day}", f"{SITE}/{path}/scoreboard?dates={day}"),
        ("standings", f"{key}_standings", f"{STANDINGS}/{path}/standings"),
        ("summary", None, f"{SITE}/{path}/summary?event={event}"),
    ]
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
        elif endpoint == "summary":
            name = f"{key}_summary_{summary_phase(document)}_{event}"
        data = compact(document) if note else body
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
