function Set-ToolkitWinRmDesiredState {
    <#
    .SYNOPSIS
        Etapa remoteaccess.winrm — aplica ou remove o listener HTTPS e sua regra de firewall.

    .DESCRIPTION
        Exige que o certificado referenciado ja esteja instalado (etapa certificates.install,
        que antecede esta na cadeia de dependencias). Substitui qualquer listener HTTPS
        existente para garantir vinculo com o thumbprint correto — nunca cria listener HTTP
        como alternativa.

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

    $winrmConfig = $Context.Config.remoteAccess.winrm
    $desiredEnabled = [bool]((Test-ToolkitPropertyPresent -InputObject $winrmConfig -Name 'enabled') -and $winrmConfig.enabled)
    $desiredProfile = if ((Test-ToolkitPropertyPresent -InputObject $winrmConfig -Name 'firewallProfile')) { @($winrmConfig.firewallProfile) } else { @('Domain', 'Private') }

    $existingListener = @(Get-WSManInstance -ResourceURI winrm/config/Listener -Enumerate -ErrorAction SilentlyContinue |
            Where-Object { $_.Transport -eq 'HTTPS' }) | Select-Object -First 1

    if (-not $PSCmdlet.ShouldProcess('WinRM HTTPS', 'Configurar listener e regra de firewall')) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    if (-not $desiredEnabled) {
        if ($existingListener) {
            Remove-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{ Address = $existingListener.Address; Transport = 'HTTPS' }
        }
        Set-ToolkitFirewallRuleState -Name 'WBA-WinRM-HTTPS-In' -Enabled $false
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Listener WinRM HTTPS removido.'; Evidence = $null }
    }

    $desiredThumbprint = [string]$winrmConfig.certificateThumbprint
    $cert = Find-ToolkitProvisioningCertificate -Thumbprint $desiredThumbprint -Store 'LocalMachine\My'
    if (-not $cert) {
        throw "Certificado '$desiredThumbprint' referenciado por remoteAccess.winrm nao esta instalado em LocalMachine\My."
    }

    if ($existingListener) {
        Remove-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{ Address = $existingListener.Address; Transport = 'HTTPS' }
    }

    New-WSManInstance -ResourceURI winrm/config/Listener -SelectorSet @{ Address = '*'; Transport = 'HTTPS' } `
        -ValueSet @{ Hostname = $env:COMPUTERNAME; CertificateThumbprint = $desiredThumbprint } | Out-Null

    Set-ToolkitFirewallRuleState -Name 'WBA-WinRM-HTTPS-In' -DisplayName 'WBA WinRM HTTPS (5986)' `
        -Enabled $true -Direction 'Inbound' -Protocol 'TCP' -LocalPort '5986' -Profile $desiredProfile

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Listener WinRM HTTPS configurado com certificado '$desiredThumbprint'."
        Evidence        = [pscustomobject]@{ Thumbprint = $desiredThumbprint }
    }
}
