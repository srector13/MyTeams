#!/usr/bin/env python3
"""Python port of the parsers CrossLeagueAcceptanceTests.swift drives, run
over the same fixtures, checking the same golden values.

    python3 scripts/verify_acceptance_p3e.py          # check, print PASS/FAIL
    python3 scripts/verify_acceptance_p3e.py --dump   # print what the port reads

There is no Swift toolchain on the capture host, so every exact value in the
acceptance walkthrough is derived here first, by a line-for-line port of the
Swift reader it pins (named beside each function). A value that disagrees
with the Swift test is a bug in one of the two.

Four teams, five sections each: schedule, roster (with a season line), news,
standings, and the box score of a finished game.
"""

import datetime
import json
import os
import sys

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "myTeamsTests", "Fixtures")


def load(name):
    with open(os.path.join(FIXTURES, f"{name}.json"), encoding="utf-8") as f:
        return json.load(f)


# MARK: - JSON coercions (JSON.swift)

def string_value(node):
    if isinstance(node, bool):
        return "true" if node else "false"
    if isinstance(node, str):
        return node
    if isinstance(node, (int, float)):
        if float(node) == round(float(node)) and abs(node) < 1e15:
            return str(int(node))
        return repr(float(node))
    return ""


def number(node):
    if isinstance(node, bool):
        return 1.0 if node else 0.0
    if isinstance(node, (int, float)):
        return float(node)
    if isinstance(node, str):
        # NSDecimalNumber(string:) reads a leading numeric run.
        run = ""
        for i, ch in enumerate(node.strip()):
            if ch.isdigit() or ch == "." or (i == 0 and ch in "+-"):
                run += ch
            else:
                break
        try:
            return float(run)
        except ValueError:
            return None
    return None


def int_value(node):
    n = number(node)
    return int(n) if n is not None else 0


def get(node, *path):
    for step in path:
        if isinstance(step, int):
            if isinstance(node, list) and 0 <= step < len(node):
                node = node[step]
            else:
                return None
        else:
            if isinstance(node, dict) and step in node:
                node = node[step]
            else:
                return None
    return node


def bool_value(node):
    if isinstance(node, bool):
        return node
    if isinstance(node, (int, float)):
        return node != 0
    if isinstance(node, str):
        return node.lower() in ("true", "yes", "y", "t", "1")
    return False


# MARK: - Schedule (DownloadScheduleData.swift parseGame / mergeSchedules)

def parse_date(raw):
    try:
        return datetime.datetime.strptime(raw.replace("T", " ").replace("Z", ""), "%Y-%m-%d %H:%M").replace(
            tzinfo=datetime.timezone.utc)
    except ValueError:
        return None


def parse_game(event, team_id, name_field, pointer, feed_competition=None, sport="soccer"):
    comps = event.get("competitions") or []
    played = next((c for c in comps if any(get(x, "team", "id") == team_id for x in c.get("competitors", []))),
                  comps[0] if comps else None)
    g = dict(team="", opponent="", opponentID="", score="", opponentScore="", location="", gameHome=False,
             gameID="", gameWin=False, completed=False, cancelled=False, postponed=False, gameClock="",
             gamePeriod="", halftime=False, channel="", date=None)
    if played:
        g["location"] = string_value(get(played, "venue", "fullName"))
        g["gameID"] = string_value(played.get("id"))
        g["date"] = parse_date(string_value(event.get("date")))
        status = played.get("status", {})
        g["completed"] = bool_value(get(status, "type", "completed"))
        g["halftime"] = string_value(get(status, "type", "description")) == "Halftime"
        g["gameClock"] = string_value(status.get("displayClock"))
        g["gamePeriod"] = string_value(status.get("period"))
        detail = string_value(get(status, "type", "detail"))
        g["postponed"] = detail == "Postponed"
        g["cancelled"] = detail == "Canceled"
        g["channel"] = string_value(get(played, "broadcasts", 0, "media", "shortName")) or "TBD"
        for c in played.get("competitors", []):
            if get(c, "team", "id") == team_id:
                g["team"] = string_value(get(c, "team", name_field))
                g["gameHome"] = c.get("homeAway") == "home"
                g["gameWin"] = bool_value(c.get("winner"))
                g["score"] = string_value(get(c, "score", "displayValue"))
            else:
                g["opponent"] = string_value(get(c, "team", name_field))
                g["opponentID"] = string_value(get(c, "team", "id"))
                g["opponentScore"] = string_value(get(c, "score", "displayValue"))
    g["eventID"] = string_value(event.get("id")) or g["gameID"]
    slug = string_value(get(event, "league", "slug"))
    g["competition"] = f"{sport}/{slug}" if slug else feed_competition
    g["pointer"] = pointer
    return g


def parse_schedule(doc, team_id, name_field, competition=None, sport="soccer"):
    return [parse_game(e, team_id, name_field, i, competition, sport) for i, e in enumerate(doc["events"])]


def merge_schedules(league_doc, cups, team_id, name_field, league_path):
    games = parse_schedule(league_doc, team_id, name_field, league_path)
    seen = {g["eventID"] for g in games}
    season = get(league_doc, "season", "year")
    for competition, doc in cups:
        for event in doc["events"]:
            event_season = get(event, "season", "year")
            if season is not None and event_season is not None and event_season != season:
                continue
            g = parse_game(event, team_id, name_field, 0, competition)
            if g["eventID"] not in seen:
                seen.add(g["eventID"])
                games.append(g)
    ordered = [g for _, g in sorted(enumerate(games), key=lambda p: (p[1]["date"], p[0]))]
    for i, g in enumerate(ordered):
        g["pointer"] = i
    return ordered


def is_draw(g):
    if g["gameWin"]:
        return False
    try:
        return int(g["score"]) == int(g["opponentScore"])
    except ValueError:
        return False


def schedule_record(games, league_path, fmt, regulation=None):
    """Record.swift scheduleRecord (no MLS date rule for these four)."""
    lg = [g for g in games if g["competition"] in (None, league_path)]
    wins = sum(1 for g in lg if g["gameWin"])
    draws = sum(1 for g in lg if not g["gameWin"] and not g["cancelled"] and not g["postponed"]
                and is_draw(g) and g["completed"])
    losses = sum(1 for g in lg if not g["gameWin"] and not g["cancelled"] and not g["postponed"]
                 and not is_draw(g) and g["completed"])
    if fmt == "winLossOvertimeLoss":
        otl = sum(1 for g in lg if g["completed"] and not g["gameWin"] and not is_draw(g)
                  and not g["cancelled"] and not g["postponed"] and int_value(g["gamePeriod"]) > regulation)
        return f"{wins}-{losses - otl}-{otl}"
    if fmt == "winLossTie":
        return f"{wins}-{losses}-{draws}"
    return f"{wins}-{losses}-{draws}" if draws else f"{wins}-{losses}"


def next_game(games):
    """GetNextGame.swift getNextGame, no date rule."""
    pointer = 0
    for g in games:
        if g["completed"] or g["cancelled"] or g["postponed"]:
            pointer += 1
        else:
            break
    return min(pointer, len(games) - 1)


# MARK: - Rosters (DownloadRosterData.swift)

def athletes_flat(doc):
    out = []
    for entry in doc.get("athletes", []):
        out += entry["items"] if isinstance(entry, dict) and "items" in entry else [entry]
    return out


def sort_by_last(players):
    # Swift's `<` on String compares by Unicode scalars, as Python does.
    return sorted(players, key=lambda p: p["lastName"])


def hometown(a, empty_na=False, region_fallback=True):
    city = string_value(get(a, "birthPlace", "city"))
    state = string_value(get(a, "birthPlace", "state"))
    region = state if state or not region_fallback else string_value(get(a, "birthPlace", "country"))
    if empty_na and not city:
        return "N/A"
    return f"{city}, {region}"


def basketball_roster(doc):
    return sort_by_last([dict(playerID=string_value(a.get("id")), name=string_value(a.get("fullName")),
                              number=string_value(a.get("jersey")),
                              position=string_value(get(a, "position", "displayName")),
                              height=string_value(a.get("displayHeight")),
                              hometown=hometown(a), lastName=string_value(a.get("lastName")))
                         for a in doc["athletes"]])


def hockey_roster(doc):
    return sort_by_last([dict(playerID=string_value(a.get("id")), name=string_value(a.get("fullName")),
                              number=string_value(a.get("jersey")),
                              position=string_value(get(a, "position", "displayName")),
                              shoots=string_value(get(a, "hand", "displayValue")),
                              hometown=hometown(a, empty_na=True), lastName=string_value(a.get("lastName")))
                         for a in athletes_flat(doc)])


def football_roster(doc):
    out = []
    for group in doc["athletes"]:
        unit = string_value(group.get("position"))
        for a in group.get("items", []):
            city = string_value(get(a, "birthPlace", "city"))
            state = string_value(get(a, "birthPlace", "state"))
            out.append(dict(playerID=string_value(a.get("id")), name=string_value(a.get("fullName")),
                            number=string_value(a.get("jersey")),
                            position=string_value(get(a, "position", "displayName")),
                            hometown="N/A" if not city else f"{city}, {state}",
                            team=unit, lastName=string_value(a.get("lastName"))))
    return sort_by_last(out)


def soccer_roster(doc):
    out = []
    for a in doc["athletes"]:
        values = {}
        for cat in get(a, "statistics", "splits", "categories") or []:
            for s in cat.get("stats", []):
                values.setdefault(string_value(s.get("name")), int_value(s.get("value")))
        out.append(dict(playerID=string_value(a.get("id")), name=string_value(a.get("fullName")),
                        number=string_value(a.get("jersey")),
                        position=string_value(get(a, "position", "displayName")),
                        appearances=values.get("appearances", 0), subIns=values.get("subIns", 0),
                        totalGoals=values.get("totalGoals", 0), goalAssists=values.get("goalAssists", 0),
                        hasSeasonStats=bool(values), lastName=string_value(a.get("lastName"))))
    return sort_by_last(out)


# MARK: - Player season lines (DownloadAthleteData.swift)

SEASON_SPLITS = {"All Splits", "Season"}


def splits_season_line(doc):
    names = [string_value(n) for n in doc.get("names", [])]
    rows = get(doc, "splitCategories", 0, "splits") or []
    season = next((r for r in rows if r.get("displayName") in SEASON_SPLITS), rows[0] if len(rows) == 1 else None)
    values = [string_value(v) for v in (season or {}).get("stats", [])]
    if not names or len(names) != len(values):
        return {}
    line = {}
    for n, v in zip(names, values):
        line.setdefault(n, v)
    return line


HOCKEY_SKATER = ["games", "goals", "assists", "points", "plusMinus", "penaltyMinutes", "shotsTotal",
                 "powerPlayGoals", "powerPlayAssists", "shortHandedGoals", "gameWinningGoals", "faceoffPercent",
                 "timeOnIcePerGame"]
HOCKEY_GOALIE = ["gameStarted", "wins", "losses", "overtimeLosses", "goalsAgainst", "avgGoalsAgainst",
                 "shotsAgainst", "saves", "savePct", "shutouts", "timeOnIcePerGame"]


def hockey_sheet(line):
    order = HOCKEY_GOALIE if "savePct" in line else HOCKEY_SKATER
    return [line[n] for n in order if n in line]


# MARK: - News (DownloadNewsData.swift parseNews)

def parse_news(doc):
    out = []
    for a in doc.get("articles", []):
        title = a.get("headline")
        href = string_value(get(a, "links", "web", "href"))
        published = string_value(a.get("published"))
        if not isinstance(title, str) or not title.strip() or not href.lower().startswith("https:"):
            continue
        try:
            datetime.datetime.strptime(published, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            continue
        if any(o["title"] == title or o["url"] == href for o in out):
            continue
        out.append(dict(title=title, url=href, published=published))
    return out


# MARK: - Standings (Standings.swift parseStandingsEntry, for one row)

def standings_row(doc, team_id):
    def walk(node, found):
        table = node.get("standings", {})
        for i, entry in enumerate(table.get("entries", []) or []):
            if get(entry, "team", "id") == team_id:
                found.append((node, i, entry))
        for child in node.get("children", []):
            walk(child, found)
    found = []
    walk(doc, found)
    node, index, entry = found[0]
    by_type, by_name = {}, {}
    for s in entry.get("stats", []):
        by_type.setdefault(string_value(s.get("type")).lower(), s)
        by_name.setdefault(string_value(s.get("name")).lower(), s)

    def stat(k):
        return by_type.get(k) or by_name.get(k)

    def i(k):
        s = stat(k)
        if s is None:
            return None
        if isinstance(s.get("value"), (int, float)) and not isinstance(s.get("value"), bool):
            return int(s["value"])
        try:
            return int(string_value(s.get("displayValue")).replace("+", ""))
        except ValueError:
            return None

    def d(k):
        s = stat(k)
        return string_value(s.get("displayValue")) if s else ""
    rank = i("rank") if i("rank") is not None else i("playoffseed")
    return dict(group=node.get("name"), index=index, wins=i("wins"), losses=i("losses"), ties=i("ties"),
                otlosses=i("otlosses"), points=i("points"), total=d("total"), rank=rank if rank and rank > 0 else None,
                gamesBehind=d("gamesbehind"), streak=d("streak"), vsconf=d("vsconf"),
                pointdifferential=d("pointdifferential"), note=get(entry, "note", "description") or "")


# MARK: - Box scores (DownloadGameData.swift, HockeyBoxScore.swift, Linescore.swift)

def boxscore_statistic(statistics, name):
    for section in statistics or []:
        if section.get("name") == name:
            return section
        for s in section.get("stats", []) or []:
            if s.get("name") == name:
                return s
    return None


def stat_display(statistics, name):
    s = boxscore_statistic(statistics, name)
    return s.get("displayValue") if s else None


def header_competitors(summary):
    return get(summary, "header", "competitions", 0, "competitors") or []


def basketball_box(summary, followed_id, followed_is_home):
    comps = header_competitors(summary)

    def total(i):
        return sum(int_value(p.get("displayValue")) for p in comps[i].get("linescores", []))
    first = get(comps[0], "team", "id") == followed_id
    team_score, opp_score = total(0 if first else 1), total(1 if first else 0)
    lines = []
    for t in summary["boxscore"]["teams"]:
        st = t.get("statistics")
        lines.append(dict(name=get(t, "team", "name"),
                          fg=string_value(stat_display(st, "fieldGoalsMade-fieldGoalsAttempted")),
                          fgPct=number(stat_display(st, "fieldGoalPct")) or 0,
                          three=string_value(stat_display(st, "threePointFieldGoalsMade-threePointFieldGoalsAttempted")),
                          threePct=number(stat_display(st, "threePointFieldGoalPct")) or 0,
                          ft=string_value(stat_display(st, "freeThrowsMade-freeThrowsAttempted")),
                          ftPct=number(stat_display(st, "freeThrowPct")) or 0,
                          oreb=int_value(stat_display(st, "offensiveRebounds")),
                          dreb=int_value(stat_display(st, "defensiveRebounds")),
                          ast=int_value(stat_display(st, "assists")), stl=int_value(stat_display(st, "steals")),
                          blk=int_value(stat_display(st, "blocks")), to=int_value(stat_display(st, "turnovers")),
                          pf=int_value(stat_display(st, "fouls"))))
    away, home = lines[0], lines[1]

    def row(title, f):
        return (title, f(home), f(away))
    rows = [
        row("Field Goals", lambda l: l["fg"].replace("-", "/")),
        row("Field Goal %", lambda l: f"{int(l['fgPct'])}%"),
        row("Three Points", lambda l: l["three"].replace("-", "/")),
        row("Three Point %", lambda l: f"{int(l['threePct'])}%"),
        row("Free Throws", lambda l: l["ft"].replace("-", "/")),
        row("Free Throw %", lambda l: f"{int(l['ftPct'])}%"),
        row("Offensive Rebounds", lambda l: str(l["oreb"])),
        row("Defensive Rebounds", lambda l: str(l["dreb"])),
        row("Assists", lambda l: str(l["ast"])),
        row("Blocks", lambda l: str(l["blk"])),
        row("Steals", lambda l: str(l["stl"])),
        row("Turnovers", lambda l: str(l["to"])),
        row("Fouls", lambda l: str(l["pf"])),
    ]
    home_score = team_score if followed_is_home else opp_score
    away_score = opp_score if followed_is_home else team_score
    return dict(homeScore=home_score, awayScore=away_score, rows=rows, lines=lines)


def football_box(summary, followed_id, followed_is_home):
    comps = header_competitors(summary)
    first = get(comps[0], "team", "id") == followed_id
    team_score = int_value(comps[0 if first else 1].get("score"))
    opp_score = int_value(comps[1 if first else 0].get("score"))
    lines = []
    for t in summary["boxscore"]["teams"]:
        st = t.get("statistics")
        lines.append(dict(name=get(t, "team", "name"), yards=int_value(stat_display(st, "totalYards")),
                          passing=int_value(stat_display(st, "netPassingYards")),
                          rushing=int_value(stat_display(st, "rushingYards")),
                          firstDowns=int_value(stat_display(st, "firstDowns")),
                          drives=int_value(stat_display(st, "totalDrives")),
                          ints=int_value(stat_display(st, "interceptions")),
                          top=string_value(stat_display(st, "possessionTime")),
                          comp=int_value(stat_display(st, "completionAttempts")),
                          compDisplay=string_value(stat_display(st, "completionAttempts"))))
    away, home = lines[0], lines[1]

    def row(title, key):
        return (title, str(home[key]), str(away[key]))
    rows = [row("Total Yards", "yards"), row("Passing Yards", "passing"), row("Rushing Yards", "rushing"),
            row("First Downs", "firstDowns"), row("Drives", "drives"), row("Interceptions", "ints"),
            row("Possession Time", "top"), row("Completion Attempts", "compDisplay")]
    if home["drives"] == 0 and away["drives"] == 0:
        rows = [r for r in rows if r[0] != "Drives"]
    return dict(homeScore=team_score if followed_is_home else opp_score,
                awayScore=opp_score if followed_is_home else team_score, rows=rows, lines=lines)


def soccer_box(summary):
    comps = header_competitors(summary)

    def goals(side):
        return next((int_value(c.get("score")) for c in comps if c.get("homeAway") == side), 0)
    lines = {}
    for t in summary["boxscore"]["teams"]:
        st = t.get("statistics")
        side = t.get("homeAway")
        lines[side] = dict(goals=goals(side), shots=int_value(stat_display(st, "totalShots")),
                           poss=number(stat_display(st, "possessionPct")) or 0,
                           corners=int_value(stat_display(st, "wonCorners")))
    home, away = lines["home"], lines["away"]

    def rnd(x):
        # Swift's .rounded() is schoolbook (half away from zero).
        return int(x + 0.5) if x >= 0 else -int(-x + 0.5)
    rows = [("Goals", str(home["goals"]), str(away["goals"])), ("Shots", str(home["shots"]), str(away["shots"])),
            ("Possession", f"{rnd(home['poss'])}%", f"{rnd(away['poss'])}%"),
            ("Corner Kicks", str(home["corners"]), str(away["corners"]))]
    return dict(homeScore=home["goals"], awayScore=away["goals"], rows=rows)


def soccer_lineup(summary, side):
    roster = next(r for r in summary.get("rosters", []) if r.get("homeAway") == side)
    starters = [string_value(get(p, "athlete", "displayName")) for p in roster.get("roster", []) if p.get("starter")]
    return dict(formation=string_value(roster.get("formation")), starters=len(starters))


def hockey_box(summary):
    comps = header_competitors(summary)
    sides = {}
    for t in summary["boxscore"]["teams"]:
        side = t.get("homeAway")
        team_id = get(t, "team", "id")
        st = t.get("statistics")
        score = next((int_value(c.get("score")) for c in comps if c.get("homeAway") == side), 0)
        players = next((p for p in summary["boxscore"].get("players", []) if get(p, "team", "id") == team_id), {})
        fwd, dfn, gk = [], [], []
        for group in players.get("statistics", []):
            keys = group.get("keys", [])
            for a in group.get("athletes", []):
                vals = [string_value(v) for v in a.get("stats", [])]
                if not vals:
                    continue
                s = {}
                for k, v in zip(keys, vals):
                    s.setdefault(k, v)
                ath = a.get("athlete", {})
                entry = dict(name=ath.get("displayName"), jersey=string_value(ath.get("jersey")),
                             pos=get(ath, "position", "abbreviation"), s=s)
                name = group.get("name")
                if name == "forwards":
                    fwd.append(entry)
                elif name in ("defenses", "defense"):
                    dfn.append(entry)
                elif name == "goalies":
                    gk.append(entry)
                elif name == "skaters":
                    (dfn if entry["pos"] == "D" else fwd).append(entry)
        stats = dict(shots=int_value(stat_display(st, "shotsTotal")),
                     ppg=int_value(stat_display(st, "powerPlayGoals")),
                     ppo=int_value(stat_display(st, "powerPlayOpportunities")),
                     ppPct=string_value(stat_display(st, "powerPlayPct")),
                     fow=int_value(stat_display(st, "faceoffsWon")),
                     foPct=string_value(stat_display(st, "faceoffPercent")),
                     hits=int_value(stat_display(st, "hits")), pim=int_value(stat_display(st, "penaltyMinutes")),
                     blk=int_value(stat_display(st, "blockedShots")))
        sides[side] = dict(teamID=team_id, name=get(t, "team", "shortDisplayName"),
                           abbr=get(t, "team", "abbreviation"), score=score, stats=stats,
                           forwards=fwd, defense=dfn, goalies=gk)
    h, a = sides["home"]["stats"], sides["away"]["stats"]
    rows = [("Shots", str(h["shots"]), str(a["shots"])),
            ("Power Play", f"{h['ppg']}/{h['ppo']}", f"{a['ppg']}/{a['ppo']}"),
            ("Power Play %", f"{h['ppPct']}%", f"{a['ppPct']}%"),
            ("Faceoffs Won", str(h["fow"]), str(a["fow"])),
            ("Faceoff %", f"{h['foPct']}%", f"{a['foPct']}%"),
            ("Hits", str(h["hits"]), str(a["hits"])),
            ("Penalty Minutes", str(h["pim"]), str(a["pim"])),
            ("Blocked Shots", str(h["blk"]), str(a["blk"]))]
    return dict(home=sides["home"], away=sides["away"], rows=rows,
                homeScore=sides["home"]["score"], awayScore=sides["away"]["score"])


def linescore(summary, regulation_fallback):
    comps = header_competitors(summary)
    home = next(c for c in comps if c.get("homeAway") == "home")
    away = next(c for c in comps if c.get("homeAway") == "away")

    def scores(c):
        return [string_value(p.get("displayValue")) or string_value(p.get("value")) for p in c.get("linescores", [])]
    regulation = get(summary, "format", "regulation", "periods") or regulation_fallback
    hs, as_ = scores(home), scores(away)
    count = max(regulation or 0, len(hs), len(as_))
    labels = [str(p) if p <= regulation else ("OT" if p - regulation <= 1 else f"{p - regulation}OT")
              for p in range(1, count + 1)]

    def line(c, s):
        total = c.get("score")
        return dict(abbr=get(c, "team", "abbreviation"), periods=s + ["-"] * (count - len(s)),
                    total=string_value(total) if total is not None else "-")
    return dict(labels=labels, home=line(home, hs), away=line(away, as_))


def game_phase(summary):
    t = get(summary, "header", "competitions", 0, "status", "type") or {}
    if bool_value(t.get("completed")):
        return "final"
    return {"pre": "pre", "in": "live", "post": "final"}.get(t.get("state"), "unknown")


def game_info(summary):
    venue = get(summary, "gameInfo", "venue") or {}
    return dict(city=string_value(get(venue, "address", "city")), state=string_value(get(venue, "address", "state")),
                attendance=string_value(get(summary, "gameInfo", "attendance")))


# MARK: - The walkthrough

def walkthrough():
    """Everything the Swift walkthrough asserts, as the port reads it."""
    out = {}

    # NBA: Atlanta Hawks (1). The live feed is preseason; the finished game
    # is from the 2025-26 schedule.
    hawks = {}
    preseason = parse_schedule(load("nba_schedule"), "1", "shortDisplayName", sport="basketball")
    last = parse_schedule(load("nba_schedule_2026"), "1", "shortDisplayName", sport="basketball")
    game = next(g for g in last if g["gameID"] == "401811028")
    hawks["schedule"] = dict(
        preseasonIDs=[g["gameID"] for g in preseason], preseasonRecord=schedule_record(preseason, None, "winLoss"),
        lastIDs=[g["gameID"] for g in last], lastRecord=schedule_record(last, None, "winLoss"),
        nextGame=next_game(last),
        game=dict(pointer=game["pointer"], opponent=game["opponent"], opponentID=game["opponentID"],
                  home=game["gameHome"], win=game["gameWin"], score=game["score"], opp=game["opponentScore"],
                  location=game["location"], channel=game["channel"], completed=game["completed"]))
    roster = basketball_roster(load("nba_roster"))
    daniels = next(p for p in roster if p["playerID"] == "4869342")
    splits = load("nba_splits_4869342")
    hawks["roster"] = dict(count=len(roster), first=roster[0]["name"], last=roster[-1]["name"],
                           daniels=dict(name=daniels["name"], number=daniels["number"],
                                        position=daniels["position"], hometown=daniels["hometown"]),
                           danielsSplitNames=[r["displayName"] for r in get(splits, "splitCategories", 0, "splits")][:3],
                           danielsSeason={k: splits_season_line(splits).get(k)
                                          for k in ("gamesPlayed", "avgPoints", "avgAssists")})
    news = parse_news(load("nba_news"))
    hawks["news"] = dict(count=len(news), first=news[0]["title"], firstPublished=news[0]["published"])
    hawks["standings"] = standings_row(load("nba_standings"), "1")
    summary = load("nba_summary_final_401811028")
    hawks["box"] = dict(basketball_box(summary, "1", game["gameHome"]), phase=game_phase(summary),
                        linescore=linescore(summary, 4), info=game_info(summary))
    out["nba"] = hawks

    # NHL: Anaheim Ducks (25).
    ducks = {}
    games = parse_schedule(load("nhl_schedule"), "25", "shortDisplayName", sport="hockey")
    game = next(g for g in games if g["gameID"] == "401879368")
    ducks["schedule"] = dict(ids=[g["gameID"] for g in games],
                             record=schedule_record(games, None, "winLossOvertimeLoss", 3), nextGame=next_game(games),
                             game=dict(opponent=game["opponent"], opponentID=game["opponentID"], home=game["gameHome"],
                                       win=game["gameWin"], score=game["score"], opp=game["opponentScore"],
                                       location=game["location"], period=game["gamePeriod"]))
    roster = hockey_roster(load("nhl_roster"))
    gauthier = next(p for p in roster if p["playerID"] == "5080145")
    dostal = next(p for p in roster if p["playerID"] == "4588165")
    ducks["roster"] = dict(count=len(roster), first=roster[0]["name"],
                           goalies=sorted(p["name"] for p in roster if p["position"] == "Goaltender"),
                           gauthier=dict(name=gauthier["name"], number=gauthier["number"],
                                         position=gauthier["position"], shoots=gauthier["shoots"]),
                           dostal=dict(name=dostal["name"], number=dostal["number"], position=dostal["position"],
                                       shoots=dostal["shoots"]),
                           skaterLine=hockey_sheet(splits_season_line(load("nhl_splits_5080145"))),
                           goalieLine=hockey_sheet(splits_season_line(load("nhl_splits_4588165"))))
    news = parse_news(load("nhl_news"))
    ducks["news"] = dict(count=len(news), first=news[0]["title"], firstPublished=news[0]["published"])
    ducks["standings"] = standings_row(load("nhl_standings"), "25")
    summary = load("nhl_summary_final_401879368")
    box = hockey_box(summary)
    ducks["box"] = dict(homeScore=box["homeScore"], awayScore=box["awayScore"], rows=box["rows"],
                        home=dict(teamID=box["home"]["teamID"], name=box["home"]["name"], abbr=box["home"]["abbr"],
                                  forwards=len(box["home"]["forwards"]), defense=len(box["home"]["defense"]),
                                  goalies=[(g["name"], g["s"].get("shotsAgainst"), g["s"].get("saves"),
                                            g["s"].get("goalsAgainst"), g["s"].get("savePct"))
                                           for g in box["home"]["goalies"]],
                                  scorers=sorted((p["name"], int_value(p["s"].get("goals")))
                                                 for p in box["home"]["forwards"] + box["home"]["defense"]
                                                 if int_value(p["s"].get("goals")) > 0)),
                        away=dict(teamID=box["away"]["teamID"], name=box["away"]["name"], abbr=box["away"]["abbr"],
                                  forwards=len(box["away"]["forwards"]), defense=len(box["away"]["defense"]),
                                  goalies=len(box["away"]["goalies"])),
                        phase=game_phase(summary), linescore=linescore(summary, 3), info=game_info(summary))
    out["nhl"] = ducks

    # EPL: Arsenal (359), with the Champions League merged in.
    arsenal = {}
    games = merge_schedules(load("epl_schedule"), [("soccer/uefa.champions", load("ucl_schedule_359"))],
                            "359", "shortDisplayName", "soccer/eng.1")
    ucl = next(g for g in games if g["gameID"] == "401915423")
    arsenal["schedule"] = dict(ids=[g["gameID"] for g in games],
                               competitions=[g["competition"] for g in games],
                               record=schedule_record(games, "soccer/eng.1", "winLossTie"),
                               ucl=dict(pointer=ucl["pointer"], opponent=ucl["opponent"], opponentID=ucl["opponentID"],
                                        home=ucl["gameHome"], win=ucl["gameWin"], score=ucl["score"],
                                        opp=ucl["opponentScore"], location=ucl["location"], channel=ucl["channel"]))
    roster = soccer_roster(load("epl_roster"))
    saka = next(p for p in roster if p["playerID"] == "280555")
    arsenal["roster"] = dict(count=len(roster), first=roster[0]["name"],
                             withoutStats=sum(1 for p in roster if not p["hasSeasonStats"]),
                             saka={k: saka[k] for k in ("name", "number", "position", "appearances", "totalGoals",
                                                        "goalAssists")},
                             sakaSummary={string_value(x.get("name")): string_value(x.get("displayValue"))
                                          for x in get(load("epl_athlete_280555"), "athlete", "statsSummary",
                                                       "statistics")})
    news = parse_news(load("epl_news"))
    arsenal["news"] = dict(count=len(news), first=news[0]["title"], firstPublished=news[0]["published"])
    arsenal["standings"] = standings_row(load("epl_standings"), "359")
    summary = load("epl_summary_final_401879301")
    arsenal["box"] = dict(soccer_box(summary), phase=game_phase(summary), linescore=linescore(summary, 2),
                          home=soccer_lineup(summary, "home"), away=soccer_lineup(summary, "away"),
                          info=game_info(summary))
    out["epl"] = arsenal

    # NCAAF: Kansas (2305).
    kansas = {}
    games = parse_schedule(load("ncaaf_schedule"), "2305", "nickname", sport="football")
    game = next(g for g in games if g["gameID"] == "401856769")
    kansas["schedule"] = dict(ids=[g["gameID"] for g in games][:4], count=len(games),
                              record=schedule_record(games, None, "winLoss"), nextGame=next_game(games),
                              game=dict(team=game["team"], opponent=game["opponent"], opponentID=game["opponentID"],
                                        home=game["gameHome"], win=game["gameWin"], score=game["score"],
                                        opp=game["opponentScore"], location=game["location"],
                                        channel=game["channel"]))
    roster = football_roster(load("ncaaf_roster"))
    marshall = next(p for p in roster if p["playerID"] == "5079604")
    kansas["roster"] = dict(count=len(roster), first=roster[0]["name"],
                            units=sorted({p["team"] for p in roster}),
                            marshall={k: marshall[k] for k in ("name", "number", "position", "team", "hometown")},
                            marshallSeason={k: splits_season_line(load("ncaaf_splits_5079604")).get(k)
                                            for k in ("passingYards", "passingTouchdowns")})
    news = parse_news(load("ncaaf_news"))
    kansas["news"] = dict(count=len(news), first=news[0]["title"], firstPublished=news[0]["published"])
    kansas["standings"] = standings_row(load("ncaaf_standings"), "2305")
    summary = load("ncaaf_summary_final_401856769")
    kansas["box"] = dict(football_box(summary, "2305", game["gameHome"]), phase=game_phase(summary),
                         linescore=linescore(summary, 4), info=game_info(summary))
    out["ncaaf"] = kansas

    # LeagueScoreboardTests, "favorites in the new leagues": each favorite's
    # lines on the boards its pages poll (DownloadScoreboardData.swift).
    out["scoreboards"] = dict(
        heat=board_lines("nba_scoreboard_20261003", "14"),
        raptors=board_lines("nba_scoreboard_20261003", "28"),
        leafs=board_lines("nhl_scoreboard_20260919", "21"),
        canadiens=board_lines("nhl_scoreboard_20260919", "10"),
        arsenal=board_lines("epl_scoreboard_20260821", "359"),
        coventry=board_lines("epl_scoreboard_20260821", "388"),
        usc=board_lines("ncaaf_scoreboard_20260829", "30"),
        sanJose=board_lines("ncaaf_scoreboard_20260829", "23"),
        arsenalLeagueOn0909=board_lines("epl_scoreboard_20260909", "359"),
        arsenalCupOn0909=board_lines("ucl_scoreboard_20260909", "359"),
        barcelonaCupOn0909=board_lines("ucl_scoreboard_20260909", "83"),
        nhlOvertimePeriod=string_value(get(load("nhl_scoreboard_20260919"), "events", 1, "competitions", 0,
                                           "status", "period")),
    )
    return out


def board_lines(name, team_id):
    """LeagueScoreboard.lines(for:): a score only for a game under way or
    played out, against one opponent."""
    out = []
    for event in load(name)["events"]:
        for c in event.get("competitions", []):
            t = get(c, "status", "type") or {}
            if not (t.get("state") == "in" or (t.get("state") == "post" and bool_value(t.get("completed")))):
                continue
            comps = [(get(x, "team", "id"), number(x.get("score"))) for x in c.get("competitors", [])]
            me = [x for x in comps if x[0] == team_id]
            if len(comps) != 2 or not me:
                continue
            them = next(x for x in comps if x[0] != team_id)
            out.append([string_value(c.get("id")) or string_value(event.get("id")), them[0], int(me[0][1]),
                        int(them[1])])
    return out


# MARK: - Expected values: the literals CrossLeagueAcceptanceTests.swift asserts

EXPECTED = {
    # Hawks (NBA)
    "nba.schedule.preseasonIDs": ["401898388", "401898394", "401898396", "401898402", "401898408"],
    "nba.schedule.preseasonRecord": "0-0",
    "nba.schedule.lastRecord": "7-5",
    "nba.schedule.game": dict(pointer=11, opponent="Cavaliers", opponentID="5", home=True, win=True, score="124",
                              opp="102", location="State Farm Arena", channel="Prime Video", completed=True),
    "nba.roster.count": 18,
    "nba.roster.first": "Nickeil Alexander-Walker",
    "nba.roster.last": "Jalen Wilson",
    "nba.roster.daniels": dict(name="Dyson Daniels", number="5", position="Guard", hometown="Bendigo, VIC"),
    "nba.roster.danielsSeason": dict(gamesPlayed="76", avgPoints="11.9", avgAssists="5.9"),
    "nba.news.count": 25,
    "nba.news.first": "2026 NBA free agency: Grades for offseason signings, extensions",
    "nba.news.firstPublished": "2026-09-26T16:55:13Z",
    "nba.standings.group": "Eastern Conference",
    "nba.standings.index": 0,
    "nba.standings.wins": 0,
    "nba.standings.losses": 0,
    "nba.standings.rank": None,
    "nba.standings.gamesBehind": "-",
    "nba.standings.vsconf": "0-0",
    "nba.box.homeScore": 124,
    "nba.box.awayScore": 102,
    "nba.box.rows": [
        ("Field Goals", "45/93", "39/86"), ("Field Goal %", "48%", "45%"), ("Three Points", "16/44", "7/27"),
        ("Three Point %", "36%", "26%"), ("Free Throws", "18/25", "17/18"), ("Free Throw %", "72%", "94%"),
        ("Offensive Rebounds", "14", "9"), ("Defensive Rebounds", "32", "31"), ("Assists", "27", "25"),
        ("Blocks", "4", "6"), ("Steals", "12", "8"), ("Turnovers", "11", "19"), ("Fouls", "18", "20"),
    ],
    "nba.box.phase": "final",
    "nba.box.linescore": dict(labels=["1", "2", "3", "4"],
                              home=dict(abbr="ATL", periods=["27", "34", "35", "28"], total="124"),
                              away=dict(abbr="CLE", periods=["22", "26", "17", "37"], total="102")),
    "nba.box.info": dict(city="Atlanta", state="GA", attendance="17517"),

    # Ducks (NHL)
    "nhl.schedule.ids": ["401879368", "401879369", "401879370", "401879371"],
    "nhl.schedule.record": "1-3-0",
    "nhl.schedule.nextGame": 3,
    "nhl.schedule.game": dict(opponent="Sharks", opponentID="18", home=True, win=True, score="6", opp="2",
                              location="Honda Center", period="3"),
    "nhl.roster.count": 56,
    "nhl.roster.first": "Anthony Allain-Samake",
    "nhl.roster.goalies": ["Elijah Neuenschwander", "Lukas Dostal", "Tomas Suchanek", "Ville Husso"],
    "nhl.roster.gauthier": dict(name="Cutter Gauthier", number="61", position="Left Wing", shoots="Left"),
    "nhl.roster.dostal.number": "1",
    "nhl.roster.dostal.position": "Goaltender",
    "nhl.roster.skaterLine": ["76", "41", "28", "69", "-2", "28", "285", "11", "8", "0", "7", "49.0", "17:15"],
    "nhl.roster.goalieLine": ["55", "30", "20", "4", "169", "3.10", "1513", "1344", ".888", "0", "58:21"],
    "nhl.news.count": 25,
    "nhl.news.first": "Lapsed fan's guide to the NHL season: Top teams, players, storylines for 2026-27",
    "nhl.news.firstPublished": "2026-09-25T12:31:06Z",
    "nhl.standings.group": "Western Conference",
    "nhl.standings.total": "0-0-0, 0 PTS",
    "nhl.standings.wins": 0,
    "nhl.standings.losses": 0,
    "nhl.standings.otlosses": 0,
    "nhl.standings.points": 0,
    "nhl.standings.rank": None,
    "nhl.box.homeScore": 6,
    "nhl.box.awayScore": 2,
    "nhl.box.rows": [
        ("Shots", "32", "23"), ("Power Play", "1/3", "0/2"), ("Power Play %", "33.3%", "0.0%"),
        ("Faceoffs Won", "35", "25"), ("Faceoff %", "58.3%", "41.7%"), ("Hits", "17", "27"),
        ("Penalty Minutes", "9", "11"), ("Blocked Shots", "7", "12"),
    ],
    "nhl.box.home.teamID": "25",
    "nhl.box.home.name": "Ducks",
    "nhl.box.home.abbr": "ANA",
    "nhl.box.home.forwards": 12,
    "nhl.box.home.defense": 6,
    "nhl.box.home.goalies": [("Laurent Brossoit", "23", "21", "2", ".913")],
    "nhl.box.away.teamID": "18",
    "nhl.box.away.name": "Sharks",
    "nhl.box.away.abbr": "SJ",
    "nhl.box.away.forwards": 12,
    "nhl.box.away.defense": 6,
    "nhl.box.away.goalies": 2,
    "nhl.box.phase": "final",
    "nhl.box.linescore": dict(labels=["1", "2", "3"], home=dict(abbr="ANA", periods=["2", "2", "2"], total="6"),
                              away=dict(abbr="SJ", periods=["1", "1", "0"], total="2")),
    "nhl.box.info.city": "Anaheim",
    "nhl.box.info.attendance": "10000",

    # Arsenal (Premier League)
    "epl.schedule.ids": ["401879301", "401879295", "401879292", "401915423", "401878779", "401879274"],
    "epl.schedule.competitions": ["soccer/eng.1", "soccer/eng.1", "soccer/eng.1", "soccer/uefa.champions",
                                  "soccer/eng.1", "soccer/eng.1"],
    "epl.schedule.record": "4-1-0",
    "epl.schedule.ucl": dict(pointer=3, opponent="Napoli", opponentID="114", home=False, win=True, score="1",
                             opp="0", location="Stadio Diego Armando Maradona", channel="Paramount+"),
    "epl.roster.count": 27,
    "epl.roster.first": "Kepa Arrizabalaga",
    "epl.roster.withoutStats": 5,
    "epl.roster.saka": dict(name="Bukayo Saka", number="7", position="Forward", appearances=5, totalGoals=3,
                            goalAssists=0),
    "epl.roster.sakaSummary.starts-subIns": "5 (0)",
    "epl.roster.sakaSummary.totalGoals": "3",
    "epl.news.count": 24,
    "epl.news.first": "Parma part ways with ex-Arsenal assistant Carlos Cuesta",
    "epl.news.firstPublished": "2026-09-27T18:01:25Z",
    "epl.standings.rank": 2,
    "epl.standings.wins": 4,
    "epl.standings.losses": 1,
    "epl.standings.ties": 0,
    "epl.standings.points": 12,
    "epl.standings.pointdifferential": "+4",
    "epl.standings.note": "Champions League",
    "epl.box.homeScore": 3,
    "epl.box.awayScore": 0,
    "epl.box.rows": [("Goals", "3", "0"), ("Shots", "20", "4"), ("Possession", "65%", "36%"),
                     ("Corner Kicks", "8", "2")],
    "epl.box.phase": "final",
    "epl.box.linescore": dict(labels=["1", "2"], home=dict(abbr="ARS", periods=["2", "1"], total="3"),
                              away=dict(abbr="COV", periods=["0", "0"], total="0")),
    "epl.box.home": dict(formation="4-2-3-1", starters=11),
    "epl.box.away": dict(formation="4-1-4-1", starters=11),
    "epl.box.info.city": "London",
    "epl.box.info.attendance": "60098",

    # Kansas (college football)
    "ncaaf.schedule.count": 12,
    "ncaaf.schedule.ids": ["401856769", "401856678", "401856812", "401856807"],
    "ncaaf.schedule.record": "1-2",
    "ncaaf.schedule.nextGame": 3,
    "ncaaf.schedule.game": dict(team="Kansas", opponent="Long Island", opponentID="2341", home=True, win=True,
                                score="51", opp="6", location="David Booth Kansas Memorial Stadium",
                                channel="ESPNU"),
    "ncaaf.roster.count": 100,
    "ncaaf.roster.first": "Jibreel Al-Amin",
    "ncaaf.roster.units": ["defense", "offense", "specialTeam"],
    "ncaaf.roster.marshall": dict(name="Isaiah Marshall", number="8", position="Quarterback", team="offense",
                                  hometown="Southfield, MI"),
    "ncaaf.roster.marshallSeason": dict(passingYards="649", passingTouchdowns="5"),
    "ncaaf.news.count": 19,
    "ncaaf.news.first": "College Football Playoff 2026: Bubble Watch after Week 3",
    "ncaaf.news.firstPublished": "2026-09-22T14:40:44Z",
    "ncaaf.standings.group": "Big 12 Conference",
    "ncaaf.standings.total": "1-2",
    "ncaaf.standings.rank": 16,
    "ncaaf.standings.gamesBehind": "2.5",
    "ncaaf.standings.streak": "L2",
    "ncaaf.standings.vsconf": "0-1",
    "ncaaf.box.homeScore": 51,
    "ncaaf.box.awayScore": 6,
    "ncaaf.box.rows": [
        ("Total Yards", "613", "146"), ("Passing Yards", "336", "111"), ("Rushing Yards", "277", "35"),
        ("First Downs", "29", "11"), ("Interceptions", "0", "0"), ("Possession Time", "33:06", "26:54"),
        ("Completion Attempts", "18/25", "10/20"),
    ],
    "ncaaf.box.phase": "final",
    "ncaaf.box.linescore": dict(labels=["1", "2", "3", "4"],
                                home=dict(abbr="KU", periods=["6", "24", "7", "14"], total="51"),
                                away=dict(abbr="LIU", periods=["0", "0", "0", "6"], total="6")),
    "ncaaf.box.info": dict(city="Lawrence", state="KS", attendance="30904"),

    # LeagueScoreboardTests: favorites in the new leagues, and the cup seam
    "scoreboards.heat": [],
    "scoreboards.raptors": [],
    "scoreboards.leafs": [["401881922", "10", 1, 4], ["401881923", "10", 3, 4]],
    "scoreboards.canadiens": [["401881922", "21", 4, 1], ["401881923", "21", 4, 3]],
    "scoreboards.arsenal": [["401879301", "388", 3, 0]],
    "scoreboards.coventry": [["401879301", "359", 0, 3]],
    "scoreboards.usc": [["401864494", "23", 42, 26]],
    "scoreboards.sanJose": [["401864494", "30", 26, 42]],
    "scoreboards.arsenalLeagueOn0909": [],
    "scoreboards.arsenalCupOn0909": [["401915423", "114", 1, 0]],
    "scoreboards.barcelonaCupOn0909": [["401915424", "142", 5, 1]],
    "scoreboards.nhlOvertimePeriod": "4",
}

# Cross-section agreements the walkthrough asserts (header record vs table).
AGREEMENTS = [
    ("Hawks: preseason header 0-0 == table 0-0",
     lambda o: o["nba"]["schedule"]["preseasonRecord"] == f"{o['nba']['standings']['wins']}-{o['nba']['standings']['losses']}"),
    ("Ducks: header 1-3-0 != table 0-0-0 (known gap: preseason counted)",
     lambda o: o["nhl"]["schedule"]["record"] != "0-0-0" and o["nhl"]["standings"]["total"].startswith("0-0-0")),
    ("Arsenal: header W-L-D == table W, L, D",
     lambda o: o["epl"]["schedule"]["record"] == "{wins}-{losses}-{ties}".format(**o["epl"]["standings"])),
    ("Kansas: header == table overall summary",
     lambda o: o["ncaaf"]["schedule"]["record"] == o["ncaaf"]["standings"]["total"]),
    ("Ducks: skater goals add up to each side's score",
     lambda o: sum(g for _, g in o["nhl"]["box"]["home"]["scorers"]) == o["nhl"]["box"]["homeScore"]),
]


def normalise(value):
    """Tuples and lists compare alike."""
    if isinstance(value, (list, tuple)):
        return [normalise(v) for v in value]
    if isinstance(value, dict):
        return {k: normalise(v) for k, v in value.items()}
    return value


def check(out):
    failures = 0
    for path, want in EXPECTED.items():
        node = out
        for step in path.split("."):
            node = node[int(step)] if isinstance(node, list) else node[step]
        ok = normalise(node) == normalise(want)
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'} {path} = {node!r}" + ("" if ok else f" (expected {want!r})"))
    for label, agrees in AGREEMENTS:
        ok = agrees(out)
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'} {label}")
    total = len(EXPECTED) + len(AGREEMENTS)
    print(f"\n{total - failures}/{total} assertions pass")
    return failures


if __name__ == "__main__":
    result = walkthrough()
    if "--dump" in sys.argv:
        print(json.dumps(result, indent=1, ensure_ascii=False, default=str))
    else:
        sys.exit(1 if check(result) else 0)
