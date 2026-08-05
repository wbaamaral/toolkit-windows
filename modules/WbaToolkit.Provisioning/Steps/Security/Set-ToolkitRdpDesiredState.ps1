function Set-ToolkitRdpDesiredState {
    <#
    .SYNOPSIS
        Etapa remoteaccess.rdp — aplica fDenyTSConnections e as regras de firewall do RDP.

    .DESCRIPTION
        Nunca cria ou remove as regras built-in do RDP — apenas habilita/desabilita e
        ajusta o perfil, preservando a definicao original do Windows. 'fDenyTSConnections'
        sempre preexiste em toda instalacao Windows; Set-ItemProperty atualiza o valor
        sem '-Type' (parametro dinamico do provider Registry, necessario so ao criar
        um valor novo via New-ItemProperty).

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

    $rdpConfig = $Context.Config.remoteAccess.rdp
    $desiredEnabled = [bool]((Test-ToolkitPropertyPresent -InputObject $rdpConfig -Name 'enabled') -and $rdpConfig.enabled)
    $desiredProfile = if ((Test-ToolkitPropertyPresent -InputObject $rdpConfig -Name 'firewallProfile')) { @($rdpConfig.firewallProfile) } else { @('Domain', 'Private') }

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $ruleNames = @('RemoteDesktop-UserMode-In-TCP', 'RemoteDesktop-UserMode-In-UDP')

    if (-not $PSCmdlet.ShouldProcess('RDP (fDenyTSConnections + firewall)', 'Configurar acesso remoto RDP')) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    if ($desiredEnabled) {
        Set-ItemProperty -LiteralPath $regPath -Name 'fDenyTSConnections' -Value 0
        foreach ($ruleName in $ruleNames) {
            if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
                Enable-NetFirewallRule -Name $ruleName
                Set-NetFirewallRule -Name $ruleName -Profile $desiredProfile
            }
        }
        return [pscustomobject]@{ RebootRequired = $false; Message = 'RDP habilitado.'; Evidence = $null }
    }

    Set-ItemProperty -LiteralPath $regPath -Name 'fDenyTSConnections' -Value 1
    foreach ($ruleName in $ruleNames) {
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Disable-NetFirewallRule -Name $ruleName
        }
    }
    [pscustomobject]@{ RebootRequired = $false; Message = 'RDP desabilitado.'; Evidence = $null }
}
