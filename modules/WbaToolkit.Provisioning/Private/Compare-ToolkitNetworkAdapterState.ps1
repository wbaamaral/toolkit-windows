function Compare-ToolkitNetworkAdapterState {
    <#
    .SYNOPSIS
        Compara o estado IPv4 atual de um adaptador com a configuracao desejada.

    .DESCRIPTION
        Sem efeitos colaterais. Usada por Test e por Verify (pos-Set) da etapa
        network.configure.

    .PARAMETER Adapter
        Objeto de Get-NetAdapter ja resolvido (ver Resolve-ToolkitNetworkAdapter).

    .PARAMETER Desired
        Entrada de computer.network.adapters (name, match, dhcp, addresses, gateway, dnsServers).

    .OUTPUTS
        System.Management.Automation.PSCustomObject — IsCompliant, Details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Adapter,

        [Parameter(Mandatory)]
        [pscustomobject]$Desired
    )

    $ifIndex = $Adapter.ifIndex
    $currentInterface = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $currentAddresses = @(Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.SuffixOrigin -ne 'WellKnown' } |
            ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" } | Sort-Object)
    $currentGateway = (Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty NextHop)
    $dnsResult = Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $currentDns = @($(if ($dnsResult) { $dnsResult.ServerAddresses } else { @() }) | Sort-Object)

    $desiredDhcp = [bool]$Desired.dhcp

    if ($desiredDhcp) {
        $isCompliant = ($currentInterface -and $currentInterface.Dhcp -eq 'Enabled')
        return [pscustomobject]@{
            IsCompliant = $isCompliant
            Details     = [pscustomobject]@{ Mode = 'Dhcp'; CurrentDhcp = $(if ($currentInterface) { $currentInterface.Dhcp } else { 'Desconhecido' }) }
        }
    }

    $desiredAddresses = @(@($Desired.addresses) | Sort-Object)
    $desiredGateway = [string]$Desired.gateway
    $desiredDns = @(@($Desired.dnsServers) | Sort-Object)

    $isCompliant = ($currentInterface -and $currentInterface.Dhcp -eq 'Disabled') -and
        (@(Compare-Object $currentAddresses $desiredAddresses).Count -eq 0) -and
        ($currentGateway -eq $desiredGateway) -and
        (@(Compare-Object $currentDns $desiredDns).Count -eq 0)

    [pscustomobject]@{
        IsCompliant = [bool]$isCompliant
        Details     = [pscustomobject]@{
            Mode            = 'Static'
            CurrentAddresses = $currentAddresses
            DesiredAddresses = $desiredAddresses
            CurrentGateway   = $currentGateway
            DesiredGateway   = $desiredGateway
            CurrentDns       = $currentDns
            DesiredDns       = $desiredDns
        }
    }
}
