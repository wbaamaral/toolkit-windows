function Test-ToolkitFinalValidationDesiredState {
    <#
    .SYNOPSIS
        Etapa validation.final — reconfirma que todas as etapas anteriores convergiram.

    .DESCRIPTION
        Etapa de avaliacao pura (nunca 'Changed'): reexecuta as funcoes Test das etapas
        de dominio ja implementadas (storage.configure, identity.hostname, computer.locale,
        network.configure, certificates.install, accounts.local, remoteaccess.winrm,
        remoteaccess.rdp, firewall.rules, activation.apply) e falha se alguma delas nao
        estiver 'Compliant' ou 'Skipped'.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Status ('Compliant'|'Failed'), Message, Evidence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $checks = @(
        @{ Name = 'storage.configure'; Result = Test-ToolkitStorageDesiredState -Context $Context },
        @{ Name = 'identity.hostname'; Result = Test-ToolkitHostnameDesiredState -Context $Context },
        @{ Name = 'computer.locale'; Result = Test-ToolkitLocaleDesiredState -Context $Context },
        @{ Name = 'network.configure'; Result = Test-ToolkitNetworkDesiredState -Context $Context },
        @{ Name = 'certificates.install'; Result = Test-ToolkitCertificateDesiredState -Context $Context },
        @{ Name = 'accounts.local'; Result = Test-ToolkitAccountsDesiredState -Context $Context },
        @{ Name = 'remoteaccess.winrm'; Result = Test-ToolkitWinRmDesiredState -Context $Context },
        @{ Name = 'remoteaccess.rdp'; Result = Test-ToolkitRdpDesiredState -Context $Context },
        @{ Name = 'firewall.rules'; Result = Test-ToolkitFirewallRulesDesiredState -Context $Context },
        @{ Name = 'activation.apply'; Result = Test-ToolkitActivationDesiredState -Context $Context }
    )

    $notConverged = @($checks | Where-Object { $_.Result.Status -notin @('Compliant', 'Skipped') })

    $evidence = [pscustomobject]@{
        Checks = @($checks | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Status = $_.Result.Status } })
    }

    if ($notConverged.Count -gt 0) {
        $names = ($notConverged | ForEach-Object { $_.Name }) -join ', '
        return [pscustomobject]@{ Status = 'Failed'; Message = "Etapas ainda nao convergidas: $names."; Evidence = $evidence }
    }

    return [pscustomobject]@{ Status = 'Compliant'; Message = 'Todas as etapas de dominio implementadas convergiram.'; Evidence = $evidence }
}
