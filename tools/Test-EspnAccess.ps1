<#
.SYNOPSIS
    Checks whether ESPN answers this computer: asks for the Premier League team list three ways, one second apart (3 requests).
    Windows PowerShell 5.1, ASCII only. Prints only status codes and sizes, no data.
#>
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
$u = 'https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams'
$ways = @(
    @{ Name = 'refused on 2026-11-10'; UA = 'FADash/0.1 (personal use; manual fetching)' },
    @{ Name = 'probe of 2026-11-09'; UA = 'FADash-probe/0.1 (personal use; one-off check)' },
    @{ Name = 'PowerShell default (as the dash asks)'; UA = '' }
)
foreach ($w in $ways) {
    Start-Sleep -Seconds 1
    try {
        if ($w.UA) { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20 -UserAgent $w.UA -ErrorAction Stop }
        else { $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop }
        Write-Host ('{0}: HTTP {1}, {2} bytes' -f $w.Name, [int]$r.StatusCode, $r.RawContentLength)
    } catch {
        $c = 0; try { $c = [int]$_.Exception.Response.StatusCode } catch { }
        Write-Host ('{0}: failed, HTTP {1} {2}' -f $w.Name, $c, $_.Exception.Message)
    }
}
Write-Host 'Copy these three lines into the chat.'
