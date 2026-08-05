function Register-ToolkitProvisioningTask {
    <#
    .SYNOPSIS
        Registra (ou substitui) a tarefa agendada de inicializacao, desabilitada.

    .DESCRIPTION
        SPEC-PROVISIONING-ENGINE: caminho '\WBA\Provisioning\', conta
        NT AUTHORITY\SYSTEM, gatilho de inicializacao, maior privilegio, multiplas
        instancias ignoradas, acao via Windows PowerShell 5.1 com caminho absoluto e
        '-NoProfile -NonInteractive'. A tarefa e criada desabilitada — Enable-ToolkitProvisioning
        e quem a habilita, nunca esta funcao.

    .PARAMETER ScriptPath
        Caminho absoluto de provisioning/Inicializar-Windows.ps1.

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, TaskName, TaskPath, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $taskPath = '\WBA\Provisioning\'
    $taskName = 'Inicializar-Windows'

    if (-not $PSCmdlet.ShouldProcess("$taskPath$taskName", 'Registrar tarefa agendada de provisionamento')) {
        return [pscustomobject]@{ Success = $false; TaskName = $taskName; TaskPath = $taskPath; Message = 'Operacao cancelada (WhatIf).' }
    }

    $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershellExe `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger    = New-ScheduledTaskTrigger -AtStartup
    $principal  = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings   = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $settings.Enabled = $false

    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    [pscustomobject]@{
        Success  = $true
        TaskName = $taskName
        TaskPath = $taskPath
        Message  = "Tarefa registrada em $taskPath$taskName (desabilitada)."
    }
}
