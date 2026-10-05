# MyTeams

An iOS app for following any teams you choose across ESPN's leagues. Each
followed team gets its own page — roster, schedule, league standings, stat
leaders and news — with live scores, score alerts, Live Activities and a
home-screen and Lock Screen widget for its next game.

Built with SwiftUI against ESPN's public site API. No API keys are needed.

## Features

- **Any team, many leagues.** The team picker lists ten leagues: NFL, NBA,
  MLB, NHL, MLS, WNBA, NCAA Football, NCAA Men's and Women's Basketball, and
  the Premier League (`LeagueID.browsable`). Its search matches every league
  it has loaded and then falls back to ESPN's own search, so teams elsewhere
  can be followed too. LALIGA, Liga MX and NWSL have their own league
  descriptors as well; any other league gets one derived from its path.
- **Team pages.** One page per followed team: a roster carousel with filter
  and sort menus and a player sheet with season stats; a schedule carousel
  opened at the next game, whose sheet shows the box score and refreshes
  while the game is live; the league standings with the team's row picked
  out; the team's stat leaders and the league's leaderboards; and the team's
  news feed.
- **Favorites.** The system tab bar at the foot of the screen has a tab per
  followed team (its crest and short name), with those past the bar's room
  under "More"; the bar holds teams only. Settings' "Add Teams" and
  "Manage Teams" open the picker, where teams are followed, reordered and
  removed. The bar minimizes on scrolling down, as in the
  system's apps (never under VoiceOver or Switch Control). Favorites are stored in the App Group's defaults
  (which the widget reads) and mirrored to iCloud key-value storage, so they
  sync between devices.
- **Onboarding.** A fresh install opens on the "Pick Your Teams" sheet with
  the seed teams — the Kansas Jayhawks, Kansas City Chiefs, Kansas City
  Royals and Sporting Kansas City, from `Resources/teams.json` — already
  checked. Dismissing it finishes onboarding. Installs restored from iCloud
  or upgraded from an earlier build skip it.
- **Live scores and alerts.** One scoreboard poll per league covers every
  favorite in it (`LeagueScoreboardCenter`). Favorites post local alerts
  for the start, each score, each period's end and the final
  (`ScoreAlertEngine`); permission is asked the first time a team is
  followed, never at launch. Alerts are driven by the app's polling, so they
  fire only while the app is in the foreground.
- **Live Activities.** While the app is in the foreground, each favorite's
  game in progress gets a Live Activity — score, period and clock on the
  Lock Screen and in the Dynamic Island — up to six at once, favorites with
  alerts on first (`LiveActivityManager`). They update as the score moves,
  end with the final score, and go stale once the app stops updating them.
- **Widget.** One configurable "Team Schedule" widget, in small and medium
  home-screen sizes and rectangular and circular Lock Screen sizes. It
  shows the next game of the team chosen in its settings, or else the first
  favorite. Tapping it opens the app on that team's page (see below).

## URL scheme

The app registers the `myteams` scheme (`Hawk Nation/Info.plist`). The
widget opens the app with

```
myteams://team/<TeamRef.id>
```

for example `myteams://team/football/nfl:12` for the Chiefs. The app switches
to that team's page if the team is a favorite and ignores the link
otherwise. Links are built and read by `WidgetDeepLink`
(`Networking/TeamRef.swift`); anything but a `team` link to a well-formed
id is ignored.

## Requirements

- Xcode 26 or later
- iOS 26 deployment target
- Swift 6, with complete strict concurrency

## Building

Open `myTeams.xcodeproj` and build the `myTeams` scheme, which also builds
and embeds the widget extension. There are no package or CocoaPods
dependencies to resolve first.

The scheme's test action runs the unit tests (`myTeamsTests`, against
recorded ESPN fixtures in `myTeamsTests/Fixtures`) and the UI tests
(`myTeamsUITests`). `.github/workflows/ios-gate.yml` builds and tests the
scheme on a simulator for every pushed branch.

## Layout

```
Hawk Nation/          The app target
  Classes/            Small shared views and helpers (colours, progress, loading)
  Home Menus/         Team pages and their sections, the team picker,
                      favorites, standings, live scoreboards, score alerts
                      and Live Activities
  Leaders/            Stat leaders: the team's and the league's
  NavigationBar/      The root screen and its tab bar
  Networking/         Team and league identity, the HTTP client, JSON
                      parsing, team catalogs and cached crests
  News/               The news feed and its article sheet
  Preview Content/    Assets for SwiftUI previews
  Resources/          App entry point, app delegate, assets and teams.json
  Roster/             Player cards, detail sheets and the roster loaders
  Schedule/           Game cards, detail sheets, box scores and the
                      schedule and scoreboard loaders
  Info.plist
  PrivacyInfo.xcprivacy
myTeamWidget/         The widget extension: the Team Schedule widget and
                      the Live Activity views
myTeamsTests/         Unit tests, with ESPN fixtures and FIXTURES.md
myTeamsUITests/       UI tests
scripts/              Fixture capture scripts and a Python check of the
                      cross-league acceptance values
docs/                 Design notes
```

The widget extension compiles `JSON`, `HTTPClient`, `Sport`, `TeamRef`,
`ConvertColor`, `LogoStore`, `RemoteTeamCatalog`, `GameActivityAttributes`
and the schedule parser from the app target rather than keeping its own copy
of them, and bundles its own copy of `teams.json`. The app and the widget
share favorites, crests and team catalogs through their App Group.

## Team identity

A team is a `TeamRef` value (`Networking/TeamRef.swift`): its ESPN league
(`LeagueID`, e.g. `football/nfl`) and ESPN team id, plus display fields. Its
`id` is `"<leaguePath>:<espnID>"`, e.g. `"football/nfl:12"`. Feeds are
matched on the ESPN id every competitor node carries, never on names.

- `TeamCatalog` reads the bundled `Resources/teams.json`: the four seed
  teams, available offline.
- `RemoteTeamCatalog` fetches and caches each league's full team list from
  ESPN, for the picker and the widget.
- `LeagueDescriptor` (`Networking/Sport.swift`) holds what differs by
  league: sport kind, roster shape, record rule, period names, standings
  and season naming.
- `FavoritesStore` is the user's list of followed teams, in crest-bar order;
  `FavoriteTeams.seedIDs` seeds it on a fresh install.

The retired `Team` enum's raw values (`"jayhawk"`, `"chiefs"`, `"royals"`,
`"sporting"`) survive only as `TeamCatalog.legacyTeamIDs`, for migrating
anything persisted under them.

## Privacy

The app does no tracking and collects no data. Each target ships a
`PrivacyInfo.xcprivacy` declaring the required-reason APIs it uses:
`UserDefaults` (its own and the App Group's) and file modification dates on
the crests it caches in its own and the App Group's containers.

## Dependencies

None. The app previously depended on Alamofire, SwiftyJSON,
SDWebImageSwiftUI, Kingfisher, AlamofireImage, SwURL, RestEssentials,
GCProgressView and ShimmerView, plus CocoaPods. Each has been replaced by the
platform equivalent:

| Was | Now |
| --- | --- |
| Alamofire | `URLSession` with async/await, in `HTTPClient` |
| SwiftyJSON | `JSON`, a `JSONSerialization`-backed value type |
| SDWebImageSwiftUI, Kingfisher, AlamofireImage | `RemoteImage`, caching over `URLCache` and `NSCache` |
| SwURL, RestEssentials, GCProgressView, ShimmerView | unused; removed |
