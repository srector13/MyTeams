# myTeams site

The GitHub Pages one-pager for myTeams: `index.html` with inline CSS. No build
step, no JS beyond the screenshot fallback, nothing loaded from outside `site/`.
Sections: header, hero, feature grid, screenshots, download line, footer.

## Screenshots

Drop portrait iPhone PNGs (390 × 844 frame, cropped with `object-fit: cover`)
into `site/screenshots/` using exactly these names:

`team-page-dark.png`, `tabbar-glass.png`, `settings.png`, `splash.png`,
`schedule-cards.png`, `standings-zones.png`, `widget-lockscreen.png`

Until a file exists, its `<img>` `onerror` adds the `missing` class to the
figure and CSS draws a labelled placeholder in the phone frame. Once the PNG
is committed, the real shot shows. No HTML changes needed.

## Deployment

`.github/workflows/pages.yml` publishes `site/` to GitHub Pages on every push
to `main` that touches `site/**` (or by hand via workflow_dispatch). The repo's
Pages source must be set to "GitHub Actions".
