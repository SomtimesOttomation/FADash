<#
.SYNOPSIS
    Calls each candidate football data source once and records what comes back. Run it yourself, on your own computer.
.DESCRIPTION
    Windows PowerShell 5.1. This is the probe step of the Data Sources report (docs/DATA-SOURCES-REPORT.md). It makes a
    handful of requests (about 12 in total), one per second, and writes everything it sees to
    tools\probe-output\fa-probe-<time>.txt (not committed: see .gitignore).

    What it does NOT do:
      - It never calls an odds, lines or spreads endpoint, and it never prints or saves the odds columns of any file.
      - It never prints your API keys. Keys are read from the environment variables below, or typed in when asked
        (nothing is typed in when you press Enter: that source is skipped). Keys are never written to a file.
      - It does not scrape any website. Every URL is a published file or a documented API endpoint.

    Keys (both optional; sources without a key are skipped):
      FADASH_FOOTBALLDATA_KEY   football-data.org  (free key, register on their site)
      FADASH_APIFOOTBALL_KEY    API-Football       (free key, register on their site; the free plan has 100 requests per day)

    Sources probed:
      1. openfootball/england (public domain text files on GitHub): lists the season folder, reads one league file.
      2. football-data.org (API, key): competition list, then Premier League and Championship matches and table.
      3. API-Football (API, key): status, English leagues, and one fixtures call. Four requests at most.
    Only sources whose terms allow this are probed. football-data.co.uk is excluded by the owner (odds in every file).
    Sites with no official API (FBref, Sofascore, FotMob, Understat, Transfermarkt, BBC and similar) are never contacted.

    Send the output file back so the report can be finished with real numbers (fields, headers, rate limits, empty responses).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Probe-FAFeeds.ps1
#>
param(
    [string]$Season = '2026-27'       # folder name used by openfootball
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
    foreach ($l in $head) { Out-Both ('  | ' + $l.TrimEnd("`r").Substring(0, [Math]::Min(180, $l.TrimEnd("`r").Length))) }
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
Out-Both 'No odds endpoints are called. Keys are never printed. About 12 requests, one per second.'

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
    $hdrs = @('X-Requests-Available-Minute', 'X-RequestCounter-Reset', 'X-Authenticated-Client')
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

Out-Both ''
Out-Both ('Done: {0} request(s). Output saved to {1}' -f $script:Count, $outFile)
Out-Both 'Check the file for anything personal before sharing it (it should contain no keys).'
