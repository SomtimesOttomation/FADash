<#
.SYNOPSIS
    Switches FADash between its PRETEND data (default) and the hidden real ESPN source. Close FADash first.
.DESCRIPTION
    Edits only the "source" value in %APPDATA%\FADash\settings.json (the file is created if it is missing) and keeps every
    other setting. FADash reads it when it starts. The environment variable FADASH_SOURCE=espn does the same for one
    session. Windows PowerShell 5.1, ASCII only.

      .\Set-FADashSource.ps1 espn
      .\Set-FADashSource.ps1 pretend
#>
param([Parameter(Mandatory)][ValidateSet('espn', 'pretend')][string]$Source)

$dir = Join-Path $env:APPDATA 'FADash'
$file = Join-Path $dir 'settings.json'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$o = [ordered]@{}
if (Test-Path $file) {
    try {
        $j = [IO.File]::ReadAllText($file) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $o[$p.Name] = $p.Value }
    } catch {
        Write-Host 'The settings file could not be read, so nothing was changed.' -ForegroundColor Yellow
        exit 1
    }
}
$o['source'] = $Source
[IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $o -Compress))
if ($Source -eq 'espn') {
    Write-Host 'FADash will use the real ESPN source the next time it starts.'
    Write-Host 'ESPN publishes no terms or limits for these feeds. FADash fetches only when you ask, at most one request per second.'
} else {
    Write-Host 'FADash will use the made-up PRETEND data the next time it starts.'
}
