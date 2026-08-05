function Test-ToolkitWinRmDesiredState {
    <#
    .SYNOPSIS
        Etapa remoteaccess.winrm — verifica o listener HTTPS e a regra de firewall.

    .DESCRIPTION
        SPEC-PROVISIONING-SECURITY: WinRM permanece desabilitado quando a secao nao
        existe — ausencia de configuracao E o estado desejado (desabilitado), nunca
        'Skipped'. HTTP nao e fallback silencioso: apenas o listener HTTPS conta como
        habilitado. Autenticacao Basic e trafego nao criptografado ficam fora do MVP.

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
    $winrmConfig = $null
    if ($config -and (Test-ToolkitPropertyPresent -InputObject $config -Name 'remoteAccess') -and
        (Test-ToolkitPropertyPresent -InputObject $config.remoteAccess -Name 'winrm')) {
        $winrmConfig = $config.remoteAccess.winrm
    }

    $desiredEnabled = [bool]($winrmConfig -and (Test-ToolkitPropertyPresent -InputObject $winrmConfig -Name 'enabled') -and $winrmConfig.enabled)
    $desiredThumbprint = if ($winrmConfig -and (Test-ToolkitPropertyPresent -InputObject $winrmConfig -Name 'certificateThumbprint')) { [string]$winrmConfig.certificateThumbprint } else { '' }
    $desiredProfile = if ($winrmConfig -and (Test-ToolkitPropertyPresent -InputObject $winrmConfig -Name 'firewallProfile')) { @($winrmConfig.firewallProfile) } else { @('Domain', 'Private') }

    $currentListener = @(Get-WSManInstance -ResourceURI winrm/config/Listener -Enumerate -ErrorAction SilentlyContinue |
            Where-Object { $_.Transport -eq 'HTTPS' }) | Select-Object -First 1

    $firewallState = Test-ToolkitFirewallRuleState -Name 'WBA-WinRM-HTTPS-In' -Enabled $desiredEnabled -Protocol 'TCP' -LocalPort '5986' -Profile $desiredProfile

    $evidence = [pscustomobject]@{
        DesiredEnabled    = $desiredEnabled
        ListenerPresent   = [bool]$currentListener
        CurrentThumbprint = $(if ($currentListener) { $currentListener.CertificateThumbprint } else { $null })
        DesiredThumbprint = $desiredThumbprint
        Firewall          = $firewallState.Details
    }

    if (-not $desiredEnabled) {
        $isCompliant = (-not $currentListener) -and $firewallState.IsCompliant
        if ($isCompliant) {
            return [pscustomobject]@{ Status = 'Compliant'; Message = 'WinRM HTTPS permanece desabilitado.'; Evidence = $evidence }
        }
        return [pscustomobject]@{ Status = 'Changed'; Message = 'WinRM HTTPS precisa ser desabilitado.'; Evidence = $evidence }
    }

    $thumbprintMatches = $currentListener -and ($currentListener.CertificateThumbprint -eq $desiredThumbprint)
    $isCompliant = $thumbprintMatches -and $firewallState.IsCompliant

    if ($isCompliant) {
        return [pscustomobject]@{ Status = 'Compliant'; Message = 'WinRM HTTPS ja configurado conforme desejado.'; Evidence = $evidence }
    }

    return [pscustomobject]@{ Status = 'Changed'; Message = 'WinRM HTTPS precisa ser configurado ou corrigido.'; Evidence = $evidence }
}
