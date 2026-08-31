#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Watch)
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
$WatchIntervalSeconds = 5; $SignatureCache = @{}
function Format-NetPulseEndpoint {
    param([string]$Address, [uint16]$Port)
    if ($Address.Contains(':')) { '[{0}]:{1}' -f $Address, $Port } else { '{0}:{1}' -f $Address, $Port }
}
function Get-NetPulseAddressScope {
    param([string]$Address)
    $ip = $null; if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return 'Unknown' }
    if ([System.Net.IPAddress]::IsLoopback($ip)) { return 'Loopback' }
    if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($ip.IsIPv4MappedToIPv6) { return Get-NetPulseAddressScope ($ip.MapToIPv4().ToString()) }
        $bytes = $ip.GetAddressBytes()
        if ($ip.IsIPv6LinkLocal) { return 'LinkLocal' }
        if ($ip.IsIPv6Multicast -or $ip.Equals([System.Net.IPAddress]::IPv6Any) -or
            ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8)) { return 'Special' }
        if (($bytes[0] -band 0xFE) -eq 0xFC) { return 'Private' }
        return 'External'
    }
    $bytes = $ip.GetAddressBytes()
    if ($bytes[0] -eq 10 -or ($bytes[0] -eq 172 -and $bytes[1] -in (16..31)) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) { return 'Private' }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return 'LinkLocal' }
    if ($bytes[0] -eq 0 -or $bytes[0] -ge 224 -or ($bytes[0] -eq 100 -and $bytes[1] -in 64..127) -or
        ($bytes[0] -eq 192 -and (($bytes[1] -eq 0 -and $bytes[2] -in @(0, 2)) -or ($bytes[1] -eq 88 -and $bytes[2] -eq 99))) -or
        ($bytes[0] -eq 198 -and ($bytes[1] -in @(18, 19) -or ($bytes[1] -eq 51 -and $bytes[2] -eq 100))) -or
        ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113)) { return 'Special' }
    'External'
}
function Get-NetPulseProcessInfo {
    param([uint32]$ProcessId)
    $process = $null
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        try { $path = [string]$process.Path } catch { $path = '' }
        $signature = 'Unknown'
        if ($path) {
            try {
                $file = Get-Item -LiteralPath $path -ErrorAction Stop
                $stamp = '{0}:{1}' -f $file.Length, $file.LastWriteTimeUtc.Ticks
                $cached = $SignatureCache[$path]
                if ($cached -and $cached.Stamp -eq $stamp) { $signature = $cached.Status }
                else {
                    $signature = (Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop).Status.ToString()
                    $SignatureCache[$path] = [pscustomobject]@{ Stamp = $stamp; Status = $signature }
                }
            } catch { $signature = 'Unknown' }
        }
        [pscustomobject]@{ Name = $process.ProcessName; Signature = $signature }
    } catch { [pscustomobject]@{ Name = 'Unknown'; Signature = 'Unknown' } }
    finally { if ($process) { $process.Dispose() } }
}
function Get-NetPulseSnapshot {
    try { $items = @(Get-NetTCPConnection -State Established -ErrorAction Stop) }
    catch { if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { return }; throw }
    $processes = @{}
    foreach ($connection in $items) {
        $processId = [uint32]$connection.OwningProcess
        if (-not $processes.ContainsKey($processId)) { $processes[$processId] = Get-NetPulseProcessInfo $processId }
        $process = $processes[$processId]
        [pscustomobject][ordered]@{
            ConnectionKey = '{0}|{1}|{2}|{3}|{4}' -f $processId, $connection.LocalAddress, $connection.LocalPort, $connection.RemoteAddress, $connection.RemotePort
            Process = $process.Name; PID = $processId
            Local = Format-NetPulseEndpoint $connection.LocalAddress $connection.LocalPort
            Remote = Format-NetPulseEndpoint $connection.RemoteAddress $connection.RemotePort
            Scope = Get-NetPulseAddressScope $connection.RemoteAddress; Signature = $process.Signature
        }
    }
}
function Show-NetPulse {
    param([string]$Mode, [AllowEmptyCollection()][object[]]$Connections)
    Write-Host "`nNETPULSE | LOCAL TCP CONNECTION MONITOR" -ForegroundColor White
    Write-Host ('Mode: {0} | Connections: {1}' -f $Mode, $Connections.Count)
    if ($Mode -eq 'WATCH') { Write-Host ("Interval: $WatchIntervalSeconds seconds | Press Ctrl+C to stop") }
    Write-Host ('-' * 41) -ForegroundColor DarkGray
    if (-not $Connections.Count) { Write-Host 'No established TCP connections found.' -ForegroundColor DarkGray; return }
    $Connections | Sort-Object Process, PID, Remote | Format-Table Process, PID, Local, Remote, Scope, Signature -AutoSize | Out-String -Width 240 | Write-Host
}
function Compare-NetPulseConnections {
    param([AllowEmptyCollection()][object[]]$Previous, [AllowEmptyCollection()][object[]]$Current)
    $before = @{}; $after = @{}
    foreach ($item in $Previous) { $before[$item.ConnectionKey] = $item }
    foreach ($item in $Current) { $after[$item.ConnectionKey] = $item }
    foreach ($key in $after.Keys) { if (-not $before.ContainsKey($key)) { [pscustomobject]@{ Event = 'OPENED'; Connection = $after[$key] } } }
    foreach ($key in $before.Keys) { if (-not $after.ContainsKey($key)) { [pscustomobject]@{ Event = 'CLOSED'; Connection = $before[$key] } } }
}
function Start-NetPulseWatch {
    param([AllowEmptyCollection()][object[]]$InitialConnections)
    Show-NetPulse WATCH $InitialConnections; $previous = $InitialConnections
    try {
        while ($true) {
            Start-Sleep -Seconds $WatchIntervalSeconds; $current = @(Get-NetPulseSnapshot)
            foreach ($change in @(Compare-NetPulseConnections $previous $current)) {
                $color = if ($change.Event -eq 'OPENED') { 'Green' } else { 'Yellow' }
                $message = '[{0}] {1,-6} {2} ({3}) -> {4}' -f (Get-Date -Format 'HH:mm:ss'), $change.Event,
                    $change.Connection.Process, $change.Connection.PID, $change.Connection.Remote
                Write-Host $message -ForegroundColor $color
            }
            $previous = $current
        }
    } finally { Write-Host "`nnetpulse stopped." -ForegroundColor DarkGray }
}
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'netpulse requires Windows.' }
        foreach ($command in 'Get-NetTCPConnection', 'Get-AuthenticodeSignature') {
            if (-not (Get-Command $command -CommandType Cmdlet -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" }
        }
        $connections = @(Get-NetPulseSnapshot)
        if ($Watch) { Start-NetPulseWatch $connections } else { Show-NetPulse SNAPSHOT $connections }
    } catch { Write-Host ('netpulse error: {0}' -f $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
