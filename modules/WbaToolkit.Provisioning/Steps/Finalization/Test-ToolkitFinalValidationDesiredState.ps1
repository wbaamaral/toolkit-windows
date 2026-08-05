function Test-ToolkitFinalValidationDesiredState {
    <#
    .SYNOPSIS
        Etapa validation.final — reconfirma que todas as etapas anteriores convergiram.

    .DESCRIPTION
        Etapa de avaliacao pura (nunca 'Changed'): reexecuta as funcoes Test das etapas
        de dominio ja implementadas (identity.hostname, computer.locale, network.configure,
        certificates.install, remoteaccess.winrm, remoteaccess.rdp, firewall.rules) e falha
        se alguma delas nao estiver 'Compliant' ou 'Skipped'. Etapas de fases futuras
        (storage, contas, ativacao) entram nesta soma quando forem implementadas.

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
        @{ Name = 'identity.hostname'; Result = Test-ToolkitHostnameDesiredState -Context $Context },
        @{ Name = 'computer.locale'; Result = Test-ToolkitLocaleDesiredState -Context $Context },
        @{ Name = 'network.configure'; Result = Test-ToolkitNetworkDesiredState -Context $Context },
        @{ Name = 'certificates.install'; Result = Test-ToolkitCertificateDesiredState -Context $Context },
        @{ Name = 'remoteaccess.winrm'; Result = Test-ToolkitWinRmDesiredState -Context $Context },
        @{ Name = 'remoteaccess.rdp'; Result = Test-ToolkitRdpDesiredState -Context $Context },
        @{ Name = 'firewall.rules'; Result = Test-ToolkitFirewallRulesDesiredState -Context $Context }
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
