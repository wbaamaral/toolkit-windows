function Test-ToolkitFirewallRulesDesiredState {
    <#
    .SYNOPSIS
        Etapa firewall.rules — verifica as regras de firewall customizadas declaradas.

    .DESCRIPTION
        SPEC-PROVISIONING-CONFIG: 'firewall' e a secao para regras adicionais geridas pelo
        Toolkit, distinta das regras built-in tratadas por remoteaccess.winrm/rdp. Sem
        desabilitacao global no MVP — esta etapa nunca toca em regras nao declaradas aqui.

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
    if (-not ($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'firewall') -and
            (Test-ToolkitPropertyPresent -InputObject $config.firewall -Name 'rules'))) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "Secao 'firewall.rules' nao declarada."; Evidence = $null }
    }

    $entries = @($config.firewall.rules)
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Message = "'firewall.rules' esta vazio."; Evidence = $null }
    }

    $evaluations = @()
    foreach ($entry in $entries) {
        $enabled = [bool]((Test-ToolkitPropertyPresent -InputObject $entry -Name 'enabled') -and $entry.enabled)
        $direction = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'direction') -and $entry.direction) { [string]$entry.direction } else { 'Inbound' }
        $protocol = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'protocol')) { [string]$entry.protocol } else { $null }
        $localPort = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'localPort')) { [string]$entry.localPort } else { $null }
        $profile = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'profile')) { @($entry.profile) } else { @('Domain', 'Private') }

        $state = Test-ToolkitFirewallRuleState -Name $entry.name -Enabled $enabled -Direction $direction -Protocol $protocol -LocalPort $localPort -Profile $profile
        $evaluations += [pscustomobject]@{ Name = $entry.name; IsCompliant = $state.IsCompliant; Details = $state.Details }
    }

    $nonCompliant = @($evaluations | Where-Object { -not $_.IsCompliant })
    $evidence = [pscustomobject]@{ Rules = $evaluations }

    if ($nonCompliant.Count -eq 0) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todas as regras de firewall declaradas ja atendem a configuracao.'; Evidence = $evidence }
    }

    $names = ($nonCompliant | ForEach-Object { $_.Name }) -join ', '
    return [pscustomobject]@{ Status = 'Changed'; Message = "Regras pendentes: $names."; Evidence = $evidence }
}
