function Set-ToolkitNetworkDesiredState {
    <#
    .SYNOPSIS
        Etapa network.configure — aplica DHCP ou IP/gateway/DNS estaticos aos adaptadores.

    .DESCRIPTION
        Aplica apenas nos adaptadores identificados como fora do estado desejado (adaptadores
        ja conformes nao sao tocados). Nao reinicia o sistema: mudanca de rede tem efeito
        imediato. A configuracao ja foi copiada para area local protegida antes desta etapa
        rodar (SPEC-PROVISIONING-CONFIG), preservando a fonte mesmo se a rede cair.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $applied = @()
    foreach ($entry in @($Context.Config.network.adapters)) {
        $resolved = Resolve-ToolkitNetworkAdapter -Match $entry.match
        if (-not $resolved.Found) {
            throw "Falha ao identificar adaptador '$($entry.name)' durante Set: $($resolved.Message)"
        }

        $comparison = Compare-ToolkitNetworkAdapterState -Adapter $resolved.Adapter -Desired $entry
        if ($comparison.IsCompliant) {
            continue
        }

        $ifIndex = $resolved.Adapter.ifIndex
        if (-not $PSCmdlet.ShouldProcess("$($entry.name) (ifIndex $ifIndex)", 'Reconfigurar adaptador de rede')) {
            continue
        }

        if ([bool]$entry.dhcp) {
            Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.SuffixOrigin -ne 'WellKnown' } |
                Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
            Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Enabled
            Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses
        }
        else {
            Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.SuffixOrigin -ne 'WellKnown' } |
                Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
            # Rota padrao anterior (DHCP ou configuracao antiga) precisa sair: sem gateway
            # desejado ela impedia convergir, e com gateway New-NetIPAddress falha se ja existir.
            $oldDefaultRoutes = @(Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Where-Object { $null -ne $_ })
            if ($oldDefaultRoutes.Count -gt 0) {
                $oldDefaultRoutes | Remove-NetRoute -Confirm:$false -ErrorAction Stop
            }
            Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled

            $first = $true
            foreach ($cidr in @($entry.addresses)) {
                $parts = $cidr -split '/'
                $ipParams = @{
                    InterfaceIndex = $ifIndex
                    IPAddress      = $parts[0]
                    PrefixLength   = [int]$parts[1]
                    ErrorAction    = 'Stop'
                }
                if ($first -and (Test-ToolkitPropertyPresent -InputObject $entry -Name 'gateway') -and -not [string]::IsNullOrWhiteSpace([string]$entry.gateway)) {
                    $ipParams['DefaultGateway'] = [string]$entry.gateway
                }
                New-NetIPAddress @ipParams | Out-Null
                $first = $false
            }

            if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'dnsServers') -and @($entry.dnsServers).Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($entry.dnsServers)
            }
        }

        $applied += $entry.name
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Adaptadores reconfigurados: $($applied -join ', ')."
        Evidence       = [pscustomobject]@{ AppliedAdapters = $applied }
    }
}
