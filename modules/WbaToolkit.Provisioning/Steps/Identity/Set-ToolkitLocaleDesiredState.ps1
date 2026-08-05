function Set-ToolkitLocaleDesiredState {
    <#
    .SYNOPSIS
        Etapa computer.locale — aplica o fuso horario desejado.

    .DESCRIPTION
        Set-TimeZone tem efeito imediato no Windows; nao exige reinicializacao. O campo
        MayRequestReboot da etapa no registro permanece $true apenas para refletir a
        tabela de risco de SPEC-PROVISIONING-STEPS, mas esta implementacao nunca pede
        reboot de fato.

    .PARAMETER Context
        Objeto com Config, Paths, DeploymentId e State.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — RebootRequired, Message, Evidence.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $desiredTimeZone = [string]$Context.Config.computer.timeZone
    $current = Get-TimeZone

    if (-not $PSCmdlet.ShouldProcess($current.Id, "Definir fuso horario para '$desiredTimeZone'")) {
        return [pscustomobject]@{ RebootRequired = $false; Message = 'Operacao cancelada (WhatIf).'; Evidence = $null }
    }

    Set-TimeZone -Id $desiredTimeZone -ErrorAction Stop

    [pscustomobject]@{
        RebootRequired = $false
        Message        = "Fuso horario alterado de '$($current.Id)' para '$desiredTimeZone'."
        Evidence       = [pscustomobject]@{ PreviousTimeZoneId = $current.Id; NewTimeZoneId = $desiredTimeZone }
    }
}
