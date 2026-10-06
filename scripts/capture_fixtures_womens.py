#!/usr/bin/env python3
"""Captures the ESPN fixtures for the two European women's leagues added in
t_67da893e: the English Women's Super League (`eng.w.1`) and France's
Première Ligue (`fra.w.1`).

Writes myTeamsTests/Fixtures/<prefix>_<endpoint>[_<date|phase_event>].json
and prints one Markdown table row per file for FIXTURES.md.

    python3 scripts/capture_fixtures_womens.py            # both leagues
    python3 scripts/capture_fixtures_womens.py wsl        # just this one

The same eight files per league as BE-3, captured by BE-3's own `capture`
(and so P3-a's client, trimming and validation): see
capture_fixtures_be3.py.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import capture_fixtures_be3 as be3  # noqa: E402

# key: (path, sample team id, scoreboard date, summary event id)
LEAGUES = {
    "wsl": ("soccer/eng.w.1", "19970", "20261004", "401902895"),
    "premiere": ("soccer/fra.w.1", "19256", "20261003", "401885704"),
}


def main():
    be3.LEAGUES = LEAGUES
    keys = sys.argv[1:] or list(LEAGUES)
    rows = []
    for key in keys:
        rows += be3.capture(key)
    print("| File | URL | Captured | Contents |")
    print("|---|---|---|---|")
    print("\n".join(rows))


if __name__ == "__main__":
    main()
