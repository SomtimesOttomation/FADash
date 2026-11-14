# Changelog

Changes are grouped by label: Feature, Bug/Fix, Redesign, Housekeeping. Every merged change lands under Unreleased first and moves to a version heading when that release is published.

Release rhythm: changes are merged as they are done without changing VERSION, and released in batches on Mondays and Thursdays. Real user-facing bugs can be released right away.

## Unreleased

### Feature
- Real data only: FADash now always uses ESPN's public JSON feeds. The made-up PRETEND data, the hidden switch (`tools\Switch-FADash-Source.bat`, `Set-FADashSource.ps1`, the `source` setting) and the Pretend data settings tab are gone. A new install shows "Download clubs" on Home (four requests); nothing is fetched until the person asks. Branch `feature/real-data-default`.
- Upgrading from 0.2.x: the ESPN favourites become the favourites (the pretend ones are dropped), and the old pretend cache folders (`cache\pl`, `cache\ch`, ...) are removed once. The ESPN cache, clubs and crests are kept.
- The browser preview (`ui\dev\mock.js`, `ui\dev\pretend-clubs.json`) keeps made-up data for testing the page; the real dash never loads it.

## v0.2.1 (2026-11-12)

### Redesign
- Matches is the first section tab and opens the main page; Table is second. Matches stays highlighted on week pages.

## v0.2.0 (2026-11-12)

### Feature
- The real ESPN source, built but HIDDEN. Branch `feature/espn-worker`. Pretend data stays the default and what everyone sees; nothing about it changes for a person who installs FADash. The real source switches on only with the environment variable `FADASH_SOURCE=espn` or `"source":"espn"` in `%APPDATA%\FADash\settings.json` (`tools\Switch-FADash-Source.bat espn` does that; `pretend` switches it back), read when FADash starts. Nothing in the page offers it.
- `modules/FADash.Espn.psm1` downloads ESPN's public JSON (scoreboard, standings, teams, rosters, match summary) and converts it into FADash's own shapes. Each converter builds a new object from a short list of fields it names, so odds, spreads and the like cannot reach the cache or the page (tests check this against responses full of odds). Postponed, cancelled and abandoned matches arrive as upcoming matches with a detail, never as 0-0 results.
- Safeguards: one request per second whatever is queued; every request counted per server and per kind on the traffic page; only the known public feeds (the address is built from a fixed list, never from the page); paused traffic and the kill switch stop it; a week is one ranged request per competition, falling back to one request per day if ESPN refuses the range; nothing on a timer unless automatic refresh is on.
- Clubs are downloaded once on a click (Home notice, four requests, kept for a week). Crests are downloaded one at a time to `cache\espn\crests` the first time a club is drawn and are never bundled; the drawn shield stays until then and if a download fails. Clear saved data keeps the crest pictures.
- Real data differences: the roster feed has age and shirt number but no appearances, goals or cards, so the squad table shows dashes there; the table's form column is empty (ESPN's table has no form). Favourites are kept separately for pretend and real clubs. Season starts on the first Monday on or after 1 August. The Pretend data tab is hidden while the real source is on.
- Injuries and transfers: still no source; the hand-entered watch list stays. We loop back when a reliable source is found.
- Needs the owner: README Disclaimer and `dash.json` list ESPN and say what it is (unofficial, no published terms). The terms link in `dash.json` (`disneytermsofuse.com`) is the company-wide terms page, not terms for this API.

### Bug/Fix
- ESPN answered HTTP 403 to every request: it refuses FADash's own user-agent name. FADash now asks the way PowerShell does by default, which ESPN answers (checked on the owner's computer with `tools/Test-EspnAccess.bat`, 3 requests). HTTP errors now name the address path. Branch `fix/espn-403`.

### Redesign
- Brought FADash up to the current NBADash standard (NAVBAR-SPEC v0.21.x): page order topbar, kill-switch bar, sync strip, league bar, club banner, week bar, navigation bar; nothing above the navigation bar has a bottom margin and hidden bars take no space. Branch `redesign/standard-catch-up`.
- One dash, five pills in a new league bar: Premier League, Championship, League One, League Two, Cups. The football data is PRETEND (made-up clubs and fixtures, labelled as such) until a real source is chosen and its terms are checked.
- **Deviation from the shared page order (NAVBAR-SPEC):** FADash adds one element, `#leaguebar`, between the sync bar and the club banner, because the four tiers and the cups are separate competitions in one dash. Reason: pills for the competitions need to sit above the club banner and week bar that follow the open competition. It is additive: namespaced classes (`.fa-leaguebar`, `.fa-lg-pill`), no shared rule changed, nothing above the navigation bar has a bottom margin, and the hidden bar takes no space. The shared navigation bar and NAVBAR-SPEC are unchanged. If the owner says move it, it moves.
- FADash's own CSS additions use an `.fa-` prefix (league bar, club tiles' league tag, goals, zone stripes, form chips, search suggestions) so no shared class is restyled.
- Football match cards: HT, 45+2', FT, AET and penalties; draws are not dimmed; goal lines; a "Match centre" refresh button on live matches while automatic refresh is off.
- The Standings page is called Table (route `#/table`), one per league, with zone stripes (promotion, play-offs, relegation, European places) driven by the league config in ui/js/leagues.js, plus hover cards for every calculated number.
- Search over clubs and players with ghost completion, "/" to focus and Esc to clear.
- New football icon for the launcher tab.

### Design decisions: league pills inside one dash
- Data keys carry the league: `score:<lg>:<date>`, `week:<lg>:<monday>`, `standings:<lg>`, `team:<club id>`. The host keeps one cache folder per league (`cache\pl`, `cache\ch`, `cache\l1`, `cache\l2`, `cache\cup`), so one league can be refreshed or deleted alone.
- Clubs are keyed by the data source's team id; favourites are club ids and work across leagues.
- Banner: favourites from every league first (with a league tag when they are not in the open league), a divider, then the clubs of the open league. Cups show every club.
- Week bar: calendar weeks (Monday to Sunday) with saved matches for the open league, labelled by their Monday ("w/c 2 Nov"). Matchweek and cup-round labels need the real source and come later.
- Traffic is counted per data source (host), not per league; the traffic page lists each key, which carries the league. The open league is remembered per viewer.
- Changing league asks for nothing by itself except what that league's page shows, like opening any other page. Manual fetching stays the default.
- When matchweek and cup-round labels arrive, the Monday keys stay and the label is added on top, so saved weeks stay valid.

### Housekeeping
- Data sources report (`docs/DATA-SOURCES-REPORT.md`) and the probe scripts (`tools/Probe-FAFeeds.ps1` with its .bat launchers): 18 candidates checked; ESPN chosen, injuries and transfers parked until a reliable source turns up. Branch `housekeeping/data-sources-report`.
- Test drop-in builds 0.1.1 and 0.1.2 were made from `fix/espn-403`; main stays at 0.1.0 until the next release (0.2.0, because of the ESPN Feature).
- Windows PowerShell 5.1 note: the backend (`modules/FADash.Host.psm1`) and the scripts were tested under PowerShell 7 only; nobody has run them on Windows PowerShell 5.1 yet. They were searched by hand for PowerShell 7 only syntax (ternary, `??`, `?.`, `&&` and `||` between commands, `-AsHashtable`, `-AsByteStream`, `ForEach-Object -Parallel`, `Join-Path` with extra child paths, .NET Core only calls) and none was found. All scripts are ASCII-only (checked, and the release workflow checks it).

## Released
