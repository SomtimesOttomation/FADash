<#
.SYNOPSIS
    FADash backend for DashLauncher contract version 1. Data: ESPN's unofficial public JSON feeds (FADash.Espn.psm1).
.DESCRIPTION
    Windows PowerShell 5.1. Built the way NBADash and NHLDash are:

      - The page asks for data by key. English football is one dash with several competitions, so keys carry the league:
        "score:pl:2026-11-09", "week:ch:2026-11-02", "standings:l1", "team:359", plus "clubs:pl", "crest:359" and
        "match:pl:704512". Leagues: pl, ch, l1, l2, cup. Keys are checked against a fixed list here, never turned into
        URLs by the page; FADash.Espn.psm1 builds every address from a fixed list.
      - The cache is cache\espn\<league>\... and cache\espn\crests.
      - A worker runspace downloads one key at a time, at most one request per second, saves a copy in the cache and queues
        the JSON for the page. Receive-DashEvents hands it over. Traffic is counted per server, with the last 40 requests.
      - Nothing is fetched until the person asks (opens a page, presses Refresh, downloads the clubs, runs a season sync).
        Automatic refresh is opt-in behind a warning.
      - A season sync queues one request per week per league and reports real progress to the page and the launcher's rail.
      - Settings live in %APPDATA%\FADash, cache and WebView2 profile in %LOCALAPPDATA%\FADash: never inside
        the dash's own folder, so an update (from the dash or from DashLauncher) never wipes them.
      - The updater (Update-FADash.ps1 + Apply-Update.ps1) is the same as NHLDash's. It only talks to GitHub, and only
        when the person clicks the version or turns "check on start" on (off by default for now).

    ESPN publishes no terms or limits for these feeds and they can change or stop at any time (README, Disclaimer).
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
# Competitions (cup = FA Cup, EFL Cup, Community Shield and EFL Trophy fixtures, no table). Clubs come from the club download.
# A real dash gets its clubs from its data source, keyed by the source's team id.
$script:Leagues = @('pl', 'ch', 'l1', 'l2', 'cup')
$script:Clubs = @()
$script:ClubIds = @()
# Cache sub-folder for the data source.
$script:Pfx = 'espn\'


function Read-EspnClubs {
    # The clubs saved by the last club download (cache\espn\<league>\clubs.json). Empty until the person downloads them.
    $by = [ordered]@{}
    foreach ($lg in @('pl', 'ch', 'l1', 'l2')) {
        $f = Join-Path $script:CacheDir "espn\$lg\clubs.json"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $j = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($c in @($j.clubs)) {
                if ([string]$c.id -notmatch '^\d{1,9}$') { continue }
                if (-not $by.Contains([string]$c.id)) { $by[[string]$c.id] = [ordered]@{ id = [string]$c.id; abbr = [string]$c.abbr; name = [string]$c.name; color = [string]$c.color; league = $lg; logo = [string]$c.logo } }
            }
        } catch { }
    }
    return @($by.Values)
}

function Read-Clubs {
    $script:Clubs = @(Read-EspnClubs)
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
            # From 0.3.0 there is only the real source: the real favourites (favoritesEspn in 0.2.x) become the favourites,
            # and the made-up ones are dropped.
            if ($null -ne $j.favoritesEspn) { $s.favorites = $j.favoritesEspn } elseif ($null -ne $j.source -and [string]$j.source -ne 'espn') { $s.favorites = @() }
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
    # Several favourites, in the order they were starred; only known club ids (any ESPN-style id until the clubs are downloaded).
    param($Value)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($Value)) {
        $v = [string]$t
        if ($out.Contains($v)) { continue }
        if ($script:ClubIds.Count -eq 0) { if ($v -cmatch '^\d{1,9}$') { $out.Add($v) }; continue }
        if ($script:ClubIds -ccontains $v) { $out.Add($v) }
    }
    return , $out.ToArray()
}
function Limit-Seconds { param($Value) $n = 60; try { $n = [int]$Value } catch { }; return [Math]::Max(20, [Math]::Min(600, $n)) }

# ---------------------------------------------------------------- data keys
function Get-SeasonStart {
    # The first Monday on or after 1 August of the season's year (the cups and the Community Shield start in August).
    $n = Get-Date
    $yr = $(if ($n.Month -ge 7) { $n.Year } else { $n.Year - 1 })
    $d = New-Object DateTime $yr, 8, 1
    while ($d.DayOfWeek -ne 'Monday') { $d = $d.AddDays(1) }
    return $d
}
function Get-SeasonWeeks {
    $d = Get-SeasonStart
    $list = @()
    while ($d -le (Get-Date).Date) { $list += $d.ToString('yyyy-MM-dd'); $d = $d.AddDays(7) }
    return , $list
}

function Resolve-EspnKey {
    <# The same page keys for the real source, plus clubs:<league>, crest:<club id> and match:<competition>:<event id>.
       Every file lives under cache\espn\. The page never supplies a URL; the worker builds it from these fields only. #>
    param([string]$k, [string]$today)
    $u = 'https://site.api.espn.com/'
    if ($k -cmatch '^score:(pl|ch|l1|l2|cup):(\d{4}-\d{2}-\d{2})$') {
        $lg = $Matches[1]; $day = $Matches[2]
        try { [void][datetime]::ParseExact($day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
        $ttl = $(if ($day -lt $today) { 3600 } else { 30 })
        return @{ Key = $k; Url = $u; Op = 'day'; Lg = $lg; Day = $day.Replace('-', ''); File = "espn\$lg\score-$day.json"; Ttl = $ttl }
    }
    if ($k -cmatch '^week:(pl|ch|l1|l2|cup):(\d{4}-\d{2}-\d{2})$') {
        $lg = $Matches[1]; $day = $Matches[2]
        try { $d = [datetime]::ParseExact($day, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
        if ($d.DayOfWeek -ne 'Monday') { return $null }
        $ttl = $(if ($d.AddDays(8) -lt (Get-Date).Date) { 2592000 } else { 600 })
        return @{ Key = $k; Url = $u; Op = 'week'; Lg = $lg; Monday = $day; File = "espn\$lg\week-$day.json"; Ttl = $ttl }
    }
    if ($k -cmatch '^standings:(pl|ch|l1|l2)$') {
        $lg = $Matches[1]
        return @{ Key = $k; Url = $u; Op = 'standings'; Lg = $lg; File = "espn\$lg\standings.json"; Ttl = 600 }
    }
    if ($k -cmatch '^clubs:(pl|ch|l1|l2)$') {
        $lg = $Matches[1]
        return @{ Key = $k; Url = $u; Op = 'clubs'; Lg = $lg; File = "espn\$lg\clubs.json"; Ttl = 604800 }
    }
    if ($k -cmatch '^team:(\d{1,9})$' -and $script:ClubIds -ccontains $Matches[1]) {
        $id = $Matches[1]
        $club = $script:Clubs | Where-Object { $_.id -ceq $id } | Select-Object -First 1
        return @{ Key = $k; Url = $u; Op = 'team'; Lg = $club.league; Id = $id; File = "espn\$($club.league)\team-$id.json"; Ttl = 21600 }
    }
    if ($k -cmatch '^crest:(\d{1,9})$' -and $script:ClubIds -ccontains $Matches[1]) {
        $id = $Matches[1]
        $club = $script:Clubs | Where-Object { $_.id -ceq $id } | Select-Object -First 1
        if (-not $club.logo) { return $null }
        return @{ Key = $k; Url = $u; Op = 'crest'; Lg = $club.league; Id = $id; Logo = [string]$club.logo; File = "espn\crests\$id.json"; Ttl = 7776000 }
    }
    if ($k -cmatch '^match:(pl|ch|l1|l2|fa|efl|cs|trophy):(\d{1,12})$') {
        return @{ Key = $k; Url = $u; Op = 'match'; Comp = $Matches[1]; Id = $Matches[2]; File = "espn\match\$($Matches[1])-$($Matches[2]).json"; Ttl = 120 }
    }
    return $null
}

function Resolve-DataKey {
    <# Turns a page key into a request spec, or $null if the key is not allowed. The page never supplies a URL. #>
    param([string]$Key)
    return (Resolve-EspnKey ([string]$Key) ((Get-Date).ToString('yyyy-MM-dd')))
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
    param($Shared, $Queue, $Out, $CacheDir, $EspnModule)
    Import-Module $EspnModule -Force -DisableNameChecking
    $utf8 = New-Object Text.UTF8Encoding($false)

    while (-not $Shared.Quit) {
        $item = $null
        if (-not $Queue.TryTake([ref]$item, 500)) { continue }
        try {
            if ($Shared.Halted -or $item.Gen -ne $Shared.Gen -or $Shared.Skip.ContainsKey($item.Key)) { continue }
            # FADash.Espn.psm1 counts every HTTP request itself (per server, per kind, one request per second).
            $text = Invoke-EspnItem $item $Shared $CacheDir
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
    [void]$ps.AddScript($script:WorkerScript).AddArgument($script:Shared).AddArgument($script:Queue).AddArgument($script:Out).AddArgument($script:CacheDir).AddArgument((Join-Path $PSScriptRoot 'FADash.Espn.psm1'))
    $script:WorkerHandle = $ps.BeginInvoke()
    $script:Worker = $ps
}

function Clear-Queue {
    $x = $null
    while ($script:Queue.TryTake([ref]$x)) { }
    $script:Shared.Pending.Clear()
}

function Get-SettingsView {
    # The settings the page sees: the favourites of the running source under "favorites".
    $o = [ordered]@{}
    foreach ($k in @($script:Settings.Keys)) { $o[$k] = $script:Settings[$k] }
    $o.favorites = @($script:Settings.favorites)
    return $o
}
function Get-TeamsView {
    # The clubs for the page. The crest address (a download link) stays here; the page only learns whether a crest file is saved.
    $list = @()
    foreach ($c in $script:Clubs) {
        $o = [ordered]@{ id = $c.id; abbr = $c.abbr; name = $c.name; color = $c.color; league = $c.league }
        $o.crest = [bool](Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $script:CacheDir 'espn') 'crests') "$($c.id).png"))
        $list += , $o
    }
    return , $list
}
function Get-Snapshot {
    return @{
        source = 'espn'
        mode = [string]$script:Ctx.Mode; version = $script:Version; theme = [string]$script:Ctx.Theme
        launcherVersion = [string]$script:Ctx.LauncherVersion
        halted = [bool]$script:Shared.Halted; live = [int]$script:Shared.Live
        error = $script:Shared.LastError
        settings = (Get-SettingsView)
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
    # 0.2.x saved its made-up (pretend) data in cache\pl, cache\ch, ...: remove those folders once. Real data lives in cache\espn.
    foreach ($old in @('pl', 'ch', 'l1', 'l2', 'cup')) {
        $op = Join-Path $script:CacheDir $old
        if (Test-Path -LiteralPath $op) { Remove-Item -LiteralPath $op -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Read-Clubs
    $script:Settings = Read-Settings
    $script:Shared = [hashtable]::Synchronized(@{
        Quit = $false; Halted = $false; Gen = 0; Live = 0; Requests = 0; Bytes = [long]0; Errors = 0; LastError = $null
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
                $snap.teams = (Get-TeamsView)
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
            'season.weeks' {
                # per week: the leagues that have a saved copy of it
                $weeks = foreach ($w in (Get-SeasonWeeks)) { @{ monday = $w; leagues = @($script:Leagues | Where-Object { $null -ne (Get-CacheAge "$($script:Pfx)$_\week-$w.json") }) } }
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
                Get-ChildItem -LiteralPath $script:CacheDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.json$' -and $_.FullName -notmatch '[\\/]crests[\\/]' } | Remove-Item -Force -ErrorAction SilentlyContinue
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
    while ($out.Count -lt 25 -and $script:Out.TryDequeue([ref]$msg)) {
        $out.Add($msg)
        # a club list was just saved: the host learns the new club ids before the page can ask for a team or a crest
        if ($msg.StartsWith('{"event":"data","data":{"key":"clubs:')) { Read-Clubs }
    }
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
        Live            = $(if ($s.Halted) { 0 } else { [int]$s.Live })
        Syncing         = $syncing
        SyncPct         = $syncPct
        UpdateAvailable = $script:UpdateAvailable
        Error           = $(if ($s.Halted) { $null } else { $s.LastError })
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
