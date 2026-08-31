#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Watch)
Set-StrictMode -Version Latest
$Interval = 5
$SignatureCache = @{}
function Get-NetPulseScope {
    param([string]$Address)
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip)) { return 'Unknown' }
    if ([Net.IPAddress]::IsLoopback($ip)) { return 'Loopback' }
    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($ip.IsIPv4MappedToIPv6) { return Get-NetPulseScope ($ip.MapToIPv4().ToString()) }
        $b = $ip.GetAddressBytes()
        if ($ip.IsIPv6LinkLocal) { return 'LinkLocal' }
        if ($ip.IsIPv6Multicast -or $ip.Equals([Net.IPAddress]::IPv6Any) -or
            ($b[0] -eq 0x20 -and $b[1] -eq 0x01 -and $b[2] -eq 0x0d -and $b[3] -eq 0xb8)) { return 'Special' }
        if (($b[0] -band 0xFE) -eq 0xFC) { return 'Private' }
        return 'Public'
    }
    $b = $ip.GetAddressBytes()
    if ($b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -in 16..31) -or
        ($b[0] -eq 192 -and $b[1] -eq 168)) { return 'Private' }
    if ($b[0] -eq 169 -and $b[1] -eq 254) { return 'LinkLocal' }
    $docs = ($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -eq 2) -or
        ($b[0] -eq 198 -and $b[1] -eq 51 -and $b[2] -eq 100) -or
        ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113)
    if ($docs -or ($b[0] -eq 100 -and $b[1] -in 64..127) -or $b[0] -eq 0 -or $b[0] -ge 224) { return 'Special' }
    'Public'
}
function Get-NetPulseProcess {
    param([uint32]$Id)
    $p = $null
    try {
        $p = Get-Process -Id $Id -ErrorAction Stop
        try { $path = [string]$p.Path } catch { $path = '' }
        $signature = 'Unknown'
        if ($path) {
            try {
                $item = Get-Item -LiteralPath $path -ErrorAction Stop
                $key = '{0}|{1}' -f $path, $item.LastWriteTimeUtc.Ticks
                if (-not $SignatureCache.ContainsKey($key)) {
                    $SignatureCache[$key] = (Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop).Status.ToString()
                }
                $signature = $SignatureCache[$key]
            } catch {}
        }
        [pscustomobject]@{ Name = $p.ProcessName; Signature = $signature }
    } catch { [pscustomobject]@{ Name = 'Unknown'; Signature = 'Unknown' } }
    finally { if ($null -ne $p) { $p.Dispose() } }
}
function Get-NetPulseSnapshot {
    $processes = @{}
    foreach ($c in @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)) {
        $id = [uint32]$c.OwningProcess
        if (-not $processes.ContainsKey($id)) { $processes[$id] = Get-NetPulseProcess $id }
        $p = $processes[$id]
        $local = if ($c.LocalAddress.Contains(':')) { '[{0}]:{1}' -f $c.LocalAddress, $c.LocalPort } else { '{0}:{1}' -f $c.LocalAddress, $c.LocalPort }
        $remote = if ($c.RemoteAddress.Contains(':')) { '[{0}]:{1}' -f $c.RemoteAddress, $c.RemotePort } else { '{0}:{1}' -f $c.RemoteAddress, $c.RemotePort }
        [pscustomobject][ordered]@{
            Key = '{0}|{1}|{2}|{3}|{4}' -f $id, $c.LocalAddress, $c.LocalPort, $c.RemoteAddress, $c.RemotePort
            Process = $p.Name; PID = $id; Local = $local; Remote = $remote
            Scope = Get-NetPulseScope $c.RemoteAddress; Signature = $p.Signature
        }
    }
}
function Show-NetPulseSnapshot {
    param([AllowEmptyCollection()][object[]]$Connections, [string]$Mode)
    Write-Host "`nNETPULSE | LOCAL TCP CONNECTION MONITOR" -ForegroundColor White
    Write-Host 'Del Risco Technologies' -ForegroundColor DarkGray
    Write-Host (' Mode: {0} | Connections: {1}' -f $Mode, $Connections.Count)
    if ($Mode -eq 'WATCH') { Write-Host (' Interval: {0}s | Press Ctrl+C to stop' -f $Interval) }
    Write-Host "-----------------------------------------`n" -ForegroundColor DarkGray
    if (-not $Connections.Count) { Write-Host 'No established TCP connections found.' -ForegroundColor DarkGray; return }
    $Connections | Sort-Object Process, PID, Remote | Format-Table Process, PID, Local, Remote, Scope, Signature -AutoSize |
        Out-String -Width 240 | Write-Host
}
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'netpulse requires Windows.' }
        foreach ($name in 'Get-NetTCPConnection', 'Get-AuthenticodeSignature') {
            if (-not (Get-Command $name -CommandType Cmdlet -ErrorAction SilentlyContinue)) { throw "Required command not found: $name" }
        }
        $current = @(Get-NetPulseSnapshot)
        if (-not $Watch) { Show-NetPulseSnapshot -Connections $current -Mode SNAPSHOT; return }
        Show-NetPulseSnapshot -Connections $current -Mode WATCH
        $previous = @{}; foreach ($c in $current) { $previous[$c.Key] = $c }
        try {
            while ($true) {
                Start-Sleep -Seconds $Interval
                $current = @(Get-NetPulseSnapshot)
                $next = @{}; foreach ($c in $current) { $next[$c.Key] = $c }
                foreach ($key in $next.Keys) {
                    if (-not $previous.ContainsKey($key)) {
                        $c = $next[$key]
                        Write-Host ('[{0}] OPENED {1} ({2}) -> {3}' -f (Get-Date -Format HH:mm:ss), $c.Process, $c.PID, $c.Remote) -ForegroundColor Green
                    }
                }
                foreach ($key in $previous.Keys) {
                    if (-not $next.ContainsKey($key)) {
                        $c = $previous[$key]
                        Write-Host ('[{0}] CLOSED {1} ({2}) -> {3}' -f (Get-Date -Format HH:mm:ss), $c.Process, $c.PID, $c.Remote) -ForegroundColor Yellow
                    }
                }
                $previous = $next
            }
        } finally { Write-Host "`nnetpulse stopped." -ForegroundColor DarkGray }
    } catch {
        Write-Host ('netpulse error: {0}' -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
