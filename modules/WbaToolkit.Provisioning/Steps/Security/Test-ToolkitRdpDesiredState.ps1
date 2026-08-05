function Test-ToolkitRdpDesiredState {
    <#
    .SYNOPSIS
        Etapa remoteaccess.rdp — verifica fDenyTSConnections e as regras de firewall do RDP.

    .DESCRIPTION
        RDP permanece desabilitado quando a secao nao existe — ausencia de configuracao E
        o estado desejado, nunca 'Skipped'. As regras de firewall built-in do RDP sao
        identificadas por 'Name' (estavel), nunca por 'DisplayGroup' (localizado; em
        Windows PT-BR aparece como 'Area de Trabalho Remota').

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
    $rdpConfig = $null
    if ($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'remoteAccess') -and
        (Test-ToolkitPropertyPresent -InputObject $config.remoteAccess -Name 'rdp')) {
        $rdpConfig = $config.remoteAccess.rdp
    }

    $desiredEnabled = [bool]($rdpConfig -and (Test-ToolkitPropertyPresent -InputObject $rdpConfig -Name 'enabled') -and $rdpConfig.enabled)
    $desiredProfile = if ($rdpConfig -and (Test-ToolkitPropertyPresent -InputObject $rdpConfig -Name 'firewallProfile')) { @($rdpConfig.firewallProfile) } else { @('Domain', 'Private') }

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $denyValue = (Get-ItemProperty -LiteralPath $regPath -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
    $currentEnabled = ($null -ne $denyValue) -and ([int]$denyValue -eq 0)

    $ruleNames = @('RemoteDesktop-UserMode-In-TCP', 'RemoteDesktop-UserMode-In-UDP')
    $rules = @(Get-NetFirewallRule -Name $ruleNames -ErrorAction SilentlyContinue)
    $rulesEnabled = ($rules.Count -gt 0) -and (-not @($rules | Where-Object { $_.Enabled -ne $true }))

    $evidence = [pscustomobject]@{
        DesiredEnabled = $desiredEnabled
        CurrentEnabled = $currentEnabled
        RulesFound     = $rules.Count
        RulesEnabled   = $rulesEnabled
    }

    if (-not $desiredEnabled) {
        $isCompliant = (-not $currentEnabled) -and (-not $rulesEnabled)
        $status = if ($isCompliant) { 'Compliant' } else { 'Changed' }
        return [pscustomobject]@{ Status = $status; Message = 'Avaliacao de RDP desabilitado.'; Evidence = $evidence }
    }

    $isCompliant = $currentEnabled -and $rulesEnabled
    $status = if ($isCompliant) { 'Compliant' } else { 'Changed' }
    return [pscustomobject]@{ Status = $status; Message = 'Avaliacao de RDP habilitado.'; Evidence = $evidence }
}
