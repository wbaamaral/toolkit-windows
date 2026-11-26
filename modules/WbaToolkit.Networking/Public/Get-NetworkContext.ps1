function Get-NetworkContext {
    <#
    .SYNOPSIS
        Coleta o contexto local de rede.

    .DESCRIPTION
        Identifica adaptador ativo, IPv4 principal, gateway, DNS e dados básicos do ambiente para uso em
        diagnósticos de conectividade.
    #>
    [CmdletBinding()]
    param()

    $startedAt = Get-Date
    $result = [pscustomobject]@{
        Hostname        = $env:COMPUTERNAME
        Username        = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
        InterfaceAlias  = $null
        IPv4Address     = $null
        PrefixLength    = $null
        Gateway         = $null
        DnsServers      = @()
        PowerShell      = $PSVersionTable.PSVersion.ToString()
        OperatingSystem = $null
        StartedAt       = $startedAt
        ErrorMessage    = $null
    }

    try {
        $upAdapters = @(Get-NetAdapter -ErrorAction Stop |
            Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' })

        # O adaptador de contexto e o da rota padrao de menor metrica efetiva. Get-NetAdapter
        # nao tem InterfaceMetric: ordenar por ela nao fazia nada e o resultado era um
        # adaptador "Up" qualquer (VPN, Hyper-V...).
        $defaultRoutes = @()
        try { $defaultRoutes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -AddressFamily IPv4 -ErrorAction Stop) }
        catch { Write-Verbose "Nao foi possivel consultar a rota padrao: $($_.Exception.Message)" }
        $adapter = $null
        foreach ($route in @($defaultRoutes | Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric })) {
            $adapter = $upAdapters | Where-Object { $_.InterfaceIndex -eq $route.InterfaceIndex } | Select-Object -First 1
            if ($adapter) { break }
        }
        if (-not $adapter) { $adapter = $upAdapters | Select-Object -First 1 }

        if ($adapter) {
            $result.InterfaceAlias = $adapter.Name

            $ipAddress = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notin @('127.0.0.1') -and $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1

            if ($ipAddress) {
                $result.IPv4Address  = $ipAddress.IPAddress
                $result.PrefixLength = $ipAddress.PrefixLength
            }

            $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction Stop
            $gateway = $ipConfig.IPv4DefaultGateway | Select-Object -First 1
            if ($gateway -and $gateway.NextHop) {
                $result.Gateway = $gateway.NextHop
            }

            $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
                Select-Object -ExpandProperty ServerAddresses
            $result.DnsServers = @($dnsServers | Where-Object { $_ -and $_ -ne '0.0.0.0' })
        }

        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
            if ($os) {
                $result.OperatingSystem = $os.Caption
            }
        }
        catch {
            $result.OperatingSystem = $null
        }
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
    }

    $result
}
