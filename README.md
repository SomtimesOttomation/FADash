# FADash 2026-27

PowerShell 5.1 + WebView2 dashboard for English league football (Premier League, Championship, League One, League Two
and the cups), built in NBADash's look and feel. One dash for every league: pills at the top switch between them.
It runs on its own or as a tab in DashLauncher.

Status: work in progress. Data comes from ESPN's unofficial public JSON feeds (see Disclaimer). On first start, click
"Download clubs" on Home; after that scores, tables and squads load when you open them or press Refresh.

## First run
1. Unzip anywhere (for example `C:\Tools\FADash`).
2. Double-click `Start-FADash.bat`. On first run it downloads the WebView2 wrapper DLLs into `lib\` (no admin needed).
   The WebView2 runtime itself ships with Edge.

## Files
- `dash.json` what DashLauncher reads (id `fadash`, tab label `FA`, data sources).
- `Start-FADash.ps1` / `.bat` window, WebView2 and context for running on its own.
- `modules\FADash.Host.psm1` the backend (the dash contract functions, worker, settings, updater control).
- `Update-FADash.ps1` / `Apply-Update.ps1` update check, verified download, and the install-and-roll-back helper.
- `ui\` the web UI. Open `ui\index.html` through any static server for a made-up-data preview in a normal browser
  (`ui\dev\`, never used by the real dash).

## Fetching
Nothing is fetched until you ask. Automatic refresh is opt-in behind a warning, a hidden DashLauncher tab fetches
nothing on a timer, and the pause button in the navigation bar stops all data traffic. Update checks to GitHub are not
affected by the pause.

## Disclaimer
Unofficial and not affiliated with ESPN, any football league, club or data provider. FADash bundles no data.

FADash's data comes from ESPN's unofficial, public JSON feeds, fetched to your own computer for personal use. ESPN
publishes no terms or limits for these feeds, and they can change or stop at any time. Using them is the project owner's
own risk decision for a hobby project; it is not a permission from ESPN and no one at ESPN has approved it.
FADash keeps its use small and polite:

- Nothing is fetched until you ask. Automatic refresh is off by default; turning it on shows a warning first, and the
  interval can be lengthened.
- At most one request per second, and every request is counted on the traffic page.
- Only the public JSON feeds, no web-page scraping, no sign-in, no other ESPN products.
- No betting data: odds, lines and spreads are never read, saved or shown.
- Club crests are downloaded to your own cache folder the first time a club is shown; they are not part of this repository.
- This repository contains no ESPN data, only the code that fetches it.

Club names and badges belong to their owners.
