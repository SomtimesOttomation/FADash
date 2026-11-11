<#
.SYNOPSIS
    FADash: the ESPN source. Downloads ESPN's public, unofficial JSON endpoints and converts them into FADash's own shapes.
.DESCRIPTION
    Windows PowerShell 5.1, ASCII only. Used by the worker runspace in FADash.Host.psm1 and by the tests.

    Unofficial: ESPN publishes no terms or limits for these endpoints, and they can change or stop at any time. This is the
    owner's risk decision for a hobby project (see README, Disclaimer). It is off unless the hidden source switch is on.

    Safeguards that live in this file:
      - Only the public JSON endpoints listed in Get-EspnUrl, plus club crests from a.espncdn.com. No web pages, no login.
      - One request per second, however many items are queued (Invoke-EspnHttp).
      - Every request is counted per host and per kind for the traffic page.
      - NO BETTING DATA. Every converter builds a new object from a short list of fields it names. The raw response is never
        copied, cached or sent to the page, so odds, hasOdds, pickcenter and the like cannot get through. The tests check this.

    Competitions: pl = eng.1, ch = eng.2, l1 = eng.3, l2 = eng.4, cup = eng.fa + eng.league_cup + eng.charity + eng.trophy.
    The identifiers come from the owner's probe run on 2026-11-09 (docs/DATA-SOURCES-REPORT.md on housekeeping/data-sources-report).
#>

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$script:SiteBase = 'https://site.api.espn.com'
$script:LastRequest = [datetime]::MinValue
$script:UserAgent = 'FADash/0.1 (personal use; manual fetching)'   # same form as the probe that worked on 2026-11-09

$script:LeagueIds = @{
    pl  = @('eng.1')
    ch  = @('eng.2')
    l1  = @('eng.3')
    l2  = @('eng.4')
    cup = @('eng.fa', 'eng.league_cup', 'eng.charity', 'eng.trophy')
}
$script:CompNames = @{
    'eng.1' = 'Premier League'; 'eng.2' = 'Championship'; 'eng.3' = 'League One'; 'eng.4' = 'League Two'
    'eng.fa' = 'FA Cup'; 'eng.league_cup' = 'EFL Cup'; 'eng.charity' = 'Community Shield'; 'eng.trophy' = 'EFL Trophy'
}
$script:CompSlugs = @{ fa = 'eng.fa'; efl = 'eng.league_cup'; cs = 'eng.charity'; trophy = 'eng.trophy'; pl = 'eng.1'; ch = 'eng.2'; l1 = 'eng.3'; l2 = 'eng.4' }

function Get-EspnLeagueIds { param([string]$Lg) if ($script:LeagueIds.ContainsKey($Lg)) { return @($script:LeagueIds[$Lg]) } else { return @() } }
function Get-EspnCompId { param([string]$Slug) if ($script:CompSlugs.ContainsKey($Slug)) { return [string]$script:CompSlugs[$Slug] } else { return '' } }

# The base address. Tests may point it at a local fake server; nothing else can change it.
function Get-EspnBase {
    $o = [string]$env:FADASH_ESPN_BASE
    if ($o -match '^http://(localhost|127\.0\.0\.1)(:\d+)?$') { return $o }
    return $script:SiteBase
}
function Test-EspnTestBase { return ((Get-EspnBase) -ne $script:SiteBase) }

function Get-EspnUrl {
    <# The only place a URL is built. Inputs are checked: competition ids come from the fixed list, ids are digits, dates are digits. #>
    param([ValidateSet('scoreboard', 'standings', 'teams', 'roster', 'summary')][string]$Op, [string]$Comp, [string]$Dates = '', [string]$Id = '', [string]$TeamId = '')
    if ($script:CompNames.ContainsKey($Comp) -eq $false) { throw 'Unknown competition.' }
    $b = Get-EspnBase
    switch ($Op) {
        'scoreboard' {
            if ($Dates -notmatch '^\d{8}(-\d{8})?$') { throw 'Bad date.' }
            return "$b/apis/site/v2/sports/soccer/$Comp/scoreboard?dates=$Dates"
        }
        'standings' { return "$b/apis/v2/sports/soccer/$Comp/standings" }
        'teams' { return "$b/apis/site/v2/sports/soccer/$Comp/teams" }
        'roster' {
            if ($TeamId -notmatch '^\d{1,9}$') { throw 'Bad team id.' }
            return "$b/apis/site/v2/sports/soccer/$Comp/teams/$TeamId/roster"
        }
        'summary' {
            if ($Id -notmatch '^\d{1,12}$') { throw 'Bad event id.' }
            return "$b/apis/site/v2/sports/soccer/$Comp/summary?event=$Id"
        }
    }
}

# ---------------------------------------------------------------- downloading
function Invoke-EspnHttp {
    <# One GET. Waits so that requests are at least one second apart, counts the request for the traffic page, honours the kill
       switch. Returns the text, or the bytes with -Binary. Throws a message that starts with "HTTP <code>" for an HTTP error. #>
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)]$Shared, [string]$Kind = 'data', [int]$Gen = -1, [switch]$Binary, [string]$Label = '')
    $okUrl = $Url.StartsWith((Get-EspnBase) + '/') -or $Url.StartsWith('https://a.espncdn.com/')
    if (-not $okUrl) { throw 'Blocked: not one of the known data addresses.' }
    if ($Shared.Halted) { throw 'Data traffic is paused.' }
    if ($Gen -ge 0 -and $Gen -ne $Shared.Gen) { throw 'Stopped.' }
    $minMs = 1000
    if ((Test-EspnTestBase) -and $env:FADASH_ESPN_MIN_MS -match '^\d{1,4}$') { $minMs = [int]$env:FADASH_ESPN_MIN_MS }
    $wait = $minMs - ([datetime]::UtcNow - $script:LastRequest).TotalMilliseconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    $script:LastRequest = [datetime]::UtcNow
    $hostName = ([uri]$Url).Host
    if (-not $Shared.ByHost.ContainsKey($hostName)) { $Shared.ByHost[$hostName] = @{ requests = 0; bytes = [long]0; errors = 0 } }
    if (-not $Shared.ByKind.ContainsKey($Kind)) { $Shared.ByKind[$Kind] = @{ requests = 0; bytes = [long]0 } }
    $hs = $Shared.ByHost[$hostName]
    $Shared.Requests++; $hs.requests++; $Shared.ByKind[$Kind].requests++
    $t0 = Get-Date
    $len = 0
    try {
        # Asked exactly the way the owner's probe asked (Invoke-WebRequest, no extra headers): that is what ESPN answered.
        $r = $null
        try { $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop }   # PowerShell's own user-agent: ESPN refused 'FADash/0.1 (...)' with 403 on 2026-11-10, answered the default
        catch {
            $code = 0
            try { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } } catch { }
            if ($code -gt 0) { throw ('HTTP {0} from {1} ({2})' -f $code, $hostName, ([uri]$Url).AbsolutePath) }
            throw ('Could not reach {0}: {1}' -f $hostName, $_.Exception.Message)
        }
        $bytes = $r.RawContentStream.ToArray()
        $len = $bytes.Length
        $Shared.Bytes += $len; $hs.bytes += $len; $Shared.ByKind[$Kind].bytes += $len
        [void]$Shared.Last.Insert(0, @{ at = $t0.ToString('o'); key = $(if ($Label) { $Label } else { $Kind }); host = $hostName; bytes = $len; ms = [int]((Get-Date) - $t0).TotalMilliseconds; ok = $true })
        while ($Shared.Last.Count -gt 40) { $Shared.Last.RemoveAt(40) }
        if ($Binary) { return , $bytes }
        return (New-Object Text.UTF8Encoding($false)).GetString($bytes)
    } catch {
        $Shared.Errors++; $hs.errors++
        [void]$Shared.Last.Insert(0, @{ at = $t0.ToString('o'); key = $(if ($Label) { $Label } else { $Kind }); host = $hostName; bytes = 0; ms = 0; ok = $false })
        while ($Shared.Last.Count -gt 40) { $Shared.Last.RemoveAt(40) }
        throw
    }
}

function ConvertFrom-EspnJson {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'ESPN sent an empty answer.' }
    try { return ($Text | ConvertFrom-Json) } catch { throw 'ESPN sent an answer that is not JSON.' }
}

# ---------------------------------------------------------------- helpers
function Get-NthSundayUtc {
    param([int]$Year, [int]$Month, [int]$N)
    $d = New-Object DateTime $Year, $Month, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    while ($d.DayOfWeek -ne [DayOfWeek]::Sunday) { $d = $d.AddDays(1) }
    return $d.AddDays(7 * ($N - 1))
}
function Get-EtDayKey {
    <# The US Eastern calendar day (yyyymmdd) of a UTC time. The page groups matches by that day (etKey in util.js). #>
    param([datetime]$Utc)
    $start = (Get-NthSundayUtc $Utc.Year 3 2).AddHours(7)       # 2:00 EST on the second Sunday of March
    $end = (Get-NthSundayUtc $Utc.Year 11 1).AddHours(6)        # 2:00 EDT on the first Sunday of November
    $off = $(if ($Utc -ge $start -and $Utc -lt $end) { -4 } else { -5 })
    return $Utc.AddHours($off).ToString('yyyyMMdd')
}
function ConvertTo-UtcDate {
    param($Value)
    $s = [string]$Value
    if (-not $s) { return $null }
    $r = [datetime]::MinValue
    $ok = [datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$r)
    if ($ok) { return $r } else { return $null }
}
function Get-Text { param($V) if ($null -eq $V) { return '' } else { return [string]$V } }
function Get-Number { param($V) $n = 0; if ($null -ne $V -and [int]::TryParse(([string]$V), [ref]$n)) { return $n } else { return $null } }

function Format-Clock {
    <# ESPN writes "67'", "45'+2'" and "90'+4'". The page wants "67'" and "45+2'". #>
    param([string]$S)
    $t = ([string]$S).Trim()
    if (-not $t) { return '' }
    if ($t -match "^(\d+)'?\s*\+\s*(\d+)'?$") { return "$($Matches[1])+$($Matches[2])'" }
    if ($t -match "^(\d+)'?$") { return "$($Matches[1])'" }
    return $t
}
function Format-Minute {
    <# A goal minute for the goal lines: "45+2" (the page adds the apostrophe). #>
    param([string]$S)
    $t = ([string]$S) -replace "[' ]", ''
    return $t
}
function Get-MinuteSort { param([string]$M) $n = 0; if ($M -match '^(\d+)(\+(\d+))?$') { $n = [int]$Matches[1] * 100; if ($Matches[3]) { $n += [int]$Matches[3] } }; return $n }
function Get-Surname {
    param($Athlete)
    if ($null -eq $Athlete) { return '' }
    $last = Get-Text $Athlete.lastName
    if ($last) { return $last }
    $n = Get-Text $Athlete.displayName
    if (-not $n) { $n = Get-Text $Athlete.shortName }
    if (-not $n) { return '' }
    $parts = $n.Trim() -split '\s+'
    return $parts[$parts.Count - 1]
}

function Get-EspnStatus {
    <# state pre/in/post, phase pre/1H/HT/2H/FT/AET/PENS, plus a detail for matches that will not be played as planned.
       A postponed match arrives from ESPN as state "post", 0-0, status STATUS_POSTPONED: it must never look like a 0-0 result. #>
    param($Event, $Comp)
    $s = $Event.status
    if ($null -eq $s) { $s = $Comp.status }
    $name = Get-Text $s.type.name
    $st = Get-Text $s.type.state
    $out = @{ state = 'pre'; phase = 'pre'; clock = ''; detail = ''; played = $false }
    if ($name -match 'POSTPONED|CANCEL|ABANDON|SUSPEND|FORFEIT') {
        $label = 'Postponed'
        if ($name -match 'CANCEL') { $label = 'Cancelled' } elseif ($name -match 'ABANDON') { $label = 'Abandoned' } elseif ($name -match 'SUSPEND') { $label = 'Suspended' } elseif ($name -match 'FORFEIT') { $label = 'Forfeit' }
        $out.detail = $label
        return $out
    }
    $clock = Format-Clock (Get-Text $s.displayClock)
    switch -Regex ($name) {
        '^STATUS_SCHEDULED$' { $out.state = 'pre'; break }
        '^STATUS_FIRST_HALF$' { $out.state = 'in'; $out.phase = '1H'; $out.clock = $clock; $out.played = $true; break }
        '^STATUS_HALFTIME$' { $out.state = 'in'; $out.phase = 'HT'; $out.clock = 'HT'; $out.played = $true; break }
        '^STATUS_SECOND_HALF$' { $out.state = 'in'; $out.phase = '2H'; $out.clock = $clock; $out.played = $true; break }
        'EXTRA_TIME|OVERTIME|END_OF_REGULATION|HALFTIME_ET' { $out.state = 'in'; $out.phase = '2H'; $out.clock = $clock; $out.played = $true; break }
        'SHOOTOUT|PENALT' { if ($st -eq 'post') { $out.state = 'post'; $out.phase = 'PENS' } else { $out.state = 'in'; $out.phase = 'PENS'; $out.clock = 'Pens' }; $out.played = $true; break }
        'FINAL_PEN' { $out.state = 'post'; $out.phase = 'PENS'; $out.played = $true; break }
        'FINAL_AET' { $out.state = 'post'; $out.phase = 'AET'; $out.played = $true; break }
        '^STATUS_FULL_TIME$|^STATUS_FINAL$' { $out.state = 'post'; $out.phase = 'FT'; $out.played = $true; break }
        default {
            if ($st -eq 'post') { $out.state = 'post'; $out.phase = 'FT'; $out.played = $true }
            elseif ($st -eq 'in') { $out.state = 'in'; $out.phase = '1H'; $out.clock = $clock; $out.played = $true }
            if ($name -match 'DELAY') { $out.detail = 'Delayed' }
        }
    }
    return $out
}

# ---------------------------------------------------------------- scoreboard -> events
function ConvertTo-EspnEvents {
    <# A scoreboard answer -> FADash events. Only named fields are read; the rest of the answer, odds included, is dropped. #>
    param($Json, [string]$Lg, [string]$CompId)
    $list = New-Object System.Collections.Generic.List[object]
    $compName = [string]$script:CompNames[$CompId]
    foreach ($e in @($Json.events)) {
        if ($null -eq $e) { continue }
        $c = @($e.competitions)[0]
        if ($null -eq $c) { continue }
        $status = Get-EspnStatus $e $c
        $utc = ConvertTo-UtcDate $e.date
        if ($null -eq $utc) { $utc = ConvertTo-UtcDate $c.date }
        if ($null -eq $utc) { continue }
        $byTeam = @{}
        $sides = @()
        foreach ($k in @($c.competitors)) {
            $homeAway = Get-Text $k.homeAway
            if ($homeAway -ne 'home' -and $homeAway -ne 'away') { continue }
            $tid = Get-Text $k.team.id
            if (-not $tid) { $tid = Get-Text $k.id }
            $score = $null
            if ($status.played) { $score = Get-Text $k.score; if (-not $score) { $score = '0' } }
            $pens = $null
            if ($status.played -and $null -ne $k.shootoutScore -and (Get-Text $k.shootoutScore) -ne '') { $pens = Get-Text $k.shootoutScore }
            $abbr = Get-Text $k.team.abbreviation
            if (-not $abbr) { $abbr = (Get-Text $k.team.shortDisplayName) }
            $side = [ordered]@{ side = $homeAway; id = $tid; abbr = $abbr; score = $score; pens = $pens; scorers = @() }
            $byTeam[$tid] = $side
            $sides += , $side
        }
        if ($sides.Count -ne 2) { continue }
        # goals: only plays ESPN marks as scoring plays
        if ($status.played) {
            $goals = @{}
            foreach ($d in @($c.details)) {
                if ($null -eq $d -or $d.scoringPlay -ne $true) { continue }
                $tid = Get-Text $d.team.id
                if (-not $byTeam.ContainsKey($tid)) { continue }
                $who = Get-Surname (@($d.athletesInvolved)[0])
                if ($d.ownGoal -eq $true) { $who = "$who (og)" } elseif ($d.penaltyKick -eq $true) { $who = "$who (pen)" }
                if (-not $goals.ContainsKey($tid)) { $goals[$tid] = New-Object System.Collections.Generic.List[object] }
                $goals[$tid].Add([ordered]@{ min = (Format-Minute (Get-Text $d.clock.displayValue)); name = $who })
            }
            foreach ($tid in @($goals.Keys)) { $byTeam[$tid].scorers = @($goals[$tid] | Sort-Object { Get-MinuteSort $_.min }) }
        }
        $ordered = @($sides | Sort-Object { if ($_.side -eq 'away') { 0 } else { 1 } })
        $venue = Get-Text $c.venue.fullName
        $list.Add([ordered]@{
            id = (Get-Text $e.id); league = $Lg; comp = $compName; state = $status.state; phase = $status.phase
            date = $utc.ToString('o'); clock = $status.clock; detail = $status.detail; venue = $venue; sides = $ordered
            dayKey = (Get-EtDayKey $utc)
        })
    }
    return $list.ToArray()      # unrolled: callers wrap in @()
}

function New-EspnDay {
    param([string]$Lg, [string]$DayKey, $Events)
    $evs = @($Events | Sort-Object { $_.date })
    foreach ($e in $evs) { if ($e.Contains('dayKey')) { $e.Remove('dayKey') } }
    return [ordered]@{ league = $Lg; date = $DayKey; events = $evs }
}

function ConvertTo-EspnWeek {
    <# Events (with dayKey) -> the week body: Monday to Sunday, seven days. #>
    param([string]$Lg, [string]$Monday, $Events)
    $m = [datetime]::ParseExact($Monday, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $days = @()
    for ($i = 0; $i -lt 7; $i++) {
        $k = $m.AddDays($i).ToString('yyyyMMdd')
        $days += , (New-EspnDay $Lg $k @($Events | Where-Object { $_.dayKey -eq $k }))
    }
    return [ordered]@{ league = $Lg; monday = $Monday; days = $days }
}

# ---------------------------------------------------------------- standings, clubs, squads, match
function ConvertTo-EspnStandings {
    param($Json, [string]$Lg)
    $entries = @()
    $child = @($Json.children)[0]
    if ($child -and $child.standings) { $entries = @($child.standings.entries) } elseif ($Json.standings) { $entries = @($Json.standings.entries) }
    $rows = @()
    $i = 0
    foreach ($en in $entries) {
        if ($null -eq $en) { continue }
        $i++
        $st = @{}
        foreach ($s in @($en.stats)) { if ($s -and $s.name) { $st[[string]$s.name] = $s.value } }
        $num = { param($n) $v = 0; if ($st.ContainsKey($n) -and $null -ne $st[$n]) { $v = [int][Math]::Round([double]$st[$n]) }; return $v }
        $rank = & $num 'rank'; if ($rank -le 0) { $rank = $i }
        $rows += [pscustomobject][ordered]@{
            id = (Get-Text $en.team.id); abbr = (Get-Text $en.team.abbreviation); gp = (& $num 'gamesPlayed'); w = (& $num 'wins'); d = (& $num 'ties'); l = (& $num 'losses')
            gf = (& $num 'pointsFor'); ga = (& $num 'pointsAgainst'); pts = (& $num 'points'); ded = (& $num 'deductions'); form = @(); rank = $rank
        }
    }
    $sorted = @($rows | Sort-Object rank)
    return [ordered]@{ league = $Lg; teams = $sorted }
}

function ConvertTo-EspnClubs {
    <# The team list of one competition -> clubs { id, abbr, name, color, league, logo }. #>
    param($Json, [string]$Lg)
    $teams = @()
    $sp = @($Json.sports)[0]
    if ($sp) { $lgj = @($sp.leagues)[0]; if ($lgj) { $teams = @($lgj.teams) } }
    $clubs = @()
    foreach ($t in $teams) {
        $x = $t.team
        if ($null -eq $x -or -not $x.id) { continue }
        $color = Get-Text $x.color
        if ($color -notmatch '^[0-9a-fA-F]{6}$') { $color = '6b7280' }
        $logo = ''
        $l0 = @($x.logos)[0]
        if ($l0) { $h = Get-Text $l0.href; if ($h -match '^https://a\.espncdn\.com/' -or ((Test-EspnTestBase) -and $h.StartsWith((Get-EspnBase) + '/'))) { $logo = $h } }
        $abbr = Get-Text $x.abbreviation
        if (-not $abbr) { $abbr = (Get-Text $x.displayName).Substring(0, [Math]::Min(3, (Get-Text $x.displayName).Length)).ToUpper() }
        $clubs += [ordered]@{ id = (Get-Text $x.id); abbr = $abbr; name = (Get-Text $x.displayName); color = $color; league = $Lg; logo = $logo }
    }
    return [ordered]@{ league = $Lg; clubs = $clubs }
}

function ConvertTo-EspnSquad {
    <# A team roster -> players with age. Apps, goals and cards are not in the roster, so they are null (the page shows a dash). #>
    param($Json, [string]$TeamId)
    $flat = @()
    foreach ($a in @($Json.athletes)) {
        if ($null -eq $a) { continue }
        if ($a.items) { foreach ($b in @($a.items)) { $flat += , $b } } else { $flat += , $a }
    }
    $players = @()
    foreach ($a in $flat) {
        if (-not $a.id) { continue }
        $p = (Get-Text $a.position.abbreviation).ToUpper()
        $pos = 'MF'
        if ($p.StartsWith('G')) { $pos = 'GK' } elseif ($p.StartsWith('D') -or $p -in @('CB', 'LB', 'RB', 'WB', 'LWB', 'RWB')) { $pos = 'DF' } elseif ($p.StartsWith('F') -or $p -in @('ST', 'CF', 'LW', 'RW', 'SS')) { $pos = 'FW' } elseif ($p.StartsWith('M')) { $pos = 'MF' }
        $name = Get-Text $a.displayName; if (-not $name) { $name = Get-Text $a.fullName }
        $dob = Get-Text $a.dateOfBirth
        if ($dob.Length -ge 10) { $dob = $dob.Substring(0, 10) } else { $dob = '' }
        $players += [ordered]@{ id = (Get-Text $a.id); name = $name; pos = $pos; no = (Get-Text $a.jersey); age = (Get-Number $a.age); dob = $dob
                                apps = $null; g = $null; a = $null; yc = $null; rc = $null }
    }
    return [ordered]@{ id = $TeamId; players = $players }
}

function ConvertTo-EspnMatch {
    <# A match summary -> key events, line-ups and team stats. Everything else in the answer (odds, news, videos...) is dropped. #>
    param($Json, [string]$Id)
    $events = @()
    foreach ($k in @($Json.keyEvents)) {
        if ($null -eq $k) { continue }
        $who = ''
        $part = @($k.participants)[0]
        if ($part) { $who = Get-Surname $part.athlete }
        $events += [ordered]@{ min = (Format-Minute (Get-Text $k.clock.displayValue)); kind = (Get-Text $k.type.text); team = (Get-Text $k.team.id); who = $who; scoring = ($k.scoringPlay -eq $true) }
    }
    $lineups = @()
    foreach ($r in @($Json.rosters)) {
        if ($null -eq $r) { continue }
        $pl = @()
        foreach ($p in @($r.roster)) {
            if ($null -eq $p) { continue }
            $pl += [ordered]@{ id = (Get-Text $p.athlete.id); name = (Get-Text $p.athlete.displayName); no = (Get-Text $p.jersey); pos = (Get-Text $p.position.abbreviation)
                               starter = ($p.starter -eq $true); on = ($null -ne $p.subbedIn -and $p.subbedIn -ne $false); off = ($null -ne $p.subbedOut -and $p.subbedOut -ne $false) }
        }
        $lineups += [ordered]@{ side = (Get-Text $r.homeAway); team = (Get-Text $r.team.id); formation = (Get-Text $r.formation); players = $pl }
    }
    $stats = @()
    foreach ($t in @($Json.boxscore.teams)) {
        if ($null -eq $t) { continue }
        $rows = @()
        foreach ($s in @($t.statistics)) {
            if ($null -eq $s -or -not $s.name) { continue }
            if ((Get-Text $s.name) -match 'odds|spread|line|bet|pick') { continue }
            $rows += [ordered]@{ name = (Get-Text $s.name); label = (Get-Text $s.label); value = (Get-Text $s.displayValue) }
        }
        $stats += [ordered]@{ side = (Get-Text $t.homeAway); team = (Get-Text $t.team.id); stats = $rows }
    }
    return [ordered]@{ id = $Id; keyEvents = $events; lineups = $lineups; teamStats = $stats }
}

# ---------------------------------------------------------------- one queued item
function Invoke-EspnItem {
    <# Does what one queued key needs and returns the JSON text for the page. $Item comes from Resolve-EspnKey in the host.
       Crests are saved as files under CacheDir\espn\crests and the page gets only their name. #>
    param($Item, $Shared, [string]$CacheDir)
    $gen = [int]$Item.Gen
    $kind = (([string]$Item.Key) -split ':')[0]
    $lg = [string]$Item.Lg
    $json = { param($o) return (ConvertTo-Json -InputObject $o -Depth 8 -Compress) }
    switch ([string]$Item.Op) {
        'day' {
            $evs = @()
            foreach ($c in (Get-EspnLeagueIds $lg)) {
                $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl scoreboard -Comp $c -Dates $Item.Day) $Shared $kind $gen -Label $Item.Key)
                $evs += @(ConvertTo-EspnEvents $j $lg $c)
            }
            return (& $json (New-EspnDay $lg $Item.Day $evs))
        }
        'week' {
            $m = [datetime]::ParseExact($Item.Monday, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            $from = $m.ToString('yyyyMMdd'); $to = $m.AddDays(6).ToString('yyyyMMdd')
            $evs = @()
            foreach ($c in (Get-EspnLeagueIds $lg)) {
                $got = $null
                try {
                    $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl scoreboard -Comp $c -Dates "$from-$to") $Shared $kind $gen -Label $Item.Key)
                    $got = @(ConvertTo-EspnEvents $j $lg $c)
                } catch {
                    # A date range the source does not accept (HTTP 4xx): ask day by day instead. Anything else is a real failure.
                    if ($_.Exception.Message -notmatch '^HTTP 4') { throw }
                }
                if ($null -eq $got) {
                    $got = @()
                    for ($i = 0; $i -lt 7; $i++) {
                        $dk = $m.AddDays($i).ToString('yyyyMMdd')
                        $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl scoreboard -Comp $c -Dates $dk) $Shared $kind $gen -Label $Item.Key)
                        foreach ($e in @(ConvertTo-EspnEvents $j $lg $c)) { $e.dayKey = $dk; $got += $e }
                    }
                }
                $evs += $got
            }
            return (& $json (ConvertTo-EspnWeek $lg $Item.Monday $evs))
        }
        'standings' {
            $c = @(Get-EspnLeagueIds $lg)[0]
            $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl standings -Comp $c) $Shared $kind $gen -Label $Item.Key)
            return (& $json (ConvertTo-EspnStandings $j $lg))
        }
        'clubs' {
            $c = @(Get-EspnLeagueIds $lg)[0]
            $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl teams -Comp $c) $Shared $kind $gen -Label $Item.Key)
            return (& $json (ConvertTo-EspnClubs $j $lg))
        }
        'team' {
            $c = @(Get-EspnLeagueIds $lg)[0]
            $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl roster -Comp $c -TeamId $Item.Id) $Shared $kind $gen -Label $Item.Key)
            return (& $json (ConvertTo-EspnSquad $j $Item.Id))
        }
        'match' {
            $j = ConvertFrom-EspnJson (Invoke-EspnHttp (Get-EspnUrl summary -Comp (Get-EspnCompId $Item.Comp) -Id $Item.Id) $Shared $kind $gen -Label $Item.Key)
            return (& $json (ConvertTo-EspnMatch $j $Item.Id))
        }
        'crest' {
            if ($Item.Id -notmatch '^\d{1,9}$') { throw 'Bad club id.' }
            $logo = [string]$Item.Logo
            if (-not ($logo.StartsWith('https://a.espncdn.com/') -or ((Test-EspnTestBase) -and $logo.StartsWith((Get-EspnBase) + '/')))) { throw 'No crest address for this club.' }
            $bytes = Invoke-EspnHttp $logo $Shared $kind $gen -Binary -Label $Item.Key
            if ($bytes.Length -lt 100 -or $bytes.Length -gt 600000) { throw 'The crest download looked wrong.' }
            $dir = Join-Path (Join-Path $CacheDir 'espn') 'crests'
            [void][IO.Directory]::CreateDirectory($dir)
            [IO.File]::WriteAllBytes((Join-Path $dir ($Item.Id + '.png')), $bytes)
            return (& $json ([ordered]@{ id = [string]$Item.Id; file = ('espn/crests/' + $Item.Id + '.png') }))
        }
        default { throw 'Unknown request.' }
    }
}

Export-ModuleMember -Function Invoke-EspnItem, ConvertTo-EspnEvents, ConvertTo-EspnWeek, ConvertTo-EspnStandings, ConvertTo-EspnClubs, ConvertTo-EspnSquad, ConvertTo-EspnMatch, Get-EspnLeagueIds, Get-EspnCompId, Get-EtDayKey, Invoke-EspnHttp, Get-EspnUrl, Format-Clock
