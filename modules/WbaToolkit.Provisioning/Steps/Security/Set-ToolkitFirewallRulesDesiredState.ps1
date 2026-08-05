function Set-ToolkitFirewallRulesDesiredState {
    <#
    .SYNOPSIS
        Etapa firewall.rules — aplica as regras de firewall customizadas pendentes.

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
    foreach ($entry in @($Context.Config.firewall.rules)) {
        $enabled = [bool]((Test-ToolkitPropertyPresent -InputObject $entry -Name 'enabled') -and $entry.enabled)
        $direction = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'direction') -and $entry.direction) { [string]$entry.direction } else { 'Inbound' }
        $protocol = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'protocol')) { [string]$entry.protocol } else { $null }
        $localPort = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'localPort')) { [string]$entry.localPort } else { $null }
        $profile = if ((Test-ToolkitPropertyPresent -InputObject $entry -Name 'profile')) { @($entry.profile) } else { @('Domain', 'Private') }

        $state = Test-ToolkitFirewallRuleState -Name $entry.name -Enabled $enabled -Direction $direction -Protocol $protocol -LocalPort $localPort -Profile $profile
        if ($state.IsCompliant) {
            continue
        }

        Set-ToolkitFirewallRuleState -Name $entry.name -DisplayName $entry.name -Enabled $enabled `
            -Direction $direction -Protocol $protocol -LocalPort $localPort -Profile $profile
        $applied += $entry.name
    }

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Regras de firewall aplicadas: $($applied -join ', ')."
        Evidence       = [pscustomobject]@{ AppliedRules = $applied }
    }
}
