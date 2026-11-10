# Changelog

Changes are grouped by label: Feature, Bug/Fix, Redesign, Housekeeping. Every merged change lands under Unreleased first and moves to a version heading when that release is published.

Release rhythm: changes are merged as they are done without changing VERSION, and released in batches on Mondays and Thursdays. Real user-facing bugs can be released right away.

## Unreleased

### Redesign
- Brought FADash up to the current NBADash standard (NAVBAR-SPEC v0.21.x): page order topbar, kill-switch bar, sync strip, league bar, club banner, week bar, navigation bar; nothing above the navigation bar has a bottom margin and hidden bars take no space. Branch `redesign/standard-catch-up`.
- One dash, five pills in a new league bar: Premier League, Championship, League One, League Two, Cups. The football data is PRETEND (made-up clubs and fixtures, labelled as such) until a real source is chosen and its terms are checked.
- The league bar is FADash's own. The shared navigation bar (NAVBAR-SPEC) is unchanged and FADash adds nothing to it; the league bar is an extra bar above the club banner, like the banner and week bar are per-dash extras. Design that only FADash needs stays inside FADash.
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
- Windows PowerShell 5.1 note: the backend (`modules/FADash.Host.psm1`) and the scripts were tested under PowerShell 7 only; nobody has run them on Windows PowerShell 5.1 yet. They were searched by hand for PowerShell 7 only syntax (ternary, `??`, `?.`, `&&` and `||` between commands, `-AsHashtable`, `-AsByteStream`, `ForEach-Object -Parallel`, `Join-Path` with extra child paths, .NET Core only calls) and none was found. All scripts are ASCII-only (checked, and the release workflow checks it).

## Released
