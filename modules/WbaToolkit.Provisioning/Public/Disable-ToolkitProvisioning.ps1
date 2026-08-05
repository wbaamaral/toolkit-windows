function Disable-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Desabilita a tarefa agendada de provisionamento sem removê-la.

    .DESCRIPTION
        Util para suspender temporariamente a execucao no boot (por exemplo, durante
        diagnostico) sem perder o registro da tarefa nem o estado acumulado.

    .EXAMPLE
        Disable-ToolkitProvisioning

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $task = Get-ScheduledTask -TaskName 'Inicializar-Windows' -TaskPath '\WBA\Provisioning\' -ErrorAction SilentlyContinue
    if (-not $task) {
        return [pscustomobject]@{ Success = $true; Message = 'Tarefa nao existe; nada a desabilitar.' }
    }

    if (-not $PSCmdlet.ShouldProcess('\WBA\Provisioning\Inicializar-Windows', 'Desabilitar tarefa agendada de provisionamento')) {
        return [pscustomobject]@{ Success = $false; Message = 'Operacao cancelada (WhatIf).' }
    }

    $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
    [pscustomobject]@{ Success = $true; Message = 'Tarefa desabilitada.' }
}
