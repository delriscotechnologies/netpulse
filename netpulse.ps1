#Requires -Version 5.1

<#
.SYNOPSIS
Shows established TCP connections or watches them for changes.

.DESCRIPTION
netpulse maps established TCP connections to local processes, classifies remote
addresses, checks executable signatures, and writes a compact console report.
It is read-only, makes no external requests, and stores no connection data.

.PARAMETER Watch
Keeps monitoring every five seconds. Press Ctrl+C to stop.

.EXAMPLE
.\netpulse.ps1 [-Watch]
#>

[CmdletBinding()]
param([switch]$Watch)
Set-StrictMode -Version Latest

$script:WatchIntervalSeconds = 5
$script:SignatureCache = @{}

function Format-NetPulseEndpoint {
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][uint16]$Port
    )
    if ($Address.Contains(':')) { return '[{0}]:{1}' -f $Address, $Port }
    return '{0}:{1}' -f $Address, $Port
}

function Get-NetPulseAddressScope {
    param([Parameter(Mandatory)][string]$Address)
    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress)) { return 'Unknown' }
    if ([System.Net.IPAddress]::IsLoopback($parsedAddress)) { return 'Loopback' }

    if ($parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($parsedAddress.IsIPv4MappedToIPv6) {
            return Get-NetPulseAddressScope -Address $parsedAddress.MapToIPv4().ToString()
        }
        if ($parsedAddress.IsIPv6LinkLocal) { return 'LinkLocal' }
        if ($parsedAddress.IsIPv6Multicast -or $parsedAddress.Equals([System.Net.IPAddress]::IPv6Any)) {
            return 'Special'
        }

        $bytes = $parsedAddress.GetAddressBytes()
        if (($bytes[0] -band 0xFE) -eq 0xFC) { return 'Private' }
        return 'Public'
    }

    $bytes = $parsedAddress.GetAddressBytes()
    if ($bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)) {
        return 'Private'
    }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return 'LinkLocal' }
    if (($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) -or
        $bytes[0] -eq 0 -or $bytes[0] -ge 224) {
        return 'Special'
    }

    return 'Public'
}

function Get-NetPulseSignatureStatus {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'Unknown' }
    if ($script:SignatureCache.ContainsKey($Path)) { return $script:SignatureCache[$Path] }

    try {
        $status = (Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status.ToString()
    }
    catch {
        $status = 'Unknown'
    }

    $script:SignatureCache[$Path] = $status
    return $status
}

function Get-NetPulseProcessInfo {
    param([Parameter(Mandatory)][uint32]$ProcessId)
    $name = 'Unknown'
    $path = ''
    $process = $null

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $name = $process.ProcessName
        try { $path = [string]$process.Path } catch { $path = '' }
    }
    catch {
        $name = 'Unknown'
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }

    [pscustomobject]@{
        Name      = $name
        Signature = Get-NetPulseSignatureStatus -Path $path
    }
}

function Get-NetPulseSnapshot {
    $connections = Get-NetTCPConnection -State Established -ErrorAction Stop
    $processCache = @{}

    $results = foreach ($connection in $connections) {
        $processId = [uint32]$connection.OwningProcess
        if (-not $processCache.ContainsKey($processId)) {
            $processCache[$processId] = Get-NetPulseProcessInfo -ProcessId $processId
        }

        $processInfo = $processCache[$processId]
        [pscustomobject][ordered]@{
            ConnectionKey = '{0}|{1}|{2}|{3}|{4}' -f $processId,
                $connection.LocalAddress, $connection.LocalPort,
                $connection.RemoteAddress, $connection.RemotePort
            Process       = $processInfo.Name
            PID           = $processId
            Local         = Format-NetPulseEndpoint -Address $connection.LocalAddress -Port $connection.LocalPort
            Remote        = Format-NetPulseEndpoint -Address $connection.RemoteAddress -Port $connection.RemotePort
            Scope         = Get-NetPulseAddressScope -Address $connection.RemoteAddress
            Signature     = $processInfo.Signature
        }
    }

    $results | Sort-Object -Property Process, PID, Remote
}

function Show-NetPulseBanner {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][int]$ConnectionCount
    )
    $asciiArt = @(
        ' _ __   ___| |_ _ __  _   _| |___  ___'
        '| ''_ \ / _ \ __| ''_ \| | | | / __|/ _ \'
        '| | | |  __/ |_| |_) | |_| | \__ \  __/'
        '|_| |_|\___|\__| .__/ \__,_|_|___/\___|'
        '               |_|'
    )
    $width = [int]($asciiArt | Measure-Object -Property Length -Maximum).Maximum

    try {
        $consoleWidth = [Console]::WindowWidth
        if ($consoleWidth -le 0) { $consoleWidth = 80 }
    }
    catch {
        $consoleWidth = 80
    }

    $leftPadding = ' ' * [int][Math]::Max(0, [Math]::Floor(($consoleWidth - $width) / 2))
    $separator = '-' * $width
    Write-Host ''
    foreach ($line in $asciiArt) { Write-Host ($leftPadding + $line) -ForegroundColor White }
    Write-Host ($leftPadding + 'LOCAL TCP CONNECTION MONITOR') -ForegroundColor DarkGray
    Write-Host ($leftPadding + 'Del Risco Technologies  |  v1.0.0') -ForegroundColor DarkGray
    Write-Host ($leftPadding + $separator) -ForegroundColor DarkGray
    Write-Host ($leftPadding + ' Mode           : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $Mode -ForegroundColor Green
    Write-Host ($leftPadding + ' Connections    : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $ConnectionCount -ForegroundColor Green

    if ($Mode -eq 'WATCH') {
        Write-Host ($leftPadding + ' Interval       : ') -NoNewline -ForegroundColor DarkGray
        Write-Host "$($script:WatchIntervalSeconds) seconds" -ForegroundColor Green
    }

    Write-Host ($leftPadding + $separator) -ForegroundColor DarkGray
    if ($Mode -eq 'WATCH') { Write-Host ($leftPadding + ' Press Ctrl+C to stop') -ForegroundColor DarkGray }
    Write-Host ''
}

function Show-NetPulseConnection {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Connections)
    if ($Connections.Count -eq 0) {
        Write-Host 'No established TCP connections found.' -ForegroundColor DarkGray
        return
    }

    $table = $Connections |
        Select-Object -Property Process, PID, Local, Remote, Scope, Signature |
        Format-Table -AutoSize |
        Out-String -Width 240
    Write-Host $table.TrimEnd()
}

function Show-NetPulseEvent {
    param(
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)]$Connection
    )
    $color = if ($Event -eq 'OPENED') { 'Green' } else { 'Yellow' }
    $message = '[{0}] {1,-6} {2} ({3}) -> {4}' -f (Get-Date -Format 'HH:mm:ss'),
        $Event, $Connection.Process, $Connection.PID, $Connection.Remote
    Write-Host $message -ForegroundColor $color
}

function Start-NetPulseWatch {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InitialConnections)
    Show-NetPulseBanner -Mode WATCH -ConnectionCount $InitialConnections.Count
    Show-NetPulseConnection -Connections $InitialConnections
    Write-Host ''

    $previousConnections = $InitialConnections
    try {
        while ($true) {
            Start-Sleep -Seconds $script:WatchIntervalSeconds
            $currentConnections = @(Get-NetPulseSnapshot)
            $previousMap = @{}
            $currentMap = @{}

            foreach ($connection in $previousConnections) {
                $previousMap[$connection.ConnectionKey] = $connection
            }
            foreach ($connection in $currentConnections) {
                $currentMap[$connection.ConnectionKey] = $connection
            }

            foreach ($key in ($currentMap.Keys | Sort-Object)) {
                if (-not $previousMap.ContainsKey($key)) {
                    Show-NetPulseEvent -Event OPENED -Connection $currentMap[$key]
                }
            }
            foreach ($key in ($previousMap.Keys | Sort-Object)) {
                if (-not $currentMap.ContainsKey($key)) {
                    Show-NetPulseEvent -Event CLOSED -Connection $previousMap[$key]
                }
            }

            $previousConnections = $currentConnections
        }
    }
    finally {
        try {
            $previousColor = [Console]::ForegroundColor
            [Console]::ForegroundColor = [ConsoleColor]::DarkGray
            [Console]::WriteLine("`nnetpulse stopped.")
            [Console]::ForegroundColor = $previousColor
        }
        catch {
            $null = $_
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            throw 'netpulse requires Windows.'
        }

        foreach ($commandName in 'Get-NetTCPConnection', 'Get-AuthenticodeSignature') {
            if (-not (Get-Command -Name $commandName -CommandType Cmdlet -ErrorAction SilentlyContinue)) {
                throw "Required command not found: $commandName"
            }
        }

        $connections = @(Get-NetPulseSnapshot)
        if ($Watch) {
            Start-NetPulseWatch -InitialConnections $connections
        }
        else {
            Show-NetPulseBanner -Mode SNAPSHOT -ConnectionCount $connections.Count
            Show-NetPulseConnection -Connections $connections
        }
    }
    catch {
        Write-Host ("netpulse error: {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
