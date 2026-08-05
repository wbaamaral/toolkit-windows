function Set-ToolkitHostnameDesiredState {
    <#
    .SYNOPSIS
        Etapa identity.hostname — aplica o nome de computador desejado.

    .DESCRIPTION
        Renomear o computador so tem efeito completo apos reinicializacao; portanto esta
        funcao sempre retorna RebootRequired = $true quando a mudanca e aplicada,
        conforme a tabela de etapas de SPEC-PROVISIONING-STEPS.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $desiredName = [string]$Context.Config.computer.name
    $currentName = $env:COMPUTERNAME

    if (-not $PSCmdlet.ShouldProcess($currentName, "Renomear computador para '$desiredName'")) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    Rename-Computer -NewName $desiredName -Force -ErrorAction Stop

    [pscustomobject]@{
        RebootRequired = $true
        Message        = "Computador renomeado de '$currentName' para '$desiredName'; reinicializacao necessaria para efetivar."
        Evidence       = [pscustomobject]@{ PreviousName = $currentName; NewName = $desiredName }
    }
}
