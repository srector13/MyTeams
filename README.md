# MyTeams

An iOS app that follows four Kansas City sports teams — the Kansas Jayhawks,
the Kansas City Chiefs, the Kansas City Royals and Sporting Kansas City —
showing each team's roster, schedule and news, with home-screen widgets for
the next fixture.

Built with SwiftUI against the public ESPN and NewsAPI endpoints.

## Requirements

- Xcode 26 or later
- iOS 26 deployment target
- Swift 6, with complete strict concurrency

## Building

Open `myTeams.xcodeproj` and build the `myTeams` scheme. There are no package
or CocoaPods dependencies to resolve first.

### The news API key

The news feeds read their key from a `NEWS_API_KEY` build setting, which
`Info.plist` passes through to the app. Supply it however suits your setup —
an `.xcconfig` that is not checked in, or a CI secret:

```
NEWS_API_KEY = your-newsapi-key
```

Without a key the rosters and schedules still load; only the news sections
stay empty.

## Layout

```
Hawk Nation/
  Networking/     JSON parsing, the HTTP client, cached remote images
  Home Menus/     The four team pages and the model and sections they share
  NavigationBar/  The root screen and its team picker
  Roster/         Player cards, detail sheets and the roster loaders
  Schedule/       Game cards, detail sheets and the schedule loaders
  News/           The news feed, its article sheet and the feed queries
myTeamWidget/     The three next-fixture widgets
myTeamsTests/     Unit tests for JSON decoding and schedule parsing
```

The widget extension compiles `JSON`, `HTTPClient`, `Sport` and the schedule
parser from the app target rather than keeping its own copy of them.

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
