function Start-ScheduledTaskByName {
    <#
    .SYNOPSIS
        Executa uma tarefa agendada manualmente.
    .PARAMETER TaskName
        Nome da tarefa (ou busca parcial).
    .PARAMETER TaskPath
        Caminho da pasta (opcional).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [string]$TaskPath
    )

    $task = Resolve-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
    if (-not $task) { throw "Tarefa '$TaskName' nao encontrada." }

    try {
        Start-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
        Write-Output "Tarefa '$($task.TaskName)' iniciada."
    } catch {
        Write-Error "Falha ao iniciar tarefa '$($task.TaskName)': $_"
    }
}
