function Unregister-ToolkitProvisioningTask {
    <#
    .SYNOPSIS
        Remove a tarefa agendada de inicializacao, se existir.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $taskPath = '\WBA\Provisioning\'
    $taskName = 'Inicializar-Windows'

    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if (-not $existing) {
        return [pscustomobject]@{ Success = $true; Message = 'Tarefa nao existia; nada a remover.' }
    }

    if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", 'Remover tarefa agendada de provisionamento')) {
        return [pscustomobject]@{ Success = $false; Message = 'Operacao cancelada (WhatIf).' }
    }

    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
    [pscustomobject]@{ Success = $true; Message = "Tarefa removida: $taskPath$taskName." }
}
