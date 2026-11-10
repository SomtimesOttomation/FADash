# FADash data sources report

Status: DRAFT 4 (probe and deep-check results from 2026-11-09 added) for NBADash's and the owner's review (hand-off v2, item A1). Nothing has been built on any source; the real worker is not approved. Written 2026-11-09. Draft 2 adds candidates 5 to 18 (the owner's list, plus ESPN and BBC) and applies the owner's rules: free only, all four tiers for 2026-27 or say exactly which, terms that allow a personal app with caching and display, no betting data, no scraping (a website with no official API and published terms counts as scraping).

## Read this first: what is checked and what is not

- I cannot reach these sites from the build environment, so the probe was run by the owner on a Windows PC on 2026-11-09 (22:10). **Probe results** below are primary evidence for what each source returned. API-Football was not probed (no key was entered), so everything about it is still from its documentation and UNVERIFIED.
- Terms and limits below are quoted from pages I could read (marked **primary**) or from third-party pages (marked **secondary**, treat as unconfirmed). Where I could not read a page I say **UNVERIFIED**. Do not build on an UNVERIFIED line before the terms page has been read in full.
- ESPN is probed as one more candidate under the shared project policy (see candidate 17). The probe output file is not committed; it holds the owner's account name for football-data.org in one header, which has been removed from the probe for next time.

## Summary and proposal

| Layer | Source | Covers | Key? | Live? | Betting data in it? |
|---|---|---|---|---|---|
| 1 base | openfootball/england (GitHub) | **Premier League and Championship only for 2026-27** (the probe found just `1-premierleague.txt` and `2-championship.txt`) | none | No | No |
| 2 live, option a | football-data.org | **Probe confirmed:** a free key sees the Premier League and Championship only (plan TIER_ONE), season 2026, 10 requests a minute | free key | Delayed on free plan (secondary) | Not mentioned in terms |
| 2 live, option b | API-Football | All four tiers (per their pricing page: "All our plans include all competitions and endpoints."), 100 requests a day free | free key | Fixtures update every 15 seconds in play | **Yes, it has odds endpoints: never called** |
| 3 candidate (owner's risk decision) | ESPN public JSON (unofficial) | **Probe confirmed: all four tiers for 2026-27 plus FA Cup, Carabao Cup, Community Shield and EFL Trophy** | none | Yes (state, score and goal/card details per match; behaviour during play not yet seen) | **Odds keys are in the responses: dropped by a whitelist** |
| excluded by the owner | football-data.co.uk | CSV results for English tiers | none | No (weekly, secondary) | **Yes, odds columns in every file** |

Proposal (for your decision, based on the probe):

1. **Make ESPN the main source, if you accept it for football.** It is the only candidate that serves all four tiers for 2026-27, needs no key, and returns live state, scores, goals and cards, tables, line-ups, match events and crests. It comes with the shared safeguards in candidate 17. It gives players with ages. It has no injuries in match summaries (a per-player injuries field exists and is not yet checked) and no transfers seen.
2. **openfootball and football-data.org are not needed for the first release if ESPN is accepted.** Both cover only the Premier League and Championship. openfootball stays a possible offline fallback for those two tiers; football-data.org needs a key and gives delayed scores.
3. **API-Football stays optional** (each person's own key) for what ESPN lacks: injuries, transfers, players and ages. Its terms are still unread and it was not probed.
4. **If you do not accept ESPN:** the plan falls back to openfootball for two tiers, and League One and League Two have no source that passes.
5. **Not proposed:** football-data.co.uk (excluded by the owner); candidates 5 to 16 and 18 (all fail).
6. **Still without a source:** injuries, transfers, free agents. Ship the watch list with hand-entered players.

Open question for you: do you accept ESPN for football, on the same terms as NBADash? If yes, a deep probe (League One and League Two checks, player data) is the last step before the worker.

## Probe results (run by the owner on Windows, 2026-11-09 22:10)

19 requests at one per second, no errors, no odds saved, API-Football skipped (no key).

| Source | What came back |
|---|---|
| openfootball | The `2026-27` folder holds only `1-premierleague.txt` and `2-championship.txt`. The Premier League file has 380 matches planned, runs "Fri Aug 21 2026 - Sun May 30 2027", and already shows results with half-time scores (about 95 score-like patterns, which includes half-time scores). Raw file 22.8 KB, 259 ms. Plain `text/plain` with an ETag. GitHub API rate limit showed 59 remaining of 60 an hour. **League One and League Two are not available for 2026-27.** |
| football-data.org (free key) | Competitions visible in England: Championship (ELC) and Premier League (PL), both plan TIER_ONE, 13 competitions in all. Standings and matches both returned for season 2026. A 7-day match window returned 10 played matches in 346 ms. The rate limit header showed 9, then 8, then 7 requests available in the minute, which matches 10 a minute. **No League One or League Two.** |
| API-Football | Not probed. |
| ESPN | See candidate 17 for the full results. All eight English competitions answered. |
| ESPN deep check (22:23, 8 requests, no errors) | Saturday 7 November Championship: 11 matches, all full time, with 4 to 16 goal/card entries each; a Championship summary had 19 key events, 90 commentary lines, two line-ups of 20 players (11 starters, formation, subbed-in and subbed-out flags). League One and League Two returned **0 events on that Saturday** (probably no league fixtures that weekend; not confirmed). Tables for League One and League Two: 24 rows each, season 2026. A League One team roster (30 players, 221 KB) carried age, date of birth, position, jersey, height, weight, citizenship and an `injuries` field. |

## Candidate 1: openfootball/england (public domain files on GitHub)

- **What it covers:** the repo's README describes four levels ("I: English Premier League (20 clubs), II: English Championship (24 clubs), III: English League One (24 clubs), IV: English League Two (24 clubs)") and has season folders from 2000-01 through 2026-27. **Correction after the probe: the 2026-27 folder contains only the Premier League and Championship files, so League One and League Two are not covered this season.** I wrongly read the README as promising all four tiers for the current season. Format is Football.TXT (plain text matches, with scores once played). Fixtures and results by round: yes, as listed in the files. Tables: not provided, computed by us. Line-ups, match events, team stats, players and ages, injuries, transfers, crests: not provided (the page shows squad lists in the format but I did not confirm they are filled for England). Cups: not confirmed (the repo has other folders I could not inspect).
- **Access:** open, no key. Files are served by GitHub (raw files or the repo), so GitHub's own limits apply (unauthenticated API: 60 requests an hour per address; raw file downloads are not counted the same way, **UNVERIFIED**). Live update speed: none. Delay on results: unknown, depends on volunteers. The repo shows 1,131 commits but I could not see the last commit date. The probe showed the Premier League file already has results from the opening weeks; no `Last-Modified` header was returned (only an ETag).
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
- **Probe (2026-11-09):** a free key sees only the Championship (ELC) and Premier League (PL), both plan TIER_ONE. Standings (season 2026) and a 7-day match window both worked. The response headers confirmed the 10-requests-a-minute limit. Fields in the matches list beyond the first lines were not inspected.
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

**Result: none of candidates 5 to 18 passes except ESPN (17), which is pending the probe and the owner's decision.** Most are websites with no official API (so any use is scraping, which is out), and the rest need payment or are Premier League only. Details and quotes follow the table.

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
| 17 | ESPN | PASS on coverage and rules, owner decides (shared ESPN policy) | Probe: all four tiers for 2026-27, four cups, live state, tables, events, line-ups, crests, no key; unofficial, so it can change or stop. |
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
- **17. ESPN (unofficial public JSON endpoints, no key).** Same policy as NBADash and NHLDash (injuries and transactions), which use these endpoints as publicly accessible data, with a README "Disclaimer" section, a terms link in `dash.json` and a note in `ARCHITECTURE.md`. This is the owner's risk decision for a hobby project, not a legal clearance and not anything ESPN has agreed to. The wording to use is the README's: unofficial, no published terms or limits from ESPN for this API, can change or stop at any time. Community pages (secondary) show the pattern `https://site.api.espn.com/apis/site/v2/sports/soccer/<league>/scoreboard` (also `/summary?event=<id>`, `/teams`, and `/apis/v2/sports/soccer/<league>/standings`); `eng.1` is the only English code those pages confirm, and the Championship, League One, League Two and cup identifiers are UNVERIFIED, so the probe looks them up rather than assuming them. Safeguards (all of them): no ESPN data in the repo; manual fetching by default, automatic refresh opt-in behind a warning; one request per second and nothing on a timer; only public JSON endpoints, no HTML pages, no login, no other ESPN products; crests fetched to the person's cache, never bundled; **no betting data: the converter keeps a whitelist of fields so odds objects are never cached or shown, and the probe output strips them**; the README disclaimer and terms link in `dash.json`. **Probe results (owner's PC, 2026-11-09, 13 ESPN requests, all answered, none blocked):**
  - **Competitions:** ESPN's own league list (220 leagues) gave these English men's identifiers: `eng.1` Premier League, `eng.2` (named "English League Championship"), `eng.3` League One, `eng.4` League Two, `eng.fa` FA Cup, `eng.league_cup` Carabao Cup, `eng.charity` Community Shield, `eng.trophy` EFL Trophy. Every scoreboard returned season 2026 with events from August to November 2026, so the current season is served. Responses took 65 to 245 ms; sizes were 13 to 207 KB.
  - **Fixtures, results and live state:** each event has an id, date, state (pre, in or post), both sides with abbreviation and score. Scoreboards for the Premier League, Championship and cups list goals and cards per match (5 to 12 entries) without a second call, so scorers can show on the match list.
  - **Match summary (one Premier League match, 409 KB, 416 ms):** 33 key events (kick-off, yellow cards, goals), 2 line-ups (`rosters`), team box score for both teams, 106 commentary lines. No injuries key in a match summary.
  - **Tables:** Premier League 20 rows and Championship 24 rows, with games played, wins, ties, losses, goals for and against, goal difference, points, points per game, rank and a `deductions` field. League One and League Two tables were not requested yet.
  - **Teams and crests:** the Championship team list returned 24 teams with a logo (fetched to cache on first use, never bundled).
  - **Odds:** the match summary carried `hasOdds` and two other odds-related keys; the probe counted them and did not print them. The worker must keep a whitelist.
  - **Deep check (owner's PC, 2026-11-09 22:23, 8 more requests):**
    - **Championship** on Saturday 7 November: 11 matches, all `STATUS_FULL_TIME`, each with 4 to 16 goal/card entries on the scoreboard. A match summary (392 KB, 463 ms) had 19 key events, 90 commentary lines and two line-ups of 20 players each (11 starters, formation `4-2-3-1`, flags for subbed in and out, a stats block per player).
    - **League One and League Two tables:** 24 rows each, season 2026.
    - **Players and ages: yes.** A League One team roster (AFC Wimbledon, 30 players, 221 KB, 228 ms) carried age, date of birth, position, jersey, height, weight, birthplace, citizenship, statistics and an `injuries` field. Sample: age 32, born 1994, goalkeeper, shirt 20. Rosters are large, so they would be fetched one team at a time, on demand.
    - **Injuries: possibly.** Each player has an `injuries` field; the probe did not count how many were filled in (the next probe does). Match summaries have no injuries key.
    - **Not seen: League One and League Two completed matches.** Both scoreboards returned 0 events for Saturday 7 November, so I still have not seen their match data. The earlier 14 November oddity (some fixtures showing state "post" at 0-0 with no details) is also unexplained, because the first probe did not print status names. The next probe looks back up to five Saturdays for each league and prints the upcoming Saturday's status names.
    - **Not seen: transfers, and how it behaves in play** (the probes ran on a Monday night with no live match).

Verdict: **PASS on coverage and the project rules, with the owner's risk decision.** It is the strongest candidate on coverage. The owner has doubts about ESPN for football specifically; the open points are League One and League Two match data (not seen yet), live behaviour, whether injuries are filled in, and the fact that it is unofficial and can change or stop at any time.

- **18. BBC.** No public football data API or feed was found. BBC Sport is a website, so any use would be scraping. The BBC Terms of Use page I could reach (a 2020 archive) says "We want everyone to enjoy the BBC. But there are a few rules to stick to." and points to explainers; the full text could not be read: UNVERIFIED. Secondary: news items from this year report the BBC objecting to an AI company reproducing its content (headlines only; I did not read them in full). Verdict: out.

Also noted: the soccerdata package, which many of these scrapers use, says "Please use this web scraping tool responsibly and in compliance with the terms of service of the websites you intend to scrape" and that "any changes to the scraped websites will break the package." That is a reminder of the stability risk for any site that is not an API.

### Ranking of everything that passes or could pass (updated with the probe)

Of candidates 5 to 18 only ESPN (17) passes; the others fail. Ranked by what each adds, using the probe where there is one:

1. **ESPN (candidate 17), if the owner accepts it.** All four tiers for 2026-27 plus FA Cup, Carabao Cup, Community Shield and EFL Trophy; no key; live state and scores; goals and cards on the match list; tables (Premier League and Championship verified); line-ups, key events, commentary and team stats per match; crests. Unlocks: match events, line-ups, players and ages, crests, and live scores for all four tiers. Players and ages are served (team rosters), and League One and League Two tables are served. Missing or unseen: injuries (none in match summaries; a per-player field exists), transfers, League One and League Two completed matches, live behaviour. Risk: unofficial; can change or stop at any time; odds keys must be whitelisted out.
2. **API-Football (candidate 3), if its terms pass.** Not probed and terms unread. All four tiers in principle, and the only candidate documented to carry injuries, transfers and players with ages. Free plan: 100 requests a day. Best used as an optional layer with each person's own key.
3. **openfootball/england (candidate 1).** No key, public domain, but only the Premier League and Championship for 2026-27, results and fixtures only, not live. Possible offline fallback; it no longer qualifies as a four-tier base layer.
4. **football-data.org (candidate 2).** Free key, Premier League and Championship only (confirmed), 10 requests a minute, delayed scores. Adds little if ESPN is used.

Excluded by the owner: football-data.co.uk (4).

## What each source gives, against your list

| Need | openfootball | football-data.org (free) | API-Football (free) | ESPN (probe) |
|---|---|---|---|---|
| Tiers for 2026-27 | Premier League, Championship | Premier League, Championship | all four (UNVERIFIED) | all four, plus four cups |
| Fixtures and results | yes | yes | UNVERIFIED | yes |
| Live state and scores | no | delayed (secondary) | documented, UNVERIFIED | yes, state and score; behaviour in play not yet seen |
| Tables | computed by us | yes | yes | yes, all four tiers |
| Line-ups | no | no (secondary) | documented, UNVERIFIED | yes (in the match summary) |
| Match events (goals, cards, subs) | goals only if listed in the files | no (secondary) | documented, UNVERIFIED | yes (key events and commentary; goals and cards also on the scoreboard) |
| Team stats | no | add-on (secondary) | documented, UNVERIFIED | team box score in the summary |
| Players and ages | no | UNVERIFIED | documented, UNVERIFIED | yes, from team rosters (age, date of birth, position, jersey; about 220 KB per team) |
| Injuries | no | UNVERIFIED | documented, UNVERIFIED | not in match summaries; a per-player `injuries` field exists, contents not yet checked |
| Transfers | no | UNVERIFIED | documented, UNVERIFIED | not seen |
| Crest images | no | UNVERIFIED (terms silent) | UNVERIFIED | yes, logo URLs in the team list (fetch to cache) |
| Cups | not confirmed | UNVERIFIED | UNVERIFIED | FA Cup, Carabao Cup, Community Shield, EFL Trophy |

Crests: club crests are trademarks, so even where an API serves them I would only fetch to the person's own cache on first use (30-day cache like NHLDash's logos), never bundle them, and fall back to the drawn crest with the club's letters (what the pretend data uses now) when a source does not allow them.

## How the rules are met

| Rule | How |
|---|---|
| Manual fetching by default; automatic only as an opt-in behind a warning | Already built: Settings > Data, warning and acknowledgement. No source changes this. |
| No betting data | Never call odds endpoints; the worker will only request URLs from a fixed list, so an odds URL cannot be requested. For files with odds columns, columns are dropped before anything is cached. |
| No API key in the repo or zip | Keys are typed in Settings and stored in the person's settings file only. football-data.org 6.1 says the same. |
| Crests fetched to the person's cache on first use | As above; not bundled. |
| Each source and its attribution in Settings > Data sources, requests counted separately | The traffic page already counts per host; each source gets its own host entry. football-data.org attribution text is required by 7.1. |
| Probe each candidate first | `tools/Probe-FAFeeds.ps1`, about 25 requests at one per second (openfootball, football-data.org, API-Football, ESPN), writes `tools\probe-output\fa-probe-<time>.txt` (not committed). |
| No scraping | Only published files, documented API endpoints and, for ESPN, the same public JSON endpoints NBADash uses (no HTML pages, no login). |

## Next steps

1. Owner: decide whether ESPN is accepted for football (same policy as NBADash). The report now shows ESPN is strong on coverage and players; the remaining gap is League One and League Two match data.
2. Run the second deep probe (`tools\Run-ProbeFAFeeds-ESPN-deep.bat`, up to about 18 requests, no key). It finds the latest Saturday with League One and League Two matches, reads one completed match from each, prints status names for the upcoming Saturday, counts filled-in injuries on one League One and one League Two roster, and sends back the file.
3. Optional: enter an API-Football key and run the full probe (`tools\Run-ProbeFAFeeds.bat`) so API-Football can be ranked on evidence; its terms still need reading in full first.
4. I finish this report with a final ranking and recommendation.
5. The worker is not built until the owner replies to the final report.
