<#
.SYNOPSIS
    Calls each candidate football data source once and records what comes back. Run it yourself, on your own computer.
.DESCRIPTION
    Windows PowerShell 5.1. This is the probe step of the Data Sources report (docs/DATA-SOURCES-REPORT.md). It makes a
    handful of requests (about 25 in total), one per second, and writes everything it sees to
    tools\probe-output\fa-probe-<time>.txt (not committed: see .gitignore).

    What it does NOT do:
      - It never calls an odds, lines or spreads endpoint, and it never prints or saves the odds columns of any file.
      - It never prints your API keys. Keys are read from the environment variables below, or typed in when asked
        (nothing is typed in when you press Enter: that source is skipped). Keys are never written to a file.
      - It does not scrape any website. Every URL is a published file or a documented API endpoint.

    Keys (both optional; sources without a key are skipped):
      FADASH_FOOTBALLDATA_KEY   football-data.org  (free key, register on their site)
      FADASH_APIFOOTBALL_KEY    API-Football       (free key, register on their site; the free plan has 100 requests per day)

    Run with -Deep (Run-ProbeFAFeeds-ESPN-deep.bat) to do only the ESPN deep check: up to about 18 requests.

    Sources probed:
      1. openfootball/england (public domain text files on GitHub): lists the season folder, reads one league file.
      2. football-data.org (API, key): competition list, then Premier League and Championship matches and table.
      3. API-Football (API, key): status, English leagues, and one fixtures call. Four requests at most.
      4. ESPN (unofficial public endpoints, no key; owner risk decision): a league list to find the English identifiers, up to 8 scoreboards,
         one match summary, two tables and one team list (about 13 requests). Odds-related keys are never printed or saved.
    Only sources whose terms allow this are probed. football-data.co.uk is excluded by the owner (odds in every file).
    Sites with no official API (FBref, Sofascore, FotMob, Understat, Transfermarkt, BBC and similar) are never contacted.

    Send the output file back so the report can be finished with real numbers (fields, headers, rate limits, empty responses).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Probe-FAFeeds.ps1
#>
param(
    [string]$Season = '2026-27',      # folder name used by openfootball
    [switch]$Deep                     # only the ESPN deep check (League One, League Two, status names, players)
)

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$outDir = Join-Path $PSScriptRoot 'probe-output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$outFile = Join-Path $outDir ('fa-probe-{0}.txt' -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$script:Count = 0

function Out-Both {
    param([string]$Text)
    Write-Host $Text
    Add-Content -LiteralPath $outFile -Value $Text -Encoding UTF8
}
function Hide-Key {
    param([string]$Text, [string[]]$Keys)
    foreach ($k in $Keys) { if ($k) { $Text = $Text.Replace($k, '<key>') } }
    return $Text
}
function Get-Probe {
    <# One request. Returns @{ Ok; Status; Headers; Body; Ms; Bytes }. Waits 1 second first (be gentle). #>
    param([string]$Url, [hashtable]$Headers = @{}, [string[]]$Keys = @())
    Start-Sleep -Milliseconds 1000
    $script:Count++
    $t0 = Get-Date
    $res = @{ Ok = $false; Status = 0; Headers = @{}; Body = ''; Ms = 0; Bytes = 0 }
    try {
        $r = Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing -TimeoutSec 30 -UserAgent 'FADash-probe/0.1 (personal use; one-off check)'
        $res.Ok = $true; $res.Status = [int]$r.StatusCode; $res.Body = [string]$r.Content
        foreach ($k in $r.Headers.Keys) { $res.Headers[[string]$k] = [string]$r.Headers[$k] }
    } catch {
        $m = Hide-Key $_.Exception.Message $Keys
        $res.Body = $m
        try {
            $resp = $_.Exception.Response
            if ($resp) {
                $res.Status = [int]$resp.StatusCode
                foreach ($k in $resp.Headers.AllKeys) { $res.Headers[[string]$k] = [string]$resp.Headers[$k] }
                $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $res.Body = Hide-Key $sr.ReadToEnd() $Keys; $sr.Close()
            }
        } catch { }
    }
    $res.Ms = [int]((Get-Date) - $t0).TotalMilliseconds
    $res.Bytes = [Text.Encoding]::UTF8.GetByteCount([string]$res.Body)
    return $res
}
function Show-Probe {
    param([string]$Label, [string]$Url, $R, [string[]]$HeaderNames = @(), [int]$Lines = 6, [string[]]$Keys = @())
    Out-Both ''
    Out-Both ('--- {0}' -f $Label)
    Out-Both ('GET {0}' -f (Hide-Key $Url $Keys))
    Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $R.Status, $R.Ok, $R.Ms, $R.Bytes)
    foreach ($h in $HeaderNames) { if ($R.Headers.ContainsKey($h)) { Out-Both ('header {0}: {1}' -f $h, $R.Headers[$h]) } }
    $head = @(([string]$R.Body) -split "`n" | Select-Object -First $Lines)
    foreach ($l in $head) { $l = $l.TrimEnd("`r") -replace '"client":"[^"]*"', '"client":"<hidden>"'; Out-Both ('  | ' + $l.Substring(0, [Math]::Min(180, $l.Length))) }
}

function Read-Key {
    <# Asks for a key without showing it. Enter (or no keyboard) skips the source. #>
    param([string]$Prompt)
    try {
        $sec = Read-Host $Prompt -AsSecureString
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    } catch { return '' }
}

Out-Both ('FADash feed probe, {0}' -f (Get-Date).ToString('o'))
Out-Both 'No odds endpoints are called. Keys are never printed. About 25 requests, one per second.'

if (-not $Deep) {
# ---- 1. openfootball/england (public domain) -----------------------------------------------------------------------
Out-Both ''; Out-Both '==== 1. openfootball/england (GitHub, public domain text files) ===='
$u = "https://api.github.com/repos/openfootball/england/contents/$Season"
$r = Get-Probe $u
Show-Probe 'season folder listing' $u $r @('X-RateLimit-Remaining') 3
$files = @()
if ($r.Ok) { try { $files = @(($r.Body | ConvertFrom-Json) | ForEach-Object { $_.name }) } catch { } }
Out-Both ('files in {0}: {1}' -f $Season, ($files -join ', '))
$first = $files | Where-Object { $_ -match '^1' } | Select-Object -First 1
if ($first) {
    $u = "https://raw.githubusercontent.com/openfootball/england/master/$Season/$first"
    $r = Get-Probe $u
    Show-Probe "first league file ($first): head" $u $r @('Content-Type', 'Last-Modified', 'ETag') 14
    $played = ([regex]::Matches($r.Body, '\d+-\d+')).Count
    Out-Both ('score-like patterns in the file: {0} (rough count of results in it)' -f $played)
}

# ---- 2. football-data.org (API, free key) -------------------------------------------------------------------------------
Out-Both ''; Out-Both '==== 2. football-data.org (API v4, key) ===='
$fdKey = $env:FADASH_FOOTBALLDATA_KEY
if (-not $fdKey) {
    $fdKey = Read-Key 'football-data.org API key (press Enter to skip)'
}
if ($fdKey) {
    $h = @{ 'X-Auth-Token' = $fdKey }
    $hdrs = @('X-Requests-Available-Minute', 'X-RequestCounter-Reset')
    $u = 'https://api.football-data.org/v4/competitions'
    $r = Get-Probe $u $h @($fdKey); Show-Probe 'competitions your key can see' $u $r $hdrs 3 @($fdKey)
    try { $j = $r.Body | ConvertFrom-Json; Out-Both ('English competitions listed: ' + ((@($j.competitions | Where-Object { $_.area.name -eq 'England' } | ForEach-Object { '{0} ({1}, plan {2})' -f $_.name, $_.code, $_.plan })) -join '; ')) } catch { Out-Both 'could not read the competition list' }
    foreach ($code in 'PL', 'ELC') {
        $u = "https://api.football-data.org/v4/competitions/$code/standings"
        $r = Get-Probe $u $h @($fdKey); Show-Probe "$code standings" $u $r $hdrs 4 @($fdKey)
    }
    $from = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd'); $to = (Get-Date).AddDays(3).ToString('yyyy-MM-dd')
    $u = "https://api.football-data.org/v4/competitions/PL/matches?dateFrom=$from&dateTo=$to"
    $r = Get-Probe $u $h @($fdKey); Show-Probe 'PL matches, 3 days either side (check: which fields, is score live or delayed, are lineups/cards present)' $u $r $hdrs 12 @($fdKey)
} else { Out-Both 'skipped (no key)' }

# ---- 3. API-Football (api-sports.io, free key; 100 requests a day) ----------------------------------------------------------
Out-Both ''; Out-Both '==== 3. API-Football (v3, key; no odds endpoint is called) ===='
$afKey = $env:FADASH_APIFOOTBALL_KEY
if (-not $afKey) {
    $afKey = Read-Key 'API-Football key (press Enter to skip)'
}
if ($afKey) {
    $h = @{ 'x-apisports-key' = $afKey }
    $hdrs = @('x-ratelimit-limit', 'x-ratelimit-remaining', 'X-RateLimit-Limit', 'X-RateLimit-Remaining')
    $u = 'https://v3.football.api-sports.io/status'
    $r = Get-Probe $u $h @($afKey); Show-Probe 'account status (plan, requests used today)' $u $r $hdrs 12 @($afKey)
    $u = 'https://v3.football.api-sports.io/leagues?country=England&season=2026'
    $r = Get-Probe $u $h @($afKey); Show-Probe 'English leagues for season 2026 (check: ids 39/40/41/42 present, coverage flags)' $u $r $hdrs 3 @($afKey)
    try { $j = $r.Body | ConvertFrom-Json; Out-Both ('leagues: ' + ((@($j.response | ForEach-Object { '{0}={1}' -f $_.league.id, $_.league.name })) -join '; ')); if ($j.errors) { Out-Both ('errors: ' + ($j.errors | ConvertTo-Json -Compress)) } } catch { }
    $u = "https://v3.football.api-sports.io/fixtures?league=41&season=2026&date=$((Get-Date).ToString('yyyy-MM-dd'))"
    $r = Get-Probe $u $h @($afKey); Show-Probe 'League One fixtures today (check: does the free plan return the current season?)' $u $r $hdrs 6 @($afKey)
} else { Out-Both 'skipped (no key)' }

}
# ---- 4. ESPN (unofficial public endpoints, no key; owner risk decision) ---------------------------------------------------
Out-Both ''; Out-Both '==== 4. ESPN (unofficial public JSON endpoints, no key; owner risk decision) ===='
Out-Both 'Odds-related keys in ESPN responses (odds, pickcenter, againstTheSpread, predictor and similar) are never printed or saved.'
$espn = 'https://site.api.espn.com/apis/site/v2/sports/soccer'
$oddsLike = '^(odds|pickcenter|againstTheSpread|predictor|winprobability|lines|spread|overUnder)$'
function Cnt { param($x) if ($null -eq $x) { return 0 } else { return @($x).Count } }
function Show-EspnKeys {
    param($Obj)
    $names = @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
    $skip = @($names | Where-Object { $_ -match $oddsLike })
    $keep = @($names | Where-Object { $_ -notmatch $oddsLike })
    Out-Both ('top-level keys: ' + ($keep -join ', '))
    if ($skip.Count -gt 0) { Out-Both ('odds-related keys present and ignored: ' + $skip.Count) }
}
if (-not $Deep) {
$sumEvent = $null; $sumLeague = $null
# Do not assume league identifiers: ask ESPN which English men's competitions it lists, then probe those (at most 8).
$u = 'https://sports.core.api.espn.com/v2/sports/soccer/leagues?limit=1000'
$r = Get-Probe $u
Out-Both ''; Out-Both '--- league list (finding the English competition identifiers)'; Out-Both ('GET {0}' -f $u)
Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
$codes = @()
if ($r.Ok) {
    try {
        $j = $r.Body | ConvertFrom-Json
        $all = @($j.items | ForEach-Object { if ($_.'$ref' -match '/leagues/([^/?]+)') { $Matches[1] } })
        Out-Both ('leagues listed: {0}' -f $all.Count)
        $codes = @($all | Where-Object { $_ -match '^eng\.' -and $_ -notmatch '^eng\.w' } | Select-Object -First 8)
        Out-Both ('English men''s identifiers found: ' + ($codes -join ', '))
    } catch { Out-Both 'could not read the league list' }
}
if ($codes.Count -eq 0) { $codes = @('eng.1', 'eng.2', 'eng.3', 'eng.4'); Out-Both 'league list unavailable: falling back to eng.1 to eng.4 as a guess (UNVERIFIED)' }
foreach ($lg in $codes) {
    $u = "$espn/$lg/scoreboard"
    $r = Get-Probe $u
    Out-Both ''; Out-Both ('--- scoreboard {0}' -f $lg); Out-Both ('GET {0}' -f $u)
    Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
    if (-not $r.Ok) { Out-Both '  (no data: code may be wrong or blocked)'; continue }
    try {
        $j = $r.Body | ConvertFrom-Json
        Show-EspnKeys $j
        $lgs = @($j.leagues | ForEach-Object { '{0} (season {1})' -f $_.name, $_.season.year })
        Out-Both ('league: ' + ($lgs -join '; '))
        $evs = @($j.events | Where-Object { $_ })
        Out-Both ('events returned: {0}' -f (Cnt $j.events))
        foreach ($e in ($evs | Select-Object -First 3)) {
            $c = $e.competitions[0]
            $sides = @($c.competitors | ForEach-Object { '{0} {1} {2}' -f $_.homeAway, $_.team.abbreviation, $_.score })
            Out-Both ('  event {0} | {1} | {2}/{3} | {4} | details (goals/cards) listed: {5}' -f $e.id, $e.date, $e.status.type.state, $e.status.type.name, ($sides -join ' v '), (Cnt $c.details))
        }
        if (-not $sumEvent) {
            $done = $evs | Where-Object { $_.status.type.state -eq 'post' } | Select-Object -First 1
            if ($done) { $sumEvent = $done.id; $sumLeague = $lg }
        }
    } catch { Out-Both 'could not read the JSON' }
}
if ($sumEvent) {
    $u = "$espn/$sumLeague/summary?event=$sumEvent"
    $r = Get-Probe $u
    Out-Both ''; Out-Both ('--- match summary for a finished {0} match' -f $sumLeague); Out-Both ('GET {0}' -f $u)
    Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
    try {
        $j = $r.Body | ConvertFrom-Json
        Show-EspnKeys $j
        Out-Both ('keyEvents: {0}  rosters: {1}  boxscore teams: {2}  commentary: {3}  injuries key: {4}' -f (Cnt $j.keyEvents), (Cnt $j.rosters), (Cnt $j.boxscore.teams), (Cnt $j.commentary), ($null -ne $j.injuries))
        $k = @($j.keyEvents | Select-Object -First 4 | ForEach-Object { '{0} {1}' -f $_.clock.displayValue, $_.type.text })
        Out-Both ('first key events: ' + ($k -join ' | '))
    } catch { Out-Both 'could not read the JSON' }
} else { Out-Both ''; Out-Both 'no finished match found on any scoreboard, so the match summary was not requested' }
foreach ($lg in 'eng.1', 'eng.2') {
    $u = "https://site.api.espn.com/apis/v2/sports/soccer/$lg/standings"
    $r = Get-Probe $u
    Out-Both ''; Out-Both ('--- standings {0}' -f $lg); Out-Both ('GET {0}' -f $u)
    Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
    try { $j = $r.Body | ConvertFrom-Json; Show-EspnKeys $j; $en = @($j.children[0].standings.entries); Out-Both ('entries: {0}; stats on the first: {1}' -f $en.Count, ((@($en[0].stats | ForEach-Object { $_.name }) | Select-Object -First 12) -join ', ')) } catch { Out-Both 'could not read the JSON' }
}
$u = "$espn/eng.2/teams"
$r = Get-Probe $u
Out-Both ''; Out-Both '--- teams eng.2'; Out-Both ('GET {0}' -f $u)
Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
try { $j = $r.Body | ConvertFrom-Json; $tm = @($j.sports[0].leagues[0].teams); Out-Both ('teams: {0}; first: {1}; logo present: {2}' -f $tm.Count, $tm[0].team.displayName, ($tm[0].team.logos.Count -gt 0)) } catch { Out-Both 'could not read the JSON' }

}
if ($Deep) {
    Out-Both ''; Out-Both '==== ESPN deep check 2: League One and League Two matches, upcoming status names, injuries on rosters ===='
    function Get-EspnDay {
        param([string]$Lg, [string]$Ds)
        $u = "$espn/$Lg/scoreboard?dates=$Ds"
        $r = Get-Probe $u
        Out-Both ''; Out-Both ('--- scoreboard {0} on {1}' -f $Lg, $Ds); Out-Both ('GET {0}' -f $u)
        Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
        $res = @{ Count = 0; Pick = $null }
        if (-not $r.Ok) { return $res }
        try {
            $j = $r.Body | ConvertFrom-Json
            $res.Count = Cnt $j.events
            Out-Both ('events returned: {0}' -f $res.Count)
            foreach ($e in @($j.events | Where-Object { $_ })) {
                $c = $e.competitions[0]
                $sides = @($c.competitors | ForEach-Object { '{0} {1} {2}' -f $_.homeAway, $_.team.abbreviation, $_.score })
                Out-Both ('  event {0} | {1}/{2} | {3} | {4} | details listed: {5}' -f $e.id, $e.status.type.state, $e.status.type.name, $e.status.type.detail, ($sides -join ' v '), (Cnt $c.details))
                if (-not $res.Pick -and $e.status.type.name -eq 'STATUS_FULL_TIME') { $res.Pick = $e.id }
            }
        } catch { Out-Both 'could not read the JSON' }
        return $res
    }
    function Show-EspnRoster {
        param([string]$Lg, [string]$TeamId)
        $u = "$espn/$Lg/teams/$TeamId/roster"
        $r = Get-Probe $u
        Out-Both ''; Out-Both ('--- roster of team {0} in {1}' -f $TeamId, $Lg); Out-Both ('GET {0}' -f $u)
        Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
        try {
            $j = $r.Body | ConvertFrom-Json
            $ath = @($j.athletes | Where-Object { $_ })
            $withInj = @($ath | Where-Object { $_.injuries -and (Cnt $_.injuries) -gt 0 })
            Out-Both ('athletes: {0}; with an injury entry: {1}; with age: {2}' -f $ath.Count, $withInj.Count, @($ath | Where-Object { $_.age }).Count)
            if ($withInj.Count -gt 0) {
                $s = ($withInj[0].injuries | ConvertTo-Json -Compress -Depth 3)
                Out-Both ('sample: {0}: {1}' -f $withInj[0].displayName, $s.Substring(0, [Math]::Min(300, $s.Length)))
            }
        } catch { Out-Both 'could not read the JSON' }
    }
    $last = Get-Date
    do { $last = $last.AddDays(-1) } while ($last.DayOfWeek -ne 'Saturday')
    foreach ($lg in 'eng.3', 'eng.4') {
        $pick = $null
        for ($k = 0; $k -lt 5; $k++) {
            $d = Get-EspnDay $lg ($last.AddDays(-7 * $k).ToString('yyyyMMdd'))
            if ($d.Count -gt 0) { $pick = $d.Pick; break }
        }
        if ($pick) {
            $u = "$espn/$lg/summary?event=$pick"
            $r = Get-Probe $u
            Out-Both ''; Out-Both ('--- match summary {0} event {1} (full time)' -f $lg, $pick); Out-Both ('GET {0}' -f $u)
            Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
            try {
                $j = $r.Body | ConvertFrom-Json
                Show-EspnKeys $j
                Out-Both ('keyEvents: {0}  rosters: {1}  commentary: {2}  injuries key: {3}' -f (Cnt $j.keyEvents), (Cnt $j.rosters), (Cnt $j.commentary), ($null -ne $j.injuries))
                if ($j.rosters) { $ro = @($j.rosters[0].roster); Out-Both ('first roster: formation {0}, players {1}, starters {2}' -f $j.rosters[0].formation, $ro.Count, @($ro | Where-Object { $_.starter }).Count) }
            } catch { Out-Both 'could not read the JSON' }
        } else { Out-Both ''; Out-Both ('no completed {0} match found on the last 5 Saturdays' -f $lg) }
    }
    $next = Get-Date
    do { $next = $next.AddDays(1) } while ($next.DayOfWeek -ne 'Saturday')
    [void](Get-EspnDay 'eng.3' ($next.ToString('yyyyMMdd')))
    Show-EspnRoster 'eng.3' '3802'
    $u = "$espn/eng.4/teams"
    $r = Get-Probe $u
    Out-Both ''; Out-Both '--- teams eng.4'; Out-Both ('GET {0}' -f $u)
    Out-Both ('status {0}  ok={1}  {2} ms  {3} bytes' -f $r.Status, $r.Ok, $r.Ms, $r.Bytes)
    try { $j = $r.Body | ConvertFrom-Json; $tm = @($j.sports[0].leagues[0].teams); Out-Both ('teams: {0}; first: {1}' -f $tm.Count, $tm[0].team.displayName); Show-EspnRoster 'eng.4' $tm[0].team.id } catch { Out-Both 'could not read the JSON' }
}

Out-Both ''
Out-Both ('Done: {0} request(s). Output saved to {1}' -f $script:Count, $outFile)
Out-Both 'Check the file for anything personal before sharing it (it should contain no keys).'
