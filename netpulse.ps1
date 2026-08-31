[CmdletBinding()]
param([switch]$Watch)

Set-StrictMode -Version Latest
$script:WatchIntervalSeconds = 5
$script:SignatureCache = @{}

function Format-NetPulseEndpoint {
    param([string]$Address, [uint16]$Port)
    if ($Address.Contains(':')) { return '[{0}]:{1}' -f $Address, $Port }
    '{0}:{1}' -f $Address, $Port
}

function Get-NetPulseAddressScope {
    param([string]$Address)

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return 'Unknown' }
    if ([System.Net.IPAddress]::IsLoopback($ip)) { return 'Loopback' }

    if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($ip.IsIPv4MappedToIPv6) {
            return Get-NetPulseAddressScope ($ip.MapToIPv4().ToString())
        }
        if ($ip.IsIPv6LinkLocal) { return 'LinkLocal' }
        if ($ip.IsIPv6Multicast -or $ip.Equals([System.Net.IPAddress]::IPv6Any)) { return 'Special' }
        if (($ip.GetAddressBytes()[0] -band 0xFE) -eq 0xFC) { return 'Private' }
        return 'Public'
    }

    $bytes = $ip.GetAddressBytes()
    if ($bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) { return 'Private' }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return 'LinkLocal' }
    if (($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) -or
        $bytes[0] -eq 0 -or $bytes[0] -ge 224) { return 'Special' }
    'Public'
}

function Get-NetPulseProcessInfo {
    param([uint32]$ProcessId)

    $process = $null
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        try { $path = [string]$process.Path } catch { $path = '' }
        $signature = 'Unknown'

        if ($path -and $script:SignatureCache.ContainsKey($path)) {
            $signature = $script:SignatureCache[$path]
        }
        elseif ($path) {
            try {
                $signature = (Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop).Status.ToString()
            }
            catch { $signature = 'Unknown' }
            $script:SignatureCache[$path] = $signature
        }

        [pscustomobject]@{ Name = $process.ProcessName; Signature = $signature }
    }
    catch { [pscustomobject]@{ Name = 'Unknown'; Signature = 'Unknown' } }
    finally { if ($null -ne $process) { $process.Dispose() } }
}

function Get-NetPulseSnapshot {
    $processCache = @{}
    $connections = foreach ($connection in (Get-NetTCPConnection -State Established -ErrorAction Stop)) {
        $processId = [uint32]$connection.OwningProcess
        if (-not $processCache.ContainsKey($processId)) {
            $processCache[$processId] = Get-NetPulseProcessInfo $processId
        }

        $process = $processCache[$processId]
        [pscustomobject][ordered]@{
            ConnectionKey = '{0}|{1}|{2}|{3}|{4}' -f $processId, $connection.LocalAddress,
                $connection.LocalPort, $connection.RemoteAddress, $connection.RemotePort
            Process       = $process.Name
            PID           = $processId
            Local         = Format-NetPulseEndpoint $connection.LocalAddress $connection.LocalPort
            Remote        = Format-NetPulseEndpoint $connection.RemoteAddress $connection.RemotePort
            Scope         = Get-NetPulseAddressScope $connection.RemoteAddress
            Signature     = $process.Signature
        }
    }
    $connections | Sort-Object Process, PID, Remote
}

function Show-NetPulseBanner {
    param([string]$Mode, [int]$ConnectionCount)
    Write-Host "`nNETPULSE | LOCAL TCP CONNECTION MONITOR" -ForegroundColor White
    Write-Host 'Del Risco Technologies | v1.1.0' -ForegroundColor DarkGray
    Write-Host (' Mode: {0} | Connections: {1}' -f $Mode, $ConnectionCount)
    if ($Mode -eq 'WATCH') {
        Write-Host (' Interval: {0} seconds | Press Ctrl+C to stop' -f $script:WatchIntervalSeconds)
    }
    Write-Host "-----------------------------------------`n" -ForegroundColor DarkGray
}

function Show-NetPulseConnection {
    param([AllowEmptyCollection()][object[]]$Connections)
    if ($Connections.Count -eq 0) {
        Write-Host 'No established TCP connections found.' -ForegroundColor DarkGray
        return
    }
    $Connections | Format-Table Process, PID, Local, Remote, Scope, Signature -AutoSize |
        Out-String -Width 240 | Write-Host
}

function Show-NetPulseEvent {
    param([string]$Event, $Connection)
    $color = if ($Event -eq 'OPENED') { 'Green' } else { 'Yellow' }
    $message = '[{0}] {1,-6} {2} ({3}) -> {4}' -f (Get-Date -Format 'HH:mm:ss'),
        $Event, $Connection.Process, $Connection.PID, $Connection.Remote
    Write-Host $message -ForegroundColor $color
}

function Compare-NetPulseConnections {
    param(
        [AllowEmptyCollection()][object[]]$Previous,
        [AllowEmptyCollection()][object[]]$Current
    )
    $previousMap = @{}
    $currentMap = @{}
    foreach ($connection in $Previous) { $previousMap[$connection.ConnectionKey] = $connection }
    foreach ($connection in $Current) { $currentMap[$connection.ConnectionKey] = $connection }

    foreach ($key in $currentMap.Keys) {
        if (-not $previousMap.ContainsKey($key)) {
            [pscustomobject]@{ Event = 'OPENED'; Connection = $currentMap[$key] }
        }
    }
    foreach ($key in $previousMap.Keys) {
        if (-not $currentMap.ContainsKey($key)) {
            [pscustomobject]@{ Event = 'CLOSED'; Connection = $previousMap[$key] }
        }
    }
}

function Start-NetPulseWatch {
    param([AllowEmptyCollection()][object[]]$InitialConnections)

    Show-NetPulseBanner WATCH $InitialConnections.Count
    Show-NetPulseConnection $InitialConnections
    $previous = $InitialConnections

    try {
        while ($true) {
            Start-Sleep -Seconds $script:WatchIntervalSeconds
            $current = @(Get-NetPulseSnapshot)
            foreach ($change in @(Compare-NetPulseConnections $previous $current)) {
                Show-NetPulseEvent $change.Event $change.Connection
            }
            $previous = $current
        }
    }
    finally { Write-Host "`nnetpulse stopped." -ForegroundColor DarkGray }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            throw 'netpulse requires Windows.'
        }
        foreach ($command in 'Get-NetTCPConnection', 'Get-AuthenticodeSignature') {
            if (-not (Get-Command $command -CommandType Cmdlet -ErrorAction SilentlyContinue)) {
                throw "Required command not found: $command"
            }
        }

        $connections = @(Get-NetPulseSnapshot)
        if ($Watch) { Start-NetPulseWatch $connections }
        else {
            Show-NetPulseBanner SNAPSHOT $connections.Count
            Show-NetPulseConnection $connections
        }
    }
    catch {
        Write-Host ('netpulse error: {0}' -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
