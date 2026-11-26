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
    # [string]: sem rota padrao o valor e '' (e nao $null), comparavel com o gateway desejado
    # ausente; '$null -eq ""' e falso e um IP estatico sem gateway nunca convergia.
    $currentGateway = "$(Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty NextHop)"
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
    $desiredGateway = if ((Test-ToolkitPropertyPresent -InputObject $Desired -Name 'gateway') -and $Desired.gateway) { [string]$Desired.gateway } else { '' }
    # dnsServers ausente vira lista vazia (e nao @($null), que nunca bate com a lista atual).
    $desiredDns = @(if (Test-ToolkitPropertyPresent -InputObject $Desired -Name 'dnsServers') {
        @($Desired.dnsServers) | Where-Object { $_ } | Sort-Object
    })

    # Listas ja ordenadas: comparacao por texto, que tambem vale para listas vazias.
    $isCompliant = ($currentInterface -and $currentInterface.Dhcp -eq 'Disabled') -and
        (($currentAddresses -join ',') -eq ($desiredAddresses -join ',')) -and
        ($currentGateway -eq $desiredGateway) -and
        (($currentDns -join ',') -eq ($desiredDns -join ','))

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
