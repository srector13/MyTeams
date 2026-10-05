# myTeams site

The GitHub Pages marketing site for myTeams: a single dark one-pager,
`index.html`, with all of its CSS inline. There is no build step — the files
in `site/` are published as they are.

Feature copy follows the repository's root `README.md`. Keep the two in step:
don't claim anything on the site that the README doesn't.

## Layout

```
site/
  index.html                         The whole site (HTML + inline CSS)
  assets/brand/
    myteams-logo-on-dark.png         Wordmark for dark backgrounds (hero)
    appicon-dark-1024.png            App icon (favicon, header)
  screenshots/                       Gallery screenshots (see below)
```

The brand PNGs are copies of `myTeamsLogoOnDark` and `AppIcon-dark-1024`
from `Hawk Nation/Resources/Assets.xcassets`. The originals stay in the asset
catalog.

## Screenshots

The gallery shows seven phone frames, in this order. Put each PNG in
`site/screenshots/` with exactly this filename:

| # | File | Caption |
| - | ---- | ------- |
| 1 | `team-page-dark.png` | Team page — live |
| 2 | `tabbar-glass.png` | Tab bar glass |
| 3 | `settings.png` | Settings |
| 4 | `splash.png` | Splash |
| 5 | `schedule-cards.png` | Schedule cards |
| 6 | `standings-zones.png` | Standings zones |
| 7 | `widget-lockscreen.png` | Widget + Live Activity lock screen |

Portrait iPhone screenshots work best; the frame is 390 × 844 points
(about 9:19.5) and crops to fill with `object-fit: cover`.

### How the placeholder swap works

Each gallery entry is a `<figure>` whose `<img>` points at
`screenshots/<name>.png` and carries
`onerror="this.closest('figure').classList.add('missing')"`. While the file
is missing, the image fails to load, the figure gets the `missing` class, the
broken image is hidden and the CSS draws a labelled placeholder inside the
phone frame ("Screenshot placeholder — drop <name>.png into
site/screenshots/"). The caption shows in the `<figcaption>` either way.

To add a real screenshot, drop the PNG into `site/screenshots/` under its
filename, commit and push to `main`. Pages redeploys, the image loads and the
placeholder no longer appears. No HTML or CSS changes are needed.

A missing screenshot logs a 404 in the browser console; that's expected
until every PNG is in place.

## Deployment

`.github/workflows/pages.yml` deploys the site with GitHub Actions. It runs
on every push to `main` that touches `site/**` or the workflow itself, and
can be started by hand (workflow_dispatch). The build job uploads `site/` as
the Pages artifact (`actions/upload-pages-artifact`) and the deploy job
publishes it (`actions/deploy-pages`) to the `github-pages` environment.

The repository's Pages source must be set to "GitHub Actions" in
Settings → Pages.

## Constraints for future edits

- No CDNs, third-party fonts, external scripts, analytics or trackers. The
  site loads nothing from outside its own directory; keep it that way. Use
  the system font stack already in `index.html`.
- Keep it build-free: plain HTML and inline CSS.
- Keep it accessible: one `h1`, landmarks, alt text on every image, visible
  focus styles, WCAG AA contrast, and `prefers-reduced-motion` respected.
