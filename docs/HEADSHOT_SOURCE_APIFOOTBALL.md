# Headshot source recon: API-Football / API-Sports (card t_2856e1f4)

Date: 2026-10-06. Zero-touch probes (curl/GET only). No API key was available in
this environment (`env` and work-profile `.env` scanned for football/sport keys:
none present — no key-gated endpoint was ever called with credentials).

## TL;DR

- **There are two different vendors with confusingly similar names.** `apifootball.com`
  ("APIfootball", `apiv3.apifootball.com` CDN) and `api-football.com` ("API-SPORTS",
  `v3.football.api-sports.io` API + `media.api-sports.io` CDN). The ESPN-slug theory in
  the card points at the **first**; ESPN's site actually mirrors nothing from either —
  see ID-alignment.
- **The "one host header away from photos with ZERO new key" hope is dead — and dangerous.**
  The keyless CDN `media.api-sports.io/football/players/<id>.png` accepts *any* integer id
  (even ESPN's athlete ids), but the id space is API-Sports' own. Feeding it ESPN ids
  yields placeholder-or-404 (~82%) or **another, unrelated player's real photo** (~18%) —
  including a male photo served for a female WSL player. Shipping any of it would mislabel
  people. Evidence below.
- **Recommendation: PASS on keyless options.** If we later want a tier-2 for soccer,
  the only viable shape is: register an API-Sports **free key (100 req/day)**, resolve
  players via their *keyed* `/players?league=&season=` endpoints (name+team join), and
  then hotlink their CDN photos, which are keyless, CORS-open, and edge-cached. Budget
  math for that fits **weekly prefetch at ~5 req/day amortized** (see §Budget). That is
  an adoption card, not this one. Wikidata (already shipped, t_159ce491) stays tier-2;
  this source could become tier-3 behind a settings flag if coverage is worth the key.

## Vendor map (both probed live)

| | apifootball.com ("APIfootball") | api-football.com ("API-SPORTS") |
|---|---|---|
| JSON API | `apiv3.apifootball.com/?action=get_players&...&APIkey=` | `v3.football.api-sports.io/players?...` (header `x-apisports-key`) |
| No-key API behavior | HTTP 200 + `{"error":404,"message":"Authentification failed!"}` | HTTP 403 `{"errors":{"token":"Missing application key..."}}` |
| Player photo host | `apiv3.apifootball.com/badges/players/<player_id>_<slug>.jpg` | `media.api-sports.io/football/players/<player_id>.png` |
| Photo host keyless? | **Yes** (GET needs no key) | **Yes** (GET needs no key) |
| Photo id discoverable without key? | No (site pages 404; ids only in keyed JSON) | No (only in keyed JSON) |
| Free tier | "free on every plan you'll choose" (widgets); data plans paid | 100 req/day, limited seasons (vendor pricing/docs; page Cloudflare-gated at probe time, corroborated by third-party summaries) |

## Probe 1 — ESPN-slug theory on apifootball.com: NEGATIVE

Card theory: ESPN slug `soccer/player/_/id/196176/david-raya` implies ESPN sources the
APIfootball DB. Tested against both their URL shapes:

```
$ curl -s -o /dev/null -w "%{http_code}\n" https://apifootball.com/english/player_196176-David_Raya.html
404
$ curl -s -o /dev/null -w "%{http_code}\n" "https://apiv3.apifootball.com/badges/players/196176_d-raya.jpg"
404        # (also tried _r-david.jpg, _d-raya-1.jpg, .png — all 404, body {"error":404,...})
```

Their badge CDN works and is keyless — but only for *their* ids with *their* slug:

```
$ curl -s -o /dev/null -w "%{http_code} %{content_type} %{size_download}B\n" \
    "https://apiv3.apifootball.com/badges/players/124730_j-oblak.jpg"
200 image/jpeg 22225B
$ curl -sI "https://apiv3.apifootball.com/badges/players/124730_j-oblak.jpg" | grep -i cache
cache-control: max-age=31536000, public
```

Their documentation page (`https://apifootball.com/documentation/`) shows the photo field
in keyed JSON (`"player_image": "https://apiv3.apifootball.com/badges/players/9898_k-benzema.jpg"`),
confirming photos exist on their plans — but the **slug is mandatory** in the URL (no-slug
and wrong-slug variants 404), so ids are useless without their keyed data. ESPN's player
pages contain no reference to either vendor:

```
$ grep -ioE "(apifootball|football-data|api-sports|sportapi)[a-z0-9./_-]*" raya_page.html   # 509KB ESPN page
(no matches)
```

Verdict: no ESPN↔APIfootball mirror; the theory is wrong, and the "ZERO new key" idea
via this vendor fails because photo filenames embed their private slug/id.

## Probe 2 — API-Sports keyless CDN: works, but id-space collision

`media.api-sports.io/football/players/<N>.png` accepts any integer, unauthenticated,
served by GCS with CORS wide open:

```
$ curl -sI "https://media.api-sports.io/football/players/124730.png"
HTTP/2 200
content-type: image/png
access-control-allow-origin: *
cache-control: public, max-age=172800     (48h edge cache)

$ curl -s "https://media.api-sports.io/football/players/9999999.png" -w "%{http_code}"
404 (html "404 - File Not Found", 678B)
```

Images are 150×150 (a few 108×108), 7–45 KB, PNG or JPEG bytes under a .png URL.
Three response classes (hash-identified):

- `2ff7d52a…` 5,192 B — grey bust silhouette (their "no photo" PNG)
- `575e4487…` 8,624 B — "NO PHOTO YET" bust (vision-verified placeholder)
- distinct hashes — a real headshot **of some player in their DB**, and for ids we
  fed in, *not the player we asked for*.

## Hit rate on the two required rosters (ESPN ids → api-sports CDN)

Rosters pulled from ESPN site API (`site.api.espn.com/apis/site/v2/sports/soccer/.../roster`),
then every player id probed on `media.api-sports.io`:

| Roster | n | real-photo hash | silhouette | NO-PHOTO-YET | 404 |
|---|---|---|---|---|---|
| West Ham WFC (WSL, ESPN team 19975) | 24 | 6 | 15 | 1 | 2 |
| Arsenal FC (EPL, ESPN team 359)* | 27 | 3 | 19 | 5 | 0 |

\* The current ESPN eng.1 roster endpoint returns a mixed-squad artifact (Meslier,
Konsa, Bruno, Zubimendi… alongside Arsenal players) — roster API bug upstream, same 27
ids either way; flagged for a separate ESPN-API health note.

**Identity spot-checks (vision model, full-res downloads) prove the "real" hits are wrong people:**

| ESPN id | ESPN player | What the CDN returned |
|---|---|---|
| 342200 | Nadine Riesen (WSL, female) | headshot of a **male**, ~20 y/o — ID collision |
| 259308 | Ffion Morgan (WSL, female) | headshot of a **male** |
| 312461 | Megan Walsh (WSL, female) | headshot of a **male** |
| 347137 | Inès Belloumou (WSL, female) | headshot of a young **male** |
| 265921 | Illan Meslier (dirty-blonde GK) | dark-haired male, "not plausibly Meslier" |
| 149622 | Jan Oblak (ESPN LaLiga id) | generic young male; APIfootball's Oblak is 124730 |

So the **legitimate hit-rate via ESPN-id passthrough is 0/51**, and ~18% of responses are
silently wrong-person photos. This is the single most important finding of the card:
the keyless path is not just empty, it's actively misleading — never wire an id-through
without an identity join via keyed data.

For completeness, ESPN's *own* headshot CDN (found via `headshot` fields in roster JSON,
pattern `a.espncdn.com/i/headshots/soccer/players/full/<id>.png`): serves 251 KB hi-res
photos when present, confirms the card's premise —

```
$ curl -s -o /dev/null -w "%{http_code}\n" https://a.espncdn.com/i/headshots/soccer/players/full/282716.png  # Timber
200
$ for id in <24 West Ham W ids>; do curl … /full/$id.png; done   # → all 404
```

— matching prior findings (WSL 0/24, EPL 2/27). The `playerpictures/soccer/` path variant
is dead (404s for everyone incl. Raya).

## ID-alignment story (ESPN ↔ API-Sports / APIfootball)

- Numeric ids do **not** align: ESPN Raya = 196176, API-Sports Benzema = 9898 vs ESPN
  Benzema = 46858 vs APIfootball Benzema = 9898 (jpg slug `k-benzema`), APIfootball Grbić
  = 31641 = same number, different vendor, different sport-role. No bijection exists;
  the CDN simply indexes its own DB and returns placeholders or collisions otherwise.
- Only join: **name + team (+ dob if available)** against keyed `/players?team=<id>` or
  `/players?league=&season=` output from API-Sports (each response carries `id`,
  `name`, `firstname`, `lastname`, `team.id`, `photo`). Fuzzy-name + exact-team would be
  the tier-3 pipeline, with the ESPN `headshot` field as truth-first (only draw from the
  vendor when ESPN has none — which is almost all of soccer).
- APIfootball's keyed `get_players` is by `player_name` only (no league/team filter in the
  example), and photos need their internal id+slug — a worse join than API-Sports.

## Budget math (API-Sports free tier = 100 req/day, images free)

App leagues (Sport.swift): 10 soccer leagues (eng.1, esp.1, ita.1, ger.1, fra.1, usa.1,
mex.1, eng.w.1, fra.w.1, usa.nwsl) ≈ 18–20 men's / 12–16 women's teams each.

- Naive per-team: 1 req/team → ~170 req for one full sweep. At 100/day: alternate-days
  sweep, or 2 leagues/day (weekly full refresh). **Amortized ≈ 24–30 req/day — fits.**
- Per-league `players?league=&season=` (50/page, ~2–3 pages/league): ~25 req full sweep —
  **fits a once-a-week cron in a single day with margin.**
- Photo bytes themselves: $0 API cost (keyless CDN), 48h public edge cache — client
  hotlinking is free and unlimited.
- **Weekly-cache-viable: yes.** One sweep/week + CDN hotlink is the shape, ~25–40 req
  burst on a single day.

## ToS / licensing notes

- apifootball.com terms (captured): *"All logos/images/videos are copyrighted by their
  legal owner. We only provide the sources. What you do with it is your own
  responsibility. To display these types of content in your app or website you must
  ensure that your use of them complies with the legal framework…"* — i.e. no image
  license is granted by the API vendor; same exposure class as the shipped
  Wikidata/Commons path (which at least carries per-image CC licenses + attribution).
- api-football.com pricing/terms pages are Cloudflare-gated to bots (probe: challenge
  page); third-party summaries (2026) state the free tier is 100 req/day with limited
  seasons and is "built for testing rather than production". Vendor rate-limit post
  warns over-quird use can trigger temporary IP/key blocks. **Manual review of their
  current terms is required before any adoption card ships.**
- CORS: `media.api-sports.io` sends `access-control-allow-origin: *` (site/widget-safe);
  `apiv3.apifootball.com` badges send no CORS headers (native `<img>`/URLSession fine,
  web cross-origin fetch not).

## Recommendation

**PASS as tier-2 (keyless).** No zero-key path yields *correct* player photos; every
keyless hit was a placeholder or a wrong person. Keep Wikidata as tier-2 (shipped).

**Conditional tier-3 later:** API-Sports free-key + weekly roster sweep + CDN hotlink
fits the 100/day budget with headroom and would plausibly cover most EPL/LaLiga men
(stars ESPN omits but they photograph). Before an adoption card: (1) sign up for a key
and re-run this hit-rate against the same 51 ids (the keyed join is the whole test);
(2) check free-tier season/league coverage for eng.w.1 / fra.w.1 / usa.nwsl (women's
coverage on free plans is the open question); (3) human review of current terms for
in-app display. Expected ceiling from their men's premier leagues; low expectation for
WSL where placeholder rate was already high even under collision conditions.
