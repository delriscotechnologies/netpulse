BeforeAll {
    . "$PSScriptRoot/../netpulse.ps1"
}

Describe 'Format-NetPulseEndpoint' {
    It 'formats IPv4 endpoints' {
        Format-NetPulseEndpoint '192.168.1.10' 443 | Should -Be '192.168.1.10:443'
    }

    It 'wraps IPv6 addresses in brackets' {
        Format-NetPulseEndpoint '2001:db8::1' 443 | Should -Be '[2001:db8::1]:443'
    }
}

Describe 'Get-NetPulseAddressScope' {
    It 'classifies IPv4 addresses' -ForEach @(
        @{ Address = '127.0.0.1'; Expected = 'Loopback' }
        @{ Address = '10.10.10.10'; Expected = 'Private' }
        @{ Address = '172.31.255.1'; Expected = 'Private' }
        @{ Address = '192.168.1.1'; Expected = 'Private' }
        @{ Address = '169.254.1.1'; Expected = 'LinkLocal' }
        @{ Address = '100.64.0.1'; Expected = 'Special' }
        @{ Address = '224.0.0.1'; Expected = 'Special' }
        @{ Address = '8.8.8.8'; Expected = 'Public' }
        @{ Address = 'not-an-address'; Expected = 'Unknown' }
    ) {
        Get-NetPulseAddressScope $Address | Should -Be $Expected
    }

    It 'classifies IPv6 addresses' -ForEach @(
        @{ Address = '::1'; Expected = 'Loopback' }
        @{ Address = 'fe80::1'; Expected = 'LinkLocal' }
        @{ Address = 'fd00::1'; Expected = 'Private' }
        @{ Address = 'ff02::1'; Expected = 'Special' }
        @{ Address = '2606:4700:4700::1111'; Expected = 'Public' }
        @{ Address = '::ffff:192.168.1.1'; Expected = 'Private' }
    ) {
        Get-NetPulseAddressScope $Address | Should -Be $Expected
    }
}

Describe 'Compare-NetPulseConnections' {
    It 'returns only newly opened and closed connections' {
        $kept = [pscustomobject]@{ ConnectionKey = 'kept' }
        $closed = [pscustomobject]@{ ConnectionKey = 'closed' }
        $opened = [pscustomobject]@{ ConnectionKey = 'opened' }

        $changes = @(Compare-NetPulseConnections @($kept, $closed) @($kept, $opened))

        $changes.Count | Should -Be 2
        ($changes | Where-Object Event -eq 'OPENED').Connection | Should -Be $opened
        ($changes | Where-Object Event -eq 'CLOSED').Connection | Should -Be $closed
    }

    It 'returns no changes for identical snapshots' {
        $connection = [pscustomobject]@{ ConnectionKey = 'same' }
        @(Compare-NetPulseConnections @($connection) @($connection)).Count | Should -Be 0
    }

    It 'accepts empty snapshots' {
        @(Compare-NetPulseConnections @() @()).Count | Should -Be 0
    }
}

Describe 'Get-NetPulseSnapshot' {
    BeforeEach {
        Mock Get-NetTCPConnection {
            @(
                [pscustomobject]@{
                    OwningProcess = 42; LocalAddress = '192.168.1.5'; LocalPort = 50000
                    RemoteAddress = '8.8.8.8'; RemotePort = 443
                },
                [pscustomobject]@{
                    OwningProcess = 42; LocalAddress = '::1'; LocalPort = 50001
                    RemoteAddress = '::1'; RemotePort = 8443
                }
            )
        }
        Mock Get-NetPulseProcessInfo {
            [pscustomobject]@{ Name = 'browser'; Signature = 'Valid' }
        }
    }

    It 'builds connection records and caches process lookups per snapshot' {
        $result = @(Get-NetPulseSnapshot)

        $result.Count | Should -Be 2
        $result[0].Process | Should -Be 'browser'
        $result.Remote | Should -Contain '8.8.8.8:443'
        $result.Local | Should -Contain '[::1]:50001'
        Should -Invoke Get-NetPulseProcessInfo -Times 1 -Exactly
    }
}
