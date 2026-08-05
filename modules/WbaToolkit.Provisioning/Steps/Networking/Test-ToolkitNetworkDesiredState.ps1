function Test-ToolkitNetworkDesiredState {
    <#
    .SYNOPSIS
        Etapa network.configure — verifica se os adaptadores declarados atendem a configuracao.

    .DESCRIPTION
        Para cada entrada em computer.network.adapters, resolve o adaptador por MAC/PnP/alias
        (nunca por indice) e compara DHCP ou endereco/gateway/DNS estaticos com o estado atual.
        Identificacao ambigua ou ausente falha a etapa inteira sem tentar os demais adaptadores
        (mesmo principio de seguranca aplicado a discos em SPEC-PROVISIONING-SECURITY).

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status, Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $config = $Context.Config
    if (-not ($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'network') -and
            (Test-ToolkitPropertyPresent -InputObject $config.network -Name 'adapters'))) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'network.adapters' nao declarada."; Evidence = $null }
    }

    $adapterEntries = @($config.network.adapters)
    if ($adapterEntries.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "'network.adapters' esta vazio."; Evidence = $null }
    }

    $evaluations = @()
    foreach ($entry in $adapterEntries) {
        $resolved = Resolve-ToolkitNetworkAdapter -Match $entry.match
        if (-not $resolved.Found) {
            return [pscustomobject]@{
                Status   = 'Failed'
                Message  = "Falha ao identificar adaptador '$($entry.name)': $($resolved.Message)"
                Evidence = [pscustomobject]@{ Entry = $entry.name; Reason = $resolved.Message }
            }
        }

        $comparison = Compare-ToolkitNetworkAdapterState -Adapter $resolved.Adapter -Desired $entry
        $evaluations += [pscustomobject]@{
            Name        = $entry.name
            IfIndex     = $resolved.Adapter.ifIndex
            IsCompliant = $comparison.IsCompliant
            Details     = $comparison.Details
        }
    }

    $nonCompliant = @($evaluations | Where-Object { -not $_.IsCompliant })
    $evidence = [pscustomobject]@{ Adapters = $evaluations }

    if ($nonCompliant.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todos os adaptadores declarados ja atendem a configuracao.'; Evidence = $evidence }
    }

    $names = ($nonCompliant | ForEach-Object { $_.Name }) -join ', '
    return [pscustomobject]@{ Status = 'Changed'; Message = "Adaptadores fora do estado desejado: $names."; Evidence = $evidence }
}
