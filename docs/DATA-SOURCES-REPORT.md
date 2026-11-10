# FADash data sources report

Status: DRAFT for NBADash's review (hand-off v2, item A1). Nothing has been built on any source. Written 2026-11-09.

## Read this first: what is checked and what is not

- I could not reach any of these sites from the build environment (its network only allows package registries and GitHub's own hosts), so **no probe has been run yet**. The probe script is ready (`tools/Probe-FAFeeds.ps1`, run it with `tools\Run-ProbeFAFeeds.bat`) and prints what each source returns; its output finishes this report.
- Terms and limits below are quoted from pages I could read (marked **primary**) or from third-party pages (marked **secondary**, treat as unconfirmed). Where I could not read a page I say **UNVERIFIED**. Do not build on an UNVERIFIED line before the terms page has been read in full.
- I have not checked ESPN. NBADash's choice of ESPN is not assumed for football.

## Summary and proposal

| Layer | Source | Covers | Key? | Live? | Betting data in it? |
|---|---|---|---|---|---|
| 1 base | openfootball/england (GitHub) | Fixtures and results, all four English tiers | none | No (community updated, lag unknown) | No |
| 2 live, option a | football-data.org | Premier League and Championship on the free plan (secondary); League One and Two are not on the free plan (secondary) | free key | Delayed on free plan (secondary) | Not mentioned in terms |
| 2 live, option b | API-Football | All four tiers (per their pricing page: "All our plans include all competitions and endpoints."), 100 requests a day free | free key | Fixtures update every 15 seconds in play | **Yes, it has odds endpoints: never called** |
| not proposed | football-data.co.uk | CSV results for English tiers | none | No (weekly, secondary) | **Yes, odds columns in every file** |

Proposal (for your decision):

1. **Base layer, no key:** build the table, results and fixtures from openfootball's public domain files. The table is computed from results, so every league has one. Nothing else is needed for the Table page, the Table Report (item 14), the week bar and the match list.
2. **Optional live layer, each person's own key:** football-data.org for the Premier League and Championship, and/or API-Football for all four tiers. Off until the person enters a key in Settings. Keys live in the person's settings file only.
3. **Not proposed:** football-data.co.uk (odds in every file, and I could not find its terms); any site that forbids scraping.
4. **Still without a source:** injuries, transfers, free agents. Ship the watch list with hand-entered players and leave the feed out until a source passes the terms check (as your section C says).

Open question for you: is a base layer that is not live acceptable for the first release (fixtures, results and tables only, live scores added when a person adds a key)?

## Candidate 1: openfootball/england (public domain files on GitHub)

- **What it covers:** four levels: "I: English Premier League (20 clubs), II: English Championship (24 clubs), III: English League One (24 clubs), IV: English League Two (24 clubs)". Season folders run from 2000-01 through 2026-27, so the current season has a folder. Format is Football.TXT (plain text matches, with scores once played). Fixtures and results by round: yes, as listed in the files. Tables: not provided, computed by us. Line-ups, match events, team stats, players and ages, injuries, transfers, crests: not provided (the page shows squad lists in the format but I did not confirm they are filled for England). Cups: not confirmed (the repo has other folders I could not inspect).
- **Access:** open, no key. Files are served by GitHub (raw files or the repo), so GitHub's own limits apply (unauthenticated API: 60 requests an hour per address; raw file downloads are not counted the same way, **UNVERIFIED**). Live update speed: none. Delay on results: unknown, depends on volunteers. The repo shows 1,131 commits but I could not see the last commit date. The probe prints `Last-Modified`/`ETag` and the file's result count, which answers this.
- **Terms (primary, README):** the data is "dedicated to the public domain. Use as you please with no restrictions whatsoever." The page links a LICENSE.md I did not read in full.
- **Risks:** volunteer run, so freshness and completeness can lag; not a live feed; file layout can change. No betting data. No crests. Public domain, so no attribution is required, but I would credit it anyway in Settings > Data sources.

## Candidate 2: football-data.org (API v4, free key)

- **What it covers:** secondary source (TheStatsAPI blog, repeating football-data.org's pricing; **unconfirmed**, their pricing page could not be fetched): the free plan has 12 competitions including the Premier League and Championship; League One and League Two are not on the free plan; free plan has delayed scores and schedules, and no line-ups, substitutions or cards (those need a paid plan); shot and possession stats need an add-on. Tables: yes. Players and ages, injuries, transfers, crests: **UNVERIFIED** (the API is known to return crest links; their rules on caching or showing crests are not stated in the terms I read).
- **Access:** key required. **Primary (docs.football-data.org policies):** "Registered clients are allowed for 10 requests/minute in the free plan"; unregistered clients get "100 requests per 24 hours" and "can only access the area and competition list resources."
- **Terms (primary, api.football-data.org/register, General Terms and Conditions):**
  - 2.3: "The API Key applies to a single Application, in its web and/or mobile form and on any platform."
  - 6.1: "Developer credentials may not be stored in code repositories of open source projects." (Fits our rule: keys never go in the repo or the zip.)
  - 7.1: attribution is required: "Football data provided by the Football-Data.org API", in a footer, about page or other visible location.
  - 9.1: "After cancellation of the subscription to the Service, the Customer is not permitted to reference the football data." (So "Clear saved data" must be easy, and we should say so in Settings.)
  - 3.3: usage is monitored under a fair usage policy.
  - Not addressed in the terms I read: personal versus commercial use, caching or storing data, redistribution, betting. Treat caching as unconfirmed and ask them if it matters.
- **Risks:** one-person-scale service, free plan can change; scores delayed on the free plan; the key is per application, so each person registers their own key.

## Candidate 3: API-Football (api-sports.io, free key)

- **What it covers:** pricing page (primary): "All our plans include all competitions and endpoints."; free plan "100 Requests / day"; "No credit card required for the free version." Their beginner guide (primary, api-football.com news): "The free tier gives you 100 requests per day and access to every endpoint without exception." and "The fixture endpoint updates every 15 seconds during live matches." League ids 39 to 42 for the four English tiers are from my own knowledge, **UNVERIFIED**; the probe lists them. Line-ups, events, team stats, players, injuries, transfers, crests: the API is documented as having these, **UNVERIFIED** for English tiers 3 and 4 and for the free plan.
- **Access:** key required (sent in a header). 100 requests a day: a four-league refresh is about 4 requests, so it is enough for manual fetching. Per-minute limit: their guide says one exists but does not give the free number; it is returned in response headers, which the probe prints. Whether the free plan includes the **current season** is not confirmed (the guide says "recent seasons"); the probe checks this with one fixtures call.
- **Terms: UNVERIFIED.** The terms page failed to load, so I have nothing to quote on personal use, caching, display, attribution or scraping. **Must be read in full before any build.**
- **Risks:** it bundles betting data (odds and in-play odds endpoints, bookmaker and bet-type reference endpoints). We never call, store or show any of it. A single commercial provider, free plan can change.

## Candidate 4 (not proposed): football-data.co.uk (CSV files)

- **What it covers:** English tiers as CSV files (the Premier League file is `E0.csv`; the other tiers are believed to be E1 to E3, **UNVERIFIED**), results and match statistics. Secondary sources (a modelling knowledge base and a Python library page): updated weekly in season and "not real-time"; "no API key, no registration, no rate limits"; the Premier League download has 111 columns, many of them bookmaker odds.
- **Terms: UNVERIFIED.** I found no terms or licence statement in any page I could read, and the site itself could not be fetched.
- **Why not proposed:** every file mixes odds in with the results, so using it means reading files that contain betting data and discarding it. The probe script reads only the header and non-betting columns and keeps no odds. I suggest not using this source unless the base layer proves too slow.

## What each source gives, against your list

| Need | openfootball | football-data.org (free) | API-Football (free) |
|---|---|---|---|
| Fixtures and results by round | yes | PL, Championship | all four tiers (UNVERIFIED) |
| Tables | computed by us | yes | yes |
| Line-ups | no | no (secondary) | documented, UNVERIFIED |
| Match events (goals, cards, subs) | goals only if listed in the files | no (secondary) | documented, UNVERIFIED |
| Team stats | no | add-on (secondary) | documented, UNVERIFIED |
| Players and ages | no | UNVERIFIED | documented, UNVERIFIED |
| Injuries | no | UNVERIFIED | documented, UNVERIFIED |
| Transfers | no | UNVERIFIED | documented, UNVERIFIED |
| Crest images | no | UNVERIFIED (terms silent) | UNVERIFIED |
| Cups | not confirmed | UNVERIFIED | UNVERIFIED |

Crests: club crests are trademarks, so even where an API serves them I would only fetch to the person's own cache on first use (30-day cache like NHLDash's logos), never bundle them, and fall back to the drawn crest with the club's letters (what the pretend data uses now) when a source does not allow them.

## How the rules are met

| Rule | How |
|---|---|
| Manual fetching by default; automatic only as an opt-in behind a warning | Already built: Settings > Data, warning and acknowledgement. No source changes this. |
| No betting data | Never call odds endpoints; the worker will only request URLs from a fixed list, so an odds URL cannot be requested. For files with odds columns, columns are dropped before anything is cached. |
| No API key in the repo or zip | Keys are typed in Settings and stored in the person's settings file only. football-data.org 6.1 says the same. |
| Crests fetched to the person's cache on first use | As above; not bundled. |
| Each source and its attribution in Settings > Data sources, requests counted separately | The traffic page already counts per host; each source gets its own host entry. football-data.org attribution text is required by 7.1. |
| Probe each candidate first | `tools/Probe-FAFeeds.ps1`, about 15 requests at one per second, writes `tools\probe-output\fa-probe-<time>.txt` (not committed). |
| No scraping | Only published files and documented API endpoints are used. |

## Next steps

1. Run the probe on a Windows machine (double-click `tools\Run-ProbeFAFeeds.bat`; keys optional) and send me the output file. It contains no keys.
2. Read the API-Football terms page and football-data.org's pricing page in full (I could not), and the football-data.co.uk notes if that source is ever wanted.
3. Decide the layers (see the open question above). The worker is not built until NBADash and the owner have replied.
