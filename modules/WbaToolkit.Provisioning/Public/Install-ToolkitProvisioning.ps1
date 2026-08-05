function Install-ToolkitProvisioning {
    <#
    .SYNOPSIS
        Instala a arvore de execucao e registra a tarefa agendada, desabilitada.

    .DESCRIPTION
        Cria %ProgramData%\WBA\Provisioning com ACL restrita a SYSTEM e Administradores
        e registra a tarefa '\WBA\Provisioning\Inicializar-Windows', desabilitada. Nao
        habilita a tarefa nem exige configuracao presente — instalar e habilitar sao
        operacoes distintas (SPEC-PROVISIONING-ENGINE). Idempotente.

    .PARAMETER ScriptPath
        Caminho absoluto de provisioning/Inicializar-Windows.ps1. Quando omitido, assume
        que este modulo esta em <raiz-do-toolkit>/modules/WbaToolkit.Provisioning e resolve
        <raiz-do-toolkit>/provisioning/Inicializar-Windows.ps1.

    .EXAMPLE
        Install-ToolkitProvisioning

    .OUTPUTS
        System.Management.Automation.PSCustomObject — Success, Paths, TaskName, Message.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        # $PSScriptRoot = <raiz>/modules/WbaToolkit.Provisioning/Public — sobe 3 niveis ate <raiz>.
        $toolkitRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $ScriptPath  = Join-Path $toolkitRoot 'provisioning/Inicializar-Windows.ps1'
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Script de inicializacao nao encontrado: $ScriptPath"
    }

    $paths = Get-ToolkitProvisioningPaths
    Initialize-ToolkitProvisioningDirectory -Paths $paths

    $taskResult = Register-ToolkitProvisioningTask -ScriptPath $ScriptPath

    [pscustomobject]@{
        Success  = $taskResult.Success
        Paths    = $paths
        TaskName = "$($taskResult.TaskPath)$($taskResult.TaskName)"
        Message  = $taskResult.Message
    }
}
