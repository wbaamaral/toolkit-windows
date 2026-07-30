function Disable-ScheduledTaskByName {
    <#
    .SYNOPSIS
        Desabilita uma tarefa agendada por nome.
    .PARAMETER TaskName
        Nome da tarefa (ou busca parcial).
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    if ($PSCmdlet.ShouldProcess($task.TaskName, 'Desabilitar')) {
        $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
        Write-Output "Tarefa '$($task.TaskName)' desabilitada."
    }
}
