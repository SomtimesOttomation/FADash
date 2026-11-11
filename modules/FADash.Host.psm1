<#
.SYNOPSIS
    FADash backend for DashLauncher contract version 1. For now it contacts nothing: its "servers" are made up (PRETEND data).
.DESCRIPTION
    Windows PowerShell 5.1. Built the way NBADash and NHLDash are, with the data source swapped for a pretend one until
    a real football source has been chosen and its terms checked (Data Sources report, see CHANGELOG):

      - The page asks for data by key. English football is one dash with several competitions, so keys carry the league:
        "score:pl:2026-11-09", "week:ch:2026-11-02", "standings:l1", "team:ALD". Leagues: pl, ch, l1, l2, cup.
        Keys are checked against a fixed list here, never turned into URLs by the page.
      - The cache has one folder per league (cache\pl, cache\ch, ...) so a league can be refreshed or deleted alone.
      - A worker runspace "downloads" each key one at a time from pretend servers (*.pretend.invalid; the .invalid name
        can never reach the internet), waits a little like a real request, saves a copy in the cache folder and queues
        the JSON for the page. Receive-DashEvents hands it over. Traffic is counted per server, with the last 40 requests.
      - A season sync queues one request per week and reports real progress to the page and to the launcher's rail.
      - Settings live in %APPDATA%\FADash, cache and WebView2 profile in %LOCALAPPDATA%\FADash: never inside
        the dash's own folder, so an update (from the dash or from DashLauncher) never wipes them.
      - The updater (Update-FADash.ps1 + Apply-Update.ps1) is the same as NHLDash's. It only talks to GitHub, and only
        when the person clicks the version or turns "check on start" on (off by default for now).

    Pretend data tools (Settings page): pretend live matches, an update or a problem for the launcher's tab badges, and
    pretend that downloads fail, to see the failed-request rule (a failed item waits for Refresh).

    The pretend clubs live in ui/data/pretend-clubs.json (shared with the browser preview, ui/dev/mock.js). Nothing here
    is a real club or fixture. To go real: replace Invoke-FakeServer in the worker with real downloads and list the
    source in dash.json with its terms.
#>

$script:Ctx = $null
$script:Root = Split-Path $PSScriptRoot
$script:Mutex = $null
$script:Version = '0.0.0'
$script:CacheDir = ''
$script:WebViewDataDir = ''
$script:SettingsFile = ''
$script:Settings = $null
$script:Visible = $false
$script:Watch = @()
$script:NextAuto = [datetime]::MaxValue
$script:SyncKeys = $null
$script:SyncTotal = 1
$script:LastSyncPct = -1
$script:Shared = $null
$script:Queue = $null
$script:Out = $null
$script:Worker = $null
$script:WorkerHandle = $null
# Pretend data tools: in-memory only
$script:Pretend = @{ Live = 0; Update = $false; Problem = $false }

# Competitions (cup = FA Cup and EFL Cup fixtures, no table) and the made-up clubs (loaded from ui/data/pretend-clubs.json).
# A real dash gets its clubs from its data source, keyed by the source's team id.
$script:Leagues = @('pl', 'ch', 'l1', 'l2', 'cup')
$script:Clubs = @()
$script:ClubIds = @()

function Read-Clubs {
    $p = Join-Path (Join-Path (Join-Path $script:Root 'ui') 'data') 'pretend-clubs.json'
    try {
        $j = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $script:Clubs = @($j.clubs | ForEach-Object { [ordered]@{ id = [string]$_.id; abbr = [string]$_.abbr; name = [string]$_.name; color = [string]$_.color; league = [string]$_.league } })
    } catch { $script:Clubs = @() }
    $script:ClubIds = @($script:Clubs | ForEach-Object { $_.id })
}

function New-DefaultSettings {
    return [ordered]@{ theme = 'system'; autoRefresh = $false; autoAck = $false; refreshSeconds = 60; favorites = @(); updateCheck = $false }
}

# ---------------------------------------------------------------- page messages
function Send-Page {
    param([string]$Json)
    try { if ($script:Ctx -and $script:Ctx.Post) { & $script:Ctx.Post $Json } } catch { }
}
function Reply { param($Id, [string]$DataJson = 'null') Send-Page ('{{"id":{0},"ok":true,"data":{1}}}' -f [int]$Id, $DataJson) }
function ReplyError { param($Id, [string]$Message) Send-Page ('{{"id":{0},"ok":false,"error":{1}}}' -f [int]$Id, (ConvertTo-Json -InputObject $Message -Compress)) }
function ConvertTo-PageJson { param($Object) return (ConvertTo-Json -InputObject $Object -Depth 6 -Compress) }

# ---------------------------------------------------------------- settings
function Read-Settings {
    $s = New-DefaultSettings
    try {
        if (Test-Path $script:SettingsFile) {
            $j = [IO.File]::ReadAllText($script:SettingsFile) | ConvertFrom-Json
            foreach ($k in @($s.Keys)) { if ($null -ne $j.$k) { $s[$k] = $j.$k } }
        }
    } catch { }
    $s.autoRefresh = [bool]$s.autoRefresh; $s.autoAck = [bool]$s.autoAck; $s.updateCheck = [bool]$s.updateCheck
    $s.refreshSeconds = Limit-Seconds $s.refreshSeconds
    if (@('system', 'light', 'dark') -notcontains [string]$s.theme) { $s.theme = 'system' }
    $s.favorites = Limit-Teams $s.favorites
    return $s
}
function Save-Settings {
    try { [IO.File]::WriteAllText($script:SettingsFile, (ConvertTo-Json -InputObject $script:Settings -Compress)) } catch { }
}
function Limit-Teams {
    # Several favourites, in the order they were starred; only known club ids.
    param($Value)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($Value)) { $v = [string]$t; if ($script:ClubIds -ccontains $v -and -not $out.Contains($v)) { $out.Add($v) } }
    return , $out.ToArray()
}
function Limit-Seconds { param($Value) $n = 60; try { $n = [int]$Value } catch { }; return [Math]::Max(20, [Math]::Min(600, $n)) }

# ---------------------------------------------------------------- data keys
function Get-SeasonStart {
    # The pretend season always started on the Monday six weeks ago, so there are a few weeks to show.
    $d = (Get-Date).Date.AddDays(-42)
    while ($d.DayOfWeek -ne 'Monday') { $d = $d.AddDays(-1) }
    return $d
}
function Get-SeasonWeeks {
    $d = Get-SeasonStart
    $list = @()
    while ($d -le (Get-Date).Date) { $list += $d.ToString('yyyy-MM-dd'); $d = $d.AddDays(7) }
    return , $list
}

function Resolve-DataKey {
    <# Turns a page key into a request spec, or $null if the key is not allowed. The page never supplies a URL.
       Every file lives in its league's cache folder (cache\pl, cache\ch, ...). #>
    param([string]$Key)
    $k = [string]$Key
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($k -cmatch '^score:(pl|ch|l1|l2|cup):(\d{4}-\d{2}-\d{2})$') {
        $lg = $Matches[1]; $day = $Matches[2]
        $ttl = if ($day -lt $today) { 3600 } else { 15 }
        return @{ Key = $k; Url = 'https://scores.pretend.invalid/' + $lg + '/day/' + $day; File = "$lg\score-$day.json"; Ttl = $ttl }
    }
    if ($k -cmatch '^week:(pl|ch|l1|l2|cup):(\d{4}-\d{2}-\d{2})$') {
        $lg = $Matches[1]; $day = $Matches[2]
        $d = [datetime]::ParseExact($day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($d.DayOfWeek -ne 'Monday') { return $null }
        $ttl = if ($d.AddDays(8) -lt (Get-Date).Date) { 2592000 } else { 600 }     # finished weeks never change
        return @{ Key = $k; Url = 'https://scores.pretend.invalid/' + $lg + '/week/' + $day; File = "$lg\week-$day.json"; Ttl = $ttl }
    }
    if ($k -cmatch '^standings:(pl|ch|l1|l2)$') {
        $lg = $Matches[1]
        return @{ Key = $k; Url = 'https://scores.pretend.invalid/' + $lg + '/standings'; File = "$lg\standings.json"; Ttl = 600 }
    }
    if ($k -cmatch '^team:([A-Z0-9]{2,12})$' -and $script:ClubIds -ccontains $Matches[1]) {
        $id = $Matches[1]
        $club = $script:Clubs | Where-Object { $_.id -ceq $id } | Select-Object -First 1
        return @{ Key = $k; Url = 'https://teams.pretend.invalid/team/' + $id; File = "$($club.league)\team-$id.json"; Ttl = 1800 }
    }
    return $null
}

function Get-CacheAge {
    param([string]$File)
    $p = Join-Path $script:CacheDir $File
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return ((Get-Date) - (Get-Item -LiteralPath $p).LastWriteTime).TotalSeconds
}

function New-DataEvent {
    <# The page event from a cached file. #>
    param($Spec, [bool]$FromCache)
    $p = Join-Path $script:CacheDir $Spec.File
    $at = (Get-Item -LiteralPath $p).LastWriteTimeUtc.ToString('o')
    return ('{{"event":"data","data":{{"key":{0},"ok":true,"cached":{1},"at":"{2}","body":' -f (ConvertTo-Json $Spec.Key), $FromCache.ToString().ToLower(), $at) + [IO.File]::ReadAllText($p) + '}}'
}

function Request-Data {
    <# Answers from the cache when it is fresh enough, otherwise queues a download. Returns 'cached', 'queued' or 'busy'. #>
    param($Spec, [bool]$Force)
    $age = Get-CacheAge $Spec.File
    if (-not $Force -and $null -ne $age -and $age -lt $Spec.Ttl) {
        try { $script:Out.Enqueue((New-DataEvent $Spec $true)); return 'cached' } catch { }
    }
    if ($script:Shared.Pending.ContainsKey($Spec.Key)) { return 'busy' }
    $script:Shared.Pending[$Spec.Key] = $true
    $item = @{} + $Spec
    $item.Gen = $script:Shared.Gen
    $script:Queue.Add($item)
    return 'queued'
}

# ---------------------------------------------------------------- worker runspace
$script:WorkerScript = {
    param($Shared, $Queue, $Out, $CacheDir, $Clubs)
    $utf8 = New-Object Text.UTF8Encoding($false)
    $leagueNames = @{ pl = 'Premier League'; ch = 'Championship'; l1 = 'League One'; l2 = 'League Two'; cup = 'Cups' }

    # ---- the PRETEND servers. A real dash downloads here instead (NHLDash: Get-Bytes with HttpWebRequest). ----
    # Same keys and shapes as ui/dev/mock.js (the browser preview). Nothing below is a real club, player or fixture.
    function Get-Seed([string]$Text) { $h = 17; foreach ($c in $Text.ToCharArray()) { $h = ($h * 31 + [int]$c) % 2147483647 }; return [int]$h }
    function Get-ClubsOf([string]$Lg) { if ($Lg -eq 'cup') { return @($Clubs) } else { return @($Clubs | Where-Object { $_.league -eq $Lg }) } }
    $first = 'Alex', 'Sam', 'Jordan', 'Riley', 'Casey', 'Morgan', 'Jamie', 'Taylor', 'Drew', 'Quinn', 'Avery', 'Rowan', 'Emery', 'Parker'
    $last = 'Hale', 'Moreau', 'Lindqvist', 'Okafor', 'Brandt', 'Castell', 'Rook', 'Vance', 'Pike', 'Ferro', 'Holm', 'Sato', 'Weller', 'Dunmore'
    $posList = 'GK', 'GK', 'DF', 'DF', 'DF', 'DF', 'DF', 'MF', 'MF', 'MF', 'MF', 'MF', 'FW', 'FW', 'FW', 'FW'
    $squadCache = @{}
    function Get-Squad([string]$Id) {
        if ($squadCache.ContainsKey($Id)) { return $squadCache[$Id] }
        $rng = New-Object Random (Get-Seed $Id)
        $out = @()
        for ($i = 0; $i -lt $posList.Count; $i++) {
            $pos = $posList[$i]
            $apps = 6 + $rng.Next(5)
            $g = switch ($pos) { 'FW' { $rng.Next(8) } 'MF' { $rng.Next(4) } 'DF' { $rng.Next(2) } default { 0 } }
            $a = if ($pos -eq 'GK') { 0 } else { $rng.Next(5) }
            $out += [ordered]@{ id = '{0}{1:00}' -f $Id, $i; name = '{0} {1}' -f $first[$rng.Next($first.Count)], $last[$rng.Next($last.Count)]; pos = $pos
                                apps = $apps; g = $g; a = $a; yc = $rng.Next(4); rc = $(if ($rng.NextDouble() -lt 0.08) { 1 } else { 0 }) }
        }
        $squadCache[$Id] = $out
        return $out
    }
    function Get-Surname([string]$Name) { return (($Name -split ' ', 2)[1]) }
    $kickoffs = @(@(12, 30), @(15, 0), @(15, 0), @(17, 30), @(20, 0))

    function Get-DayMatches([string]$Lg, [datetime]$Day, [bool]$Scorers = $true) {
        $rng = New-Object Random (Get-Seed ($Lg + $Day.ToString('yyyy-MM-dd')))
        $clubs = @(Get-ClubsOf $Lg | Sort-Object { $rng.Next() })
        $now = Get-Date
        $isToday = $Day.Date -eq $now.Date
        # Match days: Saturday, Sunday and Tuesday, plus today whatever day it is (so there is always something live).
        if (-not $isToday -and @('Saturday', 'Sunday', 'Tuesday') -notcontains [string]$Day.DayOfWeek) { return , @() }
        $n = $(if ($Lg -eq 'cup') { 2 } else { 3 + $rng.Next(3) })
        $events = @()
        for ($i = 0; $i -lt $n; $i++) {
            $hClub = $clubs[2 * $i + 1]; $aClub = $clubs[2 * $i]
            $start = if ($isToday) { $now.AddMinutes(@(-130, -25, -70, 40, 150)[$i % 5]) } else { $Day.Date.AddHours($kickoffs[$i % 5][0]).AddMinutes($kickoffs[$i % 5][1]) }
            $e = ($now - $start).TotalMinutes                       # minutes since kick-off
            $fin = @{ home = [int][Math]::Floor($rng.NextDouble() * $rng.NextDouble() * 5.2); away = [int][Math]::Floor($rng.NextDouble() * $rng.NextDouble() * 4.6) }
            $goals = @()
            foreach ($s in 'home', 'away') {
                $club = $(if ($s -eq 'home') { $hClub } else { $aClub })
                for ($k = 0; $k -lt $fin[$s]; $k++) {
                    $min = 1 + $rng.Next(90); $pick = $rng.Next(8)
                    $who = $(if ($Scorers) { Get-Surname (Get-Squad $club.id)[8 + $pick].name } else { '' })
                    $goals += [pscustomobject]@{ side = $s; min = $min; who = $who }
                }
            }
            $goals = @($goals | Sort-Object min)
            $state = 'pre'; $phase = 'pre'; $clock = ''; $p = 0
            if ($Day.Date -lt $now.Date -or $e -ge 111) { $state = 'post'; $phase = 'FT'; $p = 120 }
            elseif ($e -ge 0) {
                $state = 'in'
                if ($e -lt 45) { $phase = '1H'; $p = [Math]::Max(1, [int][Math]::Floor($e) + 1); $clock = "$p'" }
                elseif ($e -lt 47) { $phase = '1H'; $p = 45; $clock = "45+$([int][Math]::Floor($e - 44))'" }
                elseif ($e -lt 62) { $phase = 'HT'; $p = 45; $clock = 'HT' }
                else { $phase = '2H'; $p = 46 + [int][Math]::Floor($e - 62); $clock = $(if ($p -gt 90) { "90+$($p - 90)'" } else { "$p'" }) }
            }
            $shown = @(); if ($state -ne 'pre') { $shown = @($goals | Where-Object { $_.min -le $p }) }
            $sides = @()
            foreach ($pair in @(@('away', $aClub), @('home', $hClub))) {
                $mine = @($shown | Where-Object { $_.side -eq $pair[0] })
                $sides += [ordered]@{ side = $pair[0]; id = $pair[1].id; abbr = $pair[1].abbr; score = $(if ($state -eq 'pre') { $null } else { [string]$mine.Count }); pens = $null
                                      scorers = @($mine | ForEach-Object { [ordered]@{ min = $_.min; name = $_.who } }) }
            }
            $comp = $(if ($Lg -eq 'cup') { $(if ($rng.NextDouble() -lt 0.5) { 'FA Cup' } else { 'EFL Cup' }) } else { $leagueNames[$Lg] })
            if ($Lg -eq 'cup' -and $state -eq 'post' -and $fin.home -eq $fin.away) {       # cup ties cannot end level: penalties
                $phase = 'PENS'; $w = $(if ($rng.NextDouble() -lt 0.5) { 'home' } else { 'away' }); $hi = 3 + $rng.Next(3)
                foreach ($sd in $sides) { $sd.pens = [string]$(if ($sd.side -eq $w) { $hi } else { $hi - 1 - $rng.Next(2) }) }
            }
            $events += [ordered]@{ id = '{0}{1}{2}' -f $Lg, $Day.ToString('yyyyMMdd'), $i; league = $Lg; comp = $comp; state = $state; phase = $phase
                                   date = $start.ToUniversalTime().ToString('o'); clock = $clock; detail = ''; venue = "$($hClub.name) ground (pretend)"; sides = $sides }
        }
        return , $events
    }
    function Get-Standings([string]$Lg) {
        $rec = @{}
        foreach ($c in (Get-ClubsOf $Lg)) { $rec[$c.id] = [ordered]@{ id = $c.id; abbr = $c.abbr; gp = 0; w = 0; d = 0; l = 0; gf = 0; ga = 0; pts = 0; form = @() } }
        $d = (Get-Date).Date.AddDays(-42); while ($d.DayOfWeek -ne 'Monday') { $d = $d.AddDays(-1) }
        while ($d -lt (Get-Date).Date) {
            foreach ($ev in (Get-DayMatches $Lg $d $false)) {
                $aw = $ev.sides[0]; $hm = $ev.sides[1]
                foreach ($pair in @(@($aw, $hm), @($hm, $aw))) {
                    $me = $pair[0]; $op = $pair[1]; $r = $rec[$me.id]
                    if (-not $r) { continue }
                    $r.gp++; $r.gf += [int]$me.score; $r.ga += [int]$op.score
                    if ([int]$me.score -gt [int]$op.score) { $r.w++; $r.pts += 3; $r.form += 'W' } elseif ([int]$me.score -eq [int]$op.score) { $r.d++; $r.pts++; $r.form += 'D' } else { $r.l++; $r.form += 'L' }
                }
            }
            $d = $d.AddDays(1)
        }
        $rows = foreach ($r in $rec.Values) { $r.form = @($r.form | Select-Object -Last 5); [pscustomobject]$r }
        return @{ league = $Lg; teams = @($rows | Sort-Object @{ Expression = 'pts'; Descending = $true }, @{ Expression = { $_.gf - $_.ga }; Descending = $true }, @{ Expression = 'gf'; Descending = $true }, @{ Expression = 'abbr' }) }
    }
    function Invoke-FakeServer($Item) {
        Start-Sleep -Milliseconds (120 + (Get-Random -Maximum 260))        # like a real request
        if ($Shared.FailDownloads) { throw 'Pretend download failure (Pretend data tools on the Settings page).' }
        $k = $Item.Key
        $body = if ($k -match '^score:([a-z0-9]+):(.+)$') { $d = [datetime]$Matches[2]; @{ league = $Matches[1]; date = $d.ToString('yyyyMMdd'); events = (Get-DayMatches $Matches[1] $d) } }
                elseif ($k -match '^week:([a-z0-9]+):(.+)$') { $lg = $Matches[1]; $m = [datetime]$Matches[2]; @{ league = $lg; monday = $Matches[2]; days = @(0..6 | ForEach-Object { $d = $m.AddDays($_); @{ league = $lg; date = $d.ToString('yyyyMMdd'); events = (Get-DayMatches $lg $d) } }) } }
                elseif ($k -match '^team:(.+)$') { @{ id = $Matches[1]; players = @(Get-Squad $Matches[1]) } }
                else { Get-Standings (($k -split ':')[1]) }
        return (ConvertTo-Json -InputObject $body -Depth 8 -Compress)
    }

    while (-not $Shared.Quit) {
        $item = $null
        if (-not $Queue.TryTake([ref]$item, 500)) { continue }
        try {
            if ($Shared.Halted -or $item.Gen -ne $Shared.Gen -or $Shared.Skip.ContainsKey($item.Key)) { continue }
            $Shared.Requests++
            $hostName = ([uri]$item.Url).Host
            $kind = ($item.Key -split ':')[0]
            if (-not $Shared.ByHost.ContainsKey($hostName)) { $Shared.ByHost[$hostName] = @{ requests = 0; bytes = [long]0; errors = 0 } }
            if (-not $Shared.ByKind.ContainsKey($kind)) { $Shared.ByKind[$kind] = @{ requests = 0; bytes = [long]0 } }
            $hs = $Shared.ByHost[$hostName]; $hs.requests++; $Shared.ByKind[$kind].requests++
            $t0 = Get-Date
            $text = Invoke-FakeServer $item
            $len = $utf8.GetByteCount($text)
            $Shared.Bytes += $len; $hs.bytes += $len; $Shared.ByKind[$kind].bytes += $len
            [void]$Shared.Last.Insert(0, @{ at = $t0.ToString('o'); key = $item.Key; host = $hostName; bytes = $len; ms = [int]((Get-Date) - $t0).TotalMilliseconds; ok = $true })
            while ($Shared.Last.Count -gt 40) { $Shared.Last.RemoveAt(40) }
            if ($Shared.Halted -or $item.Gen -ne $Shared.Gen) { continue }
            $path = Join-Path $CacheDir $item.File
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            [IO.File]::WriteAllText($path, $text, $utf8)
            if ($item.Key -match '^score:([a-z0-9]+):(.+)$' -and $Matches[2] -eq $Shared.TodayDate) {
                # matches in play, per league; the launcher's tab badge shows the total
                $Shared.LiveBy[$Matches[1]] = ([regex]::Matches($text, '"state":"in"')).Count
                $sum = 0; foreach ($v in @($Shared.LiveBy.Values)) { $sum += [int]$v }
                $Shared.Live = $sum
            }
            $head = '{{"event":"data","data":{{"key":"{0}","ok":true,"cached":false,"at":"{1}","body":' -f $item.Key, [datetime]::UtcNow.ToString('o')
            $Out.Enqueue($head + $text + '}}')
            $Shared.LastError = $null
        } catch {
            if ($item.Gen -eq $Shared.Gen -and -not $Shared.Halted) {
                $Shared.Errors++
                try { $hn = ([uri]$item.Url).Host; if ($Shared.ByHost.ContainsKey($hn)) { $Shared.ByHost[$hn].errors++ }; [void]$Shared.Last.Insert(0, @{ at = (Get-Date).ToString('o'); key = $item.Key; host = $hn; bytes = 0; ms = 0; ok = $false }) } catch { }
                $msg = $_.Exception.Message
                $Shared.LastError = $msg
                $Out.Enqueue('{"event":"data","data":{"key":' + (ConvertTo-Json $item.Key) + ',"ok":false,"error":' + (ConvertTo-Json -InputObject ([string]$msg) -Compress) + '}}')
            }
        } finally {
            if ($item) { $Shared.Pending.Remove($item.Key) }
        }
    }
}

function Start-WorkerRunspace {
    if ($script:Worker) { return }
    $ps = [PowerShell]::Create()
    $ps.Runspace = [RunspaceFactory]::CreateRunspace()
    $ps.Runspace.Open()
    [void]$ps.AddScript($script:WorkerScript).AddArgument($script:Shared).AddArgument($script:Queue).AddArgument($script:Out).AddArgument($script:CacheDir).AddArgument($script:Clubs)
    $script:WorkerHandle = $ps.BeginInvoke()
    $script:Worker = $ps
}

function Clear-Queue {
    $x = $null
    while ($script:Queue.TryTake([ref]$x)) { }
    $script:Shared.Pending.Clear()
}

function Get-Snapshot {
    return @{
        mode = [string]$script:Ctx.Mode; version = $script:Version; theme = [string]$script:Ctx.Theme
        launcherVersion = [string]$script:Ctx.LauncherVersion
        halted = [bool]$script:Shared.Halted; live = [int]$script:Shared.Live + $script:Pretend.Live
        error = $(if ($script:Pretend.Problem) { 'Pretend problem (Pretend data tools).' } else { $script:Shared.LastError })
        settings = $script:Settings
        pretend = @{ live = $script:Pretend.Live; update = $script:Pretend.Update; problem = $script:Pretend.Problem; fail = [bool]$script:Shared.FailDownloads }
        today = (Get-Date).ToString('yyyy-MM-dd'); seasonStart = (Get-SeasonStart).ToString('yyyy-MM-dd')
        traffic = @{ requests = [int]$script:Shared.Requests; bytes = [long]$script:Shared.Bytes; errors = [int]$script:Shared.Errors }
    }
}

function Reset-AutoTimer {
    if ($script:Settings.autoRefresh -and $script:Visible -and -not $script:Shared.Halted) {
        $script:NextAuto = (Get-Date).AddSeconds($script:Settings.refreshSeconds)
    } else { $script:NextAuto = [datetime]::MaxValue }
}

# ---------------------------------------------------------------- updater (child process, same as NBADash and NHLDash)
$script:UpdDir = ''
$script:UpdProc = $null
$script:UpdAction = ''
$script:LastUpdJson = ''
$script:UpdateAvailable = $null
$script:UpdateNote = $null
$script:UpdOut = ''

function Get-ChildProgress {
    # Reads a child's console output: the last ##PROGRESS marker.
    param([string]$Path)
    $r = @{ pct = 0; text = '' }
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs)
        while (($l = $sr.ReadLine()) -ne $null) {
            if ($l.Trim() -match '^##PROGRESS (\d+)\|(.*)$') { $r.pct = [int]$Matches[1]; $r.text = $Matches[2] }
        }
        $sr.Close(); $fs.Close()
    } catch { }
    return $r
}
function Read-UpdateJson {
    param([string]$Name)
    $p = Join-Path $script:UpdDir $Name
    if (Test-Path $p) { try { return ([IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { } }
    return $null
}
function Start-Updater {
    <# Update checks talk to GitHub only, so the pause switch leaves them alone. #>
    param([string]$Action)
    if ($script:UpdProc -and -not $script:UpdProc.HasExited) { return $false }
    $cur = if ($env:FADASH_FAKE_VERSION) { $env:FADASH_FAKE_VERSION } else { $script:Version }     # test hook: pretend to be older
    Remove-Item (Join-Path $script:UpdDir 'update-result.json') -Force -ErrorAction SilentlyContinue
    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $script:Root 'Update-FADash.ps1')),
                  '-Action', $Action, '-CurrentVersion', $cur, '-WorkDir', ('"{0}"' -f $script:UpdDir))
    if ($env:FADASH_UPDATE_API) { $argsList += '-ApiBase'; $argsList += $env:FADASH_UPDATE_API }   # test hook
    $exe = if ($env:FADASH_PS) { $env:FADASH_PS } else { 'powershell.exe' }                         # test hook
    $script:UpdAction = $Action
    $sp = @{ FilePath = $exe; ArgumentList = $argsList; PassThru = $true; RedirectStandardOutput = $script:UpdOut }
    if ($IsWindows -ne $false) { $sp.WindowStyle = 'Hidden' }       # $IsWindows is $null in Windows PowerShell 5.1
    $script:UpdProc = Start-Process @sp
    $script:LastUpdJson = ''
    $script:Out.Enqueue((ConvertTo-PageJson @{ event = 'update'; data = @{ running = $true; action = $Action; pct = 0; text = 'Starting...' } }))
    return $true
}
function Get-UpdateEvents {
    $list = @()
    if (-not $script:UpdProc) { return $list }
    if ($script:UpdProc.HasExited) {
        $res = Read-UpdateJson 'update-result.json'
        if (-not $res) { $res = [pscustomobject]@{ status = 'error'; error = 'The update check ended without an answer.' } }
        $script:UpdProc = $null
        if ([string]$res.status -eq 'available' -or [string]$res.status -eq 'staged') { $script:UpdateAvailable = [string]$res.latest }
        elseif ([string]$res.status -eq 'current') { $script:UpdateAvailable = $null }
        $list += (ConvertTo-Json -InputObject @{ event = 'update'; data = @{ running = $false; action = $script:UpdAction; result = $res } } -Depth 6 -Compress)
    } else {
        $prog = Get-ChildProgress $script:UpdOut
        $json = ConvertTo-PageJson @{ event = 'update'; data = @{ running = $true; action = $script:UpdAction; pct = $prog.pct; text = $prog.text } }
        if ($json -ne $script:LastUpdJson) { $script:LastUpdJson = $json; $list += $json }
    }
    return $list
}

# ---------------------------------------------------------------- contract functions
function Initialize-Dash {
    <# Takes the host lock, loads settings and makes folders. Fetches nothing. #>
    param([Parameter(Mandatory)]$Context)
    if ($script:Ctx) { return @{ Ok = $true; Reason = ''; CacheDir = $script:CacheDir; WebViewDataDir = $script:WebViewDataDir } }
    $created = $false
    try { $m = New-Object System.Threading.Mutex($true, 'Local\DashHost-fadash', [ref]$created) } catch { $m = $null }
    if (-not $m -or -not $created) {
        if ($m) { $m.Dispose() }
        return @{ Ok = $false; Reason = 'locked'; CacheDir = ''; WebViewDataDir = '' }
    }
    $script:Mutex = $m
    $script:Ctx = $Context
    if ($Context.Root) { $script:Root = [string]$Context.Root }
    try { $script:Version = ([IO.File]::ReadAllText((Join-Path $script:Root 'VERSION'))).Trim() } catch { }
    $local = Join-Path $env:LOCALAPPDATA 'FADash'
    $roam = Join-Path $env:APPDATA 'FADash'
    $script:CacheDir = Join-Path $local 'cache'
    $script:WebViewDataDir = Join-Path $local 'webview2'
    foreach ($d in @($script:CacheDir, $script:WebViewDataDir, $roam)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    $script:SettingsFile = Join-Path $roam 'settings.json'
    $script:UpdDir = Join-Path $local 'update'
    if (-not (Test-Path $script:UpdDir)) { New-Item -ItemType Directory -Path $script:UpdDir -Force | Out-Null }
    $script:UpdOut = Join-Path $script:UpdDir 'update.out'
    # After an update the helper leaves a "pending" note: report the result once; the page load confirms it worked.
    $script:UpdateNote = $null
    $pend = Read-UpdateJson 'update-pending.json'
    if ($pend -and [string]$pend.to -eq $script:Version) { $script:UpdateNote = @{ ok = $true; from = [string]$pend.from; to = [string]$pend.to } }
    $failed = Read-UpdateJson 'update-failed.json'
    if ($failed) {
        $script:UpdateNote = @{ ok = $false; from = [string]$failed.from; to = [string]$failed.to; reason = [string]$failed.reason }
        Remove-Item (Join-Path $script:UpdDir 'update-failed.json') -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $script:UpdDir 'update-pending.json') -Force -ErrorAction SilentlyContinue
    }
    Read-Clubs
    $script:Settings = Read-Settings
    $script:Pretend = @{ Live = 0; Update = $false; Problem = $false }
    $script:Shared = [hashtable]::Synchronized(@{
        Quit = $false; Halted = $false; Gen = 0; Live = 0; Requests = 0; Bytes = [long]0; Errors = 0; LastError = $null; FailDownloads = $false
        Pending = [hashtable]::Synchronized(@{}); Skip = [hashtable]::Synchronized(@{}); ByHost = [hashtable]::Synchronized(@{}); ByKind = [hashtable]::Synchronized(@{})
        Last = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)); Started = Get-Date; TodayDate = (Get-Date).ToString('yyyy-MM-dd'); LiveBy = [hashtable]::Synchronized(@{})
    })
    $script:Queue = New-Object 'System.Collections.Concurrent.BlockingCollection[object]'
    $script:Out = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $script:Visible = $false
    $script:Watch = @()
    $script:SyncKeys = $null
    return @{ Ok = $true; Reason = ''; CacheDir = $script:CacheDir; WebViewDataDir = $script:WebViewDataDir }
}

function Start-DashWorker {
    <# Visible: the worker runs (it only ever fetches what was asked for); automatic refresh resumes if it is on. #>
    if (-not $script:Shared) { return }
    $script:Visible = $true
    if ($script:Shared.Halted) { return }
    Start-WorkerRunspace
    Reset-AutoTimer
}

function Suspend-DashWorker {
    <# Hidden: no timed refresh. Requests already queued (and a running sync) finish. #>
    if (-not $script:Shared) { return }
    $script:Visible = $false
    $script:NextAuto = [datetime]::MaxValue
}

function Invoke-DashCommand {
    param([Parameter(Mandatory)]$Message)
    $id = $Message.id
    $a = $Message.args
    try {
        switch ([string]$Message.cmd) {
            'init' {
                $snap = Get-Snapshot
                $snap.updateNote = $script:UpdateNote
                $snap.teams = $script:Clubs
                Reply $id (ConvertTo-PageJson $snap)
                if ($script:UpdateNote -and $script:UpdateNote.ok) {
                    # the page loaded: tell the update helper the new version works
                    try { [IO.File]::WriteAllText((Join-Path $script:UpdDir 'update-ok.json'), '{"ok":true}') } catch { }
                    Remove-Item (Join-Path $script:UpdDir 'update-pending.json') -Force -ErrorAction SilentlyContinue
                }
                $script:UpdateNote = $null
            }
            'update.check' { Reply $id ((Start-Updater 'Check').ToString().ToLower()) }
            'update.stage' { Reply $id ((Start-Updater 'Stage').ToString().ToLower()) }
            'update.cancel' {
                try { if ($script:UpdProc -and -not $script:UpdProc.HasExited) { $script:UpdProc.Kill() } } catch { }
                Reply $id 'true'
            }
            'update.apply' {
                $st = Read-UpdateJson 'staged.json'
                $stage = Join-Path $script:UpdDir 'stage'
                if (-not $st -or -not (Test-Path (Join-Path $stage 'Start-FADash.ps1'))) { ReplyError $id 'There is no downloaded update to install. Download it again.'; return }
                # run the helper from a copy so replacing the app files cannot touch the running helper
                $runDir = Join-Path $script:UpdDir 'run'
                if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }
                $helper = Join-Path $runDir 'Apply-Update.ps1'
                Copy-Item (Join-Path $script:Root 'Apply-Update.ps1') $helper -Force
                # Context.Relaunch is passed through exactly as given (it may include arguments, e.g. -Open fadash)
                $relaunch = if ($script:Ctx.Relaunch) { [string]$script:Ctx.Relaunch } else { '"' + (Join-Path $script:Root 'Start-FADash.bat') + '"' }
                $relaunchB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($relaunch))
                $hostPid = if ($script:Ctx.HostPid) { [int]$script:Ctx.HostPid } else { $PID }
                $h = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $helper), '-AppDir', ('"{0}"' -f $script:Root), '-StageDir', ('"{0}"' -f $stage),
                       '-WorkDir', ('"{0}"' -f $script:UpdDir), '-ParentPid', [string]$hostPid, '-RelaunchB64', $relaunchB64,
                       '-OldVersion', $script:Version, '-NewVersion', [string]$st.version)
                Start-Process -FilePath 'powershell.exe' -ArgumentList $h -WindowStyle Hidden | Out-Null
                Reply $id 'true'
                if ($script:Ctx.Close) { & $script:Ctx.Close }
            }
            'data.get' {
                $spec = Resolve-DataKey ([string]$a.key)
                if (-not $spec) { ReplyError $id 'unknown data key'; return }
                if ($script:Shared.Halted) {
                    # Paused: saved copies still show, nothing is fetched.
                    if ($null -ne (Get-CacheAge $spec.File)) { $script:Out.Enqueue((New-DataEvent $spec $true)); Reply $id '"cached"' }
                    else { ReplyError $id 'Data traffic is paused.' }
                    return
                }
                if ([bool]$a.cacheOnly) {
                    if ($null -ne (Get-CacheAge $spec.File)) { $script:Out.Enqueue((New-DataEvent $spec $true)); Reply $id '"cached"' } else { Reply $id '"missing"' }
                    return
                }
                Start-WorkerRunspace
                Reply $id (ConvertTo-Json (Request-Data $spec ([bool]$a.force)))
            }
            'watch.set' {
                # what the opt-in refresh timer may refetch: at most 6 keys the open page shows
                $keys = @()
                foreach ($k in @($a.keys)) { if ($k -and (Resolve-DataKey ([string]$k))) { $keys += [string]$k } }
                $script:Watch = @($keys | Select-Object -First 6)
                Reply $id 'true'
            }
            'settings.set' {
                $s = $script:Settings
                switch ([string]$a.key) {
                    'autoRefresh' {
                        $on = [bool]$a.value
                        if ($on -and -not [bool]$a.ack -and -not $s.autoAck) { ReplyError $id 'Automatic refresh needs the warning acknowledged.'; return }
                        $s.autoRefresh = $on; if ($on) { $s.autoAck = $true }
                    }
                    'refreshSeconds' { $s.refreshSeconds = Limit-Seconds $a.value }
                    'favorites' { $s.favorites = Limit-Teams $a.value }
                    'updateCheck' { $s.updateCheck = [bool]$a.value }
                    'theme' { if (@('system', 'light', 'dark') -contains [string]$a.value) { $s.theme = [string]$a.value } }
                    default { ReplyError $id 'unknown setting'; return }
                }
                Save-Settings
                Reset-AutoTimer
                Reply $id (ConvertTo-PageJson (Get-Snapshot))
            }
            'pretend.set' {
                # Pretend data tools: pretend states for the launcher's tab badges, and pretend download failures
                switch ([string]$a.key) {
                    'live' { $n = 0; try { $n = [int]$a.value } catch { }; $script:Pretend.Live = [Math]::Max(0, [Math]::Min(15, $n)) }
                    'update' { $script:Pretend.Update = [bool]$a.value }
                    'problem' { $script:Pretend.Problem = [bool]$a.value }
                    'fail' { $script:Shared.FailDownloads = [bool]$a.value }
                    default { ReplyError $id 'unknown setting'; return }
                }
                Reply $id (ConvertTo-PageJson (Get-Snapshot))
            }
            'season.weeks' {
                # per week: the leagues that have a saved copy of it
                $weeks = foreach ($w in (Get-SeasonWeeks)) { @{ monday = $w; leagues = @($script:Leagues | Where-Object { $null -ne (Get-CacheAge "$_\week-$w.json") }) } }
                Reply $id (ConvertTo-Json -InputObject @($weeks) -Depth 4 -Compress)
            }
            'sync.run' {
                if ($script:Shared.Halted) { ReplyError $id 'Data traffic is paused. Resume first.'; return }
                if ($script:SyncKeys) { Reply $id 'false'; return }
                Start-WorkerRunspace
                $script:Shared.Skip.Clear()
                $weeks = Get-SeasonWeeks
                $keys = @()
                foreach ($lg in $script:Leagues) {
                    for ($i = 0; $i -lt $weeks.Count; $i++) {
                        $spec = Resolve-DataKey ("week:$lg`:" + $weeks[$i])
                        $r = Request-Data $spec ($i -eq $weeks.Count - 1)     # finished weeks come from the cache when saved
                        if ($r -ne 'cached') { $keys += $spec.Key }
                    }
                    if ($lg -ne 'cup') { if ((Request-Data (Resolve-DataKey "standings:$lg") $true) -ne 'cached') { $keys += "standings:$lg" } }
                }
                $script:SyncKeys = $keys
                $script:SyncTotal = [Math]::Max(1, $keys.Count)
                $script:LastSyncPct = -1
                Reply $id (ConvertTo-Json @{ started = $true; requests = $keys.Count; weeks = $weeks.Count } -Compress)
            }
            'sync.cancel' {
                if ($script:SyncKeys) { foreach ($k in $script:SyncKeys) { $script:Shared.Skip[$k] = $true } }
                Reply $id 'true'
            }
            'traffic.get' {
                $s = $script:Shared
                $hosts = @{}
                foreach ($h in @($s.ByHost.Keys)) { $hosts[$h] = $s.ByHost[$h] }
                $kinds = @{}
                foreach ($k in @($s.ByKind.Keys)) { $kinds[$k] = $s.ByKind[$k] }
                $list = @($s.Last.ToArray())
                $lastText = $(if ($list.Count) { '{0} ({1})' -f $list[0].key, ([datetime]$list[0].at).ToString('T') } else { '' })
                # NBADash's fields (bytes, byKind, last) plus per-server counts and the last 40 requests
                $obj = @{ uptimeSec = [int]((Get-Date) - $s.Started).TotalSeconds; requests = [int]$s.Requests; bytes = [long]$s.Bytes; wireBytes = [long]$s.Bytes; errors = [int]$s.Errors
                          byKind = $kinds; byHost = $hosts; last = $lastText; lastList = $list }
                Reply $id (ConvertTo-Json -InputObject $obj -Depth 5 -Compress)
            }
            'cache.clear' {
                Get-ChildItem -LiteralPath $script:CacheDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.json$' } | Remove-Item -Force -ErrorAction SilentlyContinue
                Reply $id 'true'
            }
            'traffic.stop' {
                Stop-DashTraffic
                Reply $id (ConvertTo-PageJson (Get-Snapshot))
            }
            'traffic.resume' {
                $script:Shared.Halted = $false
                $script:Shared.LastError = $null
                if ($script:Visible) { Start-WorkerRunspace }
                Reset-AutoTimer
                Send-Page '{"event":"traffic","data":{"stopped":false}}'
                Reply $id (ConvertTo-PageJson (Get-Snapshot))
            }
            default { ReplyError $id ('unknown command: ' + [string]$Message.cmd) }
        }
    } catch { ReplyError $id $_.Exception.Message }
}

function Receive-DashEvents {
    <# Every 250 ms: runs the opt-in refresh timer and drains up to 25 worker messages. #>
    if (-not $script:Shared) { return @() }
    $now = Get-Date
    $script:Shared.TodayDate = $now.ToString('yyyy-MM-dd')
    if ($now -ge $script:NextAuto) {
        if ($script:Visible -and $script:Settings.autoRefresh -and -not $script:Shared.Halted) {
            foreach ($k in $script:Watch) { $spec = Resolve-DataKey $k; if ($spec) { [void](Request-Data $spec $true) } }
        }
        Reset-AutoTimer
    }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($u in @(Get-UpdateEvents)) { if ($u) { $out.Add($u) } }
    if ($script:SyncKeys) {
        $left = @($script:SyncKeys | Where-Object { $script:Shared.Pending.ContainsKey($_) }).Count
        $pct = [int](100 * ($script:SyncTotal - $left) / $script:SyncTotal)
        if ($left -eq 0) { $script:SyncKeys = $null; $out.Add(('{{"event":"sync","data":{{"running":false,"pct":100,"exitCode":0,"summary":"{0} requests","lastRun":"{1}"}}}}' -f $script:SyncTotal, (Get-Date).ToString('o'))) }
        elseif ($pct -ne $script:LastSyncPct) { $script:LastSyncPct = $pct; $out.Add(('{{"event":"sync","data":{{"running":true,"pct":{0},"text":"Downloading {1} of {2}"}}}}' -f $pct, ($script:SyncTotal - $left), $script:SyncTotal)) }
    }
    $msg = $null
    while ($out.Count -lt 25 -and $script:Out.TryDequeue([ref]$msg)) { $out.Add($msg) }
    return $out.ToArray()       # unrolled: the caller gets one JSON string per item (wrap in @() for 0 or 1)
}

function Get-DashStatus {
    <# Every 2 seconds: no network, no disk. #>
    $s = $script:Shared
    if (-not $s) { return @{ Live = 0; Syncing = $false; SyncPct = $null; UpdateAvailable = $null; Error = $null; Traffic = @{ Requests = 0; Bytes = 0; Errors = 0 } } }
    $syncing = $false
    $syncPct = $null
    if ($script:SyncKeys) {
        $left = @($script:SyncKeys | Where-Object { $s.Pending.ContainsKey($_) }).Count
        if ($left -gt 0) { $syncing = $true; $syncPct = [int](100 * ($script:SyncTotal - $left) / $script:SyncTotal) }
    }
    return @{
        Live            = $(if ($s.Halted) { 0 } else { [int]$s.Live + $script:Pretend.Live })
        Syncing         = $syncing
        SyncPct         = $syncPct
        UpdateAvailable = $(if ($script:Pretend.Update) { '9.9.9' } else { $script:UpdateAvailable })
        Error           = $(if ($script:Pretend.Problem) { 'Pretend problem (Pretend data tools).' } elseif ($s.Halted) { $null } else { $s.LastError })
        Traffic         = @{ Requests = [int]$s.Requests; Bytes = [long]$s.Bytes; Errors = [int]$s.Errors }
    }
}

function Stop-DashTraffic {
    <# Kill switch: drop queued requests, ignore the one in flight, stop the refresh timer. Settings are not changed. #>
    if (-not $script:Shared) { return }
    $script:Shared.Halted = $true
    $script:Shared.Gen++
    Clear-Queue
    if ($script:SyncKeys) { $script:Out.Enqueue('{"event":"sync","data":{"running":false,"pct":0,"cancelled":true}}') }
    $script:SyncKeys = $null
    $script:NextAuto = [datetime]::MaxValue
    Send-Page '{"event":"traffic","data":{"stopped":true}}'
}

function Stop-Dash {
    <# Closing: stop the worker and release the host lock within 2 seconds. #>
    try {
        if ($script:Shared) { $script:Shared.Quit = $true; $script:Shared.Gen++ }
        if ($script:Worker) {
            if (-not $script:WorkerHandle.AsyncWaitHandle.WaitOne(1200)) { try { $script:Worker.Stop() } catch { } }
            $script:Worker.Runspace.Dispose(); $script:Worker.Dispose()
        }
    } catch { }
    $script:Worker = $null; $script:WorkerHandle = $null
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } } catch { }
    $script:Mutex = $null
    $script:Ctx = $null
    $script:Shared = $null
}

function Invoke-DashSync {
    <# Optional (master sync, switched off in the launcher for now): today's matches and the tables of every league. #>
    param([ValidateSet('quick')][string]$Scope = 'quick')
    if (-not $script:Shared -or $script:Shared.Halted) { return $false }
    if ($script:SyncKeys) { return $false }
    Start-WorkerRunspace
    $day = (Get-Date).ToString('yyyy-MM-dd')
    $keys = @()
    foreach ($lg in $script:Leagues) { $keys += "score:$lg`:$day"; if ($lg -ne 'cup') { $keys += "standings:$lg" } }
    foreach ($k in $keys) { [void](Request-Data (Resolve-DataKey $k) $true) }
    $script:SyncKeys = $keys
    $script:SyncTotal = $keys.Count
    $script:LastSyncPct = -1
    return $true
}

Export-ModuleMember -Function Initialize-Dash, Start-DashWorker, Suspend-DashWorker, Invoke-DashCommand, Receive-DashEvents, Get-DashStatus, Stop-DashTraffic, Stop-Dash, Invoke-DashSync
