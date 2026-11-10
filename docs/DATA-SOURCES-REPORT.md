# FADash data sources report

Status: DRAFT 2 for NBADash's and the owner's review (hand-off v2, item A1). Nothing has been built on any source; the real worker is not approved. Written 2026-11-09. Draft 2 adds candidates 5 to 18 (the owner's list, plus ESPN and BBC) and applies the owner's rules: free only, all four tiers for 2026-27 or say exactly which, terms that allow a personal app with caching and display, no betting data, no scraping (a website with no official API and published terms counts as scraping).

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
| excluded by the owner | football-data.co.uk | CSV results for English tiers | none | No (weekly, secondary) | **Yes, odds columns in every file** |

Proposal (for your decision):

1. **Base layer, no key:** build the table, results and fixtures from openfootball's public domain files. The table is computed from results, so every league has one. Nothing else is needed for the Table page, the Table Report (item 14), the week bar and the match list.
2. **Optional live layer, each person's own key:** football-data.org for the Premier League and Championship, and/or API-Football for all four tiers. Off until the person enters a key in Settings. Keys live in the person's settings file only.
3. **Not proposed:** football-data.co.uk (excluded by the owner: odds in every file); every candidate 5 to 18 below (none passes; see the pass/fail table).
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

## Candidate 4 (excluded by the owner, not probed): football-data.co.uk (CSV files)

- **What it covers:** English tiers as CSV files (the Premier League file is `E0.csv`; the other tiers are believed to be E1 to E3, **UNVERIFIED**), results and match statistics. Secondary sources (a modelling knowledge base and a Python library page): updated weekly in season and "not real-time"; "no API key, no registration, no rate limits"; the Premier League download has 111 columns, many of them bookmaker odds.
- **Terms: UNVERIFIED.** I found no terms or licence statement in any page I could read, and the site itself could not be fetched.
- **Why not proposed:** every file mixes odds in with the results, so using it means reading files that contain betting data. The owner has excluded it and it is not probed.

## Candidates 5 to 18 (added at the owner's request)

Rules applied: free only (a paid plan, paid trial, card on file or enterprise contract is out, no price comparison); all four English tiers for 2026-27 or exactly which; terms that allow a personal app on each person's machine with caching and display; no betting data; no scraping (a website with no official API and published terms counts as scraping); each person's own key in Settings; manual fetching by default.

**Result: none of candidates 5 to 18 passes.** Most are websites with no official API (so any use is scraping, which is out), and the rest need payment or are Premier League only. Details and quotes follow the table.

| # | Source | Result | One-line reason |
|---|---|---|---|
| 5 | FBref | FAIL | Website, no official API found; Sports Reference's data page says "Please do not attempt to aggressively spider data from our web sites." |
| 6 | Sofascore | FAIL | Website, no official API found; terms UNVERIFIED (could not be read); only third-party scrapers exist. |
| 7 | FotMob | FAIL | Website; its terms forbid scraping and bulk retrieval in as many words. |
| 8 | Understat | FAIL | Website, no official API found; terms UNVERIFIED; only unofficial scraper libraries. |
| 9 | Transfermarkt | FAIL (clear no) | No official API found; terms UNVERIFIED (could not be read). Without an official API, using it is scraping. Transfers and free agents stay without a feed. |
| 10 | Datahub EPL dataset | FAIL | Premier League only; last file is season 2025/26 (no 2026-27 file listed); derived from football-data.co.uk (excluded); "educational and research purposes only". |
| 11 | FootyStats CSVs | FAIL | CSV downloads need a login (only a 2018/2019 Premier League sample is free); automated use is steered to their separate API (terms and price not read); betting-oriented (BTTS columns). |
| 12 | Kaggle EPL 2025-26 | FAIL | Premier League 2025-26 only, licence UNVERIFIED, derived from scraped data per the owner's note. Page could not be read. |
| 13 | Opta / Stats Perform | FAIL | "designed for organisations rather than individual use"; pricing by sales. No free personal plan. |
| 14 | footballdata.io Premier League API | UNVERIFIED, treated as out | Site could not be read; Premier League only per the name; no free tier found. Out unless a free tier with personal-app terms is shown. |
| 15 | Enetpulse | FAIL | Business-to-business, sales-tailored pricing, a trial but no free plan. |
| 16 | Statorium | FAIL | Paid plans with a 5-day trial and a refund guarantee; no free plan on the pricing page. |
| 17 | ESPN | FAIL | ESPN closed its public API in 2014; the soccer endpoints are undocumented, so no published terms allow them. NBADash's use of ESPN is a separate matter for NBADash. |
| 18 | BBC | FAIL | No public football data feed found; BBC Sport is a website, so use would be scraping; full terms UNVERIFIED. |

Evidence for each (primary = the site's own page, secondary = anyone else; UNVERIFIED = I could not read it):

- **5. FBref.** Primary (Sports Reference "SR and Data Use" page, which covers the whole Sports Reference family; it does not name FBref or Opta): "Please do not attempt to aggressively spider data from our web sites." Their Terms of Use prohibit using "any automated means to access or use the Site" without written permission when it "adversely impacts site performance or access"; you may not use site content to "create any database, archive, or other data store that competes with or constitutes a material substitute"; and for some datasets "our licenses completely preclude any redistribution of the data." The page does not mention an API. FBref's own terms and its current data coverage: UNVERIFIED. Covers: Premier League to League Two stats (UNVERIFIED). Verdict: no official API, automated access restricted: out.
- **6. Sofascore.** Searches found only its privacy policy and third-party scrapers (Apify, Bright Data and similar). No developer API or terms about automated access found. Terms: UNVERIFIED. Verdict: no official API: out.
- **7. FotMob.** Primary (`fotmob.com/tos.txt`): "Use of the data, content, or any information displayed on FotMob for any purpose, including but not limited to scraping" ... "without the express written consent of FotMob is strictly prohibited."; "The use of automatic services (robots, spiders, etc.), as well as other methods" ... "for systematic, regular, or bulk retrieval of data, is forbidden."; the software licence is "for your own personal, non-commercial use." The terms do not mention an API. Verdict: out.
- **8. Understat.** Searches found only third-party scrapers and an unofficial Python library (its docs mention no official API or permission). Terms: UNVERIFIED. Verdict: no official API: out. It also covers only the top leagues, not all four tiers (UNVERIFIED).
- **9. Transfermarkt.** Searches found only third-party scrapers (Apify actors, R and Python packages). No official API and no terms I could read. Terms: UNVERIFIED. **Clear answer for the owner: no.** I cannot show that any use of Transfermarkt data is permitted, and with no official API it would be scraping. The transfers and free agent gap stays open: the watch list ships with hand-entered players, and a feed is only added if API-Football's terms (candidate 3) cover transfers and the owner is happy with them.
- **10. Datahub EPL dataset.** Primary (`datahub.io/core/english-premier-league`): "English Premier League" only, seasons "1993/94 through 2025/26" (one CSV per season), daily updates claimed, 22 columns with no odds columns listed. Licence: "This repository is distributed under the Open Data Commons Public Domain Dedication and License." But: "This dataset is sourced from Football Data UK and is intended for educational and research purposes only." Fails on tiers (Premier League only), current season (no 2026-27 file listed) and origin (football-data.co.uk).
- **11. FootyStats.** Primary (`footystats.org/download-stats-csv`): "You must Login to Download CSVs"; the free sample is the 2018/2019 Premier League; current-season files are listed for the Premier League, Championship, EFL League One and EFL League Two (the page does not say they are free); "Automated data downloads should use our API at Football Stats API." The file descriptions include "BTTS & Win" columns; the full column list was cut off, so odds columns cannot be ruled out. Price and API terms: UNVERIFIED. Verdict: needs a login and (probably) payment, betting-oriented, automated use only through a separate API whose terms I did not read: out.
- **12. Kaggle EPL 2025-26.** The dataset page could not be fetched. Searches found only older datasets by the same author (2023-24) with no licence shown. Per the owner's note it is Premier League 2025-26 only and partly derived from scraped FBref data. Licence: UNVERIFIED. Verdict: out.
- **13. Opta / Stats Perform.** Primary (Stats Perform pricing and licensing FAQ): the solutions are "designed for organisations rather than individual use"; pricing is quoted case by case through sales; "custom licensing is available by competition, country, or data level." No free or personal plan is mentioned. Verdict: out.
- **14. footballdata.io Premier League API.** The page could not be fetched and searches did not find it. Premier League only per its name. No free tier shown. Verdict: UNVERIFIED, out until shown otherwise.
- **15. Enetpulse.** Primary (FAQ): "Contact our sales team and they will be ready to tailor a package that suits your business."; a trial of "up to 30 days" in one place and "for free for two weeks" in another; the page lists business clients (live score apps, media, broadcasters) and says nothing about individuals; no odds product is mentioned. No free plan. Verdict: out.
- **16. Statorium.** Primary (pricing page): "Starter, advanced and enterprise plans", "5-day trial available", "30-days full satisfaction or refund guarantee with any subscription"; no free plan is mentioned. Its Terms of use page was not read. Verdict: paid: out.
- **17. ESPN.** Secondary (App Developer Magazine, 12 August 2014): ESPN closed its public API; it stopped issuing keys and existing keys were deactivated on 8 December 2014; the article does not say whether any ESPN API remains public. The soccer scoreboard endpoints that NBADash-style dashes use are not documented by ESPN, so there is no published API terms page to quote. ESPN's own Terms of Use could not be retrieved (the ESPN page I could fetch was the licence for a discontinued desktop program and does not cover scraping); a Disney+ terms excerpt (secondary, ConductAtlas, captured 22 April 2026) prohibits "access, monitor, copy, or extract the Services using a robot, spider, script or other automated means", which suggests the same family of wording but is not ESPN's own text: UNVERIFIED. Under the owner's rule (no official API plus published terms = scraping) it fails. If NBADash wants to keep ESPN, that is its own call.
- **18. BBC.** No public football data API or feed was found. BBC Sport is a website, so any use would be scraping. The BBC Terms of Use page I could reach (a 2020 archive) says "We want everyone to enjoy the BBC. But there are a few rules to stick to." and points to explainers; the full text could not be read: UNVERIFIED. Secondary: news items from this year report the BBC objecting to an AI company reproducing its content (headlines only; I did not read them in full). Verdict: out.

Also noted: the soccerdata package, which many of these scrapers use, says "Please use this web scraping tool responsibly and in compliance with the terms of service of the websites you intend to scrape" and that "any changes to the scraped websites will break the package." That is a reminder of the stability risk for any site that is not an API.

### Ranking of everything that passes or could pass

Nothing from 5 to 18 passes, so the plan does not change. Ranked by what each remaining source adds (current plan: no-key base plus an optional key):

1. **API-Football (candidate 3), if its terms pass.** All four tiers in principle, live fixtures every 15 seconds, and the only candidate documented to carry line-ups, match events, team stats, players with ages, injuries, transfers and crests. Needs: terms read in full, confirmation that the free plan returns the 2026-27 season, 100 requests a day is enough for manual fetching. Unlocks the most missing features.
2. **openfootball/england (candidate 1).** The only one that already passes every requirement: all four tiers, a 2026-27 folder, public domain, no key. Not live, and results only. It is the base layer. Unlocks the Table page, results, fixtures and the Table Report; nothing else.
3. **football-data.org (candidate 2).** Free key, but Premier League and Championship only (secondary), delayed scores, no line-ups or cards on the free plan. Adds little over API-Football and covers two of four tiers. Its terms are readable and fit our key rule. A fallback if API-Football's terms fail.

Excluded by the owner: football-data.co.uk (4).

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
| Probe each candidate first | `tools/Probe-FAFeeds.ps1`, about 12 requests at one per second (openfootball, football-data.org, API-Football), writes `tools\probe-output\fa-probe-<time>.txt` (not committed). |
| No scraping | Only published files and documented API endpoints are used. |

## Next steps

1. Run the probe on a Windows machine (double-click `tools\Run-ProbeFAFeeds.bat`; keys optional) and send me the output file. It contains no keys.
2. Read the API-Football terms page and football-data.org's pricing page in full (I could not), and the football-data.co.uk notes if that source is ever wanted.
3. Decide the layers (see the open question above). The worker is not built until NBADash and the owner have replied.
4. Probes: only for candidates whose terms pass. That is openfootball, football-data.org and API-Football; the probe script no longer touches football-data.co.uk (the owner excluded it). No site that forbids or lacks permission for automated access is probed.
